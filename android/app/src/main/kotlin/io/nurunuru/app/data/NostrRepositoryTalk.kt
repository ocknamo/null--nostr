package io.nurunuru.app.data

import io.nurunuru.app.data.models.*
import kotlinx.coroutines.*
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.*
import uniffi.nurunuru.FfiEncryptedMessageData

private fun mlsLogPrefix(value: String?): String {
    val v = value.orEmpty()
    return if (v.length <= 8) v else v.take(8) + "…"
}

private fun mlsRedactedError(e: Throwable): String {
    val lower = e.message.orEmpty().lowercase()
    return when {
        "hmac" in lower -> "hmac_error"
        "process_welcome" in lower || "welcome" in lower -> "welcome_error"
        "content" in lower || "payload" in lower || "plaintext" in lower || "secret" in lower || "private" in lower -> "redacted_error"
        else -> "mls_error"
    }
}

private fun mlsLogPrefixes(values: List<String>): List<String> = values.map { mlsLogPrefix(it) }

/**
 * Marmot/WhiteNoise interop relays.
 *
 * WhiteNoise diagnostics show Welcome inbox delivery and group-message fanout often use
 * auth.nostr1.com / relay.primal.net in addition to the user's selected relays. After an
 * Android reinstall the local MLS DB is empty, so rediscovering historical Kind-1059
 * Welcomes from these relays is required before subscribing to the group's Kind-445 #h feed.
 */
private val MLS_INTEROP_RELAYS = listOf(
    "wss://auth.nostr1.com",
    "wss://relay.damus.io",
    "wss://relay.primal.net",
    "wss://nos.lol",
    "wss://yabu.me",
    "wss://relay.nostr.band",
    "wss://purplepag.es"
)

// ─── MLS Groups (Marmot MIP-00〜03, WhiteNoise 互換) ─────────────────────────
//
// 設計方針:
//   - Rust SQLite (MDK) を single source of truth とし、アプリ側キャッシュは保持しない。
//   - mlsProcessedIds は relay イベントの二重復号防止のみに使用（セッション内）。
//   - processedWelcomeIds は Welcome の再処理を防止。

/** キャッシュファースト用: Rust 未接続でも即時表示可能なグループ一覧。 */
fun NostrRepository.getCachedMlsGroups(): List<MlsGroup> {
    val pubkey = prefs.publicKeyHex ?: return emptyList()
    val raw = cache.getCachedMlsGroups(pubkey) ?: return emptyList()
    return try {
        val allGroups = json.decodeFromString<List<MlsGroup>>(raw)
        val leftIds = cache.getLeftGroupIds()
        allGroups.filter { it.groupIdHex !in leftIds }
    } catch (_: Exception) { emptyList() }
}

/** Rust SQLite のローカル履歴のみ即時返す（ネットワーク不要）。 */
suspend fun NostrRepository.getLocalMlsMessages(groupIdHex: String): List<MlsMessage> {
    val rustClient = client.getRustClient() ?: return emptyList()
    return withContext(Dispatchers.IO) {
        try {
            val history = rustClient.mlsGetMessageHistory(groupIdHex, 200u)
            val senderPubkeys = history.map { it.senderPubkey }.distinct()
            val profiles = fetchProfiles(senderPubkeys)
            history.map { msg ->
                MlsMessage(
                    id = "${msg.senderPubkey}_${msg.timestamp}",
                    senderPubkey = msg.senderPubkey,
                    content = msg.content,
                    timestamp = msg.timestamp.toLong(),
                    groupIdHex = groupIdHex,
                    senderProfile = profiles[msg.senderPubkey]
                )
            }.sortedBy { it.timestamp }
        } catch (e: Exception) {
            android.util.Log.w("NostrRepository", "getLocalMlsMessages($groupIdHex): ${mlsRedactedError(e)}")
            emptyList()
        }
    }
}

