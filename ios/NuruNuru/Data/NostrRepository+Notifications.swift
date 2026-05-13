import Foundation

// MARK: - Notifications
// Android 対応ファイル: NostrRepositoryNotifications.kt
// fetchNotifications / fetchEvent / parseBolt11Amount を管理。
//
// 同期済み:
//   ✅ NIP-65 読み取りリレー優先取得
//   ✅ 通知種別フィルタ設定 (notificationEnabledKinds)
//   ✅ 通知キャッシュ (cache.getCachedNotifications / setCachedNotifications)
//   ✅ NIP-05 解決キャッシュ (5分TTL) → NostrRepository+Profiles.swift

extension NostrRepository {

    // MARK: - fetchNotifications

    /// NIP-65 読み取りリレーのURL一覧を返す。
    /// 空なら通常の接続先リレーを使用（Android NIP-65 read relay priority と同等）。
    private func nip65ReadRelayUrls() -> [String] {
        prefs.nip65Relays
            .filter { $0.permission == .read || $0.permission == .readWrite }
            .map(\.url)
    }

    /// ユーザー宛の通知（リアクション・Zap・リポスト・返信/メンション・バッジ付与・フォロー）を取得する。
    /// NIP-65 read リレーを優先的に使用 (Android parity)。
    /// 24時間ウィンドウ、最大 `limit` 件。Android の `fetchNotifications()` に相当。
    func fetchNotifications(pubkey: String, limit: Int = 50) async -> [NotificationItem] {
        let oneDayAgo = Int64(Date().addingTimeInterval(-86400).timeIntervalSince1970)
        let enabledKinds = prefs.notificationEnabledKinds
        let emojiReactionEnabled = prefs.notificationEmojiReactionEnabled
        let allowedSenders = await notificationAllowedSenderSet(for: pubkey)

        func canNotify(sender: String) -> Bool {
            sender != pubkey && (allowedSenders == nil || allowedSenders?.contains(sender) == true)
        }

        // 種別ごとに個別フィルタを作成（Android と同構造）
        let reactionFilter = NostrFilter(
            kinds: [NostrKind.reaction],
            since: oneDayAgo, limit: limit,
            tags: ["#p": [pubkey]]
        )
        let zapFilter = NostrFilter(
            kinds: [NostrKind.zapReceipt],
            since: oneDayAgo, limit: limit,
            tags: ["#p": [pubkey]]
        )
        let repostFilter = NostrFilter(
            kinds: [NostrKind.repost],
            since: oneDayAgo, limit: limit,
            tags: ["#p": [pubkey]]
        )
        let replyFilter = NostrFilter(
            kinds: [NostrKind.textNote],
            since: oneDayAgo, limit: limit,
            tags: ["#p": [pubkey]]
        )
        // Kind 8: バッジ付与 (NIP-58) — Android parity
        let badgeFilter = NostrFilter(
            kinds: [NostrKind.badgeAward],
            since: oneDayAgo, limit: limit,
            tags: ["#p": [pubkey]]
        )
        // Kind 3: フォロー通知 — 「自分を p タグに含む最新のコンタクトリスト更新」を通知
        let followFilter = NostrFilter(
            kinds: [NostrKind.contactList],
            since: oneDayAgo, limit: limit,
            tags: ["#p": [pubkey]]
        )

        // NIP-65 read リレー優先 (Android parity)
        let readRelays = nip65ReadRelayUrls()

        // 全種別を並列取得（NIP-65 read リレーがあればそちらを使用）。設定でOFFの種別はリクエストしない。
        async let reactions: [NostrEvent] = enabledKinds.contains(NostrKind.reaction)
            ? (readRelays.isEmpty ? fetchEvents(filters: [reactionFilter]) : fetchEventsFromReadRelays(readRelays, filters: [reactionFilter]))
            : []
        async let zaps: [NostrEvent] = enabledKinds.contains(NostrKind.zapReceipt)
            ? (readRelays.isEmpty ? fetchEvents(filters: [zapFilter]) : fetchEventsFromReadRelays(readRelays, filters: [zapFilter]))
            : []
        async let reposts: [NostrEvent] = enabledKinds.contains(NostrKind.repost)
            ? (readRelays.isEmpty ? fetchEvents(filters: [repostFilter]) : fetchEventsFromReadRelays(readRelays, filters: [repostFilter]))
            : []
        async let mentions: [NostrEvent] = enabledKinds.contains(NostrKind.textNote)
            ? (readRelays.isEmpty ? fetchEvents(filters: [replyFilter]) : fetchEventsFromReadRelays(readRelays, filters: [replyFilter]))
            : []
        async let badges: [NostrEvent] = enabledKinds.contains(NostrKind.badgeAward)
            ? (readRelays.isEmpty ? fetchEvents(filters: [badgeFilter]) : fetchEventsFromReadRelays(readRelays, filters: [badgeFilter]))
            : []
        async let follows: [NostrEvent] = enabledKinds.contains(NostrKind.contactList)
            ? (readRelays.isEmpty ? fetchEvents(filters: [followFilter]) : fetchEventsFromReadRelays(readRelays, filters: [followFilter]))
            : []

        let (reactionEvents, zapEvents, repostEvents, mentionEvents, badgeEvents, followEvents) =
            await (reactions, zaps, reposts, mentions, badges, follows)

        var items: [NotificationItem] = []

        // MARK: Reactions (Kind 7)
        for event in reactionEvents {
            guard canNotify(sender: event.pubkey) else { continue }
            let content  = event.content.isEmpty ? "+" : event.content
            let emojiTag = event.tags.first { $0.first == "emoji" }
            // "emoji" タグ: ["emoji", <name>, <url>]
            let emojiUrl = emojiTag.flatMap { $0.count >= 3 ? $0[2] : nil }
            let isCustom = emojiUrl != nil ||
                (content.hasPrefix(":") && content.hasSuffix(":") && content.count > 2)

            if isCustom && !emojiReactionEnabled { continue }
            let reactionComment = (content != "+" && content != "-" && !content.isEmpty) ? content : nil
            items.append(NotificationItem(
                id:            event.id,
                pubkey:        event.pubkey,
                type:          isCustom ? "emoji_reaction" : "reaction",
                createdAt:     event.createdAt,
                amount:        nil,
                comment:       reactionComment,
                targetEventId: event.getTagValue("e"),
                emojiUrl:      emojiUrl,
                reactionEmoji: content
            ))
        }

        // MARK: Zaps (Kind 9735)
        for event in zapEvents {
            let targetEvent = event.getTagValue("e")

            // description タグから送信者 pubkey とコメントを解析（Android 同様）
            let descTag   = event.getTagValue("description")
            var zapPubkey = event.pubkey
            var zapComment: String? = nil
            var descAmountMsats: Int64? = nil
            if let desc = descTag,
               let data = desc.data(using: .utf8),
               let obj  = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let sender = obj["pubkey"] as? String { zapPubkey = sender }
                if let c = obj["content"] as? String, !c.isEmpty { zapComment = c }
                // NIP-57: zap request の amount タグ (millisats) をフォールバック用に取得
                if let tags = obj["tags"] as? [[String]] {
                    if let amountTag = tags.first(where: { $0.first == "amount" }),
                       amountTag.count >= 2,
                       let msats = Int64(amountTag[1]) {
                        descAmountMsats = msats
                    }
                }
            }
            guard canNotify(sender: zapPubkey) else { continue }

            let bolt11 = event.getTagValue("bolt11") ?? ""
            // bolt11 優先、パース失敗時は description の amount タグにフォールバック
            let amount = Self.parseBolt11Amount(bolt11) ?? descAmountMsats

            items.append(NotificationItem(
                id:            event.id,
                pubkey:        zapPubkey,
                type:          "zap",
                createdAt:     event.createdAt,
                amount:        amount,
                comment:       zapComment,
                targetEventId: targetEvent,
                emojiUrl:      nil,
                reactionEmoji: nil
            ))
        }

