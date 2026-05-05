import Foundation

/// ViewModel for TalkView — MLS group list and group chat.
/// Mirrors Android TalkViewModel.kt.
@Observable @MainActor final class TalkViewModel {

    // MARK: - Published State

    var groups:           [MlsGroup]    = []
    var isLoading:        Bool          = false
    var error:            String?       = nil
    var activeGroup:      MlsGroup?     = nil
    var messages:         [MlsMessage]  = []
    var messagesLoading:  Bool          = false
    var sendingMessage:   Bool          = false
    var showGroupInfo:    Bool          = false
    var showCreateGroup:  Bool          = false
    var followingProfiles: [UserProfile] = []
    var followingLoading: Bool          = false
    var stuckGroupIds: Set<String>      = []
    private var autoRecoveredDmGroupIds: Set<String> = []
    private var dmRecoveryInFlight: Bool = false
    private var repairInFlightGroupIds: Set<String> = []

    // MARK: - Private

    private let repository:    NostrRepository
    let myPubkeyHex: String
    private var pollingTask:   Task<Void, Never>?

    private func normalizeMlsError(_ error: Error, fallback: String) -> String {
        if let mls = error as? MlsError, let d = mls.errorDescription, !d.isEmpty {
            return d
        }
        let raw = String(describing: error).lowercased()

        // MDK / FFI string-level normalization (defensive mapping)
        if raw.contains("invalid_base64_content") || raw.contains("invalid base64") {
            return "MLSイベント形式が不正です（base64）"
        }
        if raw.contains("malformed_content_too_short") || raw.contains("too_short") {
            return "MLSイベント形式が不正です（長さ不足）"
        }
        if raw.contains("missing_h_tag") {
            return "MLSイベント形式が不正です（hタグ不足）"
        }
        if raw.contains("group_id_mismatch") {
            return "MLSイベントのグループIDが一致しません"
        }
        if raw.contains("invalid_kind") {
            return "MLSイベント種別が不正です"
        }
        if raw.contains("pending proposal exists") || raw.contains("pending commit exists") {
            return "同期中です。少し待って再試行してください"
        }
        if raw.contains("no ffi client") || raw.contains("ffi unavailable") || raw.contains("mls not initialised") {
            return "MLSエンジンが利用できません"
        }
        if raw.contains("not admin") {
            return "管理者のみがこの操作を実行できます"
        }

        return fallback
    }

    private func setNormalizedError(_ error: Error, fallback: String, context: String) {
        let message = normalizeMlsError(error, fallback: fallback)
        self.error = message
        AppLogger.log("MLS", "TalkVM.\(context) normalizedError=\(message) raw=\(String(describing: error))")
    }

    func isGroupStuck(_ groupIdHex: String) -> Bool {
        stuckGroupIds.contains(groupIdHex)
    }

    // MARK: - Init

    init(repository: NostrRepository, myPubkeyHex: String) {
        self.repository   = repository
        self.myPubkeyHex  = myPubkeyHex
        // Heavy Marmot/MLS relay discovery is intentionally lazy.
        // MainTabView keeps TalkView alive even when the timeline is active, so starting
        // here would connect WhiteNoise/Marmot interop relays during timeline startup.
    }

    // MARK: - Group List

    /// 進行中の loadGroups を防ぐフラグ
    private var loadGroupsInFlight = false

    /// openGroup() が sibling DM selection を完了する前に送信される race を防ぐ。
    private var openingGroupInFlight = false

    func loadGroups() async {
        // 既に実行中なら重複呼び出しを無視
        guard !loadGroupsInFlight else {
            AppLogger.log("MLS", "TalkVM.loadGroups skipped (already in flight)")
            return
        }
        loadGroupsInFlight = true
        defer { loadGroupsInFlight = false }

        AppLogger.log("MLS", "TalkVM.loadGroups start")
        // Foreground Talk load must not be blocked by retry drains. Retry work is
        // handled by polling/background paths with tiny batches.
        isLoading = true
        error     = nil
        do {
            let fetched = try await repository.fetchMlsGroups(myPubkeyHex: myPubkeyHex)
            let filtered = fetched.filter { !stuckGroupIds.contains($0.groupIdHex) }
            let previousGroups = groups
            let collapsed = collapseDuplicateDmGroups(filtered)
            groups = collapsed
            AppLogger.log("MLS", "TalkVM.loadGroups success: groups=\(fetched.count) filtered=\(filtered.count) collapsed=\(collapsed.count)")

            if let active = activeGroup,
               let remapped = remapGroupForCollapsedDm(activeGroupId: active.groupIdHex, previousGroups: previousGroups, in: collapsed) {
                activeGroup = remapped
            }
            isLoading = false
        } catch {
            AppLogger.log("MLS", "TalkVM.loadGroups error: \(error)")
            setNormalizedError(error, fallback: "トークの読み込みに失敗しました", context: "loadGroups")
            isLoading   = false
        }
    }

