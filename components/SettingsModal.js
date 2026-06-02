'use client'

import { useEffect, useState } from 'react'
import { createPortal } from 'react-dom'
import { nip19 } from 'nostr-tools'
import { getLoginMethod } from '@/lib/nostr'
import { AccountStatusCard, NosskeySecuritySection } from './AccountSecuritySettings'

/**
 * App settings sheet opened from the Home header gear button.
 * Mirrors iOS AppSettingsView — Home-owned account/security settings plus links.
 *
 * Intentionally separate from the Mini Apps tab so the gear does not switch tabs.
 */
export default function SettingsModal({ pubkey, onClose, onLogout }) {
  const [mounted, setMounted] = useState(false)
  const [showLogoutConfirm, setShowLogoutConfirm] = useState(false)
  const [inviteCopied, setInviteCopied] = useState(false)

  const PRIVACY_URL = 'https://tami1A84.github.io/null--nostr/privacy.html'
  const TERMS_URL = 'https://tami1A84.github.io/null--nostr/terms.html'

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

  const handleShareInvite = async () => {
    if (!pubkey) return
    const npub = pubkey.startsWith('npub1') ? pubkey : nip19.npubEncode(pubkey)
    const url = `https://www.nullnull.app/p/${npub}`
    try {
      if (navigator.share) {
        await navigator.share({ title: 'ぬるぬるに招待', text: 'リンクから始めると、わたしをフォローした状態でぬるぬるを始められます。', url })
      } else {
        await navigator.clipboard.writeText(url)
        setInviteCopied(true)
        setTimeout(() => setInviteCopied(false), 2000)
      }
    } catch (e) {
      if (e?.name !== 'AbortError') console.error('Invite share failed:', e)
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
          {pubkey && (
            <AccountStatusCard pubkey={pubkey} onLogout={() => setShowLogoutConfirm(true)} />
          )}

          {pubkey && getLoginMethod() === 'nosskey' && (
            <NosskeySecuritySection pubkey={pubkey} />
          )}

          {pubkey && (
            <SettingsRow
              icon={<svg className="w-5 h-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"><path d="M4 12v7a1 1 0 001 1h14a1 1 0 001-1v-7"/><polyline points="16 6 12 2 8 6"/><line x1="12" y1="2" x2="12" y2="15"/></svg>}
              title="招待"
              subtitle={inviteCopied ? '招待リンクをコピーしました' : '友だちを招待リンクで共有'}
              trailing="chevron"
              onClick={handleShareInvite}
            />
          )}

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
