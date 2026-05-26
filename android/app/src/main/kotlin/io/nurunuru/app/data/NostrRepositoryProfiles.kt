package io.nurunuru.app.data

import io.nurunuru.app.data.models.*
import kotlinx.coroutines.*
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

// ─── Profiles ─────────────────────────────────────────────────────────────────

suspend fun NostrRepository.fetchProfile(pubkeyHex: String): UserProfile? {
    val filter = NostrClient.Filter(
        kinds = listOf(NostrKind.METADATA),
        authors = listOf(pubkeyHex),
        limit = 1
    )
    val events = client.fetchEvents(filter, timeoutMs = 4_000)
    val event = events.maxByOrNull { it.createdAt } ?: return getCachedProfile(pubkeyHex)
    val profile = parseProfile(event)
    val persist = pubkeyHex == myPubkeyHex || followingSet.contains(pubkeyHex)
    cache.setCachedProfile(pubkeyHex, profile, persist)
    return profile
}


fun NostrRepository.cacheUserNotePost(pubkeyHex: String, post: ScoredPost) {
    cache.setCachedEvent(post.event)
    cache.prependToUserNotesCache(pubkeyHex, post, json)
}

fun NostrRepository.cacheUserLikedPost(pubkeyHex: String, post: ScoredPost) {
    cache.setCachedEvent(post.event)
    cache.prependToUserLikesCache(pubkeyHex, post, json)
}


fun NostrRepository.removeCachedUserLikedPost(pubkeyHex: String, eventId: String) {
    cache.removeFromUserLikesCache(pubkeyHex, eventId, json)
}

// ─── User Notes / Likes ───────────────────────────────────────────────────────

/** キャッシュのみ読む（ネットワーク不使用）。初回表示の即時描画に使う。 */
fun NostrRepository.getCachedUserNotesPosts(pubkeyHex: String): List<ScoredPost> {
    val raw = cache.getCachedUserNotes(pubkeyHex) ?: return emptyList()
    val deletedIds = cache.getDeletedEventIds()
    return try {
        json.decodeFromString<List<ScoredPost>>(raw)
            .filter { it.event.id !in deletedIds }
            .also { android.util.Log.d("NostrRepository", "user_notes cache-only: ${it.size}") }
    } catch (_: Exception) { emptyList() }
}

/** キャッシュのみ読む（ネットワーク不使用）。初回表示の即時描画に使う。 */
fun NostrRepository.getCachedUserLikesPosts(pubkeyHex: String): List<ScoredPost> {
    val raw = cache.getCachedUserLikes(pubkeyHex) ?: return emptyList()
    val deletedIds = cache.getDeletedEventIds()
    return try {
        json.decodeFromString<List<ScoredPost>>(raw)
            .filter { it.event.id !in deletedIds }
            .also { android.util.Log.d("NostrRepository", "user_likes cache-only: ${it.size}") }
    } catch (_: Exception) { emptyList() }
}

/**
 * 常にリレーから最新を取得し、取得後にキャッシュを更新する。
 * キャッシュからの読み出しは行わない（getCachedUserNotesPosts を使うこと）。
 */
suspend fun NostrRepository.fetchUserNotes(pubkeyHex: String, limit: Int = 30): List<ScoredPost> {
    // nostrdb のローカルキャッシュから即時表示用データを取得（kind-1のみ）
    // queryLocal() は Rust block_on() を呼ぶためIOスレッドで実行する
    val rustClient = client.getRustClient()
    val nostrdbPosts = if (rustClient != null) {
        try {
            withContext(Dispatchers.IO) {
                val eventsJson = rustClient.queryLocal(listOf(pubkeyHex), limit.toUInt())
                eventsJson.mapNotNull { j -> try { Json.decodeFromString<NostrEvent>(j) } catch (_: Exception) { null } }
            }
        } catch (_: Exception) { emptyList() }
    } else emptyList()

    val filter = NostrClient.Filter(
        kinds = listOf(NostrKind.TEXT_NOTE, NostrKind.LONG_FORM, NostrKind.REPOST),
        authors = listOf(pubkeyHex),
        limit = limit
    )
    val relayEvents = client.fetchEvents(filter, 6_000)
    val deletedIds = cache.getDeletedEventIds()
    val allEvents = (relayEvents + nostrdbPosts).distinctBy { it.id }
        .filter { it.id !in deletedIds }
        .sortedByDescending { it.createdAt }
        .take(limit)
    if (allEvents.isEmpty()) return getCachedUserNotesPosts(pubkeyHex).take(limit)
    cache.setCachedEvents(allEvents)
    val posts = enrichPosts(allEvents)
    try {
        cache.setCachedUserNotes(pubkeyHex,
            json.encodeToString(kotlinx.serialization.builtins.ListSerializer(ScoredPost.serializer()), posts))
    } catch (_: Exception) { }
    android.util.Log.d("NostrRepository",
        "fetchUserNotes: relay=${relayEvents.size} nostrdb=${nostrdbPosts.size} merged=${posts.size} deleted=${deletedIds.size}")
    return posts
}