suspend fun NostrRepository.fetchMlsGroups(): List<MlsGroup> {
    val pubkey = prefs.publicKeyHex ?: return emptyList()
    val rustClient = client.getRustClient() ?: return emptyList()

    return withContext(Dispatchers.IO) {
        try {
            // 1. Welcome イベントを取得 → 未処理分のみ process
            //    Marmot (MIP-02): Kind 1059 (NIP-59 gift-wrapped)
            //      - recipient は KeyPackage owner (= 自分の pubkey) の #p tag
            //      - 受信した signed 1059 event JSON をそのまま Rust に渡す
            //      - Rust 側 mlsProcessWelcome が unwrap → Kind 444 rumor process → join まで行う
            //    Legacy (NIP-EE): Kind 444 (raw rumor) も互換用に受ける
            //    WhiteNoise 等がデフォルト外リレーに publish する可能性あり
            //    → グローバルリレーも含めた広い範囲から取得
            val welcomeRelays = mlsPublishRelays()
            val giftWrapWelcomeFilter = NostrClient.Filter(
                kinds = listOf(NostrKind.MLS_WELCOME),
                tags = mapOf("p" to listOf(pubkey)),
                // Reinstall recovery needs historical Welcomes, not only the last few inbox items.
                limit = 200
            )
            val legacyWelcomeFilter = NostrClient.Filter(
                kinds = listOf(NostrKind.MLS_WELCOME_INNER),
                tags = mapOf("p" to listOf(pubkey)),
                limit = 200
            )
            val welcomeEvents = (client.fetchEventsFrom(welcomeRelays, giftWrapWelcomeFilter, timeoutMs = 8_000) +
                client.fetchEventsFrom(welcomeRelays, legacyWelcomeFilter, timeoutMs = 8_000))
                .distinctBy { it.id }
                .sortedBy { it.createdAt }
            val joinedGroupIds = mutableSetOf<String>()
            var newWelcomeCount = 0
            var skippedWelcomeCount = 0
            var failedWelcomeCount = 0
            for (event in welcomeEvents) {
                if (event.kind != NostrKind.MLS_WELCOME && event.kind != NostrKind.MLS_WELCOME_INNER) continue
                if (event.kind == NostrKind.MLS_WELCOME && event.getTagValues("p").none { it.equals(pubkey, ignoreCase = true) }) {
                    // 1059 の recipient は KeyPackage event owner pubkey。自分宛て以外は unwrap しない。
                    skippedWelcomeCount++
                    continue
                }
                if (processedWelcomeIds.contains(event.id)) {
                    skippedWelcomeCount++
                    continue
                }
                try {
                    val eventJson = json.encodeToString(NostrEvent.serializer(), event)
                    val joined = rustClient.mlsProcessWelcome(eventJson)
                    // FFI/App 境界の groupIdHex は Nostr group id。internal MLS group id は扱わない。
                    joinedGroupIds.add(joined.groupIdHex)
                    processedWelcomeIds.add(event.id)
                    rotateOwnKeyPackageAfterWelcome()
                    newWelcomeCount++
                    android.util.Log.d(
                        "NostrRepository",
                        "fetchMlsGroups: processed Welcome kind=${event.kind} event=${event.id} groupIdHex=${joined.groupIdHex} joinedAt=${event.createdAt}"
                    )
                } catch (e: Exception) {
                    failedWelcomeCount++
                    // 失敗した Welcome はセッション内 processed に入れず、次回 fetch で再試行可能にする。
                    android.util.Log.w(
                        "NostrRepository",
                        "fetchMlsGroups: failed to process Welcome kind=${event.kind} event=${event.id}: ${mlsRedactedError(e)}"
                    )
                }
            }
            if (newWelcomeCount > 0 || failedWelcomeCount > 0) {
                android.util.Log.d(
                    "NostrRepository",
                    "fetchMlsGroups: welcomes fetched=${welcomeEvents.size} processed=$newWelcomeCount skipped=$skippedWelcomeCount failed=$failedWelcomeCount joinedGroups=${joinedGroupIds.size}"
                )
            }

            // Welcome process 後の post-join self-update。
            // FFI/App 境界の groupIdHex は Nostr group id のまま扱う。
            // mlsGroupsNeedingSelfUpdate() も Nostr group id を返す contract なので retry source として使う。
            publishPendingMlsSelfUpdates(joinedGroupIds)

            // 2. Rust SQLite からグループ一覧（process success 後なので新規 join 済み group も含まれる）
            val ffiGroups = rustClient.mlsListGroups()
            val leftIds = cache.getLeftGroupIds()
            val activeGroups = ffiGroups.filter { it.groupIdHex !in leftIds }

            // 3. メンバープロファイルエンリッチ
            val allPubkeys = activeGroups.flatMap { it.memberPubkeys }.distinct()
            val profiles = fetchProfiles(allPubkeys)

            // 4. 各グループの最新メッセージを Rust SQLite から取得
            activeGroups.map { ffi ->
                val lastMsg = try {
                    rustClient.mlsGetMessageHistory(ffi.groupIdHex, 1u).firstOrNull()
                } catch (_: Exception) { null }
                MlsGroup(
                    groupIdHex = ffi.groupIdHex,
                    name = ffi.name,
                    description = ffi.description,
                    adminPubkeys = ffi.adminPubkeys,
                    memberPubkeys = ffi.memberPubkeys,
                    relays = ffi.relays,
                    createdAt = ffi.createdAt.toLong(),
                    epoch = ffi.epoch.toLong(),
                    isDm = ffi.isDm,
                    memberProfiles = ffi.memberPubkeys.mapNotNull { pk ->
                        profiles[pk]?.let { pk to it }
                    }.toMap(),
                    lastMessage = lastMsg?.content ?: "",
                    lastMessageTime = lastMsg?.timestamp?.toLong() ?: ffi.createdAt.toLong()
                )
            }.sortedByDescending { it.lastMessageTime }.also { result ->
                // 次回起動時の即時表示用にキャッシュ永続化
                try { cache.setCachedMlsGroups(pubkey, json.encodeToString(result)) } catch (_: Exception) { }
            }
        } catch (e: Exception) {
            android.util.Log.e("NostrRepository", "fetchMlsGroups failed: ${mlsRedactedError(e)}")
            getCachedMlsGroups()
        }
    }
}

/**
 * グループのメッセージを取得する。
 *
 * 1. グループのリレーリストを取得（グループメタデータ → デフォルトリレー fallback）
 * 2. Kind-445 を**グループのリレー＋デフォルトリレー**から取得
 * 3. 未処理分を mlsProcessMessageResult で復号または state update 適用
 * 4. Rust SQLite から全履歴を返す（= single source of truth）
 * - Commit/Proposal は StateUpdate として処理済みにする
 * - relay out-of-order で今は処理できないイベントは processedIds に入れず retry queue に残す
 */
