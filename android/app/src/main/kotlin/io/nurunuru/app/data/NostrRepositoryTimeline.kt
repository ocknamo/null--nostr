package io.nurunuru.app.data

import io.nurunuru.app.data.models.*
import kotlinx.coroutines.*
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

// ─── Timeline ─────────────────────────────────────────────────────────────────

private const val TIMELINE_PAGE_WINDOW_SECS: Long = 60L * 60L * 6L
private const val TIMELINE_FIRST_PAGE_TIMEOUT_MS: Long = 2_500L
private const val TIMELINE_MORE_TIMEOUT_MS: Long = 3_500L
private const val TIMELINE_FOLLOW_CHUNK_SIZE: Int = 80
private const val TIMELINE_ACTIVE_AUTHOR_SAMPLE: Int = 240
private const val TIMELINE_RECENT_REPOST_GRACE_SECS: Long = 3L * 24L * 60L * 60L

/** General fetchEvents method. */
suspend fun NostrRepository.fetchEvents(filter: NostrClient.Filter, timeoutMs: Long = 5_000): List<NostrEvent> {
    return client.fetchEvents(filter, timeoutMs)
}

/** Fetch from explicit relays. Used for reply/detail screens where the event may live on NIP-65 read/write relays not in the current pool. */
suspend fun NostrRepository.fetchEventsFromRelays(
    relayUrls: List<String>,
    filter: NostrClient.Filter,
    timeoutMs: Long = 5_000
): List<NostrEvent> {
    return client.fetchEventsFrom(relayUrls.distinct(), filter, timeoutMs)
}

suspend fun NostrRepository.fetchGlobalTimelineFast(limit: Int = 50): List<ScoredPost> = withContext(Dispatchers.IO) {
    val filter = NostrClient.Filter(
        kinds = listOf(NostrKind.TEXT_NOTE, NostrKind.VIDEO_LOOP, NostrKind.LONG_FORM, NostrKind.REPOST),
        since = getOneHourAgo(),
        limit = limit
    )
    val events = client.fetchEvents(filter, timeoutMs = 2_500)
        .distinctBy { it.id }
        .filter { it.getTagValues("e").isEmpty() }
        .sortedByDescending { it.createdAt }
    cache.setCachedEvents(events)
    val muted = getCachedMuteList(myPubkeyHex)?.pubkeys?.toSet() ?: emptySet()
    events.filter { it.pubkey !in muted }.map { ev ->
        ScoredPost(event = ev, profile = getCachedProfile(ev.pubkey))
    }
}

suspend fun NostrRepository.fetchFollowingTimelineFast(authors: List<String>, limit: Int = 50): List<ScoredPost> = withContext(Dispatchers.IO) {
    if (authors.isEmpty()) return@withContext emptyList()
    val since = System.currentTimeMillis() / 1000 - 2 * Constants.Time.DAY_SECS
    val allEvents = fetchTimelineChunkedByAuthors(
        authors = authors,
        since = since,
        limit = limit,
        timeoutMs = TIMELINE_FIRST_PAGE_TIMEOUT_MS
    )
    cache.setCachedEvents(allEvents)
    postsFromRawTimelineEvents(allEvents).take(limit)
}

suspend fun NostrRepository.enrichTimelinePosts(posts: List<ScoredPost>): List<ScoredPost> = withContext(Dispatchers.IO) {
    enrichPosts(posts.map { it.event })
}

fun NostrRepository.unwrapTimelineEvents(events: List<NostrEvent>): List<NostrEvent> {
    val out = mutableListOf<NostrEvent>()
    for (event in events) {
        if (event.kind == NostrKind.REPOST) {
            val inner = runCatching { Json.decodeFromString<NostrEvent>(event.content) }.getOrNull()
            if (inner != null && (inner.kind == NostrKind.TEXT_NOTE || inner.kind == NostrKind.VIDEO_LOOP || inner.kind == NostrKind.LONG_FORM)) {
                out += inner.copy(createdAt = event.createdAt)
            }
        } else {
            out += event
        }
    }
    return out
}

