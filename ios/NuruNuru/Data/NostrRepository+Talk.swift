import Foundation

/// MLS / トーク関連メソッド群 — グループ取得・メッセージ送受信・グループ管理。
/// Android の NostrRepositoryTalk.kt に相当。
///
/// 設計方針:
///   - Rust SQLite (MDK) を single source of truth とし、アプリ側キャッシュは保持しない。
///   - processedIds は relay イベントの二重復号防止のみに使用（セッション内）。
///   - processedWelcomeIds は Welcome の再処理を防止。
///   - Marmot MIP-00〜03 準拠。WhiteNoise 互換。
extension NostrRepository {

    private func mlsLogPrefix(_ value: String) -> String {
        value.count <= 8 ? value : String(value.prefix(8)) + "…"
    }

    private func mlsRedactedError(_ error: Error) -> String {
        let raw = String(describing: error).lowercased()
        if raw.contains("hmac") { return "hmac_error" }
        if raw.contains("process_welcome") || raw.contains("welcome") { return "welcome_error" }
        if raw.contains("content") || raw.contains("payload") || raw.contains("plaintext") || raw.contains("secret") || raw.contains("private") {
            return "redacted_error"
        }
        return "mls_error"
    }

    /// Marmot/WhiteNoise interop relays shared by Welcome rediscovery and Kind-445 fanout.
    ///
    /// After an iOS reinstall the local MLS DB is empty, so the app must rediscover historical
    /// Kind-1059 Welcomes from the relays WhiteNoise uses for account inbox/group fanout before
    /// it can subscribe to that group's Kind-445 #h feed. `groupIdHex` remains the Nostr group id.
    private var mlsInteropRelayUrls: [String] {
        [
            "wss://auth.nostr1.com",
            "wss://relay.damus.io",
            "wss://relay.primal.net",
            "wss://nos.lol",
            "wss://yabu.me",
            "wss://relay.nostr.band",
            "wss://purplepag.es"
        ]
    }

    private func mlsRelayUrls(_ relays: [String] = []) -> [String] {
        canonicalRelayUrls(relays + prefs.selectedRelays + mlsInteropRelayUrls)
    }

    // MARK: - Group Fetch

    /// MLS グループ一覧をリレー + Rust SQLite から取得する。
    ///
    /// 1. Kind-1059 Welcome (NIP-59 gift-wrapped) を取得し未処理分を process
    ///    （Kind-444 legacy は互換 fallback としてのみ扱う）
    /// 2. mlsListGroups() で Rust SQLite のグループ一覧取得
    /// 3. Welcome process 直後の group を含めてメンバープロファイルエンリッチ
    func fetchMlsGroups(myPubkeyHex: String) async throws -> [MlsGroup] {
        guard let ffi = ensureMlsClient() else {
            AppLogger.log("MLS", "fetchMlsGroups: FFI unavailable")
            return []
        }

        // 1. Welcome イベント取得 → 未処理分のみ process
        //    WhiteNoise 等がデフォルト外リレーに publish する可能性あり
        //    → グローバルリレーも含めた広い範囲から取得
        //    FFI/App boundary の groupIdHex は常に Nostr group id (Kind 445 `h`)。
        //    internal MLS group id は Rust 内部に閉じ込める。
        var joinedGroupsById: [String: FfiMlsGroupInfo] = [:]
        do {
            let welcomeRelays = mlsRelayUrls()
            await client.connect(relayUrls: welcomeRelays)

            // Primary path: Marmot MIP-02 Welcome delivery is kind:1059 addressed to
            // the KeyPackage owner pubkey via #p. Pass the complete signed 1059
            // event JSON to Rust so it can NIP-59 unwrap and process/join.
            let f = NostrFilter(ids: nil, authors: nil, kinds: [NostrKind.mlsWelcome], since: nil, until: nil, limit: 200, tags: ["#p": [myPubkeyHex]], search: nil)
            var welcomeEvents = await fetchEvents(filters: [f], timeoutSeconds: 8.0)
            if welcomeEvents.isEmpty {
                let broad = NostrFilter(ids: nil, authors: nil, kinds: [NostrKind.mlsWelcome], since: nil, until: nil, limit: 300, tags: nil, search: nil)
                let broadEvents = await fetchEvents(filters: [broad], timeoutSeconds: 5.0)
                let mine = broadEvents.filter { $0.getTagValues("p").contains(myPubkeyHex) }
                AppLogger.log("MLS", "fetchMlsGroups: kind1059 #p fallback broad=\(broadEvents.count) mine=\(mine.count)")
                welcomeEvents = mine
            }

            // Legacy compatibility only: some older peers may publish plain kind:444.
            // Keep this fallback separate so the normal receive flow remains kind:1059.
            if welcomeEvents.isEmpty {
                let legacy = NostrFilter(ids: nil, authors: nil, kinds: [NostrKind.mlsWelcomeInner], since: nil, until: nil, limit: 200, tags: ["#p": [myPubkeyHex]], search: nil)
                welcomeEvents = await fetchEvents(filters: [legacy], timeoutSeconds: 4.0)
                if !welcomeEvents.isEmpty {
                    AppLogger.log("MLS", "fetchMlsGroups: legacy kind444 fallback count=\(welcomeEvents.count)")
                }
            }

            var newCount = 0
            let now = Int64(Date().timeIntervalSince1970)
            var persistedRejectedWelcomeRetryAfter = prefs.mlsRejectedWelcomeRetryAfterById
            // Prune expired persisted gates opportunistically. Keep only future retry windows.
            persistedRejectedWelcomeRetryAfter = persistedRejectedWelcomeRetryAfter.filter { $0.value > now }
            if persistedRejectedWelcomeRetryAfter.count != prefs.mlsRejectedWelcomeRetryAfterById.count {
                prefs.mlsRejectedWelcomeRetryAfterById = persistedRejectedWelcomeRetryAfter
            }
            for ev in welcomeEvents {
                guard !processedWelcomeIds.contains(ev.id) else { continue }
                if let retryAfter = rejectedWelcomeRetryAfter[ev.id], retryAfter > now {
                    continue
                }
                if let retryAfter = persistedRejectedWelcomeRetryAfter[ev.id], retryAfter > now {
                    rejectedWelcomeRetryAfter[ev.id] = retryAfter
                    continue
                }
                guard let eventJSON = encodeEventJSON(ev) else { continue }

                // Gate before processing, not only in catch. NostrRepository actors are reentrant
                // across relay fetch awaits and multiple repository instances can exist during SwiftUI
                // lifecycle churn; persisting the gate prevents the same rejected Welcome from being
                // unwrapped/processed repeatedly on every loadGroups tick. The gate is removed on success.
                let retryAfterOnFailure = now + 600
                rejectedWelcomeRetryAfter[ev.id] = retryAfterOnFailure
                persistedRejectedWelcomeRetryAfter[ev.id] = retryAfterOnFailure
                prefs.mlsRejectedWelcomeRetryAfterById = persistedRejectedWelcomeRetryAfter

                do {
                    try validateWelcomeEventForMip02(ev)
                    let joined = try ffi.mlsProcessWelcome(welcomeEventJSON: eventJSON)
                    processedWelcomeIds.insert(ev.id)
                    rejectedWelcomeRetryAfter.removeValue(forKey: ev.id)
                    persistedRejectedWelcomeRetryAfter.removeValue(forKey: ev.id)
                    prefs.mlsRejectedWelcomeRetryAfterById = persistedRejectedWelcomeRetryAfter
                    joinedGroupsById[joined.groupIdHex] = joined
                    AppLogger.log("MLS", "fetchMlsGroups: welcome process success id=\(ev.id) kind=\(ev.kind) group=\(joined.groupIdHex)")
                    // MIP-02 key package lifecycle: rotate consumed key package after successful join.
                    await rotateConsumedKeyPackageAfterWelcomeIfNeeded(welcomeEvent: ev, ffi: ffi)
                    // MIP-02 post-join: best-effort catch-up then self-update ASAP.
                    await postWelcomeBestEffortCatchUpAndSelfUpdate(group: joined, ffi: ffi)
                    newCount += 1
                } catch {
                    // HMAC / process_welcome failures for old or non-matching 1059 events are common on relays.
                    // Keep them retryable, but back off per event so Talk UI actions are not delayed by
                    // reprocessing the same rejected Welcomes every loadGroups tick.
                    rejectedWelcomeRetryAfter[ev.id] = retryAfterOnFailure
                    persistedRejectedWelcomeRetryAfter[ev.id] = retryAfterOnFailure
                    prefs.mlsRejectedWelcomeRetryAfterById = persistedRejectedWelcomeRetryAfter
                    AppLogger.log("MLS", "fetchMlsGroups: welcome processing rejected id=\(ev.id) kind=\(ev.kind) retryAfter=600s err=\(mlsRedactedError(error))")
                }
            }
            if newCount > 0 {
                AppLogger.log("MLS", "fetchMlsGroups: processed \(newCount) new Welcome(s) of \(welcomeEvents.count)")
            }
        } catch {
            AppLogger.log("MLS", "fetchEventsFromRelay (Welcome) failed: \(mlsRedactedError(error))")
        }

        // 2. Rust SQLite からグループ一覧
        var ffiGroupsAll = try ffi.mlsListGroups()
        if !joinedGroupsById.isEmpty {
            var byId = Dictionary(uniqueKeysWithValues: ffiGroupsAll.map { ($0.groupIdHex, $0) })
            for (groupId, joined) in joinedGroupsById where byId[groupId] == nil {
                // mlsProcessWelcome returns an active group immediately. If list refresh
                // lags for any runtime, include/enrich the returned Nostr group id so UI
                // can show the newly joined group in this fetch cycle.
                byId[groupId] = (try? ffi.mlsGetGroupInfo(groupIdHex: groupId)) ?? joined
            }
            ffiGroupsAll = Array(byId.values)
        }
        var hidden = prefs.hiddenMlsGroupIds
        // invalid DM（相手不在 = 自分だけ）を一覧から除外
        var ffiGroups = ffiGroupsAll.filter { g in
            guard !hidden.contains(g.groupIdHex) else { return false }
            if g.isDm {
                return g.memberPubkeys.contains(where: { $0 != myPubkeyHex })
            }
            return true
        }

        // Recovery safety: a previous stuck-DM auto recovery could locally hide every
        // otherwise valid Rust/MDK group for the account. If that happens, Talk becomes
        // permanently empty after reinstall even though mlsListGroups still returns valid
        // Nostr groups. Do not expose internal MLS ids here; groupIdHex remains the Nostr
        // group id from FFI. Prune only stale local-hide tombstones for groups that still
        // have a peer member (or are non-DM groups) and only when the visible list would be
        // empty, preserving normal explicit leave/orphan hiding in non-empty states.
        if ffiGroups.isEmpty, !hidden.isEmpty {
            let validHiddenGroups = ffiGroupsAll.filter { g in
                hidden.contains(g.groupIdHex) && (!g.isDm || g.memberPubkeys.contains(where: { $0 != myPubkeyHex }))
            }
            if !validHiddenGroups.isEmpty {
                for g in validHiddenGroups { hidden.remove(g.groupIdHex) }
                prefs.hiddenMlsGroupIds = hidden
                ffiGroups = ffiGroupsAll.filter { g in
                    if g.isDm {
                        return g.memberPubkeys.contains(where: { $0 != myPubkeyHex })
                    }
                    return true
                }
                AppLogger.log("MLS", "fetchMlsGroups: pruned stale hidden tombstones=\(validHiddenGroups.count) after zero-visible guard")
            }
        }

        AppLogger.log("MLS", "fetchMlsGroups: ffi.mlsListGroups -> \(ffiGroups.count)/\(ffiGroupsAll.count) visible groups")

        // 3. メンバープロファイルエンリッチ
        let allPubkeys  = Array(Set(ffiGroups.flatMap { $0.memberPubkeys }))
        let profiles    = await fetchProfiles(pubkeys: allPubkeys)
        let profileMap  = Dictionary(uniqueKeysWithValues: profiles.map { ($0.pubkey, $0) })

        // 4. 各グループの最新メッセージを Rust SQLite から取得
        return ffiGroups.map { ffiG in
            let lastMsg = (try? ffi.mlsGetMessageHistory(groupIdHex: ffiG.groupIdHex, limit: 1))?.first
            return MlsGroup(
                groupIdHex:    ffiG.groupIdHex,
                name:          ffiG.name,
                description:   ffiG.description,
                adminPubkeys:  ffiG.adminPubkeys,
                memberPubkeys: ffiG.memberPubkeys,
                relays:        ffiG.relays,
                createdAt:     Int64(ffiG.createdAt),
                epoch:         Int64(ffiG.epoch),
                disappearingMessageSecs: ffiG.disappearingMessageSecs.map(Int64.init),
                isDm:          ffiG.isDm,
                memberProfiles: Dictionary(
                    uniqueKeysWithValues: ffiG.memberPubkeys.compactMap { pk in
                        profileMap[pk].map { (pk, $0) }
                    }
                ),
                lastMessage:     lastMsg?.content ?? "",
                lastMessageTime: lastMsg.map { Int64($0.timestamp) } ?? Int64(ffiG.createdAt)
            )
        }.sorted { $0.lastMessageTime > $1.lastMessageTime }
    }

