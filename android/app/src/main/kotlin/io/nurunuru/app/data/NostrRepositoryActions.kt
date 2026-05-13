package io.nurunuru.app.data

import io.nurunuru.app.data.models.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

// ─── Actions ──────────────────────────────────────────────────────────────────

/** Returns the reaction event ID on success, null on failure. */
suspend fun NostrRepository.likePost(
    eventId: String,
    authorPubkey: String,
    emoji: String = "+",
    customTags: List<List<String>> = emptyList()
): String? {
    val rustClient = client.getRustClient() ?: return null
    return try {
        if (isExternalSigner()) {
            val unsigned = rustClient.createUnsignedReaction(eventId, authorPubkey, emoji, myPubkeyHex)
            signAndPublishGetId(unsigned, requireManualApproval = true).also { if (it != null) android.util.Log.d("NostrRepository", "Ext react OK: $eventId id=$it") }
        } else {
            val reactionId = withContext(Dispatchers.IO) {
                rustClient.react(eventId, authorPubkey, emoji)
            }
            android.util.Log.d("NostrRepository", "Rust react OK: $eventId emoji=$emoji id=$reactionId")
            reactionId.ifEmpty { null }
        }
    } catch (e: Exception) {
        android.util.Log.e("NostrRepository", "Rust react failed: ${e.message}")
        null
    }
}

/**
 * Repost an event (Kind 6, NIP-18).
 * `eventJson` must be the full serialised Nostr event JSON (with encodeDefaults=true).
 * Returns the repost event ID on success, null on failure.
 */
suspend fun NostrRepository.repostPost(eventId: String, eventJson: String? = null): String? {
    val rustClient = client.getRustClient() ?: return null
    if (eventJson == null) {
        android.util.Log.w("NostrRepository", "repostPost: eventJson is null, skipping $eventId")
        return null
    }
    return try {
        if (isExternalSigner()) {
            val unsigned = rustClient.createUnsignedRepost(eventJson, myPubkeyHex)
            signAndPublishGetId(unsigned, requireManualApproval = true).also { if (it != null) android.util.Log.d("NostrRepository", "Ext repost OK: $eventId id=$it") }
        } else {
            val repostId = withContext(Dispatchers.IO) { rustClient.repost(eventJson) }
            android.util.Log.d("NostrRepository", "Rust repost OK: $eventId id=$repostId")
            repostId.ifEmpty { null }
        }
    } catch (e: Exception) {
        android.util.Log.e("NostrRepository", "Rust repost failed: ${e.message}")
        null
    }
}