/**
 * 常にリレーから最新のいいねを取得し、取得後にキャッシュを更新する。
 */
suspend fun NostrRepository.fetchUserLikes(pubkeyHex: String, limit: Int = 30): List<ScoredPost> {
    val reactionFilter = NostrClient.Filter(
        kinds = listOf(NostrKind.REACTION),
        authors = listOf(pubkeyHex),
        limit = limit
    )
    val reactions = client.fetchEvents(reactionFilter, timeoutMs = 5_000)
    val eventIds = reactions.mapNotNull { it.getTagValue("e") }.distinct()
    if (eventIds.isEmpty()) return getCachedUserLikesPosts(pubkeyHex).take(limit)

    val eventsFilter = NostrClient.Filter(ids = eventIds)
    val events = client.fetchEvents(eventsFilter, timeoutMs = 3_000).distinctBy { it.id }.sortedByDescending { it.createdAt }
    if (events.isEmpty()) return getCachedUserLikesPosts(pubkeyHex).take(limit)
    cache.setCachedEvents(events)
    val posts = enrichPosts(events)
    try {
        cache.setCachedUserLikes(pubkeyHex,
            json.encodeToString(kotlinx.serialization.builtins.ListSerializer(ScoredPost.serializer()), posts))
    } catch (_: Exception) { }
    android.util.Log.d("NostrRepository", "fetchUserLikes: ${posts.size} liked posts")
    return posts
}

// ─── Badges ───────────────────────────────────────────────────────────────────

suspend fun NostrRepository.fetchBadges(pubkeyHex: String): List<NostrEvent> = coroutineScope {
    val filter = NostrClient.Filter(
        kinds = listOf(NostrKind.PROFILE_BADGES),
        authors = listOf(pubkeyHex),
        limit = 1
    )
    val events = client.fetchEvents(filter, timeoutMs = 4_000)
    val profileBadgeEvent = events.maxByOrNull { it.createdAt } ?: return@coroutineScope emptyList()

    val tags = profileBadgeEvent.tags
    val refs = tags
        .filter { it.getOrNull(0) == "a" && it.getOrNull(1)?.startsWith("30009:") == true }
        .take(3)
        .mapNotNull { it.getOrNull(1) }

    refs.map { ref ->
        async {
            val parts = ref.split(":")
            if (parts.size < 3) return@async null
            val defFilter = NostrClient.Filter(
                kinds = listOf(NostrKind.BADGE_DEFINITION),
                authors = listOf(parts[1]),
                tags = mapOf("d" to listOf(parts.drop(2).joinToString(":"))),
                limit = 1
            )
            client.fetchEvents(defFilter, timeoutMs = 2_000).maxByOrNull { it.createdAt }
        }
    }.awaitAll().filterNotNull()
}

// ─── Badge Cache helpers ───────────────────────────────────────────────────────

fun NostrRepository.getCachedProfileBadges(pubkeyHex: String): List<BadgeInfo> {
    return getCachedProfileBadgesOrNull(pubkeyHex) ?: emptyList()
}

private fun NostrRepository.getCachedProfileBadgesOrNull(pubkeyHex: String): List<BadgeInfo>? {
    val raw = cache.getCachedBadgeInfo(pubkeyHex) ?: return null
    return try { json.decodeFromString(raw) } catch (_: Exception) { emptyList() }
}

