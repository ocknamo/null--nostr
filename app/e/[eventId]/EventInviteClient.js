'use client'

import { useEffect, useMemo, useState } from 'react'
import Image from 'next/image'
import { fetchEvents, parseProfile, shortenPubkey } from '@/lib/nostr'

function cleanContent(content) {
  return (content || '').replace(/https?:\/\/\S+\.(?:jpg|jpeg|png|gif|webp|mp4|mov|webm)(\?\S*)?/gi, '').trim()
}

export default function EventInviteClient({ eventId }) {
  const [event, setEvent] = useState(null)
  const [profile, setProfile] = useState(null)
  const appUrl = `nurunuru://event?id=${encodeURIComponent(eventId)}`
  const webUrl = typeof window !== 'undefined' ? window.location.href : `https://www.nullnull.app/e/${eventId}`
  const androidIntent = `intent://event?id=${encodeURIComponent(eventId)}#Intent;scheme=nurunuru;package=io.nurunuru.app;S.browser_fallback_url=${encodeURIComponent(webUrl)};end`
  const content = useMemo(() => cleanContent(event?.content || ''), [event])
  const name = profile?.displayName || profile?.name || (event?.pubkey ? shortenPubkey(event.pubkey) : 'ぬるぬる')

  useEffect(() => {
    if (!eventId) return
    fetchEvents({ ids: [eventId], limit: 1 }).then(events => {
      const ev = events[0]
      if (!ev) return
      setEvent(ev)
      fetchEvents({ kinds: [0], authors: [ev.pubkey], limit: 1 }).then(profileEvents => {
        const latest = profileEvents.sort((a, b) => b.created_at - a.created_at)[0]
        const p = latest ? parseProfile(latest) : null
        if (p) setProfile(p)
      })
    })
  }, [eventId])

  const openApp = () => {
    const ua = navigator.userAgent || ''
    window.location.href = /Android/i.test(ua) ? androidIntent : appUrl
  }

  return (
    <main className="min-h-screen bg-[#0b0b0b] text-white flex items-center justify-center px-6">
      <article className="w-full max-w-xl rounded-3xl bg-[#151515] p-6 shadow-2xl">
        <div className="flex items-center gap-3 mb-5">
          <Image src="/icon-512.png" alt="ぬるぬる" width={44} height={44} className="rounded-xl" />
          <div>
            <p className="text-sm text-[#06C755] font-bold">ぬるぬるの投稿</p>
            <p className="text-xs text-gray-400">Nostr post preview</p>
          </div>
        </div>
        <div className="flex gap-3 mb-4">
          <div className="h-12 w-12 overflow-hidden rounded-full bg-[#242424] flex items-center justify-center shrink-0">
            {profile?.picture ? <img src={profile.picture} alt="" className="h-full w-full object-cover" /> : <span className="text-2xl">👤</span>}
          </div>
          <div className="min-w-0">
            <h1 className="font-bold truncate">{name}</h1>
            <p className="text-xs text-gray-500 truncate">{event?.pubkey ? shortenPubkey(event.pubkey) : 'loading...'}</p>
          </div>
        </div>
        <p className="whitespace-pre-wrap text-[17px] leading-7 text-gray-100 mb-6">
          {event ? (content || 'メディア投稿') : '投稿を読み込み中...'}
        </p>
        <button onClick={openApp} className="block text-center w-full rounded-2xl bg-[#06C755] py-4 font-bold">アプリで開く</button>
      </article>
    </main>
  )
}