suspend fun NostrRepository.fetchMlsMessages(groupIdHex: String): List<MlsMessage> {
    val rustClient = client.getRustClient() ?: return emptyList()

    return withContext(Dispatchers.IO) {
        try {
            // FFI/App 境界の groupIdHex は Nostr group id。internal MLS group id は扱わない。
            val processedIds = mlsProcessedIds.getOrPut(groupIdHex) {
                java.util.concurrent.ConcurrentHashMap.newKeySet()
            }
            val retryQueue = mlsMessageRetryQueues.getOrPut(groupIdHex) {
                java.util.concurrent.ConcurrentHashMap<String, NostrEvent>()
            }

            // 1. グループのリレーリストを取得
            val groupRelays = try {
                rustClient.mlsGetGroupInfo(groupIdHex)?.relays ?: emptyList()
            } catch (_: Exception) { emptyList() }

            // デフォルトリレー + グループリレー + Marmot interop fallback を統合（重複排除）。
            // iOS/WhiteNoise が group relay 外にも self-update/message を publish するケースを拾う。
            val allRelays = mlsPublishRelays(groupRelays)

            android.util.Log.d("NostrRepository",
                "fetchMlsMessages($groupIdHex): groupRelays=$groupRelays, allRelays=$allRelays")

            // 2. Kind-445 をグループのリレーから取得して未処理分を process
            val filter = NostrClient.Filter(
                kinds = listOf(NostrKind.MLS_GROUP_MESSAGE),
                tags = mapOf("h" to listOf(groupIdHex)),
                limit = 100
            )

            // 特定リレーから取得（自動追加・接続も行われる）
            val events = if (allRelays.isNotEmpty()) {
                client.fetchEventsFrom(allRelays, filter, timeoutMs = 8_000)
            } else {
                client.fetchEvents(filter, timeoutMs = 5_000)
            }.distinctBy { it.id }

            android.util.Log.d("NostrRepository",
                "fetchMlsMessages($groupIdHex): fetched ${events.size} Kind-445 events")

            var applied = 0
            var stateOnly = 0
            var dropped = 0
            var retryable = 0
            var duplicates = 0

            fun processCandidate(event: NostrEvent): MlsProcessPolicy {
                val shapePolicy = event.mlsKind445ShapePolicy(groupIdHex)
                if (shapePolicy != null) return shapePolicy

                return try {
                    val eventJson = json.encodeToString(NostrEvent.serializer(), event)
                    when (rustClient.mlsProcessMessageResult(groupIdHex, eventJson)) {
                        is uniffi.nurunuru.FfiMlsProcessResult.Application -> {
                            applied++
                            MlsProcessPolicy.Processed
                        }
                        is uniffi.nurunuru.FfiMlsProcessResult.StateUpdate -> {
                            stateOnly++
                            MlsProcessPolicy.StateUpdated
                        }
                    }
                } catch (e: Exception) {
                    if (e.isRetryableMlsProcessError()) {
                        MlsProcessPolicy.Retryable
                    } else {
                        MlsProcessPolicy.Dropped
                    }
                }
            }

            fun handleEvent(event: NostrEvent): MlsProcessPolicy {
                if (event.id.isBlank()) {
                    dropped++
                    return MlsProcessPolicy.Dropped
                }
                if (processedIds.contains(event.id)) {
                    duplicates++
                    retryQueue.remove(event.id)
                    return MlsProcessPolicy.AlreadyProcessed
                }

                val policy = processCandidate(event)
                when (policy) {
                    MlsProcessPolicy.Processed,
                    MlsProcessPolicy.StateUpdated,
                    MlsProcessPolicy.Dropped -> {
                        // invalid shape / wrong h-tag / invalid kind / unrecoverable process errors are dropped idempotently.
                        processedIds.add(event.id)
                        retryQueue.remove(event.id)
                        if (policy == MlsProcessPolicy.Dropped) dropped++
                    }
                    MlsProcessPolicy.Retryable -> {
                        // relay out-of-order: do not mark processed; retry after state update or next fetch.
                        retryQueue[event.id] = event
                        retryable++
                    }
                    MlsProcessPolicy.AlreadyProcessed -> Unit
                }
                return policy
            }

            for (event in events.sortedWith(compareBy<NostrEvent> { it.createdAt }.thenBy { it.id })) {
                handleEvent(event)
            }

            // state update 適用後は out-of-order で保留していたイベントを再走査する。
            var retryPasses = 0
            var progressed: Boolean
            do {
                progressed = false
                val pending = retryQueue.values
                    .filter { !processedIds.contains(it.id) }
                    .sortedWith(compareBy<NostrEvent> { it.createdAt }.thenBy { it.id })
                if (pending.isEmpty()) break

                for (event in pending) {
                    val beforeProcessed = processedIds.contains(event.id)
                    val policy = handleEvent(event)
                    if (!beforeProcessed && (policy == MlsProcessPolicy.Processed ||
                            policy == MlsProcessPolicy.StateUpdated ||
                            policy == MlsProcessPolicy.Dropped)) {
                        progressed = true
                    }
                }
                retryPasses++
            } while (progressed && retryPasses < 4)

            android.util.Log.d("NostrRepository",
                "fetchMlsMessages($groupIdHex): applied=$applied stateOnly=$stateOnly dropped=$dropped retryable=$retryable duplicates=$duplicates retryQueued=${retryQueue.size}")

            // 3. Rust SQLite から全履歴（= single source of truth）
            val history = rustClient.mlsGetMessageHistory(groupIdHex, 200u)

            // 4. プロファイルエンリッチ
            val senderPubkeys = history.map { it.senderPubkey }.distinct()
            val profiles = fetchProfiles(senderPubkeys)

            history.map { msg ->
                MlsMessage(
                    id = "${msg.senderPubkey}_${msg.timestamp}",
                    senderPubkey = msg.senderPubkey,
                    content = msg.content,
                    timestamp = msg.timestamp.toLong(),
                    groupIdHex = groupIdHex,
                    senderProfile = profiles[msg.senderPubkey]
                )
            }.sortedBy { it.timestamp }
        } catch (e: Exception) {
            android.util.Log.e("NostrRepository", "fetchMlsMessages($groupIdHex) failed: ${mlsRedactedError(e)}")
            emptyList()
        }
    }
}


/**
 * Welcome process 後、および前回 publish/merge に失敗した group の self-update を publish する。
 *
 * Flow は Marmot P4-S2 の policy に合わせる:
 *   mlsCreateRecoveryCommit(groupIdHex) -> publish Kind 445 -> success なら mlsMergePendingCommit(groupIdHex)
 * publish fail 時は pending commit を clear し、次回 mlsGroupsNeedingSelfUpdate() から再作成できるようにする。
 *
 * groupIdHex は FFI/App 境界 contract どおり Nostr group id。internal MLS group id は扱わない。
 */