    // MARK: - Group Dedup (DM)

    /// 同一相手との DM グループが複数ある場合でも、ここでは折りたたまない。
    ///
    /// WhiteNoise interop では「最新に見える self-only/orphan DM」を一覧に残してしまうと、
    /// そこへ送信しても Android 側には表示されない。以前の collapse はまさにこの状態を
    /// 作っていた。DM の正規化は openGroup() で MDK history を読んで行うため、一覧では
    /// 全候補を残して安全側に倒す。
    private func collapseDuplicateDmGroups(_ input: [MlsGroup]) -> [MlsGroup] {
        let grouped = Dictionary(grouping: input.filter { $0.isDm }) { g in
            g.memberPubkeys.first(where: { $0 != myPubkeyHex }) ?? g.groupIdHex
        }
        for (partner, entries) in grouped where entries.count > 1 {
            AppLogger.log("MLS", "TalkVM.collapseDuplicateDmGroups: partner=\(String(partner.prefix(8)))… duplicates=\(entries.count) display=all_no_collapse")
        }
        return input.sorted { $0.lastMessageTime > $1.lastMessageTime }
    }

    /// activeGroup が統合で消えた場合、同一相手の最新DMへマップし直す。
    private func remapGroupForCollapsedDm(activeGroupId: String, previousGroups: [MlsGroup], in groups: [MlsGroup]) -> MlsGroup? {
        guard let previous = previousGroups.first(where: { $0.groupIdHex == activeGroupId }), previous.isDm,
              let partner = previous.memberPubkeys.first(where: { $0 != myPubkeyHex }) else {
            return groups.first(where: { $0.groupIdHex == activeGroupId })
        }
        return groups.first(where: { $0.isDm && $0.memberPubkeys.contains(partner) })
            ?? groups.first(where: { $0.groupIdHex == activeGroupId })
    }

    /// 同一相手の DM groupId を返す（重複移行期フォールバック用）。
    private func siblingDmGroupIds(for group: MlsGroup, from source: [MlsGroup]) -> [String] {
        guard group.isDm, let partner = group.memberPubkeys.first(where: { $0 != myPubkeyHex }) else {
            return []
        }
        return source
            .filter { $0.isDm && $0.memberPubkeys.contains(partner) }
            .map { $0.groupIdHex }
    }

    // MARK: - Group Chat