fun NostrRepository.postsFromRawTimelineEvents(events: List<NostrEvent>): List<ScoredPost> {
    val muted = getCachedMuteList(myPubkeyHex)?.pubkeys?.toSet() ?: emptySet()
    return unwrapTimelineEvents(events)
        .distinctBy { it.id }
        .filter { it.pubkey !in muted && it.getTagValues("e").isEmpty() }
        .sortedByDescending { it.createdAt }
        .map { ev -> ScoredPost(event = ev, profile = getCachedProfile(ev.pubkey)) }
}

private fun List<NostrEvent>.activeAuthors(limit: Int): List<String> =
    asSequence()
        .filter { it.kind != NostrKind.REPOST }
        .sortedByDescending { it.createdAt }
        .map { it.pubkey }
        .distinct()
        .take(limit)
        .toList()

private suspend fun NostrRepository.fetchTimelineChunkedByAuthors(
    authors: List<String>,
    since: Long,
    until: Long? = null,
    limit: Int,
    timeoutMs: Long
): List<NostrEvent> = coroutineScope {
    val uniqueAuthors = authors.distinct()
    if (uniqueAuthors.isEmpty()) return@coroutineScope emptyList()
    val chunkCount = maxOf(1, (uniqueAuthors.size + TIMELINE_FOLLOW_CHUNK_SIZE - 1) / TIMELINE_FOLLOW_CHUNK_SIZE)
    val perChunkLimit = maxOf(20, limit / chunkCount + 12)
    uniqueAuthors.chunked(TIMELINE_FOLLOW_CHUNK_SIZE).map { chunk ->
        async(Dispatchers.IO) {
            runCatching {
                client.fetchEvents(
                    NostrClient.Filter(
                        kinds = listOf(NostrKind.TEXT_NOTE, NostrKind.VIDEO_LOOP, NostrKind.LONG_FORM, NostrKind.REPOST),
                        authors = chunk,
                        since = since,
                        until = until,
                        limit = perChunkLimit
                    ),
                    timeoutMs = timeoutMs
                )
            }.getOrDefault(emptyList())
        }
    }.awaitAll().flatten()
        .distinctBy { it.id }
        .sortedByDescending { it.createdAt }
        .take(limit)
}

private suspend fun NostrRepository.fetchTimelineWithRelayHints(
    authors: List<String>,
    since: Long,
    until: Long? = null,
    limit: Int,
    timeoutMs: Long
): List<NostrEvent> = coroutineScope {
    val base = async(Dispatchers.IO) { fetchTimelineChunkedByAuthors(authors, since, until, limit, timeoutMs) }
    val hinted = async(Dispatchers.IO) {
        runCatching {
            val plan = OutboxModel(client).getOptimalFetchRelays(authors.take(160))
            val selected = plan.entries
                .filter { (relay, group) -> group.isNotEmpty() && Validation.isValidRelayUrl(relay) }
                .sortedByDescending { it.value.size }
                .take(6)
            selected.map { (relay, group) ->
                async(Dispatchers.IO) {
                    runCatching {
                        client.fetchEventsFrom(
                            listOf(relay),
                            NostrClient.Filter(
                                kinds = listOf(NostrKind.TEXT_NOTE, NostrKind.VIDEO_LOOP, NostrKind.LONG_FORM, NostrKind.REPOST),
                                authors = group.take(TIMELINE_FOLLOW_CHUNK_SIZE),
                                since = since,
                                until = until,
                                limit = maxOf(20, limit / maxOf(1, selected.size) + 12)
                            ),
                            timeoutMs = timeoutMs
                        )
                    }.getOrDefault(emptyList())
                }
            }.awaitAll().flatten()
        }.getOrDefault(emptyList())
    }
    (base.await() + hinted.await()).distinctBy { it.id }.sortedByDescending { it.createdAt }.take(limit)
}

