package io.nurunuru.app.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import io.nurunuru.app.data.Nip05Utils
import io.nurunuru.app.data.NostrKeyUtils
import io.nurunuru.app.data.NostrRepository
import io.nurunuru.app.data.SearchQueryParser
import io.nurunuru.app.data.models.ScoredPost
import io.nurunuru.app.data.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*

enum class FeedType { GLOBAL, FOLLOWING }

sealed class SearchNavigationEvent {
    data class OpenProfile(val pubkey: String) : SearchNavigationEvent()
}

data class TimelineUiState(
    val globalPosts: List<ScoredPost> = emptyList(),
    val followingPosts: List<ScoredPost> = emptyList(),
    val pendingGlobalPosts: List<ScoredPost> = emptyList(),
    val pendingFollowingPosts: List<ScoredPost> = emptyList(),
    val isGlobalLoading: Boolean = false,
    val isFollowingLoading: Boolean = false,
    val isGlobalRefreshing: Boolean = false,
    val isFollowingRefreshing: Boolean = false,
    val globalError: String? = null,
    val followingError: String? = null,
    val feedType: FeedType = FeedType.FOLLOWING,
    val searchQuery: String = "",
    val searchResults: List<ScoredPost> = emptyList(),
    val isSearching: Boolean = false,
    val recentSearches: List<String> = emptyList(),
    val hasNewRecommendations: Boolean = false,
    val hasNewFollowing: Boolean = false,
    val hasNewNotifications: Boolean = false,
    val followList: List<String> = emptyList(),
    val birdwatchNotes: Map<String, List<io.nurunuru.app.data.models.NostrEvent>> = emptyMap(),
    val savedRelayUrls: List<String> = emptyList(),
    val selectedRelayUrl: String? = null,
    val relayPosts: List<ScoredPost> = emptyList(),
    val pendingRelayPosts: List<ScoredPost> = emptyList(),
    val isRelayFeedLoading: Boolean = false,
    val isGlobalLoadingMore: Boolean = false,
    val isFollowingLoadingMore: Boolean = false,
    val hasMoreGlobal: Boolean = true,
    val hasMoreFollowing: Boolean = true,
    val hasMoreRelay: Boolean = true,
    val globalPageCursor: Long? = null,
    val followingPageCursor: Long? = null,
    val relayPageCursor: Long? = null
)

