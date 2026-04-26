import Foundation

/// Feed scoring engine. Mirrors rust-engine/nurunuru-core/src/recommendation.rs.
struct RecommendationEngine {
    let config: RecommendationConfig

    init(config: RecommendationConfig = .init()) {
        self.config = config
    }

    func timeDecay(createdAt: Int64, now: Date = Date()) -> Double {
        let ageHours = max(0, now.timeIntervalSince1970 - TimeInterval(createdAt)) / 3600.0
        let td = config.timeDecay

        if ageHours < 1.0 {
            return td.freshnessBoost
        }
        if ageHours > td.maxAgeHours {
            return td.minScore
        }

        return pow(0.5, ageHours / td.halfLifeHours)
    }

    func engagementScore(_ data: RecommendationEngagementData) -> Double {
        let w = config.engagementWeights
        return Double(data.zaps) * w.zap
            + Double(data.replies) * w.reply
            + Double(data.reposts) * w.repost
            + Double(data.likes) * w.like
            + Double(data.quotes) * w.quote
            + 1.0
    }

    func socialBoost(
        authorPubkey: String,
        followList: Set<String>,
        secondDegree: Set<String>,
        followers: Set<String>,
        engagementHistory: RecommendationEngagementHistory
    ) -> Double {
        let sb = config.socialBoost
        let liked = Double(engagementHistory.likedAuthors[authorPubkey] ?? 0)
        let reposted = Double(engagementHistory.repostedAuthors[authorPubkey] ?? 0)
        let replied = Double(engagementHistory.repliedAuthors[authorPubkey] ?? 0)
        let totalEngagements = liked + reposted * 2.0 + replied * 3.0

        let engagementBoost: Double
        if totalEngagements >= 10.0 {
            engagementBoost = sb.highEngagementAuthor
        } else if totalEngagements >= 5.0 {
            engagementBoost = 1.5
        } else {
            engagementBoost = 1.0
        }

        if followList.contains(authorPubkey) {
            if followers.contains(authorPubkey) {
                return sb.mutualFollow * engagementBoost
            }
            return sb.firstDegree * engagementBoost
        }

        if secondDegree.contains(authorPubkey) {
            return sb.secondDegree * engagementBoost
        }

        return sb.unknown * engagementBoost
    }

    func authorQuality(profile: UserProfile?, followerCount: Int) -> Double {
        var quality = 1.0

        if let nip05 = profile?.nip05, !nip05.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            quality *= 1.3
        }

        if followerCount > 0 {
            let followerBoost = 1.0 + log10(max(1.0, Double(followerCount))) * 0.1
            quality *= min(followerBoost, 1.5)
        }

