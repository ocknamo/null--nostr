'use client'

import { useState, useEffect, useCallback, useRef, useImperativeHandle, forwardRef } from 'react'
import { nip19 } from 'nostr-tools'
import {
  fetchEvents,
  parseProfile,
  signEventNip07,
  createEventTemplate,
  publishEvent,
  shortenPubkey,
  formatTimestamp,
  hasNip07,
  addToMuteList,
  fetchMuteListCached,
  fetchLightningInvoice,
  copyToClipboard,
  unlikeEvent,
  unrepostEvent,
  deleteEvent,
  fetchFollowListCached,
  fetchMutualFollowsCached,
  fetchProfilesBatch,
  getAllCachedProfiles,
  getReadRelays,
  getWriteRelays,
  getDefaultRelay,
  getNotificationRelays,
  reportEvent,
  createBirdwatchLabel,
  fetchBirdwatchLabels,
  rateBirdwatchLabel,
  fetchBookmarkEventIds,
  addBookmark,
  removeBookmark,
  fetchZapTotals,
  fetchRepostCounts,
  RELAYS
} from '@/lib/nostr'
import { uploadImagesInParallel } from '@/lib/imageUtils'
import { setCachedMuteList } from '@/lib/cache'
import {
  markNotInterested,
  recordEngagement
} from '@/lib/recommendation'
import { fetchEventsManaged } from '@/lib/connection-manager'
import PostItem from './PostItem'
import LongFormPostItem from './LongFormPostItem'
import UserProfileView from './UserProfileView'
import SearchModal from './SearchModal'
import NotificationModal from './NotificationModal'
import PostDetailModal from './PostDetailModal'
import EmojiPicker from './EmojiPicker'
import { NOSTR_KINDS } from '@/lib/constants'
import { useSTT } from '@/hooks/useSTT'
import DivineVideoRecorder from './DivineVideoRecorder'
import { recordMetric } from '@/lib/performance-metrics'

// Extract hashtags from content (NIP-01)
function extractHashtags(content) {
  if (!content) return []
  const hashtagRegex = /#([^\s#\u3000]+)/g
  const hashtags = []
  let match
  while ((match = hashtagRegex.exec(content)) !== null) {
    const tag = match[1].toLowerCase()
    if (!hashtags.includes(tag)) {
      hashtags.push(tag)
    }
  }
  return hashtags
}