    // MARK: - Message Fetch

    /// グループのメッセージを取得する。
    ///
    /// Marmot / MDK 準拠方針:
    /// - kind:445 イベントを時系列で収集し、MDK に順次適用する
    /// - 独自の強制 recovery/quarantine でイベントを捨てない
    /// - retryable (state_not_ready など) は未処理のまま次回ポーリングへ回す
    /// - Rust SQLite を single source of truth として履歴を返す
    func fetchMlsMessages(groupIdHex: String) async throws -> [MlsMessage] {
        guard let ffi = ensureMlsClient() else {
            AppLogger.log("MLS", "fetchMlsMessages: FFI unavailable for group=\(groupIdHex)")
            return []
        }

        var processedIds = mlsProcessedIds[groupIdHex] ?? []
        var liveDecrypted: [FfiDecryptedMessage] = []

        // 旧独自の quarantine 状態はこの準拠版では使用しないためクリアしておく。
        mlsUnprocessableEventAttempts[groupIdHex] = [:]
        mlsUnprocessableSenderAttempts[groupIdHex] = [:]
        mlsUnprocessableEpochAttempts[groupIdHex] = [:]
        mlsUnprocessableStreak[groupIdHex] = 0

        let baselineHistory = (try? ffi.mlsGetMessageHistory(groupIdHex: groupIdHex, limit: 100)) ?? []
        let baselineLatestTs = baselineHistory.map { Int64($0.timestamp) }.max() ?? 0

        _ = try? ffi.mlsMergePendingCommit(groupIdHex: groupIdHex)

        let fetchSince: Int64? = baselineLatestTs > 0 ? max(0, baselineLatestTs - 86_400) : nil
        let sortedEvents = await collectGroupMessageEvents(groupIdHex: groupIdHex, ffi: ffi, since: fetchSince)
        AppLogger.log("MLS", "fetchMlsMessages[MARMOT]: fetched kind445=\(sortedEvents.count) group=\(groupIdHex)")

        var appliedCount = 0
        var stateOnlyCount = 0
        var droppedCount = 0
        var retryableIds = Set<String>()
        var retryLoggedIds = Set<String>()

        // Relay は順序保証がないため、retryable unprocessable は processedIds に入れず、
        // 同一 fetch 内でも state update/commit 適用後に未処理 queue を再走査する。
        // processedIds に入れるのは「適用済み」または「再試行しても無意味な drop」のみ。
        var shouldRescanAfterStateUpdate = true
        var pass = 0
        let maxPasses = max(1, min(sortedEvents.count + 1, 8))

        while shouldRescanAfterStateUpdate && pass < maxPasses {
            pass += 1
            shouldRescanAfterStateUpdate = false
            var stateUpdateProcessedInPass = false

            for ev in sortedEvents {
                // duplicate event id は idempotent に扱う。既に適用/drop 済みなら何もしない。
                guard !processedIds.contains(ev.id) else { continue }

                guard ev.kind == NostrKind.mlsGroupMessage else {
                    processedIds.insert(ev.id)
                    retryableIds.remove(ev.id)
                    droppedCount += 1
                    AppLogger.log("MLS", "fetchMlsMessages: drop invalid kind id=\(ev.id) kind=\(ev.kind) expected=\(NostrKind.mlsGroupMessage)")
                    continue
                }

                if let invalidReason = invalidMlsOuterPayloadReason(ev.content) {
                    processedIds.insert(ev.id)
                    retryableIds.remove(ev.id)
                    droppedCount += 1
                    AppLogger.log("MLS", "fetchMlsMessages: drop invalid kind445 payload id=\(ev.id) reason=\(invalidReason)")
                    continue
                }

                let evH = ev.getTagValue("h") ?? ""
                if evH.lowercased() != groupIdHex.lowercased() {
                    processedIds.insert(ev.id)
                    retryableIds.remove(ev.id)
                    droppedCount += 1
                    AppLogger.log("MLS", "fetchMlsMessages: drop mismatched h-tag id=\(ev.id) h=\(evH) expected=\(groupIdHex)")
                    continue
                }

                guard let eventJSON = encodeEventJSON(ev) else {
                    processedIds.insert(ev.id)
                    retryableIds.remove(ev.id)
                    droppedCount += 1
                    AppLogger.log("MLS", "fetchMlsMessages: drop unencodable event id=\(ev.id)")
                    continue
                }

                do {
                    let result = try ffi.mlsProcessMessageResult(groupIdHex: groupIdHex, eventJSON: eventJSON)
                    switch result {
                    case .application(let msg):
                        liveDecrypted.append(msg)
                        processedIds.insert(ev.id)
                        retryableIds.remove(ev.id)
                        appliedCount += 1
                        AppLogger.log("MLS", "fetchMlsMessages: application id=\(ev.id) sender=\(mlsLogPrefix(msg.senderPubkey)) len=\(msg.content.count)")

                    case .stateUpdate(let kind):
                        // protocol-shape mismatch は再試行不要として処理済み化
                        if isNonRetryableMlsUnprocessable(kind) {
                            processedIds.insert(ev.id)
                            retryableIds.remove(ev.id)
                            droppedCount += 1
                            AppLogger.log("MLS", "fetchMlsMessages: drop non-retryable state-update kind=\(kind) id=\(ev.id)")
                            continue
                        }

                        // retryable unprocessable は processedIds に入れず、後続 state update 後または次回 fetch で再試行する。
                        if kind.hasPrefix("unhandled:Unprocessable") {
                            retryableIds.insert(ev.id)
                            if retryLoggedIds.insert(ev.id).inserted {
                                AppLogger.log("MLS", "fetchMlsMessages: retryable state-update kind=\(kind) id=\(ev.id)")
                            }
                        } else {
                            processedIds.insert(ev.id)
                            retryableIds.remove(ev.id)
                            stateOnlyCount += 1
                            stateUpdateProcessedInPass = true
                            try? ffi.mlsMergePendingCommit(groupIdHex: groupIdHex)
                            AppLogger.log("MLS", "fetchMlsMessages: state-only kind=\(kind) id=\(ev.id)")
                        }
                    }
                } catch {
                    // out-of-order / pending state は processedIds に入れず retry queue に残す。
                    retryableIds.insert(ev.id)
                    if retryLoggedIds.insert(ev.id).inserted {
                        AppLogger.log("MLS", "fetchMlsMessages: process failed (will retry) id=\(ev.id) err=\(mlsRedactedError(error))")
                    }
                }
            }

            // Commit/proposal 等で state が進んだ場合、同じ relay fetch で既に見えている
            // retryable event を即時再試行する。進展がなければ次回 polling まで保持。
            shouldRescanAfterStateUpdate = stateUpdateProcessedInPass && sortedEvents.contains { !processedIds.contains($0.id) }
        }

        let retryableCount = retryableIds.count
        AppLogger.log("MLS", "fetchMlsMessages: applied=\(appliedCount) stateOnly=\(stateOnlyCount) retryable=\(retryableCount) dropped=\(droppedCount) passes=\(pass)")

        mlsProcessedIds[groupIdHex] = processedIds
        mlsRetryableStateCount[groupIdHex] = retryableCount

        _ = try? ffi.mlsMergePendingCommit(groupIdHex: groupIdHex)

        let history = (try? ffi.mlsGetMessageHistory(groupIdHex: groupIdHex, limit: 300)) ?? []
        AppLogger.log("MLS", "fetchMlsMessages: history count=\(history.count) group=\(groupIdHex)")

        let merged = mergeHistoryAndLive(history: history, live: liveDecrypted)

        let visible = merged.filter { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let droppedEmpty = merged.count - visible.count
        if droppedEmpty > 0 {
            AppLogger.log("MLS", "fetchMlsMessages: dropped empty-content messages=\(droppedEmpty)")
        }

        let senderPubkeys = Array(Set(visible.map { $0.senderPubkey }))
        let senderProfiles = await quickFetchProfiles(pubkeys: senderPubkeys)
        let profileMap = Dictionary(uniqueKeysWithValues: senderProfiles.map { ($0.pubkey, $0) })

        return visible.map { msg in
            let sender = profileMap[msg.senderPubkey] ?? cache.getCachedProfile(msg.senderPubkey)
            return MlsMessage(
                id: stableMessageId(groupIdHex: groupIdHex, senderPubkey: msg.senderPubkey, timestamp: Int64(msg.timestamp), content: msg.content),
                senderPubkey: msg.senderPubkey,
                content: msg.content,
                timestamp: Int64(msg.timestamp),
                groupIdHex: groupIdHex,
                senderProfile: sender
            )
        }.sorted { lhs, rhs in
            if lhs.timestamp != rhs.timestamp { return lhs.timestamp < rhs.timestamp }
            return lhs.id < rhs.id
        }
    }

    // MARK: - Send Message

    /// MLS グループにメッセージを送信する (Kind 445)。
    ///
    /// Marmot 準拠方針:
    /// - 送信前に pending commit を merge し、最新 state へ追従
    /// - mlsCreateMessage 失敗時は独自 recovery commit を発行せずエラーを返す
    /// - raw kind:445 は MDK 署名済み payload をそのまま publish
    @discardableResult
    func sendMlsMessage(groupIdHex: String, content: String, myPubkeyHex: String) async throws -> MlsMessage {
        guard let ffi = ensureMlsClient() else {
            AppLogger.log("MLS", "sendMlsMessage: FFI unavailable for group=\(groupIdHex)")
            throw MlsError.noFfiClient
        }

        let groupInfo = try? ffi.mlsGetGroupInfo(groupIdHex: groupIdHex)
        let groupRelays = groupInfo?.relays ?? []
        let inboxRelays = await resolveInboxRelaysForMembers(groupInfo?.memberPubkeys ?? [])
        let publishRelays = mlsRelayUrls(groupRelays + inboxRelays)

        if !publishRelays.isEmpty {
            await client.connect(relayUrls: publishRelays)
        }

        _ = try? ffi.mlsMergePendingCommit(groupIdHex: groupIdHex)

        // Do not block local sends just because older relay events are retryable.
        // Relay history can contain stale/out-of-order state_not_ready events from previous
        // epochs, while this device may still be able to create and publish a valid local
        // application message. Let mlsCreateMessage be the source of truth for whether the
        // current local group state is send-capable.
        if (mlsRetryableStateCount[groupIdHex] ?? 0) > 0 {
            AppLogger.log("MLS", "sendMlsMessage[MARMOT]: continuing despite retryable state_not_ready group=\(groupIdHex) count=\(mlsRetryableStateCount[groupIdHex] ?? 0)")
        }

        let data: FfiEncryptedMessageData
        do {
            data = try ffi.mlsCreateMessage(groupIdHex: groupIdHex, content: content)
        } catch {
            let raw = String(describing: error).lowercased()
            if raw.contains("pending proposal exists") || raw.contains("pending commit exists") {
                throw MlsError.groupStateStuck
            }
            throw error
        }

        AppLogger.log("MLS", "sendMlsMessage[MARMOT]: publish kind445 relays=\(publishRelays.count)")
        do {
            try await publishMlsKind445(data: data, groupRelays: publishRelays)
        } catch {
            if let eid = extractEventId(from: data.content), let account = prefs.publicKeyHex {
                mlsRetryStore.enqueueMessage(
                    accountPubkey: account,
                    groupIdHex: groupIdHex,
                    eventId: eid,
                    relayUrls: publishRelays,
                    signedEventJSON: data.content,
                    lastErrorKind: classifyMlsRetryError(error)
                )
                AppLogger.log("MLS", "sendMlsMessage: queued message retry event=\(eid) group=\(groupIdHex) relays=\(publishRelays.count)")
            }
            throw error
        }

        if let eid = extractEventId(from: data.content) {
            mlsProcessedIds[groupIdHex, default: []].insert(eid)
        }

        return MlsMessage(
            id: extractEventId(from: data.content) ?? UUID().uuidString,
            senderPubkey: myPubkeyHex,
            content: content,
            timestamp: Int64(Date().timeIntervalSince1970),
            groupIdHex: groupIdHex
        )
    }

    // MARK: - Group Creation

    /// 1:1 DM グループを作成。
    func createMlsDmConversation(partnerPubkeyHex: String, myPubkeyHex: String) async throws -> MlsGroup {
        guard let ffi = ensureMlsClient() else {
            return makeFallbackDmGroup(partner: partnerPubkeyHex, me: myPubkeyHex)
        }
        await ensureKeyPackagePublished(ffi: ffi, myPubkeyHex: myPubkeyHex)

        let seedRelays = Array(prefs.selectedRelays.prefix(3))

        // 先に相手 KeyPackage を確認（失敗時に自己だけDMを作らない）
        guard let kpEvent = await fetchLatestKeyPackage(pubkey: partnerPubkeyHex, ffi: ffi) else {
            AppLogger.log("MLS", "createDm: key package not found partner=\(mlsLogPrefix(partnerPubkeyHex))")
            throw MlsError.keyPackageNotFound
        }
        // Safety: Welcome 1059 must be addressed to the KeyPackage event owner.
        // Never add a member with a KeyPackage whose event pubkey differs from the requested partner.
        guard extractPubkey(from: kpEvent)?.lowercased() == partnerPubkeyHex.lowercased() else {
            AppLogger.log("MLS", "createDm: key package owner mismatch requested=\(mlsLogPrefix(partnerPubkeyHex)) owner=\(mlsLogPrefix(extractPubkey(from: kpEvent) ?? ""))")
            throw MlsError.keyPackageNotFound
        }

        // KeyPackage が取得できた場合のみグループ作成
        let ffiGroup = try ffi.mlsCreateGroup(name: "", adminPubkeys: [myPubkeyHex], relays: seedRelays)

        // MUST: never mutate peer-signed KeyPackage event JSON.
        let keyPackageEventJSON = kpEvent
        do {
            let result = try ffi.mlsAddMember(groupIdHex: ffiGroup.groupIdHex, keyPackageEventJSON: keyPackageEventJSON)
            guard result.welcomeEventData.recipientPubkey.lowercased() == partnerPubkeyHex.lowercased() else {
                AppLogger.log("MLS", "createDm: welcome recipient mismatch partner=\(mlsLogPrefix(partnerPubkeyHex)) recipient=\(mlsLogPrefix(result.welcomeEventData.recipientPubkey))")
                throw MlsError.keyPackageNotFound
            }
            AppLogger.log("MLS", "createDm: mlsAddMember success group=\(ffiGroup.groupIdHex) partner=\(mlsLogPrefix(partnerPubkeyHex))")

            // WhiteNoise 互換: 相手 inbox/kp relay + global fallback まで publish 範囲を拡張。
            let inboxRelays = await resolveInboxRelaysForMembers([partnerPubkeyHex])
            let publishRelays = mlsRelayUrls(ffiGroup.relays + seedRelays + inboxRelays)

            try await publishMlsKind445(data: result.commitEventData, groupRelays: publishRelays)
            AppLogger.log("MLS", "createDm: commit publish success group=\(ffiGroup.groupIdHex)")
            // MIP-02 timing (fork prevention): Welcome MUST be sent only after Commit relay ACK.
            try await publishMlsWelcome(data: result.welcomeEventData, groupRelays: publishRelays)
            AppLogger.log("MLS", "createDm: welcome publish success group=\(ffiGroup.groupIdHex)")
            recordConsumedKeyPackageEventId(fromEventJSON: keyPackageEventJSON)
            try? ffi.mlsMergePendingCommit(groupIdHex: ffiGroup.groupIdHex)
        } catch {
            // addMember/publish失敗時の orphan DM を残さない
            hideMlsGroupLocally(groupIdHex: ffiGroup.groupIdHex)
            AppLogger.log("MLS", "createDm: addMember/publish failed -> hide orphan group=\(ffiGroup.groupIdHex) err=\(mlsRedactedError(error))")
            throw error
        }

        let resolved = (try? enrichFfiGroup(ffiGroup, ffi: ffi)) ?? bridgeFfiGroup(ffiGroup)

        // Safety guard: DM must include partner member after addMember/welcome flow.
        // If not, treat as creation failure and hide the orphan group locally.
        if !resolved.memberPubkeys.contains(partnerPubkeyHex) {
            hideMlsGroupLocally(groupIdHex: resolved.groupIdHex)
            AppLogger.log("MLS", "createDm: invalid orphan DM detected (partner missing) group=\(resolved.groupIdHex) partner=\(mlsLogPrefix(partnerPubkeyHex))")
            throw MlsError.groupStateStuck
        }

        return resolved
    }

    /// 名前付きグループチャットを作成。
    func createMlsGroupChat(name: String, memberPubkeys: [String], myPubkeyHex: String) async throws -> MlsGroup {
        guard let ffi = ensureMlsClient() else {
            return makeFallbackGroupChat(name: name, members: memberPubkeys, me: myPubkeyHex)
        }
        await ensureKeyPackagePublished(ffi: ffi, myPubkeyHex: myPubkeyHex)

        let seedRelays = Array(prefs.selectedRelays.prefix(3))
        let ffiGroup = try ffi.mlsCreateGroup(name: name, adminPubkeys: [myPubkeyHex], relays: seedRelays)

        let inboxRelays = await resolveInboxRelaysForMembers(memberPubkeys)
        let publishRelays = mlsRelayUrls(ffiGroup.relays + seedRelays + inboxRelays)

        let kpEvents = await fetchKeyPackages(pubkeys: memberPubkeys, ffi: ffi)
        for kpEvent in kpEvents {
            guard let owner = extractPubkey(from: kpEvent), memberPubkeys.contains(where: { $0.lowercased() == owner.lowercased() }) else {
                AppLogger.log("MLS", "createGroup: skip key package owner mismatch owner=\(mlsLogPrefix(extractPubkey(from: kpEvent) ?? ""))")
                continue
            }
            // MUST: never mutate peer-signed KeyPackage event JSON.
            let keyPackageEventJSON = kpEvent
            do {
                let result = try ffi.mlsAddMember(groupIdHex: ffiGroup.groupIdHex, keyPackageEventJSON: keyPackageEventJSON)
                guard result.welcomeEventData.recipientPubkey.lowercased() == owner.lowercased() else {
                    AppLogger.log("MLS", "createGroup: welcome recipient mismatch owner=\(mlsLogPrefix(owner)) recipient=\(mlsLogPrefix(result.welcomeEventData.recipientPubkey))")
                    throw MlsError.keyPackageNotFound
                }
                try await publishMlsKind445(data: result.commitEventData, groupRelays: publishRelays)
                // MIP-02 timing (fork prevention): Welcome MUST be sent only after Commit relay ACK.
                try await publishMlsWelcome(data: result.welcomeEventData, groupRelays: publishRelays)
                recordConsumedKeyPackageEventId(fromEventJSON: keyPackageEventJSON)
                try? ffi.mlsMergePendingCommit(groupIdHex: ffiGroup.groupIdHex)
            } catch {
                AppLogger.log("MLS", "createGroup: addMember failed (continue next): \(mlsRedactedError(error))")
            }
        }
        return (try? enrichFfiGroup(ffiGroup, ffi: ffi)) ?? bridgeFfiGroup(ffiGroup)
    }

    // MARK: - Member Management

    func addMemberToGroup(groupIdHex: String, memberPubkey: String) async throws {
        guard let ffi = ensureMlsClient() else { return }
        let seedRelays = Array(prefs.selectedRelays.prefix(3))
        let groupRelays = (try? ffi.mlsGetGroupInfo(groupIdHex: groupIdHex))?.relays ?? seedRelays
        let inboxRelays = await resolveInboxRelaysForMembers([memberPubkey])
        let publishRelays = mlsRelayUrls(groupRelays + seedRelays + inboxRelays)

        guard let kpEvent = await fetchLatestKeyPackage(pubkey: memberPubkey, ffi: ffi) else {
            throw MlsError.keyPackageNotFound
        }
        // Safety: Welcome 1059 recipient is the KeyPackage event owner.
        guard extractPubkey(from: kpEvent)?.lowercased() == memberPubkey.lowercased() else {
            AppLogger.log("MLS", "addMemberToGroup: key package owner mismatch requested=\(mlsLogPrefix(memberPubkey)) owner=\(mlsLogPrefix(extractPubkey(from: kpEvent) ?? ""))")
            throw MlsError.keyPackageNotFound
        }
        // MUST: never mutate peer-signed KeyPackage event JSON.
        let keyPackageEventJSON = kpEvent
        let addResult = try ffi.mlsAddMember(groupIdHex: groupIdHex, keyPackageEventJSON: keyPackageEventJSON)
        guard addResult.welcomeEventData.recipientPubkey.lowercased() == memberPubkey.lowercased() else {
            AppLogger.log("MLS", "addMemberToGroup: welcome recipient mismatch requested=\(mlsLogPrefix(memberPubkey)) recipient=\(mlsLogPrefix(addResult.welcomeEventData.recipientPubkey))")
            throw MlsError.keyPackageNotFound
        }
        try await publishMlsKind445(data: addResult.commitEventData, groupRelays: publishRelays)
        // MIP-02 timing (fork prevention): Welcome MUST be sent only after Commit relay ACK.
        try await publishMlsWelcome(data: addResult.welcomeEventData, groupRelays: publishRelays)
        recordConsumedKeyPackageEventId(fromEventJSON: keyPackageEventJSON)
        try? ffi.mlsMergePendingCommit(groupIdHex: groupIdHex)
    }

    func removeMemberFromGroup(groupIdHex: String, memberPubkey: String) async throws {
        guard let ffi = ensureMlsClient() else { return }
        let groupRelays = (try? ffi.mlsGetGroupInfo(groupIdHex: groupIdHex))?.relays ?? []
        let ffiMsg = try ffi.mlsRemoveMember(groupIdHex: groupIdHex, memberPubkeyHex: memberPubkey)
        try await publishMlsKind445(data: ffiMsg, groupRelays: groupRelays)
        try? ffi.mlsMergePendingCommit(groupIdHex: groupIdHex)
    }

    /// ローカルでグループを非表示化する（再起動後も維持）。
    /// leave publish の成否に関係なく UI 復活を防ぐために使用。
    func hideMlsGroupLocally(groupIdHex: String) {
        mlsProcessedIds.removeValue(forKey: groupIdHex)
        var hidden = prefs.hiddenMlsGroupIds
        hidden.insert(groupIdHex)
        prefs.hiddenMlsGroupIds = hidden
    }

    func leaveMlsGroup(groupIdHex: String) async throws {
        // 退出publishが失敗しても、再起動時に復活しないよう先にローカル非表示を確定。
        hideMlsGroupLocally(groupIdHex: groupIdHex)

        guard let ffi = ensureMlsClient() else {
            AppLogger.log("MLS", "leaveMlsGroup: FFI unavailable, local-hide only group=\(groupIdHex)")
            return
        }

        let groupRelays = (try? ffi.mlsGetGroupInfo(groupIdHex: groupIdHex))?.relays ?? []
        try? ffi.mlsMergePendingCommit(groupIdHex: groupIdHex)
        let data = try ffi.mlsLeaveGroup(groupIdHex: groupIdHex)
        do {
            try await publishMlsKind445(data: data, groupRelays: groupRelays)
        } catch {
            // 退出イベント配信失敗は非fatal（ローカルでは退出状態を維持）。
            AppLogger.log("MLS", "leaveMlsGroup: publish failed (non-fatal) group=\(groupIdHex) err=\(mlsRedactedError(error))")
        }
    }

    // MARK: - Key Package

    func forceRepublishMyKeyPackageIfNeeded(myPubkeyHex: String) async {
        guard let ffi = ensureMlsClient() else { return }
        do {
            try await publishKeyPackage(ffi: ffi)
            AppLogger.log("MLS", "forceRepublishMyKeyPackageIfNeeded: republished key package + relay lists")
        } catch {
            AppLogger.log("MLS", "forceRepublishMyKeyPackageIfNeeded: republish failed: \(mlsRedactedError(error))")
        }
    }

    func ensureKeyPackagePublished(ffi: MlsFFIBridge, myPubkeyHex: String) async {
        guard !keyPackagePublished else { return }
        let f = NostrFilter(
            ids: nil,
            authors: [myPubkeyHex],
            kinds: [NostrKind.mlsKeyPackage, NostrKind.mlsKeyPackageLegacy],
            since: nil,
            until: nil,
            limit: 1,
            tags: nil,
            search: nil
        )
        let events = await fetchEvents(filters: [f], timeoutSeconds: 3.0)
        let nonConsumed = events.filter { !isConsumedKeyPackageEventId($0.id) }
        if let json = selectBestKeyPackageEventsByAuthor(events: nonConsumed.compactMap { encodeEventJSON($0) })[myPubkeyHex] {
            let hasRelays = extractTagValue(from: json, tag: "relays") != nil
            if hasRelays { keyPackagePublished = true; return }
        }
        try? await publishKeyPackage(ffi: ffi)
    }

    private func publishKeyPackage(ffi: MlsFFIBridge) async throws {
        let kpData    = try ffi.mlsCreateKeyPackage()
        // Interop: publish KeyPackage to broader relay set so WhiteNoise can reliably fetch it.
        let relayUrls = canonicalRelayUrls(
            Array(prefs.selectedRelays.prefix(3)) + [
                "wss://yabu.me",
                "wss://relay.damus.io",
                "wss://relay.primal.net",
                "wss://nos.lol"
            ]
        )
        var tags30443 = kpData.tags.map { t -> [String] in t.first == "relays" ? ["relays"] + relayUrls : t }
        if !tags30443.contains(where: { $0.first == "relays" }) { tags30443.append(["relays"] + relayUrls) }

        // MIP-00 canonical publish (kind:30443).
        // IMPORTANT: persist the exact signed event that was published so later
        // MIP-02 consumed-keypackage rotation can resolve the correct event id.
        let signed30443 = try await publishEventAndReturnSigned(kind: Int(kpData.kind), tags: tags30443, content: kpData.content)

        if let json30443 = encodeEventJSON(signed30443) {
            var map = prefs.mlsKeyPackageEventJsonById
            map[signed30443.id] = json30443
            prefs.mlsKeyPackageEventJsonById = map
        }

        // Migration compatibility publish (legacy kind:443) only until 2026-05-01.
        if shouldDualPublishLegacy443() {
            var tags443 = kpData.legacyTags
            if tags443.isEmpty {
                // Fallback for older FFI: derive by removing d tag.
                tags443 = tags30443.filter { $0.first != "d" }
            }
            // Keep relay hints current even on legacy event.
            tags443 = tags443.map { t in t.first == "relays" ? ["relays"] + relayUrls : t }
            if !tags443.contains(where: { $0.first == "relays" }) { tags443.append(["relays"] + relayUrls) }

            let signed443 = try await publishEventAndReturnSigned(kind: NostrKind.mlsKeyPackageLegacy, tags: tags443, content: kpData.content)

            if let json443 = encodeEventJSON(signed443) {
                var map = prefs.mlsKeyPackageEventJsonById
                map[signed443.id] = json443
                prefs.mlsKeyPackageEventJsonById = map
            }
        }

        // Marmot MIP-00 / Kind 10051 — publish preferred KeyPackage relays.
        // MIP-00 expects ["relay", "wss://..."] tags for kind:10051.
        let kpRelayTags = relayUrls.map { ["relay", $0] }
        try await publishEvent(kind: NostrKind.mlsKeyPackageRelays, tags: kpRelayTags, content: "")
        // Also publish kind 10050 so peers can discover our preferred receiving relays (NIP-17 style "r").
        let dmRelayTags = relayUrls.map { ["r", $0] }
        try await publishEvent(kind: NostrKind.dmRelayList, tags: dmRelayTags, content: "")
        AppLogger.log("MLS", "publishKeyPackage: published kind=\(kpData.kind) legacy443=\(shouldDualPublishLegacy443()) + kind10051/kind10050 relays=\(relayUrls.count)")
        keyPackagePublished = true
    }

    // MARK: - Publish Helpers

    /// Kind-445 (MLS message/commit/proposal) を publish。
    /// data.content は MDK がエフェメラル鍵で署名済みの完全なイベントJSON。
    /// groupRelays を指定するとグループのリレーにも publish する（WhiteNoise 互換）。
    private func publishMlsKind445(data: FfiEncryptedMessageData, groupRelays: [String] = []) async throws {
        try await publishMlsRawEventJSON(data.content, groupRelays: groupRelays)
    }

    private func publishMlsRawEventJSON(_ rawEventJSON: String, groupRelays: [String] = []) async throws {
        guard let eventData = rawEventJSON.data(using: .utf8),
              let eventObj = (try? JSONSerialization.jsonObject(with: eventData)) as? [String: Any] else {
            throw MlsError.invalidPayload
        }

        // Validate minimum outer shape for kind:445 before publish.
        // NOTE: rawEventJSON is already signed by MDK. Do NOT mutate tags/content here.
        if (eventObj["kind"] as? Int) == NostrKind.mlsGroupMessage {
            guard let tagsAny = eventObj["tags"] as? [[Any]],
                  tagsAny.contains(where: { ($0.first as? String) == "h" && $0.count >= 2 && (($0[1] as? String)?.isEmpty == false) }) else {
                throw MlsError.invalidPayload
            }
        }

        // グループリレー + 選択リレー + WhiteNoise interop relay の統合セット。
        // Welcome 1059 は recipient の inbox relay に届く必要があるため、auth.nostr1.com も除外しない。
        let allRelays = mlsRelayUrls(groupRelays)
        // グループリレーを接続プールに追加
        if !groupRelays.isEmpty {
            await client.connect(relayUrls: groupRelays)
        }
        AppLogger.log("MLS", "publishMlsRawEventJSON: targetRelays=\(allRelays.count)")
        try await client.publishRawEventJSON(rawEventJSON, to: allRelays)
    }

    /// Marmot MIP-02: Welcome publish.
    ///
    /// WhiteNoise / Marmot interop expects the Welcome rumor (kind 444) to be
    /// delivered as a NIP-59 gift-wrap (kind 1059). The inner rumor itself is not
    /// a publishable signed event, so we use giftWrappedEventJson as the primary
    /// publish path and skip raw kind-444 rumor publishing.
    private func publishMlsWelcome(data: FfiWelcomeEventData, groupRelays: [String] = []) async throws {
        if !data.giftWrappedEventJson.isEmpty {
            do {
                try await publishMlsRawEventJSON(data.giftWrappedEventJson, groupRelays: groupRelays)
                AppLogger.log("MLS", "publishMlsWelcome: kind1059 gift-wrap publish ok recipient=\(mlsLogPrefix(data.recipientPubkey))")
            } catch {
                AppLogger.log("MLS", "publishMlsWelcome: kind1059 gift-wrap publish failed: \(mlsRedactedError(error))")
                throw error
            }

            // Interop safety: also publish legacy kind:444 only when inner rumor content is base64 welcome payload.
            // Avoid publishing JSON-looking rumors as kind:444 content (peers reject with invalid base64).
            if !data.content.isEmpty, Data(base64Encoded: data.content) != nil {
                do {
                    var tags = data.tags
                    if !tags.contains(where: { $0.first == "p" && $0.count >= 2 && $0[1] == data.recipientPubkey }) {
                        tags.append(["p", data.recipientPubkey])
                    }
                    try await publishEvent(kind: NostrKind.mlsWelcomeInner, tags: tags, content: data.content)
                    AppLogger.log("MLS", "publishMlsWelcome: legacy kind444 publish ok recipient=\(mlsLogPrefix(data.recipientPubkey))")
                } catch {
                    AppLogger.log("MLS", "publishMlsWelcome: legacy kind444 publish failed (non-fatal): \(mlsRedactedError(error))")
                }
            }
            return
        }

        if !data.content.isEmpty, Data(base64Encoded: data.content) != nil {
            // gift-wrap missing fallback
            var tags = data.tags
            if !tags.contains(where: { $0.first == "p" && $0.count >= 2 && $0[1] == data.recipientPubkey }) {
                tags.append(["p", data.recipientPubkey])
            }
            try await publishEvent(kind: NostrKind.mlsWelcomeInner, tags: tags, content: data.content)
            AppLogger.log("MLS", "publishMlsWelcome: fallback legacy kind444 publish recipient=\(mlsLogPrefix(data.recipientPubkey))")
        } else if !data.content.isEmpty {
            AppLogger.log("MLS", "publishMlsWelcome: skipped non-base64 legacy kind444 publish recipient=\(mlsLogPrefix(data.recipientPubkey))")
        }
    }

    // MARK: - Key Package Helpers

    private func isConsumedKeyPackageEventId(_ eventId: String) -> Bool {
        prefs.mlsConsumedKeyPackageEventIds.contains(eventId)
    }

    private func recordConsumedKeyPackageEventId(_ eventId: String) {
        guard !eventId.isEmpty else { return }
        var consumed = prefs.mlsConsumedKeyPackageEventIds
        consumed.insert(eventId)
        prefs.mlsConsumedKeyPackageEventIds = consumed
    }

    private func recordConsumedKeyPackageEventId(fromEventJSON eventJSON: String) {
        guard let data = eventJSON.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let eventId = obj["id"] as? String,
              !eventId.isEmpty else { return }
        recordConsumedKeyPackageEventId(eventId)
    }

    private func publishConsumedKeyPackageDeleteBestEffort(eventId: String) async {
        guard !eventId.isEmpty else { return }
        do {
            try await publishDelete(eventId: eventId)
            AppLogger.log("MLS", "KeyPackage consumed delete published id=\(eventId)")
        } catch {
            AppLogger.log("MLS", "KeyPackage consumed delete failed (best-effort) id=\(eventId) err=\(mlsRedactedError(error))")
        }
    }

    private func fetchLatestKeyPackage(pubkey: String, ffi: MlsFFIBridge) async -> String? {
        let f = NostrFilter(
            ids: nil,
            authors: [pubkey],
            kinds: [NostrKind.mlsKeyPackage, NostrKind.mlsKeyPackageLegacy],
            since: nil,
            until: nil,
            limit: 4,
            tags: nil,
            search: nil
        )

        let preferredRelays = await resolveKeyPackageRelaysForMembers([pubkey])[pubkey] ?? []
        if !preferredRelays.isEmpty {
            await client.connect(relayUrls: preferredRelays)
            var merged: [String: NostrEvent] = [:]
            var perRelayHits: [String: Int] = [:]
            for relay in preferredRelays.prefix(12) {
                let events = await client.fetchEventsFromRelay(relay, filters: [f], timeoutSeconds: 4.0)
                perRelayHits[relay] = events.count
                for ev in events { merged[ev.id] = ev }
            }
            let evs = merged.values
                .filter { !isConsumedKeyPackageEventId($0.id) }
                .compactMap { encodeEventJSON($0) }
            if let best = selectBestKeyPackageEventsByAuthor(events: evs)[pubkey] {
                AppLogger.log("MLS", "fetchLatestKeyPackage: author=\(mlsLogPrefix(pubkey)) via10051 relays=\(preferredRelays.count) totalEvents=\(evs.count) hits=\(perRelayHits.values.reduce(0, +)) found=yes")
                return best
            }
            AppLogger.log("MLS", "fetchLatestKeyPackage: author=\(mlsLogPrefix(pubkey)) via10051 relays=\(preferredRelays.count) totalEvents=\(evs.count) hits=\(perRelayHits.values.reduce(0, +)) found=no")
        }

        // Discovery fallback: include WhiteNoise relay set + global ecosystem relays.
        let discoveryRelays = [
            "wss://relay.nostr.wirednet.jp",
            "wss://yabu.me",
            "wss://r.kojira.io",
            "wss://relay.damus.io",
            "wss://relay.primal.net",
            "wss://nos.lol",
            "wss://purplepag.es",
            "wss://auth.nostr1.com"
        ]
        await client.connect(relayUrls: discoveryRelays)

        var mergedFallback: [String: NostrEvent] = [:]
        for relay in discoveryRelays {
            let events = await client.fetchEventsFromRelay(relay, filters: [f], timeoutSeconds: 4.0)
            for ev in events { mergedFallback[ev.id] = ev }
        }
        for ev in await fetchEvents(filters: [f], timeoutSeconds: 5.0) {
            mergedFallback[ev.id] = ev
        }

        let evs = mergedFallback.values
            .filter { !isConsumedKeyPackageEventId($0.id) }
            .compactMap { encodeEventJSON($0) }
        if let best = selectBestKeyPackageEventsByAuthor(events: evs)[pubkey] {
            AppLogger.log("MLS", "fetchLatestKeyPackage: author=\(mlsLogPrefix(pubkey)) viaFallback relays=\(discoveryRelays.count) events=\(evs.count) found=true")
            return best
        }

        // Final fallback (interop): if strict pre-selection yields none, return freshest raw candidate
        // and let mlsAddMember perform final protocol-level acceptance.
        let rawCandidates = mergedFallback.values
            .filter { $0.pubkey == pubkey && ($0.kind == NostrKind.mlsKeyPackage || $0.kind == NostrKind.mlsKeyPackageLegacy) }
            .filter { !isConsumedKeyPackageEventId($0.id) }
            .sorted { lhs, rhs in
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
                return lhs.id < rhs.id
            }
        if let raw = rawCandidates.first, let rawJSON = encodeEventJSON(raw) {
            AppLogger.log("MLS", "fetchLatestKeyPackage: author=\(mlsLogPrefix(pubkey)) viaFallback relays=\(discoveryRelays.count) events=\(evs.count) strict=false rawFallback=true kind=\(raw.kind) id=\(raw.id)")
            return rawJSON
        }

        AppLogger.log("MLS", "fetchLatestKeyPackage: author=\(mlsLogPrefix(pubkey)) viaFallback relays=\(discoveryRelays.count) events=\(evs.count) found=false")
        return nil
    }

    private func fetchKeyPackages(pubkeys: [String], ffi: MlsFFIBridge) async -> [String] {
        let f = NostrFilter(
            ids: nil,
            authors: pubkeys,
            kinds: [NostrKind.mlsKeyPackage, NostrKind.mlsKeyPackageLegacy],
            since: nil,
            until: nil,
            limit: pubkeys.count * 4,
            tags: nil,
            search: nil
        )
        var collected: [NostrEvent] = []
        let kpRelayMap = await resolveKeyPackageRelaysForMembers(pubkeys)
        let kpRelays = canonicalRelayUrls(kpRelayMap.values.flatMap { $0 })
        if !kpRelays.isEmpty {
            await client.connect(relayUrls: kpRelays)
            for relay in kpRelays.prefix(10) {
                let evs = await client.fetchEventsFromRelay(relay, filters: [f], timeoutSeconds: 4.0)
                collected.append(contentsOf: evs)
            }
        }
        collected.append(contentsOf: await fetchEvents(filters: [f], timeoutSeconds: 5.0))

        let evs = Dictionary(uniqueKeysWithValues: collected.map { ($0.id, $0) }).values
            .filter { !isConsumedKeyPackageEventId($0.id) }
            .compactMap { encodeEventJSON($0) }
        let bestPerAuthor = selectBestKeyPackageEventsByAuthor(events: evs)
        AppLogger.log("MLS", "fetchKeyPackages: authors=\(pubkeys.count) kpRelays=\(kpRelays.count) found=\(bestPerAuthor.count)")
        return Array(bestPerAuthor.values)
    }

    /// Android parity selection policy:
    /// - choose latest kind:30443 by created_at per author
    /// - fallback to latest kind:443 by created_at per author
    /// - do not apply extra iOS-only prefilters here (final accept/reject is done by mlsAddMember)
    private func selectBestKeyPackageEventsByAuthor(events: [String]) -> [String: String] {
        struct Candidate {
            let eventJSON: String
            let pubkey: String
            let kind: Int
            let createdAt: Int64
            let id: String
        }

        func parse(_ eventJSON: String) -> Candidate? {
            guard let obj = (try? JSONSerialization.jsonObject(with: Data(eventJSON.utf8))) as? [String: Any],
                  let kind = obj["kind"] as? Int,
                  (kind == NostrKind.mlsKeyPackage || kind == NostrKind.mlsKeyPackageLegacy),
                  let pubkey = obj["pubkey"] as? String, !pubkey.isEmpty,
                  let id = obj["id"] as? String, !id.isEmpty else {
                return nil
            }

            let createdAt: Int64
            if let n = obj["created_at"] as? NSNumber {
                createdAt = n.int64Value
            } else if let i = obj["created_at"] as? Int {
                createdAt = Int64(i)
            } else {
                return nil
            }

            return Candidate(eventJSON: eventJSON, pubkey: pubkey, kind: kind, createdAt: createdAt, id: id)
        }

        let parsed = events.compactMap(parse)
        let byAuthor = Dictionary(grouping: parsed, by: { $0.pubkey })
        var best: [String: String] = [:]

        func latest(_ candidates: [Candidate]) -> Candidate? {
            candidates.sorted { lhs, rhs in
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
                return lhs.id < rhs.id
            }.first
        }

        for (author, candidates) in byAuthor {
            let k30443 = candidates.filter { $0.kind == NostrKind.mlsKeyPackage }
            if let selected = latest(k30443) {
                best[author] = selected.eventJSON
                continue
            }

            let k443 = candidates.filter { $0.kind == NostrKind.mlsKeyPackageLegacy }
            if let selected = latest(k443) {
                best[author] = selected.eventJSON
            }
        }

        return best
    }


    // MARK: - MIP-02 Welcome Validation / Post-Join Actions

    /// Validate transport-level Welcome event constraints before handing off to Rust.
    ///
    /// - For gift-wrapped kind:1059, outer payload is opaque and validated during unwrapping.
    /// - For legacy/plain kind:444, enforce MIP-02 required tags and base64 constraints.
    private func validateWelcomeEventForMip02(_ ev: NostrEvent) throws {
        switch ev.kind {
        case NostrKind.mlsWelcome:
            // kind:1059 gift-wrap. Inner rumor validation is delegated to Rust MDK.
            return
        case NostrKind.mlsWelcomeInner:
            // Interop-first: do not pre-reject legacy kind:444 by iOS-side shape checks.
            // Delegate full validation/acceptance to Rust MDK (mlsProcessWelcome),
            // because peers may publish equivalent payload shapes across ecosystem versions.
            return
        default:
            throw MlsError.invalidWelcomeKind
        }
    }

    /// MIP-02 post-join behavior:
    /// 1) Best-effort catch-up of outstanding commits/messages
    /// 2) Self-update commit creation/publish/merge as soon as practical
    /// 3) Persist tracking so we can enforce retry within 24h window
    private func postWelcomeBestEffortCatchUpAndSelfUpdate(group: FfiMlsGroupInfo, ffi: MlsFFIBridge) async {
        let now = Int64(Date().timeIntervalSince1970)
        var joinedMap = prefs.mlsJoinedAtByGroupId
        if joinedMap[group.groupIdHex] == nil {
            joinedMap[group.groupIdHex] = now
            prefs.mlsJoinedAtByGroupId = joinedMap
        }

        // 1) Catch-up best-effort (non-fatal)
        do {
            _ = try await fetchMlsMessages(groupIdHex: group.groupIdHex)
        } catch {
            AppLogger.log("MLS", "postWelcome: catch-up failed (non-fatal) group=\(group.groupIdHex) err=\(mlsRedactedError(error))")
        }

        // 2) Self-update commit (best-effort). mlsCreateRecoveryCommit is a self-update commit emitter.
        do {
            try await publishAndMergeSelfUpdateCommit(
                groupIdHex: group.groupIdHex,
                memberPubkeys: group.memberPubkeys,
                relays: group.relays,
                ffi: ffi,
                context: "postWelcome"
            )
            AppLogger.log("MLS", "postWelcome: self-update committed group=\(group.groupIdHex)")
        } catch {
            AppLogger.log("MLS", "postWelcome: self-update failed (retry later via normal recovery loop) group=\(group.groupIdHex) err=\(mlsRedactedError(error))")
        }

        // 3) MIP-02 MUST within 24h: sweep groups that still need a self-update.
        await enforceSelfUpdateDeadlineIfNeeded(ffi: ffi)
    }

    // MARK: - Group Enrich / Bridge

    private func enrichFfiGroup(_ ffiGroup: FfiMlsGroupInfo, ffi: MlsFFIBridge) throws -> MlsGroup {
        let fresh         = (try? ffi.mlsGetGroupInfo(groupIdHex: ffiGroup.groupIdHex)) ?? ffiGroup
        let memberPubkeys = fresh.memberPubkeys
        let profiles: [(String, UserProfile)] = memberPubkeys.compactMap { pk in
            cache.getCachedProfile(pk).map { (pk, $0) }
        }
        return MlsGroup(
            groupIdHex: fresh.groupIdHex, name: fresh.name, description: fresh.description,
            adminPubkeys: fresh.adminPubkeys, memberPubkeys: memberPubkeys,
            relays: fresh.relays, createdAt: Int64(fresh.createdAt),
            epoch: Int64(fresh.epoch), disappearingMessageSecs: fresh.disappearingMessageSecs.map(Int64.init), isDm: fresh.isDm,
            memberProfiles: Dictionary(uniqueKeysWithValues: profiles)
        )
    }

    /// Create/publish/merge a post-Welcome self-update commit.
    ///
    /// Contract note: groupIdHex is the Nostr group id (Kind 445 h tag), not
    /// the internal MLS group id. The required order is:
    /// mlsCreateRecoveryCommit -> publish Kind 445 -> mlsMergePendingCommit.
    /// If publish fails, clear the pending commit so the retry source
    /// (mlsGroupsNeedingSelfUpdate) can create a fresh commit later instead
    /// of leaving the group stuck behind an unpublished pending commit.
    private func publishAndMergeSelfUpdateCommit(
        groupIdHex: String,
        memberPubkeys: [String],
        relays: [String],
        ffi: MlsFFIBridge,
        context: String
    ) async throws {
        let inboxRelays = await resolveInboxRelaysForMembers(memberPubkeys)
        let targetRelays = mlsRelayUrls(relays + inboxRelays)

        let commit = try ffi.mlsCreateRecoveryCommit(groupIdHex: groupIdHex)
        do {
            try await publishMlsKind445(data: commit, groupRelays: targetRelays)
        } catch {
            do {
                try ffi.mlsClearPendingCommit(groupIdHex: groupIdHex)
                AppLogger.log("MLS", "\(context): self-update publish failed; cleared pending commit group=\(groupIdHex) err=\(mlsRedactedError(error))")
            } catch {
                AppLogger.log("MLS", "\(context): self-update publish failed; clear pending also failed group=\(groupIdHex) err=\(mlsRedactedError(error))")
            }
            if let account = prefs.publicKeyHex {
                mlsRetryStore.enqueueSelfUpdate(
                    accountPubkey: account,
                    groupIdHex: groupIdHex,
                    relayUrls: targetRelays,
                    lastErrorKind: classifyMlsRetryError(error)
                )
                AppLogger.log("MLS", "\(context): queued self-update retry group=\(groupIdHex) relays=\(targetRelays.count)")
            }
            throw error
        }

        try ffi.mlsMergePendingCommit(groupIdHex: groupIdHex)

        var doneMap = prefs.mlsSelfUpdateCompletedAtByGroupId
        doneMap[groupIdHex] = Int64(Date().timeIntervalSince1970)
        prefs.mlsSelfUpdateCompletedAtByGroupId = doneMap
    }

    /// MIP-02 MUST within 24h: retry self-update for joined groups without completion marker.
    private func enforceSelfUpdateDeadlineIfNeeded(ffi: MlsFFIBridge) async {
        let now = Int64(Date().timeIntervalSince1970)

        // Prefer Rust/MDK source of truth for post-join self-update requirement.
        // threshold=86400 enforces MIP-02 "within 24h" target.
        let candidateGroups: [String]
        if let ids = try? ffi.mlsGroupsNeedingSelfUpdate(thresholdSecs: 86_400), !ids.isEmpty {
            candidateGroups = ids
        } else {
            // Fallback for older FFI/runtime without state query support.
            let joined = prefs.mlsJoinedAtByGroupId
            let done = prefs.mlsSelfUpdateCompletedAtByGroupId
            candidateGroups = joined.compactMap { (groupId, joinedAt) in
                if done[groupId] != nil { return nil }
                return (now - joinedAt) >= 60 ? groupId : nil
            }
        }

        for groupId in candidateGroups {
            do {
                let gi = try ffi.mlsGetGroupInfo(groupIdHex: groupId)
                try await publishAndMergeSelfUpdateCommit(
                    groupIdHex: groupId,
                    memberPubkeys: gi.memberPubkeys,
                    relays: gi.relays,
                    ffi: ffi,
                    context: "enforceSelfUpdateDeadlineIfNeeded"
                )
                AppLogger.log("MLS", "enforceSelfUpdateDeadlineIfNeeded: self-update success group=\(groupId)")
            } catch {
                AppLogger.log("MLS", "enforceSelfUpdateDeadlineIfNeeded: retry failed group=\(groupId) err=\(mlsRedactedError(error))")
            }
        }
    }

    /// MIP-02 key package lifecycle:
    /// Rotate consumed key package after successful welcome processing.
    /// - consumed kind:30443 -> publish replacement using SAME d
    /// - consumed kind:443   -> publish fresh kind:30443 with random d
    private func rotateConsumedKeyPackageAfterWelcomeIfNeeded(
        welcomeEvent: NostrEvent,
        ffi: MlsFFIBridge
    ) async {
        guard let consumedEventId = welcomeEvent.getTagValue("e"), !consumedEventId.isEmpty else {
            return
        }
        recordConsumedKeyPackageEventId(consumedEventId)
        keyPackagePublished = false

        let relayHints = welcomeEvent.tags.first(where: { $0.first == "relays" }).map { Array($0.dropFirst()) } ?? []
        let candidateRelays = mlsRelayUrls(relayHints)
        await client.connect(relayUrls: candidateRelays)

        let byId = NostrFilter(ids: [consumedEventId], authors: nil, kinds: [NostrKind.mlsKeyPackage, NostrKind.mlsKeyPackageLegacy], since: nil, until: nil, limit: 1, tags: nil, search: nil)
        let consumedEvent = await fetchEvents(filters: [byId], timeoutSeconds: 4.0).first

        // Build raw JSON once so we can both (a) inspect kind/d and (b) ask Rust to delete consumed init_key material.
        // Prefer relay-fetched event; fallback to locally persisted keypackage map.
        let localConsumedJson = prefs.mlsKeyPackageEventJsonById[consumedEventId]
        let consumedEventJSON = consumedEvent.flatMap { encodeEventJSON($0) } ?? localConsumedJson

        do {
            let kpData = try ffi.mlsCreateKeyPackage()
            let relayUrls = canonicalRelayUrls(Array(prefs.selectedRelays.prefix(3)))
            var tags30443 = kpData.tags.map { t -> [String] in t.first == "relays" ? ["relays"] + relayUrls : t }
            if !tags30443.contains(where: { $0.first == "relays" }) { tags30443.append(["relays"] + relayUrls) }

            // If consumed was kind:30443, reuse same d tag.
            // Prefer relay event metadata; fallback to locally persisted JSON parse; then kpData.dTag.
            if let consumedEvent, consumedEvent.kind == NostrKind.mlsKeyPackage,
               let d = consumedEvent.getTagValue("d"), !d.isEmpty {
                tags30443.removeAll { $0.first == "d" }
                tags30443.insert(["d", d], at: 0)
            } else if let consumedEventJSON,
                      let data = consumedEventJSON.data(using: .utf8),
                      let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                      let kind = obj["kind"] as? Int,
                      kind == NostrKind.mlsKeyPackage,
                      let rawTags = obj["tags"] as? [[Any]],
                      let dTag = rawTags.first(where: { ($0.first as? String) == "d" })?.dropFirst().first as? String,
                      !dTag.isEmpty {
                tags30443.removeAll { $0.first == "d" }
                tags30443.insert(["d", dTag], at: 0)
            } else if !kpData.dTag.isEmpty {
                tags30443.removeAll { $0.first == "d" }
                tags30443.insert(["d", kpData.dTag], at: 0)
            }

            // Canonical rotation publish (kind:30443; same d when consumed was 30443).
            let signed30443 = try await publishEventAndReturnSigned(kind: Int(kpData.kind), tags: tags30443, content: kpData.content)
            if let json30443 = encodeEventJSON(signed30443) {
                var map = prefs.mlsKeyPackageEventJsonById
                map[signed30443.id] = json30443
                prefs.mlsKeyPackageEventJsonById = map
            }
            // Migration compatibility publish (legacy kind:443) until 2026-05-01 only.
            if shouldDualPublishLegacy443() {
                var tags443 = kpData.legacyTags
                if tags443.isEmpty {
                    // Fallback for older FFI
                    tags443 = tags30443.filter { $0.first != "d" }
                }
                tags443 = tags443.map { t in t.first == "relays" ? ["relays"] + relayUrls : t }
                if !tags443.contains(where: { $0.first == "relays" }) { tags443.append(["relays"] + relayUrls) }

                let signed443 = try await publishEventAndReturnSigned(kind: NostrKind.mlsKeyPackageLegacy, tags: tags443, content: kpData.content)
                if let json443 = encodeEventJSON(signed443) {
                    var map = prefs.mlsKeyPackageEventJsonById
                    map[signed443.id] = json443
                    prefs.mlsKeyPackageEventJsonById = map
                }
            }

            let kpRelayTags = relayUrls.map { ["relay", $0] }
            try await publishEvent(kind: NostrKind.mlsKeyPackageRelays, tags: kpRelayTags, content: "")
            let dmRelayTags = relayUrls.map { ["r", $0] }
            try await publishEvent(kind: NostrKind.dmRelayList, tags: dmRelayTags, content: "")
            await publishConsumedKeyPackageDeleteBestEffort(eventId: consumedEventId)

            // MIP-02: after successful welcome processing + replacement KeyPackage publish,
            // delete consumed init_key/private keypackage material from local storage.
            if let consumedEventJSON {
                do {
                    try ffi.mlsDeleteConsumedKeyPackageFromEventJSON(eventJSON: consumedEventJSON)
                    AppLogger.log("MLS", "rotateConsumedKeyPackage: deleted consumed key package material id=\(consumedEventId)")
                } catch {
                    AppLogger.log("MLS", "rotateConsumedKeyPackage: consumed key package delete failed id=\(consumedEventId) err=\(mlsRedactedError(error))")
                }
            }

            AppLogger.log("MLS", "rotateConsumedKeyPackage: rotated consumedId=\(consumedEventId) consumedKind=\(consumedEvent?.kind ?? -1)")
        } catch {
            let ownerPubkey = consumedEvent?.pubkey
                ?? consumedEventJSON.flatMap { extractPubkey(from: $0) }
                ?? prefs.publicKeyHex
                ?? ""
            if let account = prefs.publicKeyHex, !ownerPubkey.isEmpty {
                mlsRetryStore.enqueueKeyPackageRotation(
                    accountPubkey: account,
                    keyPackageOwnerPubkey: ownerPubkey,
                    keyPackageEventId: consumedEventId,
                    relayUrls: candidateRelays,
                    lastErrorKind: classifyMlsRetryError(error)
                )
                AppLogger.log("MLS", "rotateConsumedKeyPackage: queued rotation retry consumedId=\(consumedEventId) owner=\(mlsLogPrefix(ownerPubkey)) relays=\(candidateRelays.count)")
            }
            AppLogger.log("MLS", "rotateConsumedKeyPackage: rotate failed id=\(consumedEventId) err=\(mlsRedactedError(error))")
        }
    }

    func bridgeFfiGroup(_ g: FfiMlsGroupInfo) -> MlsGroup {
        MlsGroup(
            groupIdHex: g.groupIdHex, name: g.name, description: g.description,
            adminPubkeys: g.adminPubkeys, memberPubkeys: g.memberPubkeys,
            relays: g.relays, createdAt: Int64(g.createdAt), epoch: Int64(g.epoch),
            disappearingMessageSecs: g.disappearingMessageSecs.map(Int64.init),
            isDm: g.isDm
        )
    }

    // MARK: - Quick Profile Fetch (non-blocking)

    private func quickFetchProfiles(pubkeys: [String]) async -> [UserProfile] {
        guard !pubkeys.isEmpty else { return [] }

        var byKey: [String: UserProfile] = [:]
        var missing: [String] = []

        for pk in pubkeys {
            if let cached = cache.getCachedProfile(pk) {
                byKey[pk] = cached
            } else {
                missing.append(pk)
            }
        }

        // Relay fallback for missing profiles (improves cross-client avatar compatibility)
        if !missing.isEmpty {
            let f = NostrFilter(
                ids: nil,
                authors: missing,
                kinds: [NostrKind.metadata],
                since: nil,
                until: nil,
                limit: missing.count,
                tags: nil,
                search: nil
            )
            let events = await fetchEvents(filters: [f], timeoutSeconds: 5.0)
            var latest: [String: NostrEvent] = [:]
            for ev in events {
                if (latest[ev.pubkey]?.createdAt ?? 0) < ev.createdAt {
                    latest[ev.pubkey] = ev
                }
            }
            for ev in latest.values {
                guard let data = ev.content.data(using: .utf8),
                      let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { continue }

                let picture = (obj["picture"] as? String)
                    ?? (obj["image"] as? String)
                    ?? (obj["avatar"] as? String)
                    ?? (obj["icon"] as? String)

                func birthdayString(_ raw: Any?) -> String? {
                    if let s = raw as? String, !s.isEmpty { return s }
                    if let dict = raw as? [String: Any],
                       let month = dict["month"] as? Int,
                       let day = dict["day"] as? Int,
                       (1...12).contains(month),
                       (1...31).contains(day) {
                        if let year = dict["year"] as? Int, year > 0 {
                            return String(format: "%04d-%02d-%02d", year, month, day)
                        }
                        return String(format: "%02d-%02d", month, day)
                    }
                    return nil
                }

                let p = UserProfile(
                    pubkey: ev.pubkey,
                    name: obj["name"] as? String,
                    displayName: (obj["display_name"] as? String) ?? (obj["displayName"] as? String),
                    about: obj["about"] as? String,
                    picture: picture,
                    nip05: obj["nip05"] as? String,
                    banner: obj["banner"] as? String,
                    lud16: obj["lud16"] as? String,
                    website: obj["website"] as? String,
                    birthday: birthdayString(obj["birthday"]) ?? birthdayString(obj["birthdate"]) ?? birthdayString(obj["birth"]),
                    geohash: obj["geohash"] as? String
                )
                byKey[ev.pubkey] = p
                cache.setCachedProfile(ev.pubkey, p)
            }
        }

        return pubkeys.compactMap { byKey[$0] }
    }

    // MARK: - Relay/Fetch Helpers

    /// Ensure group relays are connected before MLS fetch/publish paths.
    private func ensureGroupRelaysConnected(_ relays: [String]) async {
        guard !relays.isEmpty else { return }
        await client.connect(relayUrls: relays)
    }

    /// Resolve KeyPackage relays for members (Marmot kind 10051 preferred).
    private func resolveKeyPackageRelaysForMembers(_ memberPubkeys: [String]) async -> [String: [String]] {
        guard !memberPubkeys.isEmpty else { return [:] }

        let discoveryRelays = [
            "wss://relay.nostr.wirednet.jp",
            "wss://yabu.me",
            "wss://r.kojira.io",
            "wss://relay.damus.io",
            "wss://relay.primal.net",
            "wss://nos.lol",
            "wss://purplepag.es",
            "wss://auth.nostr1.com"
        ]
        await client.connect(relayUrls: discoveryRelays)

        let kpFilter = NostrFilter(ids: nil, authors: memberPubkeys, kinds: [NostrKind.mlsKeyPackageRelays], since: nil, until: nil, limit: memberPubkeys.count * 2, tags: nil, search: nil)
        let kpEvents = await fetchEvents(filters: [kpFilter], timeoutSeconds: 4.0)
        var relayMap: [String: Set<String>] = [:]
        for ev in kpEvents {
            for t in ev.tags where (t.first == "r" || t.first == "relay") && t.count >= 2 {
                relayMap[ev.pubkey, default: []].insert(t[1])
            }
        }
        // Fallback: if a member has no kind-10051, reuse kind-10050 relay hints.
        if relayMap.count < memberPubkeys.count {
            let dmFilter = NostrFilter(ids: nil, authors: memberPubkeys, kinds: [NostrKind.dmRelayList], since: nil, until: nil, limit: memberPubkeys.count * 2, tags: nil, search: nil)
            let dmEvents = await fetchEvents(filters: [dmFilter], timeoutSeconds: 4.0)
            for ev in dmEvents {
                for t in ev.tags where (t.first == "r" || t.first == "relay") && t.count >= 2 {
                    relayMap[ev.pubkey, default: []].insert(t[1])
                }
            }
        }
        AppLogger.log("MLS", "resolveKeyPackageRelaysForMembers: members=\(memberPubkeys.count) resolvedAuthors=\(relayMap.count)")
        return relayMap.mapValues { Array($0) }
    }

    /// Resolve inbox relays for members (NIP-17 kind 10050 preferred, fallback kind 10002).
    /// グローバルリレーにも接続して、JP リレーに NIP-65 がないユーザーの relay list も取得する。
    private func resolveInboxRelaysForMembers(_ memberPubkeys: [String]) async -> [String] {
        guard !memberPubkeys.isEmpty else { return [] }

        // グローバルリレーを一時接続して NIP-65 / DM relay list / kind10051 取得範囲を広げる
        let discoveryRelays = [
            "wss://relay.nostr.wirednet.jp",
            "wss://yabu.me",
            "wss://r.kojira.io",
            "wss://relay.damus.io",
            "wss://relay.primal.net",
            "wss://nos.lol",
            "wss://purplepag.es",
            "wss://auth.nostr1.com"
        ]
        await client.connect(relayUrls: discoveryRelays)

        var relays = Set<String>()

        // 0) Marmot KeyPackage relay list (kind 10051) — useful for WhiteNoise relay discovery.
        let kpRelayMap = await resolveKeyPackageRelaysForMembers(memberPubkeys)
        for entry in kpRelayMap.values {
            for relay in entry { relays.insert(relay) }
        }

        // 1) NIP-17 DM relay list (kind 10050)
        let dmFilter = NostrFilter(ids: nil, authors: memberPubkeys, kinds: [NostrKind.dmRelayList], since: nil, until: nil, limit: memberPubkeys.count * 2, tags: nil, search: nil)
        let dmEvents = await fetchEvents(filters: [dmFilter], timeoutSeconds: 4.0)
        for ev in dmEvents {
            for t in ev.tags where (t.first == "r" || t.first == "relay") && t.count >= 2 {
                relays.insert(t[1])
            }
        }

        // 2) Fallback to NIP-65 relay list (kind 10002)
        if relays.isEmpty {
            let rFilter = NostrFilter(ids: nil, authors: memberPubkeys, kinds: [NostrKind.relayList], since: nil, until: nil, limit: memberPubkeys.count * 2, tags: nil, search: nil)
            let rEvents = await fetchEvents(filters: [rFilter], timeoutSeconds: 4.0)
            for ev in rEvents {
                for t in ev.tags where (t.first == "r" || t.first == "relay") && t.count >= 2 {
                    relays.insert(t[1])
                }
            }
        }

        let canonical = canonicalRelayUrls(Array(relays))
        AppLogger.log("MLS", "resolveInboxRelaysForMembers: members=\(memberPubkeys.count) resolved=\(canonical.count) relays=\(canonical.count)")
        return canonical
    }

    /// Collect kind-445 events for one group from app relay pool + group-specific relays + member inbox relays.
    /// Returns time-ascending list.
    private func collectGroupMessageEvents(groupIdHex: String, ffi: MlsFFIBridge, since: Int64? = nil) async -> [NostrEvent] {
        let hFilter = NostrFilter(
            ids: nil,
            authors: nil,
            kinds: [NostrKind.mlsGroupMessage],
            since: since,
            until: nil,
            limit: 150,
            tags: ["#h": [groupIdHex]],
            search: nil
        )
        let broadFilter = NostrFilter(
            ids: nil,
            authors: nil,
            kinds: [NostrKind.mlsGroupMessage],
            since: since,
            until: nil,
            limit: 300,
            tags: nil,
            search: nil
        )

        // 1) App-managed relay pool (#h)
        var mergedById = Dictionary(uniqueKeysWithValues: await fetchEvents(filters: [hFilter], timeoutSeconds: 5.0).map { ($0.id, $0) })

        // 2) Group-specific relays + member inbox relays + global fallback relays
        var resolvedRelayCount = 0
        if let gi = try? ffi.mlsGetGroupInfo(groupIdHex: groupIdHex) {
            let inboxRelays = await resolveInboxRelaysForMembers(gi.memberPubkeys)
            var allRelays = mlsRelayUrls(gi.relays + inboxRelays)

            // hostname normalization for wirednet variants
            if allRelays.contains(canonicalRelayUrl("wss://relay.nostr.wirednet.jp"))
                && !allRelays.contains(canonicalRelayUrl("wss://relay-jp.nostr.wirednet.jp")) {
                allRelays.append(canonicalRelayUrl("wss://relay-jp.nostr.wirednet.jp"))
            }
            if allRelays.contains(canonicalRelayUrl("wss://relay-jp.nostr.wirednet.jp"))
                && !allRelays.contains(canonicalRelayUrl("wss://relay.nostr.wirednet.jp")) {
                allRelays.append(canonicalRelayUrl("wss://relay.nostr.wirednet.jp"))
            }

            await ensureGroupRelaysConnected(allRelays)
            resolvedRelayCount = allRelays.count

            // pass A: #h query
            for relay in allRelays.prefix(20) {
                let evs = await client.fetchEventsFromRelay(relay, filters: [hFilter], timeoutSeconds: 4.0)
                for ev in evs { mergedById[ev.id] = ev }
            }

            // pass B: broad query + local h-match
            // Some relays/bridges don't reliably return #h-tag filtered results.
            // Always do a broad supplement to reduce missing-commit gaps (state_not_ready).
            let normalized = groupIdHex.lowercased()
            for relay in allRelays.prefix(20) {
                let evs = await client.fetchEventsFromRelay(relay, filters: [broadFilter], timeoutSeconds: 4.0)
                for ev in evs where (ev.getTagValue("h") ?? "").lowercased() == normalized {
                    mergedById[ev.id] = ev
                }
            }

            AppLogger.log("MLS", "collectGroupMessageEvents: groupRelays=\(gi.relays.count) inboxRelays=\(inboxRelays.count) interopRelays=\(mlsInteropRelayUrls.count) queried=\(allRelays.count) total=\(mergedById.count)")
        }

        // 3) App-pool broad supplement as final fallback
        let normalized = groupIdHex.lowercased()
        let broadEvents = await fetchEvents(filters: [broadFilter], timeoutSeconds: 5.0)
        for ev in broadEvents where (ev.getTagValue("h") ?? "").lowercased() == normalized {
            mergedById[ev.id] = ev
        }

        AppLogger.log("MLS", "collectGroupMessageEvents: broadPool=\(broadEvents.count) matched=\(mergedById.count) group=\(groupIdHex) relays=\(resolvedRelayCount)")

        return Array(mergedById.values).sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            return lhs.id < rhs.id
        }
    }