suspend fun NostrRepository.publishNote(
    content: String,
    replyToId: String? = null,
    contentWarning: String? = null,
    customTags: List<List<String>> = emptyList(),
    kind: Int = NostrKind.TEXT_NOTE,
    targetRelays: List<String>? = null,
    nip70Protected: Boolean = false
): NostrEvent? {
    val tags = mutableListOf<List<String>>()
    tags.addAll(customTags)

    if (replyToId != null && tags.none { it.getOrNull(0) == "e" && it.getOrNull(1) == replyToId }) {
        tags.add(listOf("e", replyToId, "", "reply"))
    }
    if (contentWarning != null && tags.none { it.getOrNull(0) == "content-warning" }) {
        tags.add(listOf("content-warning", contentWarning))
    }
    if (nip70Protected && tags.none { it.getOrNull(0) == "-" }) {
        tags.add(listOf("-"))
    }
    if (tags.none { it.getOrNull(0) == "client" }) {
        tags.add(clientTag)
    }

    val rustClient = client.getRustClient() ?: return null

    if (isExternalSigner()) {
        return try {
            val unsigned = withContext(Dispatchers.IO) {
                rustClient.createUnsignedEvent(kind.toUInt(), content, tags, myPubkeyHex)
            }
            android.util.Log.d("NostrRepository", "Ext publishNote: unsigned created (${unsigned.length} chars), signing...")
            val signedJson = client.getSigner().signEvent(unsigned, requireManualApproval = true) ?: run {
                android.util.Log.w("NostrRepository", "Ext publishNote: signer returned null")
                return null
            }
            android.util.Log.d("NostrRepository", "Ext publishNote: signed (${signedJson.length} chars), publishing...")
            withContext(Dispatchers.IO) {
                // 外部署名（Amber等）では signed raw event を送るため、targetRelays が指定されている場合は
                // 先に送信先リレーを接続プールへ追加してから publishRawEvent する。
                // これにより返信時も相手の NIP-65 Read リレーへ確実に配送される。
                targetRelays.orEmpty().forEach { relay ->
                    try { rustClient.addRelay(relay) }
                    catch (e: Exception) { android.util.Log.w("NostrRepository", "Ext publishNote addRelay failed: " + relay + " / " + e.message) }
                }
                rustClient.publishRawEvent(signedJson)
            }
            android.util.Log.d("NostrRepository", "Ext publishNote OK")
            try { json.decodeFromString<NostrEvent>(signedJson).also { ev -> cacheUserNotePost(ev.pubkey.ifBlank { myPubkeyHex }, ScoredPost(event = ev, profile = getCachedProfile(ev.pubkey.ifBlank { myPubkeyHex }))) } } catch (_: Exception) { null }
        } catch (e: Exception) {
            android.util.Log.e("NostrRepository", "Ext publishNote failed: ${e.message}")
            null
        }
    }

    if (kind == NostrKind.TEXT_NOTE) {
        return try {
            val eventId = withContext(Dispatchers.IO) {
                if (!targetRelays.isNullOrEmpty()) {
                    android.util.Log.d("NostrRepository", "publishNote to ${targetRelays.size} relays: $targetRelays")
                    rustClient.publishNoteWithTagsToRelays(content, tags, targetRelays)
                } else {
                    rustClient.publishNoteWithTags(content, tags)
                }
            }
            android.util.Log.d("NostrRepository", "Rust publishNote OK: $eventId")
            withContext(Dispatchers.IO) {
                rustClient.queryLocal(listOf(prefs.publicKeyHex ?: ""), 1u)
                    .firstOrNull()
                    ?.let { try { Json.decodeFromString<NostrEvent>(it) } catch (_: Exception) { null } }
            }?.also { ev ->
                cacheUserNotePost(ev.pubkey.ifBlank { myPubkeyHex }, ScoredPost(event = ev, profile = getCachedProfile(ev.pubkey.ifBlank { myPubkeyHex })))
            } ?: NostrEvent(
                id = eventId,
                pubkey = myPubkeyHex,
                createdAt = System.currentTimeMillis() / 1000,
                kind = kind,
                tags = tags,
                content = content
            ).also { ev -> cacheUserNotePost(myPubkeyHex, ScoredPost(event = ev, profile = getCachedProfile(myPubkeyHex))) }
        } catch (e: Exception) {
            android.util.Log.e("NostrRepository", "Rust publishNote failed: ${e.message}")
            null
        }
    }

    // Non-Kind-1: use generic publishEvent
    return try {
        val eventId = withContext(Dispatchers.IO) { rustClient.publishEvent(kind.toUInt(), content, tags) }
        android.util.Log.d("NostrRepository", "Rust publishEvent(kind=$kind) OK id=$eventId tags=${tags.size}")
        NostrEvent(id = eventId, pubkey = myPubkeyHex, createdAt = System.currentTimeMillis() / 1000, kind = kind, tags = tags, content = content).also { ev -> cache.setCachedEvent(ev) }
    } catch (e: Exception) {
        android.util.Log.e("NostrRepository", "Rust publishEvent(kind=$kind) failed: ${e.message}")
        null
    }
}

suspend fun NostrRepository.sendDm(recipientPubkeyHex: String, content: String): Boolean =
    client.sendEncryptedDm(recipientPubkeyHex, content)