/** Fetch older global timeline posts before [until]. Used by infinite scroll. */
suspend fun NostrRepository.fetchGlobalTimelinePage(
    until: Long,
    limit: Int = 50
): List<ScoredPost> = withContext(Dispatchers.IO) {
    var cursor = until
    repeat(8) { attempt ->
        val since = cursor - TIMELINE_PAGE_WINDOW_SECS
        val filter = NostrClient.Filter(
            kinds = listOf(NostrKind.TEXT_NOTE, NostrKind.VIDEO_LOOP, NostrKind.LONG_FORM, NostrKind.REPOST),
            since = since,
            until = cursor,
            limit = limit
        )
        val events = client.fetchEvents(filter, timeoutMs = TIMELINE_MORE_TIMEOUT_MS)
            .distinctBy { it.id }
            .filter { it.getTagValues("e").isEmpty() }
            .sortedByDescending { it.createdAt }
        if (events.isNotEmpty()) {
            cache.setCachedEvents(events)
            return@withContext postsFromRawTimelineEvents(events).take(limit)
        }
        android.util.Log.d("NostrRepository", "global timeline page empty window attempt=" + (attempt + 1) + " until=" + cursor + " since=" + since)
        cursor = since - 1
    }
    emptyList()
}

/** Fetch older following timeline posts before [until]. Used by infinite scroll. */
suspend fun NostrRepository.fetchFollowTimelinePage(
    pubkeyHex: String,
    until: Long,
    limit: Int = 50
): List<ScoredPost> = withContext(Dispatchers.IO) {
    val followList = getCachedFollowList(pubkeyHex)?.takeIf { it.isNotEmpty() }
        ?: fetchFollowList(pubkeyHex)
    if (followList.isEmpty()) return@withContext emptyList()
    var cursor = until
    repeat(8) { attempt ->
        val since = cursor - TIMELINE_PAGE_WINDOW_SECS
        val discovery = fetchTimelineChunkedByAuthors(
            authors = followList.take(500),
            since = since,
            until = cursor,
            limit = TIMELINE_ACTIVE_AUTHOR_SAMPLE,
            timeoutMs = 1_800L
        )
        val activeAuthors = discovery.activeAuthors(TIMELINE_ACTIVE_AUTHOR_SAMPLE)
        val targetAuthors = if (activeAuthors.isNotEmpty()) activeAuthors else followList.take(500)
        val events = fetchTimelineWithRelayHints(
            authors = targetAuthors,
            since = since,
            until = cursor,
            limit = limit,
            timeoutMs = TIMELINE_MORE_TIMEOUT_MS
        ).ifEmpty { discovery }
        if (events.isNotEmpty()) {
            cache.setCachedEvents(events)
            return@withContext postsFromRawTimelineEvents(events).take(limit)
        }
        android.util.Log.d("NostrRepository", "follow timeline page empty window attempt=" + (attempt + 1) + " until=" + cursor + " since=" + since)
        cursor = since - 1
    }
    emptyList()
}

suspend fun NostrRepository.prefetchProfilesAndBadges(pubkeys: List<String>, limit: Int = 80) = coroutineScope {
    val targets = pubkeys.distinct().take(limit)
    if (targets.isEmpty()) return@coroutineScope
    launch(Dispatchers.IO) { runCatching { fetchProfiles(targets) } }
    targets.take(30).forEach { pk -> launch(Dispatchers.IO) { runCatching { fetchProfileBadgesInfo(pk) } } }
}

suspend fun NostrRepository.fetchRecommendedTimeline(limit: Int = 50): List<ScoredPost> =
    withContext(Dispatchers.IO) {
        try {
            fetchRecommendedFromMainRelay(limit)
        } catch (e: Exception) {
            android.util.Log.e("NostrRepository", "fetchRecommendedTimeline failed: ${e.message}", e)
            emptyList()
        }
    }

/**
 * メインリレーから kind 1 を時系列で取得し、ミュートフィルタのみ適用する。
 */