        return quality
    }

    static func geohashBoost(userGeohash: String?, authorGeohash: String?) -> Double {
        guard let userGeohash, let authorGeohash else { return 1.0 }

        let commonPrefix = zip(userGeohash, authorGeohash)
            .prefix { lhs, rhs in lhs == rhs }
            .count

        if commonPrefix >= 5 { return 2.0 }
        if commonPrefix >= 3 { return 1.5 }
        if commonPrefix >= 2 { return 1.2 }
        return 1.0
    }

    func scorePost(
        _ post: ScoredPost,
        engagement: RecommendationEngagementData,
        followList: Set<String>,
        secondDegree: Set<String>,
        followers: Set<String>,
        engagementHistory: RecommendationEngagementHistory,
        profiles: [String: UserProfile],
        mutedPubkeys: Set<String>,
        notInterestedPosts: Set<String>,
        authorScores: [String: Double],
        userGeohash: String?,
        followerCount: Int
    ) -> Double? {
        if notInterestedPosts.contains(post.event.id) || mutedPubkeys.contains(post.event.pubkey) {
            return nil
        }

        let profile = profiles[post.event.pubkey] ?? post.profile
        let finalScore = engagementScore(engagement)
            * socialBoost(
                authorPubkey: post.event.pubkey,
                followList: followList,
                secondDegree: secondDegree,
                followers: followers,
                engagementHistory: engagementHistory
            )
            * authorQuality(profile: profile, followerCount: followerCount)
            * Self.geohashBoost(userGeohash: userGeohash, authorGeohash: profile?.geohash)
            * (authorScores[post.event.pubkey] ?? 1.0)
            * timeDecay(createdAt: post.event.createdAt)

        return finalScore > 0 ? finalScore : nil
    }

    func rankFeed(
        posts: [ScoredPost],
        engagements: [String: RecommendationEngagementData],
        followList: Set<String>,
        secondDegree: Set<String>,
        followers: Set<String>,
        engagementHistory: RecommendationEngagementHistory,
        profiles: [String: UserProfile],
        mutedPubkeys: Set<String>,
        notInterestedPosts: Set<String>,
        authorScores: [String: Double],
        userGeohash: String?,
        authorStats: [String: RecommendationAuthorStats],
        limit: Int
    ) -> [ScoredPost] {
        let scored: [ScoredPost] = posts.compactMap { post in
            let engagement = engagements[post.event.id] ?? RecommendationEngagementData()
            let followerCount = authorStats[post.event.pubkey]?.followerCount ?? 0
            guard let score = scorePost(
                post,
                engagement: engagement,
                followList: followList,
                secondDegree: secondDegree,
                followers: followers,
                engagementHistory: engagementHistory,
                profiles: profiles,
                mutedPubkeys: mutedPubkeys,
                notInterestedPosts: notInterestedPosts,
                authorScores: authorScores,
                userGeohash: userGeohash,
                followerCount: followerCount
            ) else {
                return nil
            }
            post.score = score
            return post
        }

        var secondDegreePosts: [ScoredPost] = []
        var outOfNetworkPosts: [ScoredPost] = []
        var firstDegreePosts: [ScoredPost] = []

        for post in scored {
            if secondDegree.contains(post.event.pubkey) {
                secondDegreePosts.append(post)
            } else if followList.contains(post.event.pubkey) {
                firstDegreePosts.append(post)
            } else {
                outOfNetworkPosts.append(post)
            }
        }

        let sortByScore: (ScoredPost, ScoredPost) -> Bool = { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.event.createdAt > rhs.event.createdAt
            }
            return lhs.score > rhs.score
        }

        secondDegreePosts.sort(by: sortByScore)
        outOfNetworkPosts.sort(by: sortByScore)
        firstDegreePosts.sort(by: sortByScore)

        let mix = config.feedMix
        let targetSecondDegree = min(secondDegreePosts.count, Int(Double(limit) * mix.secondDegree))
        let targetOutOfNetwork = min(outOfNetworkPosts.count, Int(Double(limit) * mix.outOfNetwork))
        let targetFirstDegree = min(firstDegreePosts.count, Int(Double(limit) * mix.firstDegree))

        var result: [ScoredPost] = []
        var seen = Set<String>()

        func appendUnique(_ candidates: ArraySlice<ScoredPost>) {
            for post in candidates where seen.insert(post.event.id).inserted {
                result.append(post)
            }
        }

        appendUnique(secondDegreePosts.prefix(targetSecondDegree))
        appendUnique(outOfNetworkPosts.prefix(targetOutOfNetwork))
        appendUnique(firstDegreePosts.prefix(targetFirstDegree))

        if result.count < limit {
            for post in scored.sorted(by: sortByScore) where seen.insert(post.event.id).inserted {
                result.append(post)
                if result.count >= limit { break }
            }
        }

        result.sort(by: sortByScore)
        if result.count > limit {
            result.removeLast(result.count - limit)
        }
        return result
    }

    static func extract2ndDegreeNetwork(
        myFollows: Set<String>,
        followsOfFollows: [String: [String]]
    ) -> Set<String> {
        var secondDegree = Set<String>()

        for (follower, theirFollows) in followsOfFollows where myFollows.contains(follower) {
            for pubkey in theirFollows where !myFollows.contains(pubkey) {
                secondDegree.insert(pubkey)
            }
        }

        return secondDegree
    }
}