class TimelineViewModel(
    private val repository: NostrRepository,
    private val pubkeyHex: String
) : ViewModel() {

    private val _uiState = MutableStateFlow(TimelineUiState(
        isGlobalLoading = true,
        isFollowingLoading = true
    ))
    val uiState: StateFlow<TimelineUiState> = _uiState.asStateFlow()

    private val _navigationEvents = MutableSharedFlow<SearchNavigationEvent>()
    val navigationEvents = _navigationEvents.asSharedFlow()

    // ─── Live streaming ───────────────────────────────────────────────────────
    /** Active subscription ID. Null until the initial load completes. */
    private var liveSubId: String? = null
    private var livePollingJob: Job? = null

    // ─── Relay live streaming ─────────────────────────────────────────────────
    private var relayLiveJob: Job? = null
    private val inFlightLikeEventIds = mutableSetOf<String>()
    private val inFlightRepostEventIds = mutableSetOf<String>()

    private val seenRelayEventIds: MutableSet<String> =
        java.util.concurrent.ConcurrentHashMap.newKeySet()
    private val liveRelayBuffer = mutableListOf<ScoredPost>()

    /**
     * IDs of events already processed by the live stream.
     * Uses ConcurrentHashMap.newKeySet() for thread safety — the live polling
     * loop runs on Dispatchers.IO while loadFollowingTimeline/loadGlobalTimeline
     * add to this set on Dispatchers.Main after suspension.
     */
    private val seenEventIds: MutableSet<String> =
        java.util.concurrent.ConcurrentHashMap.newKeySet()

    /** Deduplicates a post list by event ID, keeping the first occurrence. */
    private fun List<ScoredPost>.deduped() = distinctBy { it.event.id }

    /** Deduplicate and keep newest-first order when merging fresh pages with stale cache. */
    private fun List<ScoredPost>.timelineSortedDeduped() =
        distinctBy { it.event.id }.sortedByDescending { it.event.createdAt }

    private fun List<ScoredPost>.olderCursorOrNull(): Long? =
        minOfOrNull { it.event.createdAt }?.minus(1)

    /**
     * Keep pagination contiguous when fresh posts are merged with a much older cache.
     * If an incoming batch is entirely older than the current cursor, it is stale
     * cache and must not move the cursor backwards over the missing gap.
     */
    private fun mergedCursorAfter(current: Long?, incoming: List<ScoredPost>): Long? {
        val next = incoming.olderCursorOrNull() ?: return current
        val newestIncoming = incoming.maxOfOrNull { it.event.createdAt } ?: return current
        return if (current == null || newestIncoming >= current) next else current
    }

    init {
        loadData()
        loadSavedRelays()
    }

    private fun loadData() {
        viewModelScope.launch {
            loadRecentSearches()

            // Cache-first follow list is loaded synchronously for first paint; relay refresh runs later.
            loadFollowList(cacheOnly = true)
            val initialFollows = _uiState.value.followList
            if (initialFollows.isNotEmpty()) {
                launch(Dispatchers.IO) { repository.prefetchProfilesAndBadges(initialFollows) }
            }

            // Fast first-paint timelines: raw posts + cached profiles only.
            launch { loadGlobalTimelineFast() }

            // バックグラウンドで設定をプリフェッチ（UIをブロックしない・すべて並列実行）
            launch(Dispatchers.IO) {
                val pk = pubkeyHex.ifEmpty { return@launch }
                listOf(
                    launch { try { repository.fetchMuteList(pk) }
                             catch (e: Exception) { android.util.Log.w("TimelineViewModel", "fetchMuteList failed: ${e.message}") } },
                    launch { try { repository.fetchEmojiList(pk) }
                             catch (e: Exception) { android.util.Log.w("TimelineViewModel", "fetchEmojiList failed: ${e.message}") } },
                    launch { try { repository.fetchProfileBadgesInfo(pk) }
                             catch (e: Exception) { android.util.Log.w("TimelineViewModel", "fetchProfileBadgesInfo failed: ${e.message}") } },
                    launch { try { repository.syncNip65Relays(pk) }
                             catch (e: Exception) { android.util.Log.w("TimelineViewModel", "syncNip65Relays failed: ${e.message}") } },
                    launch { try { repository.prefetchFollowRelayLists() }
                             catch (e: Exception) { android.util.Log.w("TimelineViewModel", "prefetchFollowRelayLists failed: ${e.message}") } }
                ).forEach { it.join() }
            }

            // Network-first timeline: do not render stale timeline event cache as normal UI.
            // Profile/follow-list caches are still used, but event caches are fallback-only.

            // Fast following with cached follows, then refresh follow list in the background.
            if (initialFollows.isNotEmpty()) loadFollowingTimelineFast(initialFollows)
            else _uiState.update { it.copy(isFollowingLoading = false) }

            launch {
                loadFollowList(cacheOnly = false)
                val freshFollows = _uiState.value.followList
                if (freshFollows.isNotEmpty() && freshFollows != initialFollows) {
                    repository.prefetchProfilesAndBadges(freshFollows)
                    loadFollowingTimelineFast(freshFollows)
                }
                launch { loadGlobalTimeline() }
                launch { loadFollowingTimeline() }
            }

            startNotificationPolling()
            // Start live streaming once first-paint data is ready.
            startLiveStreaming()
        }
    }

    /**
     * Kick off a 1-second polling loop that prepends new events to the active
     * feed.  Called automatically after the initial load.
     */
    private fun startLiveStreaming() {
        livePollingJob?.cancel()

        // Seed deduplication set from whatever is already displayed.
        val state = _uiState.value
        seenEventIds.clear()
        seenEventIds.addAll(state.globalPosts.map { it.event.id })
        seenEventIds.addAll(state.followingPosts.map { it.event.id })

        // おすすめタブ用の内部バッファ。50件たまったらピルを表示する。
        val liveGlobalBuffer = mutableListOf<ScoredPost>()

        // Subscribe globally so both tabs receive all new events in real time.
        // Using an empty authors list sends a REQ with no author filter, which
        // matches all Kind-1 notes on connected relays.
        val followAuthors = emptyList<String>()

        livePollingJob = viewModelScope.launch(Dispatchers.IO) {
            val subId = repository.startLiveStream(followAuthors)
            if (subId == null) {
                android.util.Log.w("TimelineViewModel", "Live stream unavailable (Rust client not ready)")
                return@launch
            }
            liveSubId = subId

            try {
                while (isActive) {
                    delay(1_000)

                    val newEvents = repository.pollLiveStream(subId)
                    if (newEvents.isEmpty()) continue

                    // Filter out duplicates (relay may echo back our own events).
                    val fresh = newEvents.filter { seenEventIds.add(it.id) }
                    if (fresh.isEmpty()) continue

                    android.util.Log.d("TimelineViewModel",
                        "Live: ${fresh.size} new event(s) received")

                    // Enrich with profile + engagement data on IO, then push to pending buffer.
                    val enriched = repository.enrichPostsDirect(fresh)
                    if (enriched.isEmpty()) continue

                    // おすすめタブ: フルアルゴリズム適用（ミュート・品質・言語ブースト・スコアリング）
                    val scoredForGlobal = repository.scoreForRecommended(enriched)

                    // フォロータブ: ミュートフィルターのみ適用（IO スレッド上、cheap）
                    val mutedPubkeys = repository.getCachedMuteList(pubkeyHex)
                        ?.pubkeys?.toSet() ?: emptySet()

                    // リレータブ: 表示済みでない投稿のみバッファに追加
                    val existingGlobalIds = _uiState.value.globalPosts.mapTo(HashSet()) { it.event.id }
                    val pendingGlobalIds = _uiState.value.pendingGlobalPosts.mapTo(HashSet()) { it.event.id }
                    val newGlobal = scoredForGlobal.filter {
                        it.event.id !in existingGlobalIds && it.event.id !in pendingGlobalIds &&
                        it.event.getTagValues("e").isEmpty() // リプライ除外
                    }
                    if (newGlobal.isNotEmpty()) liveGlobalBuffer.addAll(newGlobal)

                    withContext(Dispatchers.Main) {
                        val followSet = _uiState.value.followList.toSet()
                        _uiState.update { state ->
                            val existingFollowIds = state.followingPosts.mapTo(HashSet()) { it.event.id }
                            val pendingFollowIds = state.pendingFollowingPosts.mapTo(HashSet()) { it.event.id }

                            val newFollow = enriched.filter {
                                followSet.contains(it.event.pubkey) &&
                                it.event.id !in existingFollowIds &&
                                it.event.id !in pendingFollowIds &&
                                it.event.pubkey !in mutedPubkeys &&
                                it.event.getTagValues("e").isEmpty() // リプライ除外
                            }

                            // リレータブ: 3件たまったらピルを表示してバッファをクリア
                            val showGlobalPill = liveGlobalBuffer.size >= 3
                            if (showGlobalPill) {
                                val buffered = liveGlobalBuffer.sortedByDescending { it.event.createdAt }.deduped()
                                liveGlobalBuffer.clear()
                                android.util.Log.d("TimelineViewModel",
                                    "Relay pill ready: ${buffered.size} posts pending")
                                state.copy(
                                    pendingGlobalPosts = (buffered + state.pendingGlobalPosts).deduped(),
                                    pendingFollowingPosts = (newFollow + state.pendingFollowingPosts).deduped(),
                                    hasNewRecommendations = state.hasNewRecommendations ||
                                        (state.feedType != FeedType.GLOBAL && buffered.isNotEmpty()),
                                    hasNewFollowing = state.hasNewFollowing ||
                                        (state.feedType != FeedType.FOLLOWING && newFollow.isNotEmpty())
                                )
                            } else {
                                state.copy(
                                    pendingFollowingPosts = (newFollow + state.pendingFollowingPosts).deduped(),
                                    hasNewFollowing = state.hasNewFollowing ||
                                        (state.feedType != FeedType.FOLLOWING && newFollow.isNotEmpty())
                                )
                            }
                        }
                    }
                }
            } finally {
                repository.stopLiveStream(subId)
                liveSubId = null
            }
        }
    }

    /** Stop live polling (e.g. when screen is backgrounded or VM is cleared). */
    fun stopLiveStreaming() {
        livePollingJob?.cancel()
        livePollingJob = null
        relayLiveJob?.cancel()
        relayLiveJob = null
    }

    private fun loadRecentSearches() {
        _uiState.update { it.copy(recentSearches = repository.getRecentSearches()) }
    }

    private suspend fun loadFollowList(cacheOnly: Boolean = false) {
        repository.getCachedFollowList(pubkeyHex)?.let { cached ->
            if (cached.isNotEmpty()) _uiState.update { it.copy(followList = cached) }
        }
        if (cacheOnly) return
        try {
            val follows = repository.refreshFollowList(pubkeyHex)
            if (follows.isNotEmpty()) _uiState.update { it.copy(followList = follows) }
        } catch (e: Exception) { /* Keep stale cache */ }
    }

    private fun startNotificationPolling() {
        viewModelScope.launch(Dispatchers.IO) {
            var knownLatest = repository.getCachedNotifications(pubkeyHex)?.items?.maxOfOrNull { it.createdAt } ?: 0L
            while (isActive) {
                delay(30_000)
                runCatching { repository.fetchNotifications(pubkeyHex, limit = 30, skipCache = true) }
                    .onSuccess { result ->
                        val latest = result.items.maxOfOrNull { it.createdAt } ?: 0L
                        if (latest > knownLatest && knownLatest > 0L) {
                            _uiState.update { it.copy(hasNewNotifications = true) }
                        }
                        knownLatest = maxOf(knownLatest, latest)
                    }
            }
        }
    }

    fun markNotificationsSeen() {
        _uiState.update { it.copy(hasNewNotifications = false) }
    }

    private fun loadGlobalTimelineFast() {
        viewModelScope.launch {
            runCatching { repository.fetchGlobalTimelineFast(50).deduped() }
                .onSuccess { posts ->
                    if (posts.isNotEmpty()) {
                        seenEventIds.addAll(posts.map { it.event.id })
                        _uiState.update { it.copy(globalPosts = posts, isGlobalLoading = false, globalPageCursor = posts.olderCursorOrNull(), hasMoreGlobal = true) }
                        val snapshot = posts
                        launch(Dispatchers.IO) {
                            val enriched = repository.enrichTimelinePosts(snapshot).deduped()
                            if (sameIds(_uiState.value.globalPosts, snapshot) && enriched.isNotEmpty()) {
                                _uiState.update { st -> st.copy(globalPosts = enriched) }
                            }
                        }
                    } else _uiState.update { it.copy(isGlobalLoading = false) }
                }
                .onFailure { _uiState.update { it.copy(isGlobalLoading = false) } }
        }
    }

    private suspend fun loadFollowingTimelineFast(authors: List<String>) {
        runCatching { repository.fetchFollowingTimelineFast(authors, 50).deduped() }
            .onSuccess { posts ->
                if (posts.isNotEmpty() || _uiState.value.followingPosts.isEmpty()) {
                    seenEventIds.addAll(posts.map { it.event.id })
                    _uiState.update { st ->
                        st.copy(
                            followingPosts = (posts + st.followingPosts).timelineSortedDeduped(),
                            isFollowingLoading = false,
                            followingPageCursor = posts.olderCursorOrNull(),
                            hasMoreFollowing = true
                        )
                    }
                    val snapshot = posts
                    viewModelScope.launch(Dispatchers.IO) {
                        val enriched = repository.enrichTimelinePosts(snapshot).deduped()
                        if (sameIds(_uiState.value.followingPosts, snapshot) && enriched.isNotEmpty()) {
                            _uiState.update { st -> st.copy(followingPosts = enriched) }
                        }
                    }
                } else _uiState.update { it.copy(isFollowingLoading = false) }
            }
            .onFailure { _uiState.update { it.copy(isFollowingLoading = false) } }
    }

    private fun sameIds(a: List<ScoredPost>, b: List<ScoredPost>): Boolean =
        a.size == b.size && a.zip(b).all { it.first.event.id == it.second.event.id }

    private var globalLoadJob: kotlinx.coroutines.Job? = null
    fun loadGlobalTimeline(isRefresh: Boolean = false) {
        if (!isRefresh && globalLoadJob?.isActive == true) return

        globalLoadJob?.cancel()
        globalLoadJob = viewModelScope.launch {
            _uiState.update {
                if (isRefresh) it.copy(isGlobalRefreshing = true, globalError = null)
                else it.copy(isGlobalLoading = true, globalError = null)
            }
            try {
                val posts = repository.fetchRecommendedTimeline(50).deduped()
                seenEventIds.addAll(posts.map { it.event.id })
                _uiState.update { state ->
                    state.copy(
                        // Keep the visible timeline on transient empty relay results.
                        globalPosts = if (posts.isNotEmpty()) (posts + state.globalPosts).timelineSortedDeduped() else state.globalPosts,
                        isGlobalLoading = false,
                        isGlobalRefreshing = false,
                        hasNewRecommendations = if (posts.isNotEmpty()) false else state.hasNewRecommendations,
                        globalPageCursor = mergedCursorAfter(state.globalPageCursor, posts),
                        hasMoreGlobal = if (posts.isNotEmpty()) true else state.hasMoreGlobal
                    )
                }
                if (posts.isNotEmpty()) fetchBirdwatchForPosts(posts)
            } catch (e: Exception) {
                _uiState.update {
                    it.copy(
                        globalError = if (isRefresh) "更新に失敗しました" else "おすすめの読み込みに失敗しました",
                        isGlobalLoading = false,
                        isGlobalRefreshing = false
                    )
                }
            }
        }
    }

    fun deletePost(eventId: String) {
        viewModelScope.launch {
            try {
                val success = repository.deleteEvent(eventId)
                if (success) {
                    _uiState.update { state ->
                        state.copy(
                            globalPosts = state.globalPosts.filter { it.event.id != eventId },
                            followingPosts = state.followingPosts.filter { it.event.id != eventId }
                        )
                    }
                }
            } catch (e: Exception) { /* ignore */ }
        }
    }

    private var followingLoadJob: kotlinx.coroutines.Job? = null
    fun loadFollowingTimeline(isRefresh: Boolean = false) {
        if (!isRefresh && followingLoadJob?.isActive == true) return

        followingLoadJob?.cancel()
        followingLoadJob = viewModelScope.launch {
            _uiState.update {
                if (isRefresh) it.copy(isFollowingRefreshing = true, followingError = null)
                else it.copy(
                    isFollowingLoading = it.followingPosts.isEmpty(),
                    followingError = null
                )
            }
            try {
                val posts = repository.fetchFollowTimeline(pubkeyHex, 50).deduped()
                seenEventIds.addAll(posts.map { it.event.id })
                _uiState.update { state ->
                    state.copy(
                        // Relay timeouts / EOSE-without-events are common on Nostr.
                        // Treat an empty result as "no fresh data" when we already
                        // have posts, otherwise a transient refresh can blank the
                        // user's primary kind-1 timeline.
                        followingPosts = if (posts.isNotEmpty()) (posts + state.followingPosts).timelineSortedDeduped() else state.followingPosts,
                        isFollowingLoading = false,
                        isFollowingRefreshing = false,
                        hasNewFollowing = if (posts.isNotEmpty()) false else state.hasNewFollowing,
                        followingPageCursor = mergedCursorAfter(state.followingPageCursor, posts),
                        hasMoreFollowing = if (posts.isNotEmpty()) true else state.hasMoreFollowing
                    )
                }
                if (posts.isNotEmpty()) {
                    // Persist to cache (encode and write on IO thread). Never write
                    // an empty network response over a healthy cached timeline.
                    launch(Dispatchers.IO) {
                        try {
                            val json = kotlinx.serialization.json.Json { encodeDefaults = true }
                            repository.setCachedTimeline(json.encodeToString(kotlinx.serialization.builtins.ListSerializer(io.nurunuru.app.data.models.ScoredPost.serializer()), posts))
                        } catch (e: Exception) { /* ignore */ }
                    }

                    fetchBirdwatchForPosts(posts)
                }
            } catch (e: Exception) {
                _uiState.update {
                    it.copy(
                        followingError = if (isRefresh) "更新に失敗しました" else "フォロー中の読み込みに失敗しました",
                        isFollowingLoading = false,
                        isFollowingRefreshing = false
                    )
                }
            }
        }
    }

    fun refresh() {
        when (_uiState.value.feedType) {
            FeedType.GLOBAL -> {
                _uiState.update { it.copy(pendingGlobalPosts = emptyList(), hasMoreGlobal = true, globalPageCursor = null) }
                loadGlobalTimeline(isRefresh = true)
            }
            FeedType.FOLLOWING -> {
                _uiState.update { it.copy(pendingFollowingPosts = emptyList(), hasMoreFollowing = true, followingPageCursor = null) }
                loadFollowingTimeline(isRefresh = true)
            }
        }
    }

    /** Load older posts when the user scrolls near the end of the timeline. */
    fun loadMore(feedType: FeedType = _uiState.value.feedType) {
        val state = _uiState.value
        if (state.selectedRelayUrl != null && feedType == FeedType.GLOBAL) {
            val relayUrl = state.selectedRelayUrl
            if (state.isGlobalLoadingMore || !state.hasMoreRelay || state.relayPosts.isEmpty()) return
            viewModelScope.launch {
                val until = state.relayPageCursor ?: ((state.relayPosts.minOfOrNull { it.event.createdAt } ?: return@launch) - 1)
                _uiState.update { it.copy(isGlobalLoadingMore = true) }
                runCatching { repository.fetchRelayTimelinePage(relayUrl, until, 50).deduped() }
                    .onSuccess { older ->
                        seenRelayEventIds.addAll(older.map { it.event.id })
                        _uiState.update { st -> st.copy(
                            relayPosts = (st.relayPosts + older).timelineSortedDeduped(),
                            isGlobalLoadingMore = false,
                            hasMoreRelay = older.isNotEmpty(),
                            relayPageCursor = older.olderCursorOrNull() ?: st.relayPageCursor
                        ) }
                        if (older.isNotEmpty()) reEnrichMissingProfiles(older)
                    }
                    .onFailure { _uiState.update { it.copy(isGlobalLoadingMore = false) } }
            }
            return
        }
        when (feedType) {
            FeedType.GLOBAL -> {
                if (state.isGlobalLoadingMore || !state.hasMoreGlobal || state.globalPosts.isEmpty()) return
                viewModelScope.launch {
                    val until = state.globalPageCursor ?: ((state.globalPosts.minOfOrNull { it.event.createdAt } ?: return@launch) - 1)
                    _uiState.update { it.copy(isGlobalLoadingMore = true) }
                    runCatching { repository.fetchGlobalTimelinePage(until, 50).deduped() }
                        .onSuccess { older ->
                            seenEventIds.addAll(older.map { it.event.id })
                            _uiState.update { st ->
                                st.copy(
                                    globalPosts = (st.globalPosts + older).timelineSortedDeduped(),
                                    isGlobalLoadingMore = false,
                                    hasMoreGlobal = older.isNotEmpty(),
                                    globalPageCursor = older.olderCursorOrNull() ?: st.globalPageCursor
                                )
                            }
                            if (older.isNotEmpty()) reEnrichMissingProfiles(older)
                        }
                        .onFailure { _uiState.update { it.copy(isGlobalLoadingMore = false) } }
                }
            }
            FeedType.FOLLOWING -> {
                if (state.isFollowingLoadingMore || !state.hasMoreFollowing || state.followingPosts.isEmpty()) return
                viewModelScope.launch {
                    val until = state.followingPageCursor ?: ((state.followingPosts.minOfOrNull { it.event.createdAt } ?: return@launch) - 1)
                    _uiState.update { it.copy(isFollowingLoadingMore = true) }
                    runCatching { repository.fetchFollowTimelinePage(pubkeyHex, until, 50).deduped() }
                        .onSuccess { older ->
                            seenEventIds.addAll(older.map { it.event.id })
                            _uiState.update { st ->
                                st.copy(
                                    followingPosts = (st.followingPosts + older).timelineSortedDeduped(),
                                    isFollowingLoadingMore = false,
                                    hasMoreFollowing = older.isNotEmpty(),
                                    followingPageCursor = older.olderCursorOrNull() ?: st.followingPageCursor
                                )
                            }
                            if (older.isNotEmpty()) reEnrichMissingProfiles(older)
                        }
                        .onFailure { _uiState.update { it.copy(isFollowingLoadingMore = false) } }
                }
            }
        }
    }

    /**
     * 新着ピルのタップ処理。
     * リレー/フォロータブともに pending を先頭に prepend する。
     */
    fun flushPendingPosts(feedType: FeedType = _uiState.value.feedType) {
        // リレー選択中は pendingRelayPosts を relayPosts に prepend
        if (feedType == FeedType.GLOBAL && _uiState.value.selectedRelayUrl != null) {
            val added = _uiState.value.pendingRelayPosts
            _uiState.update { state ->
                android.util.Log.d("TimelineViewModel",
                    "Relay live pill tapped: prepending ${added.size} posts")
                state.copy(
                    relayPosts = (added + state.relayPosts).deduped(),
                    pendingRelayPosts = emptyList(),
                    hasNewRecommendations = false
                )
            }
            reEnrichMissingProfiles(added)
            return
        }
        when (feedType) {
            FeedType.GLOBAL -> {
                val added = _uiState.value.pendingGlobalPosts
                _uiState.update { state ->
                    android.util.Log.d("TimelineViewModel",
                        "Relay pill tapped: prepending ${added.size} posts → total ${added.size + state.globalPosts.size}")
                    state.copy(
                        globalPosts = (added + state.globalPosts).deduped(),
                        pendingGlobalPosts = emptyList(),
                        hasNewRecommendations = false
                    )
                }
                reEnrichMissingProfiles(added)
            }
            FeedType.FOLLOWING -> {
                val added = _uiState.value.pendingFollowingPosts
                _uiState.update { state ->
                    android.util.Log.d("TimelineViewModel",
                        "Follow pill tapped: prepending ${state.pendingFollowingPosts.size} posts")
                    state.copy(
                        followingPosts = (added + state.followingPosts).deduped(),
                        pendingFollowingPosts = emptyList()
                    )
                }
                reEnrichMissingProfiles(added)
            }
        }
    }

    /**
     * プロフィール未取得の投稿について、バックグラウンドで再取得し表示を更新する。
     */
    private fun reEnrichMissingProfiles(posts: List<ScoredPost>) {
        val missing = posts.filter { p ->
            p.profile?.picture == null && p.profile?.displayName == null && p.profile?.name == null
        }
        if (missing.isEmpty()) return

        viewModelScope.launch(Dispatchers.IO) {
            val pubkeys = missing.map { it.event.pubkey }.distinct()
            val profiles = try { repository.fetchProfiles(pubkeys) } catch (_: Exception) { return@launch }

            // 取得できたプロフィールで表示中リストを更新
            val resolved = profiles.filter { (_, v) ->
                v.picture != null || v.displayName != null || v.name != null
            }
            if (resolved.isEmpty()) return@launch

            android.util.Log.d("TimelineViewModel",
                "reEnrichMissingProfiles: resolved ${resolved.size}/${pubkeys.size}")

            withContext(Dispatchers.Main) {
                _uiState.update { state ->
                    state.copy(
                        globalPosts = state.globalPosts.updateProfiles(resolved),
                        followingPosts = state.followingPosts.updateProfiles(resolved),
                        relayPosts = state.relayPosts.updateProfiles(resolved)
                    )
                }
            }
        }
    }

    private fun List<ScoredPost>.updateProfiles(
        profiles: Map<String, io.nurunuru.app.data.models.UserProfile>
    ): List<ScoredPost> {
        if (profiles.isEmpty()) return this
        return map { post ->
            val newProfile = profiles[post.event.pubkey]
            if (newProfile != null && (post.profile?.picture == null && post.profile?.displayName == null && post.profile?.name == null)) {
                post.copy(profile = newProfile)
            } else post
        }
    }

    private fun fetchBirdwatchForPosts(posts: List<ScoredPost>) {
        if (posts.isEmpty()) return
        viewModelScope.launch {
            try {
                val ids = posts.map { it.event.id }
                val notes = repository.fetchBirdwatchNotes(ids)
                _uiState.update { state ->
                    val newNotes = state.birdwatchNotes.toMutableMap()
                    newNotes.putAll(notes)
                    state.copy(birdwatchNotes = newNotes)
                }
            } catch (e: Exception) { /* Silently ignore */ }
        }
    }

    fun switchFeed(feedType: FeedType) {
        if (_uiState.value.feedType == feedType) return
        _uiState.update {
            it.copy(
                feedType = feedType,
                hasNewRecommendations = if (feedType == FeedType.GLOBAL) false else it.hasNewRecommendations,
                hasNewFollowing = if (feedType == FeedType.FOLLOWING) false else it.hasNewFollowing
            )
        }
        if (feedType == FeedType.GLOBAL && _uiState.value.globalPosts.isEmpty()) {
            loadGlobalTimeline()
        } else if (feedType == FeedType.FOLLOWING && _uiState.value.followingPosts.isEmpty()) {
            loadFollowingTimeline()
        }
    }

    fun search(query: String) {
        if (query.isBlank()) {
            _uiState.update { it.copy(searchQuery = "", searchResults = emptyList(), isSearching = false) }
            return
        }

        val trimmedQuery = query.trim()
        repository.saveRecentSearch(trimmedQuery)
        _uiState.update { it.copy(
            searchQuery = trimmedQuery,
            isSearching = true,
            recentSearches = repository.getRecentSearches()
        ) }

        viewModelScope.launch {
            try {
                // 1. Check for npub or hex pubkey
                val pubkey = NostrKeyUtils.parsePublicKey(trimmedQuery)
                if (pubkey != null && trimmedQuery.startsWith("npub")) {
                    _navigationEvents.emit(SearchNavigationEvent.OpenProfile(pubkey))
                    _uiState.update { it.copy(isSearching = false) }
                    return@launch
                }

                // 2. Check for NIP-05
                if (trimmedQuery.contains("@") && !trimmedQuery.contains(" ")) {
                    val resolved = Nip05Utils.resolveNip05(trimmedQuery)
                    if (resolved != null) {
                        _navigationEvents.emit(SearchNavigationEvent.OpenProfile(resolved))
                        _uiState.update { it.copy(isSearching = false) }
                        return@launch
                    }
                }

                // 3. Check for specific event (note, nevent, or 64-char hex)
                val isHex64 = trimmedQuery.length == 64 && trimmedQuery.all { it.isDigit() || it.lowercaseChar() in 'a'..'f' }
                if (trimmedQuery.startsWith("note") || trimmedQuery.startsWith("nevent") || isHex64) {
                    val eventId = if (isHex64) trimmedQuery.lowercase()
                        else NostrKeyUtils.parseNostrLink(trimmedQuery)?.id
                    val event = eventId?.let { repository.fetchEvent(it) }
                    if (event != null) {
                        _uiState.update { it.copy(searchResults = listOf(event), isSearching = false) }
                        return@launch
                    } else if (isHex64) {
                        // If 64 char hex failed as event, try as pubkey
                        _navigationEvents.emit(SearchNavigationEvent.OpenProfile(trimmedQuery.lowercase()))
                        _uiState.update { it.copy(isSearching = false) }
                        return@launch
                    }
                }

                // 4. オペレータ付き高度検索 or 通常テキスト検索
                val parsed = SearchQueryParser.parse(trimmedQuery)
                val results = if (parsed.hasOperators) {
                    val resolvedNip05 = parsed.fromNip05.mapNotNull { Nip05Utils.resolveNip05(it) }
                    repository.advancedSearch(parsed, resolvedNip05, 30)
                } else {
                    repository.searchNotes(trimmedQuery, 30)
                }
                _uiState.update { it.copy(searchResults = results, isSearching = false) }
            } catch (e: Exception) {
                _uiState.update { it.copy(isSearching = false) }
            }
        }
    }

    fun clearSearch() {
        _uiState.update { it.copy(searchQuery = "", searchResults = emptyList(), isSearching = false) }
    }

    fun removeRecentSearch(query: String) {
        repository.removeRecentSearch(query)
        loadRecentSearches()
    }

    fun clearRecentSearches() {
        repository.clearRecentSearches()
        loadRecentSearches()
    }

    fun loadSavedRelays() {
        val urls = repository.getSavedRelayUrls()
        _uiState.update { it.copy(savedRelayUrls = urls) }
    }

    fun selectRelayFeed(url: String?) {
        // 旧ライブストリームを停止してバッファをリセット
        relayLiveJob?.cancel()
        relayLiveJob = null
        seenRelayEventIds.clear()
        synchronized(liveRelayBuffer) { liveRelayBuffer.clear() }
        _uiState.update { it.copy(selectedRelayUrl = url, pendingRelayPosts = emptyList(), hasMoreRelay = true, relayPageCursor = null) }
        if (url != null) {
            loadRelayFeed(url)
        } else {
            _uiState.update { it.copy(relayPosts = emptyList()) }
        }
    }

    private fun loadRelayFeed(relayUrl: String) {
        viewModelScope.launch {
            _uiState.update { it.copy(isRelayFeedLoading = true) }
            val posts = try { repository.fetchRelayTimeline(relayUrl, 50) }
                        catch (_: Exception) { emptyList() }
            if (posts.isEmpty()) {
                // タイムアウトまたは接続失敗 → リレー選択を解除して通常フィードに戻す
                android.util.Log.d("TimelineViewModel",
                    "loadRelayFeed: $relayUrl returned 0 events, auto-deselecting")
                _uiState.update { it.copy(
                    selectedRelayUrl = null,
                    relayPosts = emptyList(),
                    isRelayFeedLoading = false
                ) }
            } else {
                // 初回取得イベントを既読としてマーク（ライブストリームとの重複防止）
                seenRelayEventIds.addAll(posts.map { it.event.id })
                _uiState.update { it.copy(relayPosts = posts, isRelayFeedLoading = false, relayPageCursor = posts.olderCursorOrNull(), hasMoreRelay = true) }
                // 初回ロード成功後にライブストリーム開始
                startRelayLiveStream(relayUrl)
            }
        }
    }

    private fun startRelayLiveStream(relayUrl: String) {
        android.util.Log.d("TimelineViewModel", "Relay live stream starting: $relayUrl")
        relayLiveJob = viewModelScope.launch {
            try {
                repository.openRelayLiveStream(relayUrl)
                    .collect { event ->
                        android.util.Log.d("TimelineViewModel", "Relay live event received: ${event.id.take(8)}")
                        if (event.id in seenRelayEventIds) return@collect
                        seenRelayEventIds.add(event.id)

                        // ミュートフィルタ
                        val muteData = repository.getCachedMuteList(pubkeyHex)
                        if (muteData != null) {
                            if (event.pubkey in muteData.pubkeys.toSet()) return@collect
                            if (event.id in muteData.eventIds.toSet()) return@collect
                        }

                        val post = withContext(Dispatchers.IO) {
                            val profiles = repository.fetchProfiles(listOf(event.pubkey))
                            ScoredPost(
                                event = event,
                                profile = profiles[event.pubkey],
                                likeCount = 0, repostCount = 0, replyCount = 0,
                                zapAmount = 0L, score = 1.0,
                                isLiked = false, isReposted = false
                            )
                        }

                        // リレー固有ストリームは投稿頻度が低いため 1件でピルを表示
                        synchronized(liveRelayBuffer) { liveRelayBuffer.add(post) }
                        val buffered = synchronized(liveRelayBuffer) {
                            val copy = liveRelayBuffer.sortedByDescending { it.event.createdAt }
                            liveRelayBuffer.clear()
                            copy
                        }
                        android.util.Log.d("TimelineViewModel",
                            "Relay live pill ready: ${buffered.size} posts pending")
                        _uiState.update { state ->
                            state.copy(
                                pendingRelayPosts = (buffered + state.pendingRelayPosts).deduped(),
                                hasNewRecommendations = state.hasNewRecommendations || state.feedType != FeedType.GLOBAL
                            )
                        }
                    }
            } catch (e: Exception) {
                android.util.Log.w("TimelineViewModel", "Relay live stream ended: ${e.message}")
            }
        }
    }

    fun likePost(eventId: String, emoji: String = "+", customTags: List<List<String>> = emptyList()) {
        if (!inFlightLikeEventIds.add(eventId)) return
        viewModelScope.launch {
            try {
            val post = (_uiState.value.globalPosts + _uiState.value.followingPosts +
                        _uiState.value.searchResults + _uiState.value.relayPosts)
                .firstOrNull { it.event.id == eventId }
            // Toggle: if already liked, unlike (delete reaction event)
            if (post?.isLiked == true) {
                val reactionEventId = post.myLikeEventId ?: return@launch
                val success = repository.deleteEvent(reactionEventId)
                if (success) {
                    repository.removeCachedUserLikedPost(pubkeyHex, eventId)
                    updatePostInteraction(eventId, isLike = true, undo = true)
                }
                return@launch
            }
            val authorPubkey = post?.event?.pubkey ?: ""
            val newEventId = repository.likePost(eventId, authorPubkey, emoji, customTags)
            if (newEventId != null) {
                updatePostInteraction(eventId, isLike = true, newEventId = newEventId)
                post?.let { repository.cacheUserLikedPost(pubkeyHex, it.copy(isLiked = true, myLikeEventId = newEventId)) }
                if (authorPubkey.isNotEmpty()) repository.recordEngagement("like", authorPubkey)
            }
            } finally {
                inFlightLikeEventIds.remove(eventId)
            }
        }
    }

    fun repostPost(eventId: String) {
        if (!inFlightRepostEventIds.add(eventId)) return
        viewModelScope.launch {
            try {
            val post = (_uiState.value.globalPosts + _uiState.value.followingPosts +
                        _uiState.value.searchResults + _uiState.value.relayPosts)
                .firstOrNull { it.event.id == eventId }
            // Toggle: if already reposted, unrepost (delete repost event)
            if (post?.isReposted == true) {
                val repostEventId = post.myRepostEventId ?: return@launch
                val success = repository.deleteEvent(repostEventId)
                if (success) updatePostInteraction(eventId, isLike = false, undo = true)
                return@launch
            }
            val eventJson = post?.event?.let {
                try { kotlinx.serialization.json.Json { encodeDefaults = true }.encodeToString(
                    io.nurunuru.app.data.models.NostrEvent.serializer(), it)
                } catch (_: Exception) { null }
            }
            val newEventId = repository.repostPost(eventId, eventJson)
            if (newEventId != null) {
                updatePostInteraction(eventId, isLike = false, newEventId = newEventId)
                val authorPubkey = post?.event?.pubkey
                if (authorPubkey != null) repository.recordEngagement("repost", authorPubkey)
            }
            } finally {
                inFlightRepostEventIds.remove(eventId)
            }
        }
    }

    private fun updatePostInteraction(eventId: String, isLike: Boolean, undo: Boolean = false, newEventId: String? = null) {
        _uiState.update { state ->
            val updateFunc: (ScoredPost) -> ScoredPost = { post ->
                if (post.event.id == eventId) {
                    if (isLike) {
                        if (undo) post.copy(isLiked = false, likeCount = maxOf(0, post.likeCount - 1), myLikeEventId = null)
                        else post.copy(isLiked = true, likeCount = post.likeCount + 1, myLikeEventId = newEventId ?: post.myLikeEventId)
                    } else {
                        if (undo) post.copy(isReposted = false, repostCount = maxOf(0, post.repostCount - 1), myRepostEventId = null)
                        else post.copy(isReposted = true, repostCount = post.repostCount + 1, myRepostEventId = newEventId ?: post.myRepostEventId)
                    }
                } else post
            }
            state.copy(
                globalPosts = state.globalPosts.map(updateFunc),
                followingPosts = state.followingPosts.map(updateFunc),
                searchResults = state.searchResults.map(updateFunc),
                relayPosts = state.relayPosts.map(updateFunc)
            )
        }
    }

    fun publishNote(content: String, contentWarning: String? = null) {
        viewModelScope.launch {
            try {
                repository.publishNote(content, contentWarning = contentWarning)
            } catch (e: Exception) { /* Silently ignore */ }
            refresh()
        }
    }

    fun muteUser(pubkey: String) {
        viewModelScope.launch {
            try {
                repository.muteUser(pubkey)
                _uiState.update { state ->
                    state.copy(
                        globalPosts = state.globalPosts.filter { it.event.pubkey != pubkey },
                        followingPosts = state.followingPosts.filter { it.event.pubkey != pubkey }
                    )
                }
            } catch (e: Exception) { /* Silently ignore */ }
        }
    }

    fun reportEvent(eventId: String?, pubkey: String, type: String, content: String) {
        viewModelScope.launch {
            try {
                repository.reportEvent(pubkey, eventId, type, content)
            } catch (e: Exception) { /* Silently ignore */ }
        }
    }

    fun toggleBookmark(eventId: String, isCurrentlyBookmarked: Boolean) {
        viewModelScope.launch {
            try {
                if (isCurrentlyBookmarked) {
                    repository.removeBookmark(pubkeyHex, eventId)
                } else {
                    repository.addBookmark(pubkeyHex, eventId)
                }
                updatePostBookmark(eventId, !isCurrentlyBookmarked)
            } catch (e: Exception) { }
        }
    }

    private fun updatePostBookmark(eventId: String, isBookmarked: Boolean) {
        _uiState.update { state ->
            state.copy(
                globalPosts = state.globalPosts.map { if (it.event.id == eventId) it.copy(isBookmarked = isBookmarked) else it },
                followingPosts = state.followingPosts.map { if (it.event.id == eventId) it.copy(isBookmarked = isBookmarked) else it }
            )
        }
    }

    fun submitBirdwatch(eventId: String, authorPubkey: String, type: String, content: String, url: String) {
        viewModelScope.launch {
            try {
                repository.publishBirdwatchLabel(eventId, authorPubkey, type, content, url)
                // Refresh birdwatch notes for this post
                fetchBirdwatchForPosts(listOf(_uiState.value.globalPosts.find { it.event.id == eventId } ?: return@launch))
            } catch (e: Exception) { /* Silently ignore */ }
        }
    }

    fun setNotInterested(eventId: String) {
        // Get the author pubkey before filtering
        val authorPubkey = (_uiState.value.globalPosts + _uiState.value.followingPosts)
            .firstOrNull { it.event.id == eventId }?.event?.pubkey

        _uiState.update { state ->
            state.copy(
                globalPosts = state.globalPosts.filter { it.event.id != eventId },
                followingPosts = state.followingPosts.filter { it.event.id != eventId }
            )
        }

        // Persist to engagement tracker (synced with web lib/recommendation.js markNotInterested)
        if (authorPubkey != null) {
            viewModelScope.launch {
                try {
                    repository.markNotInterested(eventId, authorPubkey)
                } catch (_: Exception) { }
            }
        }
    }

    override fun onCleared() {
        super.onCleared()
        liveSubId?.let { repository.stopLiveStream(it) }
        liveSubId = null
        relayLiveJob?.cancel()
        relayLiveJob = null
    }

    class Factory(
        private val repository: NostrRepository,
        private val pubkeyHex: String
    ) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : androidx.lifecycle.ViewModel> create(modelClass: Class<T>): T =
            TimelineViewModel(repository, pubkeyHex) as T
    }
}
