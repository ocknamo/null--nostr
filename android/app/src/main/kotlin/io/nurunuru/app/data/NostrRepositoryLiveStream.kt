package io.nurunuru.app.data

import io.nurunuru.app.data.models.*
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.withTimeout
import kotlinx.serialization.json.*
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import java.util.concurrent.TimeUnit

// ─── Miniapp helpers ──────────────────────────────────────────────────────────

/** Fetch events with simplified parameters for miniapps */
suspend fun NostrRepository.fetchEvents(
    kinds: List<Int>,
    authors: List<String>? = null,
    limit: Int = 10,
    dTags: List<String>? = null,
    since: Long? = null
): List<NostrEvent> {
    val tags = mutableMapOf<String, List<String>>()
    dTags?.let { tags["d"] = it }

    return client.fetchEvents(
        NostrClient.Filter(
            kinds = kinds,
            authors = authors,
            limit = limit,
            tags = tags.ifEmpty { null },
            since = since
        ),
        timeoutMs = 5_000
    )
}

/** Publish a generic event (used by SchedulerApp, etc.) */
suspend fun NostrRepository.publishEvent(
    kind: Int,
    content: String,
    tags: List<List<String>> = emptyList(),
    addClientTag: Boolean = false
): NostrEvent? {
    val allTags = tags.toMutableList()
    if (addClientTag && allTags.none { it.getOrNull(0) == "client" }) {
        allTags.add(clientTag)
    }
    val eventId = publishNewEvent(kind, content, allTags) ?: return null
    return NostrEvent(id = eventId, pubkey = myPubkeyHex, kind = kind, tags = allTags, content = content)
}

// ─── Live Streaming ───────────────────────────────────────────────────────────

/**
 * Start a live subscription for new Kind-1 events.
 * Returns a subscription ID to pass to [pollLiveStream] and [stopLiveStream].
 */
fun NostrRepository.startLiveStream(authors: List<String> = emptyList()): String? {
    return try {
        client.getRustClient()?.startLiveSubscription(authors).also {
            android.util.Log.d("NostrRepository", "Live stream started: sub=$it authors=${authors.size}")
        }
    } catch (e: Exception) {
        android.util.Log.e("NostrRepository", "startLiveStream failed", e)
        null
    }
}

/**
 * Drain buffered live events. Returns immediately with whatever has arrived
 * since the last call. Safe to call every second from a coroutine loop.
 */
fun NostrRepository.pollLiveStream(subId: String): List<NostrEvent> {
    return try {
        val jsonList = client.getRustClient()?.pollLiveEvents(subId, 20u) ?: return emptyList()
        jsonList.mapNotNull { jsonStr ->
            try { Json.decodeFromString<NostrEvent>(jsonStr) } catch (_: Exception) { null }
        }
    } catch (e: Exception) {
        android.util.Log.w("NostrRepository", "pollLiveStream error", e)
        emptyList()
    }
}

/** Cancel a live subscription and release its resources. */
fun NostrRepository.stopLiveStream(subId: String) {
    try {
        client.getRustClient()?.stopLiveSubscription(subId)
        android.util.Log.d("NostrRepository", "Live stream stopped: sub=$subId")
    } catch (e: Exception) {
        android.util.Log.w("NostrRepository", "stopLiveStream error", e)
    }
}

// ─── Relay Timeline ───────────────────────────────────────────────────────────

/**
 * 指定リレー単体から kind 1 を時系列で取得する（リレーフィード用）。
 * OkHttp WebSocket で直接接続し、Rust エンジンの全リレー混合を回避する。
 * リプライ除外・ミュートフィルタ適用。他のリレーへのフォールバックなし。
 */
suspend fun NostrRepository.fetchRelayTimeline(relayUrl: String, limit: Int = 50): List<ScoredPost> =
    fetchRelayTimelinePage(relayUrl = relayUrl, until = null, limit = limit)