private suspend fun NostrRepository.fetchRecommendedFromMainRelay(limit: Int): List<ScoredPost> {
    val mainRelay = prefs.mainRelay
    val myPubkey = prefs.publicKeyHex ?: ""

    val relaysToTry = listOf(mainRelay) +
        io.nurunuru.app.data.models.DEFAULT_RELAYS.filter { it != mainRelay }.take(2)

    var events = emptyList<NostrEvent>()
    for (relay in relaysToTry) {
        events = try {
            client.fetchEventsFrom(
                listOf(relay),
                NostrClient.Filter(
                    kinds = listOf(NostrKind.TEXT_NOTE),
                    limit = limit
                ), timeoutMs = 5_000
            )
        } catch (_: Exception) { emptyList() }
        if (events.isNotEmpty()) break
    }

    // リプライ除外 (e タグあり = 他投稿へのリプライ)
    val rootPosts = events.filter { it.getTagValues("e").isEmpty() }

    val enriched = enrichPosts(rootPosts)

    val muteData = getCachedMuteList(myPubkey)
    val result = if (muteData != null &&
        (muteData.pubkeys.isNotEmpty() || muteData.eventIds.isNotEmpty())) {
        val mutedPks = muteData.pubkeys.toSet()
        val mutedIds = muteData.eventIds.toSet()
        enriched.filter { it.event.pubkey !in mutedPks && it.event.id !in mutedIds }
    } else enriched

    return result.sortedByDescending { it.event.createdAt }
}

suspend fun NostrRepository.fetchGlobalTimeline(limit: Int = 50): List<ScoredPost> {
    if (useRustCore) {
        return withContext(Dispatchers.IO) {
            try {
                val rustClient = client.getRustClient()
                    ?: return@withContext fetchGlobalTimelineLegacy(limit)

                val eventsJson = rustClient.fetchGlobalTimeline(limit.toUInt())
                android.util.Log.d("NostrRepository", "Rust fetchGlobalTimeline: ${eventsJson.size} events from relay")

                if (eventsJson.isEmpty()) {
                    return@withContext fetchGlobalTimelineLegacy(limit)
                }

                val events = eventsJson.mapNotNull { json ->
                    try { Json.decodeFromString<NostrEvent>(json) }
                    catch (e: Exception) {
                        android.util.Log.w("NostrRepository", "Event parse failed: ${e.message}")
                        null
                    }
                }.distinctBy { it.id }
                cache.setCachedEvents(events)
                postsFromRawTimelineEvents(events).take(limit)
            } catch (e: Exception) {
                android.util.Log.e("NostrRepository", "Rust fetchGlobalTimeline failed, falling back", e)
                fetchGlobalTimelineLegacy(limit)
            }
        }
    }
    return fetchGlobalTimelineLegacy(limit)
}

private suspend fun NostrRepository.fetchGlobalTimelineLegacy(limit: Int): List<ScoredPost> {
    val myPubkey = prefs.publicKeyHex ?: ""
    val oneHourAgo = getOneHourAgo()
    val threeHoursAgo = System.currentTimeMillis() / 1000 - 10800

    // 1. Fetch candidates in parallel
    val (allEvents, followList, secondDegreeFollows) = coroutineScope {
        val viralJob = async {
            client.fetchEvents(NostrClient.Filter(
                kinds = listOf(NostrKind.TEXT_NOTE, NostrKind.VIDEO_LOOP, NostrKind.LONG_FORM),
                limit = 100,
                since = oneHourAgo
            ), timeoutMs = 4000)
        }
        val recentJob = async {
            client.fetchEvents(NostrClient.Filter(
                kinds = listOf(NostrKind.TEXT_NOTE, NostrKind.VIDEO_LOOP, NostrKind.LONG_FORM),
                limit = 50,
                since = oneHourAgo
            ), timeoutMs = 4000)
        }
        val followListJob = async { fetchFollowList(myPubkey) }

        val viral = viralJob.await()
        val recent = recentJob.await()
        val follows = followListJob.await()

        // Build 2nd-degree network (friends of friends) — 改善3: dynamic sampling
        val secondDegree = if (follows.isNotEmpty()) {
            val sampleSize = maxOf(30, follows.size / 3)
            val sampleFollows = follows.shuffled().take(sampleSize)
            val followsOfFollows = fetchFollowListsBatch(sampleFollows)
            RecommendationEngine.extract2ndDegreeNetwork(follows, followsOfFollows)
        } else emptySet()

        // Fetch some posts from 2nd degree network
        val secondDegreePosts = if (secondDegree.isNotEmpty()) {
            client.fetchEvents(NostrClient.Filter(
                kinds = listOf(NostrKind.TEXT_NOTE, NostrKind.VIDEO_LOOP, NostrKind.LONG_FORM),
                authors = secondDegree.take(50).toList(),
                limit = 50,
                since = threeHoursAgo
            ), timeoutMs = 4000)
        } else emptyList()

        Triple(
            (viral + recent + secondDegreePosts).distinctBy { it.id }
                .filter { it.getTagValues("e").isEmpty() }, // リプライ除外
            follows.toSet(),
            secondDegree
        )
    }

    // 2. Enrich candidates with profiles and engagement data
    val enriched = enrichPosts(allEvents)

    // 3. Score and mix using RecommendationEngine (synced with Web algorithm)
    val profileMap = enriched.associate { it.event.pubkey to (it.profile ?: UserProfile(it.event.pubkey)) }
    val engagements = enriched.associate { it.event.id to RecommendationEngine.EngagementCounts(
        likes = it.likeCount,
        reposts = it.repostCount,
        replies = it.replyCount,
        // 改善2: Zap対数スケール
        zaps = if (it.zapAmount <= 0) 0
               else (kotlin.math.ln(it.zapAmount.toDouble() / 1000.0 + 1.0) * 10).toInt().coerceAtLeast(1)
    ) }

    val context = RecommendationEngine.ScoringContext(
        followList = followList,
        secondDegreeFollows = secondDegreeFollows,
        engagements = engagements,
        profiles = profileMap,
        userGeohash = prefs.userGeohash,
        mutedPubkeys = getCachedMuteList(myPubkey)?.pubkeys?.toSet() ?: emptySet()
    )

    return recommendationEngine.getRecommendedPosts(enriched, context, limit)
}

