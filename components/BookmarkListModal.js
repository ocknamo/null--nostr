'use client'

import { useState, useEffect, useCallback } from 'react'
import { createPortal } from 'react-dom'
import {
  fetchEvents,
  fetchProfilesBatch,
  getAllCachedProfiles,
  shortenPubkey,
  RELAYS
} from '@/lib/nostr'
import { NOSTR_KINDS } from '@/lib/constants'
import PostItem from './PostItem'
import LongFormPostItem from './LongFormPostItem'

const MAX_BOOKMARKS_TO_FETCH = 100
const MAX_ADDRESSABLE_BOOKMARKS_TO_FETCH = 30

function uniq(values) {
  return [...new Set(values.filter(Boolean))]
}

function parseAddressTag(value) {
  if (!value || typeof value !== 'string') return null

  const [kindText, pubkey, ...identifierParts] = value.split(':')
  const kind = Number(kindText)
  const identifier = identifierParts.join(':')

  if (!Number.isInteger(kind) || !pubkey || !identifier) return null

  return {
    raw: value,
    kind,
    pubkey,
    identifier
  }
}

function eventAddress(event) {
  const identifier = event.tags?.find(tag => tag[0] === 'd')?.[1]
  return identifier ? `${event.kind}:${event.pubkey}:${identifier}` : null
}