/** Fetch older posts from a selected relay before [until]. */
suspend fun NostrRepository.fetchRelayTimelinePage(
    relayUrl: String,
    until: Long?,
    limit: Int = 50
): List<ScoredPost> = withContext(Dispatchers.IO) {
    try {
        var cursor = until ?: (System.currentTimeMillis() / 1000)
        repeat(8) { attempt ->
            val since = cursor - 6L * 60L * 60L
            val events = fetchFromSingleRelayWs(relayUrl, limit, since, cursor, timeoutMs = 3_500)
            android.util.Log.d("NostrRepository", "fetchRelayTimelinePage(" + relayUrl + " attempt=" + (attempt + 1) + " until=" + cursor + "): " + events.size + " events")
            if (events.isNotEmpty()) {
                cache.setCachedEvents(events)
                val muteData = getCachedMuteList(myPubkeyHex)
                val mutedPks = muteData?.pubkeys?.toSet() ?: emptySet()
                val mutedIds = muteData?.eventIds?.toSet() ?: emptySet()
                return@withContext postsFromRawTimelineEvents(events)
                    .filter { it.event.pubkey !in mutedPks && it.event.id !in mutedIds }
                    .take(limit)
            }
            cursor = since - 1
        }
        emptyList()
    } catch (e: Exception) {
        android.util.Log.e("NostrRepository", "fetchRelayTimelinePage failed: " + e.message, e)
        emptyList()
    }
}

/**
 * OkHttp WebSocket で指定リレー1つにのみ接続し kind 1 を取得する。
 */
private suspend fun NostrRepository.fetchFromSingleRelayWs(
    relayUrl: String,
    limit: Int,
    since: Long? = null,
    until: Long? = null,
    timeoutMs: Long = 8_000
): List<NostrEvent> = withContext(Dispatchers.IO) {
    val events = mutableListOf<NostrEvent>()
    val done = CompletableDeferred<Unit>()
    val subId = "relay-tl-${System.currentTimeMillis()}"
    val filterParts = mutableListOf<String>()
    filterParts += "\"kinds\":[1,6,22,30023]"
    filterParts += "\"limit\":$limit"
    since?.let { filterParts += "\"since\":$it" }
    until?.let { filterParts += "\"until\":$it" }
    val filterJson = "{" + filterParts.joinToString(",") + "}"
    val reqMsg = """["REQ","$subId",$filterJson]"""
    val closeMsg = """["CLOSE","$subId"]"""

    val wsClient = OkHttpClient.Builder()
        .connectTimeout(5, TimeUnit.SECONDS)
        .build()
    val request = Request.Builder().url(relayUrl).build()

    val listener = object : WebSocketListener() {
        override fun onOpen(ws: WebSocket, response: Response) {
            ws.send(reqMsg)
        }
        override fun onMessage(ws: WebSocket, text: String) {
            if (done.isCompleted) return
            try {
                val arr = Json.parseToJsonElement(text).jsonArray
                when (arr[0].jsonPrimitive.content) {
                    "EVENT" -> {
                        val event = Json { ignoreUnknownKeys = true }
                            .decodeFromString<NostrEvent>(arr[2].toString())
                        synchronized(events) { events.add(event) }
                    }
                    "EOSE" -> {
                        ws.send(closeMsg)
                        ws.close(1000, "done")
                        done.complete(Unit)
                    }
                }
            } catch (_: Exception) {}
        }
        override fun onFailure(ws: WebSocket, t: Throwable, response: Response?) {
            android.util.Log.w("NostrRepository", "WS failure $relayUrl: ${t.message}")
            if (!done.isCompleted) done.complete(Unit)
        }
        override fun onClosed(ws: WebSocket, code: Int, reason: String) {
            if (!done.isCompleted) done.complete(Unit)
        }
    }

    val ws = wsClient.newWebSocket(request, listener)
    try {
        withTimeout(timeoutMs) { done.await() }
    } catch (_: kotlinx.coroutines.TimeoutCancellationException) {
        android.util.Log.d("NostrRepository", "WS timeout for $relayUrl")
        ws.close(1000, "timeout")
    } finally {
        wsClient.dispatcher.executorService.shutdown()
    }
    events.toList()
}

