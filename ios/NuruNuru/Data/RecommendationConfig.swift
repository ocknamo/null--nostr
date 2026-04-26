import Foundation

/// Recommendation scoring weights and mix ratios.
/// Mirrors rust-engine/nurunuru-core/src/config.rs defaults.
struct RecommendationConfig {
    let engagementWeights = RecommendationEngagementWeights()
    let socialBoost = RecommendationSocialBoostConfig()
    let timeDecay = RecommendationTimeDecayConfig()
    let feedMix = RecommendationFeedMixRatio()
}

struct RecommendationEngagementWeights {
    let zap: Double = 100.0
    let reply: Double = 30.0
    let repost: Double = 25.0
    let like: Double = 5.0
    let quote: Double = 35.0
    let bookmark: Double = 15.0
}

struct RecommendationSocialBoostConfig {
    let secondDegree: Double = 3.0
    let mutualFollow: Double = 2.5
    let highEngagementAuthor: Double = 2.0
    let firstDegree: Double = 0.5
    let unknown: Double = 1.0
}

struct RecommendationTimeDecayConfig {
    let halfLifeHours: Double = 6.0
    let maxAgeHours: Double = 48.0
    let freshnessBoost: Double = 1.5
    let minScore: Double = 0.1
}

struct RecommendationFeedMixRatio {
    let secondDegree: Double = 0.50
    let outOfNetwork: Double = 0.30
    let firstDegree: Double = 0.20
}

struct RecommendationEngagementData: Codable, Equatable {
    var likes: Int = 0
    var reposts: Int = 0
    var replies: Int = 0
    var zaps: Int = 0
    var quotes: Int = 0
}

struct RecommendationAuthorStats: Codable, Equatable {
    var followerCount: Int = 0
}

struct RecommendationEngagementHistory: Codable, Equatable {
    var likedAuthors: [String: Int] = [:]
    var repostedAuthors: [String: Int] = [:]
    var repliedAuthors: [String: Int] = [:]
}

enum RecommendationEngagementType {
    case like
    case repost
    case reply
}
