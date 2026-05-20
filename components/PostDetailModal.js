'use client'

/**
 * PostDetailModal — Android PostDetailScreen と同じ振る舞いの Web 版投稿詳細モーダル。
 *
 *   - 通知タップ等で遷移したターゲット投稿を中央に表示
 *   - その投稿への返信 (Kind 1 で #e タグを持つもの) を時系列順で下に並べる
 *   - 右下に「返信」FAB (LineGreen) を表示し、押すと外側の onReply(post) を呼ぶ
 *
 * リレー選択:
 *   投稿者の NIP-65 write relays + 自分の read relays + 保存済み (localStorage 'nip65Relays') を
 *   重複排除して使う。fetchEventsManaged を直接呼び複数リレーから REQ する。
 */

import { useEffect, useRef, useState } from 'react'
import { createPortal } from 'react-dom'
import {
  fetchEventsManaged,
  fetchEvents,
  fetchProfilesBatch,
  fetchZapTotals,
  fetchRepostCounts,
  fetchBookmarkEventIds,
  getNotificationRelays,
  getDefaultRelay,
  fetchRelayListMetadata
} from '@/lib/nostr'
import { NOSTR_KINDS } from '@/lib/constants'
import PostItem from './PostItem'

/**
 * 投稿者の write relays + 自分の read relays + ローカル NIP-65 を結合して返す。
 * 失敗してもデフォルトに必ずフォールバック。
 */
async function resolveDetailRelays(myPubkey, authorPubkey) {
  const collected = new Set()
  // 1) 自分の read relays (ローカル + リモート NIP-65)
  try {
    const read = await getNotificationRelays(myPubkey)
    for (const r of read || []) collected.add(r)
  } catch (_) {}
  // 2) 投稿者の write relays (リモート NIP-65)
  if (authorPubkey) {
    try {
      const list = await fetchRelayListMetadata(authorPubkey)
      for (const r of list?.write || []) collected.add(r)
    } catch (_) {}
  }
  if (collected.size === 0) collected.add(getDefaultRelay())
  return Array.from(collected)
}

