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
        await repository.drainMlsRetryQueue(trigger: "talkLoadGroups", maxItems: 3)
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

    /// 同一相手との DM グループが複数ある場合、一覧上は1件に折りたたむ。
    ///
    /// 注意: ここでは Rust/MDK history を async に読めないため、lastMessageTime だけで
    /// 「送信すべき group」を確定しない。実際の active/send group は openGroup() で
    /// sibling DM の復号済み履歴を見て partner-message aware に再選択する。
    private func collapseDuplicateDmGroups(_ input: [MlsGroup]) -> [MlsGroup] {
        var keepByPartner: [String: MlsGroup] = [:]
        var duplicateCounts: [String: Int] = [:]
        var nonDm: [MlsGroup] = []

        for g in input {
            guard g.isDm else {
                nonDm.append(g)
                continue
            }
            guard let partner = g.memberPubkeys.first(where: { $0 != myPubkeyHex }) else {
                nonDm.append(g)
                continue
            }

            duplicateCounts[partner, default: 0] += 1
            if let old = keepByPartner[partner] {
                if g.lastMessageTime > old.lastMessageTime {
                    keepByPartner[partner] = g
                }
            } else {
                keepByPartner[partner] = g
            }
        }

        for (partner, count) in duplicateCounts where count > 1 {
            let selected = keepByPartner[partner]?.groupIdHex ?? ""
            AppLogger.log("MLS", "TalkVM.collapseDuplicateDmGroups: partner=\(String(partner.prefix(8)))… duplicates=\(count) displayGroup=\(selected) selection=provisional")
        }

        let dmCollapsed = Array(keepByPartner.values)
        return (dmCollapsed + nonDm).sorted { $0.lastMessageTime > $1.lastMessageTime }
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
        await repository.drainMlsRetryQueue(trigger: "talkOpenGroup", maxItems: 3)
        // 以前は stuckGroupIds で開封を拒否していたが、
        // 回復可能性を残すため開封自体は許可する。
        guard let group = groups.first(where: { $0.groupIdHex == groupIdHex }) else {
            openingGroupInFlight = false
            AppLogger.log("MLS", "TalkVM.openGroup: group not found in local list")
            return
        }

        // First phase must be quick: open the tapped/collapsed group so the Talk screen
        // can start. The heavier duplicate-DM sibling scan is bounded below and never
        // scans all historical duplicate groups sequentially.
        messagesLoading = true
        activeGroup = group
        var finalGroup = group
        var pollingGroupId = groupIdHex

        do {
            var msgs = try await withTimeout(seconds: 10.0) {
                try await self.repository.fetchMlsMessages(groupIdHex: groupIdHex)
            }

            // DM重複移行期 / WhiteNoise interop:
            // 同一相手との DM が複数ある場合、collapse された表示用 group と
            // WhiteNoise が実際に kind445 を送っている Nostr group id がズレることがある。
            // ただし全 sibling を逐次 fetch すると openGroup が終わらずトーク開始不能になるため、
            // lastMessageTime 上位だけを短い timeout 付きで調査する。
            if group.isDm {
                let fetchedAll = (try? await repository.fetchMlsGroups(myPubkeyHex: myPubkeyHex)) ?? []
                let partner = group.memberPubkeys.first(where: { $0 != myPubkeyHex })
                let siblingGroupsAll = fetchedAll.filter { candidate in
                    guard candidate.isDm, candidate.groupIdHex != groupIdHex else { return false }
                    guard let partner else { return false }
                    return candidate.memberPubkeys.contains(partner)
                }.sorted { lhs, rhs in
                    if lhs.lastMessageTime != rhs.lastMessageTime { return lhs.lastMessageTime > rhs.lastMessageTime }
                    return lhs.groupIdHex < rhs.groupIdHex
                }
                let maxSiblingScan = 6
                let siblingGroups = Array(siblingGroupsAll.prefix(maxSiblingScan))
                let partnerShort = partner.map { String($0.prefix(8)) + "…" } ?? ""
                let siblingIds = siblingGroups.map { $0.groupIdHex }.joined(separator: ",")
                AppLogger.log("MLS", "TalkVM.openGroup: DM sibling candidates current=\(groupIdHex) partner=\(partnerShort) total=\(siblingGroupsAll.count) scanned=\(siblingGroups.count) siblings=\(siblingIds)")

                var allMessagesByGroup: [(group: MlsGroup, messages: [MlsMessage], fetchOk: Bool)] = [(group, msgs, true)]
                for sibling in siblingGroups {
                    do {
                        let alt = try await withTimeout(seconds: 4.0) {
                            try await self.repository.fetchMlsMessages(groupIdHex: sibling.groupIdHex)
                        }
                        allMessagesByGroup.append((sibling, alt, true))
                    } catch {
                        allMessagesByGroup.append((sibling, [], false))
                        let fetchError = normalizeMlsError(error, fallback: "fetch_failed")
                        AppLogger.log("MLS", "TalkVM.openGroup: DM sibling fetch failed group=\(sibling.groupIdHex) err=\(fetchError)")
                    }
                }

                struct DmSiblingScore {
                    let historyCount: Int
                    let partnerCount: Int
                    let myCount: Int
                    let latestPartnerTs: Int64
                    let latestAnyTs: Int64
                    let groupTs: Int64
                    let fetchOk: Bool
                }

                func score(_ entry: (group: MlsGroup, messages: [MlsMessage], fetchOk: Bool)) -> DmSiblingScore {
                    let partnerMsgs = entry.messages.filter { $0.senderPubkey != myPubkeyHex }
                    let myMsgs = entry.messages.filter { $0.senderPubkey == myPubkeyHex }
                    return DmSiblingScore(
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
                    let marker = entry.group.groupIdHex == groupIdHex ? "current" : "sibling"
                    AppLogger.log("MLS", "TalkVM.openGroup: DM sibling stats role=\(marker) group=\(entry.group.groupIdHex) fetchOk=\(s.fetchOk) history=\(s.historyCount) partnerMessages=\(s.partnerCount) myMessages=\(s.myCount) latestPartnerTs=\(s.latestPartnerTs) latestAnyTs=\(s.latestAnyTs) lastMessageTime=\(s.groupTs) retryable=unavailable")
                }

                if let best = allMessagesByGroup.max(by: { lhs, rhs in
                    let l = score(lhs)
                    let r = score(rhs)
                    if (l.partnerCount > 0) != (r.partnerCount > 0) { return l.partnerCount == 0 && r.partnerCount > 0 }
                    if l.latestPartnerTs != r.latestPartnerTs { return l.latestPartnerTs < r.latestPartnerTs }
                    if l.historyCount != r.historyCount { return l.historyCount < r.historyCount }
                    if l.latestAnyTs != r.latestAnyTs { return l.latestAnyTs < r.latestAnyTs }
                    return l.groupTs < r.groupTs
                }) {
                    let bestScore = score(best)
                    if best.group.groupIdHex != groupIdHex, bestScore.partnerCount > 0 {
                        finalGroup = best.group
                        pollingGroupId = best.group.groupIdHex
                        AppLogger.log("MLS", "TalkVM.openGroup: remapped active DM to sibling current=\(groupIdHex) selected=\(best.group.groupIdHex) partnerMessages=\(bestScore.partnerCount) myMessages=\(bestScore.myCount) partnerTs=\(bestScore.latestPartnerTs) anyTs=\(bestScore.latestAnyTs)")
                    } else {
                        let keepReason = bestScore.partnerCount > 0 ? "current_has_partner_messages" : "no_decryptable_partner_sibling"
                        AppLogger.log("MLS", "TalkVM.openGroup: kept active DM group=\(groupIdHex) partnerMessages=\(bestScore.partnerCount) myMessages=\(bestScore.myCount) partnerTs=\(bestScore.latestPartnerTs) anyTs=\(bestScore.latestAnyTs) reason=\(keepReason)")
                    }
                }

                var merged: [MlsMessage] = []
                for entry in allMessagesByGroup { merged.append(contentsOf: entry.messages) }
                if allMessagesByGroup.count > 1 {
                    var byId: [String: MlsMessage] = [:]
                    for m in merged { byId[m.id] = m }
                    msgs = Array(byId.values).sorted { lhs, rhs in
                        if lhs.timestamp == rhs.timestamp { return lhs.id < rhs.id }
                        return lhs.timestamp < rhs.timestamp
                    }
                    AppLogger.log("MLS", "TalkVM.openGroup: merged sibling DM histories groups=\(allMessagesByGroup.count) merged=\(msgs.count) sendGroup=\(pollingGroupId)")
                }
            }

            activeGroup = finalGroup
            messages = msgs
            error = nil
            AppLogger.log("MLS", "TalkVM.openGroup success: messages=\(msgs.count) active=\(finalGroup.groupIdHex)")
            messagesLoading = false
            openingGroupInFlight = false
            startPolling(groupIdHex: pollingGroupId)
        } catch {
            AppLogger.log("MLS", "TalkVM.openGroup error: \(error)")
            messagesLoading = false
            openingGroupInFlight = false

            // Keep the selected group open even if initial fetch times out, so Talk can start.
            activeGroup = group
            messages = []
            startPolling(groupIdHex: groupIdHex)

            // Same recovery UX as sendMessage(): if this DM is stuck, recreate to a fresh group.
            if let mlsErr = error as? MlsError,
               case .groupStateStuck = mlsErr,
               group.isDm {
                // 非fatal化: 旧グループを閉じずに表示継続し、次ポーリングでの回復を待つ。
                self.error = "同期中です。しばらく待って再読込してください"
            } else if let te = error as? TalkTimeoutError, te == .timedOut {
                self.error = "読み込みに時間がかかっています。バックグラウンドで同期を続けます"
            } else {
                setNormalizedError(error, fallback: "メッセージの読み込みに失敗しました", context: "openGroup")
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

    /// アクティブグループのメッセージを 10 秒ごとにポーリング。
    /// Android: LaunchedEffect + collect flow に対応。
    private func startPolling(groupIdHex: String) {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000) // 10s
                guard !Task.isCancelled, let self else { break }
                guard self.activeGroup?.groupIdHex == groupIdHex else { break }
                await self.repository.drainMlsRetryQueue(trigger: "talkPolling", maxItems: 2)
                if let msgs = try? await self.repository.fetchMlsMessages(groupIdHex: groupIdHex),
                   self.shouldReplaceMessages(current: self.messages, incoming: msgs) {
                    self.messages = msgs
                }
            }
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
        guard !openingGroupInFlight, !messagesLoading else {
            AppLogger.log("MLS", "TalkVM.sendMessage: blocked while opening group opening=\(openingGroupInFlight) messagesLoading=\(messagesLoading)")
            self.error = "トークを同期中です。読み込み完了後に送信してください"
            return
        }
        guard let group = activeGroup, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            AppLogger.log("MLS", "TalkVM.sendMessage: skipped (no active group or empty text)")
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
            if let idx = messages.firstIndex(where: { $0.id == tempId }) {
                messages[idx] = msg
            } else {
                messages.append(msg)
            }
            AppLogger.log("MLS", "TalkVM.sendMessage success")
        } catch {
            // Stop false-positive UX: failed/timed-out send must not remain as sent bubble.
            messages.removeAll { $0.id == tempId }
            AppLogger.log("MLS", "TalkVM.sendMessage error: \(error)")

            if let mlsErr = error as? MlsError,
               case .groupStateStuck = mlsErr,
               group.isDm {
                await recoverStuckDmIfNeeded(group)
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
        guard current.count == incoming.count else { return true }
        for (lhs, rhs) in zip(current, incoming) {
            if lhs.id != rhs.id { return true }
            if lhs.senderPubkey != rhs.senderPubkey { return true }
            if lhs.timestamp != rhs.timestamp { return true }
            if lhs.content != rhs.content { return true }
        }
        return false
    }
}