    func openGroup(_ groupIdHex: String) async {
        guard !openingGroupInFlight else {
            AppLogger.log("MLS", "TalkVM.openGroup skipped (already opening) requested=\(groupIdHex)")
            return
        }
        openingGroupInFlight = true

        AppLogger.log("MLS", "TalkVM.openGroup start: group=\(groupIdHex)")
        // Do not drain retry queue before opening: it serializes on NostrRepository and
        // makes Talk appear frozen. Open local history first, then catch up.
        // 以前は stuckGroupIds で開封を拒否していたが、
        // 回復可能性を残すため開封自体は許可する。
        guard let group = groups.first(where: { $0.groupIdHex == groupIdHex }) else {
            openingGroupInFlight = false
            AppLogger.log("MLS", "TalkVM.openGroup: group not found in local list")
            return
        }

        // First phase must be quick: open the tapped/collapsed group so the Talk screen
        // can start. Sending is allowed while catch-up continues in the background.
        messagesLoading = true
        activeGroup = group
        openingGroupInFlight = false
        startPolling(groupIdHex: groupIdHex)
        var finalGroup = group
        var pollingGroupId = groupIdHex

        do {
            let localMsgs = await repository.getLocalMlsMessages(groupIdHex: groupIdHex)
            if !localMsgs.isEmpty {
                messages = localMsgs
                messagesLoading = false
                AppLogger.log("MLS", "TalkVM.openGroup local-first messages=\(localMsgs.count) group=\(groupIdHex)")
            }

            // Do not block opening on relay/MLS catch-up. The user-visible chat must
            // be local-first and send-capable immediately; catch-up runs in polling.
            var msgs = localMsgs

            // DM重複移行期 / WhiteNoise interop:
            // 同一相手との DM が複数ある場合、表示上の最新 group（自分だけが送った
            // 新規 orphan group）と、WhiteNoise Android が実際に参加している group が
            // ずれることがある。ここがずれると iOS では送信済みに見えても Android には
            // 出ない。開封時は常に local MDK history を見て「相手のメッセージが復号
            // できている group」を送信先として選ぶ。異なる group の履歴は混ぜない。
            if group.isDm {
                let partner = group.memberPubkeys.first(where: { $0 != myPubkeyHex })
                let siblingGroupsAll = groups.filter { candidate in
                    guard candidate.isDm else { return false }
                    guard let partner else { return candidate.groupIdHex == groupIdHex }
                    return candidate.memberPubkeys.contains(partner)
                }.sorted { lhs, rhs in
                    if lhs.lastMessageTime != rhs.lastMessageTime { return lhs.lastMessageTime > rhs.lastMessageTime }
                    return lhs.groupIdHex < rhs.groupIdHex
                }

                let maxSiblingScan = 8
                let siblingGroups = Array(siblingGroupsAll.prefix(maxSiblingScan))
                let partnerShort = partner.map { String($0.prefix(8)) + "…" } ?? ""
                AppLogger.log("MLS", "TalkVM.openGroup: DM canonical scan requested=\(groupIdHex) partner=\(partnerShort) total=\(siblingGroupsAll.count) scanned=\(siblingGroups.count)")

                var allMessagesByGroup: [(group: MlsGroup, messages: [MlsMessage], fetchOk: Bool)] = []
                var seenGroupIds = Set<String>()
                for candidate in ([group] + siblingGroups) where seenGroupIds.insert(candidate.groupIdHex).inserted {
                    do {
                        var local = candidate.groupIdHex == groupIdHex ? msgs : await self.repository.getLocalMlsMessages(groupIdHex: candidate.groupIdHex)
                        // If a DM has no peer message locally, do a real relay/MDK repair pass
                        // before deciding it is an orphan. WhiteNoise often has already sent
                        // the first message (e.g. group_id shown in Android logs) while iOS has
                        // not replayed that kind:445 yet. Choosing based on local-empty history
                        // sends replies to the wrong group. Keep this at 30s: prior
                        // successful WhiteNoise interop logs showed decrypt completing
                        // just after the old 10s timeout, and short timeouts caused UI
                        // failure exactly when MDK history became available.
                        if local.filter({ $0.senderPubkey != myPubkeyHex }).isEmpty {
                            do {
                                local = try await withTimeout(seconds: 30.0) {
                                    try await self.repository.fetchMlsMessages(groupIdHex: candidate.groupIdHex, repairFull: true)
                                }
                                AppLogger.log("MLS", "TalkVM.openGroup: DM canonical repair group=\(candidate.groupIdHex) messages=\(local.count) peer=\(local.filter { $0.senderPubkey != self.myPubkeyHex }.count)")
                            } catch {
                                AppLogger.log("MLS", "TalkVM.openGroup: DM canonical repair failed group=\(candidate.groupIdHex) err=\(self.normalizeMlsError(error, fallback: "repair_failed"))")
                            }
                        }
                        allMessagesByGroup.append((candidate, local, true))
                    } catch {
                        allMessagesByGroup.append((candidate, [], false))
                        let fetchError = normalizeMlsError(error, fallback: "fetch_failed")
                        AppLogger.log("MLS", "TalkVM.openGroup: DM canonical fetch failed group=\(candidate.groupIdHex) err=\(fetchError)")
                    }
                }

                struct DmCanonicalScore {
                    let historyCount: Int
                    let partnerCount: Int
                    let myCount: Int
                    let latestPartnerTs: Int64
                    let latestAnyTs: Int64
                    let groupTs: Int64
                    let fetchOk: Bool
                }

                func score(_ entry: (group: MlsGroup, messages: [MlsMessage], fetchOk: Bool)) -> DmCanonicalScore {
                    let partnerMsgs = entry.messages.filter { $0.senderPubkey != myPubkeyHex }
                    let myMsgs = entry.messages.filter { $0.senderPubkey == myPubkeyHex }
                    return DmCanonicalScore(
                        historyCount: entry.messages.count,
                        partnerCount: partnerMsgs.count,
                        myCount: myMsgs.count,
                        latestPartnerTs: partnerMsgs.map { $0.timestamp }.max() ?? 0,
                        latestAnyTs: entry.messages.map { $0.timestamp }.max() ?? 0,
                        groupTs: entry.group.lastMessageTime,
                        fetchOk: entry.fetchOk
                    )
                }

                for entry in allMessagesByGroup {
                    let s = score(entry)
                    let marker = entry.group.groupIdHex == groupIdHex ? "requested" : "sibling"
                    AppLogger.log("MLS", "TalkVM.openGroup: DM canonical stats role=\(marker) group=\(entry.group.groupIdHex) fetchOk=\(s.fetchOk) history=\(s.historyCount) partnerMessages=\(s.partnerCount) myMessages=\(s.myCount) latestPartnerTs=\(s.latestPartnerTs) latestAnyTs=\(s.latestAnyTs) lastMessageTime=\(s.groupTs)")
                }

                if let best = allMessagesByGroup.max(by: { lhs, rhs in
                    let l = score(lhs)
                    let r = score(rhs)
                    // WhiteNoise interop priority: any group with peer/partner messages wins
                    // over a newer self-only duplicate group, because only the former proves
                    // both clients share the MLS state and group id.
                    if (l.partnerCount > 0) != (r.partnerCount > 0) { return l.partnerCount == 0 && r.partnerCount > 0 }
                    if l.latestPartnerTs != r.latestPartnerTs { return l.latestPartnerTs < r.latestPartnerTs }
                    if l.historyCount != r.historyCount { return l.historyCount < r.historyCount }
                    if l.latestAnyTs != r.latestAnyTs { return l.latestAnyTs < r.latestAnyTs }
                    return l.groupTs < r.groupTs
                }) {
                    let bestScore = score(best)
                    if best.group.groupIdHex != groupIdHex {
                        finalGroup = best.group
                        pollingGroupId = best.group.groupIdHex
                        AppLogger.log("MLS", "TalkVM.openGroup: canonical DM remap requested=\(groupIdHex) selected=\(best.group.groupIdHex) partnerMessages=\(bestScore.partnerCount) myMessages=\(bestScore.myCount) partnerTs=\(bestScore.latestPartnerTs) anyTs=\(bestScore.latestAnyTs)")
                    } else {
                        AppLogger.log("MLS", "TalkVM.openGroup: canonical DM keep group=\(groupIdHex) partnerMessages=\(bestScore.partnerCount) myMessages=\(bestScore.myCount) partnerTs=\(bestScore.latestPartnerTs) anyTs=\(bestScore.latestAnyTs)")
                    }
                    msgs = best.messages
                }
            }

            activeGroup = finalGroup
            messages = dedupeMessages(msgs)
            // Do not surface a timeout/error banner for slow sync. Empty local history is
            // still a valid opened chat; polling will update when MLS catches up.
            error = nil
            AppLogger.log("MLS", "TalkVM.openGroup local-ready: messages=\(msgs.count) active=\(finalGroup.groupIdHex)")
            messagesLoading = false
            startPolling(groupIdHex: pollingGroupId)
        } catch {
            AppLogger.log("MLS", "TalkVM.openGroup error: \(error)")
            messagesLoading = false

            // Keep the selected group open even if local read fails, so Talk can start.
            activeGroup = group
            if messages.isEmpty { messages = [] }
            startPolling(groupIdHex: groupIdHex)

            // Same recovery UX as sendMessage(): if this DM is stuck, recreate to a fresh group.
            if let mlsErr = error as? MlsError,
               case .groupStateStuck = mlsErr,
               group.isDm {
                // 非fatal化: 旧グループを閉じずに表示継続し、次ポーリングでの回復を待つ。
                self.error = "同期中です。しばらく待って再読込してください"
            } else {
                // Opening is local-first. Slow relay sync is intentionally silent.
                AppLogger.log("MLS", "TalkVM.openGroup local-first nonfatal error hidden from UI: \(error)")
            }
        }
    }