    // MARK: - Relay URL Normalization

    /// Canonicalize relay URLs to reduce duplicates such as `wss://yabu.me` and `wss://yabu.me/`.
    private func canonicalRelayUrls(_ urls: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for raw in urls {
            let normalized = canonicalRelayUrl(raw)
            guard !normalized.isEmpty else { continue }
            if seen.insert(normalized).inserted {
                out.append(normalized)
            }
        }
        return out
    }

    /// Migration guard for legacy KeyPackage publish (kind:443).
    /// Enabled strictly until 2026-05-01T00:00:00Z.
    private func shouldDualPublishLegacy443(now: Date = Date()) -> Bool {
        var comp = DateComponents()
        comp.calendar = Calendar(identifier: .gregorian)
        comp.timeZone = TimeZone(secondsFromGMT: 0)
        comp.year = 2026
        comp.month = 5
        comp.day = 1
        comp.hour = 0
        comp.minute = 0
        comp.second = 0
        guard let cutoff = comp.date else { return false }
        return now < cutoff
    }

    private func canonicalRelayUrl(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var comp = URLComponents(string: trimmed) else { return "" }
        comp.scheme = comp.scheme?.lowercased()
        comp.host = comp.host?.lowercased()
        // Root path is normalized away so both host and host/ are treated as same relay.
        if comp.path == "/" { comp.path = "" }
        if comp.path.isEmpty {
            // keep as scheme://host[:port] without trailing slash
            let portPart = comp.port.map { ":\($0)" } ?? ""
            let scheme = comp.scheme ?? "wss"
            let host = comp.host ?? ""
            if host.isEmpty { return "" }
            return "\(scheme)://\(host)\(portPart)"
        }
        return comp.string ?? trimmed
    }


