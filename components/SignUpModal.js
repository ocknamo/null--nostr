'use client'

import { useState, useRef } from 'react'
import { nip19 } from 'nostr-tools'
import {
  savePubkey,
  setStoredPrivateKey,
  publishRelayListMetadata,
  setDefaultRelay,
  hexToBytes,
  bytesToHex,
  uploadImage,
  createEventTemplate,
  signEventNip07,
  publishEvent
} from '@/lib/nostr'
import { autoDetectRelays, formatDistance, REGION_COORDINATES, selectRelaysByRegion, saveSelectedRegion } from '@/lib/geohash'
import { decodeNsec, passkeyErrorMessage } from '@/lib/nosskey'

/**
 * SignUpModal Component
 *
 * Handles new user registration including:
 * 1. Passkey registration via Nosskey
 * 2. Nostr key derivation behind the passkey
 * 3. Regional relay server setup
 * 4. Profile setup and metadata publishing
 */
// チュートリアル投稿で使用する固定ハッシュタグ。
// 本文に書かれた `#xxx` は `t` タグとして抽出して送信する (PostModal.js と同一)。
//
// 既定本文に `\n#nostrはじめました` を pre-fill し、ユーザーが何もしなくても
// エディタ上に常時ハッシュタグが見える状態にする。
// (「付けてもないハッシュタグを勝手につけられた」という不信感を回避するため)
//
// ユーザーが意図的にハッシュタグ行を消した場合は、その状態のまま投稿する
// (自動補完・自動付与は一切しない。3 プラットフォーム共通の規約)。
// 1 行目を空にすることで、ユーザーが先頭にカーソルを置けば
// 「本文 → 改行 → #nostrはじめました」の配置が自然に成立する。
//
// placeholder は本文を全て消した時のガイドとしてのみ機能 (pre-fill 時は非表示)。
const TUTORIAL_HASHTAG = 'nostrはじめました'
const TUTORIAL_DEFAULT_CONTENT = `\n#${TUTORIAL_HASHTAG}`
const TUTORIAL_PLACEHOLDER = `いまどうしてる？\n#${TUTORIAL_HASHTAG}`