/**
 * 指定リレーのライブストリームを Flow で返す。
 * EOSE 後も接続を維持し、新着 kind 1 イベントを emit し続ける。
 */
fun NostrRepository.openRelayLiveStream(relayUrl: String): Flow<NostrEvent> = callbackFlow {
    val subId = "relay-live-${System.currentTimeMillis()}"
    val since = System.currentTimeMillis() / 1000
    val reqMsg  = """["REQ","$subId",{"kinds":[1],"since":$since}]"""
    val closeMsg = """["CLOSE","$subId"]"""
    val jsonParser = Json { ignoreUnknownKeys = true }

    val wsClient = OkHttpClient.Builder()
        .connectTimeout(5, TimeUnit.SECONDS)
        .pingInterval(20, TimeUnit.SECONDS)  // 30秒サーバータイムアウトより前に ping を送る
        .build()
    val request = Request.Builder().url(relayUrl).build()

    val listener = object : WebSocketListener() {
        override fun onOpen(ws: WebSocket, response: Response) {
            android.util.Log.d("NostrRepository", "Relay live WS open: $relayUrl since=$since")
            ws.send(reqMsg)
        }
        override fun onMessage(ws: WebSocket, text: String) {
            try {
                val arr = jsonParser.parseToJsonElement(text).jsonArray
                when (arr[0].jsonPrimitive.content) {
                    "EVENT" -> {
                        val event = jsonParser.decodeFromString<NostrEvent>(arr[2].toString())
                        trySend(event)
                    }
                    "EOSE" -> android.util.Log.d("NostrRepository", "Relay live EOSE: $relayUrl (staying connected)")
                }
            } catch (_: Exception) {}
        }
        override fun onFailure(ws: WebSocket, t: Throwable, response: Response?) {
            android.util.Log.w("NostrRepository", "Relay live WS failure $relayUrl: ${t.message}")
            close(t)
        }
        override fun onClosed(ws: WebSocket, code: Int, reason: String) { channel.close() }
    }

    val ws = wsClient.newWebSocket(request, listener)
    awaitClose {
        ws.send(closeMsg)
        ws.close(1000, "cancelled")
        wsClient.dispatcher.executorService.shutdown()
    }
}

// ─── WebView / NIP-07 Bridge helpers ─────────────────────────────────────────

/**
 * WebView から渡された未署名イベント JSON に署名して返す。
 */
suspend fun NostrRepository.signEventForWebBridge(eventJson: String): String? = withContext(Dispatchers.IO) {
    try {
        val parsed = kotlinx.serialization.json.Json.parseToJsonElement(eventJson).jsonObject
        val kind      = parsed["kind"]?.jsonPrimitive?.intOrNull ?: return@withContext null
        val content   = parsed["content"]?.jsonPrimitive?.content ?: ""
        val tagsArr   = parsed["tags"]?.jsonArray
            ?: kotlinx.serialization.json.JsonArray(emptyList())
        val createdAt = parsed["created_at"]?.jsonPrimitive?.longOrNull
            ?: (System.currentTimeMillis() / 1000)

        val unsigned = buildString {
            append("{")
            append("\"kind\":$kind,")
            append("\"content\":${JsonPrimitive(content)},")
            append("\"tags\":${tagsArr},")
            append("\"created_at\":$createdAt,")
            append("\"pubkey\":\"$myPubkeyHex\"")
            append("}")
        }
        client.getSigner().signEvent(unsigned, requireManualApproval = true)
    } catch (e: Exception) {
        android.util.Log.e("NostrRepository", "signEventForWebBridge: ${e.message}")
        null
    }
}

/** NIP-04 暗号化（WebView ブリッジ用） */
suspend fun NostrRepository.nip04EncryptForBridge(receiverPubkey: String, plaintext: String): String? =
    client.encryptNip04(receiverPubkey, plaintext)

/** NIP-04 復号（WebView ブリッジ用） */
suspend fun NostrRepository.nip04DecryptForBridge(senderPubkey: String, ciphertext: String): String? =
    client.decryptNip04(senderPubkey, ciphertext)
