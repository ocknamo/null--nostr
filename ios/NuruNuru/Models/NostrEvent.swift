import Foundation

/// NIP-01 Nostr event — mirrors Android NostrEvent data class.
struct NostrEvent: Codable, Identifiable, Hashable {
    let id: String
    let pubkey: String
    let createdAt: Int64
    let kind: Int
    let tags: [[String]]
    let content: String
    let sig: String

    enum CodingKeys: String, CodingKey {
        case id, pubkey
        case createdAt = "created_at"
        case kind, tags, content, sig
    }

    init(
        id: String = "",
        pubkey: String = "",
        createdAt: Int64 = 0,
        kind: Int = 1,
        tags: [[String]] = [],
        content: String = "",
        sig: String = ""
    ) {
        self.id       = id
        self.pubkey   = pubkey
        self.createdAt = createdAt
        self.kind     = kind
        self.tags     = tags
        self.content  = content
        self.sig      = sig
    }

    /// Returns the first tag value for the given tag name.
    func getTagValue(_ tagName: String) -> String? {
        tags.first { $0.first == tagName }.flatMap { $0.dropFirst().first }
    }

    /// Returns all tag values for the given tag name.
    func getTagValues(_ tagName: String) -> [String] {
        tags.filter { $0.first == tagName }.compactMap { $0.dropFirst().first }
    }

    /// NIP-70: protected event (has single "-" tag).
    var isProtected: Bool {
        tags.contains { $0.count == 1 && $0[0] == "-" }
    }

    /// NIP-92 `imeta` tags から URL を抽出する。
    /// 対応形式:
    /// - ["imeta", "url https://...", ...]
    /// - ["imeta", "x <sha256>", "m image/webp", "url https://...", ...]
    /// - ["imeta", "https://..."] (互換)
    func extractImetaUrls() -> [String] {
        var out: [String] = []
        var seen = Set<String>()

        for tag in tags where tag.first == "imeta" {
            for item in tag.dropFirst() {
                let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }

                var candidate: String? = nil
                if trimmed.hasPrefix("url ") {
                    candidate = String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
                } else if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
                    candidate = trimmed
                }

                guard let c = candidate,
                      let u = URL(string: c),
                      let scheme = u.scheme?.lowercased(),
                      scheme == "http" || scheme == "https" else { continue }

                if seen.insert(c).inserted {
                    out.append(c)
                }
            }
        }

        return out
    }
}

// MARK: - NIP-65 Relay Permission

/// リレーの読み書き権限。
/// Android: `Nip65Relay.read` / `Nip65Relay.write` フィールドに対応。
enum RelayPermission: String, Codable, CaseIterable {
    case read      = "read"
    case write     = "write"
    case readWrite = "readWrite"

    /// NIP-65 "r" タグの 3 番目の要素からパースする。
    /// マーカーなし → readWrite、"read" → read、"write" → write。
    init(marker: String?) {
        switch marker {
        case "read":  self = .read
        case "write": self = .write
        default:      self = .readWrite
        }
    }

    /// NIP-65 タグに付与するマーカー文字列。readWrite の場合は nil（タグ 3 列目省略）。
    var tagMarker: String? {
        switch self {
        case .read:      return "read"
        case .write:     return "write"
        case .readWrite: return nil
        }
    }

    var label: String {
        switch self {
        case .read:      return "読み取り"
        case .write:     return "書き込み"
        case .readWrite: return "読み書き"
        }
    }
}

// MARK: - NIP-65 Relay Model

/// NIP-65 Kind 10002 リレーリストの 1 エントリ。
/// Android: `io.nurunuru.app.data.models.Nip65Relay` に対応。
struct Nip65Relay: Codable, Identifiable, Hashable {
    var id: String { url }
    let url: String
    var permission: RelayPermission

    init(url: String, permission: RelayPermission = .readWrite) {
        self.url        = url
        self.permission = permission
    }
}

// MARK: - Nostr Filter (NIP-01 REQ filter)

struct NostrFilter: Encodable {
    var ids:      [String]?
    var authors:  [String]?
    var kinds:    [Int]?
    var since:    Int64?
    var until:    Int64?
    var limit:    Int?
    var tags:     [String: [String]]?  // "#e", "#p", etc.
    var search:   String?              // NIP-50

    enum CodingKeys: String, CodingKey {
        case ids, authors, kinds, since, until, limit, search
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicKey.self)
        if let ids     = ids      { try container.encode(ids,     forKey: .init("ids")) }
        if let authors = authors  { try container.encode(authors, forKey: .init("authors")) }
        if let kinds   = kinds    { try container.encode(kinds,   forKey: .init("kinds")) }
        if let since   = since    { try container.encode(since,   forKey: .init("since")) }
        if let until   = until    { try container.encode(until,   forKey: .init("until")) }
        if let limit   = limit    { try container.encode(limit,   forKey: .init("limit")) }
        if let search  = search   { try container.encode(search,  forKey: .init("search")) }
        if let tags = tags {
            for (key, values) in tags {
                try container.encode(values, forKey: .init(key))
            }
        }
    }

    private struct DynamicKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(_ key: String) { self.stringValue = key }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }
}
