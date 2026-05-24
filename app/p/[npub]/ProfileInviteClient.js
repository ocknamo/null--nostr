'use client'

import { useEffect, useMemo, useState } from 'react'
import Image from 'next/image'
import { nip19, fetchEvents, parseProfile, shortenPubkey } from '@/lib/nostr'

const PLAY_STORE_URL = 'https://play.google.com/store/apps/details?id=io.nurunuru.app'
const APP_STORE_URL = null

function parsePubkey(value) {
  try {
    if (!value) return null
    if (value.startsWith('npub1')) return nip19.decode(value).data
    if (/^[0-9a-fA-F]{64}$/.test(value)) return value.toLowerCase()
  } catch (_) {}
  return null
}

export default function ProfileInviteClient({ npubOrHex }) {
  const pubkey = useMemo(() => parsePubkey(npubOrHex), [npubOrHex])
  const npub = useMemo(() => {
    if (!pubkey) return npubOrHex
    try { return nip19.npubEncode(pubkey) } catch (_) { return npubOrHex }
  }, [pubkey, npubOrHex])
  const [profile, setProfile] = useState(null)
  const [opened, setOpened] = useState(false)

  const webUrl = typeof window !== 'undefined' ? window.location.href : `https://www.nullnull.app/p/${npub}`
  const appUrl = `nurunuru://profile?npub=${encodeURIComponent(npub)}`
  const androidIntent = `intent://profile?npub=${encodeURIComponent(npub)}#Intent;scheme=io.nurunuru.app;package=io.nurunuru.app;S.browser_fallback_url=${encodeURIComponent(webUrl)};end`

  useEffect(() => {
    if (!pubkey) return
    try {
      localStorage.setItem('nurunuru_pending_referral_pubkey', pubkey)
      localStorage.setItem('nurunuru_pending_referral_npub', npub)
      localStorage.setItem('nurunuru_pending_referral_saved_at', String(Date.now()))
    } catch (_) {}
    fetchEvents({ kinds: [0], authors: [pubkey], limit: 1 }).then(events => {
      const latest = events.sort((a, b) => b.created_at - a.created_at)[0]
      const p = latest ? parseProfile(latest) : null
      if (p) setProfile(p)
    })
  }, [pubkey, npub])

  const openApp = () => {
    setOpened(true)
    const ua = navigator.userAgent || ''
    window.location.href = /Android/i.test(ua) ? androidIntent : appUrl
  }

  const name = profile?.displayName || profile?.name || (pubkey ? shortenPubkey(pubkey) : 'プロフィール')

  return (
    <main className="min-h-screen bg-[#0b0b0b] text-white flex items-center justify-center px-6">
      <section className="w-full max-w-md rounded-3xl bg-[#151515] p-6 text-center shadow-2xl">
        <Image src="/icon-512.png" alt="ぬるぬる" width={72} height={72} className="mx-auto rounded-2xl mb-5" />
        <p className="text-sm text-[#06C755] font-bold mb-2">ぬるぬるに招待されています</p>
        <div className="mx-auto mb-4 h-24 w-24 overflow-hidden rounded-full bg-[#242424] flex items-center justify-center">
          {profile?.picture ? <img src={profile.picture} alt="" className="h-full w-full object-cover" /> : <span className="text-4xl">👤</span>}
        </div>
        <h1 className="text-2xl font-bold mb-2">{name}</h1>
        {profile?.about && <p className="text-sm text-gray-300 line-clamp-3 mb-5">{profile.about}</p>}
        <p className="text-sm text-gray-400 mb-6">アプリを開いて始めると、このユーザーをフォローした状態でスタートします。</p>
        <button onClick={openApp} className="w-full h-14 rounded-2xl bg-[#06C755] text-white font-bold mb-3">アプリで開く</button>
        {opened && <p className="text-xs text-gray-400 mb-3">アプリが開かない場合は、インストール後にこのページへ戻って「アプリで開く」を押してください。</p>}
        <div className="grid grid-cols-2 gap-3">
          {APP_STORE_URL ? (
            <a className="rounded-xl bg-[#242424] py-3 text-sm" href={APP_STORE_URL}>App Store</a>
          ) : (
            <span className="rounded-xl bg-[#242424] py-3 text-sm text-gray-500">App Store 準備中</span>
          )}
          <a className="rounded-xl bg-[#242424] py-3 text-sm" href={PLAY_STORE_URL}>Google Play</a>
        </div>
      </section>
    </main>
  )
}