private suspend fun NostrRepository.publishPendingMlsSelfUpdates(
    joinedGroupIds: Set<String> = emptySet()
) = withContext(Dispatchers.IO) {
    val rustClient = client.getRustClient() ?: return@withContext

    val retryGroupIds = try {
        // thresholdSecs=0: Rust/MDK が self-update 必要と判断する group を全て retry 対象にする。
        rustClient.mlsGroupsNeedingSelfUpdate(0uL)
    } catch (e: Exception) {
        android.util.Log.w("NostrRepository", "mlsGroupsNeedingSelfUpdate unavailable/failed: ${mlsRedactedError(e)}")
        emptyList()
    }

    val targetGroupIds = (joinedGroupIds + retryGroupIds)
        .map { it.trim() }
        .filter { it.length == 64 && it.all { c -> c in '0'..'9' || c in 'a'..'f' || c in 'A'..'F' } }
        .distinct()

    if (targetGroupIds.isEmpty()) return@withContext

    var success = 0
    var failed = 0
    for (groupIdHex in targetGroupIds) {
        try {
            val groupRelays = try {
                rustClient.mlsGetGroupInfo(groupIdHex)?.relays ?: emptyList()
            } catch (_: Exception) { emptyList() }
            val recoveryCommit = rustClient.mlsCreateRecoveryCommit(groupIdHex)
            val published = publishMlsKind445(recoveryCommit, mlsPublishRelays(groupRelays))
            if (published) {
                rustClient.mlsMergePendingCommit(groupIdHex)
                prefs.setMlsSelfUpdateSuccessAt(groupIdHex, System.currentTimeMillis() / 1000)
                success++
                android.util.Log.d(
                    "NostrRepository",
                    "publishPendingMlsSelfUpdates: published+merged groupIdHex=$groupIdHex"
                )
            } else {
                failed++
                try { rustClient.mlsClearPendingCommit(groupIdHex) } catch (clearError: Exception) {
                    android.util.Log.w(
                        "NostrRepository",
                        "publishPendingMlsSelfUpdates: clear pending failed groupIdHex=$groupIdHex: ${mlsRedactedError(clearError)}"
                    )
                }
                android.util.Log.w(
                    "NostrRepository",
                    "publishPendingMlsSelfUpdates: publish failed; pending cleared for retry groupIdHex=$groupIdHex"
                )
            }
        } catch (e: Exception) {
            failed++
            try { rustClient.mlsClearPendingCommit(groupIdHex) } catch (clearError: Exception) {
                android.util.Log.w(
                    "NostrRepository",
                    "publishPendingMlsSelfUpdates: clear pending after error failed groupIdHex=$groupIdHex: ${mlsRedactedError(clearError)}"
                )
            }
            android.util.Log.w(
                "NostrRepository",
                "publishPendingMlsSelfUpdates: failed groupIdHex=$groupIdHex: ${mlsRedactedError(e)}"
            )
        }
    }

    android.util.Log.d(
        "NostrRepository",
        "publishPendingMlsSelfUpdates: targets=${targetGroupIds.size} success=$success failed=$failed"
    )
}

private val mlsMessageRetryQueues = java.util.concurrent.ConcurrentHashMap<String, MutableMap<String, NostrEvent>>()

private enum class MlsProcessPolicy {
    Processed,
    StateUpdated,
    Retryable,
    Dropped,
    AlreadyProcessed
}

private fun String.isHex64(): Boolean =
    length == 64 && all { it in '0'..'9' || it in 'a'..'f' || it in 'A'..'F' }

/**
 * Pre-FFI validation for Kind-445 envelope only. MLS payload is never logged or inspected here.
 * Drop malformed/wrong-group events idempotently; retry only events that have a valid envelope.
 */
private fun NostrEvent.mlsKind445ShapePolicy(groupIdHex: String): MlsProcessPolicy? {
    if (kind != NostrKind.MLS_GROUP_MESSAGE) return MlsProcessPolicy.Dropped
    if (!id.isHex64() || !pubkey.isHex64() || !sig.isHex64()) return MlsProcessPolicy.Dropped
    val hTags = getTagValues("h")
    if (hTags.none { it.equals(groupIdHex, ignoreCase = true) }) return MlsProcessPolicy.Dropped
    return null
}

/**
 * Classify FFI failures without logging payload/plaintext/secrets.
 * Retryable means relay out-of-order or local state not caught up yet; keep it out of processedIds.
 */
private fun Exception.isRetryableMlsProcessError(): Boolean {
    val msg = (message ?: "").lowercase()
    val droppedSignals = listOf(
        "invalid event", "invalid kind", "wrong kind", "missing h", "wrong h", "group mismatch",
        "bad signature", "invalid signature", "malformed", "deserialize", "json", "not a nostr event"
    )
    if (droppedSignals.any { msg.contains(it) }) return false

    val retrySignals = listOf(
        "epoch", "generation", "out of order", "pending", "state", "commit", "proposal",
        "unknown sender", "sender", "member", "ratchet", "decrypt", "decryption", "welcome",
        "not found", "does not exist", "missing", "stale", "future"
    )
    return retrySignals.any { msg.contains(it) }
}

suspend fun NostrRepository.sendMlsMessage(groupIdHex: String, content: String): Boolean {
    val rustClient = client.getRustClient() ?: return false
    return withContext(Dispatchers.IO) {
        try {
            // グループのリレーを動的追加（相手側クライアントが見れるように）
            val groupRelays = try {
                rustClient.mlsGetGroupInfo(groupIdHex)?.relays ?: emptyList()
            } catch (_: Exception) { emptyList() }
            for (relay in groupRelays) {
                try { client.addRelay(relay) } catch (_: Exception) { }
            }

            val ffiMsg = rustClient.mlsCreateMessage(groupIdHex, content)
            val published = publishMlsKind445(ffiMsg, mlsPublishRelays(groupRelays))
            if (published) {
                // 送信済みイベント ID を processedIds に登録 → relay 再取得時の二重復号防止
                try {
                    val eventObj = json.decodeFromString<NostrEvent>(ffiMsg.content)
                    mlsProcessedIds.getOrPut(groupIdHex) {
                        java.util.concurrent.ConcurrentHashMap.newKeySet()
                    }.add(eventObj.id)
                } catch (_: Exception) { }
            }
            published
        } catch (e: Exception) {
            android.util.Log.e("NostrRepository", "sendMlsMessage failed: ${mlsRedactedError(e)}")
            false
        }
    }
}

