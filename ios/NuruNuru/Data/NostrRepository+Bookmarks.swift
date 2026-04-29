import Foundation

/// ブックマーク (Kind 10003, NIP-51) 関連メソッド。
/// Android の NostrRepositoryBookmarks.kt に相当。
///
/// Kind 10003 は replaceable event — 同じ pubkey で1件のみ存在し、更新で上書きされる。
extension NostrRepository {

    // MARK: - Fetch Bookmark Event IDs

    /// ブックマーク一覧 (Kind 10003) からイベント ID 配列を取得する。
    ///
    /// - Parameter pubkeyHex: 取得対象ユーザーの hex 公開鍵。
    /// - Returns: "e" タグに含まれるブックマーク済みイベント ID 配列。
    func fetchBookmarkEventIds(pubkeyHex: String) async -> [String] {
        let now = Date()
        if let cached = bookmarkEventIdCache[pubkeyHex],
           now.timeIntervalSince(cached.cachedAt) < 30 {
            return cached.ids
        }
        if let task = bookmarkEventIdFetchTasks[pubkeyHex] {
            return await task.value
        }

        let task = Task { await self.fetchBookmarkEventIdsUncached(pubkeyHex: pubkeyHex) }
        bookmarkEventIdFetchTasks[pubkeyHex] = task
        let ids = await task.value
        bookmarkEventIdCache[pubkeyHex] = (ids: ids, cachedAt: Date())
        bookmarkEventIdFetchTasks[pubkeyHex] = nil
        return ids
    }

    private func fetchBookmarkEventIdsUncached(pubkeyHex: String) async -> [String] {
        AppLogger.log("Bookmarks", "fetchBookmarkEventIds for \(pubkeyHex.prefix(16))…")
        var filter = NostrFilter()
        filter.kinds   = [NostrKind.bookmarks]
        filter.authors = [pubkeyHex]
        filter.limit   = 1

        // まずメインリレーから取得を試みる（タイムアウト延長）
        var events = await fetchEvents(filters: [filter], timeoutSeconds: 6.0)
        AppLogger.log("Bookmarks", "Kind 10003 events found: \(events.count)")

        // メインリレーで見つからない場合、各リレーに個別に問い合わせ
        if events.isEmpty {
            let relayUrls = getSavedRelayUrls()
            AppLogger.log("Bookmarks", "Retrying on individual relays: \(relayUrls.prefix(4))")
            for url in relayUrls.prefix(4) {
                let relayEvents = await client.fetchEventsFromRelay(url, filters: [filter], timeoutSeconds: 4.0)
                if !relayEvents.isEmpty {
                    events = relayEvents
                    AppLogger.log("Bookmarks", "Found kind-10003 on relay: \(url)")
                    break
                }
            }
        }

        guard let latest = events
            .filter({ $0.kind == NostrKind.bookmarks })
            .max(by: { $0.createdAt < $1.createdAt }) else {
            AppLogger.log("Bookmarks", "No bookmark event found")
            return []
        }
        let ids = latest.getTagValues("e")
        AppLogger.log("Bookmarks", "Bookmark contains \(ids.count) event IDs")
        return ids
    }

    // MARK: - Fetch Bookmarked Posts

    /// ブックマーク一覧 (Kind 10003) からイベントを取得し、`enrichPosts` を適用して返す。
    /// Android `NostrRepositoryBookmarks.fetchBookmarkedPosts` と同等。
    ///
    /// - Parameter pubkeyHex: ブックマーク所有者の hex 公開鍵。
    /// - Returns: いいね数・リポスト数・Zap 額が付与された `ScoredPost` 配列（投稿日時降順）。
    func fetchBookmarks(pubkeyHex: String) async -> [ScoredPost] {
        let eventIds = await fetchBookmarkEventIds(pubkeyHex: pubkeyHex)
        guard !eventIds.isEmpty else { return [] }

        var filter = NostrFilter()
        filter.ids   = eventIds
        filter.kinds = [NostrKind.textNote]

        let events = await fetchEvents(filters: [filter], timeoutSeconds: 6.0)

        // ID 重複排除
        var seen    = Set<String>()
        var posts   = events
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.createdAt > $1.createdAt }
            .map    { ScoredPost(event: $0) }

        // enrichPosts: いいね数 / リポスト数 / Zap 額を付与
        await enrichPosts(&posts)
        return posts
    }

    /// 後方互換ラッパー — 既存コードから参照されている場合は `fetchBookmarks` に委譲。
    @available(*, deprecated, renamed: "fetchBookmarks(pubkeyHex:)")
    func fetchBookmarkedPosts(pubkeyHex: String) async -> [ScoredPost] {
        await fetchBookmarks(pubkeyHex: pubkeyHex)
    }

    // MARK: - Add Bookmark

    /// イベントをブックマークリストに追加し、Kind 10003 として再発行する。
    ///
    /// 既にブックマーク済みの場合は何もしない（冪等）。
    /// - Parameters:
    ///   - pubkeyHex: 操作者の hex 公開鍵。
    ///   - eventId:   ブックマーク対象イベント ID。
    func addBookmark(pubkeyHex: String, eventId: String) async throws {
        AppLogger.log("Bookmarks", "addBookmark — eventId: \(eventId.prefix(16))…")
        var existing = await fetchBookmarkEventIds(pubkeyHex: pubkeyHex)
        guard !existing.contains(eventId) else {
            AppLogger.log("Bookmarks", "Already bookmarked, skipping")
            return
        }
        existing.append(eventId)
        let tags: [[String]] = existing.map { ["e", $0] }
        do {
            try await publishEvent(kind: NostrKind.bookmarks, tags: tags, content: "")
            bookmarkEventIdCache[pubkeyHex] = (ids: existing, cachedAt: Date())
            AppLogger.log("Bookmarks", "Bookmark published successfully — \(existing.count) total")
        } catch {
            AppLogger.log("Bookmarks", "Bookmark publish failed: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Remove Bookmark

    /// ブックマークリストからイベントを削除し、Kind 10003 として再発行する。
    ///
    /// 対象がリスト内に存在しない場合は何もしない（冪等）。
    /// - Parameters:
    ///   - pubkeyHex: 操作者の hex 公開鍵。
    ///   - eventId:   削除対象イベント ID。
    func removeBookmark(pubkeyHex: String, eventId: String) async throws {
        var existing = await fetchBookmarkEventIds(pubkeyHex: pubkeyHex)
        let before = existing.count
        existing.removeAll { $0 == eventId }
        guard existing.count != before else { return }
        let tags: [[String]] = existing.map { ["e", $0] }
        try await publishEvent(kind: NostrKind.bookmarks, tags: tags, content: "")
        bookmarkEventIdCache[pubkeyHex] = (ids: existing, cachedAt: Date())
    }

    // MARK: - isBookmarked

    /// ログイン中ユーザーのブックマークリストに指定イベントが含まれるか確認する。
    func isBookmarked(eventId: String) async -> Bool {
        let myPubkey = prefs.publicKeyHex ?? ""
        guard !myPubkey.isEmpty else { return false }
        let ids = await fetchBookmarkEventIds(pubkeyHex: myPubkey)
        return ids.contains(eventId)
    }
}