        // MARK: Reposts (Kind 6)
        for event in repostEvents {
            guard canNotify(sender: event.pubkey) else { continue }
            items.append(NotificationItem(
                id:            event.id,
                pubkey:        event.pubkey,
                type:          "repost",
                createdAt:     event.createdAt,
                amount:        nil,
                comment:       nil,
                targetEventId: event.getTagValue("e"),
                emojiUrl:      nil,
                reactionEmoji: nil
            ))
        }

        // MARK: Replies & Mentions (Kind 1)
        for event in mentionEvents {
            guard canNotify(sender: event.pubkey) else { continue }

            let eTags = event.tags.filter { $0.first == "e" }
            let hasReplyMarker = eTags.contains { $0.count >= 4 && $0[3] == "reply" }
            let hasRootMarker  = eTags.contains { $0.count >= 4 && $0[3] == "root" }
            let hasPTagToMe    = event.tags.contains { $0.first == "p" && $0.count >= 2 && $0[1] == pubkey }
            let qTags          = event.tags.filter { $0.first == "q" }
            let hasQuoteTag    = !qTags.isEmpty
            let contentHasQuoteLink = event.content.range(
                of: #"nostr:(?:note1|nevent1)[a-z0-9]{58,}"#,
                options: [.regularExpression, .caseInsensitive]
            ) != nil
            let isQuotePost = hasQuoteTag || contentHasQuoteLink

            // NIP-18 引用投稿は、引用元作者の p タグが付くため #p フィルタに引っかかる。
            // これは「メンションされた」通知ではなく「引用された投稿」の通知として扱う。
            if isQuotePost {
                items.append(NotificationItem(
                    id:            event.id,
                    pubkey:        event.pubkey,
                    type:          "quote",
                    createdAt:     event.createdAt,
                    amount:        nil,
                    comment:       String(removeNostrEventLinksForNotification(event.content).prefix(100)),
                    targetEventId: qTags.first?.dropFirst().first ?? event.getTagValue("e"),
                    emojiUrl:      nil,
                    reactionEmoji: nil
                ))
                continue
            }

            // reply判定: 明示 reply marker / root+私宛p / 旧式 e+p（quote は上で除外済み）
            let isReply = hasReplyMarker
                || (hasRootMarker && hasPTagToMe)
                || (!eTags.isEmpty && hasPTagToMe)

            let mentionComment = isReply ? String(event.content.prefix(100)) : nil
            items.append(NotificationItem(
                id:            event.id,
                pubkey:        event.pubkey,
                type:          isReply ? "reply" : "mention",
                createdAt:     event.createdAt,
                amount:        nil,
                comment:       mentionComment,
                targetEventId: event.getTagValue("e"),
                emojiUrl:      nil,
                reactionEmoji: nil
            ))
        }