    // MARK: - MLS Retry Drain (foreground-first)

    /// Foreground-first retry drain for Marmot self-update / KeyPackage rotation / message retry.
    /// BGAppRefreshTask is intentionally not registered here; iOS background execution is
    /// best-effort and should be evaluated only after this foreground drain is stable.
    func drainMlsRetryQueue(trigger: String, maxItems: Int = 4) async {
        guard let account = prefs.publicKeyHex, !account.isEmpty else { return }
        guard let ffi = ensureMlsClient() else { return }

        let summary = mlsRetryStore.summary(accountPubkey: account)
        guard summary.queued > 0 else { return }

        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        var items = mlsRetryStore.dueItems(accountPubkey: account, limit: maxItems)
        if lowPower {
            // Low Power Mode: avoid proactive crypto except user-visible message retry.
            items = items.filter { $0.queueType == .message }
        }
        guard !items.isEmpty else { return }

        AppLogger.log("MLS", "retry drain start trigger=\(trigger) queued=\(summary.queued) due=\(items.count) lowPower=\(lowPower)")

        for item in items {
            switch item.queueType {
            case .selfUpdate:
                await drainSelfUpdateRetry(item, ffi: ffi, trigger: trigger)
            case .keyPackageRotation:
                await drainKeyPackageRotationRetry(item, ffi: ffi, trigger: trigger)
            case .message:
                await drainMessageRetry(item, trigger: trigger)
            }
        }
    }