suspend fun NostrRepository.createDmGroup(partnerPubkey: String): MlsGroup? {
    val rustClient = client.getRustClient() ?: return null
    ensureKeyPackagePublished()

    return withContext(Dispatchers.IO) {
        try {
            val relays = prefs.relays.take(3).toList()
            val ffiGroup = rustClient.mlsCreateGroup(
                name = "", adminPubkeys = listOf(myPubkeyHex), relays = relays
            )

            val kpEvent = fetchKeyPackage(partnerPubkey, relays)
            if (kpEvent != null) {
                val kpJson = json.encodeToString(NostrEvent.serializer(),
                    patchKeyPackageRelays(kpEvent, relays))
                val addResult = rustClient.mlsAddMember(ffiGroup.groupIdHex, kpJson)
                val addPublished = publishAddMemberCommitWelcomeAndMerge(
                    groupIdHex = ffiGroup.groupIdHex,
                    commitEventData = addResult.commitEventData,
                    welcomeEventData = addResult.welcomeEventData,
                    keyPackageEventId = kpEvent.id,
                    publishRelays = mlsPublishRelays(ffiGroup.relays + relays),
                    context = "createDmGroup"
                )
                if (!addPublished) return@withContext null
            }

            val freshGroup = try { rustClient.mlsGetGroupInfo(ffiGroup.groupIdHex) } catch (_: Exception) { null }
            val memberPubkeys = freshGroup?.memberPubkeys ?: listOf(myPubkeyHex, partnerPubkey).distinct()
            val profiles = fetchProfiles(memberPubkeys)
            MlsGroup(
                groupIdHex = ffiGroup.groupIdHex,
                name = ffiGroup.name, description = ffiGroup.description,
                adminPubkeys = ffiGroup.adminPubkeys, memberPubkeys = memberPubkeys,
                relays = ffiGroup.relays, createdAt = ffiGroup.createdAt.toLong(),
                epoch = ffiGroup.epoch.toLong(), isDm = true,
                memberProfiles = memberPubkeys.mapNotNull { pk -> profiles[pk]?.let { pk to it } }.toMap()
            )
        } catch (e: Exception) {
            android.util.Log.e("NostrRepository", "createDmGroup failed: ${mlsRedactedError(e)}")
            null
        }
    }
}

suspend fun NostrRepository.createGroupChat(name: String, memberPubkeys: List<String>): MlsGroup? {
    val rustClient = client.getRustClient() ?: return null
    ensureKeyPackagePublished()

    return withContext(Dispatchers.IO) {
        try {
            val relays = prefs.relays.take(3).toList()
            val ffiGroup = rustClient.mlsCreateGroup(
                name = name, adminPubkeys = listOf(myPubkeyHex), relays = relays
            )

            // KeyPackage 取得: Kind 30443 + legacy 443。ローカル consumed set にある event id は再利用しない。
            for (memberPubkey in memberPubkeys.distinct()) {
                val kpEvent = fetchKeyPackage(memberPubkey, relays) ?: continue
                try {
                    val kpJson = json.encodeToString(NostrEvent.serializer(),
                        patchKeyPackageRelays(kpEvent, relays))
                    val addResult = rustClient.mlsAddMember(ffiGroup.groupIdHex, kpJson)
                    publishAddMemberCommitWelcomeAndMerge(
                        groupIdHex = ffiGroup.groupIdHex,
                        commitEventData = addResult.commitEventData,
                        welcomeEventData = addResult.welcomeEventData,
                        keyPackageEventId = kpEvent.id,
                        publishRelays = mlsPublishRelays(ffiGroup.relays + relays),
                        context = "createGroupChat"
                    )
                } catch (e: Exception) {
                    android.util.Log.w("NostrRepository", "createGroupChat: add member failed member=${mlsLogPrefix(memberPubkey)}: ${mlsRedactedError(e)}")
                }
            }

            val freshGroup = try { rustClient.mlsGetGroupInfo(ffiGroup.groupIdHex) } catch (_: Exception) { null }
            val allMembers = freshGroup?.memberPubkeys ?: (listOf(myPubkeyHex) + memberPubkeys).distinct()
            val profiles = fetchProfiles(allMembers)
            MlsGroup(
                groupIdHex = ffiGroup.groupIdHex,
                name = ffiGroup.name, description = ffiGroup.description,
                adminPubkeys = ffiGroup.adminPubkeys, memberPubkeys = allMembers,
                relays = ffiGroup.relays, createdAt = ffiGroup.createdAt.toLong(),
                epoch = ffiGroup.epoch.toLong(), isDm = false,
                memberProfiles = allMembers.mapNotNull { pk -> profiles[pk]?.let { pk to it } }.toMap()
            )
        } catch (e: Exception) {
            android.util.Log.e("NostrRepository", "createGroupChat failed: ${mlsRedactedError(e)}")
            null
        }
    }
}

suspend fun NostrRepository.leaveGroup(groupIdHex: String): Boolean {
    val rustClient = client.getRustClient() ?: return false
    return withContext(Dispatchers.IO) {
        try {
            try { rustClient.mlsMergePendingCommit(groupIdHex) } catch (_: Exception) { }
            val groupRelays = try {
                rustClient.mlsGetGroupInfo(groupIdHex)?.relays ?: emptyList()
            } catch (_: Exception) { emptyList() }
            val ffiMsg = rustClient.mlsLeaveGroup(groupIdHex)
            publishMlsKind445(ffiMsg, mlsPublishRelays(groupRelays))
            cache.markGroupAsLeft(groupIdHex)
            mlsProcessedIds.remove(groupIdHex)
            true
        } catch (e: Exception) {
            android.util.Log.e("NostrRepository", "leaveGroup failed: ${mlsRedactedError(e)}")
            false
        }
    }
}

