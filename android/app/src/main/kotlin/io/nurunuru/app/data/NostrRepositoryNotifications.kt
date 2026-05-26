package io.nurunuru.app.data

import io.nurunuru.app.data.models.*
import io.nurunuru.app.data.prefs.NotificationSenderScope
import kotlinx.coroutines.*
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.*
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import java.util.concurrent.TimeUnit

// ─── Notifications ────────────────────────────────────────────────────────────

private val NOTIFICATION_ALLOWED_TYPES = setOf("reaction", "emoji_reaction", "zap", "repost", "reply", "mention", "badge", "follow")

fun NostrRepository.getCachedNotifications(pubkeyHex: String): NotificationResult? {
    val raw = cache.getCachedNotifications(pubkeyHex) ?: return null
    return try { json.decodeFromString<NotificationResult>(raw) } catch (_: Exception) { null }
}

/** Fetch notifications (reactions + zaps targeting the user). Cache-first, 1-day window. */
suspend fun NostrRepository.fetchNotifications(pubkeyHex: String, limit: Int = 50, skipCache: Boolean = false): NotificationResult {
    // キャッシュヒット時は即返す（skipCache=true のときはスキップ）
    if (!skipCache) {
        cache.getCachedNotifications(pubkeyHex)?.let { cached ->
            try {
                val result = json.decodeFromString<NotificationResult>(cached)
                if (result.items.isNotEmpty()) {
                    val dedupedItems = dedupeFollowNotifications(result.items.filter { it.type in NOTIFICATION_ALLOWED_TYPES })
                    val dedupedResult = if (dedupedItems.size != result.items.size) {
                        result.copy(items = dedupedItems)
                    } else result
                    android.util.Log.d("NostrRepository", "notifications cache hit: ${result.items.size} deduped=${dedupedItems.size}")
                    if (dedupedItems.size != result.items.size) {
                        try { cache.setCachedNotifications(pubkeyHex, json.encodeToString(NotificationResult.serializer(), dedupedResult)) } catch (_: Exception) { }
                    }
                    return dedupedResult
                }
            } catch (_: Exception) { }
        }
    }

    val oneDayAgo = System.currentTimeMillis() / 1000 - Constants.Time.DAY_SECS

    // 1. Fetch reactions (#p tag targeting me)
    val reactionFilter = NostrClient.Filter(
        kinds = listOf(NostrKind.REACTION),
        tags = mapOf("p" to listOf(pubkeyHex)),
        since = oneDayAgo,
        limit = limit
    )

    // 2. Fetch zaps (#p tag targeting me)
    val zapFilter = NostrClient.Filter(
        kinds = listOf(NostrKind.ZAP_RECEIPT),
        tags = mapOf("p" to listOf(pubkeyHex)),
        since = oneDayAgo,
        limit = limit
    )

    // 3. Fetch reposts of my posts (Kind 6 #p tag)
    val repostFilter = NostrClient.Filter(
        kinds = listOf(NostrKind.REPOST),
        tags = mapOf("p" to listOf(pubkeyHex)),
        since = oneDayAgo,
        limit = limit
    )

    // 4. Fetch replies to my posts (Kind 1 #p tag)
    val replyFilter = NostrClient.Filter(
        kinds = listOf(NostrKind.TEXT_NOTE),
        tags = mapOf("p" to listOf(pubkeyHex)),
        since = oneDayAgo,
        limit = limit
    )

    // 5. Fetch badge awards (Kind 8 #p tag)
    val badgeFilter = NostrClient.Filter(
        kinds = listOf(NostrKind.BADGE_AWARD),
        tags = mapOf("p" to listOf(pubkeyHex)),
        since = oneDayAgo,
        limit = limit
    )

    // 6. Fetch new followers (Kind 3 #p tag)
    val followFilter = NostrClient.Filter(
        kinds = listOf(NostrKind.CONTACT_LIST),
        tags = mapOf("p" to listOf(pubkeyHex)),
        since = oneDayAgo,
        limit = limit
    )

    val enabledKinds = prefs.notificationEnabledKinds
    val emojiReactionEnabled = prefs.notificationEmojiReactionEnabled
    val allowedSenders: Set<String>? = when (prefs.notificationSenderScope) {
        NotificationSenderScope.ALL -> null
        NotificationSenderScope.FOLLOWING -> fetchFollowList(pubkeyHex).toSet()
        NotificationSenderScope.NETWORK -> {
            val follows = fetchFollowList(pubkeyHex)
            val secondDegree = fetchFollowListsBatch(follows).values.flatten()
            (follows + secondDegree).toSet()
        }
    }
    fun canNotify(sender: String): Boolean = sender != pubkeyHex && (allowedSenders == null || sender in allowedSenders)
    android.util.Log.d("NostrRepository",
        "fetchNotifications: enabledKinds=${enabledKinds.sorted()} emojiReaction=$emojiReactionEnabled")

    // Use NIP-65 read relays if configured; fall back to default client.fetchEvents
    val readRelayUrls = prefs.nip65Relays.filter { it.read }.map { it.url }.takeIf { it.isNotEmpty() }
    android.util.Log.d("NostrRepository", "fetchNotifications: readRelays=${readRelayUrls?.size ?: 0}")

    suspend fun fetchWith(filter: NostrClient.Filter): List<NostrEvent> {
        return if (readRelayUrls != null) {
            fetchNotificationEventsFromRelays(readRelayUrls, filter, timeoutMs = 6_000)
        } else {
            client.fetchEvents(filter, timeoutMs = 5_000)
        }
    }

    val reactions = if (NostrKind.REACTION in enabledKinds || emojiReactionEnabled)
        fetchWith(reactionFilter) else emptyList()
    val zaps = if (NostrKind.ZAP_RECEIPT in enabledKinds)
        fetchWith(zapFilter) else emptyList()
    val reposts = if (NostrKind.REPOST in enabledKinds)
        fetchWith(repostFilter) else emptyList()
    val mentions = if (NostrKind.TEXT_NOTE in enabledKinds)
        fetchWith(replyFilter) else emptyList()
    val badges = if (NostrKind.BADGE_AWARD in enabledKinds)
        fetchWith(badgeFilter) else emptyList()
    val follows = if (NostrKind.CONTACT_LIST in enabledKinds)
        fetchWith(followFilter) else emptyList()
    android.util.Log.d("NostrRepository",
        "fetchNotifications: reactions=${reactions.size} zaps=${zaps.size} reposts=${reposts.size} mentions=${mentions.size} badges=${badges.size} follows=${follows.size}")

    // Build notification items
    val notificationItems = mutableListOf<NotificationItem>()
    val targetEventIds = mutableSetOf<String>()
    val notifierPubkeys = mutableSetOf<String>()

    for (event in reactions) {
        if (!canNotify(event.pubkey)) continue
        val targetEvent = event.getTagValue("e")
        val emojiTag = event.tags.firstOrNull { it.getOrNull(0) == "emoji" }
        val emojiUrl = emojiTag?.getOrNull(2)
        val content = event.content.ifBlank { "+" }
        val isEmoji = emojiUrl != null ||
            (content.startsWith(":") && content.endsWith(":") && content.length > 2)

        if (isEmoji && !emojiReactionEnabled) continue
        if (!isEmoji && NostrKind.REACTION !in enabledKinds) continue

        targetEvent?.let { targetEventIds.add(it) }
        notifierPubkeys.add(event.pubkey)

        notificationItems.add(
            NotificationItem(
                id = event.id,
                pubkey = event.pubkey,
                type = if (isEmoji) "emoji_reaction" else "reaction",
                createdAt = event.createdAt,
                targetEventId = targetEvent,
                comment = content.takeIf { it != "+" && it != "-" && it.isNotBlank() },
                emojiUrl = emojiUrl,
                reactionEmoji = content
            )
        )
    }

    for (event in zaps) {
        val targetEvent = event.getTagValue("e")
        targetEvent?.let { targetEventIds.add(it) }

        // Parse zap amount from bolt11 tag
        val bolt11 = event.getTagValue("bolt11") ?: ""
        val amount = NostrRepository.parseBolt11Amount(bolt11)

        // Parse sender from description tag (zap request)
        val descTag = event.getTagValue("description")
        val senderPubkey = if (descTag != null) {
            try {
                val descObj = json.parseToJsonElement(descTag).jsonObject
                descObj["pubkey"]?.jsonPrimitive?.content
            } catch (e: Exception) { null }
        } else null

        val zapPubkey = senderPubkey ?: event.pubkey
        if (zapPubkey == pubkeyHex) continue
        notifierPubkeys.add(zapPubkey)

        val comment = if (descTag != null) {
            try {
                json.parseToJsonElement(descTag).jsonObject["content"]?.jsonPrimitive?.content?.takeIf { it.isNotBlank() }
            } catch (e: Exception) { null }
        } else null

        notificationItems.add(
            NotificationItem(
                id = event.id,
                pubkey = zapPubkey,
                type = "zap",
                createdAt = event.createdAt,
                amount = amount,
                comment = comment,
                targetEventId = targetEvent
            )
        )
    }

    for (event in reposts) {
        if (!canNotify(event.pubkey)) continue
        val targetEvent = event.getTagValue("e")
        targetEvent?.let { targetEventIds.add(it) }
        notifierPubkeys.add(event.pubkey)

        notificationItems.add(
            NotificationItem(
                id = event.id,
                pubkey = event.pubkey,
                type = "repost",
                createdAt = event.createdAt,
                targetEventId = targetEvent
            )
        )
    }

    for (event in mentions) {
        if (!canNotify(event.pubkey)) continue
        // Distinguish reply (has "e" tag) vs plain mention (only "p" tag)
        val targetEvent = event.getTagValue("e")
        targetEvent?.let { targetEventIds.add(it) }
        notifierPubkeys.add(event.pubkey)

        val type = if (targetEvent != null) "reply" else "mention"
        notificationItems.add(
            NotificationItem(
                id = event.id,
                pubkey = event.pubkey,
                type = type,
                createdAt = event.createdAt,
                targetEventId = targetEvent,
                comment = event.content.take(100).ifBlank { null }
            )
        )
    }

    for (event in badges) {
        if (!canNotify(event.pubkey)) continue
        notifierPubkeys.add(event.pubkey)
        // バッジ名: "a" タグ "30009:pubkey:d-tag" の d-tag 部分
        val aRef = event.tags.find { it.getOrNull(0) == "a" && it.getOrNull(1)?.startsWith("30009:") == true }
        val badgeName = aRef?.getOrNull(1)?.split(":")?.drop(2)?.joinToString(":") ?: ""
        notificationItems.add(
            NotificationItem(
                id = event.id,
                pubkey = event.pubkey,
                type = "badge",
                createdAt = event.createdAt,
                comment = badgeName.ifBlank { null }
            )
        )
    }



    // Follow notifications: mirror iOS high-water + known-followers de-duplication.
    // Kind 3 is a full contact-list replacement. If someone already follows me,
    // every later contact-list update still contains my pubkey, so it must not be
    // treated as a new follow. Notify only on an author first seen after the last
    // processed high-water mark; baseline existing followers without emitting.
    if (follows.isNotEmpty()) {
        val allCandidates = follows
            .filter { it.pubkey != pubkeyHex }
            .filter { event -> event.tags.any { it.firstOrNull() == "p" && it.getOrNull(1) == pubkeyHex } }
            .sortedBy { it.createdAt }
        if (allCandidates.isNotEmpty()) {
            val previousHighWater = prefs.notificationFollowLastSeenAt
            val maxSeenAt = maxOf(previousHighWater, allCandidates.maxOfOrNull { it.createdAt.toLong() } ?: previousHighWater)
            val knownFollowers = prefs.notificationKnownFollowerPubkeys.toMutableSet()

            // 初回、または過去版で high-water だけ保存され known が空の状態は、まず現存フォロワーをベースライン化する。
            // ここで通知は出さない（既存フォロワーの contact list 更新を重複通知しないため）。
            if (previousHighWater == 0L || knownFollowers.isEmpty()) {
                knownFollowers.addAll(allCandidates.map { it.pubkey })
                prefs.notificationKnownFollowerPubkeys = knownFollowers
                prefs.notificationFollowLastSeenAt = maxSeenAt
                android.util.Log.d("NostrRepository", "NotificationFollow baseline known=${knownFollowers.size} highWater=$maxSeenAt all=${allCandidates.size}")
            } else {
                val emittedAuthors = mutableSetOf<String>()
                for (event in allCandidates) {
                    val wasKnown = event.pubkey in knownFollowers
                    val isNewEvent = event.createdAt.toLong() > previousHighWater
                    if (isNewEvent && !wasKnown && canNotify(event.pubkey) && emittedAuthors.add(event.pubkey)) {
                        notifierPubkeys.add(event.pubkey)
                        notificationItems.add(
                            NotificationItem(
                                id = event.id,
                                pubkey = event.pubkey,
                                type = "follow",
                                createdAt = event.createdAt,
                                comment = null
                            )
                        )
                    }
                    // canNotify で除外した相手も既知化し、設定変更後に古い Kind 3 が通知化されるのを防ぐ。
                    knownFollowers.add(event.pubkey)
                }
                prefs.notificationKnownFollowerPubkeys = knownFollowers
                prefs.notificationFollowLastSeenAt = maxSeenAt
                android.util.Log.d("NostrRepository", "NotificationFollow all=${allCandidates.size} emitted=${emittedAuthors.size} known=${knownFollowers.size} prevHighWater=$previousHighWater highWater=$maxSeenAt")
            }
        }
    }

    // Fetch original posts
    val originalPosts = mutableMapOf<String, NostrEvent>()
    if (targetEventIds.isNotEmpty()) {
        val postsFilter = NostrClient.Filter(
            ids = targetEventIds.take(50).toList()
        )
        val cachedIds = targetEventIds.mapNotNull { id -> cache.getCachedEvent(id)?.also { originalPosts[id] = it } }.map { it.id }.toSet()
        val missingIds = targetEventIds.filter { it !in cachedIds }.take(50)
        val posts = if (missingIds.isNotEmpty()) client.fetchEvents(NostrClient.Filter(ids = missingIds), timeoutMs = 3_000) else emptyList()
        cache.setCachedEvents(posts)
        posts.forEach { originalPosts[it.id] = it }
    }

    // Fetch notifier profiles
    val profiles = fetchProfiles(notifierPubkeys.toList())

    // Sort by time descending and remove duplicated follow notifications by follower pubkey.
    val sorted = dedupeFollowNotifications(notificationItems.filter { it.type in NOTIFICATION_ALLOWED_TYPES })

    val result = NotificationResult(sorted, profiles, originalPosts)

    // キャッシュに保存（1日有効）
    try {
        cache.setCachedNotifications(pubkeyHex, json.encodeToString(NotificationResult.serializer(), result))
    } catch (_: Exception) { }

    return result
}


