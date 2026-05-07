import Foundation

/// diVine / OpenVine compatible NIP-71 short video event.
///
/// Primary discovery/publish kind is 34236 (addressable short video).  The
/// parser is intentionally permissive for metadata shape because diVine has
/// emitted both NIP-92 style `imeta` values (`"url https://..."`) and direct
/// legacy tags (`url`, `r`, `streaming`).
struct RokunanaVideo: Identifiable, Hashable {
    let event: NostrEvent
    var id: String { event.id }

    let dTag: String?
    let videoUrl: String
    let thumbnailUrl: String?
    let title: String?
    let summary: String?
    let duration: Int?
    let dimensions: String?
    let mimeType: String?
    let sha256: String?
    let fileSize: Int?
    let blurhash: String?
    let language: String?
    let publishedAt: Int64?
    let altText: String?
    let hashtags: [String]

    var displayTitle: String {
        if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return title }
        if let altText, !altText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return altText }
        return "ろくなな"
    }

    var displaySummary: String {
        if let summary, !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return summary }
        if !event.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return event.content }
        return altText ?? ""
    }

    init?(event: NostrEvent, permissive: Bool = false) {
        let acceptedKinds = permissive ? RokunanaVideoKinds.acceptableVideoKinds : RokunanaVideoKinds.discoveryKinds
        guard acceptedKinds.contains(event.kind) else { return nil }

        var dTag: String?
        var videoCandidates: [String] = []
        var thumbnailUrl: String?
        var title: String?
        var summary: String?
        var duration: Int?
        var dimensions: String?
        var mimeType: String?
        var sha256: String?
        var fileSize: Int?
        var blurhash: String?
        var language: String?
        var publishedAt: Int64?
        var altText: String?
        var hashtags: [String] = []

        for tag in event.tags {
            guard let name = tag.first else { continue }
            let value = tag.count > 1 ? tag[1] : ""

            switch name {
            case "d":
                dTag = value
            case "url", "streaming":
                if Self.isValidVideoUrl(value) { videoCandidates.append(Self.correctedUrl(value)) }
            case "r":
                if tag.count >= 3, tag[2] == "video", Self.isValidVideoUrl(value) {
                    videoCandidates.append(Self.correctedUrl(value))
                }
            case "imeta":
                Self.parseImeta(tag) { key, parsedValue in
                    switch key {
                    case "url":
                        if Self.isValidVideoUrl(parsedValue) { videoCandidates.append(Self.correctedUrl(parsedValue)) }
                    case "m":
                        mimeType = parsedValue
                    case "image":
                        if Self.isHttpUrl(parsedValue) { thumbnailUrl = parsedValue }
                    case "dim":
                        dimensions = parsedValue
                    case "size":
                        fileSize = Int(parsedValue)
                    case "x", "sha256":
                        sha256 = parsedValue
                    case "blurhash":
                        blurhash = parsedValue
                    case "duration":
                        duration = Int(Double(parsedValue) ?? -1)
                    default:
                        break
                    }
                }
            case "title":
                title = value
            case "summary":
                summary = value
            case "duration":
                duration = Int(value)
            case "published_at":
                publishedAt = Int64(value)
            case "alt":
                altText = value
            case "l":
                if tag.count > 2, tag[2] == "ISO-639-1" { language = value }
            case "t":
                if !value.isEmpty { hashtags.append(value) }
            default:
                break
            }
        }

        let bestVideoUrl = Self.bestVideoUrl(from: videoCandidates)
        guard let videoUrl = bestVideoUrl else { return nil }

        self.event = event
        self.dTag = dTag
        self.videoUrl = videoUrl
        self.thumbnailUrl = thumbnailUrl
        self.title = title
        self.summary = summary
        self.duration = duration
        self.dimensions = dimensions
        self.mimeType = mimeType
        self.sha256 = sha256
        self.fileSize = fileSize
        self.blurhash = blurhash
        self.language = language
        self.publishedAt = publishedAt
        self.altText = altText
        self.hashtags = Array(Set(hashtags)).sorted()
    }

    private static func parseImeta(_ tag: [String], onKeyValue: (String, String) -> Void) {
        guard tag.count > 1 else { return }
        let first = tag[1]
        if first.contains(" ") {
            for element in tag.dropFirst() {
                guard let idx = element.firstIndex(of: " ") else { continue }
                let key = String(element[..<idx])
                let value = String(element[element.index(after: idx)...])
                onKeyValue(key, value)
            }
        } else {
            var index = 1
            while index + 1 < tag.count {
                onKeyValue(tag[index], tag[index + 1])
                index += 2
            }
        }
    }

    private static func correctedUrl(_ url: String) -> String {
        url.replacingOccurrences(of: "apt.openvine.co", with: "api.openvine.co")
    }

    private static func isHttpUrl(_ url: String) -> Bool {
        guard let comp = URLComponents(string: correctedUrl(url)),
              let scheme = comp.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              comp.host?.isEmpty == false else { return false }
        return true
    }

    private static func isValidVideoUrl(_ url: String) -> Bool {
        isHttpUrl(url)
    }

    private static func bestVideoUrl(from urls: [String]) -> String? {
        let unique = Array(NSOrderedSet(array: urls)) as? [String] ?? urls
        return unique.max { score($0) < score($1) }
    }

    private static func score(_ url: String) -> Int {
        let lower = url.lowercased()
        if lower.contains("//vine.co/") || lower.contains("//www.vine.co/") { return -1 }
        if lower.contains(".mp4") { return 100 }
        if lower.contains("video/mp4") { return 90 }
        if lower.contains(".m3u8") { return 60 }
        if lower.contains("divine.video") || lower.contains("openvine.co") { return 50 }
        return 10
    }
}

enum RokunanaVideoKinds {
    /// OpenVine/diVine discovery uses only kind 34236.
    static let addressableShortVideo = NostrKind.videoLoop
    static let discoveryKinds = [addressableShortVideo]

    /// Accepted when parsing referenced videos from outside diVine.
    static let acceptableVideoKinds = [22, 21, 34235, 34236, 34237]
}

enum RokunanaRelays {
    /// divine-mobile/OpenVine default relay.
    static let primary = "wss://relay.divine.video"
    /// Older tests and staging data in divine-mobile reference this relay.
    static let staging = "wss://staging-relay.divine.video"

    /// Read/write targets for the dedicated tab. Keep the production relay first.
    static let readWrite = [primary]
}
