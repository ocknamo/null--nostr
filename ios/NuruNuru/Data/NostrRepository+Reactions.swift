import Foundation

/// リアクション数取得・Zap金額パース・Birdwatch ラベル関連メソッド。
/// Android の NostrRepositoryReactions.kt に相当。
///
/// Phase 3 で `enrichPosts()` がタイムライン取得後に自動呼び出される予定。
extension NostrRepository {

    // MARK: - Reaction Counts (Kind 7, NIP-25)

    /// 指定イベント ID 群のリアクション数を取得する。
    ///
    /// Kind 7 イベントを `#e` タグでバッチ取得し、イベント ID ごとにカウントする。
    /// Android: `fetchReactions()` に対応。
    ///
    /// - Parameter eventIds: カウント対象のイベント ID 配列。
    /// - Returns: `[eventId: reactionCount]` の辞書。
    func fetchReactionCounts(eventIds: [String]) async -> [String: Int] {
        guard !eventIds.isEmpty else { return [:] }

        var filter = NostrFilter()
        filter.kinds = [NostrKind.reaction]
        filter.tags  = ["#e": eventIds]
        filter.limit = 500

        let events = await fetchEvents(filters: [filter], timeoutSeconds: 3.0)

        return Dictionary(
            grouping: events.compactMap { $0.getTagValue("e") },
            by: { $0 }
        ).mapValues { $0.count }
    }

    // MARK: - Repost Counts (Kind 6, NIP-18)

    /// 指定イベント ID 群のリポスト数を取得する。
    ///
    /// Kind 6 イベントを `#e` タグでバッチ取得し、イベント ID ごとにカウントする。
    ///
    /// - Parameter eventIds: カウント対象のイベント ID 配列。
    /// - Returns: `[eventId: repostCount]` の辞書。
    func fetchRepostCounts(eventIds: [String]) async -> [String: Int] {
        guard !eventIds.isEmpty else { return [:] }

        var filter = NostrFilter()
        filter.kinds = [NostrKind.repost]
        filter.tags  = ["#e": eventIds]
        filter.limit = 500

        let events = await fetchEvents(filters: [filter], timeoutSeconds: 3.0)

        return Dictionary(
            grouping: events.compactMap { $0.getTagValue("e") },
            by: { $0 }
        ).mapValues { $0.count }
    }

    // MARK: - Zap Amounts (Kind 9735, NIP-57)

    /// 指定イベント ID 群の Zap 受取金額（サトシ）を取得する。
    ///
    /// Kind 9735 Zap レシートを `#e` タグでバッチ取得し、
    /// bolt11 または description タグから金額をパースしてイベント ID ごとに合算する。
    ///
    /// - Parameter eventIds: カウント対象のイベント ID 配列。
    /// - Returns: `[eventId: totalSatoshis]` の辞書。
    func fetchZapAmounts(eventIds: [String]) async -> [String: Int64] {
        guard !eventIds.isEmpty else { return [:] }

        var filter = NostrFilter()
        filter.kinds = [NostrKind.zapReceipt]
        filter.tags  = ["#e": eventIds]
        filter.limit = 500

        let events = await fetchEvents(filters: [filter], timeoutSeconds: 3.0)

        var totals: [String: Int64] = [:]
        for event in events {
            guard let targetId = event.getTagValue("e") else { continue }
            let sats = parseZapAmountSats(from: event)
            totals[targetId, default: 0] += sats
        }
        return totals
    }

    // MARK: - Birdwatch Notes (Kind 1985, NIP-32)

    /// Birdwatch コンテキストノート (Kind 1985) をパブリッシュする。
    ///
    /// NIP-32 ラベルフォーマット:
    /// - `["e", targetEventId]` — 対象イベント
    /// - `["L", "social.birdwatch"]` — ラベル名前空間
    /// - `["l", contextType, "social.birdwatch"]` — ラベル値
    /// - `["r", sourceUrl]` — ソース URL（任意）
    ///
    /// Android: `publishBirdwatchNote()` に対応。
    func publishBirdwatchNote(
        targetEventId: String,
        content:       String,
        contextType:   String,
        sourceUrl:     String? = nil
    ) async throws {
        var tags: [[String]] = [
            ["e", targetEventId],
            ["L", "social.birdwatch"],
            ["l", contextType, "social.birdwatch"]
        ]
        if let url = sourceUrl, !url.trimmingCharacters(in: .whitespaces).isEmpty {
            tags.append(["r", url])
        }
        // ソース URL をコンテンツ末尾に付加（Android と同様）
        let fullContent: String
        if let url = sourceUrl, !url.trimmingCharacters(in: .whitespaces).isEmpty {
            fullContent = "\(content)\n\(url)"
        } else {
            fullContent = content
        }
        try await publishEvent(kind: NostrKind.label, tags: tags, content: fullContent)
    }