    private func drainSelfUpdateRetry(_ item: MlsRetryQueueItem, ffi: MlsFFIBridge, trigger: String) async {
        guard let groupIdHex = item.groupIdHex, !groupIdHex.isEmpty else {
            mlsRetryStore.markTerminal(itemId: item.id, reason: "missing_group_id")
            return
        }
        do {
            let gi = try ffi.mlsGetGroupInfo(groupIdHex: groupIdHex)
            try await publishAndMergeSelfUpdateCommit(
                groupIdHex: groupIdHex,
                memberPubkeys: gi.memberPubkeys,
                relays: gi.relays,
                ffi: ffi,
                context: "retryDrain/\(trigger)"
            )
            mlsRetryStore.markSucceeded(itemId: item.id)
            AppLogger.log("MLS", "retry drain self-update success group=\(groupIdHex)")
        } catch {
            let kind = classifyMlsRetryError(error)
            if isTerminalMlsRetry(kind) {
                mlsRetryStore.markTerminal(itemId: item.id, reason: kind.rawValue)
            } else {
                mlsRetryStore.markFailed(itemId: item.id, relayUrls: item.relayUrls, errorKind: kind, foreground: true)
            }
            AppLogger.log("MLS", "retry drain self-update failed group=\(groupIdHex) err=\(mlsRedactedError(error))")
        }
    }