suspend fun NostrRepository.deleteEvent(eventId: String, reason: String = ""): Boolean {
    val success = try {
        if (isExternalSigner()) {
            publishNewEvent(5, reason, listOf(listOf("e", eventId))) != null
        } else {
            val rustClient = client.getRustClient() ?: return false
            rustClient.deleteEvent(eventId, reason.ifEmpty { null })
            true
        }
    } catch (e: Exception) {
        android.util.Log.e("NostrRepository", "deleteEvent failed: ${e.message}")
        false
    }
    // 削除成功後はディスクキャッシュからも即座に除外する。
    // リレーが NIP-09 を反映する前に refresh() が走っても再出現しなくなる。
    if (success) {
        // 永続セットに登録 → アプリ再起動後のリレーフェッチでも除外される
        cache.addDeletedEventId(eventId)
        val pubkey = prefs.publicKeyHex ?: return true
        cache.removeFromUserNotesCache(pubkey, eventId, json)
        cache.removeFromUserLikesCache(pubkey, eventId, json)
    }
    return success
}

suspend fun NostrRepository.reportEvent(targetPubkey: String, eventId: String?, reportType: String, content: String): Boolean {
    val tags = mutableListOf(listOf("p", targetPubkey, reportType))
    eventId?.let { tags.add(listOf("e", it, reportType)) }
    return publishNewEvent(1984, content, tags) != null
}

suspend fun NostrRepository.publishBirdwatchLabel(eventId: String, authorPubkey: String, contextType: String, content: String, sourceUrl: String = ""): Boolean {
    val fullContent = if (sourceUrl.isNotBlank()) "$content\n\nソース: $sourceUrl" else content
    val tags = listOf(
        listOf("L", "birdwatch"),
        listOf("l", contextType, "birdwatch"),
        listOf("e", eventId),
        listOf("p", authorPubkey)
    )
    return publishNewEvent(1985, fullContent, tags) != null
}

suspend fun NostrRepository.fetchMuteList(pubkeyHex: String): MuteListData {
    // ローカルで直近に追加した非公開ミュートを先に読む。
    // リレー上の kind:10000 が古い/取得失敗/復号失敗でも、ミュートリスト画面には即時反映する。
    val cachedLocal = getCachedMuteList(pubkeyHex)

    val filter = NostrClient.Filter(
        kinds = listOf(NostrKind.MUTE_LIST),
        authors = listOf(pubkeyHex),
        limit = 1
    )
    val events = client.fetchEvents(filter, timeoutMs = 4_000)
    val event = events.maxByOrNull { it.createdAt }

    if (event != null) {
        // NIP-51 kind 10000:
        // - public mute entries are event.tags
        // - private mute entries are NIP-44 encrypted JSON tags in content
        val publicPubkeys = event.getTagValues("p")
        val signer = client.getSigner()
        val privateTags = if (event.content.isNotBlank() && signer != null) {
            try {
                val decrypted = signer.nip44Decrypt(pubkeyHex, event.content)
                if (decrypted != null) {
                    kotlinx.serialization.json.Json.decodeFromString<List<List<String>>>(decrypted)
                } else emptyList()
            } catch (_: Exception) { emptyList() }
        } else emptyList()

        val privatePubkeys = privateTags.filter { it.firstOrNull() == "p" }.mapNotNull { it.getOrNull(1) }
        val relayMuteData = MuteListData(
            pubkeys = (privatePubkeys + publicPubkeys).distinct(),
            eventIds = (privateTags.filter { it.firstOrNull() == "e" }.mapNotNull { it.getOrNull(1) } + event.getTagValues("e")).distinct(),
            hashtags = (privateTags.filter { it.firstOrNull() == "t" }.mapNotNull { it.getOrNull(1) } + event.getTagValues("t")).distinct(),
            words = (privateTags.filter { it.firstOrNull() == "word" }.mapNotNull { it.getOrNull(1) } + event.getTagValues("word")).distinct(),
            privatePubkeys = privatePubkeys.distinct(),
            publicPubkeys = publicPubkeys.distinct()
        )

        val merged = if (cachedLocal != null) {
            MuteListData(
                pubkeys = (cachedLocal.pubkeys + relayMuteData.pubkeys).distinct(),
                eventIds = (cachedLocal.eventIds + relayMuteData.eventIds).distinct(),
                hashtags = (cachedLocal.hashtags + relayMuteData.hashtags).distinct(),
                words = (cachedLocal.words + relayMuteData.words).distinct(),
                privatePubkeys = (cachedLocal.privatePubkeys + relayMuteData.privatePubkeys).distinct(),
                publicPubkeys = (cachedLocal.publicPubkeys + relayMuteData.publicPubkeys).distinct()
            )
        } else relayMuteData

        cache.setCachedMuteList(pubkeyHex, json.encodeToString(MuteListData.serializer(), merged))
        android.util.Log.d("NostrRepository", "fetchMuteList relay=" + relayMuteData.privatePubkeys.size + "/" + relayMuteData.publicPubkeys.size + " cached=" + (cachedLocal?.privatePubkeys?.size ?: 0) + "/" + (cachedLocal?.publicPubkeys?.size ?: 0) + " merged=" + merged.privatePubkeys.size + "/" + merged.publicPubkeys.size)
        return merged
    }

    android.util.Log.d("NostrRepository", "fetchMuteList cacheOnly=" + (cachedLocal?.privatePubkeys?.size ?: 0) + "/" + (cachedLocal?.publicPubkeys?.size ?: 0))
    return cachedLocal ?: MuteListData()
}