fun NostrRepository.getCachedAwardedBadgesList(pubkeyHex: String): List<BadgeInfo> {
    val raw = cache.getCachedAwardedBadges(pubkeyHex) ?: return emptyList()
    return try { json.decodeFromString(raw) } catch (_: Exception) { emptyList() }
}

suspend fun NostrRepository.fetchProfileBadgesInfo(pubkeyHex: String): List<BadgeInfo> = coroutineScope {
    // Cache-first: return immediately if a fresh cache exists, including an
    // intentionally empty list right after the user removed all kind-30008 badges.
    val cached = getCachedProfileBadgesOrNull(pubkeyHex)
    if (cached != null) {
        // Refresh non-empty cache in background. For an empty cache, avoid an
        // immediate stale relay response resurrecting just-removed badges.
        if (cached.isNotEmpty()) {
            kotlinx.coroutines.GlobalScope.launch(kotlinx.coroutines.Dispatchers.IO) {
                try { refreshProfileBadgesInBackground(pubkeyHex) } catch (_: Exception) {}
            }
        }
        return@coroutineScope cached
    }

    val filter = NostrClient.Filter(
        kinds = listOf(NostrKind.PROFILE_BADGES),
        authors = listOf(pubkeyHex),
        limit = 1
    )
    val events = client.fetchEvents(filter, timeoutMs = 4_000)
    val profileBadgeEvent = events.maxByOrNull { it.createdAt } ?: return@coroutineScope emptyList()

    val tags = profileBadgeEvent.tags
    val badgeRequests = mutableListOf<Deferred<BadgeInfo>>()
    val seenRefs = mutableSetOf<String>()

    for (i in tags.indices) {
        if (tags[i].getOrNull(0) == "a" && tags[i].getOrNull(1)?.startsWith("30009:") == true) {
            val ref = tags[i][1]
            if (!seenRefs.contains(ref)) {
                seenRefs.add(ref)
                val awardEventId = if (i + 1 < tags.size && tags[i+1].getOrNull(0) == "e") tags[i+1].getOrNull(1) else null

                val parts = ref.split(":")
                if (parts.size >= 3) {
                    val creator = parts[1]
                    val dTag = parts.drop(2).joinToString(":")

                    badgeRequests.add(async {
                        try {
                            val defFilter = NostrClient.Filter(
                                kinds = listOf(NostrKind.BADGE_DEFINITION),
                                authors = listOf(creator),
                                tags = mapOf("d" to listOf(dTag)),
                                limit = 1
                            )
                            val defEvents = client.fetchEvents(defFilter, timeoutMs = 2_000)
                            val defEvent = defEvents.maxByOrNull { it.createdAt }

                            BadgeInfo(
                                ref = ref,
                                awardEventId = awardEventId,
                                name = defEvent?.getTagValue("name") ?: dTag,
                                image = defEvent?.getTagValue("thumb") ?: defEvent?.getTagValue("image") ?: "",
                                description = defEvent?.getTagValue("description") ?: ""
                            )
                        } catch (e: Exception) {
                            android.util.Log.e("NostrRepository", "Error fetching badge definition: $ref", e)
                            BadgeInfo(ref = ref, awardEventId = awardEventId, name = dTag)
                        }
                    })
                }
            }
        }
    }
    val result = badgeRequests.awaitAll()
    try { cache.setCachedBadgeInfo(pubkeyHex, json.encodeToString(result)) } catch (_: Exception) {}
    result
}

