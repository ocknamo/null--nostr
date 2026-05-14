// App Store submission build: ろくなな / diVine short-video feature is disabled for App Store submission.
// The original implementation is intentionally commented out via `#if false`.
#if false
import Foundation
import Observation
import AVFoundation
import UIKit

@MainActor
@Observable
final class RokunanaViewModel {
    private let repository: NostrRepository
    private let pubkeyHex: String

    var mode: RokunanaFeedMode = .recommended
    var posts: [ScoredPost] = []
    var isLoading = false
    var isPublishing = false
    private var inFlightLikeEventIds: Set<String> = []
    private var inFlightRepostEventIds: Set<String> = []
    var errorMessage: String? = nil
    var selectedCategory = "すべて"

    let categories = ["すべて", "モッパン", "マンガ", "面白"]

    var myPubkeyHex: String { pubkeyHex }

    init(repository: NostrRepository, pubkeyHex: String) {
        self.repository = repository
        self.pubkeyHex = pubkeyHex
    }

    func startInitialLoadIfNeeded() {
        guard posts.isEmpty, !isLoading else { return }
        Task { await refresh() }
    }

    func refresh() async {
        isLoading = true
        errorMessage = nil
        let mode = mode
        let fetched = await repository.fetchRokunanaVideos(mode: mode, limit: 40)
        posts = fetched
        isLoading = false
    }

    func setMode(_ newMode: RokunanaFeedMode) {
        guard mode != newMode else { return }
        mode = newMode
        Task { await refresh() }
    }

    func toggleLike(post: ScoredPost) async {
        let eventId = post.event.id
        guard !inFlightLikeEventIds.contains(eventId) else { return }
        inFlightLikeEventIds.insert(eventId)
        defer { inFlightLikeEventIds.remove(eventId) }
        let wasLiked = post.isLiked
        post.isLiked = !wasLiked
        post.likeCount += wasLiked ? -1 : 1
        do {
            if wasLiked, let likeId = post.myLikeEventId {
                try await repository.publishDelete(eventId: likeId)
                post.myLikeEventId = nil
            } else {
                try await repository.publishReaction(to: post.event.id, authorPubkey: post.event.pubkey)
            }
        } catch {
            post.isLiked = wasLiked
            post.likeCount += wasLiked ? 1 : -1
            errorMessage = "リアクションに失敗しました"
        }
    }

    func toggleRepost(post: ScoredPost) async {
        let eventId = post.event.id
        guard !inFlightRepostEventIds.contains(eventId) else { return }
        inFlightRepostEventIds.insert(eventId)
        defer { inFlightRepostEventIds.remove(eventId) }
        let wasReposted = post.isReposted
        post.isReposted = !wasReposted
        post.repostCount += wasReposted ? -1 : 1
        do {
            if wasReposted {
                if let repostId = post.myRepostEventId {
                    try await repository.publishDelete(eventId: repostId)
                    post.myRepostEventId = nil
                }
            } else {
                let event = try await repository.publishRepostAndReturn(event: post.event)
                post.myRepostEventId = event.id
            }
        } catch {
            post.isReposted = wasReposted
            post.repostCount += wasReposted ? 1 : -1
            errorMessage = "リポストに失敗しました"
        }
    }

    func toggleBookmark(post: ScoredPost) async {
        let wasBookmarked = post.isBookmarked
        post.isBookmarked = !wasBookmarked
        do {
            if wasBookmarked {
                try await repository.removeBookmark(pubkeyHex: pubkeyHex, eventId: post.event.id)
            } else {
                try await repository.addBookmark(pubkeyHex: pubkeyHex, eventId: post.event.id)
            }
        } catch {
            post.isBookmarked = wasBookmarked
            errorMessage = "ブックマークに失敗しました"
        }
    }


    func notInterested(post: ScoredPost) {
        posts.removeAll { $0.event.id == post.event.id }
    }

    func deletePost(_ post: ScoredPost) async {
        posts.removeAll { $0.event.id == post.event.id }
        try? await repository.publishDelete(eventId: post.event.id)
    }