suspend fun NostrRepository.fetchNip65WriteRelays(pubkeyHex: String): List<String> {
    return try {
        OutboxModel(client).fetchUserRelayList(pubkeyHex).write
    } catch (_: Exception) { emptyList() }
}

suspend fun NostrRepository.fetchNip65ReadRelays(pubkeyHex: String): List<String> {
    return try {
        OutboxModel(client).fetchUserRelayList(pubkeyHex).read
    } catch (_: Exception) { emptyList() }
}

/**
 * ログインユーザーの NIP-65 kind:10002 リレーリストを読み込み、保存済みリレーへ反映する。
 * リレーリストが存在するユーザーではデフォルトリレーへ戻さず、そのリストを優先する。
 */
suspend fun NostrRepository.syncLoggedInUserRelayList(pubkeyHex: String): Boolean {
    return try {
        val relayList = OutboxModel(client).fetchUserRelayList(pubkeyHex)
        if (relayList.all.isEmpty()) return false

        val nip65 = relayList.all
            .distinctBy { it.url }
            .map { io.nurunuru.app.data.models.Nip65Relay(it.url, it.read, it.write) }
        if (nip65.isEmpty()) return false

        prefs.nip65Relays = nip65
        prefs.relays = nip65.map { it.url }.toSet()
        prefs.mainRelay = nip65.firstOrNull { it.write }?.url ?: nip65.first().url
        android.util.Log.d("NostrRepository", "Synced login user's NIP-65 relays: " + nip65.size)
        true
    } catch (e: Exception) {
        android.util.Log.w("NostrRepository", "syncLoggedInUserRelayList failed: " + e.message)
        false
    }
}

/**
 * NIP-65 kind 10002 から最寄りリレーを取得し、mainRelay に保存する。
 */
suspend fun NostrRepository.syncNip65Relays(pubkeyHex: String) {
    syncLoggedInUserRelayList(pubkeyHex)
}

private suspend fun NostrRepository.ensureWriteRelaysForReplaceablePublish() {
    val rustClient = client.getRustClient() ?: return
    val writeRelays = prefs.nip65Relays
        .filter { it.write }
        .map { it.url }
        .ifEmpty { prefs.relays.toList() }
        .distinct()
    android.util.Log.d("NostrRepository", "ensureWriteRelaysForReplaceablePublish relays=" + writeRelays.size)
    withContext(Dispatchers.IO) {
        writeRelays.forEach { relay ->
            try { rustClient.addRelay(relay) }
            catch (e: Exception) { android.util.Log.w("NostrRepository", "add write relay for replaceable publish failed: " + relay + " / " + e.message) }
        }
    }
}