/**
 * Instant nostrdb cache-first read for following timeline.
 * Returns events already cached locally by previous relay fetches — no network call.
 * Used to show data immediately at startup before the relay fetch completes.
 */
suspend fun NostrRepository.fetchCachedFollowTimeline(pubkeyHex: String, limit: Int = 50): List<ScoredPost> {
    val rustClient = client.getRustClient() ?: return emptyList()
    val followList = getCachedFollowList(pubkeyHex) ?: return emptyList()
    if (followList.isEmpty()) return emptyList()
    return withContext(Dispatchers.IO) {
        try {
            val eventsJson = rustClient.queryLocal(followList.take(500), limit.toUInt())
            if (eventsJson.isEmpty()) return@withContext emptyList()
            val events = eventsJson.mapNotNull { json ->
                try { Json.decodeFromString<NostrEvent>(json) } catch (_: Exception) { null }
            }.distinctBy { it.id }
            android.util.Log.d("NostrRepository", "nostrdb cache-first: ${events.size} events")
            enrichPosts(events)
        } catch (e: Exception) {
            android.util.Log.w("NostrRepository", "nostrdb cache-first failed: ${e.message}")
            emptyList()
        }
    }
}

private suspend fun NostrRepository.cachedFollowTimelineFallback(pubkeyHex: String, limit: Int): List<ScoredPost> {
    return try {
        val cached = fetchCachedFollowTimeline(pubkeyHex, limit)
        if (cached.isNotEmpty()) {
            android.util.Log.w("NostrRepository", "follow timeline network empty; using " + cached.size + " cached posts")
        }
        cached
    } catch (e: Exception) {
        android.util.Log.w("NostrRepository", "follow timeline cache fallback failed: " + e.message)
        emptyList()
    }
}

/** Fetch timeline for followed users. */
suspend fun NostrRepository.fetchFollowTimeline(pubkeyHex: String, limit: Int = 50): List<ScoredPost> {
    if (useRustCore) {
        return withContext(Dispatchers.IO) {
            try {
                val rustClient = client.getRustClient()
                    ?: return@withContext fetchFollowTimelineLegacy(pubkeyHex, limit)

                val followList = fetchFollowList(pubkeyHex)
                if (followList.isEmpty()) return@withContext emptyList()

                val eventsJson = rustClient.fetchFollowTimeline(
                    followList.take(500),
                    limit.toUInt()
                )
                android.util.Log.d(
                    "NostrRepository",
                    "Rust fetchFollowTimeline: ${eventsJson.size} events (${followList.size} authors)"
                )

                if (eventsJson.isEmpty()) {
                    return@withContext fetchFollowTimelineLegacy(pubkeyHex, limit)
                }

                val events = eventsJson.mapNotNull { json ->
                    try { Json.decodeFromString<NostrEvent>(json) }
                    catch (e: Exception) {
                        android.util.Log.w("NostrRepository", "Event parse failed: ${e.message}")
                        null
                    }
                }.distinctBy { it.id }
                    .filter { it.getTagValues("e").isEmpty() } // リプライ除外
                if (events.isEmpty()) return@withContext emptyList()
                cache.setCachedEvents(events)
                postsFromRawTimelineEvents(events).take(limit)
            } catch (e: Exception) {
                android.util.Log.e("NostrRepository", "Rust fetchFollowTimeline failed, falling back", e)
                fetchFollowTimelineLegacy(pubkeyHex, limit)
                    .ifEmpty { cachedFollowTimelineFallback(pubkeyHex, limit) }
            }
        }
    }
    return fetchFollowTimelineLegacy(pubkeyHex, limit)
}