suspend fun NostrRepository.addMemberToGroup(groupIdHex: String, memberPubkey: String): Boolean {
    val rustClient = client.getRustClient() ?: return false
    return withContext(Dispatchers.IO) {
        try {
            val relays = prefs.relays.take(3).toList()
            val kpEvent = fetchKeyPackage(memberPubkey, relays) ?: return@withContext false
            val kpJson = json.encodeToString(NostrEvent.serializer(),
                patchKeyPackageRelays(kpEvent, relays))
            val groupRelays = try {
                rustClient.mlsGetGroupInfo(groupIdHex)?.relays ?: emptyList()
            } catch (_: Exception) { emptyList() }
            val addResult = rustClient.mlsAddMember(groupIdHex, kpJson)
            publishAddMemberCommitWelcomeAndMerge(
                groupIdHex = groupIdHex,
                commitEventData = addResult.commitEventData,
                welcomeEventData = addResult.welcomeEventData,
                keyPackageEventId = kpEvent.id,
                publishRelays = mlsPublishRelays(groupRelays + relays),
                context = "addMemberToGroup"
            )
        } catch (e: Exception) {
            android.util.Log.e("NostrRepository", "addMemberToGroup failed: ${mlsRedactedError(e)}")
            false
        }
    }
}

suspend fun NostrRepository.removeMemberFromGroup(groupIdHex: String, memberPubkey: String): Boolean {
    val rustClient = client.getRustClient() ?: return false
    return withContext(Dispatchers.IO) {
        try {
            val groupRelays = try {
                rustClient.mlsGetGroupInfo(groupIdHex)?.relays ?: emptyList()
            } catch (_: Exception) { emptyList() }
            val ffiMsg = rustClient.mlsRemoveMember(groupIdHex, memberPubkey)
            publishMlsKind445(ffiMsg, mlsPublishRelays(groupRelays))
            try { rustClient.mlsMergePendingCommit(groupIdHex) } catch (_: Exception) { }
            true
        } catch (e: Exception) {
            android.util.Log.e("NostrRepository", "removeMemberFromGroup failed: ${mlsRedactedError(e)}")
            false
        }
    }
}

suspend fun NostrRepository.ensureKeyPackagePublished() {
    val pubkey = prefs.publicKeyHex ?: return
    val rustClient = client.getRustClient() ?: return
    withContext(Dispatchers.IO) {
        try {
            val consumedIds = prefs.mlsConsumedKeyPackageEventIds
            val existing = client.fetchEvents(
                NostrClient.Filter(
                    // Fetch both Marmot canonical 30443 and legacy 443; constants are historical.
                    kinds = listOf(NostrKind.MLS_KEY_PACKAGE_LEGACY, NostrKind.MLS_KEY_PACKAGE),
                    authors = listOf(pubkey), limit = 10
                ), timeoutMs = 3_000
            ).filter { it.id.lowercase() !in consumedIds }
            val latest = existing.maxByOrNull { it.createdAt }
            val hasRelays = latest?.tags?.any { tag ->
                tag.firstOrNull() == "relays" && tag.size > 1
            } ?: false
            if (latest != null && hasRelays) {
                if (prefs.mlsPublishedKeyPackageEventId?.equals(latest.id, ignoreCase = true) != true) {
                    prefs.mlsPublishedKeyPackageEventId = latest.id
                    prefs.mlsPublishedKeyPackageAt = latest.createdAt
                }
                return@withContext
            }

            publishKeyPackage()
        } catch (e: Exception) {
            android.util.Log.w("NostrRepository", "ensureKeyPackagePublished: ${mlsRedactedError(e)}")
        }
    }
}

/**
 * Welcome process means our currently published KeyPackage was consumed by the inviter.
 * Track it locally, best-effort delete it from relays, remove matching local init-key material,
 * then publish a fresh KeyPackage so future invites do not reuse the consumed one.
 */
private suspend fun NostrRepository.rotateOwnKeyPackageAfterWelcome() {
    val oldEventId = prefs.mlsPublishedKeyPackageEventId?.trim()?.takeIf { it.isNotEmpty() } ?: return
    if (oldEventId.lowercase() in prefs.mlsConsumedKeyPackageEventIds) return

    prefs.addMlsConsumedKeyPackageEventId(oldEventId)

    val rustClient = client.getRustClient()
    val oldEvent = try {
        client.fetchEvents(NostrClient.Filter(ids = listOf(oldEventId), limit = 1), timeoutMs = 3_000)
            .firstOrNull { it.id.equals(oldEventId, ignoreCase = true) }
    } catch (_: Exception) { null }

    if (rustClient != null && oldEvent != null) {
        try {
            val oldEventJson = json.encodeToString(NostrEvent.serializer(), oldEvent)
            rustClient.mlsDeleteConsumedKeyPackageFromEventJson(oldEventJson)
        } catch (e: Exception) {
            android.util.Log.w("NostrRepository", "rotateOwnKeyPackageAfterWelcome: local consumed KeyPackage cleanup failed: ${mlsRedactedError(e)}")
        }
    }

    try {
        // NIP-09 delete is relay best-effort. The local consumed set above remains authoritative.
        deleteEvent(oldEventId, "consumed MLS KeyPackage")
    } catch (e: Exception) {
        android.util.Log.w("NostrRepository", "rotateOwnKeyPackageAfterWelcome: best-effort delete failed: ${mlsRedactedError(e)}")
    }

    prefs.mlsPublishedKeyPackageEventId = null
    prefs.mlsPublishedKeyPackageAt = 0L
    publishKeyPackage()
}

// ─── Private Helpers ─────────────────────────────────────────────────────────

private suspend fun NostrRepository.fetchKeyPackage(
    pubkey: String, fallbackRelays: List<String>
): NostrEvent? {
    val kpFilter = NostrClient.Filter(
        kinds = listOf(NostrKind.MLS_KEY_PACKAGE, NostrKind.MLS_KEY_PACKAGE_LEGACY),
        authors = listOf(pubkey), limit = 10
    )
    val consumedIds = prefs.mlsConsumedKeyPackageEventIds
    val kpEvents = client.fetchEvents(kpFilter, timeoutMs = 5_000)
        .filter { it.id.lowercase() !in consumedIds }
    // Marmot canonical KeyPackage is kind 30443; legacy kind 443 is fallback.
    // Constant names are historical in this module: MLS_KEY_PACKAGE_LEGACY == 30443.
    return kpEvents.filter { it.kind == NostrKind.MLS_KEY_PACKAGE_LEGACY }.maxByOrNull { it.createdAt }
        ?: kpEvents.filter { it.kind == NostrKind.MLS_KEY_PACKAGE }.maxByOrNull { it.createdAt }
        ?: kpEvents.maxByOrNull { it.createdAt }
}