suspend fun NostrRepository.removeFromMuteList(pubkeyHex: String, type: String, value: String): Boolean {
    val signer = client.getSigner()
    val cached = getCachedMuteList(pubkeyHex) ?: MuteListData()

    val tagType = when (type) {
        "pubkey", "privatePubkey", "publicPubkey" -> "p"
        "event" -> "e"
        "hashtag" -> "t"
        "word" -> "word"
        else -> return false
    }
    val removePrivate = type != "publicPubkey"
    val removePublic = type == "pubkey" || type == "publicPubkey"

    val cachedPrivateTags = mutableListOf<List<String>>()
    cached.privatePubkeys.forEach { cachedPrivateTags.add(listOf("p", it)) }
    cached.eventIds.forEach { cachedPrivateTags.add(listOf("e", it)) }
    cached.hashtags.forEach { cachedPrivateTags.add(listOf("t", it)) }
    cached.words.forEach { cachedPrivateTags.add(listOf("word", it)) }
    val cachedPublicTags = cached.publicPubkeys.map { listOf("p", it) }

    val newPrivateTags = if (removePrivate) cachedPrivateTags.filter { !(it.firstOrNull() == tagType && it.getOrNull(1) == value) } else cachedPrivateTags
    val newPublicTags = if (removePublic) cachedPublicTags.filter { !(it.firstOrNull() == tagType && it.getOrNull(1) == value) } else cachedPublicTags

    val newPrivatePubkeys = newPrivateTags.filter { it.firstOrNull() == "p" }.mapNotNull { it.getOrNull(1) }.distinct()
    val newPublicPubkeys = newPublicTags.filter { it.firstOrNull() == "p" }.mapNotNull { it.getOrNull(1) }.distinct()
    val data = MuteListData(
        pubkeys = (newPrivatePubkeys + newPublicPubkeys).distinct(),
        eventIds = newPrivateTags.filter { it.firstOrNull() == "e" }.mapNotNull { it.getOrNull(1) }.distinct(),
        hashtags = newPrivateTags.filter { it.firstOrNull() == "t" }.mapNotNull { it.getOrNull(1) }.distinct(),
        words = newPrivateTags.filter { it.firstOrNull() == "word" }.mapNotNull { it.getOrNull(1) }.distinct(),
        privatePubkeys = newPrivatePubkeys,
        publicPubkeys = newPublicPubkeys
    )
    cache.setCachedMuteList(pubkeyHex, json.encodeToString(MuteListData.serializer(), data))

    val encryptedContent = if (newPrivateTags.isNotEmpty()) {
        if (signer == null) return true
        try { signer.nip44Encrypt(pubkeyHex, kotlinx.serialization.json.Json.encodeToString(newPrivateTags)) ?: return true }
        catch (_: Exception) { return true }
    } else ""

    ensureWriteRelaysForReplaceablePublish()
    val published = publishNewEvent(NostrKind.MUTE_LIST, encryptedContent, newPublicTags) != null
    android.util.Log.d("NostrRepository", "removeFromMuteList local=true publish=" + published + " value=" + value.take(8) + " remaining=" + newPrivatePubkeys.size + "/" + newPublicPubkeys.size)
    return true
}

suspend fun NostrRepository.muteUser(pubkeyHex: String): Boolean {
    val myPubkey = myPubkeyHex.ifBlank { prefs.publicKeyHex ?: return false }
    val signer = client.getSigner()

    // Use merged local cache as the source of truth for app UI. Do not start from latest relay event,
    // otherwise rapid consecutive mutes are overwritten by a stale kind:10000 from the relay.
    val cached = getCachedMuteList(myPubkey) ?: MuteListData()
    val existingPrivatePubkeys = cached.privatePubkeys.ifEmpty { cached.pubkeys }.distinct()
    val publicPubkeys = cached.publicPubkeys.distinct()
    val allPrivatePubkeys = (existingPrivatePubkeys + pubkeyHex).distinct()

    val privateTags = mutableListOf<List<String>>()
    allPrivatePubkeys.forEach { privateTags.add(listOf("p", it)) }
    cached.eventIds.forEach { privateTags.add(listOf("e", it)) }
    cached.hashtags.forEach { privateTags.add(listOf("t", it)) }
    cached.words.forEach { privateTags.add(listOf("word", it)) }
    val publicTags = publicPubkeys.map { listOf("p", it) }

    val localMuteData = MuteListData(
        pubkeys = (allPrivatePubkeys + publicPubkeys).distinct(),
        eventIds = cached.eventIds.distinct(),
        hashtags = cached.hashtags.distinct(),
        words = cached.words.distinct(),
        privatePubkeys = allPrivatePubkeys,
        publicPubkeys = publicPubkeys
    )
    cache.setCachedMuteList(myPubkey, json.encodeToString(MuteListData.serializer(), localMuteData))

    if (signer == null) {
        android.util.Log.w("NostrRepository", "muteUser local-only: signer unavailable target=" + pubkeyHex.take(8) + " total=" + allPrivatePubkeys.size)
        return true
    }

    val encryptedContent = try {
        signer.nip44Encrypt(myPubkey, kotlinx.serialization.json.Json.encodeToString(privateTags)) ?: run {
            android.util.Log.w("NostrRepository", "muteUser local-only: encrypt returned null target=" + pubkeyHex.take(8))
            return true
        }
    } catch (e: Exception) {
        android.util.Log.w("NostrRepository", "muteUser local-only: encrypt failed " + e.message)
        return true
    }

    ensureWriteRelaysForReplaceablePublish()
    val published = publishNewEvent(NostrKind.MUTE_LIST, encryptedContent, publicTags) != null
    android.util.Log.d("NostrRepository", "muteUser private local=true publish=" + published + " target=" + pubkeyHex.take(8) + " total=" + allPrivatePubkeys.size)
    return true
}


