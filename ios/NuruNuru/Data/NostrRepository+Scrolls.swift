import Foundation

/// NIP-A5 Scrolls (Kind 1227 / 10027) 関連メソッド。
/// Android の NostrRepositoryScrolls.kt に相当。
///
/// - Kind 1227: Scroll 定義イベント（WASM + param タグ）
/// - Kind 10027: お気に入りスクロールリスト（replaceable event, "e" タグ）
extension NostrRepository {

    // MARK: - Kind constants

    /// NIP-A5 Scroll イベント kind。
    private static let kindScroll         = 1227
    /// NIP-A5 お気に入りスクロールリスト kind。
    private static let kindFavoriteScrolls = 10027

    // MARK: - Fetch Scrolls

    /// Kind 1227 をリレーから取得し `ScrollEvent` の配列として返す。
    ///
    /// - Parameter limit: 最大取得件数（デフォルト 50）。
    /// - Returns: パース成功した `ScrollEvent` を createdAt 降順で返す。
    func fetchScrolls(limit: Int = 50) async -> [ScrollEvent] {
        var filter = NostrFilter()
        filter.kinds = [Self.kindScroll]
        filter.limit = limit

        let events = await fetchEvents(filters: [filter], timeoutSeconds: 8.0)
        return events
            .compactMap { ScrollEvent(nostrEvent: $0) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Fetch Favorite Scrolls

    /// Kind 10027 お気に入りスクロールリストを取得し、"e" タグの ID 配列を返す。
    ///
    /// - Parameter pubkeyHex: 取得対象ユーザーの hex 公開鍵。
    /// - Returns: お気に入り登録済みスクロールイベント ID の配列。
    func fetchFavoriteScrolls(pubkeyHex: String) async -> [String] {
        var filter = NostrFilter()
        filter.kinds   = [Self.kindFavoriteScrolls]
        filter.authors = [pubkeyHex]
        filter.limit   = 1

        let events = await fetchEvents(filters: [filter], timeoutSeconds: 4.0)
        guard let latest = events.max(by: { $0.createdAt < $1.createdAt }) else { return [] }
        return latest.getTagValues("e")
    }

    // MARK: - Add Favorite Scroll

    /// スクロールをお気に入りリストに追加し、Kind 10027 として再発行する。
    ///
    /// 既に登録済みの場合は何もしない（冪等）。
    /// - Parameters:
    ///   - pubkeyHex: 操作者の hex 公開鍵。
    ///   - scrollId:  追加するスクロールイベント ID。
    func addFavoriteScroll(pubkeyHex: String, scrollId: String) async throws {
        var existing = await fetchFavoriteScrolls(pubkeyHex: pubkeyHex)
        guard !existing.contains(scrollId) else { return }
        existing.append(scrollId)
        let tags: [[String]] = existing.map { ["e", $0] }
        try await publishEvent(kind: Self.kindFavoriteScrolls, tags: tags, content: "")
    }

    // MARK: - Remove Favorite Scroll

    /// スクロールをお気に入りリストから削除し、Kind 10027 として再発行する。
    ///
    /// 対象がリスト内に存在しない場合は何もしない（冪等）。
    /// - Parameters:
    ///   - pubkeyHex: 操作者の hex 公開鍵。
    ///   - scrollId:  削除するスクロールイベント ID。
    func removeFavoriteScroll(pubkeyHex: String, scrollId: String) async throws {
        var existing = await fetchFavoriteScrolls(pubkeyHex: pubkeyHex)
        let before = existing.count
        existing.removeAll { $0 == scrollId }
        guard existing.count != before else { return }
        let tags: [[String]] = existing.map { ["e", $0] }
        try await publishEvent(kind: Self.kindFavoriteScrolls, tags: tags, content: "")
    }
}