export default function SignUpModal({ onClose, onSuccess, nosskeyManager }) {
  const [step, setStep] = useState('welcome') // welcome, import, relay, profile, tutorial, success
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(false)

  // 既存秘密鍵(nsec)インポート用ステート
  const [importNsecInput, setImportNsecInput] = useState('')
  const [importError, setImportError] = useState('')
  const [createdPubkey, setCreatedPubkey] = useState(null)
  const [backupNsec, setBackupNsec] = useState('')
  const [recommendedRelays, setRecommendedRelays] = useState([])
  const [locationInfo, setLocationInfo] = useState(null)
  const [selectionMode, setSelectionMode] = useState('auto') // auto, manual

  // チュートリアル投稿用ステート
  const [tutorialContent, setTutorialContent] = useState(TUTORIAL_DEFAULT_CONTENT)
  const [tutorialPosting, setTutorialPosting] = useState(false)
  const [tutorialPosted, setTutorialPosted] = useState(false)
  const [tutorialError, setTutorialError] = useState('')

  // Profile setup state
  const [profileForm, setProfileForm] = useState({
    name: '',
    about: '',
    picture: '',
    banner: '',
    nip05: '',
    lud16: '',
    website: '',
    birthday: ''
  })
  const [uploadingPicture, setUploadingPicture] = useState(false)
  const [uploadingBanner, setUploadingBanner] = useState(false)
  const pictureInputRef = useRef(null)
  const bannerInputRef = useRef(null)

  // Handle account creation (Passkey step)
  const handleCreateAccount = async () => {
    setLoading(true)
    setError('')
    try {
      if (!nosskeyManager) throw new Error('Passkey manager not initialized')

      // Ensure manager is available globally
      window.nosskeyManager = nosskeyManager

      // 1. Create passkey - This triggers the FIRST biometric prompt
      const cid = await nosskeyManager.createPasskey({
        rp: { name: 'ぬるぬる' },
        user: { name: 'user', displayName: 'Nostr User' }
      })

      if (cid) {
        // 新規登録はパスキー登録のみ。秘密鍵バックアップ画面は表示しない。
        //
        // nosskey-sdk 0.2.0 では createPasskey() が作成時に PRF を先読みキャッシュ
        // するため、直後の createNostrKey(cid) は追加の生体認証なしで鍵情報を返す。
        // exportNostrKey(keyInfo, cid) は自動署名用の秘密鍵取得のために 1 回だけ
        // 認証を行う (UV 回数は従来と同じ 2 回)。
        const keyInfo = await nosskeyManager.createNostrKey(cid)
        const pk = keyInfo?.pubkey
        if (!pk) throw new Error('パスキーから鍵を準備できませんでした')

        setCreatedPubkey(pk)
        nosskeyManager.setCurrentKeyInfo(keyInfo)

        const privateKeyHex = await nosskeyManager.exportNostrKey(keyInfo, cid)
        if (privateKeyHex) {
          setStoredPrivateKey(pk, privateKeyHex)
          setBackupNsec(nip19.nsecEncode(hexToBytes(privateKeyHex)))
        }

        setStep('relay')
        startRelayDetection()
      } else {
        throw new Error('パスキーの作成に失敗しました')
      }
    } catch (e) {
      console.error('Signup error:', e)
      setError(passkeyErrorMessage(e, { cancelled: '登録がキャンセルされました' }))
    } finally {
      setLoading(false)
    }
  }

  // Handle importing an existing Nostr secret key (nsec) behind a passkey.
  // 既存の Nostr 秘密鍵をパスキーで暗号化保護 (wrap モード) してログインする。
  const handleImportKey = async () => {
    setLoading(true)
    setImportError('')
    try {
      if (!nosskeyManager) throw new Error('Passkey manager not initialized')

      // 1. 入力された nsec / hex を検証してバイト列へ
      let seckey
      try {
        seckey = decodeNsec(importNsecInput)
      } catch (validationError) {
        setImportError(validationError.message || '秘密鍵の形式が正しくありません')
        setLoading(false)
        return
      }

      // importNostrKey は渡した seckey バッファを内部で 0 埋めするため、
      // 自動署名用に控える hex は呼び出し前に確保しておく。
      const privateKeyHex = bytesToHex(seckey)

      window.nosskeyManager = nosskeyManager

      // 2. パスキーを作成 (生体認証 1 回目 / PRF 先読みキャッシュ)
      const cid = await nosskeyManager.createPasskey({
        rp: { name: 'ぬるぬる' },
        user: { name: 'user', displayName: 'Nostr User' }
      })
      if (!cid) throw new Error('パスキーの作成に失敗しました')

      // 3. wrap モードでインポート (先読み PRF を消費するため追加認証なし)
      const keyInfo = await nosskeyManager.importNostrKey(seckey, cid)
      const pk = keyInfo?.pubkey
      if (!pk) throw new Error('秘密鍵のインポートに失敗しました')

      setCreatedPubkey(pk)
      nosskeyManager.setCurrentKeyInfo(keyInfo)

      // 4. 自動署名・DM 用に暗号化して端末内保存 (新規登録フローと同じ挙動)
      setStoredPrivateKey(pk, privateKeyHex)
      setBackupNsec(nip19.nsecEncode(hexToBytes(privateKeyHex)))

      // 入力欄はメモリから消す
      setImportNsecInput('')

      // 通常の新規登録と同じウィザードへ合流
      setStep('relay')
      startRelayDetection()
    } catch (e) {
      console.error('Import error:', e)
      setImportError(passkeyErrorMessage(e, { cancelled: '登録がキャンセルされました' }))
    } finally {
      setLoading(false)
    }
  }


  // Handle relay detection
  const startRelayDetection = async () => {
    setLoading(true)
    try {
      const result = await autoDetectRelays()
      if (result.nearestRelays && result.nearestRelays.length > 0) {
        setRecommendedRelays(result.nearestRelays)
        setLocationInfo(result.region || { name: '検出された地域' })

        // Save detected region ID for persistence in Mini App settings
        if (result.region?.id) {
          saveSelectedRegion(result.region.id)
        }

        setSelectionMode('auto')
      } else {
        // Fallback to manual if auto fails
        setSelectionMode('manual')
      }
    } catch (e) {
      console.error('Relay detection failed:', e)
      setSelectionMode('manual')
    } finally {
      setLoading(false)
    }
  }

  // Handle manual region selection
  const handleRegionSelect = (regionId) => {
    if (!regionId) return
    const result = selectRelaysByRegion(regionId)
    if (result.nearestRelays) {
      setRecommendedRelays(result.nearestRelays)
      setLocationInfo(result.region)
    }
  }

  const handlePictureUpload = async (e) => {
    const file = e.target.files?.[0]
    if (!file) return
    setUploadingPicture(true)
    try {
      const url = await uploadImage(file)
      setProfileForm(prev => ({ ...prev, picture: url }))
    } catch (err) {
      console.error('Upload failed:', err)
      alert('アップロードに失敗しました')
    } finally {
      setUploadingPicture(false)
    }
  }

  const handleBannerUpload = async (e) => {
    const file = e.target.files?.[0]
    if (!file) return
    setUploadingBanner(true)
    try {
      const url = await uploadImage(file)
      setProfileForm(prev => ({ ...prev, banner: url }))
    } catch (err) {
      console.error('Upload failed:', err)
      alert('アップロードに失敗しました')
    } finally {
      setUploadingBanner(false)
    }
  }

  // Finish setup and publish relay list + profile
  const handleFinishSetup = async () => {
    setLoading(true)

    // 1. Basic persistence (must happen even if publish fails)
    savePubkey(createdPubkey)
    localStorage.setItem('nurunuru_login_method', 'nosskey')

    if (recommendedRelays.length > 0) {
      // Set the first relay as default for the application immediately
      if (recommendedRelays[0]?.url) {
        setDefaultRelay(recommendedRelays[0].url)
      }

      // Ensure region is saved for Mini App persistence
      if (locationInfo?.id) {
        saveSelectedRegion(locationInfo.id)
      }
    }

    try {
      const targetRelays = recommendedRelays.length > 0
        ? recommendedRelays.map(r => r.url)
        : [setDefaultRelay()]

      // 2. Publish Profile Metadata (kind 0) and Relay List (kind 10002)
      // Both use the cached key from the backup step
      const profileData = {
        name: profileForm.name || 'Anonymous',
        display_name: profileForm.name || 'Anonymous',
        about: profileForm.about,
        picture: profileForm.picture,
        banner: profileForm.banner,
        nip05: profileForm.nip05,
        lud16: profileForm.lud16,
        website: profileForm.website,
        birthday: profileForm.birthday
      }

      const profileEvent = createEventTemplate(0, JSON.stringify(profileData))
      profileEvent.pubkey = createdPubkey

      // Use signEventNip07 which will use the cached private key
      const signedProfile = await signEventNip07(profileEvent)
      if (signedProfile) {
        await publishEvent(signedProfile, targetRelays)
      }

      // 3. Publish NIP-65 relay list
      if (recommendedRelays.length > 0) {
        await publishRelayListMetadata(recommendedRelays.map(r => ({
          url: r.url,
          read: true,
          write: true
        })))
      }

      setStep('tutorial')
    } catch (e) {
      console.error('Setup publication failed, but account is created:', e)
      // プロフィール発行に失敗しても、アカウントは作成済みなのでチュートリアルへ進む。
      setStep('tutorial')
    } finally {
      setLoading(false)
    }
  }

  // チュートリアル投稿: kind:1 を発行する。
  // 既定 pre-fill により本文末尾に `#nostrはじめました` が表示されているため、
  // ユーザーが消さない限り自動的にハッシュタグ付きで送信される。
  // ユーザーがハッシュタグ行を削除した場合は、削除した状態のまま送信する
  // (自動補完・自動末尾付与は行わない。「勝手に付けられた」を回避する規約)。
  const handlePostTutorial = async () => {
    // trim せず原文を送信する (pre-fill 由来の先頭改行を残せる)。
    // ただし完全に空白のみの場合は空投稿扱いで送信ボタンが押せないため、
    // 長さチェック用に trim 後の長さも見ておく。
    const finalContent = tutorialContent

    setTutorialPosting(true)
    setTutorialError('')

    try {
      // 本文から #タグ を抽出して t タグ化 (PostModal.js と同じ正規表現)。
      // ユーザーが #nostrはじめました を消していれば t タグも付与されない (意図尊重)。
      const hashtagRegex = /#([^\s#\u3000]+)/g
      const seen = new Set()
      const tags = []
      let match
      while ((match = hashtagRegex.exec(finalContent)) !== null) {
        const t = match[1].toLowerCase()
        if (!seen.has(t)) {
          seen.add(t)
          tags.push(['t', t])
        }
      }

      if (finalContent.length > 140) {
        throw new Error('140文字以内で入力してください')
      }
      if (finalContent.trim().length === 0) {
        throw new Error('本文を入力してください')
      }

      const targetRelays = recommendedRelays.length > 0
        ? recommendedRelays.map(r => r.url)
        : undefined

      const ev = createEventTemplate(1, finalContent, tags)
      ev.pubkey = createdPubkey
      const signed = await signEventNip07(ev)
      if (!signed) throw new Error('署名に失敗しました')

      const published = await publishEvent(signed, targetRelays)
      if (!published) throw new Error('リレーサーバーへの送信に失敗しました')
      setTutorialPosted(true)
    } catch (e) {
      console.error('Tutorial post failed:', e)
      setTutorialError(e?.message || '投稿に失敗しました')
    } finally {
      setTutorialPosting(false)
    }
  }

  const handleSkipTutorial = () => {
    setStep('success')
  }

  const handleComplete = () => {
    // Check for redirect_uri for app login
    const urlParams = new URLSearchParams(window.location.search)
    const redirectUri = urlParams.get('redirect_uri')

    if (redirectUri && backupNsec) {
      console.log('SignUpModal: Redirecting to app:', redirectUri)
      window.location.href = `${redirectUri}${redirectUri.includes('?') ? '&' : '?'}nsec=${backupNsec}`
      return
    }

    onSuccess(createdPubkey)
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center modal-overlay p-4" onClick={onClose}>
      <div className="w-full max-w-md bg-[var(--bg-primary)] rounded-3xl overflow-hidden shadow-2xl animate-scaleIn" onClick={e => e.stopPropagation()}>

        {/* Progress bar (5 steps: welcome / region / profile / tutorial / success) */}
        <div className="h-1.5 w-full bg-[var(--bg-secondary)] flex">
          <div className={`h-full bg-[var(--line-green)] transition-all duration-500 ${
            step === 'welcome' || step === 'import' ? 'w-1/5' :
            step === 'relay' ? 'w-2/5' :
            step === 'profile' ? 'w-3/5' :
            step === 'tutorial' ? 'w-4/5' : 'w-full'
          }`} />
        </div>

        <div className="p-8">
          {step === 'welcome' && (
            <div className="text-center space-y-6">
              <div className="w-20 h-20 mx-auto bg-green-500/10 rounded-full flex items-center justify-center">
                <svg className="w-10 h-10 text-[var(--line-green)]" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                  <path d="M16 21v-2a4 4 0 00-4-4H5a4 4 0 00-4 4v2" />
                  <circle cx="8.5" cy="7" r="4" />
                  <line x1="20" y1="8" x2="20" y2="14" />
                  <line x1="17" y1="11" x2="23" y2="11" />
                </svg>
              </div>
              <div>
                <h2 className="text-2xl font-bold text-[var(--text-primary)] mb-2">新規登録</h2>
                <p className="text-[var(--text-secondary)] text-sm">
                  パスキーだけで、新しいNostrアカウントを作成します。秘密鍵を保管する必要はありません。
                </p>
              </div>

              {error && (
                <div className="p-3 bg-red-500/10 rounded-xl">
                  <p className="text-red-500 text-xs">{error}</p>
                </div>
              )}

              <button
                onClick={handleCreateAccount}
                disabled={loading}
                className="w-full btn-line py-4 text-lg font-bold disabled:opacity-50"
              >
                {loading ? '登録中...' : 'パスキーで登録'}
              </button>

              <button onClick={onClose} className="text-[var(--text-tertiary)] text-sm hover:underline">
                キャンセル
              </button>

              {/* 既存 Nostr ユーザー向けの控えめな導線 */}
              <div className="pt-2">
                <button
                  onClick={() => { setError(''); setImportError(''); setStep('import') }}
                  disabled={loading}
                  className="text-[var(--text-tertiary)] text-xs hover:text-[var(--line-green)] hover:underline disabled:opacity-50"
                >
                  既存の秘密鍵(nsec)をお持ちの方はこちら
                </button>
              </div>
            </div>
          )}

          {step === 'import' && (
            <div className="text-center space-y-6">
              <div className="w-20 h-20 mx-auto bg-green-500/10 rounded-full flex items-center justify-center">
                <svg className="w-10 h-10 text-[var(--line-green)]" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                  <path d="M15 7h3a5 5 0 015 5 5 5 0 01-5 5h-3m-6 0H6a5 5 0 01-5-5 5 5 0 015-5h3" />
                  <line x1="8" y1="12" x2="16" y2="12" />
                </svg>
              </div>
              <div>
                <h2 className="text-2xl font-bold text-[var(--text-primary)] mb-2">秘密鍵をインポート</h2>
                <p className="text-[var(--text-secondary)] text-sm">
                  お持ちの秘密鍵(nsec)を、この端末のパスキーで暗号化して安全に保存します。
                </p>
              </div>

              <div className="text-left">
                <input
                  type="password"
                  value={importNsecInput}
                  onChange={e => { setImportNsecInput(e.target.value); setImportError('') }}
                  placeholder="nsec1..."
                  autoComplete="off"
                  spellCheck={false}
                  className="w-full px-4 py-3 rounded-xl bg-[var(--bg-secondary)] text-[var(--text-primary)] text-sm outline-none border border-transparent focus:border-[var(--line-green)]"
                />
                <p className="text-[var(--text-tertiary)] text-xs mt-2">
                  秘密鍵はサーバーに送信されず、この端末内にのみ保存されます。
                </p>
              </div>

              {importError && (
                <div className="p-3 bg-red-500/10 rounded-xl">
                  <p className="text-red-500 text-xs">{importError}</p>
                </div>
              )}

              <button
                onClick={handleImportKey}
                disabled={loading || !importNsecInput.trim()}
                className="w-full btn-line py-4 text-lg font-bold disabled:opacity-50"
              >
                {loading ? 'インポート中...' : 'パスキーでインポート'}
              </button>

              <button
                onClick={() => { setImportNsecInput(''); setImportError(''); setStep('welcome') }}
                disabled={loading}
                className="text-[var(--text-tertiary)] text-sm hover:underline disabled:opacity-50"
              >
                戻る
              </button>
            </div>
          )}

          {step === 'relay' && (
            <div className="space-y-5 animate-fadeIn">
              <div className="text-center">
                <div className="w-14 h-14 mx-auto bg-blue-500/10 rounded-full flex items-center justify-center mb-3">
                  <svg className="w-7 h-7 text-blue-500" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                    <path d="M21 10c0 7-9 13-9 13s-9-6-9-13a9 9 0 0118 0z" />
                    <circle cx="12" cy="10" r="3" />
                  </svg>
                </div>
                <h2 className="text-xl font-bold text-[var(--text-primary)] mb-1">地域の設定</h2>
                <p className="text-[var(--text-secondary)] text-xs">
                  地域を選択すると、近くのリレーサーバーを自動セットアップします。
                </p>
              </div>

              <div className="space-y-4">
                <div className="flex p-1 bg-[var(--bg-secondary)] rounded-xl">
                  <button
                    onClick={() => {
                      setSelectionMode('auto')
                      startRelayDetection()
                    }}
                    className={`flex-1 py-2 text-xs font-bold rounded-lg transition-colors ${
                      selectionMode === 'auto' ? 'bg-[var(--bg-primary)] text-[var(--line-green)] shadow-sm' : 'text-[var(--text-tertiary)]'
                    }`}
                  >
                    GPSで自動検出
                  </button>
                  <button
                    onClick={() => setSelectionMode('manual')}
                    className={`flex-1 py-2 text-xs font-bold rounded-lg transition-colors ${
                      selectionMode === 'manual' ? 'bg-[var(--bg-primary)] text-[var(--line-green)] shadow-sm' : 'text-[var(--text-tertiary)]'
                    }`}
                  >
                    手動で地域を選択
                  </button>
                </div>

                {selectionMode === 'manual' && (
                  <div className="animate-fadeIn">
                    <select
                      onChange={(e) => handleRegionSelect(e.target.value)}
                      className="w-full bg-[var(--bg-secondary)] border-none rounded-xl px-4 py-3 text-sm text-[var(--text-primary)] focus:ring-2 focus:ring-[var(--line-green)]"
                      defaultValue=""
                    >
                      <option value="" disabled>地域を選択してください...</option>
                      {REGION_COORDINATES.map(region => (
                        <option key={region.id} value={region.id}>
                          {region.country === 'JP' ? '🇯🇵 ' : ''}{region.name}
                        </option>
                      ))}
                    </select>
                  </div>
                )}

                <div className="bg-[var(--bg-secondary)] rounded-2xl p-4 space-y-3 max-h-40 overflow-y-auto border border-[var(--border-color)]">
                  {loading ? (
                    <div className="py-6 text-center space-y-2">
                      <div className="w-5 h-5 border-2 border-[var(--line-green)] border-t-transparent rounded-full animate-spin mx-auto"></div>
                      <p className="text-[10px] text-[var(--text-tertiary)]">最適なリレーサーバーを検索中...</p>
                    </div>
                  ) : recommendedRelays.length > 0 ? (
                    <>
                      <div className="flex items-center justify-between text-[10px] font-bold text-[var(--text-tertiary)] px-1 border-b border-[var(--border-color)] pb-2 mb-1">
                        <span>推奨リレーサーバー ({locationInfo?.name || '選択済み'})</span>
                        <span>距離</span>
                      </div>
                      {recommendedRelays.map((relay, i) => (
                        <div key={i} className="flex items-center justify-between text-xs">
                          <span className="text-[var(--text-primary)] truncate flex-1">{relay.url.replace('wss://', '')}</span>
                          <span className="text-[var(--text-tertiary)] text-[10px] ml-2 font-mono">
                            {relay.distance ? formatDistance(relay.distance) : '-'}
                          </span>
                        </div>
                      ))}
                    </>
                  ) : (
                    <div className="py-6 text-center">
                      <p className="text-xs text-[var(--text-tertiary)]">地域を選択してください</p>
                    </div>
                  )}
                </div>
              </div>

              <button
                onClick={() => setStep('profile')}
                disabled={recommendedRelays.length === 0}
                className="w-full btn-line py-4 text-lg font-bold disabled:opacity-50"
              >
                次へ進む
              </button>
            </div>
          )}

          {step === 'profile' && (
            <div className="space-y-5 animate-fadeIn">
              <div className="text-center">
                <div className="w-14 h-14 mx-auto bg-green-500/10 rounded-full flex items-center justify-center mb-3">
                  <svg className="w-7 h-7 text-[var(--line-green)]" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                    <path d="M20 21v-2a4 4 0 00-4-4H8a4 4 0 00-4 4v2" />
                    <circle cx="12" cy="7" r="4" />
                  </svg>
                </div>
                <h2 className="text-xl font-bold text-[var(--text-primary)] mb-1">プロフィールの設定</h2>
                <p className="text-[var(--text-secondary)] text-xs">
                  あなたの情報を入力して、世界に公開しましょう。
                </p>
              </div>

              <div className="space-y-4 max-h-[50vh] overflow-y-auto px-1">
                <div>
                  <label className="block text-xs font-bold text-[var(--text-tertiary)] mb-1 uppercase">名前</label>
                  <input
                    type="text"
                    value={profileForm.name}
                    onChange={(e) => setProfileForm({...profileForm, name: e.target.value})}
                    className="w-full bg-[var(--bg-secondary)] border-none rounded-xl px-4 py-3 text-sm text-[var(--text-primary)] focus:ring-2 focus:ring-[var(--line-green)]"
                    placeholder="表示名"
                  />
                </div>

                <div>
                  <label className="block text-xs font-bold text-[var(--text-tertiary)] mb-1 uppercase">アイコン画像</label>
                  <div className="flex gap-2">
                    <input
                      type="url"
                      value={profileForm.picture}
                      onChange={(e) => setProfileForm({...profileForm, picture: e.target.value})}
                      className="flex-1 bg-[var(--bg-secondary)] border-none rounded-xl px-4 py-3 text-sm text-[var(--text-primary)] focus:ring-2 focus:ring-[var(--line-green)]"
                      placeholder="https://..."
                    />
                    <input ref={pictureInputRef} type="file" accept="image/*" onChange={handlePictureUpload} className="hidden" />
                    <button type="button" onClick={() => pictureInputRef.current?.click()} disabled={uploadingPicture} className="bg-[var(--bg-secondary)] px-4 rounded-xl flex-shrink-0">
                      {uploadingPicture ? <div className="w-5 h-5 border-2 border-[var(--text-tertiary)] border-t-transparent rounded-full animate-spin" /> :
                      <svg className="w-5 h-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M21 15v4a2 2 0 01-2 2H5a2 2 0 01-2-2v-4"/><polyline points="17 8 12 3 7 8"/><line x1="12" y1="3" x2="12" y2="15"/></svg>}
                    </button>
                  </div>
                </div>

                <div>
                  <label className="block text-xs font-bold text-[var(--text-tertiary)] mb-1 uppercase">自己紹介</label>
                  <textarea
                    value={profileForm.about}
                    onChange={(e) => setProfileForm({...profileForm, about: e.target.value})}
                    className="w-full bg-[var(--bg-secondary)] border-none rounded-xl px-4 py-3 text-sm text-[var(--text-primary)] focus:ring-2 focus:ring-[var(--line-green)] h-20 resize-none"
                    placeholder="自己紹介"
                  />
                </div>

                <details className="group">
                  <summary className="text-xs text-[var(--line-green)] cursor-pointer font-bold mb-2">詳細設定を表示</summary>
                  <div className="space-y-4 pt-2">
                    <div>
                      <label className="block text-xs font-bold text-[var(--text-tertiary)] mb-1 uppercase">バナー画像</label>
                      <div className="flex gap-2">
                        <input
                          type="url"
                          value={profileForm.banner}
                          onChange={(e) => setProfileForm({...profileForm, banner: e.target.value})}
                          className="flex-1 bg-[var(--bg-secondary)] border-none rounded-xl px-4 py-3 text-sm text-[var(--text-primary)] focus:ring-2 focus:ring-[var(--line-green)]"
                          placeholder="https://..."
                        />
                        <input ref={bannerInputRef} type="file" accept="image/*" onChange={handleBannerUpload} className="hidden" />
                        <button type="button" onClick={() => bannerInputRef.current?.click()} disabled={uploadingBanner} className="bg-[var(--bg-secondary)] px-4 rounded-xl flex-shrink-0">
                          {uploadingBanner ? <div className="w-5 h-5 border-2 border-[var(--text-tertiary)] border-t-transparent rounded-full animate-spin" /> :
                          <svg className="w-5 h-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M21 15v4a2 2 0 01-2 2H5a2 2 0 01-2-2v-4"/><polyline points="17 8 12 3 7 8"/><line x1="12" y1="3" x2="12" y2="15"/></svg>}
                        </button>
                      </div>
                    </div>
                    <div>
                      <label className="block text-xs font-bold text-[var(--text-tertiary)] mb-1 uppercase">NIP-05 (認証)</label>
                      <input type="text" value={profileForm.nip05} onChange={(e) => setProfileForm({...profileForm, nip05: e.target.value})} className="w-full bg-[var(--bg-secondary)] border-none rounded-xl px-4 py-3 text-sm text-[var(--text-primary)] focus:ring-2 focus:ring-[var(--line-green)]" placeholder="user@domain.com" />
                    </div>
                    <div>
                      <label className="block text-xs font-bold text-[var(--text-tertiary)] mb-1 uppercase">ライトニングアドレス</label>
                      <input type="text" value={profileForm.lud16} onChange={(e) => setProfileForm({...profileForm, lud16: e.target.value})} className="w-full bg-[var(--bg-secondary)] border-none rounded-xl px-4 py-3 text-sm text-[var(--text-primary)] focus:ring-2 focus:ring-[var(--line-green)]" placeholder="you@wallet.com" />
                    </div>
                    <div>
                      <label className="block text-xs font-bold text-[var(--text-tertiary)] mb-1 uppercase">ウェブサイト</label>
                      <input type="url" value={profileForm.website} onChange={(e) => setProfileForm({...profileForm, website: e.target.value})} className="w-full bg-[var(--bg-secondary)] border-none rounded-xl px-4 py-3 text-sm text-[var(--text-primary)] focus:ring-2 focus:ring-[var(--line-green)]" placeholder="https://..." />
                    </div>
                    <div>
                      <label className="block text-xs font-bold text-[var(--text-tertiary)] mb-1 uppercase">誕生日</label>
                      <input type="text" value={profileForm.birthday} onChange={(e) => setProfileForm({...profileForm, birthday: e.target.value})} className="w-full bg-[var(--bg-secondary)] border-none rounded-xl px-4 py-3 text-sm text-[var(--text-primary)] focus:ring-2 focus:ring-[var(--line-green)]" placeholder="MM-DD" />
                    </div>
                  </div>
                </details>
              </div>

              <button
                onClick={handleFinishSetup}
                disabled={loading}
                className="w-full btn-line py-4 text-lg font-bold disabled:opacity-50"
              >
                {loading ? '保存中...' : 'セットアップを完了する'}
              </button>
            </div>
          )}

          {step === 'tutorial' && (
            <div className="space-y-5 animate-fadeIn">
              <div className="text-center">
                {/* ぬるぬるブランドカラー (LineGreen) に統一。chat-bubble アイコン。 */}
                <div className="w-14 h-14 mx-auto rounded-full flex items-center justify-center mb-3" style={{ backgroundColor: 'rgba(6, 199, 85, 0.1)' }}>
                  <svg className="w-7 h-7" style={{ color: 'var(--line-green)' }} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                    <path d="M21 11.5a8.38 8.38 0 01-.9 3.8 8.5 8.5 0 01-7.6 4.7 8.38 8.38 0 01-3.8-.9L3 21l1.9-5.7a8.38 8.38 0 01-.9-3.8 8.5 8.5 0 014.7-7.6 8.38 8.38 0 013.8-.9h.5a8.48 8.48 0 018 8v.5z" />
                  </svg>
                </div>
                <h2 className="text-xl font-bold text-[var(--text-primary)] mb-1">はじめての投稿</h2>
                <p className="text-[var(--text-secondary)] text-xs">
                  まずは、ひとことあいさつしてみましょう。何を書けばいいか迷ったら、例文を使えます。
                </p>
              </div>

              {tutorialPosted ? (
                <div className="space-y-4">
                  <div className="p-4 bg-green-500/10 rounded-2xl flex items-start gap-3 border border-green-500/20">
                    <svg className="w-5 h-5 text-[var(--line-green)] flex-shrink-0 mt-0.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                      <polyline points="20 6 9 17 4 12" />
                    </svg>
                    <div>
                      <p className="text-sm font-bold text-[var(--text-primary)]">投稿しました！</p>
                      <p className="text-xs text-[var(--text-secondary)] mt-1">
                        Nostr の世界へようこそ。タイムラインで「#nostrはじめました」を検索すると、同じ仲間が見つかります。
                      </p>
                    </div>
                  </div>
                  <button
                    onClick={() => setStep('success')}
                    className="w-full btn-line py-4 text-lg font-bold"
                  >
                    次へ進む
                  </button>
                </div>
              ) : (
                <div className="space-y-4">
                  <button
                    type="button"
                    onClick={() => setTutorialContent('はじめまして。ぬるぬるを始めました。よろしくね。\n#' + TUTORIAL_HASHTAG)}
                    className="inline-flex items-center gap-2 rounded-full bg-[var(--bg-secondary)] px-3 py-2 text-xs font-bold text-[var(--line-green)]"
                  >
                    例文を使う
                  </button>

                  <div>
                    {/*
                      `#nostrはじめました` は既定で pre-fill されているため、エディタを開いた瞬間から
                      ユーザーには常時ハッシュタグが見えている (「勝手に付けられた」を回避する規約)。
                      ユーザーが消したら消した状態のまま投稿される (自動補完なし)。
                      プレースホルダーは本文を全て消した時のガイドとしてのみ表示される。
                    */}
                    <textarea
                      value={tutorialContent}
                      onChange={(e) => setTutorialContent(e.target.value)}
                      maxLength={140}
                      placeholder={TUTORIAL_PLACEHOLDER}
                      className="w-full bg-[var(--bg-secondary)] border-none rounded-xl px-4 py-3 text-sm text-[var(--text-primary)] placeholder:text-[var(--text-tertiary)] placeholder:opacity-70 focus:ring-2 focus:ring-[var(--line-green)] h-28 resize-none whitespace-pre-wrap"
                    />
                    <div className="flex justify-end mt-1">
                      <span className={`text-[10px] ${tutorialContent.length > 140 ? 'text-red-500' : 'text-[var(--text-tertiary)]'}`}>
                        {tutorialContent.length}/140
                      </span>
                    </div>
                  </div>

                  {tutorialError && (
                    <div className="p-3 bg-red-500/10 rounded-xl">
                      <p className="text-red-500 text-xs">{tutorialError}</p>
                    </div>
                  )}

                  <button
                    onClick={handlePostTutorial}
                    disabled={tutorialPosting || tutorialContent.length > 140 || tutorialContent.trim().length === 0}
                    className="w-full btn-line py-4 text-lg font-bold disabled:opacity-50"
                  >
                    {tutorialPosting ? '投稿中...' : '投稿する'}
                  </button>

                  <button
                    onClick={handleSkipTutorial}
                    disabled={tutorialPosting}
                    className="w-full text-[var(--text-tertiary)] text-sm hover:underline disabled:opacity-50"
                  >
                    スキップ
                  </button>
                </div>
              )}
            </div>
          )}

          {step === 'success' && (
            <div className="text-center space-y-6 animate-fadeIn">
              <div className="w-20 h-20 mx-auto bg-green-500 rounded-full flex items-center justify-center shadow-lg shadow-green-500/20">
                <svg className="w-12 h-12 text-white" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3">
                  <polyline points="20 6 9 17 4 12" />
                </svg>
              </div>
              <div>
                <h2 className="text-2xl font-bold text-[var(--text-primary)] mb-2">準備完了！</h2>
                <p className="text-[var(--text-secondary)] text-sm">
                  アカウントが作成されました。ぬるぬるの世界へようこそ！
                </p>
              </div>

              <div className="bg-[var(--bg-secondary)] rounded-2xl p-4 text-left">
                <p className="text-[var(--text-tertiary)] text-xs mb-1">あなたの公開鍵 (npub)</p>
                <p className="text-[var(--text-primary)] text-xs font-mono break-all line-clamp-2">
                  {createdPubkey ? nip19.npubEncode(createdPubkey) : ''}
                </p>
              </div>

              <button
                onClick={handleComplete}
                className="w-full btn-line py-4 text-lg font-bold"
              >
                はじめる
              </button>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}