private fun dedupeFollowNotifications(items: List<NotificationItem>): List<NotificationItem> {
    val seenFollowPubkeys = mutableSetOf<String>()
    val seenIds = mutableSetOf<String>()
    return items
        .sortedByDescending { it.createdAt }
        .filter { item ->
            if (item.type == "follow") {
                // 同じフォロワーの Kind 3 更新が複数リレー/複数回届いても、最新1件だけ表示する。
                seenFollowPubkeys.add(item.pubkey)
            } else {
                seenIds.add(item.id)
            }
        }
}

/**
 * Fetch notification events from specific relay URLs via OkHttp WebSocket.
 * Connects to each relay in parallel and aggregates results.
 */
private suspend fun NostrRepository.fetchNotificationEventsFromRelays(
    relayUrls: List<String>,
    filter: NostrClient.Filter,
    timeoutMs: Long = 6_000
): List<NostrEvent> = coroutineScope {
    val filterJson = buildString {
        append("{")
        filter.kinds?.let { append("\"kinds\":${it},") }
        filter.since?.let { append("\"since\":$it,") }
        filter.limit?.let { append("\"limit\":$it,") }
        filter.tags?.forEach { (key, values) ->
            append("\"#$key\":${values.map { "\"$it\"" }},")
        }
        if (endsWith(",")) deleteCharAt(length - 1)
        append("}")
    }

    val allEvents = java.util.concurrent.ConcurrentHashMap<String, NostrEvent>()

    relayUrls.map { relayUrl ->
        async(Dispatchers.IO) {
            try {
                val done = kotlinx.coroutines.CompletableDeferred<Unit>()
                val subId = "notif-${System.currentTimeMillis()}-${relayUrl.hashCode()}"
                val reqMsg = """["REQ","$subId",$filterJson]"""
                val wsClient = OkHttpClient.Builder()
                    .connectTimeout(5, TimeUnit.SECONDS)
                    .build()
                val request = Request.Builder().url(relayUrl).build()
                val listener = object : WebSocketListener() {
                    override fun onOpen(ws: WebSocket, response: Response) { ws.send(reqMsg) }
                    override fun onMessage(ws: WebSocket, text: String) {
                        if (done.isCompleted) return
                        try {
                            val arr = Json.parseToJsonElement(text).jsonArray
                            when (arr[0].jsonPrimitive.content) {
                                "EVENT" -> {
                                    val ev = Json { ignoreUnknownKeys = true }
                                        .decodeFromString<NostrEvent>(arr[2].toString())
                                    allEvents[ev.id] = ev
                                }
                                "EOSE" -> { ws.close(1000, "done"); done.complete(Unit) }
                            }
                        } catch (_: Exception) {}
                    }
                    override fun onFailure(ws: WebSocket, t: Throwable, response: Response?) {
                        if (!done.isCompleted) done.complete(Unit)
                    }
                    override fun onClosed(ws: WebSocket, code: Int, reason: String) {
                        if (!done.isCompleted) done.complete(Unit)
                    }
                }
                val ws = wsClient.newWebSocket(request, listener)
                try {
                    withTimeout(timeoutMs) { done.await() }
                } catch (_: kotlinx.coroutines.TimeoutCancellationException) { }
                ws.cancel()
            } catch (_: Exception) {}
        }
    }.awaitAll()

    allEvents.values.toList()
}