private fun patchKeyPackageRelays(kpEvent: NostrEvent, fallbackRelays: List<String>): NostrEvent {
    val hasRelays = kpEvent.tags.any { tag -> tag.firstOrNull() == "relays" && tag.size > 1 }
    if (hasRelays) return kpEvent
    val relayTag = listOf("relays") + fallbackRelays
    val patchedTags = kpEvent.tags.map { tag ->
        if (tag.firstOrNull() == "relays") relayTag else tag
    }.let { if (it.none { t -> t.firstOrNull() == "relays" }) it + listOf(relayTag) else it }
    return kpEvent.copy(tags = patchedTags)
}

private suspend fun NostrRepository.publishKeyPackage() {
    val rustClient = client.getRustClient() ?: return
    try {
        val kpData = rustClient.mlsCreateKeyPackage()
        val tags = if (kpData.tags.any { it.firstOrNull() == "relays" && it.size > 1 }) {
            kpData.tags
        } else {
            val relayUrls = prefs.relays.take(3).toList()
            val relayTag = listOf("relays") + relayUrls
            kpData.tags.map { tag ->
                if (tag.firstOrNull() == "relays") relayTag else tag
            }
        }
        val eventId = if (isExternalSigner()) {
            val unsigned = rustClient.createUnsignedEvent(kpData.kind, kpData.content, tags, myPubkeyHex)
            signAndPublishGetId(unsigned)
        } else {
            rustClient.publishEvent(kpData.kind, kpData.content, tags).takeIf { it.isNotEmpty() }
        }
        if (eventId != null) {
            prefs.mlsPublishedKeyPackageEventId = eventId
            prefs.mlsPublishedKeyPackageAt = System.currentTimeMillis() / 1000
        }
    } catch (e: Exception) {
        android.util.Log.e("NostrRepository", "publishKeyPackage failed: ${mlsRedactedError(e)}")
    }
}

/**
 * Marmot MLS publish target relays.
 *
 * Android/iOS interop: publish/fetch MLS traffic on group relays, selected relays,
 * and common global fallback relays so Bob self-update and follow-up messages are
 * discoverable even when each platform has a different selected relay set.
 */
private fun NostrRepository.mlsPublishRelays(groupRelays: List<String> = emptyList()): List<String> =
    (groupRelays + prefs.relays.toList() + MLS_INTEROP_RELAYS)
        .map { it.trim() }
        .filter { it.startsWith("wss://") || it.startsWith("ws://") }
        .distinct()

private data class MlsRawEventSummary(
    val id: String,
    val kind: Int?,
    val pubkey: String,
    val hTags: List<String>,
    val pTags: List<String>
)

private fun mlsRawEventSummary(rawEventJson: String): MlsRawEventSummary? = try {
    val obj = Json.parseToJsonElement(rawEventJson).jsonObject
    val tags = obj["tags"]?.jsonArray?.mapNotNull { tagEl ->
        tagEl.jsonArray.mapNotNull { it.jsonPrimitive.contentOrNull }
    } ?: emptyList()
    MlsRawEventSummary(
        id = obj["id"]?.jsonPrimitive?.contentOrNull.orEmpty(),
        kind = obj["kind"]?.jsonPrimitive?.intOrNull,
        pubkey = obj["pubkey"]?.jsonPrimitive?.contentOrNull.orEmpty(),
        hTags = tags.filter { it.firstOrNull() == "h" }.mapNotNull { it.getOrNull(1) },
        pTags = tags.filter { it.firstOrNull() == "p" }.mapNotNull { it.getOrNull(1) }
    )
} catch (_: Exception) { null }

private suspend fun NostrRepository.connectMlsPublishRelays(relays: List<String>) {
    val rustClient = client.getRustClient() ?: return
    relays.forEach { relay ->
        try { rustClient.addRelay(relay) } catch (e: Exception) {
            android.util.Log.w("NostrRepository", "connectMlsPublishRelays: addRelay failed relay=$relay: ${mlsRedactedError(e)}")
        }
    }
}

/**
 * Kind-445 (MLS message/commit/proposal) を publish。
 * content は MDK がエフェメラル鍵で署名済みの完全なイベントJSON → publishRawEvent 必須。
 */
private suspend fun NostrRepository.publishMlsKind445(
    ffiMsg: FfiEncryptedMessageData,
    publishRelays: List<String> = mlsPublishRelays()
): Boolean {
    val rustClient = client.getRustClient() ?: return false
    val summary = mlsRawEventSummary(ffiMsg.content)
    return try {
        connectMlsPublishRelays(publishRelays)
        val publishedId = rustClient.publishRawEvent(ffiMsg.content)
        android.util.Log.d(
            "NostrRepository",
            "publishMlsKind445: ok event=${summary?.id ?: publishedId} kind=${summary?.kind} h=${summary?.hTags.orEmpty()} relays=${publishRelays.size}"
        )
        true
    } catch (e: Exception) {
        android.util.Log.e(
            "NostrRepository",
            "publishMlsKind445 failed event=${summary?.id.orEmpty()} kind=${summary?.kind} h=${summary?.hTags.orEmpty()} relays=${publishRelays.size}: ${mlsRedactedError(e)}"
        )
        false
    }
}

/**
 * Marmot MIP-02: gift-wrapped Welcome (Kind 1059) を publish。
 * Welcome 1059 の recipient は KeyPackage event owner pubkey (= welcomeData.recipientPubkey)。
 */