        // MARK: Badge Awards (Kind 8, NIP-58)
        for event in badgeEvents {
            guard canNotify(sender: event.pubkey) else { continue }
            // "a" タグ "30009:<pubkey>:<d-tag>" の d-tag 部分をバッジ名として使用
            let aRef = event.tags.first {
                $0.first == "a" && ($0.dropFirst().first?.hasPrefix("30009:") == true)
            }
            let badgeName: String? = aRef.flatMap { tag -> String? in
                guard let ref = tag.dropFirst().first else { return nil }
                let parts = ref.split(separator: ":", maxSplits: 2)
                return parts.count == 3 ? String(parts[2]) : nil
            }
            items.append(NotificationItem(
                id:            event.id,
                pubkey:        event.pubkey,
                type:          "badge",
                createdAt:     event.createdAt,
                amount:        nil,
                comment:       badgeName,
                targetEventId: nil,
                emojiUrl:      nil,
                reactionEmoji: nil
            ))
        }

        // MARK: Follow Events (Kind 3)
        // Kind 3 は「フォロー一覧全体の更新」なので、#p に自分が含まれるだけで通知すると
        // 既存フォロワーが連絡先リストを更新するたびに何度も「フォローしました」になってしまう。
        // 直前の contact list 状態から「未フォロー → フォロー」に変化した時だけ通知する。
        let followItems = await buildFollowNotificationItems(
            followEvents: followEvents,
            pubkey: pubkey,
            windowStart: oneDayAgo,
            canNotify: canNotify
        )
        items.append(contentsOf: followItems)

