'use client'

import { useEffect, useState } from 'react'
import { nip19 } from 'nostr-tools'
import {
  getLoginMethod,
  hexToBytes,
  copyToClipboard
} from '@/lib/nostr'
import { hasPrivateKey, storePrivateKey } from '@/lib/secure-key-store'

/**
 * Shared account status card for Home settings.
 * PR #1 only adds the reusable component; MiniAppTab/SettingsModal wiring is PR #2.
 */
export function AccountStatusCard({ pubkey, onLogout }) {
  const loginMethod = getLoginMethod?.()
  const label = loginMethod === 'nosskey' ? 'パスキーでログイン中' : 'ログイン中'
  const shortPubkey = pubkey ? `${pubkey.slice(0, 8)}...${pubkey.slice(-8)}` : ''

  return (
    <section className="bg-[var(--bg-secondary)] rounded-2xl p-4">
      <div className="flex items-center gap-3">
        <div className="w-10 h-10 rounded-full bg-[var(--line-green)] flex items-center justify-center flex-shrink-0">
          <svg className="w-5 h-5 text-white" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
            <path d="M12 2a4 4 0 014 4v2h2a2 2 0 012 2v10a2 2 0 01-2 2H6a2 2 0 01-2-2V10a2 2 0 012-2h2V6a4 4 0 014-4z"/>
            <circle cx="12" cy="15" r="1"/>
          </svg>
        </div>
        <div className="flex-1 min-w-0">
          <p className="font-medium text-[var(--text-primary)] truncate">{label}</p>
          {shortPubkey && <p className="text-xs text-[var(--text-tertiary)] truncate">{shortPubkey}</p>}
        </div>
        <button
          onClick={() => onLogout?.()}
          className="px-3 py-1.5 text-xs bg-red-100 dark:bg-red-900/30 text-red-600 dark:text-red-400 rounded-full"
        >
          ログアウト
        </button>
      </div>
    </section>
  )
}

/**
 * Shared Web Nosskey security settings. Kept behavior-compatible with the
 * existing MiniAppTab NosskeySettings implementation for PR #2 migration.
 */
export function NosskeySecuritySection({ pubkey }) {
  const [showSettings, setShowSettings] = useState(false)
  const [exporting, setExporting] = useState(false)
  const [exportedNsec, setExportedNsec] = useState(null)
  const [copied, setCopied] = useState(false)
  const [autoSign, setAutoSign] = useState(true)
  const [hasExportedKey, setHasExportedKey] = useState(false)

  useEffect(() => {
    if (typeof window !== 'undefined') {
      if (hasPrivateKey()) setHasExportedKey(true)
      const savedAutoSign = localStorage.getItem('nurunuru_auto_sign')
      setAutoSign(savedAutoSign !== 'false')
    }
  }, [])

  const handleAutoSignChange = (enabled) => {
    setAutoSign(enabled)
    localStorage.setItem('nurunuru_auto_sign', enabled ? 'true' : 'false')
  }

  const handleExportKey = async () => {
    if (!window.nosskeyManager) {
      alert('Nosskeyマネージャーが見つかりません。再ログインしてください。')
      return
    }

    setExporting(true)
    try {
      const manager = window.nosskeyManager
      const keyInfo = manager.getCurrentKeyInfo()
      if (!keyInfo) throw new Error('鍵情報が見つかりません')
      manager.setCacheOptions({ enabled: true, timeoutMs: 3600000 })
      const privateKeyHex = await manager.exportNostrKey(keyInfo)
      if (!privateKeyHex) throw new Error('秘密鍵を取得できませんでした')
      const nsec = nip19.nsecEncode(hexToBytes(privateKeyHex))
      setExportedNsec(nsec)
      storePrivateKey(pubkey, privateKeyHex)
      setHasExportedKey(true)
    } catch (e) {
      console.error(e)
      alert('エクスポートに失敗しました: ' + e.message)
    } finally {
      setExporting(false)
    }
  }

  return (
    <section className="bg-[var(--bg-secondary)] rounded-2xl p-4">
      <button onClick={() => setShowSettings(!showSettings)} className="w-full flex items-center justify-between">
        <div className="flex items-center gap-2">
          <svg className="w-5 h-5 text-[var(--text-secondary)]" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
            <path d="M12 2a4 4 0 014 4v2h2a2 2 0 012 2v10a2 2 0 01-2 2H6a2 2 0 01-2-2V10a2 2 0 012-2h2V6a4 4 0 014-4z"/>
            <circle cx="12" cy="15" r="1"/>
          </svg>
          <h2 className="font-semibold text-[var(--text-primary)]">パスキー設定</h2>
        </div>
        <svg className={`w-5 h-5 text-[var(--text-tertiary)] transition-transform ${showSettings ? 'rotate-180' : ''}`} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
          <polyline points="6 9 12 15 18 9"/>
        </svg>
      </button>

      {showSettings && (
        <div className="mt-4 space-y-4">
          <div className="bg-[var(--bg-tertiary)] p-3 rounded-xl">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm font-medium text-[var(--text-primary)]">自動署名</p>
                <p className="text-xs text-[var(--text-tertiary)]">
                  {hasExportedKey ? (autoSign ? '投稿時に生体認証なし' : '毎回生体認証を要求') : '秘密鍵をエクスポートすると有効化'}
                </p>
              </div>
              <button
                onClick={() => handleAutoSignChange(!autoSign)}
                disabled={!hasExportedKey}
                className={`relative w-12 h-6 rounded-full transition-colors ${autoSign && hasExportedKey ? 'bg-[var(--line-green)]' : 'bg-[var(--border-color)]'} ${!hasExportedKey ? 'opacity-50' : ''}`}
              >
                <span className={`absolute top-0.5 left-0.5 w-5 h-5 bg-white rounded-full shadow transition-transform ${autoSign && hasExportedKey ? 'translate-x-6' : 'translate-x-0'}`} />
              </button>
            </div>
          </div>
          <button onClick={handleExportKey} disabled={exporting} className="w-full py-3 text-sm btn-secondary disabled:opacity-50">
            {exporting ? '認証中...' : '秘密鍵を表示'}
          </button>
          {exportedNsec && (
            <div className="space-y-3">
              <div className="bg-red-500/10 border border-red-500/20 p-3 rounded-xl">
                <p className="text-[10px] text-red-500 font-bold mb-1">⚠️ 警告: 秘密鍵の取り扱い</p>
                <p className="text-[10px] text-red-500/80 leading-relaxed">
                  この鍵はあなたの身元を証明する唯一の手段です。他人に教えたり、安全でない場所に保存したりしないでください。
                </p>
              </div>
              <div className="bg-[var(--bg-tertiary)] p-3 rounded-xl flex items-center justify-between gap-2">
                <p className="text-xs text-[var(--text-primary)] break-all font-mono select-all flex-1">{exportedNsec}</p>
                <button
                  onClick={() => {
                    copyToClipboard(exportedNsec)
                    setCopied(true)
                    setTimeout(() => setCopied(false), 2000)
                  }}
                  className="p-2 text-[var(--text-secondary)] hover:text-[var(--line-green)] transition-colors"
                >
                  {copied ? '✓' : 'コピー'}
                </button>
              </div>
            </div>
          )}
        </div>
      )}
    </section>
  )
}
