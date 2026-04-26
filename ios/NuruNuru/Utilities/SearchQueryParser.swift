import Foundation

// MARK: - MediaFilter

enum MediaFilter: String, CaseIterable {
    case image
    case video
    case link
}

// MARK: - ParsedQuery

struct ParsedQuery {
    /// 残りのキーワードテキスト（searchnosへ送るクエリ）
    let text: String
    /// filter:image / filter:video / filter:link
    let filters: [MediaFilter]
    /// from:npub1... or from:user@domain（単一: 最初の1件）
    let fromUser: String?
    /// since:YYYY-MM-DD → Date
    let sinceDate: Date?
    /// until:YYYY-MM-DD → Date
    let untilDate: Date?
    /// -word → クライアント側除外フィルタ
    let excludeTerms: [String]
    /// "phrase" → クライアント側完全一致フィルタ
    let exactPhrases: [String]
    /// kind:N → 特定 Kind フィルタ
    let kind: Int?

    /// ハッシュタグ（#t フィルタ用）— SearchSheet 内で直接利用
    let hashtags: [String]
    /// from: の全ターゲット（npub / hex / NIP-05 混在）
    let fromTargets: [String]

    /// オペレーターが1つでも含まれる場合 true
    var hasOperators: Bool {
        !hashtags.isEmpty || !fromTargets.isEmpty ||
        sinceDate != nil || untilDate != nil ||
        !excludeTerms.isEmpty || !exactPhrases.isEmpty ||
        !filters.isEmpty || kind != nil
    }
}

// MARK: - SearchQueryParser

/// 検索クエリ文字列をパースしてオペレータトークンを抽出する。
///
/// サポートするオペレータ:
///   #タグ              → #t タグフィルタ
///   from:npub1...     → authors フィルタ (npub / 64桁 hex)
///   from:user@domain  → NIP-05解決 → authors フィルタ
///   since:YYYY-MM-DD  → since タイムスタンプ
///   until:YYYY-MM-DD  → until タイムスタンプ
///   -除外語            → 結果からクライアント側除外
///   "完全一致"         → クライアント側完全一致フィルタ
///   filter:image      → 画像 URL を含む投稿のみ
///   filter:video      → 動画 URL を含む投稿のみ
///   filter:link       → リンクを含む投稿のみ
///   kind:N            → 特定 Kind フィルタ
enum SearchQueryParser {

    // MARK: Regex patterns

    private static let exactRegex   = try! NSRegularExpression(pattern: #""([^"]+)""#)
    private static let hashtagRegex = try! NSRegularExpression(pattern: #"(?<!\S)#(\w+)"#)
    private static let fromRegex    = try! NSRegularExpression(pattern: #"from:(\S+)"#)
    private static let sinceRegex   = try! NSRegularExpression(pattern: #"since:(\d{4}-\d{2}-\d{2})"#)
    private static let untilRegex   = try! NSRegularExpression(pattern: #"until:(\d{4}-\d{2}-\d{2})"#)
    private static let mediaRegex   = try! NSRegularExpression(pattern: #"filter:(image|video|link)"#)
    private static let excludeRegex = try! NSRegularExpression(pattern: #"(?<!\S)-([^\s]+)"#)
    private static let kindRegex    = try! NSRegularExpression(pattern: #"kind:(\d+)"#)
    private static let hexRegex     = try! NSRegularExpression(pattern: #"^[0-9a-f]{64}$"#)

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    // MARK: Public API

    static func parse(query raw: String) -> ParsedQuery {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. 完全一致フレーズ ("...") を先に抽出
        let exactPhrases = allCaptures(exactRegex, in: s, group: 1)
        s = replace(exactRegex, in: s, with: " ")

        // 2. ハッシュタグ
        let hashtags = allCaptures(hashtagRegex, in: s, group: 1).map { $0.lowercased() }
        s = replace(hashtagRegex, in: s, with: " ")

        // 3. from:
        let fromTargets = allCaptures(fromRegex, in: s, group: 1)
        s = replace(fromRegex, in: s, with: " ")

        // 4. since:
        let sinceStr = firstCapture(sinceRegex, in: s, group: 1)
        let sinceDate = sinceStr.flatMap { dateFormatter.date(from: $0) }
        s = replace(sinceRegex, in: s, with: " ")

        // 5. until:
        let untilStr = firstCapture(untilRegex, in: s, group: 1)
        let untilDate = untilStr.flatMap { dateFormatter.date(from: $0) }
        s = replace(untilRegex, in: s, with: " ")

        // 6. filter:image/video/link
        let mediaValues = allCaptures(mediaRegex, in: s, group: 1)
        let filters = mediaValues.compactMap { MediaFilter(rawValue: $0) }
        s = replace(mediaRegex, in: s, with: " ")

        // 7. -除外語
        let excludeTerms = allCaptures(excludeRegex, in: s, group: 1)
        s = replace(excludeRegex, in: s, with: " ")

        // 8. kind:N
        let kindStr = firstCapture(kindRegex, in: s, group: 1)
        let kind = kindStr.flatMap { Int($0) }
        s = replace(kindRegex, in: s, with: " ")

        // 9. from: ターゲットを種別分類（fromUser: 最初の1件）
        let fromUser = fromTargets.first

        // 10. 残りがテキストクエリ
        let whitespace = try! NSRegularExpression(pattern: #"\s+"#)
        let text = replace(whitespace, in: s, with: " ").trimmingCharacters(in: .whitespacesAndNewlines)

        return ParsedQuery(
            text:         text,
            filters:      filters,
            fromUser:     fromUser,
            sinceDate:    sinceDate,
            untilDate:    untilDate,
            excludeTerms: excludeTerms,
            exactPhrases: exactPhrases,
            kind:         kind,
            hashtags:     hashtags,
            fromTargets:  fromTargets
        )
    }

    // MARK: Helpers

    private static func allCaptures(_ regex: NSRegularExpression, in str: String, group: Int) -> [String] {
        let range = NSRange(str.startIndex..., in: str)
        return regex.matches(in: str, range: range).compactMap { match -> String? in
            guard let r = Range(match.range(at: group), in: str) else { return nil }
            return String(str[r])
        }
    }

    private static func firstCapture(_ regex: NSRegularExpression, in str: String, group: Int) -> String? {
        let range = NSRange(str.startIndex..., in: str)
        guard let match = regex.firstMatch(in: str, range: range),
              let r = Range(match.range(at: group), in: str) else { return nil }
        return String(str[r])
    }

    private static func replace(_ regex: NSRegularExpression, in str: String, with replacement: String) -> String {
        let range = NSRange(str.startIndex..., in: str)
        return regex.stringByReplacingMatches(in: str, range: range, withTemplate: replacement)
    }
}