/** Fetch a specific event by ID, trying hinted relays before the wider fallback. */
suspend fun NostrRepository.fetchEventFromRelays(eventId: String, relayHints: List<String>): ScoredPost? {
    cache.getCachedEvent(eventId)?.let { return enrichPosts(listOf(it)).firstOrNull() }
    val hints = relayHints.filter { it.startsWith("wss://") || it.startsWith("ws://") }.distinct()
    if (hints.isNotEmpty()) {
        val filter = NostrClient.Filter(ids = listOf(eventId), limit = 1)
        val events = client.fetchEventsFrom(hints, filter, timeoutMs = 3_000)
        if (events.isNotEmpty()) {
            cache.setCachedEvents(events)
            return enrichPosts(events.distinctBy { it.id }).firstOrNull()
        }
    }
    return fetchEvent(eventId)
}

/** Fetch an addressable event (naddr) using kind:author:d-tag and optional relay hints. */
suspend fun NostrRepository.fetchAddressableEvent(pointer: String, relayHints: List<String> = emptyList()): ScoredPost? {
    val parts = pointer.split(":", limit = 3)
    if (parts.size != 3) return null
    val kind = parts[0].toIntOrNull() ?: return null
    val author = parts[1]
    val dTag = parts[2]
    val filter = NostrClient.Filter(kinds = listOf(kind), authors = listOf(author), tags = mapOf("d" to listOf(dTag)), limit = 1)

    val hints = relayHints.filter { it.startsWith("wss://") || it.startsWith("ws://") }.distinct()
    val hinted = if (hints.isNotEmpty()) client.fetchEventsFrom(hints, filter, timeoutMs = 3_000) else emptyList()
    if (hinted.isNotEmpty()) { cache.setCachedEvents(hinted); return enrichPosts(hinted.distinctBy { it.id }).firstOrNull() }

    val relayCandidates = (
        prefs.nip65Relays.map { it.url } +
        prefs.relays.toList() +
        io.nurunuru.app.data.models.DEFAULT_RELAYS +
        listOf(NostrClient.SEARCH_RELAY)
    ).distinct()
    val events = client.fetchEventsFrom(relayCandidates, filter, timeoutMs = 5_000)
    cache.setCachedEvents(events)
    return enrichPosts(events.distinctBy { it.id }).firstOrNull()
}

