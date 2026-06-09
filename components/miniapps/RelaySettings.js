'use client'

import { useState, useEffect } from 'react'
import {
  getDefaultRelay,
  setDefaultRelay,
  canSign,
  publishRelayListMetadata,
  fetchRelayListMetadata,
  isValidRelayUrl,
  getPendingPublishOutbox,
  getPublishOutboxStats,
  retryPendingPublishOutbox
} from '@/lib/nostr'
import {
  autoDetectRelays,
  loadUserGeohash,
  loadUserLocation,
  formatDistance,
  REGION_COORDINATES,
  selectRelaysByRegion,
  loadSelectedRegion,
  findNearestRelays,
  generateRelayListByLocation
} from '@/lib/geohash'
import { getConnectionStats, getRelayHealth } from '@/lib/connection-manager'

// ──────────────────────────────────────────────────────────────
// localStorage keys (mirrors Android AppPreferences)
// ──────────────────────────────────────────────────────────────
const LS_NIP65_RELAYS         = 'nip65Relays'
const LS_MLS_KEYPACKAGE_RELAY = 'mlsKeyPackageRelays'
const LS_MLS_INBOX_RELAY      = 'mlsInboxRelays'

// Defaults match Android SettingsScreen.kt
const DEFAULT_MLS_KEYPACKAGE = [
  'wss://relay.0xchat.com',
  'wss://auth.nostr1.com',
  'wss://relay.damus.io',
  'wss://relay.primal.net',
  'wss://nos.lol',
  'wss://relay.nostr.wirednet.jp',
  'wss://yabu.me',
  'wss://r.kojira.io'
]
const DEFAULT_MLS_INBOX = [
  'wss://relay.0xchat.com',
  'wss://auth.nostr1.com',
  'wss://yabu.me',
  'wss://r.kojira.io'
]

function loadList(key, fallback = []) {
  if (typeof window === 'undefined') return fallback
  try {
    const raw = localStorage.getItem(key)
    if (!raw) return fallback
    const parsed = JSON.parse(raw)
    return Array.isArray(parsed) ? parsed : fallback
  } catch {
    return fallback
  }
}
function saveList(key, value) {
  if (typeof window === 'undefined') return
  try { localStorage.setItem(key, JSON.stringify(value)) } catch {}
}
function canonical(list) {
  return list
    .map(u => (u || '').trim().replace(/\/+$/, ''))
    .filter(u => u.startsWith('wss://') || u.startsWith('ws://'))
    .filter((u, i, arr) => arr.indexOf(u) === i)
    .slice(0, 10)
}

