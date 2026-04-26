import SwiftUI

// MARK: - Badge Cache
// Top-level module cache — mirrors Android's top-level `badgeCache` map.

private var badgeCache: [String: [String]] = [:]

func clearBadgeCache(pubkey: String) {
    badgeCache.removeValue(forKey: pubkey)
}

// MARK: - BadgeDisplay

/// NIP-58 badge images (max 3, 16×16pt) in a horizontal row.
/// Mirrors Android BadgeDisplay composable — self-contained, loads automatically.
struct BadgeDisplay: View {
    let pubkey:        String
    let repository:    NostrRepository
    var maxBadges:     Int      = 3
    var initialBadges: [String] = []

    @State private var badgeUrls: [String] = []
    @State private var hasFetched: Bool = false

    /// initialBadges のハッシュ値を追跡して再レンダリングを検知するためのキー
    private var badgeKey: String {
        pubkey + "_" + initialBadges.joined(separator: ",")
    }

    var body: some View {
        Group {
            if !displayUrls.isEmpty {
                HStack(spacing: 4) {
                    ForEach(displayUrls, id: \.self) { url in
                        AsyncImage(url: URL(string: url)) { phase in
                            if case .success(let img) = phase {
                                img.resizable().scaledToFit()
                            }
                        }
                        .frame(width: 16, height: 16)
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                    }
                }
            }
        }
        // pubkey + initialBadges の組み合わせが変わったら再実行
        .task(id: badgeKey) {
            // Prefer pre-fetched initialBadges (mirrors Android's initialBadges param)
            if !initialBadges.isEmpty {
                badgeUrls = Array(initialBadges.prefix(maxBadges))
                badgeCache[pubkey] = initialBadges
                return
            }
            // Return from cache without network round-trip
            if let cached = badgeCache[pubkey], !cached.isEmpty {
                badgeUrls = Array(cached.prefix(maxBadges))
                return
            }
            // Fetch from repository
            guard !hasFetched else { return }
            hasFetched = true
            let badges = await repository.fetchBadges(pubkeyHex: pubkey)
            let urls = badges.compactMap { $0.imageUrl }
            badgeUrls = Array(urls.prefix(maxBadges))
            badgeCache[pubkey] = urls
        }
    }

    /// 表示用 URL: initialBadges が優先、なければ badgeUrls
    private var displayUrls: [String] {
        let source = !initialBadges.isEmpty ? initialBadges : badgeUrls
        return Array(source.prefix(maxBadges))
    }
}