export default function PostDetailModal({
  eventId,
  initialPost = null,
  pubkey,
  onClose,
  onReply,
  onAvatarClick,
  onHashtagClick
}) {
  const [post, setPost] = useState(initialPost && initialPost.id === eventId ? initialPost : null)
  const [replies, setReplies] = useState([])
  const [profiles, setProfiles] = useState({})
  const [reactions, setReactions] = useState({})
  const [repostCounts, setRepostCounts] = useState({})
  const [zapAmounts, setZapAmounts] = useState({})
  const [userReactions, setUserReactions] = useState(new Set())
  const [userReposts, setUserReposts] = useState(new Set())
  const [userBookmarks, setUserBookmarks] = useState(new Set())
  const [loading, setLoading] = useState(true)
  const [mounted, setMounted] = useState(false)
  const overlayRef = useRef(null)

  useEffect(() => {
    setMounted(true)
    return () => setMounted(false)
  }, [])

  // body スクロールロック
  useEffect(() => {
    if (typeof document === 'undefined') return
    const prev = document.body.style.overflow
    document.body.style.overflow = 'hidden'
    return () => { document.body.style.overflow = prev }
  }, [])

  // ESC で閉じる
  useEffect(() => {
    const onKey = (e) => { if (e.key === 'Escape') onClose?.() }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [onClose])

  useEffect(() => {
    if (!eventId) return
    let cancelled = false

    const load = async () => {
      setLoading(true)
      try {
        // まず投稿者を推定 (initialPost があれば即決、なければ後で更新)
        const authorHint = post?.pubkey || initialPost?.pubkey || null
        const relays = await resolveDetailRelays(pubkey, authorHint)

        // ターゲット投稿本体 (キャッシュが無ければ ids: [eventId] で取得)
        let target = post && post.id === eventId ? post : null
        if (!target) {
          const found = await fetchEventsManaged({ ids: [eventId], limit: 1 }, relays)
          if (found && found.length > 0) target = found[0]
        }
        if (cancelled) return
        if (target) setPost(target)

        // 投稿者が判明してからもう一度 relays を解決して返信を取りに行く
        const finalRelays = target?.pubkey && target.pubkey !== authorHint
          ? await resolveDetailRelays(pubkey, target.pubkey)
          : relays

        // 返信: Kind 1 で #e=eventId のもの
        const replyEvents = await fetchEventsManaged({
          kinds: [NOSTR_KINDS.TEXT_NOTE],
          '#e': [eventId],
          limit: 100
        }, finalRelays)
        if (cancelled) return

        const sortedReplies = (replyEvents || [])
          .filter(e => e && e.id !== eventId)
          .sort((a, b) => a.created_at - b.created_at)
        setReplies(sortedReplies)

        // プロフィール / リアクション / リポスト / Zap / ブックマークをまとめて取得
        const allEvents = [target, ...sortedReplies].filter(Boolean)
        const authorPubkeys = Array.from(new Set(allEvents.map(e => e.pubkey)))
        const allIds = allEvents.map(e => e.id)

        const [profileMap, reactionEvents, repostMap, zapMap, myBookmarks] = await Promise.all([
          fetchProfilesBatch(authorPubkeys),
          allIds.length > 0
            ? fetchEventsManaged({ kinds: [NOSTR_KINDS.REACTION], '#e': allIds, limit: 500 }, finalRelays)
            : Promise.resolve([]),
          allIds.length > 0 ? fetchRepostCounts(allIds, pubkey) : Promise.resolve({}),
          allIds.length > 0 ? fetchZapTotals(allIds) : Promise.resolve({}),
          pubkey ? fetchBookmarkEventIds(pubkey).catch(() => []) : Promise.resolve([])
        ])
        if (cancelled) return

        // リアクション集計
        const reactionMap = {}
        const myReactions = new Set()
        for (const r of reactionEvents || []) {
          const eTag = (r.tags || []).find(t => t[0] === 'e')
          const tid = eTag?.[1]
          if (!tid) continue
          reactionMap[tid] = (reactionMap[tid] || 0) + 1
          if (r.pubkey === pubkey) myReactions.add(tid)
        }

        // リポスト: fetchRepostCounts は { counts, userReposts } を返す実装もあるので両対応
        let repostCountsLocal = {}
        let myRepostsLocal = new Set()
        if (repostMap && typeof repostMap === 'object') {
          if (repostMap.counts) {
            repostCountsLocal = repostMap.counts || {}
            if (repostMap.userReposts) {
              myRepostsLocal = repostMap.userReposts instanceof Set
                ? repostMap.userReposts
                : new Set(repostMap.userReposts || [])
            }
          } else {
            repostCountsLocal = repostMap
          }
        }

        setProfiles(profileMap || {})
        setReactions(reactionMap)
        setUserReactions(myReactions)
        setRepostCounts(repostCountsLocal)
        setUserReposts(myRepostsLocal)
        setZapAmounts(zapMap || {})
        setUserBookmarks(new Set(myBookmarks || []))
      } catch (e) {
        console.error('[PostDetailModal] failed to load:', e)
      } finally {
        if (!cancelled) setLoading(false)
      }
    }

    load()
    return () => { cancelled = true }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [eventId])

  if (!mounted) return null

  const handleOverlayClick = (e) => {
    if (e.target === overlayRef.current) onClose?.()
  }

  // PostItem に渡す共通 props を作るヘルパ
  const buildItemProps = (p) => ({
    post: p,
    profile: profiles[p.pubkey],
    profiles,
    likeCount: reactions[p.id] || 0,
    repostCount: repostCounts[p.id] || 0,
    zapAmount: zapAmounts[p.id] || 0,
    hasLiked: userReactions.has(p.id),
    hasReposted: userReposts.has(p.id),
    hasBookmarked: userBookmarks.has(p.id),
    myPubkey: pubkey,
    isOwnPost: p.pubkey === pubkey,
    onAvatarClick: onAvatarClick || (() => {}),
    onHashtagClick: onHashtagClick || (() => {}),
    // 詳細モーダル内ではアクションは飾りのみ (タップしても何もしない)。
    // 既存タイムラインに戻ってからアクションする想定 — Android PostDetailScreen と同じ範囲。
    onLike: () => onReply?.(p),
    onRepost: () => {},
    onZap: () => {}
  })

  const modal = (
    <div
      ref={overlayRef}
      onClick={handleOverlayClick}
      className="fixed inset-0 z-[60] bg-black/70 backdrop-blur-sm flex items-stretch lg:items-center lg:justify-center"
    >
      <div
        className="relative flex flex-col w-full lg:w-auto lg:max-w-2xl lg:h-[85vh] lg:max-h-[820px] bg-[var(--bg-primary)] lg:rounded-2xl lg:shadow-2xl lg:border lg:border-[var(--border-color)] overflow-hidden"
        onClick={(e) => e.stopPropagation()}
      >
        {/* Header */}
        <header className="sticky top-0 z-10 header-blur border-b border-[var(--border-color)] flex-shrink-0">
          <div className="flex items-center justify-between px-3 h-14">
            <button
              onClick={onClose}
              aria-label="戻る"
              className="p-2 -ml-1 text-[var(--text-primary)] rounded-full hover:bg-[var(--bg-secondary)]"
            >
              <svg className="w-6 h-6" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                <path strokeLinecap="round" strokeLinejoin="round" d="M15 18l-6-6 6-6"/>
              </svg>
            </button>
            <h2 className="font-bold text-[var(--text-primary)]">投稿</h2>
            <div className="w-10" />
          </div>
        </header>

        {/* Body */}
        <div className="flex-1 overflow-y-auto pb-28">
          {loading && !post ? (
            <div className="flex flex-col items-center justify-center py-20">
              <div className="w-8 h-8 border-2 border-[var(--bg-tertiary)] border-t-[var(--line-green)] rounded-full animate-spin" />
            </div>
          ) : !post ? (
            <div className="flex flex-col items-center justify-center py-20 px-4 text-center">
              <p className="text-[var(--text-secondary)]">投稿が見つかりませんでした</p>
            </div>
          ) : (
            <>
              <PostItem {...buildItemProps(post)} />
              {replies.length > 0 && (
                <>
                  <div className="px-4 py-2 text-xs text-[var(--text-tertiary)] uppercase tracking-wider border-b border-[var(--border-color)]">
                    返信 {replies.length}
                  </div>
                  {replies.map(r => (
                    <PostItem key={r.id} {...buildItemProps(r)} />
                  ))}
                </>
              )}
              {!loading && replies.length === 0 && (
                <div className="px-4 py-8 text-center text-xs text-[var(--text-tertiary)]">
                  まだ返信はありません
                </div>
              )}
              {loading && (
                <div className="flex justify-center py-4">
                  <div className="w-5 h-5 border-2 border-[var(--bg-tertiary)] border-t-[var(--line-green)] rounded-full animate-spin" />
                </div>
              )}
            </>
          )}
        </div>

        {/* Reply FAB — Android PostDetailScreen 右下の「返信」ボタンと同等 */}
        {post && onReply && (
          <button
            onClick={() => onReply(post)}
            className="absolute right-4 bottom-6 flex items-center gap-2 px-5 h-14 rounded-full bg-[var(--line-green)] text-white font-bold shadow-lg hover:opacity-90 active:scale-95 transition"
          >
            <svg className="w-5 h-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
              <path strokeLinecap="round" strokeLinejoin="round" d="M21 11.5a8.38 8.38 0 0 1-.9 3.8 8.5 8.5 0 0 1-7.6 4.7 8.38 8.38 0 0 1-3.8-.9L3 21l1.9-5.7a8.38 8.38 0 0 1-.9-3.8 8.5 8.5 0 0 1 4.7-7.6 8.38 8.38 0 0 1 3.8-.9h.5a8.48 8.48 0 0 1 8 8v.5z"/>
            </svg>
            返信
          </button>
        )}
      </div>
    </div>
  )

  return createPortal(modal, document.body)
}