/** Fetch a specific event by ID. */
suspend fun NostrRepository.fetchEvent(eventId: String): ScoredPost? {
    cache.getCachedEvent(eventId)?.let { return enrichPosts(listOf(it)).firstOrNull() }
    val filter = NostrClient.Filter(
        ids = listOf(eventId),
        limit = 1
    )

    // まず現在接続中のリレーを試す。
    val direct = client.fetchEvents(filter, timeoutMs = 2_500)
    if (direct.isNotEmpty()) { cache.setCachedEvents(direct); return enrichPosts(direct).firstOrNull() }

    // 投稿詳細・通知から開く投稿は、現在の接続プールに無い NIP-65 Read/Write リレーや
    // デフォルト/検索リレーにしか存在しない場合があるため、明示的に広めに探索する。
    val relayCandidates = (
        prefs.nip65Relays.map { it.url } +
        prefs.relays.toList() +
        io.nurunuru.app.data.models.DEFAULT_RELAYS +
        listOf(NostrClient.SEARCH_RELAY)
    ).distinct()
    android.util.Log.d("NostrRepository", "fetchEvent wide relayCandidates=" + relayCandidates.size + " id=" + eventId.take(8))
    val relayEvents = if (relayCandidates.isNotEmpty()) {
        client.fetchEventsFrom(relayCandidates, filter, timeoutMs = 5_000)
    } else emptyList()
    android.util.Log.d("NostrRepository", "fetchEvent wide result=" + relayEvents.size + " id=" + eventId.take(8))
    cache.setCachedEvents(relayEvents)

    return enrichPosts(relayEvents.distinctBy { it.id }).firstOrNull()
}