    func muteUser(_ pubkeyHex: String) async {
        posts.removeAll { $0.event.pubkey == pubkeyHex }
        try? await repository.muteUser(pubkeyHex: pubkeyHex, isPrivate: true)
    }

    func reportEvent(post: ScoredPost, type: String, content: String) async {
        let tags: [[String]] = [["e", post.event.id, type], ["p", post.event.pubkey]]
        try? await repository.publishEvent(kind: NostrKind.report, tags: tags, content: content)
    }

    func submitBirdwatch(post: ScoredPost, type: String, content: String, url: String) async {
        _ = try? await repository.publishBirdwatchNote(
            targetEventId: post.event.id,
            content: content,
            contextType: type,
            sourceUrl: url.isEmpty ? nil : url
        )
    }

    func publishVideo(data: Data?, title: String, summary: String, hashtagsText: String) async {
        guard let data else { return }
        isPublishing = true
        errorMessage = nil
        do {
            let trimmedData = try await Self.trimVideoToRokunanaLengthIfNeeded(data)
            let meta = try await Self.videoMetadata(from: trimmedData)
            let hashtags = hashtagsText
                .split(separator: " ")
                .map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: "# ")) }
                .filter { !$0.isEmpty }
            let event = try await repository.publishRokunanaVideo(
                videoData: trimmedData,
                title: title,
                summary: summary,
                thumbnailData: meta.thumbnailData,
                duration: meta.duration,
                dimensions: meta.dimensions,
                hashtags: hashtags
            )
            let post = ScoredPost(event: event)
            posts.insert(post, at: 0)
        } catch {
            errorMessage = "動画投稿に失敗しました: \(error.localizedDescription)"
        }
        isPublishing = false
    }

    /// Normalize selected/recorded clips to an MP4 capped at 6.7 seconds.
    private static func trimVideoToRokunanaLengthIfNeeded(_ data: Data) async throws -> Data {
        let inputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("rokunana-input-\(UUID().uuidString).mov")
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("rokunana-trimmed-\(UUID().uuidString).mp4")
        try data.write(to: inputURL, options: .atomic)
        defer {
            try? FileManager.default.removeItem(at: inputURL)
            try? FileManager.default.removeItem(at: outputURL)
        }

        let asset = AVURLAsset(url: inputURL)
        let durationSeconds = (try? await asset.load(.duration).seconds) ?? 0
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            return data
        }

        export.outputURL = outputURL
        export.outputFileType = .mp4
        let cappedDuration = max(0.1, min(durationSeconds.isFinite ? durationSeconds : 6.7, 6.7))
        export.timeRange = CMTimeRange(
            start: .zero,
            duration: CMTime(seconds: cappedDuration, preferredTimescale: 600)
        )

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            export.exportAsynchronously {
                if let error = export.error {
                    continuation.resume(throwing: error)
                } else if export.status == .completed {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: RokunanaPublishError.videoLoadFailed)
                }
            }
        }

        return try Data(contentsOf: outputURL)
    }

    private static func videoMetadata(from data: Data) async throws -> (duration: Int?, dimensions: CGSize?, thumbnailData: Data?) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("rokunana-\(UUID().uuidString).mp4")
        try data.write(to: url, options: .atomic)
        defer { try? FileManager.default.removeItem(at: url) }

        let asset = AVURLAsset(url: url)
        let durationSeconds = try? await asset.load(.duration).seconds
        let tracks = try? await asset.loadTracks(withMediaType: .video)
        var size: CGSize? = nil
        if let firstTrack = tracks?.first {
            size = try? await firstTrack.load(.naturalSize)
        }

        var thumbnailData: Data? = nil
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        if let cgImage = try? generator.copyCGImage(at: CMTime(seconds: 0, preferredTimescale: 600), actualTime: nil) {
            thumbnailData = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.82)
        }

        return (
            duration: durationSeconds.flatMap { $0.isFinite ? Int($0.rounded()) : nil },
            dimensions: size,
            thumbnailData: thumbnailData
        )
    }
}

enum RokunanaPublishError: LocalizedError {
    case videoLoadFailed

    var errorDescription: String? {
        switch self {
        case .videoLoadFailed: return "動画を読み込めませんでした"
        }
    }
}

#endif
