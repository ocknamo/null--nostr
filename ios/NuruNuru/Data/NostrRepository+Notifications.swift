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

    /// ユーザー宛の通知（リアクション・Zap・リポスト・返信/メンション・バッジ付与）を取得する。
    /// NIP-65 read リレーを優先的に使用 (Android parity)。
    /// 24時間ウィンドウ、最大 `limit` 件。Android の `fetchNotifications()` に相当。
    func fetchNotifications(pubkey: String, limit: Int = 50) async -> [NotificationItem] {
        let oneDayAgo = Int64(Date().addingTimeInterval(-86400).timeIntervalSince1970)

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

        // NIP-65 read リレー優先 (Android parity)
        let readRelays = nip65ReadRelayUrls()

        // 全種別を並列取得（NIP-65 read リレーがあればそちらを使用）
        async let reactions = readRelays.isEmpty
            ? fetchEvents(filters: [reactionFilter])
            : fetchEventsFromReadRelays(readRelays, filters: [reactionFilter])
        async let zaps = readRelays.isEmpty
            ? fetchEvents(filters: [zapFilter])
            : fetchEventsFromReadRelays(readRelays, filters: [zapFilter])
        async let reposts = readRelays.isEmpty
            ? fetchEvents(filters: [repostFilter])
            : fetchEventsFromReadRelays(readRelays, filters: [repostFilter])
        async let mentions = readRelays.isEmpty
            ? fetchEvents(filters: [replyFilter])
            : fetchEventsFromReadRelays(readRelays, filters: [replyFilter])
        async let badges = readRelays.isEmpty
            ? fetchEvents(filters: [badgeFilter])
            : fetchEventsFromReadRelays(readRelays, filters: [badgeFilter])

        let (reactionEvents, zapEvents, repostEvents, mentionEvents, badgeEvents) =
            await (reactions, zaps, reposts, mentions, badges)

        var items: [NotificationItem] = []

        // MARK: Reactions (Kind 7)
        for event in reactionEvents {
            guard event.pubkey != pubkey else { continue }
            let content  = event.content.isEmpty ? "+" : event.content
            let emojiTag = event.tags.first { $0.first == "emoji" }
            // "emoji" タグ: ["emoji", <name>, <url>]
            let emojiUrl = emojiTag.flatMap { $0.count >= 3 ? $0[2] : nil }
            let isCustom = emojiUrl != nil ||
                (content.hasPrefix(":") && content.hasSuffix(":") && content.count > 2)

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
            guard zapPubkey != pubkey else { continue }

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
            guard event.pubkey != pubkey else { continue }
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
            guard event.pubkey != pubkey else { continue }

            let eTags = event.tags.filter { $0.first == "e" }
            let hasReplyMarker = eTags.contains { $0.count >= 4 && $0[3] == "reply" }
            let hasRootMarker  = eTags.contains { $0.count >= 4 && $0[3] == "root" }
            let hasPTagToMe    = event.tags.contains { $0.first == "p" && $0.count >= 2 && $0[1] == pubkey }
            let hasQTag        = event.tags.contains { $0.first == "q" }

            // reply判定: 明示 reply marker / root+私宛p / 旧式 e+p（ただし quote は除外）
            let isReply = hasReplyMarker
                || (hasRootMarker && hasPTagToMe)
                || (!eTags.isEmpty && hasPTagToMe && !hasQTag)

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
            guard event.pubkey != pubkey else { continue }
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

        return items.sorted { $0.createdAt > $1.createdAt }
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

    /// 通知 + プロフィール + 元投稿を一括取得（Android fetchNotifications 相当）。
    /// キャッシュを活用し、skipCache=true でリフレッシュ。
    func fetchNotificationsWithContext(pubkey: String, skipCache: Bool = false) async -> NotificationResult {
        // キャッシュからの復元（skipCache でない場合のみ）
        if !skipCache, let cached = cache.getCachedNotificationResult() {
            // キャッシュ済みアイテムのプロフィール・元投稿を再構築
            let pubkeys = Array(Set(cached.items.map { $0.pubkey }))
            let profileList = await fetchProfiles(pubkeys: pubkeys)
            let profilesMap = Dictionary(profileList.map { ($0.pubkey, $0) }, uniquingKeysWith: { a, _ in a })
            return NotificationResult(items: cached.items, profiles: profilesMap, originalPosts: [:])
        }

        let items = await fetchNotifications(pubkey: pubkey)

        // キャッシュに保存
        cache.setCachedNotificationResult(items)

        // プロフィール取得
        let pubkeys = Array(Set(items.map { $0.pubkey }))
        let profileList = await fetchProfiles(pubkeys: pubkeys)
        let profilesMap = Dictionary(profileList.map { ($0.pubkey, $0) }, uniquingKeysWith: { a, _ in a })

        // 元投稿取得（reaction/repost/zap の対象イベント）
        let targetIds = Set(items.compactMap { item -> String? in
            guard ["reaction", "emoji_reaction", "repost", "zap"].contains(item.type) else { return nil }
            return item.targetEventId
        })
        var originalPosts: [String: NostrEvent] = [:]
        if !targetIds.isEmpty {
            // 一括フェッチ（最大50件）
            let filter = NostrFilter(ids: Array(targetIds).prefix(50).map { $0 }, limit: 50)
            let events = await fetchEvents(filters: [filter])
            for event in events {
                originalPosts[event.id] = event
            }
        }

        return NotificationResult(items: items, profiles: profilesMap, originalPosts: originalPosts)
    }

    // MARK: - fetchEvent

    /// イベント ID を指定して単一イベントを取得する。
    /// Android: `NostrRepository.fetchEvent()` に相当。
    func fetchEvent(eventId: String) async -> NostrEvent? {
        let filter = NostrFilter(ids: [eventId], limit: 1)
        return await fetchEvents(filters: [filter]).first
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