private suspend fun NostrRepository.refreshProfileBadgesInBackground(pubkeyHex: String) = coroutineScope {
    val filter = NostrClient.Filter(kinds = listOf(NostrKind.PROFILE_BADGES), authors = listOf(pubkeyHex), limit = 1)
    val events = client.fetchEvents(filter, timeoutMs = 4_000)
    val profileBadgeEvent = events.maxByOrNull { it.createdAt } ?: return@coroutineScope
    val tags = profileBadgeEvent.tags
    val badgeRequests = mutableListOf<Deferred<BadgeInfo>>()
    val seenRefs = mutableSetOf<String>()
    for (i in tags.indices) {
        if (tags[i].getOrNull(0) == "a" && tags[i].getOrNull(1)?.startsWith("30009:") == true) {
            val ref = tags[i][1]
            if (!seenRefs.add(ref)) continue
            val awardEventId = if (i + 1 < tags.size && tags[i + 1].getOrNull(0) == "e") tags[i + 1].getOrNull(1) else null
            val parts = ref.split(":")
            if (parts.size >= 3) {
                val dTag = parts.getOrElse(2) { "" }
                badgeRequests.add(async {
                    try {
                        val defFilter = NostrClient.Filter(kinds = listOf(NostrKind.BADGE_DEFINITION), authors = listOf(parts[1]), tags = mapOf("d" to listOf(dTag)), limit = 1)
                        val defEvent = client.fetchEvents(defFilter, timeoutMs = 3_000).maxByOrNull { it.createdAt }
                        if (defEvent != null) {
                            BadgeInfo(ref = ref, awardEventId = awardEventId, name = defEvent.getTagValue("name") ?: dTag, image = defEvent.getTagValue("thumb") ?: defEvent.getTagValue("image") ?: "", description = defEvent.getTagValue("description") ?: "")
                        } else BadgeInfo(ref = ref, awardEventId = awardEventId, name = dTag)
                    } catch (_: Exception) { BadgeInfo(ref = ref, awardEventId = awardEventId, name = dTag) }
                })
            }
        }
    }
    if (badgeRequests.isNotEmpty()) {
        val result = badgeRequests.awaitAll()
        try { cache.setCachedBadgeInfo(pubkeyHex, json.encodeToString(result)) } catch (_: Exception) {}
    }
}

suspend fun NostrRepository.fetchAwardedBadges(pubkeyHex: String, currentBadgeRefs: Set<String>): List<BadgeInfo> = coroutineScope {
    val awardFilter = NostrClient.Filter(
        kinds = listOf(NostrKind.BADGE_AWARD),
        tags = mapOf("p" to listOf(pubkeyHex)),
        limit = 50
    )
    val awardEvents = client.fetchEvents(awardFilter, timeoutMs = 5_000)

    val badgeRequests = mutableListOf<Deferred<BadgeInfo>>()
    val seenAwards = currentBadgeRefs.toMutableSet()

    for (event in awardEvents) {
        val aTag = event.tags.find { it.getOrNull(0) == "a" && it.getOrNull(1)?.startsWith("30009:") == true }
        if (aTag != null) {
            val ref = aTag[1]
            if (seenAwards.contains(ref)) continue
            seenAwards.add(ref)

            val parts = ref.split(":")
            if (parts.size >= 3) {
                val creator = parts[1]
                val dTag = parts.drop(2).joinToString(":")

                badgeRequests.add(async {
                    try {
                        val defFilter = NostrClient.Filter(
                            kinds = listOf(NostrKind.BADGE_DEFINITION),
                            authors = listOf(creator),
                            tags = mapOf("d" to listOf(dTag)),
                            limit = 1
                        )
                        val defEvents = client.fetchEvents(defFilter, timeoutMs = 2_000)
                        val defEvent = defEvents.maxByOrNull { it.createdAt }

                        BadgeInfo(
                            ref = ref,
                            awardEventId = event.id,
                            name = defEvent?.getTagValue("name") ?: dTag,
                            image = defEvent?.getTagValue("thumb") ?: defEvent?.getTagValue("image") ?: "",
                            description = defEvent?.getTagValue("description") ?: ""
                        )
                    } catch (e: Exception) {
                        android.util.Log.e("NostrRepository", "Error fetching awarded badge: $ref", e)
                        BadgeInfo(ref = ref, awardEventId = event.id, name = dTag)
                    }
                })
            }
        }
    }
    val result = badgeRequests.awaitAll()
    try { cache.setCachedAwardedBadges(pubkeyHex, json.encodeToString(result)) } catch (_: Exception) {}
    result
}

suspend fun NostrRepository.updateProfileBadges(pubkeyHex: String, badges: List<BadgeInfo>): Boolean {
    // NIP-58 profile_badges is kind 30008: a replaceable event containing
    // ["d", "profile_badges"] and ordered badge-definition refs.  When the
    // award event is known, publish the paired ["e", award-event-id] tag too.
    val selected = badges.distinctBy { it.ref }.take(3)
    val tags = mutableListOf(listOf("d", "profile_badges"))
    for (badge in selected) {
        tags.add(listOf("a", badge.ref))
        badge.awardEventId?.takeIf { it.isNotBlank() }?.let { tags.add(listOf("e", it)) }
    }
    val ok = publishNewEvent(NostrKind.PROFILE_BADGES, "", tags) != null
    if (ok) {
        // Make the freshly edited badge set visible immediately.  Do not wait
        // for relay propagation; otherwise a cache-first profile screen may keep
        // showing the previous kind-30008 for the badge TTL.
        try { cache.setCachedBadgeInfo(pubkeyHex, json.encodeToString(selected)) } catch (_: Exception) {}
    }
    return ok
}