        return items.sorted { $0.createdAt > $1.createdAt }
    }

    /// Kind 3 contact list 更新から「新規フォロー」だけを通知化する。
    private func buildFollowNotificationItems(
        followEvents: [NostrEvent],
        pubkey: String,
        windowStart: Int64,
        canNotify: (String) -> Bool
    ) async -> [NotificationItem] {
        // canNotify（フォロー中のみ/ネットワーク）で除外した相手も「既存フォロワー」として記録する。
        // 設定変更後に、古い Kind 3 更新が突然「新規フォロー」として出るのを防ぐため。
        let allCandidates = followEvents
            .filter { $0.pubkey != pubkey }
            .filter { $0.tags.contains { $0.first == "p" && $0.dropFirst().first == pubkey } }
            .sorted { $0.createdAt < $1.createdAt }
        guard !allCandidates.isEmpty else { return [] }

        let notifiableCandidates = allCandidates.filter { canNotify($0.pubkey) }
        var knownFollowers = prefs.notificationKnownFollowerPubkeys
        let previousHighWater = prefs.notificationFollowLastSeenAt
        let maxSeenAt = max(previousHighWater, allCandidates.map(\.createdAt).max() ?? previousHighWater)

        // 初回、または過去版で high-water だけ保存され known が空の状態は、まず現存フォロワーをベースライン化する。
        // ここで通知は出さない（既存フォロワーの contact list 更新を重複通知しないため）。
        if previousHighWater == 0 || knownFollowers.isEmpty {
            knownFollowers.formUnion(allCandidates.map(\.pubkey))
            prefs.notificationKnownFollowerPubkeys = knownFollowers
            prefs.notificationFollowLastSeenAt = maxSeenAt
            print("[NotificationFollow] baseline known=\(knownFollowers.count) highWater=\(maxSeenAt) all=\(allCandidates.count) notifiable=\(notifiableCandidates.count) reason=\(previousHighWater == 0 ? "first-run" : "empty-known")")
            return []
        }

        var emittedAuthors = Set<String>()
        var out: [NotificationItem] = []
        for event in allCandidates {
            let wasKnown = knownFollowers.contains(event.pubkey)
            let isNewEvent = event.createdAt > previousHighWater
            if isNewEvent,
               !wasKnown,
               canNotify(event.pubkey),
               emittedAuthors.insert(event.pubkey).inserted {
                out.append(NotificationItem(id: event.id, pubkey: event.pubkey, type: "follow", createdAt: event.createdAt, amount: nil, comment: nil, targetEventId: nil, emojiUrl: nil, reactionEmoji: nil))
            }
            knownFollowers.insert(event.pubkey)
        }
        prefs.notificationKnownFollowerPubkeys = knownFollowers
        prefs.notificationFollowLastSeenAt = maxSeenAt
        print("[NotificationFollow] all=\(allCandidates.count) notifiable=\(notifiableCandidates.count) emitted=\(out.count) known=\(knownFollowers.count) prevHighWater=\(previousHighWater) highWater=\(maxSeenAt)")
        return out
    }

    /// 通知送信者フィルタ用の許可 pubkey セットを返す。nil は全員許可。
    private func notificationAllowedSenderSet(for pubkey: String) async -> Set<String>? {
        switch prefs.notificationSenderScope {
        case .all:
            return nil
        case .following:
            return Set(await fetchFollowList(pubkey: pubkey))
        case .network:
            let follows = await fetchFollowList(pubkey: pubkey)
            var allowed = Set(follows)
            let events = await fetchLatestContactLists(authors: follows)
            for event in events {
                for followed in event.tags where followed.first == "p" {
                    if let pk = followed.dropFirst().first { allowed.insert(pk) }
                }
            }
            return allowed
        }
    }

    /// 指定ユーザー群の最新 Kind 3 をまとめて取得する（ネットワーク通知フィルタ用）。
    private func fetchLatestContactLists(authors: [String], until: Int64? = nil) async -> [NostrEvent] {
        let uniqueAuthors = Array(Set(authors))
        guard !uniqueAuthors.isEmpty else { return [] }
        let filter = NostrFilter(
            authors: uniqueAuthors,
            kinds: [NostrKind.contactList],
            until: until,
            limit: max(uniqueAuthors.count * 3, 100)
        )
        let events = await fetchEvents(filters: [filter], timeoutSeconds: 5.0)
        var latestByAuthor: [String: NostrEvent] = [:]
        for event in events where (latestByAuthor[event.pubkey]?.createdAt ?? 0) < event.createdAt {
            latestByAuthor[event.pubkey] = event
        }
        return Array(latestByAuthor.values)
    }

    // MARK: - NotificationResult

    /// Android `fetchNotifications` の返り値に相当する構造体。
    /// items + profiles + originalPosts をまとめて返す。
    struct NotificationResult {
        let items:         [NotificationItem]
        let profiles:      [String: UserProfile]
        let originalPosts: [String: NostrEvent]
    }

    /// NIP-65 read リレー群からイベントを並列フェッチしてマージする。
    /// Android: NIP-65 read relays → fallback to default client relays と同等。
    private func fetchEventsFromReadRelays(_ relayUrls: [String], filters: [NostrFilter]) async -> [NostrEvent] {
        // 最大3リレーから並列取得してマージ（重複除去）
        let relays = Array(relayUrls.prefix(3))
        var allEvents: [NostrEvent] = []
        var seenIds = Set<String>()

        await withTaskGroup(of: [NostrEvent].self) { group in
            for relay in relays {
                group.addTask {
                    await self.fetchEventsFromRelay(relay, filters: filters, timeoutSeconds: 5.0)
                }
            }
            for await events in group {
                for ev in events where seenIds.insert(ev.id).inserted {
                    allEvents.append(ev)
                }
            }
        }

        // read リレーの結果が空なら通常リレーにフォールバック
        if allEvents.isEmpty {
            return await fetchEvents(filters: filters)
        }
        return allEvents
    }


    /// Fast, network-free notification snapshot for opening the sheet without a spinner.
    /// Uses the persisted notification result, profile cache, and cached original posts only.
    func cachedNotificationsWithContext(pubkey: String) -> NotificationResult? {
        guard let cached = cache.getCachedNotificationResult() else { return nil }
        let pubkeys = Array(Set(cached.items.map { $0.pubkey }))
        var profiles: [String: UserProfile] = [:]
        for key in pubkeys {
            if let profile = cache.getCachedProfile(key) { profiles[key] = profile }
        }
        var originals: [String: NostrEvent] = [:]
        for event in cached.originalPosts ?? [] { originals[event.id] = event }
        for id in cached.items.compactMap(\.targetEventId) {
            if originals[id] == nil, let event = cache.getCachedEvent(eventId: id) {
                originals[id] = event
            }
        }
        return NotificationResult(items: cached.items, profiles: profiles, originalPosts: originals)
    }

    /// 通知 + プロフィール + 元投稿を一括取得（Android fetchNotifications 相当）。
    /// キャッシュを活用し、skipCache=true でリフレッシュ。
    func fetchNotificationsWithContext(pubkey: String, skipCache: Bool = false) async -> NotificationResult {
        // キャッシュからの復元（skipCache でない場合のみ）
        if !skipCache, let cached = cache.getCachedNotificationResult() {
            // キャッシュ済みアイテムのプロフィール・元投稿を再構築。元投稿もキャッシュから即時表示する。
            let pubkeys = Array(Set(cached.items.map { $0.pubkey }))
            async let profileList = fetchProfiles(pubkeys: pubkeys)
            async let postMap = resolveOriginalPosts(for: cached.items, cachedOriginalPosts: cached.originalPosts ?? [])
            let (profiles, originalPosts) = await (profileList, postMap)
            let profilesMap = Dictionary(profiles.map { ($0.pubkey, $0) }, uniquingKeysWith: { a, _ in a })
            if (cached.originalPosts ?? []).count != originalPosts.count {
                cache.setCachedNotificationResult(cached.items, originalPosts: originalPosts)
            }
            return NotificationResult(items: cached.items, profiles: profilesMap, originalPosts: originalPosts)
        }

        let items = await fetchNotifications(pubkey: pubkey)

        // プロフィール取得
        let pubkeys = Array(Set(items.map { $0.pubkey }))
        let profileList = await fetchProfiles(pubkeys: pubkeys)
        let profilesMap = Dictionary(profileList.map { ($0.pubkey, $0) }, uniquingKeysWith: { a, _ in a })

        // 元投稿取得（reaction/repost/zap/quote の対象イベント）。取得後に通知結果ごとキャッシュし、次回表示を高速化。
        let originalPosts = await resolveOriginalPosts(for: items)
        cache.setCachedNotificationResult(items, originalPosts: originalPosts)

        return NotificationResult(items: items, profiles: profilesMap, originalPosts: originalPosts)
    }

    /// 通知に紐づく元投稿を解決する。キャッシュ済みイベントを優先し、不足分だけリレーから一括取得する。
    private func resolveOriginalPosts(for items: [NotificationItem], cachedOriginalPosts: [NostrEvent] = []) async -> [String: NostrEvent] {
        let previewTypes: Set<String> = ["reaction", "emoji_reaction", "repost", "zap", "quote"]
        let targetIds = Set(items.compactMap { item -> String? in
            guard previewTypes.contains(item.type) else { return nil }
            return item.targetEventId
        })
        guard !targetIds.isEmpty else { return [:] }

        var originalPosts = Dictionary(cachedOriginalPosts.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let missingIds = Array(targetIds.subtracting(originalPosts.keys).prefix(50))
        if !missingIds.isEmpty {
            let filter = NostrFilter(ids: missingIds, limit: missingIds.count)
            let events = await fetchEvents(filters: [filter], timeoutSeconds: 3.0)
            cache.setCachedEvents(events)
            for event in events { originalPosts[event.id] = event }
        }
        return originalPosts.filter { targetIds.contains($0.key) }
    }

    // MARK: - fetchEvent

    /// イベント ID を指定して単一イベントを取得する。
    /// Android: `NostrRepository.fetchEvent()` に相当。
    func fetchEvent(eventId: String) async -> NostrEvent? {
        if let cached = cache.getCachedEvent(eventId: eventId) { return cached }
        let filter = NostrFilter(ids: [eventId], limit: 1)
        let event = await fetchEvents(filters: [filter], timeoutSeconds: 2.5).first
        if let event { cache.setCachedEvent(event) }
        return event
    }


    /// NIP-19 naddr の kind:pubkey:d 参照から addressable event を取得する。
    func fetchAddressableEvent(aTag: String) async -> NostrEvent? {
        let parts = aTag.split(separator: ":", maxSplits: 2).map(String.init)
        guard parts.count == 3, let kind = Int(parts[0]) else { return nil }
        let filter = NostrFilter(authors: [parts[1]], kinds: [kind], limit: 10, tags: ["#d": [parts[2]]])
        return await fetchEvents(filters: [filter], timeoutSeconds: 5.0)
            .max(by: { $0.createdAt < $1.createdAt })
    }

    // MARK: - BOLT-11 Amount Parser

    /// BOLT-11 インボイス文字列からミリサトシ単位の送金額を解析する。
    /// Android: `NostrRepository.parseBolt11Amount()` に相当。
    ///
    /// BOLT-11 HR部: `ln` + チェーンプレフィックス + amount + 乗数 + `1` + ...
    /// 乗数: m=milli, u=micro, n=nano, p=pico (BTC基準)
    static func parseBolt11Amount(_ bolt11: String) -> Int64? {
        let lower = bolt11.lowercased()
        guard lower.hasPrefix("ln") else { return nil }

        // チェーンプレフィックスを除去
        var rest = lower.dropFirst(2)
        for prefix in ["bcrt", "tbs", "tb", "bc"] {
            if rest.hasPrefix(prefix) {
                rest = rest.dropFirst(prefix.count)
                break
            }
        }

        // 数字部分と乗数文字を抽出
        var digits = ""
        var multiplier: Character? = nil
        for ch in rest {
            if ch.isNumber {
                digits.append(ch)
            } else if digits.isEmpty {
                break // 数字なし → 金額フィールド不在
            } else {
                if "munp".contains(ch) { multiplier = ch }
                break
            }
        }
        guard let amount = Int64(digits) else { return nil }

        // BTC → msats 換算
        switch multiplier {
        case "m": return amount * 100_000_000      // milli-BTC
        case "u": return amount * 100_000           // micro-BTC
        case "n": return amount * 100               // nano-BTC
        case "p": return max(1, amount / 10)        // pico-BTC (端数切り上げ)
        default:  return amount * 100_000_000_000   // whole BTC
        }
    }
}


private func removeNostrEventLinksForNotification(_ content: String) -> String {
    let pattern = #"nostr:(?:note1|nevent1)[a-z0-9]{58,}"#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return content }
    let ns = content as NSString
    return regex.stringByReplacingMatches(
        in: content,
        range: NSRange(location: 0, length: ns.length),
        withTemplate: ""
    ).trimmingCharacters(in: .whitespacesAndNewlines)
}