// Render content preview with hashtags and custom emojis highlighted
function ContentPreview({ content, customEmojis = [] }) {
  if (!content) return null

  // Build emoji map from selected emojis (format: ['emoji', shortcode, url])
  const emojiMap = {}
  customEmojis.forEach(emoji => {
    if (emoji[0] === 'emoji' && emoji[1] && emoji[2]) {
      emojiMap[emoji[1]] = emoji[2]
    }
  })

  // Split by hashtags and custom emoji shortcodes
  const combinedRegex = /(#[^\s#\u3000]+|:[a-zA-Z0-9_]+:)/g
  const parts = content.split(combinedRegex).filter(Boolean)

  return (
    <div className="text-base text-[var(--text-primary)] whitespace-pre-wrap break-words">
      {parts.map((part, i) => {
        // Check for hashtags
        if (part.startsWith('#') && part.length > 1) {
          return (
            <span key={i} className="text-[var(--line-green)]">
              {part}
            </span>
          )
        }

        // Check for custom emoji shortcodes
        const emojiMatch = part.match(/^:([a-zA-Z0-9_]+):$/)
        if (emojiMatch) {
          const shortcode = emojiMatch[1]
          const emojiUrl = emojiMap[shortcode]
          if (emojiUrl) {
            return (
              <img
                key={i}
                src={emojiUrl}
                alt={`:${shortcode}:`}
                title={`:${shortcode}:`}
                className="inline-block w-5 h-5 align-middle mx-0.5"
                onError={(e) => {
                  e.target.style.display = 'none'
                }}
              />
            )
          }
          // Show shortcode as text if no URL found
          return <span key={i} className="text-[var(--text-tertiary)]">{part}</span>
        }

        return <span key={i}>{part}</span>
      })}
    </div>
  )
}

const TimelineTab = forwardRef(function TimelineTab({ pubkey, onStartDM, scrollContainerRef, onPostPublished, isDesktop = false, isActive = true }, ref) {
  const [followingPosts, setFollowingPosts] = useState([])
  const [profiles, setProfiles] = useState({})
  const [loading, setLoading] = useState(true)
  const [loadError, setLoadError] = useState(false)
  const [loadingMore, setLoadingMore] = useState(false)
  const [reactions, setReactions] = useState({})
  const [userReactions, setUserReactions] = useState(new Set())
  const [userReposts, setUserReposts] = useState(new Set())
  const [userReactionIds, setUserReactionIds] = useState({}) // eventId -> reactionEventId
  const [userRepostIds, setUserRepostIds] = useState({}) // eventId -> repostEventId
  const [repostCounts, setRepostCounts] = useState({}) // eventId -> repost count
  const [zapAmounts, setZapAmounts] = useState({}) // eventId -> total zap sats
  const [userBookmarks, setUserBookmarks] = useState(new Set()) // bookmarked event ids
  const [bookmarkingId, setBookmarkingId] = useState(null) // in-flight bookmark toggle
  const [zapAnimating, setZapAnimating] = useState(null)
  const [likeAnimating, setLikeAnimating] = useState(null)
  const [showPostModal, setShowPostModal] = useState(false)
  const [newPost, setNewPost] = useState('')
  // 引用ポスト (リポスト長押し) と 返信 (投稿長押し) のターゲット — iOS PostSheet と同じ NIP-10/NIP-18
  const [quotePost, setQuotePost] = useState(null)
  const [replyToPost, setReplyToPost] = useState(null)
  const [imageFiles, setImageFiles] = useState([])
  const [imagePreviews, setImagePreviews] = useState([])
  const [uploadingPostImage, setUploadingPostImage] = useState(false)
  const [uploadProgress, setUploadProgress] = useState('')
  const [posting, setPosting] = useState(false)
  const [showEmojiPicker, setShowEmojiPicker] = useState(false)
  const [showRecorder, setShowRecorder] = useState(false)
  const [recordedVideo, setRecordedVideo] = useState(null)
  const [emojiTags, setEmojiTags] = useState([]) // Array of emoji tags for post
  const [contentWarning, setContentWarning] = useState('') // Content warning text (NIP-36)
  const [showCWInput, setShowCWInput] = useState(false) // Toggle CW input visibility
  const [viewingProfile, setViewingProfile] = useState(null)
  const [mutedPubkeys, setMutedPubkeys] = useState(new Set())
  const [showZapModal, setShowZapModal] = useState(null)
  const [zapAmount, setZapAmount] = useState('')
  const [zapComment, setZapComment] = useState('')
  const [zapping, setZapping] = useState(false)
  const [showSearch, setShowSearch] = useState(false)
  const [searchQuery, setSearchQuery] = useState('') // Initial query for search modal
  const [showNotifications, setShowNotifications] = useState(false)
  const [hasUnreadNotifications, setHasUnreadNotifications] = useState(false)
  // 通知から投稿詳細モーダルへ遷移するための状態 (Android PostDetailScreen 相当)
  const [focusedPostId, setFocusedPostId] = useState(null)
  const [focusedPostEvent, setFocusedPostEvent] = useState(null)

  // Speech to Text
  const handleTranscript = useCallback((text) => {
    setNewPost(prev => prev ? prev + ' ' + text : text)
  }, [])
  const { isRecording: isSTTActive, toggleRecording: toggleSTT, partialText } = useSTT(handleTranscript)

  // Birdwatch (NIP-32) state
  const [birdwatchLabels, setBirdwatchLabels] = useState({}) // eventId -> array of label events
  const [followList, setFollowList] = useState([])
  const [followListLoading, setFollowListLoading] = useState(false)
  const [followingPrefetched, setFollowingPrefetched] = useState(false)
  const subRef = useRef(null)
  const longPressTimerRef = useRef(null)
  const postImageInputRef = useRef(null)
  const postImageAddRef = useRef(null)
  const initialLoadDone = useRef(false)
  // Maximum number of images allowed
  const MAX_IMAGES = 3
  // Get posts for current mode
  const posts = followingPosts
  const setPosts = setFollowingPosts

  // Expose refresh function to parent
  useImperativeHandle(ref, () => ({
    refresh: loadTimeline,
    closeProfile: () => setViewingProfile(null),
    openPostModal: () => setShowPostModal(true),
    closeSearch: () => { setShowSearch(false); setSearchQuery('') },
    openSearch: (query) => { setSearchQuery(query); setShowSearch(true) }
  }))

  // Lock body scroll when modal is open
  useEffect(() => {
    if (showPostModal || viewingProfile || showZapModal || showSearch || showNotifications || focusedPostId) {
      document.body.style.overflow = 'hidden'
    } else {
      document.body.style.overflow = ''
    }
    return () => {
      document.body.style.overflow = ''
    }
  }, [showPostModal, viewingProfile, showZapModal, showSearch, showNotifications, focusedPostId])

  // Close search modal when tab becomes inactive
  useEffect(() => {
    if (!isActive && showSearch) {
      setShowSearch(false)
    }
  }, [isActive, showSearch])

  useEffect(() => {
    // Immediately load cached profiles for instant display
    const cachedProfiles = getAllCachedProfiles()
    if (Object.keys(cachedProfiles).length > 0) {
      setProfiles(cachedProfiles)
    }

    // Start loading data
    loadTimeline()

    return () => {
      if (subRef.current) {
        subRef.current.close()
      }
    }
  }, [])

  // Load mute list, follow list, and check notifications when pubkey is available
  useEffect(() => {
    if (pubkey) {
      loadMuteList()
      loadFollowList()
      checkNotifications()
    }
  }, [pubkey])

  const checkNotifications = async () => {
    if (!pubkey) return
    try {
      const lastRead = parseInt(localStorage.getItem('lastNotificationReadAt') || '0', 10)
      // アプリ版 (Android NostrRepositoryNotifications) と同じく接続中の
      // inbox/read リレー (NIP-65 read=true) からまとめて取得する
      const notifRelays = await getNotificationRelays(pubkey)
      const relays = (notifRelays && notifRelays.length > 0) ? notifRelays : [getDefaultRelay()]

      const [events, mutualFollowPubkeys] = await Promise.all([
        // fetchEventsManaged を直接呼び全 read relay から REQ する
        // (fetchEvents は先頭リレーしか使わないため通知の取りこぼしが起きる)
        // Android と同じ 6 種類 (リアクション / Zap / リポスト / 返信メンション / バッジ / フォロー) を見る
        fetchEventsManaged({
          kinds: [
            NOSTR_KINDS.REACTION,
            NOSTR_KINDS.ZAP,
            NOSTR_KINDS.REPOST,
            NOSTR_KINDS.TEXT_NOTE,
            NOSTR_KINDS.BADGE_AWARD,
            NOSTR_KINDS.CONTACTS
          ],
          '#p': [pubkey],
          since: lastRead,
          limit: 100
        }, relays),
        fetchMutualFollowsCached(pubkey, relays)
      ])

      // 自分由来のイベントは無視。Kind 1 はメンションも返信も両方拾う。
      let hasNew = events.some(e => e.pubkey !== pubkey && e.created_at > lastRead)

      // Check for birthdays today if not already read today
      if (!hasNew && mutualFollowPubkeys.length > 0) {
        const today = new Date()
        const startOfToday = new Date(today.getFullYear(), today.getMonth(), today.getDate()).getTime() / 1000

        if (lastRead < startOfToday) {
          const todayMonthDay = `${String(today.getMonth() + 1).padStart(2, '0')}-${String(today.getDate()).padStart(2, '0')}`

          // Need profiles to check birthdays
          const profileMap = await fetchProfilesBatch(mutualFollowPubkeys)
          const hasBirthdayToday = mutualFollowPubkeys.some(pk => {
            const profile = profileMap[pk]
            if (profile?.birthday) {
              if (typeof profile.birthday === 'string') {
                return profile.birthday.endsWith(todayMonthDay)
              } else if (typeof profile.birthday === 'object') {
                const bMonth = String(profile.birthday.month || '').padStart(2, '0')
                const bDay = String(profile.birthday.day || '').padStart(2, '0')
                return `${bMonth}-${bDay}` === todayMonthDay
              }
            }
            return false
          })

          if (hasBirthdayToday) {
            hasNew = true
          }
        }
      }

      setHasUnreadNotifications(hasNew)
    } catch (e) {
      console.error('Failed to check notifications:', e)
    }
  }

  const handleOpenNotifications = () => {
    setShowNotifications(true)
    setHasUnreadNotifications(false)
    localStorage.setItem('lastNotificationReadAt', Math.floor(Date.now() / 1000).toString())
  }

  // Load following timeline when follow list is first available
  useEffect(() => {
    if (followList.length > 0 && followingPosts.length === 0 && !loading) {
      loadFollowingTimeline()
    }
  }, [followList])

  const loadFollowList = async () => {
    if (!pubkey) return
    setFollowListLoading(true)
    let retries = 2
    
    while (retries >= 0) {
      try {
        const follows = await fetchFollowListCached(pubkey, retries < 2) // Force refresh on retry
        if (follows && follows.length > 0) {
          setFollowList(follows)
          setFollowListLoading(false)
          return
        } else if (follows && follows.length === 0) {
          // User has no follows, this is valid
          setFollowList([])
          setFollowListLoading(false)
          return
        }
      } catch (e) {
        console.error('Failed to load follow list:', e, 'Retries left:', retries)
      }
      retries--
      if (retries >= 0) {
        await new Promise(r => setTimeout(r, 500))
      }
    }
    // Default to empty array on complete failure
    setFollowList([])
    setFollowListLoading(false)
  }

  const loadMuteList = async () => {
    if (!pubkey) return
    let retries = 2
    
    while (retries >= 0) {
      try {
        const muteList = await fetchMuteListCached(pubkey, retries < 2) // Force refresh on retry
        if (muteList && muteList.pubkeys) {
          setMutedPubkeys(new Set(muteList.pubkeys))
          return
        }
      } catch (e) {
        console.error('Failed to load mute list:', e, 'Retries left:', retries)
      }
      retries--
      if (retries >= 0) {
        await new Promise(r => setTimeout(r, 500))
      }
    }
    // Default to empty set on complete failure
    setMutedPubkeys(new Set())
  }

  const handleAvatarClick = (targetPubkey, profile) => {
    if (targetPubkey !== pubkey) {
      setViewingProfile(targetPubkey)
    }
  }

  const handleMute = async (targetPubkey) => {
    if (!pubkey) return
    try {
      await addToMuteList(pubkey, 'pubkey', targetPubkey)
      setMutedPubkeys(prev => new Set([...prev, targetPubkey]))
      // Update cache
      const newMuteList = { pubkeys: [...mutedPubkeys, targetPubkey], eventIds: [], hashtags: [], words: [] }
      setCachedMuteList(pubkey, newMuteList)
    } catch (e) {
      console.error('Failed to mute:', e)
    }
  }

  // Handle "Not Interested" feedback for recommendation feed
  const handleNotInterested = (eventId, authorPubkey) => {
    // Mark in recommendation system
    markNotInterested(eventId, authorPubkey)
  }

  // NIP-56: Report handler
  const handleReport = async (reportData) => {
    if (!pubkey) return
    try {
      await reportEvent(reportData)
      alert('通報を送信しました')
    } catch (e) {
      console.error('Failed to report:', e)
      throw e
    }
  }

  // NIP-32: Birdwatch handler
  const handleBirdwatch = async (birdwatchData) => {
    if (!pubkey) return
    try {
      const result = await createBirdwatchLabel(birdwatchData)
      if (result.success && result.event) {
        // Add the new label to state
        setBirdwatchLabels(prev => ({
          ...prev,
          [birdwatchData.eventId]: [
            ...(prev[birdwatchData.eventId] || []),
            result.event
          ]
        }))
      }
      alert('コンテキストを追加しました')
    } catch (e) {
      console.error('Failed to create Birdwatch label:', e)
      throw e
    }
  }

  // NIP-32: Birdwatch rate handler
  const handleBirdwatchRate = async (labelEventId, rating) => {
    if (!pubkey) return
    try {
      await rateBirdwatchLabel(labelEventId, rating)
    } catch (e) {
      console.error('Failed to rate Birdwatch label:', e)
      throw e
    }
  }

  // Fetch Birdwatch labels for posts
  const fetchBirdwatchForPosts = async (postIds) => {
    if (!postIds || postIds.length === 0) return
    try {
      const labels = await fetchBirdwatchLabels(postIds)
      if (Object.keys(labels).length > 0) {
        setBirdwatchLabels(prev => ({ ...prev, ...labels }))
      }
    } catch (e) {
      console.error('Failed to fetch Birdwatch labels:', e)
    }
  }


  // Load following timeline (for following mode and desktop dual column)
  const loadFollowingTimeline = async () => {
    setFollowListLoading(true)
    if (followingPosts.length === 0) {
      setLoading(true)
    }

    if (followList.length === 0) {
      setFollowingPosts([])
      setFollowListLoading(false)
      setLoading(false)
      initialLoadDone.current = true
      return
    }
    
    const fetchStartedAt = (typeof performance !== 'undefined' && performance.now) ? performance.now() : Date.now()
    const readRelays = getReadRelays()
    // アプリ版に合わせて 2 日間ウィンドウを使用:
    //   - Android NostrRepositoryTimeline.fetchFollowingTimelineFast: since = now - 2 * DAY_SECS
    //   - iOS  NostrRepository+Timeline.fetchFollowingTimeline:        since = -86400 * 2
    // 1時間だとフォロー中ユーザーの新着が無い場合に空になりやすいため。
    const twoDaysAgo = Math.floor(Date.now() / 1000) - 2 * 24 * 3600

    try {
      const noteFilter = { kinds: [1, NOSTR_KINDS.LONG_FORM, NOSTR_KINDS.ADDRESSABLE_SHORT_VIDEO], authors: followList, since: twoDaysAgo, limit: 100 }
      const repostFilter = { kinds: [6], authors: followList, since: twoDaysAgo, limit: 50 }
      
      const [notes, reposts] = await Promise.all([
        fetchEvents(noteFilter, readRelays),
        fetchEvents(repostFilter, readRelays)
      ])

      const repostData = []
      const originalAuthors = new Set()

      for (const repost of reposts) {
        try {
          if (repost.content) {
            const originalEvent = JSON.parse(repost.content)
            originalAuthors.add(originalEvent.pubkey)
            repostData.push({
              ...originalEvent,
              _repostedBy: repost.pubkey,
              _repostTime: repost.created_at,
              _isRepost: true,
              _repostId: repost.id
            })
          }
        } catch (e) {
          console.warn('Failed to parse repost event:', e.message)
        }
      }

      const allPosts = [...notes, ...repostData].sort((a, b) => {
        const timeA = a._repostTime || a.created_at
        const timeB = b._repostTime || b.created_at
        return timeB - timeA
      })

      if (allPosts.length > 0 || followingPosts.length === 0) {
        setFollowingPosts(allPosts)
      }
      recordMetric('timeline.following.firstPage', ((typeof performance !== 'undefined' && performance.now) ? performance.now() : Date.now()) - fetchStartedAt, { count: allPosts.length, emptyPreserved: allPosts.length === 0 && followingPosts.length > 0 })
      initialLoadDone.current = true
      
      // Fetch profiles
      const authors = new Set()
      allPosts.forEach(p => {
        authors.add(p.pubkey)
        if (p._repostedBy) authors.add(p._repostedBy)
      })
      originalAuthors.forEach(a => authors.add(a))
      
      if (authors.size > 0) {
        const profileMap = await fetchProfilesBatch(Array.from(authors))
        setProfiles(prev => ({ ...prev, ...profileMap }))
      }

      // Fetch Birdwatch labels in background
      const eventIds = allPosts.map(p => p.id)
      fetchBirdwatchForPosts(eventIds)

      // Fetch reactions / reposts / zaps / bookmarks in parallel (iOS enrichPosts と同じ)
      if (pubkey && eventIds.length > 0) {
        const [reactionEvents, repostAgg, zapTotals, bookmarkIds] = await Promise.all([
          fetchEvents({ kinds: [7], '#e': eventIds, limit: 500 }, getReadRelays()),
          fetchRepostCounts(eventIds, pubkey),
          fetchZapTotals(eventIds),
          fetchBookmarkEventIds(pubkey)
        ])

        const reactionCounts = {}
        const myReactions = new Set()
        const myReactionIds = {}
        for (const event of reactionEvents) {
          const targetId = event.tags.find(t => t[0] === 'e')?.[1]
          if (targetId) {
            reactionCounts[targetId] = (reactionCounts[targetId] || 0) + 1
            if (event.pubkey === pubkey) {
              myReactions.add(targetId)
              myReactionIds[targetId] = event.id
            }
          }
        }

        setReactions(reactionCounts)
        setUserReactions(myReactions)
        setUserReposts(new Set(Object.keys(repostAgg.myRepostIds)))
        setUserReactionIds(myReactionIds)
        setUserRepostIds(repostAgg.myRepostIds)
        setRepostCounts(repostAgg.counts)
        setZapAmounts(zapTotals)
        setUserBookmarks(new Set(bookmarkIds))
      }
    } catch (e) {
      console.error('Failed to load following timeline:', e)
    } finally {
      setFollowListLoading(false)
      setLoading(false)
    }
  }

  // Manual refresh for the follow-graph timeline.
  const loadTimeline = async () => {
    await loadFollowingTimeline()
  }

  // Handle hashtag click - open search with hashtag
  const handleHashtagClick = (hashtag) => {
    setSearchQuery(`#${hashtag}`)
    setShowSearch(true)
  }

  const handleLike = async (event, emoji = null) => {
    if (!pubkey || userReactions.has(event.id)) return

    setLikeAnimating(event.id)
    setTimeout(() => setLikeAnimating(null), 300)

    try {
      // Build reaction content and tags based on emoji type (NIP-25 + NIP-30)
      let content = '+'
      const tags = [
        ['e', event.id],
        ['p', event.pubkey]
      ]

      if (emoji) {
        if (emoji.type === 'custom') {
          content = `:${emoji.shortcode}:`
          tags.push(['emoji', emoji.shortcode, emoji.url])
        } else if (emoji.type === 'unicode') {
          content = emoji.content
        }
      }

      const reactionEvent = createEventTemplate(7, content, tags)
      reactionEvent.pubkey = pubkey

      const signed = await signEventNip07(reactionEvent)
      const success = await publishEvent(signed)

      if (success) {
        setUserReactions(prev => new Set([...prev, event.id]))
        setUserReactionIds(prev => ({ ...prev, [event.id]: signed.id }))
        setReactions(prev => ({
          ...prev,
          [event.id]: (prev[event.id] || 0) + 1
        }))
        // Record engagement for recommendation personalization
        recordEngagement('like', event.pubkey)
      }
    } catch (e) {
      console.error('Failed to like:', e)
      alert(e.message || 'いいねに失敗しました')
    }
  }

  const handleUnlike = async (event, reactionEventId) => {
    if (!pubkey || !userReactions.has(event.id)) return

    try {
      const result = await unlikeEvent(reactionEventId)
      
      if (result.success) {
        setUserReactions(prev => {
          const newSet = new Set(prev)
          newSet.delete(event.id)
          return newSet
        })
        setUserReactionIds(prev => {
          const newIds = { ...prev }
          delete newIds[event.id]
          return newIds
        })
        setReactions(prev => ({
          ...prev,
          [event.id]: Math.max(0, (prev[event.id] || 1) - 1)
        }))
      }
    } catch (e) {
      console.error('Failed to unlike:', e)
    }
  }

  const handleRepost = async (event) => {
    if (!pubkey || userReposts.has(event.id)) return

    try {
      const repostEvent = createEventTemplate(6, JSON.stringify(event), [
        ['e', event.id, '', 'mention'],
        ['p', event.pubkey]
      ])
      repostEvent.pubkey = pubkey
      
      const signed = await signEventNip07(repostEvent)
      const success = await publishEvent(signed)
      
      if (success) {
        setUserReposts(prev => new Set([...prev, event.id]))
        setUserRepostIds(prev => ({ ...prev, [event.id]: signed.id }))
        setRepostCounts(prev => ({
          ...prev,
          [event.id]: (prev[event.id] || 0) + 1
        }))
        // Record engagement for recommendation personalization
        recordEngagement('repost', event.pubkey)
      }
    } catch (e) {
      console.error('Failed to repost:', e)
      alert(e.message || 'リポストに失敗しました')
    }
  }

  const handleUnrepost = async (event, repostEventId) => {
    if (!pubkey || !userReposts.has(event.id)) return

    try {
      const result = await unrepostEvent(repostEventId)
      
      if (result.success) {
        setUserReposts(prev => {
          const newSet = new Set(prev)
          newSet.delete(event.id)
          return newSet
        })
        setUserRepostIds(prev => {
          const newIds = { ...prev }
          delete newIds[event.id]
          return newIds
        })
        setRepostCounts(prev => ({
          ...prev,
          [event.id]: Math.max(0, (prev[event.id] || 1) - 1)
        }))
      }
    } catch (e) {
      console.error('Failed to unrepost:', e)
    }
  }

  // Bookmark toggle (NIP-51 Kind 10003) — iOS NostrRepository+Bookmarks の add/remove と同じ振る舞い
  const handleBookmark = async (event, wasBookmarked) => {
    if (!pubkey || !event?.id) return
    if (bookmarkingId === event.id) return
    setBookmarkingId(event.id)
    try {
      if (wasBookmarked) {
        const { ids } = await removeBookmark(pubkey, event.id)
        setUserBookmarks(new Set(ids))
      } else {
        const { ids } = await addBookmark(pubkey, event.id)
        setUserBookmarks(new Set(ids))
      }
    } catch (e) {
      console.error('Bookmark toggle failed:', e)
      alert(e.message || 'ブックマーク更新に失敗しました')
    } finally {
      setBookmarkingId(null)
    }
  }

  // リポスト長押し → 引用ポスト (iOS PostRow onRepostLongPress → showQuoteSheet 相当)
  const handleRepostLongPress = (event) => {
    if (!event) return
    setReplyToPost(null)
    setQuotePost(event)
    setShowPostModal(true)
  }

  // 投稿長押し → 返信モーダル (iOS PostRow .onLongPressGesture → showPostDetail 相当)
  const handlePostLongPress = (event) => {
    if (!event) return
    setQuotePost(null)
    setReplyToPost(event)
    setShowPostModal(true)
  }

  // モーダルを閉じるとき replyTo / quotePost もクリア
  const closePostModal = () => {
    setShowPostModal(false)
    setReplyToPost(null)
    setQuotePost(null)
    setImageFiles([])
    setImagePreviews([])
  }

  const handleDelete = async (eventId) => {
    if (!confirm('この投稿を削除しますか？')) return
    
    try {
      const result = await deleteEvent(eventId)
      if (result.success) {
        // Remove from posts list
        setPosts(prev => prev.filter(p => p.id !== eventId && p._repostId !== eventId))
      }
    } catch (e) {
      console.error('Failed to delete:', e)
      alert('削除に失敗しました')
    }
  }

  // Get default zap amount from localStorage
  const getDefaultZapAmount = () => {
    if (typeof window !== 'undefined') {
      const saved = localStorage.getItem('defaultZapAmount')
      return saved ? parseInt(saved, 10) : 21
    }
    return 21
  }

  // Quick zap (single tap)
  const handleZap = async (event) => {
    const profile = profiles[event.pubkey]
    if (!profile?.lud16) {
      alert('この投稿者はLightningアドレスを設定していません')
      return
    }

    setZapAnimating(event.id)
    setTimeout(() => setZapAnimating(null), 600)

    const amount = getDefaultZapAmount()

    try {
      setZapping(true)
      const result = await fetchLightningInvoice(profile.lud16, amount)
      
      if (result.invoice) {
        const copied = await copyToClipboard(result.invoice)
        if (copied) {
          alert(`⚡ ${amount} sats のインボイスをコピーしました！\n\nお好きなLightningウォレットで支払いできます。`)
        } else {
          // Fallback: show invoice for manual copy
          prompt('インボイスをコピーしてください:', result.invoice)
        }
      }
    } catch (e) {
      console.error('Failed to create invoice:', e)
      alert(`インボイスの作成に失敗しました: ${e.message}`)
    } finally {
      setZapping(false)
    }
  }

  // Long press to open zap modal
  const handleZapLongPressStart = (event) => {
    longPressTimerRef.current = setTimeout(() => {
      const profile = profiles[event.pubkey]
      if (!profile?.lud16) {
        alert('この投稿者はLightningアドレスを設定していません')
        return
      }
      setShowZapModal({ event, profile })
      setZapAmount(getDefaultZapAmount().toString())
      setZapComment('')
    }, 500)
  }

  const handleZapLongPressEnd = () => {
    if (longPressTimerRef.current) {
      clearTimeout(longPressTimerRef.current)
      longPressTimerRef.current = null
    }
  }

  // Send custom zap from modal
  const handleSendCustomZap = async () => {
    if (!showZapModal || zapping) return

    const amount = parseInt(zapAmount, 10)
    if (!amount || amount < 1) {
      alert('有効な金額を入力してください')
      return
    }

    try {
      setZapping(true)
      const result = await fetchLightningInvoice(
        showZapModal.profile.lud16, 
        amount, 
        zapComment
      )
      
      if (result.invoice) {
        const copied = await copyToClipboard(result.invoice)
        setShowZapModal(null)
        if (copied) {
          alert(`⚡ ${amount} sats のインボイスをコピーしました！\n\nお好きなLightningウォレットで支払いできます。`)
        } else {
          prompt('インボイスをコピーしてください:', result.invoice)
        }
      }
    } catch (e) {
      console.error('Failed to create invoice:', e)
      alert(`インボイスの作成に失敗しました: ${e.message}`)
    } finally {
      setZapping(false)
    }
  }

  const handlePostImageSelect = (e) => {
    const files = Array.from(e.target.files || [])
    if (files.length === 0) return

    const remainingSlots = MAX_IMAGES - imageFiles.length
    const filesToAdd = files.slice(0, remainingSlots)

    if (filesToAdd.length === 0) {
      alert(`最大${MAX_IMAGES}枚まで画像を追加できます`)
      return
    }

    // Create previews for each file
    filesToAdd.forEach(file => {
      const reader = new FileReader()
      reader.onloadend = () => {
        setImagePreviews(prev => [...prev, reader.result])
      }
      reader.readAsDataURL(file)
    })

    setImageFiles(prev => [...prev, ...filesToAdd])

    // Reset file inputs
    if (postImageInputRef.current) postImageInputRef.current.value = ''
    if (postImageAddRef.current) postImageAddRef.current.value = ''
  }

  const handleRemovePostImage = (index) => {
    setImageFiles(prev => prev.filter((_, i) => i !== index))
    setImagePreviews(prev => prev.filter((_, i) => i !== index))
  }

  const handlePost = async () => {
    if ((!newPost.trim() && imageFiles.length === 0 && !recordedVideo) || !pubkey) return
    setPosting(true)

    try {
      let content = newPost.trim()

      // Upload images if selected
      if (imageFiles.length > 0 && !recordedVideo) {
        try {
          setUploadingPostImage(true)
          setUploadProgress(`アップロード中... (0/${imageFiles.length})`)

          const { urls: uploadedUrls, errors } = await uploadImagesInParallel(imageFiles, {
            onProgress: (current, total) => {
              setUploadProgress(`アップロード中... (${current}/${total})`)
            }
          })

          if (errors.length > 0) {
            const errorMessages = errors.map(e => `${e.fileName}: ${e.error.message}`).join('\n')
            console.error('Some uploads failed:', errors)
            if (uploadedUrls.length === 0) {
              alert(`すべての画像のアップロードに失敗しました:\n${errorMessages}`)
              return
            } else {
              const continueWithPartial = confirm(
                `${errors.length}枚の画像のアップロードに失敗しました。\n` +
                `成功した${uploadedUrls.length}枚で投稿を続けますか?`
              )
              if (!continueWithPartial) {
                return
              }
            }
          }

          if (uploadedUrls.length > 0) {
            const imageUrlsStr = uploadedUrls.join('\n')
            content = content ? `${content}\n${imageUrlsStr}` : imageUrlsStr
          }
        } catch (e) {
          console.error('Image upload failed:', e)
          alert(`画像のアップロードに失敗しました: ${e.message}`)
          return
        } finally {
          setUploadingPostImage(false)
          setUploadProgress('')
        }
      }

      // 引用ポスト (NIP-18): content 末尾に nostr:nevent... を埋め込む
      if (quotePost) {
        try {
          const nevent = nip19.neventEncode({ id: quotePost.id })
          content = content ? `${content}\n\nnostr:${nevent}` : `nostr:${nevent}`
        } catch (e) {
          console.error('Failed to encode nevent for quote:', e)
        }
      }

      const event = createEventTemplate(1, content)
      event.pubkey = pubkey

      // Add client tag
      event.tags = [...event.tags, ['client', 'ぬるぬるweb']]

      // 返信 (NIP-10): e + p タグ
      if (replyToPost) {
        event.tags.push(['e', replyToPost.id, '', 'reply'])
        event.tags.push(['p', replyToPost.pubkey])
      }

      // 引用 (NIP-18): q + p タグ
      if (quotePost) {
        event.tags.push(['q', quotePost.id])
        event.tags.push(['p', quotePost.pubkey])
      }

      // Add video tags if present (imeta for diVine compatibility)
      if (recordedVideo) {
        event.kind = NOSTR_KINDS.ADDRESSABLE_SHORT_VIDEO
        const hashTag = recordedVideo.proofTags?.find(t => t[0] === 'x')
        const hash = hashTag ? hashTag[1] : ''

        // Build imeta tag
        const imetaParts = [
          `url ${recordedVideo.url}`,
          `m ${recordedVideo.mimeType}`,
          `size ${recordedVideo.size}`,
          `dim ${recordedVideo.dim || '720x720'}`
        ]
        if (hash) imetaParts.push(`x ${hash}`)

        event.tags.push(['imeta', ...imetaParts])

        // Also keep individual tags for broader compatibility
        event.tags.push(['url', recordedVideo.url])
        event.tags.push(['m', recordedVideo.mimeType])
        event.tags.push(['x', hash])

        if (recordedVideo.proofTags) {
          // Add verification and proofmode tags
          const diVineTags = recordedVideo.proofTags.filter(t => t[0] === 'verification' || t[0] === 'proofmode')
          event.tags.push(...diVineTags)
        }
      }

      // Add emoji tags if any
      if (emojiTags.length > 0) {
        event.tags = [...event.tags, ...emojiTags]
      }

      // Content warning tag (NIP-36)
      if (contentWarning.trim()) {
        event.tags = [...event.tags, ['content-warning', contentWarning.trim()]]
      }

      // Hashtag tags (NIP-01)
      const hashtags = extractHashtags(content)
      if (hashtags.length > 0) {
        const hashtagTags = hashtags.map(tag => ['t', tag])
        event.tags = [...event.tags, ...hashtagTags]
      }

      const signed = await signEventNip07(event)
      const success = await publishEvent(signed)

      if (success) {
        // 返信/引用ポストは自分のタイムラインに直接出すと文脈が崩れるので、新規投稿のみ追加
        if (!replyToPost && !quotePost) {
          setPosts([signed, ...posts])
        }
        setNewPost('')
        setImageFiles([])
        setImagePreviews([])
        setRecordedVideo(null)
        setEmojiTags([])
        setContentWarning('')
        setShowCWInput(false)
        setShowPostModal(false)
        setReplyToPost(null)
        setQuotePost(null)

        // Notify parent to refresh home tab
        if (onPostPublished) {
          onPostPublished()
        }
      }
    } catch (e) {
      console.error('Failed to post:', e)
      alert(e.message || '投稿に失敗しました')
    } finally {
      setPosting(false)
    }
  }
  
  // Handle emoji selection from picker
  const handleEmojiSelect = (emoji) => {
    // Add :shortcode: to content
    setNewPost(prev => prev + `:${emoji.shortcode}:`)
    // Add emoji tag if not already present
    if (!emojiTags.some(t => t[1] === emoji.shortcode)) {
      setEmojiTags(prev => [...prev, ['emoji', emoji.shortcode, emoji.url]])
    }
    setShowEmojiPicker(false)
  }

  // Render post item - choose between PostItem and LongFormPostItem based on kind
  const renderTimelinePost = (post, { showNotInterested: showNI = false } = {}) => {
    const postProfile = profiles[post.pubkey]
    const postLikeCount = reactions[post.id] || 0
    const postRepostCount = repostCounts[post.id] || 0
    const postZapAmount = zapAmounts[post.id] || 0
    const postHasLiked = userReactions.has(post.id)
    const postHasReposted = userReposts.has(post.id)
    const postHasBookmarked = userBookmarks.has(post.id)
    const postIsZapping = zapAnimating === post.id
    const postIsLiking = likeAnimating === post.id
    const postIsBookmarking = bookmarkingId === post.id
    const commonProps = {
      post,
      profile: postProfile,
      profiles,
      likeCount: postLikeCount,
      repostCount: postRepostCount,
      zapAmount: postZapAmount,
      hasLiked: postHasLiked,
      hasReposted: postHasReposted,
      hasBookmarked: postHasBookmarked,
      myReactionId: userReactionIds[post.id],
      myRepostId: userRepostIds[post.id],
      isLiking: postIsLiking,
      isZapping: postIsZapping,
      isBookmarking: postIsBookmarking,
      onLike: handleLike,
      onUnlike: handleUnlike,
      onRepost: handleRepost,
      onUnrepost: handleUnrepost,
      onZap: handleZap,
      onZapLongPress: handleZapLongPressStart,
      onZapLongPressEnd: handleZapLongPressEnd,
      onBookmark: handleBookmark,
      onRepostLongPress: handleRepostLongPress,
      onPostLongPress: handlePostLongPress,
      onAvatarClick: handleAvatarClick,
      onHashtagClick: handleHashtagClick,
      onMute: handleMute,
      onDelete: handleDelete,
      onReport: handleReport,
      onBirdwatch: handleBirdwatch,
      onBirdwatchRate: handleBirdwatchRate,
      onNotInterested: handleNotInterested,
      birdwatchNotes: birdwatchLabels[post.id] || [],
      myPubkey: pubkey,
      isOwnPost: post.pubkey === pubkey,
      isRepost: post._isRepost,
      repostedBy: post._repostedBy ? profiles[post._repostedBy] || { pubkey: post._repostedBy } : null,
      showNotInterested: showNI
    }

    if (post.kind === NOSTR_KINDS.LONG_FORM) {
      return <LongFormPostItem {...commonProps} />
    }
    return <PostItem {...commonProps} />
  }

  return (
    <div className="min-h-full overflow-x-hidden">
      {/* Header with tabs - fixed position (mobile only) */}
      <header className="fixed top-0 left-0 right-0 lg:left-[240px] xl:left-[280px] z-30 bg-[var(--bg-primary)] border-b border-[var(--border-color)]">
        <div className="flex items-center justify-between px-4 h-14 lg:h-16">
          {/* ADR-0013: relay-wide feed removed; mobile shows follow-graph feed only. */}
          <div className="flex items-center gap-2 p-1 bg-[var(--bg-secondary)] rounded-full lg:hidden">
            <button
              onClick={() => loadTimeline()}
              className="px-4 py-1.5 rounded-full text-xs font-bold transition-all bg-[var(--line-green)] text-white shadow-sm"
            >
              フォロー
            </button>
          </div>
          
          {/* Desktop Title */}
          <h1 className="hidden lg:block text-lg font-bold text-[var(--text-primary)]">タイムライン</h1>
          
          {/* Desktop Search Bar */}
          <div className="hidden lg:flex flex-1 max-w-md mx-8 gap-2 items-center">
            <button
              onClick={() => setShowSearch(true)}
              className="flex-1 flex items-center gap-3 px-5 py-2.5 rounded-full bg-[var(--bg-secondary)] border border-[var(--border-color)] text-[var(--text-tertiary)] hover:border-[var(--text-tertiary)] transition-all"
            >
              <svg className="w-5 h-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                <circle cx="11" cy="11" r="8"/>
                <line x1="21" y1="21" x2="16.65" y2="16.65"/>
              </svg>
              <span className="text-sm">検索...</span>
            </button>
            {/* Desktop Notification Button */}
            <button
              onClick={handleOpenNotifications}
              className="relative p-2.5 rounded-full bg-[var(--bg-secondary)] border border-[var(--border-color)] text-[var(--text-secondary)] hover:text-[var(--text-primary)] transition-all"
              title="通知"
            >
              <svg className="w-5 h-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9"/>
                <path d="M13.73 21a2 2 0 0 1-3.46 0"/>
              </svg>
              {hasUnreadNotifications && (
                <span className="absolute top-2.5 right-2.5 w-2 h-2 bg-red-500 rounded-full border-2 border-[var(--bg-secondary)]" />
              )}
            </button>
          </div>
          
          <div className="flex items-center gap-1 lg:hidden">
            {/* Mobile Search Button */}
            <button
              onClick={() => setShowSearch(true)}
              className="text-[var(--text-secondary)] action-btn p-2"
            >
              <svg className="w-5 h-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <circle cx="11" cy="11" r="8"/>
                <line x1="21" y1="21" x2="16.65" y2="16.65"/>
              </svg>
            </button>

            {/* Mobile Notification Button */}
            <button
              onClick={handleOpenNotifications}
              className="relative text-[var(--text-secondary)] action-btn p-2"
            >
              <svg className="w-5 h-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9"/>
                <path d="M13.73 21a2 2 0 0 1-3.46 0"/>
              </svg>
              {hasUnreadNotifications && (
                <span className="absolute top-2 right-2 w-2 h-2 bg-red-500 rounded-full border-2 border-[var(--bg-primary)]" />
              )}
            </button>
          </div>
          
          {/* Spacer for desktop (refresh buttons moved to columns) */}
          <div className="hidden lg:block w-20" />
        </div>
      </header>
      
      {/* Spacer for fixed header */}
      <div className="h-14 lg:h-16" />

      {/* Search Modal */}
      {showSearch && (
        <SearchModal
          pubkey={pubkey}
          initialQuery={searchQuery}
          onClose={() => { setShowSearch(false); setSearchQuery('') }}
          onViewProfile={(pk) => {
            setShowSearch(false)
            setViewingProfile(pk)
          }}
        />
      )}

      {/* Notification Modal */}
      {showNotifications && (
        <NotificationModal
          pubkey={pubkey}
          onClose={() => setShowNotifications(false)}
          onViewProfile={(pk) => {
            setShowNotifications(false)
            setViewingProfile(pk)
          }}
          onPostClick={(eventId, eventObj) => {
            // 通知タップ → 投稿詳細モーダルへ (Android NotificationRow onNoteClick → PostDetailScreen 相当)
            setShowNotifications(false)
            setFocusedPostEvent(eventObj || null)
            setFocusedPostId(eventId)
          }}
        />
      )}

      {/* Post Detail Modal (通知から遷移) */}
      {focusedPostId && (
        <PostDetailModal
          eventId={focusedPostId}
          initialPost={focusedPostEvent}
          pubkey={pubkey}
          onClose={() => {
            setFocusedPostId(null)
            setFocusedPostEvent(null)
          }}
          onAvatarClick={(pk) => {
            setFocusedPostId(null)
            setFocusedPostEvent(null)
            setViewingProfile(pk)
          }}
          onHashtagClick={(tag) => {
            setFocusedPostId(null)
            setFocusedPostEvent(null)
            setSearchQuery(`#${tag}`)
            setShowSearch(true)
          }}
          onReply={(event) => {
            // 既存の handlePostLongPress と同じフロー (返信モーダルを開く)
            setFocusedPostId(null)
            setFocusedPostEvent(null)
            setQuotePost(null)
            setReplyToPost(event)
            setShowPostModal(true)
          }}
        />
      )}

      {/* Post Modal */}
      {showPostModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center modal-overlay" onClick={closePostModal}>
          <div
            className="w-full h-full sm:h-auto sm:max-w-lg bg-[var(--bg-primary)] sm:rounded-2xl flex flex-col overflow-hidden animate-scaleIn"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex items-center justify-between p-4 border-b border-[var(--border-color)] flex-shrink-0">
              <button onClick={closePostModal} className="text-[var(--text-secondary)] action-btn whitespace-nowrap flex-shrink-0">
                キャンセル
              </button>
              <span className="font-semibold text-[var(--text-primary)] whitespace-nowrap flex-shrink-0">
                {replyToPost ? '返信' : quotePost ? '引用投稿' : '新規投稿'}
              </span>
              <button
                onClick={handlePost}
                disabled={posting || uploadingPostImage || (!newPost.trim() && imageFiles.length === 0)}
                className="btn-line text-sm py-1.5 px-4 disabled:opacity-50 whitespace-nowrap flex-shrink-0"
              >
                {uploadingPostImage ? uploadProgress : posting ? '投稿中...' : '投稿'}
              </button>
            </div>
            <div className="flex-1 p-4 pb-20 sm:pb-4 flex flex-col overflow-y-auto">
              {/* 返信/引用ターゲット表示 */}
              {(replyToPost || quotePost) && (
                <div className="mb-3 p-3 rounded-lg border border-[var(--border-color)] bg-[var(--bg-secondary)]/50">
                  <div className="flex items-center gap-2 mb-1.5 text-xs text-[var(--text-tertiary)]">
                    {replyToPost ? (
                      <>
                        <svg className="w-3.5 h-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><polyline points="9 17 4 12 9 7"/><path d="M20 18v-2a4 4 0 00-4-4H4"/></svg>
                        <span>返信先</span>
                      </>
                    ) : (
                      <>
                        <svg className="w-3.5 h-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><polyline points="17 1 21 5 17 9"/><path d="M3 11V9a4 4 0 014-4h14"/><polyline points="7 23 3 19 7 15"/><path d="M21 13v2a4 4 0 01-4 4H3"/></svg>
                        <span>引用元</span>
                      </>
                    )}
                  </div>
                  <p className="text-sm text-[var(--text-secondary)] line-clamp-3 whitespace-pre-wrap break-words">
                    {(replyToPost || quotePost).content}
                  </p>
                </div>
              )}
              {/* Video Preview */}
              {recordedVideo && (
                <div className="mb-4 relative aspect-square w-full max-w-[300px] mx-auto overflow-hidden rounded-xl bg-black">
                  <video
                    src={recordedVideo.url}
                    autoPlay
                    loop
                    muted
                    playsInline
                    className="w-full h-full object-cover"
                  />
                  <button
                    onClick={() => setRecordedVideo(null)}
                    className="absolute top-2 right-2 p-1.5 bg-black/60 rounded-full text-white hover:bg-black/80 transition-colors"
                    aria-label="動画を削除"
                  >
                    <svg className="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5">
                      <line x1="18" y1="6" x2="6" y2="18" />
                      <line x1="6" y1="6" x2="18" y2="18" />
                    </svg>
                  </button>
                  <div className="absolute bottom-2 left-2 px-2 py-0.5 bg-[var(--line-green)] text-white text-[10px] font-bold rounded-md">
                    6.3s LOOP
                  </div>
                </div>
              )}

              {/* Content Warning Input (NIP-36) */}
              {showCWInput && (
                <div className="mb-3 pb-3 border-b border-[var(--border-color)]">
                  <div className="flex items-center gap-2 mb-1.5">
                    <svg className="w-4 h-4 text-orange-500" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                      <path d="M10.29 3.86L1.82 18a2 2 0 001.71 3h16.94a2 2 0 001.71-3L13.71 3.86a2 2 0 00-3.42 0z"/>
                      <line x1="12" y1="9" x2="12" y2="13"/>
                      <line x1="12" y1="17" x2="12.01" y2="17"/>
                    </svg>
                    <span className="text-sm font-medium text-orange-500">コンテンツ警告</span>
                  </div>
                  <input
                    type="text"
                    value={contentWarning}
                    onChange={(e) => setContentWarning(e.target.value)}
                    className="w-full px-3 py-2 text-sm bg-[var(--bg-secondary)] border border-[var(--border-color)] rounded-lg text-[var(--text-primary)] placeholder:text-[var(--text-tertiary)] focus:outline-none focus:border-orange-500"
                    placeholder="警告の理由（例: ネタバレ、センシティブ）"
                    maxLength={100}
                  />
                </div>
              )}

              {/* Textarea with preview overlay */}
              <div className="relative min-h-[120px] sm:min-h-[150px]">
                <textarea
                  value={newPost}
                  onChange={(e) => setNewPost(e.target.value)}
                  spellCheck={false}
                  className={`w-full min-h-[120px] sm:min-h-[150px] bg-transparent resize-none placeholder-[var(--text-tertiary)] outline-none text-base ${
                    (newPost && (newPost.includes('#') || emojiTags.length > 0)) || partialText || isSTTActive
                      ? 'text-transparent caret-[var(--text-primary)] absolute inset-0 z-10'
                      : 'text-[var(--text-primary)] relative'
                  }`}
                  placeholder={replyToPost ? '返信を入力...' : quotePost ? 'コメントを追加...' : 'いまどうしてる？'}
                  autoFocus
                />
                {/* Visible preview layer - show when there are hashtags, emojis, or active STT */}
                {((newPost && (newPost.includes('#') || emojiTags.length > 0)) || partialText || isSTTActive) && (
                  <div className="w-full min-h-[120px] sm:min-h-[150px] pointer-events-none">
                    <ContentPreview
                      content={newPost + (partialText ? (newPost ? ' ' : '') + partialText : '')}
                      customEmojis={emojiTags}
                    />
                  </div>
                )}
              </div>

              {/* Image previews - Grid layout */}
              {imagePreviews.length > 0 && (
                <div className="mt-3">
                  <div className="flex flex-wrap gap-2">
                    {imagePreviews.map((preview, index) => (
                      <div key={index} className="relative">
                        <img
                          src={preview}
                          alt={`プレビュー ${index + 1}`}
                          className="h-20 w-20 rounded-lg object-cover"
                        />
                        <button
                          onClick={() => handleRemovePostImage(index)}
                          className="absolute -top-1 -right-1 p-1 bg-black/60 rounded-full text-white hover:bg-black/80 transition-colors"
                          aria-label="画像を削除"
                        >
                          <svg className="w-3 h-3" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                            <line x1="18" y1="6" x2="6" y2="18" />
                            <line x1="6" y1="6" x2="18" y2="18" />
                          </svg>
                        </button>
                      </div>
                    ))}
                    {/* Add more button */}
                    {imageFiles.length < MAX_IMAGES && (
                      <label
                        htmlFor="timeline-post-image-add"
                        className="h-20 w-20 rounded-lg border-2 border-dashed border-[var(--border-color)] flex items-center justify-center cursor-pointer hover:border-[var(--line-green)] transition-colors"
                      >
                        <svg className="w-6 h-6 text-[var(--text-tertiary)]" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                          <line x1="12" y1="5" x2="12" y2="19" />
                          <line x1="5" y1="12" x2="19" y2="12" />
                        </svg>
                      </label>
                    )}
                  </div>
                  <input
                    ref={postImageAddRef}
                    type="file"
                    accept="image/*"
                    multiple
                    onChange={handlePostImageSelect}
                    className="hidden"
                    id="timeline-post-image-add"
                  />
                </div>
              )}
              
              {/* Image upload, CW, and emoji picker buttons */}
              <div className="mt-3 pt-3 border-t border-[var(--border-color)] flex-shrink-0">
                <input
                  ref={postImageInputRef}
                  type="file"
                  accept="image/*"
                  multiple
                  className="hidden"
                  onChange={handlePostImageSelect}
                />
                <div className="flex items-center gap-4">
                  {/* Video Recorder button */}
                  {!isDesktop && (
                    <button
                      onClick={() => setShowRecorder(true)}
                      className={`action-btn p-2 ${recordedVideo ? 'text-[var(--line-green)]' : 'text-[var(--text-tertiary)]'}`}
                      title="6秒動画を録画"
                    >
                      <svg className="w-5 h-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                        <polygon points="23 7 16 12 23 17 23 7"></polygon>
                        <rect x="1" y="5" width="15" height="14" rx="2" ry="2"></rect>
                      </svg>
                    </button>
                  )}

                  <label
                    htmlFor="timeline-post-image-input"
                    className={`action-btn p-2 cursor-pointer relative ${(imageFiles.length >= MAX_IMAGES || recordedVideo) ? 'opacity-50 pointer-events-none' : ''}`}
                    title="画像を追加"
                  >
                    <svg className="w-5 h-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                      <rect x="3" y="3" width="18" height="18" rx="2" ry="2"/>
                      <circle cx="8.5" cy="8.5" r="1.5"/>
                      <polyline points="21 15 16 10 5 21"/>
                    </svg>
                    {imageFiles.length > 0 && (
                      <span className="absolute -top-1 -right-1 bg-[var(--line-green)] text-white text-[10px] w-4 h-4 rounded-full flex items-center justify-center">
                        {imageFiles.length}
                      </span>
                    )}
                  </label>
                  <input
                    type="file"
                    accept="image/*"
                    multiple
                    onChange={handlePostImageSelect}
                    className="hidden"
                    id="timeline-post-image-input"
                  />

                  {/* Content Warning toggle (NIP-36) */}
                  <button
                    onClick={() => setShowCWInput(!showCWInput)}
                    className={`action-btn p-2 ${showCWInput ? 'text-orange-500' : 'text-[var(--text-tertiary)]'}`}
                    title="コンテンツ警告 (CW)"
                  >
                    <svg className="w-5 h-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                      <path d="M10.29 3.86L1.82 18a2 2 0 001.71 3h16.94a2 2 0 001.71-3L13.71 3.86a2 2 0 00-3.42 0z"/>
                      <line x1="12" y1="9" x2="12" y2="13"/>
                      <line x1="12" y1="17" x2="12.01" y2="17"/>
                    </svg>
                  </button>

                  {/* Emoji picker button */}
                  <button
                    onClick={() => setShowEmojiPicker(!showEmojiPicker)}
                    className={`action-btn p-2 ${showEmojiPicker ? 'text-[var(--line-green)]' : 'text-[var(--text-tertiary)]'}`}
                    aria-label="絵文字を追加"
                  >
                    <svg className="w-5 h-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                      <circle cx="12" cy="12" r="10"/>
                      <path d="M8 14s1.5 2 4 2 4-2 4-2"/>
                      <line x1="9" y1="9" x2="9.01" y2="9"/>
                      <line x1="15" y1="9" x2="15.01" y2="9"/>
                    </svg>
                  </button>

                  {/* Microphone button for STT */}
                  <button
                    onClick={toggleSTT}
                    className={`action-btn p-2 ${isSTTActive ? 'text-red-500 animate-pulse' : 'text-[var(--text-tertiary)]'}`}
                    title="音声入力"
                  >
                    <svg className="w-5 h-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                      <path d="M12 1a3 3 0 0 0-3 3v8a3 3 0 0 0 6 0V4a3 3 0 0 0-3-3z"/>
                      <path d="M19 10v2a7 7 0 0 1-14 0v-2"/>
                      <line x1="12" y1="19" x2="12" y2="23"/>
                      <line x1="8" y1="23" x2="16" y2="23"/>
                    </svg>
                  </button>
                </div>
                
                {/* Emoji Picker - displayed below buttons */}
                {showEmojiPicker && (
                  <div className="mt-3">
                    <EmojiPicker
                      pubkey={pubkey}
                      onSelect={handleEmojiSelect}
                      onClose={() => setShowEmojiPicker(false)}
                    />
                  </div>
                )}
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Zap Modal */}
      {showZapModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center modal-overlay" onClick={() => setShowZapModal(null)}>
          <div 
            className="w-full max-w-sm mx-4 bg-[var(--bg-primary)] rounded-2xl overflow-hidden animate-scaleIn"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="p-4 border-b border-[var(--border-color)]">
              <div className="flex items-center justify-between">
                <h3 className="text-lg font-bold text-[var(--text-primary)]">⚡ Zap送信</h3>
                <button onClick={() => setShowZapModal(null)} className="text-[var(--text-tertiary)] action-btn p-1">
                  <svg className="w-6 h-6" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                    <line x1="18" y1="6" x2="6" y2="18"/>
                    <line x1="6" y1="6" x2="18" y2="18"/>
                  </svg>
                </button>
              </div>
              <p className="text-sm text-[var(--text-secondary)] mt-1">
                {showZapModal.profile.name || shortenPubkey(showZapModal.event.pubkey)}
              </p>
            </div>

            <div className="p-4 space-y-4">
              <div>
                <label className="block text-sm font-medium text-[var(--text-secondary)] mb-1.5">金額 (sats)</label>
                <input
                  type="number"
                  value={zapAmount}
                  onChange={(e) => setZapAmount(e.target.value)}
                  className="input-line"
                  placeholder="21"
                  min="1"
                />
              </div>

              <div className="flex flex-wrap gap-2">
                {[21, 100, 500, 1000, 5000].map(amount => (
                  <button
                    key={amount}
                    onClick={() => setZapAmount(amount.toString())}
                    className={`px-3 py-1 rounded-full text-sm ${
                      zapAmount === amount.toString()
                        ? 'bg-yellow-500 text-black'
                        : 'bg-[var(--bg-secondary)] text-[var(--text-primary)]'
                    }`}
                  >
                    ⚡{amount}
                  </button>
                ))}
              </div>

              <div>
                <label className="block text-sm font-medium text-[var(--text-secondary)] mb-1.5">コメント (任意)</label>
                <input
                  type="text"
                  value={zapComment}
                  onChange={(e) => setZapComment(e.target.value)}
                  className="input-line"
                  placeholder="Zap!"
                  maxLength={100}
                />
              </div>
            </div>

            <div className="p-4 border-t border-[var(--border-color)]">
              <button
                onClick={handleSendCustomZap}
                disabled={zapping || !zapAmount}
                className="w-full btn-line py-3 disabled:opacity-50"
              >
                {zapping ? '作成中...' : `⚡ ${zapAmount || 0} sats のインボイスを作成`}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Video Recorder Modal */}
      {showRecorder && (
        <DivineVideoRecorder
          onComplete={(data) => {
            setRecordedVideo(data)
            setShowRecorder(false)
            setImageFiles([])
            setImagePreviews([])
          }}
          onClose={() => setShowRecorder(false)}
        />
      )}

      {/* FAB - Post Button (Hidden on desktop where sidebar has compose button) */}
      <button
        onClick={() => setShowPostModal(true)}
        className="fab lg:hidden"
      >
        <svg className="w-6 h-6" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
          <line x1="12" y1="5" x2="12" y2="19"/>
          <line x1="5" y1="12" x2="19" y2="12"/>
        </svg>
      </button>
      
      {/* Desktop FAB */}
      <button
        onClick={() => setShowPostModal(true)}
        className="hidden lg:flex fixed bottom-8 right-8 w-14 h-14 rounded-full bg-[var(--line-green)] text-white items-center justify-center shadow-lg hover:scale-105 hover:shadow-xl transition-all z-30"
      >
        <svg className="w-6 h-6" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
          <line x1="12" y1="5" x2="12" y2="19"/>
          <line x1="5" y1="12" x2="19" y2="12"/>
        </svg>
      </button>

      {/* Timeline */}
      {/* Mobile: Single column with tab switching */}
      <div className="lg:hidden">
        {loading ? (
          /* Nintendo-style: やさしいローディング */
          <div className="flex items-center justify-center min-h-[50vh] animate-fadeIn">
            <div className="loading-friendly">
              <div className="loading-dots">
                <div className="loading-dot" />
                <div className="loading-dot" />
                <div className="loading-dot" />
              </div>
              <p className="loading-text">読み込んでいます...</p>
            </div>
          </div>
        ) : posts.length === 0 || loadError ? (
          <div className="flex flex-col items-center justify-center py-20 px-4 text-center animate-fadeIn">
            {loadError ? (
              <>
                <div className="w-16 h-16 bg-[var(--bg-secondary)] rounded-full flex items-center justify-center mb-4 text-2xl">
                  🌐
                </div>
                <h2 className="text-lg font-bold text-[var(--text-primary)] mb-2">接続エラー</h2>
                <p className="text-[var(--text-secondary)] mb-6">
                  通信状態を確認して、もう一度お試しください
                </p>
                <button
                  onClick={() => loadTimeline()}
                  className="btn-line px-6 py-2 rounded-full text-sm"
                >
                  再試行
                </button>
              </>
            ) : (
              <div className="empty-friendly">
                <div className="empty-friendly-icon">📭</div>
                <p className="empty-friendly-text">
                  {followList.length === 0 ? 'まだ誰もフォローしていません' : 'フォロー中のユーザーの投稿がありません'}
                </p>
                {followList.length === 0 && (
                  <div className="mt-6">
                    <div className="text-xs px-3 py-2 bg-[var(--bg-secondary)] rounded-lg text-[var(--text-tertiary)] inline-block">
                      💡 プロフィールページでユーザーをフォローしてみましょう
                    </div>
                  </div>
                )}
                {followList.length > 0 && (
                   <p className="text-xs text-[var(--text-tertiary)] mt-2">
                     しばらくお待ちいただくか、更新してみてください
                   </p>
                )}
              </div>
            )}
          </div>
        ) : (
          <div className="divide-y divide-[var(--border-color)]">
            {posts
              .filter(post => !mutedPubkeys.has(post.pubkey))
              .map((post, index) => (
                <div
                  key={post._repostId || post.id}
                  className="animate-fadeIn"
                  style={{ animationDelay: `${Math.min(index * 30, 300)}ms` }}
                >
                  {renderTimelinePost(post)}
                </div>
              ))}

            {loadingMore && (
              /* Nintendo-style: やさしい追加読み込み表示 */
              <div className="loading-friendly py-4">
                <div className="loading-dots">
                  <div className="loading-dot" />
                  <div className="loading-dot" />
                  <div className="loading-dot" />
                </div>
                <p className="loading-text">もっと読み込んでいます...</p>
              </div>
            )}
          </div>
        )}
      </div>
      
      {/* Desktop: following feed only after ADR-0013 relay-feed removal */}
      <div className="hidden lg:flex lg:fixed lg:top-16 lg:bottom-0 lg:left-[240px] xl:left-[280px] lg:right-0">
        {/* Relay column removed from UI by ADR-0013. */}

        {/* Right column: Following timeline */}
        <div className="flex-1 flex flex-col overflow-hidden">
          <div className="flex-shrink-0 bg-[var(--bg-primary)] border-b border-[var(--border-color)] px-4 py-3 flex items-center justify-between">
            <h2 className="font-bold text-[var(--text-primary)]">フォロー</h2>
            <button
              onClick={() => loadFollowingTimeline()}
              disabled={followListLoading}
              className="p-2 rounded-full text-[var(--text-tertiary)] hover:text-[var(--text-primary)] hover:bg-[var(--bg-tertiary)] transition-all disabled:opacity-50"
              title="フォローを更新"
            >
              <svg className={`w-4 h-4 ${followListLoading ? 'animate-spin' : ''}`} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                <path d="M23 4v6h-6M1 20v-6h6"/>
                <path d="M3.51 9a9 9 0 0114.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0020.49 15"/>
              </svg>
            </button>
          </div>
          <div className="flex-1 overflow-y-auto">
            {followListLoading ? (
              <div className="divide-y divide-[var(--border-color)]">
                {[1, 2, 3].map((i) => (
                  <div key={i} className="p-4">
                    <div className="flex items-start gap-3">
                      <div className="w-10 h-10 rounded-full skeleton" />
                      <div className="flex-1">
                        <div className="skeleton h-4 w-24 rounded mb-2" />
                        <div className="skeleton h-4 w-full rounded mb-1" />
                        <div className="skeleton h-4 w-2/3 rounded" />
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            ) : followingPosts.length === 0 ? (
              <div className="px-4 py-16 text-center">
                <p className="text-[var(--text-tertiary)]">
                  {followList.length === 0 ? 'まだ誰もフォローしていません' : 'フォロー中のユーザーの投稿がありません'}
                </p>
                {followList.length === 0 && (
                  <div className="mt-4">
                    <div className="text-xs px-3 py-2 bg-[var(--bg-secondary)] rounded-lg text-[var(--text-tertiary)] inline-block">
                      💡 プロフィールページでユーザーをフォローしてみましょう
                    </div>
                  </div>
                )}
              </div>
            ) : (
              <div className="divide-y divide-[var(--border-color)]">
                {followingPosts
                  .filter(post => !mutedPubkeys.has(post.pubkey))
                  .map((post, index) => (
                    <div
                      key={post._repostId || post.id}
                      className="animate-fadeIn"
                      style={{ animationDelay: `${Math.min(index * 30, 300)}ms` }}
                    >
                      {renderTimelinePost(post)}
                    </div>
                  ))}
              </div>
            )}
          </div>
        </div>
      </div>

      {/* User Profile View */}
      {viewingProfile && (
        <UserProfileView
          targetPubkey={viewingProfile}
          myPubkey={pubkey}
          onClose={() => setViewingProfile(null)}
          onMute={(targetPubkey) => {
            setMutedPubkeys(prev => new Set([...prev, targetPubkey]))
          }}
          onStartDM={(targetPubkey) => {
            setViewingProfile(null)
            if (onStartDM) onStartDM(targetPubkey)
          }}
        />
      )}
    </div>
  )
})

export default TimelineTab