private suspend fun NostrRepository.fetchFollowTimelineLegacy(pubkeyHex: String, limit: Int): List<ScoredPost> {
    val followList = fetchFollowList(pubkeyHex)
    if (followList.isEmpty()) return emptyList()

    val filter = NostrClient.Filter(
        kinds = listOf(NostrKind.TEXT_NOTE, NostrKind.VIDEO_LOOP, NostrKind.LONG_FORM, NostrKind.REPOST),
        authors = followList.take(500),
        limit = limit,
        // Follow feeds can be quiet. A 1-hour window made healthy timelines look
        // empty; match the fast path's 48h window for a reliable kind-1 baseline.
        since = System.currentTimeMillis() / 1000 - 2 * Constants.Time.DAY_SECS
    )
    val events = client.fetchEvents(filter, timeoutMs = TIMELINE_FIRST_PAGE_TIMEOUT_MS).distinctBy { it.id }
        .filter { it.getTagValues("e").isEmpty() } // リプライ除外
    if (events.isEmpty()) return emptyList()
    cache.setCachedEvents(events)
    val muted = getCachedMuteList(myPubkeyHex)?.pubkeys?.toSet() ?: emptySet()
    return events.filter { it.pubkey !in muted }.map { ev ->
        ScoredPost(event = ev, profile = getCachedProfile(ev.pubkey))
    }
}

/** Search for notes by text (NIP-50) using dedicated search relay. */
suspend fun NostrRepository.searchNotes(query: String, limit: Int = 30): List<ScoredPost> {
    val filter = NostrClient.Filter(
        // search.nos.today/searchnos returns results for a bare NIP-50 search filter.
        // Kind filtering is applied client-side so relays that ignore combined
        // {search,kinds} filters still work.
        search = query,
        limit = limit
    )
    val events = client.fetchEventsFrom(
        listOf(NostrClient.SEARCH_RELAY), filter, timeoutMs = 6_000
    ).filter { it.kind == NostrKind.TEXT_NOTE || it.kind == NostrKind.VIDEO_LOOP }
    cache.setCachedEvents(events)
    val muted = getCachedMuteList(myPubkeyHex)?.pubkeys?.toSet() ?: emptySet()
    return events.filter { it.pubkey !in muted }.map { ev ->
        ScoredPost(event = ev, profile = getCachedProfile(ev.pubkey))
    }
}

/**
 * オペレータ付き高度検索。
 * - テキストあり → searchnos (NIP-50) に構造化フィルタを組み合わせて送信
 * - テキストなし → 標準リレーREQ（#t / authors / since / until のみ）
 * - クライアント側後処理: -除外語、"完全一致"、filter:image/video/link
 */