// ─── Emoji ────────────────────────────────────────────────────────────────────


fun NostrRepository.getCachedEmojiEvent(cacheKey: String): NostrEvent? {
    val jsonStr = cache.getCachedEmoji(cacheKey) ?: return null
    return try { json.decodeFromString<NostrEvent>(jsonStr) } catch (_: Exception) { null }
}

fun NostrRepository.cacheEmojiEvent(cacheKey: String, event: NostrEvent) {
    try { cache.setCachedEmoji(cacheKey, json.encodeToString(NostrEvent.serializer(), event)) } catch (_: Exception) { }
}

fun NostrRepository.getCachedEmojiList(pubkeyHex: String): NostrEvent? {
    return getCachedEmojiEvent(pubkeyHex)
}

suspend fun NostrRepository.fetchEmojiList(pubkeyHex: String): NostrEvent? {
    val filter = NostrClient.Filter(
        kinds = listOf(NostrKind.EMOJI_LIST),
        authors = listOf(pubkeyHex),
        limit = 1
    )
    val events = client.fetchEvents(filter, timeoutMs = 4_000)
    val event = events.maxByOrNull { it.createdAt }
    if (event != null) {
        cacheEmojiEvent(pubkeyHex, event)
        return event
    }
    return getCachedEmojiList(pubkeyHex)
}

suspend fun NostrRepository.fetchEmojiSet(author: String, dTag: String): EmojiSet? {
    val filter = NostrClient.Filter(
        kinds = listOf(NostrKind.EMOJI_SET),
        authors = listOf(author),
        tags = mapOf("d" to listOf(dTag)),
        limit = 1
    )
    val events = client.fetchEvents(filter, timeoutMs = 4_000)
    val event = events.maxByOrNull { it.createdAt } ?: return null

    val title = event.getTagValue("title") ?: dTag
    val emojiTags = event.tags.filter { it.getOrNull(0) == "emoji" }

    return EmojiSet(
        pointer = "30030:$author:$dTag",
        name = title,
        author = author,
        dTag = dTag,
        emojiCount = emojiTags.size,
        emojis = emojiTags.mapNotNull {
            val shortcode = it.getOrNull(1)
            val url = it.getOrNull(2)
            if (shortcode != null && url != null) EmojiInfo(shortcode, url) else null
        }
    )
}

suspend fun NostrRepository.searchEmojiSets(query: String): List<EmojiSet> {
    val filter = NostrClient.Filter(
        kinds = listOf(NostrKind.EMOJI_SET),
        limit = 50
    )
    val events = client.fetchEvents(filter, timeoutMs = 5_000)
    val search = query.lowercase()

    return events.mapNotNull { e ->
        val dTag = e.getTagValue("d") ?: return@mapNotNull null
        val title = e.getTagValue("title") ?: dTag
        if (query.isNotEmpty() && !title.lowercase().contains(search) && !dTag.lowercase().contains(search)) {
            return@mapNotNull null
        }

        val emojiTags = e.tags.filter { it.getOrNull(0) == "emoji" }
        if (emojiTags.isEmpty()) return@mapNotNull null

        EmojiSet(
            pointer = "30030:${e.pubkey}:$dTag",
            name = title,
            author = e.pubkey,
            dTag = dTag,
            emojiCount = emojiTags.size,
            emojis = emojiTags.take(5).mapNotNull {
                val shortcode = it.getOrNull(1)
                val url = it.getOrNull(2)
                if (shortcode != null && url != null) EmojiInfo(shortcode, url) else null
            }
        )
    }.distinctBy { it.pointer }
}

suspend fun NostrRepository.updateEmojiList(tags: List<List<String>>): Boolean {
    return publishNewEvent(NostrKind.EMOJI_LIST, "", tags) != null
}