private suspend fun NostrRepository.publishMlsWelcome(
    welcomeData: uniffi.nurunuru.FfiWelcomeEventData,
    publishRelays: List<String> = mlsPublishRelays()
): Boolean {
    val rustClient = client.getRustClient() ?: return false
    return try {
        if (welcomeData.giftWrappedEventJson.isNotEmpty()) {
            val summary = mlsRawEventSummary(welcomeData.giftWrappedEventJson)
            connectMlsPublishRelays(publishRelays)
            val publishedId = rustClient.publishRawEvent(welcomeData.giftWrappedEventJson)
            android.util.Log.d(
                "NostrRepository",
                "publishMlsWelcome: ok event=${summary?.id ?: publishedId} kind=${summary?.kind} p=${mlsLogPrefixes(summary?.pTags.orEmpty())} recipient=${mlsLogPrefix(welcomeData.recipientPubkey)} relays=${publishRelays.size}"
            )
            true
        } else {
            android.util.Log.w("NostrRepository", "publishMlsWelcome: no gift-wrap — legacy 444 fallback")
            val tags = welcomeData.tags + listOf(listOf("p", welcomeData.recipientPubkey))
            val ok = if (isExternalSigner()) {
                val unsigned = rustClient.createUnsignedEvent(
                    NostrKind.MLS_WELCOME_INNER.toUInt(), welcomeData.innerRumorJson, tags, myPubkeyHex
                )
                signAndPublish(unsigned)
            } else {
                rustClient.publishEvent(NostrKind.MLS_WELCOME_INNER.toUInt(), welcomeData.innerRumorJson, tags).isNotEmpty()
            }
            android.util.Log.d(
                "NostrRepository",
                "publishMlsWelcome: legacy kind=${NostrKind.MLS_WELCOME_INNER} p=${mlsLogPrefixes(tags.filter { it.firstOrNull() == "p" }.mapNotNull { it.getOrNull(1) })} recipient=${mlsLogPrefix(welcomeData.recipientPubkey)} ok=$ok"
            )
            ok
        }
    } catch (e: Exception) {
        android.util.Log.e(
            "NostrRepository",
            "publishMlsWelcome failed recipient=${mlsLogPrefix(welcomeData.recipientPubkey)}: ${mlsRedactedError(e)}"
        )
        false
    }
}

/**
 * Add-member publish/merge policy shared by DM/group/add-member flows.
 *
 * P4-S2-compatible policy:
 *  - publish Welcome only after commit Kind-445 publish succeeds;
 *  - merge pending commit only after the required publish sequence succeeds;
 *  - on publish/merge failure, clear pending commit so retry can create a fresh commit.
 */
private suspend fun NostrRepository.publishAddMemberCommitWelcomeAndMerge(
    groupIdHex: String,
    commitEventData: FfiEncryptedMessageData,
    welcomeEventData: uniffi.nurunuru.FfiWelcomeEventData,
    keyPackageEventId: String,
    publishRelays: List<String>,
    context: String
): Boolean {
    val rustClient = client.getRustClient() ?: return false
    fun clearPending(reason: String) {
        try { rustClient.mlsClearPendingCommit(groupIdHex) } catch (clearError: Exception) {
            android.util.Log.w(
                "NostrRepository",
                "$context: clear pending failed groupIdHex=$groupIdHex reason=$reason: ${mlsRedactedError(clearError)}"
            )
        }
    }

    val commitPublished = publishMlsKind445(commitEventData, publishRelays)
    if (!commitPublished) {
        clearPending("commit-publish-failed")
        android.util.Log.w("NostrRepository", "$context: commit publish failed; Welcome skipped groupIdHex=$groupIdHex")
        return false
    }

    val welcomePublished = publishMlsWelcome(welcomeEventData, publishRelays)
    if (!welcomePublished) {
        clearPending("welcome-publish-failed")
        android.util.Log.w("NostrRepository", "$context: Welcome publish failed; merge skipped groupIdHex=$groupIdHex")
        return false
    }

    return try {
        rustClient.mlsMergePendingCommit(groupIdHex)
        prefs.addMlsConsumedKeyPackageEventId(keyPackageEventId)
        android.util.Log.d("NostrRepository", "$context: commit+Welcome published and merged groupIdHex=$groupIdHex keyPackageEvent=$keyPackageEventId")
        true
    } catch (e: Exception) {
        clearPending("merge-failed")
        android.util.Log.w("NostrRepository", "$context: merge failed; pending cleared groupIdHex=$groupIdHex: ${mlsRedactedError(e)}")
        false
    }
}

// ─── Legacy DM (read-only, migration only) ───────────────────────────────────

@Deprecated("Use MLS groups for new conversations")
suspend fun NostrRepository.fetchDmConversations(pubkeyHex: String): List<DmConversation> {
    val oneHourAgo = getOneHourAgo()
    val receivedFilter = NostrClient.Filter(
        kinds = listOf(NostrKind.ENCRYPTED_DM),
        tags = mapOf("p" to listOf(pubkeyHex)),
        limit = 200, since = oneHourAgo
    )
    val sentFilter = NostrClient.Filter(
        kinds = listOf(NostrKind.ENCRYPTED_DM),
        authors = listOf(pubkeyHex),
        limit = 200, since = oneHourAgo
    )
    val allEvents = coroutineScope {
        val received = async { client.fetchEvents(receivedFilter, 5_000) }
        val sent = async { client.fetchEvents(sentFilter, 5_000) }
        received.await() + sent.await()
    }

    val conversations = mutableMapOf<String, MutableList<NostrEvent>>()
    for (event in allEvents) {
        val partner = if (event.pubkey == pubkeyHex) {
            event.getTagValue("p") ?: continue
        } else { event.pubkey }
        conversations.getOrPut(partner) { mutableListOf() }.add(event)
    }

    val profiles = fetchProfiles(conversations.keys.toList())
    return conversations.map { (partnerKey, events) ->
        val lastEvent = events.maxByOrNull { it.createdAt }!!
        DmConversation(
            partnerPubkey = partnerKey, partnerProfile = profiles[partnerKey],
            lastMessage = "...", lastMessageTime = lastEvent.createdAt, unreadCount = 0
        )
    }.sortedByDescending { it.lastMessageTime }
}