export default function BookmarkListModal({ pubkey, onClose, onProfileClick, onHashtagClick }) {
  const [mounted, setMounted] = useState(false)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [posts, setPosts] = useState([])
  const [profiles, setProfiles] = useState({})
  const [bookmarkCount, setBookmarkCount] = useState(0)

  useEffect(() => {
    setMounted(true)
  }, [])

  useEffect(() => {
    if (!mounted) return

    const previousOverflow = document.body.style.overflow
    document.body.style.overflow = 'hidden'

    const handleKeyDown = (event) => {
      if (event.key === 'Escape') onClose()
    }

    window.addEventListener('keydown', handleKeyDown)

    return () => {
      document.body.style.overflow = previousOverflow
      window.removeEventListener('keydown', handleKeyDown)
    }
  }, [mounted, onClose])

  const loadBookmarks = useCallback(async () => {
    if (!pubkey) return

    setLoading(true)
    setError(null)

    try {
      // NIP-51 public bookmark list: latest kind 10003 authored by the current user.
      const bookmarkLists = await fetchEvents({
        kinds: [NOSTR_KINDS.BOOKMARKS],
        authors: [pubkey],
        limit: 5
      }, RELAYS)

      const latestList = bookmarkLists.sort((a, b) => b.created_at - a.created_at)[0]
      const tags = latestList?.tags || []
      const eventIds = uniq(tags
        .filter(tag => tag[0] === 'e' && tag[1])
        .map(tag => tag[1])
      ).slice(0, MAX_BOOKMARKS_TO_FETCH)
      const addressRefs = uniq(tags
        .filter(tag => tag[0] === 'a' && tag[1])
        .map(tag => tag[1])
      )
        .map(parseAddressTag)
        .filter(Boolean)
        .slice(0, MAX_ADDRESSABLE_BOOKMARKS_TO_FETCH)

      setBookmarkCount(eventIds.length + addressRefs.length)

      if (eventIds.length === 0 && addressRefs.length === 0) {
        setPosts([])
        setProfiles({})
        return
      }

      const [eventsById, addressableResults] = await Promise.all([
        eventIds.length > 0
          ? fetchEvents({ ids: eventIds, limit: eventIds.length }, RELAYS)
          : Promise.resolve([]),
        addressRefs.length > 0
          ? Promise.all(addressRefs.map(ref => fetchEvents({
              kinds: [ref.kind],
              authors: [ref.pubkey],
              '#d': [ref.identifier],
              limit: 1
            }, RELAYS)))
          : Promise.resolve([])
      ])

      const byId = new Map()
      for (const event of [...eventsById, ...addressableResults.flat()]) {
        byId.set(event.id, event)
      }

      const eventOrder = new Map(eventIds.map((id, index) => [id, index]))
      const addressOrder = new Map(addressRefs.map((ref, index) => [ref.raw, eventIds.length + index]))
      const sortedPosts = [...byId.values()].sort((a, b) => {
        const orderA = eventOrder.get(a.id) ?? addressOrder.get(eventAddress(a)) ?? Number.MAX_SAFE_INTEGER
        const orderB = eventOrder.get(b.id) ?? addressOrder.get(eventAddress(b)) ?? Number.MAX_SAFE_INTEGER
        return orderA - orderB
      })

      setPosts(sortedPosts)

      const cachedProfiles = getAllCachedProfiles()
      const authors = uniq(sortedPosts.map(post => post.pubkey))
      const fetchedProfiles = authors.length > 0 ? await fetchProfilesBatch(authors) : {}
      setProfiles({ ...cachedProfiles, ...fetchedProfiles })
    } catch (e) {
      console.error('Failed to load bookmarks:', e)
      setError('ブックマークの読み込みに失敗しました')
      setPosts([])
    } finally {
      setLoading(false)
    }
  }, [pubkey])

  useEffect(() => {
    if (mounted) {
      loadBookmarks()
    }
  }, [mounted, loadBookmarks])

  if (!mounted) return null

  return createPortal(
    <div className="fixed inset-0 z-[70] bg-[var(--bg-primary)] flex flex-col">
      <header className="flex-shrink-0 header-blur border-b border-[var(--border-color)]">
        <div className="flex items-center justify-between px-4 h-12 lg:h-14 max-w-3xl mx-auto w-full">
          <button
            onClick={onClose}
            aria-label="閉じる"
            className="w-10 h-10 -ml-2 flex items-center justify-center text-[var(--text-primary)] action-btn rounded-full"
          >
            <svg className="w-6 h-6" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
              <polyline points="15 18 9 12 15 6"/>
            </svg>
          </button>
          <div className="text-center">
            <h2 className="text-lg font-semibold text-[var(--text-primary)]">ブックマーク</h2>
            {bookmarkCount > 0 && (
              <p className="text-[10px] text-[var(--text-tertiary)]">{bookmarkCount}件</p>
            )}
          </div>
          <button
            onClick={loadBookmarks}
            aria-label="更新"
            className="w-10 h-10 -mr-2 flex items-center justify-center text-[var(--text-secondary)] action-btn rounded-full"
          >
            <svg className="w-5 h-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
              <polyline points="23 4 23 10 17 10"/>
              <polyline points="1 20 1 14 7 14"/>
              <path d="M3.51 9a9 9 0 0114.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0020.49 15"/>
            </svg>
          </button>
        </div>
      </header>

      <div className="flex-1 overflow-y-auto">
        <div className="max-w-3xl mx-auto w-full">
          {loading ? (
            <div className="px-4 py-16 text-center">
              <div className="w-8 h-8 mx-auto mb-4 border-2 border-[var(--line-green)] border-t-transparent rounded-full animate-spin" />
              <p className="text-sm text-[var(--text-secondary)]">読み込み中...</p>
            </div>
          ) : error ? (
            <div className="px-4 py-16 text-center">
              <div className="w-16 h-16 mx-auto mb-4 rounded-full bg-red-500/10 flex items-center justify-center">
                <svg className="w-8 h-8 text-red-500" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
                  <circle cx="12" cy="12" r="10"/>
                  <line x1="12" y1="8" x2="12" y2="12"/>
                  <line x1="12" y1="16" x2="12.01" y2="16"/>
                </svg>
              </div>
              <p className="text-[var(--text-secondary)] mb-4">{error}</p>
              <button onClick={loadBookmarks} className="px-4 py-2 rounded-full bg-[var(--line-green)] text-white text-sm font-medium action-btn">
                再読み込み
              </button>
            </div>
          ) : posts.length === 0 ? (
            <div className="px-4 py-16 text-center">
              <div className="w-16 h-16 mx-auto mb-4 rounded-full bg-[var(--bg-secondary)] flex items-center justify-center">
                <svg className="w-8 h-8 text-[var(--text-tertiary)]" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
                  <path d="M5 4a1 1 0 011-1h12a1 1 0 011 1v17l-7-4-7 4V4z"/>
                </svg>
              </div>
              <p className="text-[var(--text-secondary)]">ブックマークはまだありません</p>
            </div>
          ) : (
            <div className="divide-y divide-[var(--border-color)]">
              {posts.map(post => {
                const ItemComponent = post.kind === NOSTR_KINDS.LONG_FORM ? LongFormPostItem : PostItem
                return (
                  <ItemComponent
                    key={post.id}
                    post={post}
                    profile={profiles[post.pubkey] || { pubkey: post.pubkey, name: shortenPubkey(post.pubkey, 6) }}
                    profiles={profiles}
                    myPubkey={pubkey}
                    isOwnPost={post.pubkey === pubkey}
                    showActions={false}
                    onAvatarClick={(targetPubkey) => {
                      onClose()
                      if (onProfileClick) onProfileClick(targetPubkey)
                    }}
                    onHashtagClick={(hashtag) => {
                      onClose()
                      if (onHashtagClick) onHashtagClick(hashtag)
                    }}
                  />
                )
              })}
            </div>
          )}
        </div>
      </div>
    </div>,
    document.body
  )
}
