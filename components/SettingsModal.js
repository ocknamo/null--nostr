'use client'

import { useEffect, useState } from 'react'
import { createPortal } from 'react-dom'

/**
 * App settings sheet opened from the Home header gear button.
 * Mirrors iOS AppSettingsView (MainTabView.swift) — 3 rows:
 *   1. プライバシーポリシー → 外部URL
 *   2. 利用規約             → 外部URL
 *   3. ログアウト           → 確認ダイアログ
 *
 * Intentionally separate from the Mini Apps tab so the gear does not switch tabs.
 */
export default function SettingsModal({ onClose, onLogout }) {
  const [mounted, setMounted] = useState(false)
  const [showLogoutConfirm, setShowLogoutConfirm] = useState(false)

  const PRIVACY_URL = 'https://tami1A84.github.io/null--nostr/privacy.html'
  const TERMS_URL = 'https://tami1A84.github.io/null--nostr/terms.html'
  const GITHUB_URL = 'https://github.com/tami1A84/null--nostr'

  useEffect(() => {
    setMounted(true)
  }, [])

  // Body scroll lock + ESC to close
  useEffect(() => {
    const prevOverflow = document.body.style.overflow
    document.body.style.overflow = 'hidden'
    const onKey = (e) => {
      if (e.key === 'Escape') {
        if (showLogoutConfirm) {
          setShowLogoutConfirm(false)
        } else {
          onClose?.()
        }
      }
    }
    window.addEventListener('keydown', onKey)
    return () => {
      document.body.style.overflow = prevOverflow
      window.removeEventListener('keydown', onKey)
    }
  }, [onClose, showLogoutConfirm])

  if (!mounted) return null

  const openExternal = (url) => {
    try {
      window.open(url, '_blank', 'noopener,noreferrer')
    } catch (_) {
      window.location.href = url
    }
  }

  const handleLogoutConfirm = () => {
    setShowLogoutConfirm(false)
    onClose?.()
    setTimeout(() => onLogout?.(), 0)
  }

  const content = (
    <div className="fixed inset-0 z-[100] bg-[var(--bg-primary)] flex flex-col">
      {/* Header */}
      <header className="sticky top-0 z-10 header-blur border-b border-[var(--border-color)]">
        <div className="flex items-center justify-between px-4 h-12">
          <h1 className="text-lg font-semibold text-[var(--text-primary)]">設定</h1>
          <button
            onClick={() => onClose?.()}
            aria-label="閉じる"
            title="閉じる"
            className="w-9 h-9 flex items-center justify-center text-[var(--text-secondary)] action-btn rounded-full"
          >
            <svg className="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round">
              <line x1="18" y1="6" x2="6" y2="18"/>
              <line x1="6" y1="6" x2="18" y2="18"/>
            </svg>
          </button>
        </div>
      </header>

      {/* Body */}
      <div className="flex-1 overflow-y-auto">
        <div className="max-w-2xl mx-auto p-4 space-y-3">
          <SettingsRow
            icon={
              <svg className="w-5 h-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
                <path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/>
              </svg>
            }
            title="プライバシーポリシー"
            subtitle="個人情報とデータの取り扱いを確認"
            trailing="chevron"
            onClick={() => openExternal(PRIVACY_URL)}
          />

          <SettingsRow
            icon={
              <svg className="w-5 h-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
                <path d="M14 2H6a2 2 0 00-2 2v16a2 2 0 002 2h12a2 2 0 002-2V8z"/>
                <polyline points="14 2 14 8 20 8"/>
                <line x1="8" y1="13" x2="16" y2="13"/>
                <line x1="8" y1="17" x2="16" y2="17"/>
                <line x1="8" y1="9" x2="10" y2="9"/>
              </svg>
            }
            title="利用規約"
            subtitle="禁止事項、通報、ブロックについて確認"
            trailing="chevron"
            onClick={() => openExternal(TERMS_URL)}
          />

          <SettingsRow
            icon={
              <svg className="w-5 h-5" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
                <path d="M12 .5C5.73.5.5 5.73.5 12c0 5.08 3.29 9.39 7.86 10.91.58.11.79-.25.79-.56 0-.27-.01-1.16-.02-2.1-3.2.7-3.88-1.37-3.88-1.37-.52-1.33-1.28-1.69-1.28-1.69-1.05-.71.08-.7.08-.7 1.16.08 1.77 1.19 1.77 1.19 1.03 1.77 2.7 1.26 3.36.96.1-.75.4-1.26.73-1.55-2.55-.29-5.24-1.28-5.24-5.69 0-1.26.45-2.29 1.19-3.1-.12-.29-.52-1.46.11-3.05 0 0 .97-.31 3.18 1.18a11 11 0 0 1 2.9-.39c.98 0 1.97.13 2.9.39 2.2-1.49 3.17-1.18 3.17-1.18.63 1.59.23 2.76.11 3.05.74.81 1.19 1.84 1.19 3.1 0 4.42-2.69 5.39-5.25 5.68.41.36.78 1.06.78 2.14 0 1.55-.01 2.8-.01 3.18 0 .31.21.68.8.56A11.51 11.51 0 0 0 23.5 12C23.5 5.73 18.27.5 12 .5z"/>
              </svg>
            }
            title="アプリケーション情報"
            subtitle="ソースコードをGitHubで確認"
            trailing="chevron"
            onClick={() => openExternal(GITHUB_URL)}
          />

          <SettingsRow
            icon={
              <svg className="w-5 h-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
                <path d="M9 21H5a2 2 0 01-2-2V5a2 2 0 012-2h4"/>
                <polyline points="16 17 21 12 16 7"/>
                <line x1="21" y1="12" x2="9" y2="12"/>
              </svg>
            }
            title="ログアウト"
            subtitle="このデバイスから秘密鍵を削除します"
            titleClass="text-red-500"
            iconClass="text-red-500"
            onClick={() => setShowLogoutConfirm(true)}
          />
        </div>
      </div>

      {/* Logout confirm dialog */}
      {showLogoutConfirm && (
        <div
          className="fixed inset-0 z-[110] bg-black/50 flex items-center justify-center p-4"
          onClick={() => setShowLogoutConfirm(false)}
        >
          <div
            className="bg-[var(--bg-primary)] rounded-2xl w-full max-w-sm p-5 border border-[var(--border-color)] shadow-xl"
            onClick={(e) => e.stopPropagation()}
          >
            <h2 className="text-base font-bold text-[var(--text-primary)] mb-2">ログアウト</h2>
            <p className="text-sm text-[var(--text-secondary)] mb-5">
              ログアウトします。秘密鍵はこのデバイスから削除されます。
            </p>
            <div className="flex flex-col gap-2">
              <button
                onClick={handleLogoutConfirm}
                className="w-full h-11 rounded-xl bg-red-500 text-white font-semibold text-sm hover:bg-red-600 transition-colors"
              >
                ログアウト
              </button>
              <button
                onClick={() => setShowLogoutConfirm(false)}
                className="w-full h-11 rounded-xl bg-[var(--bg-secondary)] text-[var(--text-primary)] font-semibold text-sm hover:opacity-80 transition-opacity"
              >
                キャンセル
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  )

  return createPortal(content, document.body)
}

function SettingsRow({ icon, title, subtitle, titleClass = '', iconClass = '', trailing, onClick }) {
  return (
    <button
      onClick={onClick}
      className="w-full flex items-center gap-3 p-4 rounded-2xl bg-[var(--bg-secondary)] hover:opacity-90 active:opacity-80 transition-opacity text-left"
    >
      <div className={`w-10 h-10 rounded-full bg-[var(--bg-primary)] flex items-center justify-center flex-shrink-0 ${iconClass || 'text-[var(--text-secondary)]'}`}>
        {icon}
      </div>
      <div className="flex-1 min-w-0">
        <div className={`text-sm font-bold ${titleClass || 'text-[var(--text-primary)]'}`}>{title}</div>
        <div className="text-xs text-[var(--text-tertiary)] line-clamp-2 mt-0.5">{subtitle}</div>
      </div>
      {trailing === 'chevron' && (
        <svg className="w-3.5 h-3.5 text-[var(--text-tertiary)] flex-shrink-0" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round">
          <polyline points="9 18 15 12 9 6"/>
        </svg>
      )}
    </button>
  )
}