    private func drainMessageRetry(_ item: MlsRetryQueueItem, trigger: String) async {
        guard let signedEventJSON = item.signedEventJSON, !signedEventJSON.isEmpty else {
            mlsRetryStore.markTerminal(itemId: item.id, reason: "missing_signed_event_json")
            return
        }
        let relays = mlsRetryStore.availableRelays(for: item)
        guard !relays.isEmpty else {
            mlsRetryStore.markFailed(itemId: item.id, relayUrls: item.relayUrls, errorKind: .notConnected, foreground: true)
            return
        }
        do {
            await client.connect(relayUrls: relays)
            try await client.publishRawEventJSON(signedEventJSON, to: relays)
            mlsRetryStore.markSucceeded(itemId: item.id)
            AppLogger.log("MLS", "retry drain message success event=\(item.eventId ?? "") group=\(item.groupIdHex ?? "") relays=\(relays.count)")
        } catch {
            let kind = classifyMlsRetryError(error)
            if isTerminalMlsRetry(kind) {
                mlsRetryStore.markTerminal(itemId: item.id, reason: kind.rawValue)
            } else {
                mlsRetryStore.markFailed(itemId: item.id, relayUrls: relays, errorKind: kind, foreground: true)
            }
            AppLogger.log("MLS", "retry drain message failed event=\(item.eventId ?? "") err=\(mlsRedactedError(error))")
        }
    }