    func closeGroup() {
        pollingTask?.cancel()
        pollingTask  = nil
        activeGroup  = nil
        messages     = []
        // NOTE: keep error banner until user explicitly closes it.
    }

    // MARK: - Timeout Helper

    private enum TalkTimeoutError: LocalizedError, Equatable {
        case timedOut
        var errorDescription: String? { "送信がタイムアウトしました" }
    }

    private func withTimeout<T>(seconds: Double, operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: Result<T, Error>.self) { group in
            group.addTask {
                do { return .success(try await operation()) }
                catch { return .failure(error) }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return .failure(TalkTimeoutError.timedOut)
            }

            let first = try await group.next()!
            group.cancelAll()

            switch first {
            case .success(let value): return value
            case .failure(let error): throw error
            }
        }
    }

    // MARK: - Live Polling (10s interval)

    /// アクティブグループのメッセージを 3 秒ごとにポーリング。
    /// Android: LaunchedEffect + collect flow に対応。
    private func startPolling(groupIdHex: String) {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000) // 3s
                guard !Task.isCancelled, let self else { break }
                guard self.activeGroup?.groupIdHex == groupIdHex else { break }
                // Polling should be a light message catch-up only. Retry drains/self-update
                // are not user-visible and must not make Talk feel stuck.
                if let msgs = try? await self.repository.fetchMlsMessages(groupIdHex: groupIdHex) {
                    let normalized = self.dedupeMessages(msgs)
                    if self.shouldReplaceMessages(current: self.messages, incoming: normalized) {
                        self.messages = normalized
                    }
                }
            }
        }
    }


    func repairCurrentGroup() async {
        guard let group = activeGroup else { return }
        repairInFlightGroupIds.insert(group.groupIdHex)
        let repaired = await repository.repairMlsGroupHistory(groupIdHex: group.groupIdHex)
        repairInFlightGroupIds.remove(group.groupIdHex)
        if shouldReplaceMessages(current: messages, incoming: repaired) {
            messages = repaired
        }
        let peerCount = repaired.filter { $0.senderPubkey != myPubkeyHex }.count
        if repaired.count > 0 && peerCount == 0 {
            stuckGroupIds.insert(group.groupIdHex)
            error = "このトークの暗号状態が相手とずれています。旧トークへの送信を止め、新しいトークを作成してください。"
        } else {
            stuckGroupIds.remove(group.groupIdHex)
            error = nil
        }
    }

    private func recoverStuckDmIfNeeded(_ group: MlsGroup) async {
        guard group.isDm else { return }
        guard !dmRecoveryInFlight else { return }
        guard !autoRecoveredDmGroupIds.contains(group.groupIdHex) else { return }
        guard let partner = group.memberPubkeys.first(where: { $0 != myPubkeyHex }) else { return }

        dmRecoveryInFlight = true
        defer { dmRecoveryInFlight = false }

        autoRecoveredDmGroupIds.insert(group.groupIdHex)
        AppLogger.log("MLS", "TalkVM.recoverStuckDmIfNeeded start old=\(group.groupIdHex) partner=\(partner)")

        await repository.hideMlsGroupLocally(groupIdHex: group.groupIdHex)
        let siblings = siblingDmGroupIds(for: group, from: groups).filter { $0 != group.groupIdHex }
        for sid in siblings {
            await repository.hideMlsGroupLocally(groupIdHex: sid)
        }

        groups.removeAll { g in
            guard g.isDm else { return false }
            return g.memberPubkeys.contains(partner)
        }

        do {
            let fresh = try await repository.createMlsDmConversation(partnerPubkeyHex: partner, myPubkeyHex: myPubkeyHex)
            if !groups.contains(where: { $0.groupIdHex == fresh.groupIdHex }) {
                groups.insert(fresh, at: 0)
            }
            activeGroup = fresh
            messages = []
            startPolling(groupIdHex: fresh.groupIdHex)
            self.error = "旧DMの同期不整合を検出したため、新しいトークを作成しました。もう一度送信してください"
            AppLogger.log("MLS", "TalkVM.recoverStuckDmIfNeeded success old=\(group.groupIdHex) new=\(fresh.groupIdHex)")
        } catch {
            self.error = "同期不整合を検出しました。旧DMを退出して新しいトークを作成してください"
            AppLogger.log("MLS", "TalkVM.recoverStuckDmIfNeeded failed old=\(group.groupIdHex) err=\(error)")
        }
    }

    func sendMessage(_ text: String) async {
        // Sending must remain possible during catch-up/sync. sendMlsMessage itself
        // validates whether the local MLS state can create an application message.
        if openingGroupInFlight || messagesLoading {
            AppLogger.log("MLS", "TalkVM.sendMessage: continuing during sync opening=\(openingGroupInFlight) messagesLoading=\(messagesLoading)")
        }
        guard var group = activeGroup, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            AppLogger.log("MLS", "TalkVM.sendMessage: skipped (no active group or empty text)")
            return
        }
        // Last-chance canonicalization: if the currently opened DM has no peer message
        // but sibling DM candidates exist, re-run openGroup's relay-backed selection before
        // creating a new kind:445. This prevents replies from going to iOS-only duplicate DMs.
        if group.isDm,
           messages.filter({ $0.senderPubkey != myPubkeyHex }).isEmpty,
           siblingDmGroupIds(for: group, from: groups).count > 1 {
            AppLogger.log("MLS", "TalkVM.sendMessage: preflight canonicalize DM group=\(group.groupIdHex)")
            await openGroup(group.groupIdHex)
            if let refreshed = activeGroup { group = refreshed }
        }
        if stuckGroupIds.contains(group.groupIdHex) {
            self.error = "このトークは暗号状態がずれているため送信できません。新しいトークを作成してください。"
            AppLogger.log("MLS", "TalkVM.sendMessage blocked stuck group=\(group.groupIdHex)")
            return
        }

        // Critical Marmot interop rule: displaying a peer message does not prove our
        // local send epoch is current. Before creating an outbound kind:9 application
        // message, replay commits/messages for THIS active group so MDK creates the
        // message from the same epoch WhiteNoise Android expects. This is deliberately
        // slow; sending from stale state was the root cause of "iOS shows sent, Android
        // does not display" while peer messages were visible.
        do {
            let caughtUp = try await withTimeout(seconds: 30.0) {
                try await self.repository.fetchMlsMessages(groupIdHex: group.groupIdHex, repairFull: true)
            }
            if shouldReplaceMessages(current: messages, incoming: caughtUp) {
                messages = dedupeMessages(caughtUp)
            }
            AppLogger.log("MLS", "TalkVM.sendMessage preflight catchup ok group=\(group.groupIdHex) messages=\(caughtUp.count) peer=\(caughtUp.filter { $0.senderPubkey != self.myPubkeyHex }.count)")
        } catch {
            AppLogger.log("MLS", "TalkVM.sendMessage preflight catchup failed group=\(group.groupIdHex) err=\(normalizeMlsError(error, fallback: "catchup_failed"))")
            self.error = "同期中です。少し待ってから再送してください"
            return
        }

        AppLogger.log("MLS", "TalkVM.sendMessage start: group=\(group.groupIdHex), len=\(text.count)")
        sendingMessage = true

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let tempId = "local_\(Date().timeIntervalSince1970)_\(UUID().uuidString)"
        let optimistic = MlsMessage(
            id: tempId,
            senderPubkey: myPubkeyHex,
            content: trimmed,
            timestamp: Int64(Date().timeIntervalSince1970),
            groupIdHex: group.groupIdHex
        )
        messages.append(optimistic)

        do {
            let msg = try await withTimeout(seconds: 30.0) {
                try await self.repository.sendMlsMessage(groupIdHex: group.groupIdHex, content: trimmed, myPubkeyHex: self.myPubkeyHex)
            }
            // Replace the optimistic bubble and defensively collapse any duplicate bubble.
            // Use the currently active group id (after canonical DM remap) as the UI group id.
            let uiMsg = MlsMessage(
                id: msg.id,
                senderPubkey: msg.senderPubkey,
                content: msg.content,
                timestamp: msg.timestamp,
                groupIdHex: group.groupIdHex,
                senderProfile: msg.senderProfile
            )
            messages.removeAll { existing in
                existing.id == tempId ||
                (existing.senderPubkey == uiMsg.senderPubkey &&
                 existing.content == uiMsg.content &&
                 abs(existing.timestamp - uiMsg.timestamp) <= 1)
            }
            messages.append(uiMsg)
            messages = dedupeMessages(messages)
            AppLogger.log("MLS", "TalkVM.sendMessage success group=\(group.groupIdHex)")
        } catch {
            // Stop false-positive UX: failed/timed-out send must not remain as sent bubble.
            messages.removeAll { $0.id == tempId }
            AppLogger.log("MLS", "TalkVM.sendMessage error: \(error)")

            if let mlsErr = error as? MlsError,
               case .groupStateStuck = mlsErr,
               group.isDm {
                // Never auto-create a replacement DM. Logs showed this creates a new
                // MLS group that WhiteNoise Android is not watching, so subsequent iOS
                // messages look sent locally but never appear remotely. Keep the shared
                // group and let explicit repair/catch-up resolve state gaps.
                let repaired = await repository.repairMlsGroupHistory(groupIdHex: group.groupIdHex)
                if shouldReplaceMessages(current: messages, incoming: repaired) { messages = repaired }
                self.error = "同期状態を修復しました。もう一度送信してください"
                AppLogger.log("MLS", "TalkVM.sendMessage groupStateStuck repaired_no_autocreate group=\(group.groupIdHex) messages=\(repaired.count)")
            } else if let te = error as? TalkTimeoutError, te == .timedOut {
                self.error = "送信がタイムアウトしました。通信状態を確認して再試行してください"
            } else {
                setNormalizedError(error, fallback: "送信保留中です。接続状態を確認して再試行してください", context: "sendMessage")
            }
        }
        sendingMessage = false
    }

    // MARK: - Group Management

    func showGroupInfoSheet()  { showGroupInfo    = true }
    func hideGroupInfo()       { showGroupInfo    = false }
    func showCreateGroupSheet(){ showCreateGroup  = true }
    func hideCreateGroup()     { showCreateGroup  = false }

    func leaveGroup() async {
        guard let group = activeGroup else { return }

        // まずローカル非表示を確定し、失敗時の再起動復活を防ぐ。
        await repository.hideMlsGroupLocally(groupIdHex: group.groupIdHex)

        // DM重複移行期では sibling も同時に非表示化して既存DM再利用を回避。
        if group.isDm {
            let siblingIds = siblingDmGroupIds(for: group, from: groups).filter { $0 != group.groupIdHex }
            for sid in siblingIds {
                await repository.hideMlsGroupLocally(groupIdHex: sid)
            }
            groups.removeAll { g in g.isDm && g.memberPubkeys.contains(where: { $0 != myPubkeyHex && group.memberPubkeys.contains($0) }) }
        }

        do {
            try await repository.leaveMlsGroup(groupIdHex: group.groupIdHex)
        } catch {
            // 非fatal: ローカルでは退出済み状態を維持する。
            AppLogger.log("MLS", "TalkVM.leaveGroup: leave publish failed (non-fatal): \(error)")
        }

        closeGroup()
        groups.removeAll { $0.groupIdHex == group.groupIdHex }
        showGroupInfo = false
    }

    /// グループにメンバーを追加する（管理者のみ）。
    func addMemberToGroup(groupIdHex: String, memberPubkey: String) async {
        do {
            try await repository.addMemberToGroup(groupIdHex: groupIdHex, memberPubkey: memberPubkey)
            // グループ一覧を更新してメンバーリストを反映
            await loadGroups()
        } catch MlsError.keyPackageNotFound {
            self.error = "相手のキーパッケージが見つかりません"
        } catch MlsError.invalidWelcomeEncoding {
            self.error = "Welcomeイベント形式が不正です（base64必須）"
        } catch MlsError.invalidWelcomeMissingKeyPackageRef {
            self.error = "Welcomeイベントに必要なKeyPackage参照がありません"
        } catch MlsError.invalidWelcomeRelays {
            self.error = "Welcomeイベントのrelay情報が不正です"
        } catch {
            setNormalizedError(error, fallback: "メンバーの追加に失敗しました", context: "addMemberToGroup")
        }
    }

    /// グループからメンバーを削除する（管理者のみ）。
    func removeMemberFromGroup(groupIdHex: String, memberPubkey: String) async {
        do {
            try await repository.removeMemberFromGroup(groupIdHex: groupIdHex, memberPubkey: memberPubkey)
            await loadGroups()
            // activeGroup のメンバーリストも即時更新
            if let idx = groups.firstIndex(where: { $0.groupIdHex == groupIdHex }) {
                activeGroup = groups[idx]
            }
        } catch {
            setNormalizedError(error, fallback: "メンバーの削除に失敗しました", context: "removeMemberFromGroup")
        }
    }

    // MARK: - DM / Group Creation

    func createDmConversation(pubkey: String) async {
        AppLogger.log("MLS", "TalkVM.createDmConversation start partner=\(pubkey)")
        do {
            // Interop safety: republish my latest key package / relay lists before starting DM.
            await repository.forceRepublishMyKeyPackageIfNeeded(myPubkeyHex: myPubkeyHex)
            // グループ未取得なら先にロードして既存DM検索可能にする (Android 同等)
            if groups.isEmpty {
                let fetched = try await repository.fetchMlsGroups(myPubkeyHex: myPubkeyHex)
                groups = fetched
            }
            // 既存の1:1 DMがあればそれを開く — 重複グループ作成を防止
            if let existing = groups.first(where: { $0.isDm && $0.memberPubkeys.contains(pubkey) }) {
                AppLogger.log("MLS", "TalkVM.createDmConversation reuse existing group=\(existing.groupIdHex)")
                await openGroup(existing.groupIdHex)
                return
            }
            // 既存なし → 新規作成
            let group = try await repository.createMlsDmConversation(partnerPubkeyHex: pubkey, myPubkeyHex: myPubkeyHex)
            if !groups.contains(where: { $0.groupIdHex == group.groupIdHex }) {
                groups.insert(group, at: 0)
            }
            AppLogger.log("MLS", "TalkVM.createDmConversation created group=\(group.groupIdHex)")
            await openGroup(group.groupIdHex)
        } catch {
            AppLogger.log("MLS", "TalkVM.createDmConversation failed err=\(error)")
            setNormalizedError(error, fallback: "トークの作成に失敗しました", context: "createDmConversation")
        }
    }

    func createGroupChat(name: String, members: [String]) async {
        hideCreateGroup()
        do {
            let group = try await repository.createMlsGroupChat(name: name, memberPubkeys: members, myPubkeyHex: myPubkeyHex)
            groups.insert(group, at: 0)
            await openGroup(group.groupIdHex)
        } catch {
            setNormalizedError(error, fallback: "グループの作成に失敗しました", context: "createGroupChat")
        }
    }

    // MARK: - Following Profiles (for member picker)

    func loadFollowingProfiles() async {
        guard followingProfiles.isEmpty else { return }
        followingLoading = true
        let follows = await repository.fetchFollowList(pubkey: myPubkeyHex)
        let profiles = await repository.fetchProfiles(pubkeys: follows)
        followingProfiles = profiles
        followingLoading  = false
    }

    // MARK: - Message Diff

    /// Count 増減だけでなく、同件数でも内容・順序・IDが変わったら置き換える。
    private func shouldReplaceMessages(current: [MlsMessage], incoming: [MlsMessage]) -> Bool {
        let normalizedIncoming = dedupeMessages(incoming)
        if normalizedIncoming.count != incoming.count { return true }
        guard current.count == incoming.count else { return true }
        for (lhs, rhs) in zip(current, incoming) {
            if lhs.id != rhs.id { return true }
            if lhs.senderPubkey != rhs.senderPubkey { return true }
            if lhs.timestamp != rhs.timestamp { return true }
            if lhs.content != rhs.content { return true }
        }
        return false
    }

    private func dedupeMessages(_ input: [MlsMessage]) -> [MlsMessage] {
        var byKey: [String: MlsMessage] = [:]
        for m in input {
            // Same sender/content within the same second is the same UI message. This avoids
            // showing both the optimistic/sent bubble and the locally replayed MLS history copy.
            let key = "\(m.groupIdHex)|\(m.senderPubkey)|\(m.timestamp)|\(m.content.trimmingCharacters(in: .whitespacesAndNewlines))"
            byKey[key] = m
        }
        return Array(byKey.values).sorted { lhs, rhs in
            if lhs.timestamp != rhs.timestamp { return lhs.timestamp < rhs.timestamp }
            return lhs.id < rhs.id
        }
    }
}