    /// 指定イベント ID 群に付与された Birdwatch ラベル (Kind 1985) を取得する。
    ///
    /// Android: `fetchBirdwatchNotes()` に対応。
    ///
    /// - Parameter eventIds: 対象イベント ID 配列。
    /// - Returns: `[eventId: [labelEvents]]` の辞書。
    func fetchBirdwatchNotes(eventIds: [String]) async -> [String: [NostrEvent]] {
        guard !eventIds.isEmpty else { return [:] }

        var filter = NostrFilter()
        filter.kinds = [NostrKind.label]
        filter.tags  = ["#e": eventIds]
        filter.limit = 200

        let events = await fetchEvents(filters: [filter], timeoutSeconds: 3.0)

        var result: [String: [NostrEvent]] = [:]
        for event in events {
            // Birdwatch ラベルのみ対象 (["L", "birdwatch"] タグが必須)
            guard event.tags.contains(where: { $0.first == "L" && $0[safe: 1] == "birdwatch" }) else { continue }
            // 対象イベント ID を取得
            guard let targetId = event.tags
                .first(where: { $0.first == "e" && eventIds.contains($0[safe: 1] ?? "") })?[safe: 1]
            else { continue }
            result[targetId, default: []].append(event)
        }
        return result
    }

}

// MARK: - Private Helpers

extension NostrRepository {

    /// Kind 9735 Zap レシートから Satoshi 金額をパースする。
    ///
    /// パース優先順位:
    /// 1. "amount" タグ (ミリサトシ → サトシ変換)
    /// 2. "description" タグ内の zap request JSON の "amount" タグ
    /// 3. bolt11 インボイスの金額フィールド (簡易パース)
    private func parseZapAmountSats(from event: NostrEvent) -> Int64 {
        // 1. "amount" タグを直接参照
        if let amountStr = event.getTagValue("amount"),
           let msats = Int64(amountStr), msats > 0 {
            return msats / 1000
        }

        // 2. "description" タグ内の zap request JSON から取得
        if let descJSON = event.getTagValue("description"),
           let data = descJSON.data(using: .utf8),
           let zapReq = try? JSONDecoder().decode(ZapRequestSummary.self, from: data),
           let amountTag = zapReq.tags.first(where: { $0.first == "amount" }),
           let amountStr = amountTag[safe: 1],
           let msats = Int64(amountStr), msats > 0 {
            return msats / 1000
        }

        // 3. bolt11 インボイスから簡易パース (lnbc[amount][multiplier]...)
        if let bolt11 = event.getTagValue("bolt11") {
            return parseBolt11Sats(bolt11)
        }

        return 0
    }

    /// bolt11 インボイス文字列から金額 (satoshi) を簡易パースする。
    ///
    /// フォーマット: `lnbc[amount][multiplier]1...`
    /// multiplier: p=pico(10^-12 BTC), n=nano(10^-9 BTC), u=micro(10^-6 BTC), m=milli(10^-3 BTC)
    private func parseBolt11Sats(_ bolt11: String) -> Int64 {
        let lower = bolt11.lowercased()
        guard lower.hasPrefix("lnbc") || lower.hasPrefix("lntb") || lower.hasPrefix("lntbs") else { return 0 }

        // "lnbc" の後の数値＋乗数を抽出
        let prefix = lower.hasPrefix("lntbs") ? "lntbs" : lower.hasPrefix("lntb") ? "lntb" : "lnbc"
        let suffix = String(lower.dropFirst(prefix.count))

        var numStr = ""
        var multiplier: Character = "0"
        for ch in suffix {
            if ch.isNumber {
                numStr.append(ch)
            } else {
                multiplier = ch
                break
            }
        }
        guard let amount = Int64(numStr) else { return 0 }

        // BTC → satoshi 変換
        // p=10^-12 BTC = 0.0001 sat (無視), n=100 sat, u=100,000 sat, m=100,000,000 sat
        switch multiplier {
        case "m": return amount * 100_000
        case "u": return amount * 100
        case "n": return amount / 10   // 100 msat ≒ 0.1 sat → 切り捨て
        default:  return 0
        }
    }
}

// MARK: - Decodable Helpers

/// Zap request summary — "description" タグ内の Kind 9734 JSON から amount タグだけ取り出すため使用。
private struct ZapRequestSummary: Decodable {
    let tags: [[String]]
}