    private func drainKeyPackageRotationRetry(_ item: MlsRetryQueueItem, ffi: MlsFFIBridge, trigger: String) async {
        guard let account = prefs.publicKeyHex, !account.isEmpty else { return }
        let owner = item.keyPackageOwnerPubkey ?? account
        guard owner == account else {
            // iOS can only rotate the current account's KeyPackage. A different owner
            // would imply using somebody else's private init key, so classify terminal.
            mlsRetryStore.markTerminal(itemId: item.id, reason: "owner_not_current_account")
            AppLogger.log("MLS", "retry drain keypackage terminal owner_not_current_account owner=\(mlsLogPrefix(owner))")
            return
        }

        do {
            try await publishReplacementKeyPackageForRetry(item: item, ffi: ffi)
            mlsRetryStore.markSucceeded(itemId: item.id)
            AppLogger.log("MLS", "retry drain keypackage success owner=\(mlsLogPrefix(owner)) consumed=\(item.keyPackageEventId ?? "")")
        } catch {
            let kind = classifyMlsRetryError(error)
            if isTerminalMlsRetry(kind) {
                mlsRetryStore.markTerminal(itemId: item.id, reason: kind.rawValue)
            } else {
                mlsRetryStore.markFailed(itemId: item.id, relayUrls: item.relayUrls, errorKind: kind, foreground: true)
            }
            AppLogger.log("MLS", "retry drain keypackage failed owner=\(mlsLogPrefix(owner)) err=\(mlsRedactedError(error))")
        }
    }