suspend fun NostrRepository.advancedSearch(
    parsed: ParsedSearchQuery,
    resolvedNip05Authors: List<String> = emptyList(),
    limit: Int = 30,
): List<ScoredPost> {
    // from: を hex pubkey に解決
    val fromHex = (parsed.fromPubkeys.mapNotNull { NostrKeyUtils.parsePublicKey(it) }
            + resolvedNip05Authors).distinct()

    val tagFilters = buildMap<String, List<String>> {
        if (parsed.hashtags.isNotEmpty()) put("t", parsed.hashtags)
    }.takeIf { it.isNotEmpty() }

    android.util.Log.d("SearchQuery", "text='${parsed.textQuery}' hashtags=${parsed.hashtags} " +
        "from=${fromHex} since=${parsed.since} until=${parsed.until} " +
        "exclude=${parsed.excludeWords} exact=${parsed.exactPhrases} media=${parsed.mediaFilter}")

    val rawEvents = if (parsed.textQuery.isNotEmpty()) {
        val filter = NostrClient.Filter(
            // Keep the relay-side NIP-50 filter broad for searchnos compatibility;
            // structured filters are still included, and kind/media/exclude checks
            // are enforced below on the client.
            search  = parsed.textQuery,
            authors = fromHex.takeIf { it.isNotEmpty() },
            tags    = tagFilters,
            since   = parsed.since,
            until   = parsed.until,
            limit   = limit,
        )
        client.fetchEventsFrom(listOf(NostrClient.SEARCH_RELAY), filter, timeoutMs = 6_000)
    } else {
        val filter = NostrClient.Filter(
            kinds   = listOf(NostrKind.TEXT_NOTE, NostrKind.VIDEO_LOOP),
            authors = fromHex.takeIf { it.isNotEmpty() },
            tags    = tagFilters,
            since   = parsed.since,
            until   = parsed.until,
            limit   = limit,
        )
        client.fetchEvents(filter, timeoutMs = 6_000)
    }

    // クライアント側後処理フィルタ
    val filtered = rawEvents.filter { event ->
        val c = event.content
        (event.kind == NostrKind.TEXT_NOTE || event.kind == NostrKind.VIDEO_LOOP) &&
        parsed.excludeWords.none  { w -> c.contains(w, ignoreCase = true) } &&
        parsed.exactPhrases.all   { p -> c.contains(p) } &&
        when (parsed.mediaFilter) {
            ParsedSearchQuery.MediaFilter.IMAGE ->
                NostrRepository.SEARCH_IMAGE_HOSTS.any { c.contains(it, ignoreCase = true) }
            ParsedSearchQuery.MediaFilter.VIDEO ->
                NostrRepository.SEARCH_VIDEO_HOSTS.any { c.contains(it, ignoreCase = true) }
            ParsedSearchQuery.MediaFilter.LINK  ->
                c.contains("http://") || c.contains("https://")
            null -> true
        }
    }
    android.util.Log.d("SearchQuery", "raw=${rawEvents.size} filtered=${filtered.size}")
    cache.setCachedEvents(filtered)
    return enrichPosts(filtered)
}

/**
 * バッチでフォロー中ユーザーの NIP-65 リレーリスト (kind 10002) を取得し、キャッシュに保存する。
 * 起動時にバックグラウンドで実行。TalkViewModel の DM 送信でキャッシュを参照。
 */
suspend fun NostrRepository.prefetchFollowRelayLists() = withContext(Dispatchers.IO) {
    val follows = followingSet.toList().take(200).ifEmpty { return@withContext }
    // Already cached? Skip those
    val uncached = follows.filter { cache.getCachedRelayList(it) == null }.take(100)
    if (uncached.isEmpty()) return@withContext

    android.util.Log.d("NostrRepository", "prefetchFollowRelayLists: fetching ${uncached.size} relay lists")
    val filter = NostrClient.Filter(
        kinds = listOf(NostrKind.RELAY_LIST),
        authors = uncached,
        limit = uncached.size
    )
    val events = client.fetchEvents(filter, timeoutMs = 10_000)
    // Store latest relay list per pubkey
    val latestPerPubkey = events.groupBy { it.pubkey }.mapValues { it.value.maxByOrNull { e -> e.createdAt }!! }
    for ((pubkey, event) in latestPerPubkey) {
        try {
            val relayList = event.tags.filter { it.firstOrNull() == "r" }.map { tag ->
                val url = tag.getOrElse(1) { "" }
                val marker = tag.getOrNull(2)
                Nip65Relay(url = url, read = marker == null || marker == "read", write = marker == null || marker == "write")
            }
            cache.setCachedRelayList(pubkey, Json.encodeToString(relayList))
        } catch (_: Exception) {}
    }
    android.util.Log.d("NostrRepository", "prefetchFollowRelayLists: cached ${latestPerPubkey.size} relay lists")
}