suspend fun NostrRepository.followUser(myPubkeyHex: String, targetPubkeyHex: String): Boolean {
    return try {
        // kind 3 is a replaceable "complete contact list" event.  Build the new
        // list from the latest relay state and publish it through the same path
        // for internal and Amber signers so profile-page follow always updates
        // the cached list and does not depend on Rust helper edge cases.
        val contactsFilter = NostrClient.Filter(kinds = listOf(NostrKind.CONTACT_LIST), authors = listOf(myPubkeyHex), limit = 1)
        val latest = client.fetchEvents(contactsFilter, timeoutMs = 4_000).maxByOrNull { it.createdAt }
        val tags = latest?.tags?.toMutableList() ?: mutableListOf()
        if (tags.any { it.firstOrNull() == "p" && it.getOrNull(1) == targetPubkeyHex }) {
            val current = tags.filter { it.firstOrNull() == "p" }.mapNotNull { it.getOrNull(1) }.distinct()
            cache.setCachedFollowList(myPubkeyHex, current)
            return true
        }
        tags.add(listOf("p", targetPubkeyHex))
        val success = publishNewEvent(NostrKind.CONTACT_LIST, latest?.content ?: "", tags) != null
        if (success) {
            val updated = tags.filter { it.firstOrNull() == "p" }.mapNotNull { it.getOrNull(1) }.distinct()
            cache.setCachedFollowList(myPubkeyHex, updated)
            if (myPubkeyHex == this.myPubkeyHex) {
                followingSet.clear()
                followingSet.addAll(updated)
            }
        }
        success
    } catch (e: Exception) {
        android.util.Log.e("NostrRepository", "followUser failed: ${e.message}")
        false
    }
}

suspend fun NostrRepository.unfollowUser(myPubkeyHex: String, targetPubkeyHex: String): Boolean {
    return try {
        val contactsFilter = NostrClient.Filter(kinds = listOf(NostrKind.CONTACT_LIST), authors = listOf(myPubkeyHex), limit = 1)
        val latest = client.fetchEvents(contactsFilter, timeoutMs = 4_000).maxByOrNull { it.createdAt }
        val tags = latest?.tags ?: emptyList()
        val newTags = tags.filter { !(it.firstOrNull() == "p" && it.getOrNull(1) == targetPubkeyHex) }
        if (newTags.size == tags.size) {
            val current = newTags.filter { it.firstOrNull() == "p" }.mapNotNull { it.getOrNull(1) }.distinct()
            cache.setCachedFollowList(myPubkeyHex, current)
            return true
        }
        val success = publishNewEvent(NostrKind.CONTACT_LIST, latest?.content ?: "", newTags) != null
        if (success) {
            val updated = newTags.filter { it.firstOrNull() == "p" }.mapNotNull { it.getOrNull(1) }.distinct()
            cache.setCachedFollowList(myPubkeyHex, updated)
            if (myPubkeyHex == this.myPubkeyHex) {
                followingSet.clear()
                followingSet.addAll(updated)
            }
        }
        success
    } catch (e: Exception) {
        android.util.Log.e("NostrRepository", "unfollowUser failed: ${e.message}")
        false
    }
}