    private func publishReplacementKeyPackageForRetry(item: MlsRetryQueueItem, ffi: MlsFFIBridge) async throws {
        let kpData = try ffi.mlsCreateKeyPackage()
        let relayUrls = canonicalRelayUrls((item.relayUrls.isEmpty ? Array(prefs.selectedRelays.prefix(3)) : item.relayUrls) + ["wss://relay.damus.io", "wss://nos.lol"])
        var tags30443 = kpData.tags.map { t -> [String] in t.first == "relays" ? ["relays"] + relayUrls : t }
        if !tags30443.contains(where: { $0.first == "relays" }) { tags30443.append(["relays"] + relayUrls) }

        if let consumedId = item.keyPackageEventId,
           let consumedJSON = prefs.mlsKeyPackageEventJsonById[consumedId],
           extractKind(from: consumedJSON) == NostrKind.mlsKeyPackage,
           let d = extractTagValue(from: consumedJSON, tag: "d"), !d.isEmpty {
            tags30443.removeAll { $0.first == "d" }
            tags30443.insert(["d", d], at: 0)
        } else if !kpData.dTag.isEmpty {
            tags30443.removeAll { $0.first == "d" }
            tags30443.insert(["d", kpData.dTag], at: 0)
        }

        let signed30443 = try await publishEventAndReturnSigned(kind: Int(kpData.kind), tags: tags30443, content: kpData.content)
        if let json30443 = encodeEventJSON(signed30443) {
            var map = prefs.mlsKeyPackageEventJsonById
            map[signed30443.id] = json30443
            prefs.mlsKeyPackageEventJsonById = map
        }

        let kpRelayTags = relayUrls.map { ["relay", $0] }
        try await publishEvent(kind: NostrKind.mlsKeyPackageRelays, tags: kpRelayTags, content: "")
        let dmRelayTags = relayUrls.map { ["r", $0] }
        try await publishEvent(kind: NostrKind.dmRelayList, tags: dmRelayTags, content: "")

        if let consumedId = item.keyPackageEventId {
            await publishConsumedKeyPackageDeleteBestEffort(eventId: consumedId)
            if let consumedJSON = prefs.mlsKeyPackageEventJsonById[consumedId] {
                try? ffi.mlsDeleteConsumedKeyPackageFromEventJSON(eventJSON: consumedJSON)
            }
        }
        keyPackagePublished = true
    }

    private func classifyMlsRetryError(_ error: Error) -> MlsRetryLastErrorKind {
        let raw = String(describing: error).lowercased()
        if raw.contains("invalid") || raw.contains("malformed") || raw.contains("missing_h_tag") || raw.contains("group_id_mismatch") {
            return .invalidPayload
        }
        if raw.contains("notconnected") || raw.contains("not connected") { return .notConnected }
        if raw.contains("rate") || raw.contains("too many") { return .rateLimited }
        if raw.contains("auth") { return .authRequired }
        if raw.contains("reject") || raw.contains("blocked") || raw.contains("policy") { return .relayRejected }
        if raw.contains("keynotunlocked") || raw.contains("secret key is not unlocked") || raw.contains("signing") { return .signingKeyMissing }
        if raw.contains("group not") || raw.contains("left group") || raw.contains("deleted") { return .groupUnavailable }
        return .transientNetwork
    }

    private func isTerminalMlsRetry(_ kind: MlsRetryLastErrorKind) -> Bool {
        switch kind {
        case .invalidPayload, .signingKeyMissing, .groupUnavailable:
            return true
        case .transientNetwork, .relayRejected, .rateLimited, .authRequired, .notConnected, .unknown:
            return false
        }
    }

    // MARK: - Fallbacks

    private func makeFallbackDmGroup(partner: String, me: String) -> MlsGroup {
        MlsGroup(
            groupIdHex: String([me, partner].sorted().joined().prefix(64)),
            name: "", description: "", adminPubkeys: [me],
            memberPubkeys: [me, partner], relays: prefs.selectedRelays,
            createdAt: Int64(Date().timeIntervalSince1970), epoch: 0,
            disappearingMessageSecs: nil,
            isDm: true
        )
    }

    private func makeFallbackGroupChat(name: String, members: [String], me: String) -> MlsGroup {
        var allMembers = members
        if !allMembers.contains(me) { allMembers.insert(me, at: 0) }
        return MlsGroup(
            groupIdHex: UUID().uuidString.replacingOccurrences(of: "-", with: ""),
            name: name, description: "", adminPubkeys: [me],
            memberPubkeys: allMembers, relays: prefs.selectedRelays,
            createdAt: Int64(Date().timeIntervalSince1970), epoch: 0,
            disappearingMessageSecs: nil,
            isDm: false
        )
    }

    // MARK: - JSON Helpers

    private func encodeEventJSON(_ event: NostrEvent) -> String? {
        guard let data = try? JSONEncoder().encode(event) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func decodeEventJSON(_ json: String) -> NostrEvent? {
        try? JSONDecoder().decode(NostrEvent.self, from: Data(json.utf8))
    }

    private func isNonRetryableMlsUnprocessable(_ kind: String) -> Bool {
        guard kind.hasPrefix("unhandled:Unprocessable") else { return false }
        return kind.hasSuffix(":missing_h_tag")
            || kind.hasSuffix(":group_id_mismatch")
            || kind.hasSuffix(":invalid_kind")
    }

    private func invalidMlsOuterPayloadReason(_ content: String) -> String? {
        guard let decoded = Data(base64Encoded: content) else {
            return "invalid_base64"
        }
        if decoded.count < 28 {
            return "too_short_\(decoded.count)"
        }
        return nil
    }

    private func mergeHistoryAndLive(history: [FfiDecryptedMessage], live: [FfiDecryptedMessage]) -> [FfiDecryptedMessage] {
        if live.isEmpty { return history }
        var seen = Set(history.map { "\($0.senderPubkey)-\($0.timestamp)-\($0.content)" })
        var out = history
        for m in live {
            let k = "\(m.senderPubkey)-\(m.timestamp)-\(m.content)"
            if !seen.contains(k) {
                seen.insert(k)
                out.append(m)
            }
        }
        return out.sorted { $0.timestamp < $1.timestamp }
    }

    private func extractEventId(from json: String) -> String? {
        (try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])?["id"] as? String
    }

    private func extractPubkey(from json: String) -> String? {
        (try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])?["pubkey"] as? String
    }

    private func extractKind(from json: String) -> Int? {
        (try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])?["kind"] as? Int
    }

    private func extractTagValue(from json: String, tag: String) -> String? {
        guard let obj  = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let tags = obj["tags"] as? [[Any]] else { return nil }
        return tags.first { ($0.first as? String) == tag && $0.count > 1 }?
            .dropFirst().first as? String
    }

    /// Stable message ID for SwiftUI diffing.
    /// Avoids index-based IDs that change on every re-fetch.
    private func stableMessageId(groupIdHex: String, senderPubkey: String, timestamp: Int64, content: String) -> String {
        let normalized = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let raw = "\(groupIdHex)|\(senderPubkey)|\(timestamp)|\(normalized)"
        // FNV-1a 64-bit (deterministic, no extra framework dependency)
        var hash: UInt64 = 0xcbf29ce484222325
        for b in raw.utf8 {
            hash ^= UInt64(b)
            hash = hash &* 0x100000001b3
        }
        return String(format: "mls_%016llx", hash)
    }
}

// MARK: - MLS Errors

enum MlsError: LocalizedError {
    case keyPackageNotFound
    case groupNotFound
    case notAdmin
    case selfRemoveFailed
    case noFfiClient
    case invalidPayload
    case invalidDisappearingMessageDuration
    case groupStateStuck
    case invalidWelcomeKind
    case invalidWelcomeEncoding
    case invalidWelcomeMissingKeyPackageRef
    case invalidWelcomeRelays

    var errorDescription: String? {
        switch self {
        case .keyPackageNotFound: return "相手のキーパッケージが見つかりません"
        case .groupNotFound:      return "グループが見つかりません"
        case .notAdmin:           return "管理者のみがこの操作を実行できます"
        case .selfRemoveFailed:   return "グループの退出に失敗しました"
        case .noFfiClient:        return "MLS エンジンが初期化されていません"
        case .invalidPayload:     return "MLS イベント形式が不正です"
        case .invalidDisappearingMessageDuration: return "消えるメッセージの有効期限が不正です"
        case .groupStateStuck:    return "グループ状態が破損しています（再作成が必要）"
        case .invalidWelcomeKind: return "Welcomeイベント種別が不正です"
        case .invalidWelcomeEncoding: return "Welcomeイベントのエンコード形式が不正です（base64必須）"
        case .invalidWelcomeMissingKeyPackageRef: return "WelcomeイベントにKeyPackage参照(eタグ)がありません"
        case .invalidWelcomeRelays: return "Welcomeイベントに有効なrelaysタグがありません"
        }
    }
}