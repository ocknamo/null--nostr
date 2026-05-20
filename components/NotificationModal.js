'use client'

import { useState, useEffect, useRef } from 'react'
import { createPortal } from 'react-dom'
import {
  fetchEventsManaged,
  parseProfile,
  parseZap,
  fetchMutualFollowsCached,
  fetchProfilesBatch,
  shortenPubkey,
  formatTimestamp,
  RELAYS,
  getDefaultRelay,
  getNotificationRelays
} from '@/lib/nostr'
import { getImageUrl } from '@/lib/imageUtils'
import { NOSTR_KINDS } from '@/lib/constants'

export default function NotificationModal({ pubkey, onClose, onViewProfile, onPostClick }) {
  const [notifications, setNotifications] = useState([])
  const [profiles, setProfiles] = useState({})
  const [originalPosts, setOriginalPosts] = useState({})
  const [loading, setLoading] = useState(true)
  const [mounted, setMounted] = useState(false)
  const modalRef = useRef(null)

  useEffect(() => {
    setMounted(true)
    return () => setMounted(false)
  }, [])

  useEffect(() => {
    if (pubkey && mounted) {
      loadNotifications()
    }

    const handleClickOutside = (e) => {
      if (modalRef.current && !modalRef.current.contains(e.target)) {
        onClose()
      }
    }

    if (window.innerWidth >= 1024) {
      document.addEventListener('mousedown', handleClickOutside)
      return () => document.removeEventListener('mousedown', handleClickOutside)
    }
  }, [pubkey, mounted])

  const loadNotifications = async () => {
    setLoading(true)
    try {
      // アプリ版 (Android NostrRepositoryNotifications.fetchNotifications) と同様、
      // 接続中の inbox/read リレー (NIP-65 read=true) からまとめて取得する。
      const notifRelays = await getNotificationRelays(pubkey)
      const relays = (notifRelays && notifRelays.length > 0) ? notifRelays : [getDefaultRelay()]

      // Android 版と同じく直近 24h 分の通知を 6 種類 (リアクション / Zap / リポスト /
      // 返信メンション / バッジ / フォロー) すべて並列に取得する。
      // 全 read relay に対し fetchEventsManaged を直接使う (fetchEvents は先頭しか使わない)。
      const oneDayAgo = Math.floor(Date.now() / 1000) - 24 * 60 * 60
      const baseFilter = (kind) => ({
        kinds: [kind],
        '#p': [pubkey],
        since: oneDayAgo,
        limit: 100
      })

      const [
        reactionEvents,
        zapEvents,
        repostEvents,
        mentionEvents,
        badgeEvents,
        followEvents,
        mutualFollowPubkeys
      ] = await Promise.all([
        fetchEventsManaged(baseFilter(NOSTR_KINDS.REACTION), relays),
        fetchEventsManaged(baseFilter(NOSTR_KINDS.ZAP), relays),
        fetchEventsManaged(baseFilter(NOSTR_KINDS.REPOST), relays),
        fetchEventsManaged(baseFilter(NOSTR_KINDS.TEXT_NOTE), relays),
        fetchEventsManaged(baseFilter(NOSTR_KINDS.BADGE_AWARD), relays),
        // フォロー通知用 Kind 3 (contact list 全置換イベント)
        fetchEventsManaged(baseFilter(NOSTR_KINDS.CONTACTS), relays),
        // 誕生日通知用の相互フォロー
        fetchMutualFollowsCached(pubkey, relays)
      ])

      // --- リアクション (通常 + カスタム絵文字) ------------------------------
      const reactionItems = []
      for (const e of reactionEvents) {
        if (e.pubkey === pubkey) continue
        const emojiTag = e.tags.find(t => t[0] === 'emoji')
        const emojiUrl = emojiTag?.[2] || null
        const content = (e.content || '').trim() || '+'
        const isEmoji = !!emojiUrl ||
          (content.startsWith(':') && content.endsWith(':') && content.length > 2)
        reactionItems.push({
          ...e,
          type: isEmoji ? 'emoji_reaction' : 'reaction',
          reactionEmoji: content,
          emojiUrl
        })
      }

      // --- Zap --------------------------------------------------------------
      // parseZap は sender を description 内 pubkey から復元してくれる
      const parsedZaps = zapEvents
        .map(parseZap)
        .filter(z => z && z.pubkey && z.pubkey !== pubkey)
        .map(z => ({ ...z, type: 'zap' }))

      // --- リポスト (Kind 6) ------------------------------------------------
      const repostItems = repostEvents
        .filter(e => e.pubkey !== pubkey)
        .map(e => ({ ...e, type: 'repost' }))

      // --- 返信 / メンション (Kind 1) ---------------------------------------
      // e タグがあれば「返信」、なければ「メンション」(Android と同じ分類)
      const mentionItems = mentionEvents
        .filter(e => e.pubkey !== pubkey)
        .map(e => {
          const eTag = e.tags.find(t => t[0] === 'e')
          return {
            ...e,
            type: eTag ? 'reply' : 'mention'
          }
        })

      // --- バッジ授与 (Kind 8) ---------------------------------------------
      const badgeItems = badgeEvents
        .filter(e => e.pubkey !== pubkey)
        .map(e => {
          const aTag = e.tags.find(t => t[0] === 'a' && (t[1] || '').startsWith('30009:'))
          const badgeName = aTag?.[1]?.split(':')?.slice(2).join(':') || ''
          return { ...e, type: 'badge', badgeName }
        })

      // --- 新規フォロー (Kind 3) -------------------------------------------
      // Kind 3 は contact list 全置換なので、既存フォロワーの更新を「新規フォロー」
      // と誤検知しないよう localStorage に最終確認時刻 + 既知フォロワーを保存する。
      const followItems = []
      try {
        const lsHighWaterKey = 'notif_follow_high_water'
        const lsKnownKey = 'notif_follow_known'
        const previousHighWater = parseInt(localStorage.getItem(lsHighWaterKey) || '0', 10)
        const knownRaw = localStorage.getItem(lsKnownKey)
        const knownFollowers = new Set(knownRaw ? JSON.parse(knownRaw) : [])

        const candidates = followEvents
          .filter(e => e.pubkey !== pubkey)
          .filter(e => e.tags.some(t => t[0] === 'p' && t[1] === pubkey))
          .sort((a, b) => a.created_at - b.created_at)

        if (candidates.length > 0) {
          const maxSeenAt = Math.max(previousHighWater, ...candidates.map(c => c.created_at))

          if (previousHighWater === 0 || knownFollowers.size === 0) {
            // 初回: 既存をベースライン化、通知は出さない
            candidates.forEach(c => knownFollowers.add(c.pubkey))
          } else {
            const emitted = new Set()
            for (const ev of candidates) {
              const isNew = ev.created_at > previousHighWater
              const wasKnown = knownFollowers.has(ev.pubkey)
              if (isNew && !wasKnown && !emitted.has(ev.pubkey)) {
                emitted.add(ev.pubkey)
                followItems.push({ ...ev, type: 'follow' })
              }
              knownFollowers.add(ev.pubkey)
            }
          }
          localStorage.setItem(lsHighWaterKey, String(maxSeenAt))
          localStorage.setItem(lsKnownKey, JSON.stringify(Array.from(knownFollowers)))
        }
      } catch (err) {
        console.warn('[NotificationModal] follow notif state failed:', err?.message || err)
      }

      // --- 元投稿 / プロフィールの一括取得 ----------------------------------
      const originalEventIds = Array.from(new Set([
        ...reactionItems.map(e => e.tags.find(t => t[0] === 'e')?.[1]).filter(Boolean),
        ...parsedZaps.map(z => z.targetEventId).filter(Boolean),
        ...repostItems.map(e => e.tags.find(t => t[0] === 'e')?.[1]).filter(Boolean),
        ...mentionItems.filter(m => m.type === 'reply')
          .map(e => e.tags.find(t => t[0] === 'e')?.[1]).filter(Boolean)
      ]))

      const notifierPubkeys = Array.from(new Set([
        ...reactionItems.map(e => e.pubkey),
        ...parsedZaps.map(z => z.pubkey),
        ...repostItems.map(e => e.pubkey),
        ...mentionItems.map(e => e.pubkey),
        ...badgeItems.map(e => e.pubkey),
        ...followItems.map(e => e.pubkey),
        ...mutualFollowPubkeys
      ]))

      const [postEvents, profileMap] = await Promise.all([
        originalEventIds.length > 0
          ? fetchEventsManaged({ ids: originalEventIds.slice(0, 200) }, relays)
          : Promise.resolve([]),
        fetchProfilesBatch(notifierPubkeys)
      ])

      const postMap = {}
      postEvents.forEach(e => { postMap[e.id] = e })

      // --- 誕生日通知 -------------------------------------------------------
      const birthdayNotifications = []
      const today = new Date()
      const todayMonthDay = `${String(today.getMonth() + 1).padStart(2, '0')}-${String(today.getDate()).padStart(2, '0')}`

      mutualFollowPubkeys.forEach(pk => {
        const profile = profileMap[pk]
        if (profile?.birthday) {
          let bMonthDay = null
          if (typeof profile.birthday === 'string') {
            const bMatch = profile.birthday.match(/(\d{2})-(\d{2})$/)
            if (bMatch) bMonthDay = bMatch[0]
          } else if (typeof profile.birthday === 'object') {
            const bMonth = String(profile.birthday.month || '').padStart(2, '0')
            const bDay = String(profile.birthday.day || '').padStart(2, '0')
            bMonthDay = `${bMonth}-${bDay}`
          }
          if (bMonthDay === todayMonthDay) {
            birthdayNotifications.push({
              id: `birthday-${pk}-${todayMonthDay}`,
              pubkey: pk,
              type: 'birthday',
              created_at: Math.floor(today.getTime() / 1000)
            })
          }
        }
      })

      // --- 結合 + 重複除去 + ソート ---------------------------------------
      const combined = [
        ...reactionItems,
        ...parsedZaps,
        ...repostItems,
        ...mentionItems,
        ...badgeItems,
        ...followItems,
        ...birthdayNotifications
      ]
      const seen = new Set()
      const deduped = []
      for (const n of combined) {
        const key = `${n.type}:${n.id}`
        if (seen.has(key)) continue
        seen.add(key)
        deduped.push(n)
      }
      deduped.sort((a, b) => b.created_at - a.created_at)

      setOriginalPosts(postMap)
      setProfiles(profileMap)
      setNotifications(deduped)
    } catch (e) {
      console.error('Failed to load notifications:', e)
    } finally {
      setLoading(false)
    }
  }

  // 通知行クリック → 対応する投稿画面に遷移 (Android NotificationRow onNoteClick 相当)
  const handleNotificationClick = (notification, originalPost) => {
    // 誕生日 / フォロー / バッジ → プロフィールに飛ばす
    if (notification.type === 'birthday' ||
        notification.type === 'follow' ||
        notification.type === 'badge' ||
        notification.type === 'mention') {
      if (onViewProfile) {
        onClose()
        onViewProfile(notification.pubkey)
      }
      return
    }
    // リアクション / Zap / リポスト / 返信 の対象投稿 ID を解決
    let targetEventId = null
    if (notification.type === 'reaction' || notification.type === 'emoji_reaction' ||
        notification.type === 'repost' || notification.type === 'reply') {
      const eTag = notification.tags?.find(t => t[0] === 'e')
      targetEventId = eTag?.[1] || originalPost?.id || null
    } else if (notification.type === 'zap') {
      targetEventId = notification.targetEventId || originalPost?.id || null
    }
    if (targetEventId && onPostClick) {
      onClose()
      onPostClick(targetEventId, originalPost || null)
    } else if (onViewProfile) {
      // 対象投稿が解決できなければプロフィールに飛ばす
      onClose()
      onViewProfile(notification.pubkey)
    }
  }

  const renderNotificationItem = (notification) => {
    const reactor = profiles[notification.pubkey] || { pubkey: notification.pubkey }

    // 対象投稿の解決 (reaction / emoji_reaction / repost / reply は e タグ, zap は targetEventId)
    let originalPost = null
    if (notification.type === 'reaction' || notification.type === 'emoji_reaction' ||
        notification.type === 'repost' || notification.type === 'reply') {
      const eTag = notification.tags?.find(t => t[0] === 'e')
      originalPost = originalPosts[eTag?.[1]]
    } else if (notification.type === 'zap') {
      originalPost = originalPosts[notification.targetEventId]
    }

    const isClickable = true

    return (
      <div
        key={notification.id}
        onClick={isClickable ? () => handleNotificationClick(notification, originalPost) : undefined}
        className={`p-4 border-b border-[var(--border-color)] hover:bg-[var(--bg-secondary)]/30 transition-colors ${isClickable ? 'cursor-pointer' : ''}`}
        role={isClickable ? 'button' : undefined}
        tabIndex={isClickable ? 0 : undefined}
        onKeyDown={isClickable ? (e) => {
          if (e.key === 'Enter' || e.key === ' ') {
            e.preventDefault()
            handleNotificationClick(notification, originalPost)
          }
        } : undefined}
      >
        <div className="flex items-start gap-3">
          {/* Reactor Avatar */}
          <div className="relative flex-shrink-0">
            <button
              onClick={(e) => { e.stopPropagation(); onClose(); onViewProfile(notification.pubkey); }}
              className="w-10 h-10 rounded-full overflow-hidden bg-[var(--bg-tertiary)] block"
            >
              {reactor.picture ? (
                <img
                  src={getImageUrl(reactor.picture)}
                  alt=""
                  className="w-full h-full object-cover"
                  referrerPolicy="no-referrer"
                />
              ) : (
                <div className="w-full h-full flex items-center justify-center">
                  <svg className="w-6 h-6 text-[var(--text-tertiary)]" viewBox="0 0 24 24" fill="currentColor">
                    <path d="M12 12c2.21 0 4-1.79 4-4s-1.79-4-4-4-4 1.79-4 4 1.79 4 4 4zm0 2c-2.67 0-8 1.34-8 4v2h16v-2c0-2.66-5.33-4-8-4z"/>
                  </svg>
                </div>
              )}
            </button>

            {/* Type Icon Overlay — 通知種別ごとに色 / アイコンを切り替え */}
            <div className={`absolute -bottom-1 -right-1 w-5 h-5 rounded-full flex items-center justify-center border-2 border-[var(--bg-primary)] ${
              (notification.type === 'reaction' || notification.type === 'emoji_reaction') ? 'bg-pink-500' :
              notification.type === 'zap' ? 'bg-yellow-500' :
              notification.type === 'repost' ? 'bg-green-500' :
              notification.type === 'reply' ? 'bg-blue-500' :
              notification.type === 'mention' ? 'bg-blue-400' :
              notification.type === 'follow' ? 'bg-purple-500' :
              notification.type === 'badge' ? 'bg-amber-500' :
              'bg-red-400' /* birthday */
            }`}>
              {notification.type === 'emoji_reaction' && notification.emojiUrl ? (
                <img src={getImageUrl(notification.emojiUrl)} alt="" className="w-3.5 h-3.5 object-contain rounded-sm" />
              ) : (notification.type === 'reaction' || notification.type === 'emoji_reaction') ? (
                <svg className="w-2.5 h-2.5 text-white" viewBox="0 0 24 24" fill="currentColor">
                  <path d="M12 21.35l-1.45-1.32C5.4 15.36 2 12.28 2 8.5 2 5.42 4.42 3 7.5 3c1.74 0 3.41.81 4.5 2.09C13.09 3.81 14.76 3 16.5 3 19.58 3 22 5.42 22 8.5c0 3.78-3.4 6.86-8.55 11.54L12 21.35z"/>
                </svg>
              ) : notification.type === 'zap' ? (
                <svg className="w-3 h-3 text-white" viewBox="0 0 24 24" fill="currentColor">
                  <polygon points="13 2 3 14 12 14 11 22 21 10 12 10 13 2"/>
                </svg>
              ) : notification.type === 'repost' ? (
                <svg className="w-3 h-3 text-white" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5">
                  <polyline points="17 1 21 5 17 9"/>
                  <path d="M3 11V9a4 4 0 0 1 4-4h14"/>
                  <polyline points="7 23 3 19 7 15"/>
                  <path d="M21 13v2a4 4 0 0 1-4 4H3"/>
                </svg>
              ) : (notification.type === 'reply' || notification.type === 'mention') ? (
                <svg className="w-3 h-3 text-white" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5">
                  <path d="M21 11.5a8.38 8.38 0 0 1-.9 3.8 8.5 8.5 0 0 1-7.6 4.7 8.38 8.38 0 0 1-3.8-.9L3 21l1.9-5.7a8.38 8.38 0 0 1-.9-3.8 8.5 8.5 0 0 1 4.7-7.6 8.38 8.38 0 0 1 3.8-.9h.5a8.48 8.48 0 0 1 8 8v.5z"/>
                </svg>
              ) : notification.type === 'follow' ? (
                <svg className="w-3 h-3 text-white" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5">
                  <path d="M16 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/>
                  <circle cx="8.5" cy="7" r="4"/>
                  <line x1="20" y1="8" x2="20" y2="14"/>
                  <line x1="23" y1="11" x2="17" y2="11"/>
                </svg>
              ) : notification.type === 'badge' ? (
                <svg className="w-3 h-3 text-white" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5">
                  <circle cx="12" cy="8" r="7"/>
                  <polyline points="8.21 13.89 7 23 12 20 17 23 15.79 13.88"/>
                </svg>
              ) : (
                <svg className="w-3 h-3 text-white" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5">
                  <path d="M20 21v-8a2 2 0 00-2-2H6a2 2 0 00-2 2v8"/>
                  <path d="M4 16s.5-1 2-1 2.5 2 4 2 2.5-2 4-2 2.5 2 4 2 2-1 2-1"/>
                  <path d="M2 21h20"/>
                  <path d="M7 8v2"/>
                  <path d="M12 8v2"/>
                  <path d="M17 8v2"/>
                </svg>
              )}
            </div>
          </div>

          <div className="flex-1 min-w-0">
            <div className="flex items-center justify-between mb-0.5">
              <span className="font-bold text-[var(--text-primary)] truncate">
                {reactor.name || shortenPubkey(notification.pubkey, 6)}
              </span>
              <span className="text-[10px] text-[var(--text-tertiary)] flex-shrink-0">
                {formatTimestamp(notification.created_at)}
              </span>
            </div>

            {/* Notification Content */}
            {(notification.type === 'reaction' || notification.type === 'emoji_reaction') ? (
              <div className="flex items-center gap-1.5 mb-2 flex-wrap">
                <span className="text-sm text-[var(--text-secondary)]">リアクションしました</span>
                {notification.emojiUrl ? (
                  <img src={getImageUrl(notification.emojiUrl)} alt="" className="w-5 h-5 object-contain" />
                ) : notification.reactionEmoji && notification.reactionEmoji !== '+' ? (
                  <span className="text-base">{notification.reactionEmoji}</span>
                ) : (
                  <span className="text-base">❤️</span>
                )}
              </div>
            ) : notification.type === 'zap' ? (
              <div className="mb-2">
                <div className="flex items-center gap-1.5 text-sm text-[var(--text-secondary)]">
                  <span className="font-bold text-yellow-500">⚡ {notification.amount} sats</span>
                  <span>Zapしました</span>
                </div>
                {notification.comment && (
                  <p className="text-sm text-[var(--text-primary)] mt-1 bg-[var(--bg-secondary)] px-2 py-1 rounded-md inline-block">
                    {notification.comment}
                  </p>
                )}
              </div>
            ) : notification.type === 'repost' ? (
              <div className="mb-2">
                <span className="text-sm text-[var(--text-secondary)]">リポストしました</span>
              </div>
            ) : notification.type === 'reply' ? (
              <div className="mb-2">
                <span className="text-sm text-[var(--text-secondary)]">返信しました</span>
                {notification.content && (
                  <p className="text-sm text-[var(--text-primary)] mt-1 line-clamp-3 whitespace-pre-wrap break-words">
                    {notification.content.length > 100 ? notification.content.slice(0, 100) + '…' : notification.content}
                  </p>
                )}
              </div>
            ) : notification.type === 'mention' ? (
              <div className="mb-2">
                <span className="text-sm text-[var(--text-secondary)]">あなたに言及しました</span>
                {notification.content && (
                  <p className="text-sm text-[var(--text-primary)] mt-1 line-clamp-3 whitespace-pre-wrap break-words">
                    {notification.content.length > 100 ? notification.content.slice(0, 100) + '…' : notification.content}
                  </p>
                )}
              </div>
            ) : notification.type === 'follow' ? (
              <div className="mb-2">
                <span className="text-sm text-[var(--text-secondary)]">あなたをフォローしました</span>
              </div>
            ) : notification.type === 'badge' ? (
              <div className="mb-2">
                <span className="text-sm text-[var(--text-secondary)]">
                  バッジ{notification.badgeName ? `「${notification.badgeName}」` : ''}を授与しました
                </span>
              </div>
            ) : (
              <div className="mb-2">
                <p className="text-sm text-[var(--text-secondary)] leading-relaxed">
                  今日{new Date().getMonth() + 1}月{new Date().getDate()}日は<span className="font-bold text-[var(--text-primary)]">{reactor.name || shortenPubkey(notification.pubkey, 6)}</span>の誕生日です。一緒にお祝いしましょう。
                </p>
              </div>
            )}

            {/* Original Post Snippet (リアクション / Zap / リポスト / 返信 の対象投稿) */}
            {(notification.type === 'reaction' || notification.type === 'emoji_reaction' ||
              notification.type === 'zap' || notification.type === 'repost' ||
              notification.type === 'reply') && (
              originalPost ? (
                <div className="p-2 bg-[var(--bg-secondary)]/50 border-l-2 border-[var(--border-color)] rounded-r-lg text-xs text-[var(--text-tertiary)] line-clamp-2 whitespace-pre-wrap break-words">
                  {originalPost.content}
                </div>
              ) : (
                <div className="text-[10px] text-[var(--text-tertiary)] italic">
                  元の投稿が見つかりませんでした
                </div>
              )
            )}

            {/* Birthday secondary text */}
            {notification.type === 'birthday' && (
              <div className="text-[10px] text-[var(--text-tertiary)] uppercase tracking-wider">
                誕生日
              </div>
            )}
          </div>
        </div>
      </div>
    )
  }

  if (!mounted) return null

  const modalContent = (
    <>
      {/* Desktop: Modal overlay */}
      <div className="hidden lg:block fixed inset-0 z-40 bg-black/40 backdrop-blur-sm" onClick={onClose} />

      {/* Mobile: Modal container */}
      <div className="lg:hidden fixed inset-x-0 top-0 bottom-16 z-30 bg-[var(--bg-primary)] flex flex-col">
        <header className="sticky top-0 z-10 header-blur border-b border-[var(--border-color)] flex-shrink-0">
          <div className="flex items-center justify-between px-4 h-14">
            <button onClick={onClose} className="p-2 -ml-2 text-[var(--text-primary)]">
              <svg className="w-6 h-6" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                <line x1="18" y1="6" x2="6" y2="18"/>
                <line x1="6" y1="6" x2="18" y2="18"/>
              </svg>
            </button>
            <h2 className="font-bold text-[var(--text-primary)]">通知</h2>
            <div className="w-10" /> {/* Spacer */}
          </div>
        </header>

        <div className="flex-1 overflow-y-auto">
          {loading ? (
            <div className="flex flex-col items-center justify-center py-20">
              <div className="w-8 h-8 border-2 border-[var(--bg-tertiary)] border-t-[var(--line-green)] rounded-full animate-spin" />
            </div>
          ) : notifications.length === 0 ? (
            <div className="flex flex-col items-center justify-center py-20 px-4 text-center">
              <div className="w-16 h-16 bg-[var(--bg-secondary)] rounded-full flex items-center justify-center mb-4">
                <svg className="w-8 h-8 text-[var(--text-tertiary)]" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5">
                  <path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9"/>
                  <path d="M13.73 21a2 2 0 0 1-3.46 0"/>
                </svg>
              </div>
              <p className="text-[var(--text-secondary)]">通知はまだありません</p>
            </div>
          ) : (
            notifications.map(renderNotificationItem)
          )}
        </div>
      </div>

      {/* Desktop: Modal container */}
      <div
        ref={modalRef}
        className="hidden lg:flex fixed z-40 bg-[var(--bg-primary)] flex-col
          lg:top-1/2 lg:left-1/2 lg:-translate-x-1/2 lg:-translate-y-1/2
          lg:w-full lg:max-w-lg lg:h-[80vh] lg:max-h-[600px] lg:rounded-2xl lg:shadow-2xl lg:border lg:border-[var(--border-color)]"
      >
        <header className="sticky top-0 z-40 header-blur border-b border-[var(--border-color)] flex-shrink-0 lg:rounded-t-2xl">
          <div className="flex items-center justify-between px-4 h-14">
            <h2 className="font-bold text-[var(--text-primary)]">通知</h2>
            <button onClick={onClose} className="p-2 -mr-2 text-[var(--text-tertiary)] hover:text-[var(--text-primary)] transition-colors">
              <svg className="w-5 h-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                <line x1="18" y1="6" x2="6" y2="18"/>
                <line x1="6" y1="6" x2="18" y2="18"/>
              </svg>
            </button>
          </div>
        </header>

        <div className="flex-1 overflow-y-auto">
          {loading ? (
            <div className="flex flex-col items-center justify-center py-20">
              <div className="w-8 h-8 border-2 border-[var(--bg-tertiary)] border-t-[var(--line-green)] rounded-full animate-spin" />
            </div>
          ) : notifications.length === 0 ? (
            <div className="flex flex-col items-center justify-center py-20 px-4 text-center">
              <div className="w-16 h-16 bg-[var(--bg-secondary)] rounded-full flex items-center justify-center mb-4">
                <svg className="w-8 h-8 text-[var(--text-tertiary)]" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5">
                  <path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9"/>
                  <path d="M13.73 21a2 2 0 0 1-3.46 0"/>
                </svg>
              </div>
              <p className="text-[var(--text-secondary)]">通知はまだありません</p>
            </div>
          ) : (
            notifications.map(renderNotificationItem)
          )}
        </div>
      </div>
    </>
  )

  return createPortal(modalContent, document.body)
}
