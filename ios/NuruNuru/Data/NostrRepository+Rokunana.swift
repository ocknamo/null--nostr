// App Store submission build: ろくなな / diVine short-video feature is disabled for App Store submission.
// The original implementation is intentionally commented out via `#if false`.
#if false
import Foundation
import CryptoKit
import AVFoundation
import UIKit

// MARK: - ろくなな / diVine compatible short video support

extension NostrRepository {

    /// Fetch diVine/OpenVine compatible short videos from the dedicated divine relay.
    func fetchRokunanaVideos(mode: RokunanaFeedMode = .recommended, limit: Int = 30) async -> [ScoredPost] {
        var filter = NostrFilter()
        filter.kinds = RokunanaVideoKinds.discoveryKinds
        filter.limit = limit
        filter.since = Int64(Date().addingTimeInterval(-86400 * 14).timeIntervalSince1970)

        if mode == .following, let myPubkey = prefs.publicKeyHex {
            let follows = await fetchFollowList(pubkey: myPubkey)
            if !follows.isEmpty { filter.authors = follows }
        }

        var rawEvents: [NostrEvent] = []
        for relay in RokunanaRelays.readWrite {
            rawEvents += await client.fetchEventsFromRelay(relay, filters: [filter], timeoutSeconds: 7.0)
        }

        var seen = Set<String>()
        var posts = rawEvents
            .filter { seen.insert($0.id).inserted }
            .compactMap { event -> ScoredPost? in
                guard RokunanaVideo(event: event) != nil else { return nil }
                return ScoredPost(event: event)
            }
            .sorted { $0.event.createdAt > $1.event.createdAt }

        await enrichPosts(&posts)
        return posts
    }

    /// Publish a kind-34236 NIP-71 / diVine compatible short video.
    ///
    /// The uploaded media is stored using the existing Blossom/NIP-98 upload path.
    /// The resulting Nostr event follows the observed diVine shape:
    /// d + imeta(url/m/image/dim/size/x) + title/summary + language + client +
    /// published_at + duration + alt + allow_audio_reuse.
    @discardableResult
    func publishRokunanaVideo(
        videoData: Data,
        title: String,
        summary: String,
        thumbnailData: Data? = nil,
        duration: Int? = nil,
        dimensions: CGSize? = nil,
        hashtags: [String] = []
    ) async throws -> NostrEvent {
        let uploadService = ImageUploadService(signer: signer)
        let videoHash = SHA256.hash(data: videoData).map { String(format: "%02x", $0) }.joined()
        let dTag = videoHash
        let videoUrl = try await uploadService.uploadImage(
            imageData: videoData,
            server: .blossom,
            blossomBaseUrl: "https://blossom.primal.net",
            mimeType: "video/mp4"
        )

        var thumbUrl: String? = nil
        if let thumbnailData {
            thumbUrl = try? await uploadService.uploadImage(
                imageData: thumbnailData,
                server: .blossom,
                blossomBaseUrl: "https://blossom.nostr.build",
                mimeType: "image/jpeg"
            )
        }

        let now = Int64(Date().timeIntervalSince1970)
        var imeta = [
            "imeta",
            "url \(videoUrl)",
            "m video/mp4"
        ]
        if let thumbUrl { imeta.append("image \(thumbUrl)") }
        if let dimensions {
            imeta.append("dim \(Int(dimensions.width))x\(Int(dimensions.height))")
        }
        imeta.append("size \(videoData.count)")
        imeta.append("x \(videoHash)")

        var tags: [[String]] = [
            ["d", dTag],
            imeta,
            ["title", title],
            ["summary", summary],
            ["L", "ISO-639-1"],
            ["l", "ja", "ISO-639-1"],
            ["client", "diVine"],
            ["published_at", "\(now)"],
            ["alt", title.isEmpty ? summary : title],
            ["allow_audio_reuse", "true"]
        ]
        if let duration { tags.append(["duration", "\(duration)"]) }
        for tag in hashtags.map({ $0.trimmingCharacters(in: CharacterSet(charactersIn: "# ")) }).filter({ !$0.isEmpty }) {
            tags.append(["t", tag])
        }

        let content = summary.isEmpty ? title : summary
        let event = try signer.signEvent(kind: NostrKind.videoLoop, tags: tags, content: content)
        try await publishSignedEvent(event, to: RokunanaRelays.readWrite)
        return event
    }

    /// Publish a signed event to explicit relays (used for divine relay write path).
    func publishSignedEvent(_ event: NostrEvent, to relays: [String]) async throws {
        let data = try JSONEncoder().encode(event)
        guard let json = String(data: data, encoding: .utf8) else {
            throw NostrClient.ClientError.invalidMessage
        }
        try await client.publishRawEventJSON(json, to: relays, waitForAllRelays: false)
    }
}

enum RokunanaFeedMode: String, CaseIterable, Identifiable {
    case recommended
    case following

    var id: String { rawValue }
    var label: String {
        switch self {
        case .recommended: return "おすすめ"
        case .following: return "フォロー中"
        }
    }
}

#endif