export default function RelaySettings({ pubkey }) {
  const [currentRelay, setCurrentRelay] = useState('wss://yabu.me')
  const [userGeohash, setUserGeohash] = useState(null)
  const [userLocation, setUserLocation] = useState(null)
  const [recommendedRelays, setRecommendedRelays] = useState([])
  const [nearestRelays, setNearestRelays] = useState([])
  const [selectedRegion, setSelectedRegion] = useState(null)
  const [detectingLocation, setDetectingLocation] = useState(false)
  const [publishingNip65, setPublishingNip65] = useState(false)
  const [loadingNip65, setLoadingNip65] = useState(false)
  const [nip65Config, setNip65Config] = useState(null)
  // 保存済みリレー（NIP-65 combined list）
  const [savedRelays, setSavedRelays] = useState([])

  // 高度な設定
  const [advancedExpanded, setAdvancedExpanded] = useState(false)
  const [manualRelayUrl, setManualRelayUrl] = useState('')
  const [newRelayRead, setNewRelayRead] = useState(true)
  const [newRelayWrite, setNewRelayWrite] = useState(true)

  // MLS / WhiteNoise リレー
  const [mlsKeyPackageRelays, setMlsKeyPackageRelays] = useState([])
  const [mlsInboxRelays, setMlsInboxRelays] = useState([])
  const [manualKeyPackageRelayUrl, setManualKeyPackageRelayUrl] = useState('')
  const [manualInboxRelayUrl, setManualInboxRelayUrl] = useState('')

  // Local publish / relay diagnostics
  const [pendingOutbox, setPendingOutbox] = useState([])
  const [outboxStats, setOutboxStats] = useState({ total: 0, pending: 0, failed: 0, published: 0 })
  const [relayDiagnostics, setRelayDiagnostics] = useState([])
  const [diagnosticsLoading, setDiagnosticsLoading] = useState(false)
  const [retryingOutbox, setRetryingOutbox] = useState(false)
  const [retrySummary, setRetrySummary] = useState(null)

  // ──────────────────────────────────────────────────────────────
  // Init
  // ──────────────────────────────────────────────────────────────
  useEffect(() => {
    setCurrentRelay(getDefaultRelay())

    // Load persisted NIP-65 list
    const persisted = loadList(LS_NIP65_RELAYS, [])
    setSavedRelays(persisted)

    // Load MLS lists
    setMlsKeyPackageRelays(loadList(LS_MLS_KEYPACKAGE_RELAY, []))
    setMlsInboxRelays(loadList(LS_MLS_INBOX_RELAY, []))

    const savedGeohash = loadUserGeohash()
    if (savedGeohash) setUserGeohash(savedGeohash)

    const savedRegionId = loadSelectedRegion()
    if (savedRegionId) {
      const result = selectRelaysByRegion(savedRegionId)
      if (result.region) {
        setSelectedRegion(result.region)
        setUserGeohash(result.geohash)
        setUserLocation(result.location)
        setNip65Config(result.nip65Config)
        setNearestRelays(result.nearestRelays || [])
        if (persisted.length === 0 && result.nip65Config?.combined) {
          setSavedRelays(result.nip65Config.combined)
        }
      }
    } else {
      const savedLocation = loadUserLocation()
      if (savedLocation) {
        try {
          const config = generateRelayListByLocation(savedLocation.lat, savedLocation.lon)
          const nearest = findNearestRelays(savedLocation.lat, savedLocation.lon, 10)
          setNip65Config(config)
          setNearestRelays(nearest)
          if (persisted.length === 0 && config?.combined) {
            setSavedRelays(config.combined)
          }
        } catch (e) {
          console.error('Failed to restore GPS relay config:', e)
        }
      }
    }
  }, [])

  // 保存済みリレーの永続化
  useEffect(() => {
    if (savedRelays && savedRelays.length >= 0) {
      saveList(LS_NIP65_RELAYS, savedRelays)
    }
  }, [savedRelays])

  const loadPublishDiagnostics = () => {
    setDiagnosticsLoading(true)
    try {
      const pending = getPendingPublishOutbox(20)
      const stats = getPublishOutboxStats()
      const conn = getConnectionStats()
      const relays = Array.from(new Set([
        ...savedRelays.map(r => typeof r === 'string' ? r : r.url),
        currentRelay,
        ...Object.keys(conn.failedRelays || {})
      ].filter(Boolean)))
      setPendingOutbox(pending)
      setOutboxStats(stats)
      setRelayDiagnostics(relays.map(url => ({ url, ...getRelayHealth(url) })).slice(0, 8))
    } finally {
      setDiagnosticsLoading(false)
    }
  }

  const handleRetryOutbox = async () => {
    setRetryingOutbox(true)
    try {
      const results = await retryPendingPublishOutbox(20)
      const ok = results.filter(r => r.ok).length
      setRetrySummary(`再送: ${ok}/${results.length} 件成功`)
      loadPublishDiagnostics()
    } catch (e) {
      setRetrySummary(`再送に失敗しました: ${e?.message || e}`)
    } finally {
      setRetryingOutbox(false)
    }
  }

  useEffect(() => {
    loadPublishDiagnostics()
    const onOnline = () => { retryPendingPublishOutbox(20).finally(loadPublishDiagnostics) }
    window.addEventListener('online', onOnline)
    return () => window.removeEventListener('online', onOnline)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [savedRelays, currentRelay])

  // ──────────────────────────────────────────────────────────────
  // Handlers
  // ──────────────────────────────────────────────────────────────
  const handleChangeRelay = (relayUrl) => {
    setCurrentRelay(relayUrl)
    setDefaultRelay(relayUrl)
  }

  const handleAutoDetectLocation = async () => {
    setDetectingLocation(true)
    try {
      const result = await autoDetectRelays()
      if (result.geohash) {
        setUserGeohash(result.geohash)
        setUserLocation(result.location)
        setRecommendedRelays(result.relays)
        setNip65Config(result.nip65Config)
        setNearestRelays(result.nearestRelays || [])
        setSelectedRegion(null)

        if (result.nip65Config?.combined?.length > 0) {
          setSavedRelays(result.nip65Config.combined)
        }
        if (result.nip65Config?.outbox?.length > 0) {
          handleChangeRelay(result.nip65Config.outbox[0].url)
        } else if (result.relays.length > 0) {
          handleChangeRelay(result.relays[0].url)
        }
      } else if (result.error) {
        alert(`位置情報の取得に失敗しました: ${result.error}`)
      }
    } catch (e) {
      console.error(e)
      alert('位置情報の取得に失敗しました。')
    } finally {
      setDetectingLocation(false)
    }
  }

  const handleSelectRegion = (regionId) => {
    const result = selectRelaysByRegion(regionId)
    if (result.region) {
      setSelectedRegion(result.region)
      setUserGeohash(result.geohash)
      setUserLocation(result.location)
      setRecommendedRelays(result.relays)
      setNip65Config(result.nip65Config)
      setNearestRelays(result.nearestRelays || [])

      if (result.nip65Config?.combined?.length > 0) {
        setSavedRelays(result.nip65Config.combined)
      }
      if (result.nip65Config?.outbox?.length > 0) {
        handleChangeRelay(result.nip65Config.outbox[0].url)
      }
    }
  }

  // 最寄りリレーをトグル（チェックボックス）— Android と同じ挙動
  const handleToggleNearestRelay = (relay, checked) => {
    setSavedRelays(prev => {
      const next = checked
        ? [{ url: relay.url, read: true, write: true }, ...prev.filter(r => r.url !== relay.url)].slice(0, 5)
        : prev.filter(r => r.url !== relay.url)
      return next
    })
    if (checked) handleChangeRelay(relay.url)
  }

  // 保存済みリレーから削除
  const handleRemoveSavedRelay = (url) => {
    setSavedRelays(prev => prev.filter(r => r.url !== url))
  }

  // read/write トグル
  const handleToggleReadWrite = (url, field, value) => {
    setSavedRelays(prev =>
      prev.map(r => (r.url === url ? { ...r, [field]: value } : r))
    )
  }

  // NIP-65 を発行
  const handlePublishRelayList = async () => {
    if (!pubkey || !canSign()) {
      alert('リレーリストを発行するにはログインが必要です')
      return
    }
    setPublishingNip65(true)
    try {
      let relayList = savedRelays.length > 0
        ? savedRelays
        : (nip65Config?.combined?.length > 0
            ? nip65Config.combined
            : [{ url: currentRelay, read: true, write: true }])
      const result = await publishRelayListMetadata(relayList)
      if (result.success) {
        alert('リレーリストを発行しました (NIP-65)')
      } else {
        alert('リレーリストの発行に失敗しました')
      }
    } catch (e) {
      console.error(e)
      alert(`リレーリストの発行に失敗しました: ${e?.message || e}`)
    } finally {
      setPublishingNip65(false)
    }
  }

  // 自分のリレーリストを読み込む（NIP-65 取得）
  const handleLoadMyRelayList = async () => {
    if (!pubkey) {
      alert('ログインが必要です')
      return
    }
    setLoadingNip65(true)
    try {
      const list = await fetchRelayListMetadata(pubkey)
      if (list && list.all && list.all.length > 0) {
        const next = list.all
          .filter(r => isValidRelayUrl(r.url))
          .slice(0, 10)
          .map(r => ({ url: r.url, read: r.read !== false, write: r.write !== false }))
        setSavedRelays(next)
        alert(`${next.length}件のリレーを読み込みました`)
      } else {
        alert('リレーリストが見つかりませんでした')
      }
    } catch (e) {
      console.error(e)
      alert('リレーリストの読み込みに失敗しました')
    } finally {
      setLoadingNip65(false)
    }
  }

  // 手動でリレー追加（read/write 指定付き）
  const handleAddManualRelay = () => {
    const url = manualRelayUrl.trim().replace(/\/+$/, '')
    if (!isValidRelayUrl(url)) {
      alert('リレーURLは wss:// または ws:// で始まる必要があります')
      return
    }
    if (!newRelayRead && !newRelayWrite) {
      alert('read / write のどちらかを有効にしてください')
      return
    }
    setSavedRelays(prev => {
      const filtered = prev.filter(r => r.url !== url)
      return [{ url, read: newRelayRead, write: newRelayWrite }, ...filtered].slice(0, 10)
    })
    setManualRelayUrl('')
  }

  // ──────────────────────────────────────────────────────────────
  // MLS handlers
  // ──────────────────────────────────────────────────────────────
  const updateMlsKeyPackage = (next) => {
    const c = canonical(next)
    setMlsKeyPackageRelays(c)
    saveList(LS_MLS_KEYPACKAGE_RELAY, c)
  }
  const updateMlsInbox = (next) => {
    const c = canonical(next)
    setMlsInboxRelays(c)
    saveList(LS_MLS_INBOX_RELAY, c)
  }

  const addMlsRelay = (type) => {
    if (type === 'kp') {
      const url = manualKeyPackageRelayUrl.trim().replace(/\/+$/, '')
      if (!isValidRelayUrl(url)) {
        alert('リレーURLは wss:// または ws:// で始まる必要があります')
        return
      }
      updateMlsKeyPackage([url, ...mlsKeyPackageRelays.filter(r => r !== url)])
      setManualKeyPackageRelayUrl('')
    } else {
      const url = manualInboxRelayUrl.trim().replace(/\/+$/, '')
      if (!isValidRelayUrl(url)) {
        alert('リレーURLは wss:// または ws:// で始まる必要があります')
        return
      }
      updateMlsInbox([url, ...mlsInboxRelays.filter(r => r !== url)])
      setManualInboxRelayUrl('')
    }
  }

  // ──────────────────────────────────────────────────────────────
  // Render
  // ──────────────────────────────────────────────────────────────
  return (
    <div className="space-y-4">
      <div className="p-4 bg-[var(--bg-secondary)] rounded-2xl">
        <h3 className="text-lg font-semibold text-[var(--text-primary)] mb-4">リレー設定</h3>

        {/* 現在の設定 */}
        <div className="p-3 bg-[var(--line-green)] bg-opacity-10 rounded-xl border border-[var(--line-green)] mb-4">
          <p className="text-xs text-[var(--text-tertiary)] mb-1">現在の設定</p>
          <p className="text-sm font-medium text-[var(--text-primary)]">
            {selectedRegion ? selectedRegion.name : (userGeohash ? 'GPS検出' : '未設定')}
          </p>
          <p className="text-xs text-[var(--text-tertiary)] mt-1">
            おすすめリレー: {currentRelay.replace('wss://', '')}
          </p>
        </div>

        {/* 地域選択 + GPS */}
        <div className="space-y-4">
          <div>
            <p className="text-sm font-medium text-[var(--text-secondary)] mb-2">地域を選択</p>
            <select
              value={selectedRegion?.id || ''}
              onChange={(e) => e.target.value && handleSelectRegion(e.target.value)}
              className="w-full py-2.5 px-3 bg-[var(--bg-primary)] text-[var(--text-primary)] rounded-lg text-sm border border-[var(--border-color)] focus:border-[var(--line-green)] focus:outline-none"
            >
              <option value="">地域を選択...</option>
              <optgroup label="日本">
                {REGION_COORDINATES.filter(r => r.country === 'JP').map(r => (
                  <option key={r.id} value={r.id}>{r.name}</option>
                ))}
              </optgroup>
              <optgroup label="アジア">
                {REGION_COORDINATES.filter(r => ['SG', 'TW', 'KR', 'CN', 'IN'].includes(r.country)).map(r => (
                  <option key={r.id} value={r.id}>{r.name}</option>
                ))}
              </optgroup>
              <optgroup label="北米">
                {REGION_COORDINATES.filter(r => ['US', 'CA'].includes(r.country)).map(r => (
                  <option key={r.id} value={r.id}>{r.name}</option>
                ))}
              </optgroup>
              <optgroup label="ヨーロッパ">
                {REGION_COORDINATES.filter(r => ['EU', 'UK'].includes(r.country)).map(r => (
                  <option key={r.id} value={r.id}>{r.name}</option>
                ))}
              </optgroup>
            </select>
          </div>

          <button
            onClick={handleAutoDetectLocation}
            disabled={detectingLocation}
            className="w-full py-2 bg-[var(--bg-primary)] hover:bg-[var(--border-color)] text-[var(--text-secondary)] rounded-lg text-xs font-medium transition-colors disabled:opacity-50 flex items-center justify-center gap-2"
          >
            {detectingLocation ? '位置情報を取得中...' : 'GPSで自動検出'}
          </button>

          {/* 最寄りのリレー */}
          {nearestRelays.length > 0 && (
            <div className="pt-3 border-t border-[var(--border-color)]">
              <p className="text-xs text-[var(--text-tertiary)] mb-2">最寄りのリレー</p>
              <div className="space-y-1">
                {nearestRelays.slice(0, 5).map(relay => {
                  const inSaved = savedRelays.some(r => r.url === relay.url)
                  return (
                    <label
                      key={relay.url}
                      className="w-full flex items-center justify-between gap-2 px-3 py-2 rounded-lg text-xs transition-colors bg-[var(--bg-primary)] text-[var(--text-primary)] hover:bg-[var(--border-color)] cursor-pointer"
                    >
                      <div className="flex-1 min-w-0">
                        <p className="truncate">{relay.name}</p>
                        <p className="text-[10px] text-[var(--text-tertiary)] mt-0.5">
                          {relay.region} · {formatDistance(relay.distance)}
                        </p>
                      </div>
                      <input
                        type="checkbox"
                        checked={inSaved}
                        onChange={(e) => handleToggleNearestRelay(relay, e.target.checked)}
                        className="w-4 h-4 accent-[var(--line-green)]"
                      />
                    </label>
                  )
                })}
              </div>
            </div>
          )}

          {/* 保存済みリレー */}
          {savedRelays.length > 0 && (
            <div className="pt-3 border-t border-[var(--border-color)]">
              <p className="text-xs text-[var(--text-tertiary)] mb-2">保存済みリレー</p>
              <div className="space-y-1">
                {savedRelays.map(relay => (
                  <div
                    key={relay.url}
                    className="flex items-center gap-2 px-3 py-2 rounded-lg text-xs bg-[var(--bg-primary)] text-[var(--text-primary)]"
                  >
                    <div className="flex-1 min-w-0">
                      <p className="truncate">{relay.url.replace('wss://', '')}</p>
                      <div className="flex gap-1 mt-1">
                        {relay.read && (
                          <span className="px-1.5 py-0.5 rounded text-[10px] bg-[var(--line-green)] bg-opacity-15 text-[var(--line-green)]">read</span>
                        )}
                        {relay.write && (
                          <span className="px-1.5 py-0.5 rounded text-[10px] bg-purple-500 bg-opacity-15 text-purple-500">write</span>
                        )}
                      </div>
                    </div>
                    <button
                      onClick={() => handleRemoveSavedRelay(relay.url)}
                      className="p-1.5 text-[var(--text-tertiary)] hover:text-red-500 transition-colors"
                      aria-label="削除"
                      title="削除"
                    >
                      <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6M1 7h22M9 7V4a1 1 0 011-1h4a1 1 0 011 1v3" />
                      </svg>
                    </button>
                  </div>
                ))}
              </div>
            </div>
          )}

          {/* NIP-65 発行ボタン */}
          {pubkey && canSign() && (
            <button
              onClick={handlePublishRelayList}
              disabled={publishingNip65}
              className="w-full py-2.5 bg-purple-500 hover:bg-purple-600 text-white rounded-lg text-sm font-medium transition-colors disabled:opacity-50"
            >
              {publishingNip65 ? '発行中...' : 'リレーリストを発行 (NIP-65)'}
            </button>
          )}
        </div>

        <PublishDiagnosticsCard
          pendingOutbox={pendingOutbox}
          outboxStats={outboxStats}
          relayDiagnostics={relayDiagnostics}
          diagnosticsLoading={diagnosticsLoading}
          retryingOutbox={retryingOutbox}
          retrySummary={retrySummary}
          onRefresh={loadPublishDiagnostics}
          onRetry={handleRetryOutbox}
        />

        {/* ── 高度な設定（折りたたみ）──────────────────────── */}
        <div className="mt-4 pt-2 border-t border-[var(--border-color)]">
          <button
            type="button"
            onClick={() => setAdvancedExpanded(v => !v)}
            className="w-full flex items-center justify-between py-2.5 text-left"
          >
            <span className="text-sm font-medium text-[var(--text-secondary)]">高度な設定</span>
            <svg
              className={`w-4 h-4 text-[var(--text-tertiary)] transition-transform ${advancedExpanded ? 'rotate-180' : ''}`}
              fill="none" stroke="currentColor" viewBox="0 0 24 24"
            >
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
            </svg>
          </button>

          {advancedExpanded && (
            <div className="space-y-3 pt-2">
              {/* NIP-65 の説明 */}
              <div className="p-3 bg-[var(--bg-primary)] rounded-xl">
                <p className="text-[13px] font-medium text-[var(--text-primary)]">アウトボックスモデル (NIP-65)</p>
                <p className="text-[11px] text-[var(--text-secondary)] mt-1 leading-relaxed">
                  read: 受信用リレー。他のユーザーがあなた宛のメンションをここに送信します。<br />
                  write: 送信用リレー。あなたの投稿がここに発行されます。
                </p>
              </div>

              {/* MLS / WhiteNoise リレー説明 */}
              <div className="p-3 bg-[var(--bg-primary)] rounded-xl">
                <p className="text-[13px] font-medium text-[var(--text-primary)]">MLS / WhiteNoise リレー</p>
                <p className="text-[11px] text-[var(--text-secondary)] mt-1 leading-relaxed">
                  KeyPackage relays は招待用 KeyPackage (30443/443/10051) を置く場所、Marmot Inbox relays は Welcome/MLS 受信用 (10050) です。トーク画面は Marmot MLS 専用で、NIP-17 メッセージは表示しません。
                </p>
              </div>

              {/* Key Package Relays エディタ */}
              <MlsRelayListEditor
                title="Key Package Relays (kind:10051)"
                relays={mlsKeyPackageRelays}
                manualUrl={manualKeyPackageRelayUrl}
                onManualUrlChange={setManualKeyPackageRelayUrl}
                defaultRelays={DEFAULT_MLS_KEYPACKAGE}
                onRelaysChange={updateMlsKeyPackage}
                onAdd={() => addMlsRelay('kp')}
              />

              {/* Marmot Inbox Relays エディタ */}
              <MlsRelayListEditor
                title="Marmot Inbox Relays (kind:10050)"
                relays={mlsInboxRelays}
                manualUrl={manualInboxRelayUrl}
                onManualUrlChange={setManualInboxRelayUrl}
                defaultRelays={DEFAULT_MLS_INBOX}
                onRelaysChange={updateMlsInbox}
                onAdd={() => addMlsRelay('inbox')}
              />

              {/* 自分のリレーリストを読み込む */}
              <button
                onClick={handleLoadMyRelayList}
                disabled={loadingNip65 || !pubkey}
                className="w-full py-2 bg-[var(--bg-primary)] hover:bg-[var(--border-color)] text-[var(--text-secondary)] rounded-lg text-xs font-medium transition-colors disabled:opacity-50 flex items-center justify-center gap-2"
              >
                {loadingNip65 ? '読み込み中...' : '自分のリレーリストを読み込む'}
              </button>

              {/* リレー詳細設定（read/write スイッチ + 削除） */}
              {savedRelays.length > 0 && (
                <div className="space-y-2">
                  <p className="text-[10px] text-[var(--text-tertiary)]">リレー詳細設定</p>
                  {savedRelays.map(relay => (
                    <div
                      key={`adv-${relay.url}`}
                      className="px-3 py-2 bg-[var(--bg-primary)] rounded-xl"
                    >
                      <p className="text-xs text-[var(--text-primary)] truncate mb-2">
                        {relay.url.replace('wss://', '')}
                      </p>
                      <div className="flex items-center gap-3 flex-wrap">
                        <label className="flex items-center gap-1.5 cursor-pointer">
                          <input
                            type="checkbox"
                            checked={!!relay.read}
                            onChange={(e) => handleToggleReadWrite(relay.url, 'read', e.target.checked)}
                            className="w-4 h-4 accent-[var(--line-green)]"
                          />
                          <span className={`text-xs ${relay.read ? 'text-[var(--text-primary)]' : 'text-[var(--text-tertiary)]'}`}>read</span>
                        </label>
                        <label className="flex items-center gap-1.5 cursor-pointer">
                          <input
                            type="checkbox"
                            checked={!!relay.write}
                            onChange={(e) => handleToggleReadWrite(relay.url, 'write', e.target.checked)}
                            className="w-4 h-4 accent-purple-500"
                          />
                          <span className={`text-xs ${relay.write ? 'text-[var(--text-primary)]' : 'text-[var(--text-tertiary)]'}`}>write</span>
                        </label>
                        <button
                          onClick={() => handleRemoveSavedRelay(relay.url)}
                          className="ml-auto p-1.5 text-[var(--text-tertiary)] hover:text-red-500 transition-colors"
                          aria-label="削除"
                          title="削除"
                        >
                          <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6M1 7h22M9 7V4a1 1 0 011-1h4a1 1 0 011 1v3" />
                          </svg>
                        </button>
                      </div>
                    </div>
                  ))}
                </div>
              )}

              {/* リレーを追加 */}
              <div className="space-y-2">
                <p className="text-[10px] text-[var(--text-tertiary)]">リレーを追加</p>
                <input
                  type="text"
                  value={manualRelayUrl}
                  onChange={(e) => setManualRelayUrl(e.target.value)}
                  placeholder="wss://relay.example.com"
                  className="w-full py-2 px-3 bg-[var(--bg-primary)] text-[var(--text-primary)] rounded-lg text-xs border border-[var(--border-color)] focus:border-[var(--line-green)] focus:outline-none"
                />
                <div className="flex items-center gap-3 flex-wrap">
                  <label className="flex items-center gap-1.5 cursor-pointer">
                    <input
                      type="checkbox"
                      checked={newRelayRead}
                      onChange={(e) => setNewRelayRead(e.target.checked)}
                      className="w-4 h-4 accent-[var(--line-green)]"
                    />
                    <span className="text-xs text-[var(--text-secondary)]">read</span>
                  </label>
                  <label className="flex items-center gap-1.5 cursor-pointer">
                    <input
                      type="checkbox"
                      checked={newRelayWrite}
                      onChange={(e) => setNewRelayWrite(e.target.checked)}
                      className="w-4 h-4 accent-purple-500"
                    />
                    <span className="text-xs text-[var(--text-secondary)]">write</span>
                  </label>
                  <button
                    onClick={handleAddManualRelay}
                    className="ml-auto px-4 py-1.5 bg-[var(--line-green)] hover:opacity-90 text-white rounded-lg text-xs font-medium transition-colors"
                  >
                    追加
                  </button>
                </div>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}


function shortEventId(id = '') {
  return id.length <= 12 ? id : `${id.slice(0, 8)}…${id.slice(-4)}`
}

function PublishDiagnosticsCard({
  pendingOutbox,
  outboxStats,
  relayDiagnostics,
  diagnosticsLoading,
  retryingOutbox,
  retrySummary,
  onRefresh,
  onRetry,
}) {
  return (
    <div className="mt-4 p-3 bg-[var(--bg-primary)] rounded-xl border border-[var(--border-color)] space-y-3">
      <div className="flex items-start gap-3">
        <div className="flex-1 min-w-0">
          <p className="text-[13px] font-medium text-[var(--text-primary)]">送信状態とリレー診断</p>
          <p className="text-[11px] text-[var(--text-tertiary)] mt-0.5">
            署名済み送信待ちと Web リレー状態です。内容は外部送信されません。
          </p>
        </div>
        <button
          type="button"
          onClick={onRefresh}
          disabled={diagnosticsLoading}
          className="px-2 py-1 text-[11px] font-semibold text-[var(--line-green)] hover:opacity-80 disabled:opacity-50"
        >
          {diagnosticsLoading ? '更新中...' : '更新'}
        </button>
      </div>

      <div className="p-3 bg-[var(--bg-secondary)] rounded-xl space-y-2">
        <div className="flex items-center justify-between">
          <span className="text-[11px] text-[var(--text-tertiary)]">送信待ち</span>
          <span className={`text-sm font-bold ${pendingOutbox.length === 0 ? 'text-[var(--line-green)]' : 'text-orange-500'}`}>
            {pendingOutbox.length} 件
          </span>
        </div>
        <p className="text-[10px] text-[var(--text-tertiary)]">
          pending {outboxStats.pending || 0} / failed {outboxStats.failed || 0} / published {outboxStats.published || 0}
        </p>
        {retrySummary && <p className="text-[11px] text-[var(--text-secondary)]">{retrySummary}</p>}
        {pendingOutbox.slice(0, 3).map(item => (
          <div key={item.eventId} className="p-2 bg-[var(--bg-primary)] rounded-lg">
            <div className="flex items-center justify-between gap-2">
              <span className="text-[11px] font-mono text-[var(--text-primary)]">{shortEventId(item.eventId)}</span>
              <span className={`text-[10px] font-semibold ${item.state === 'failed' ? 'text-red-500' : 'text-orange-500'}`}>{item.state}</span>
            </div>
            <p className="text-[10px] text-[var(--text-tertiary)] mt-0.5">
              attempts: {item.attempts || 0} · relays: {item.relayUrls?.length || 0}
            </p>
            {item.lastError && <p className="text-[10px] text-[var(--text-tertiary)] truncate mt-0.5">{item.lastError}</p>}
          </div>
        ))}
        <button
          type="button"
          onClick={onRetry}
          disabled={pendingOutbox.length === 0 || retryingOutbox}
          className="w-full py-2 bg-[var(--line-green)] hover:opacity-90 text-white rounded-lg text-xs font-bold transition-colors disabled:opacity-40"
        >
          {retryingOutbox ? '再送中...' : '送信待ちを再送'}
        </button>
      </div>

      <div className="p-3 bg-[var(--bg-secondary)] rounded-xl space-y-2">
        <div className="flex items-center justify-between">
          <span className="text-[11px] text-[var(--text-tertiary)]">Web relay health</span>
          <span className="text-[10px] text-[var(--text-tertiary)]">{relayDiagnostics.length} relays</span>
        </div>
        {relayDiagnostics.length === 0 ? (
          <p className="text-[11px] text-[var(--text-tertiary)]">投稿・取得後にリレー状態が表示されます。</p>
        ) : relayDiagnostics.slice(0, 5).map(relay => (
          <div key={relay.url} className="flex items-center gap-2 p-2 bg-[var(--bg-primary)] rounded-lg">
            <span className={`w-2 h-2 rounded-full ${relay.status === 'healthy' ? 'bg-[var(--line-green)]' : relay.status === 'cooldown' ? 'bg-orange-500' : 'bg-red-500'}`} />
            <div className="flex-1 min-w-0">
              <p className="text-[11px] text-[var(--text-primary)] truncate">{relay.url.replace('wss://', '')}</p>
              <p className="text-[10px] text-[var(--text-tertiary)]">
                {relay.status} · fail {relay.failures || 0}{relay.cooldownRemaining ? ` · ${Math.ceil(relay.cooldownRemaining / 1000)}s` : ''}
              </p>
            </div>
          </div>
        ))}
      </div>
    </div>
  )
}

// ──────────────────────────────────────────────────────────────
// MLS Relay List Editor (Key Package / Marmot Inbox 共通)
// ──────────────────────────────────────────────────────────────
function MlsRelayListEditor({
  title,
  relays,
  manualUrl,
  onManualUrlChange,
  defaultRelays,
  onRelaysChange,
  onAdd
}) {
  return (
    <div className="space-y-2">
      <div className="flex items-center justify-between">
        <p className="text-[10px] text-[var(--text-tertiary)]">{title}</p>
        <button
          type="button"
          onClick={() => onRelaysChange(defaultRelays)}
          className="text-[11px] font-semibold text-[var(--line-green)] hover:opacity-80"
        >
          標準
        </button>
      </div>

      <div className="space-y-1">
        {relays.length === 0 && (
          <p className="text-[11px] text-[var(--text-tertiary)] italic py-1">未設定</p>
        )}
        {relays.map(relay => (
          <div
            key={relay}
            className="flex items-center gap-2 px-3 py-1.5 bg-[var(--bg-primary)] rounded-xl"
          >
            <span className="inline-block w-2 h-2 rounded-full bg-[var(--line-green)] shrink-0" />
            <span className="flex-1 min-w-0 text-xs text-[var(--text-primary)] truncate">
              {relay.replace('wss://', '')}
            </span>
            <button
              onClick={() => onRelaysChange(relays.filter(r => r !== relay))}
              className="p-1 text-[var(--text-tertiary)] hover:text-red-500 transition-colors"
              aria-label="削除"
              title="削除"
            >
              <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          </div>
        ))}
      </div>

      <div className="flex items-center gap-2">
        <input
          type="text"
          value={manualUrl}
          onChange={(e) => onManualUrlChange(e.target.value)}
          placeholder="wss://relay.example.com"
          className="flex-1 py-1.5 px-3 bg-[var(--bg-primary)] text-[var(--text-primary)] rounded-lg text-xs border border-[var(--border-color)] focus:border-[var(--line-green)] focus:outline-none"
        />
        <button
          onClick={onAdd}
          className="px-3 py-1.5 bg-[var(--line-green)] hover:opacity-90 text-white rounded-lg text-xs font-medium transition-colors"
        >
          追加
        </button>
      </div>
    </div>
  )
}
