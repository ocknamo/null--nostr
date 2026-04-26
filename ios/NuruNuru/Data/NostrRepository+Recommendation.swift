import Foundation

extension NostrRepository {
    private enum RecommendationStorageKeys {
        static let notInterestedPosts = "nurunuru_not_interested"
        static let authorScores = "nurunuru_not_interested_authors"
        static let engagementHistory = "nurunuru_engagement_history"
    }

    func getNotInterestedPosts() -> Set<String> {
        guard let data = UserDefaults.standard.data(forKey: RecommendationStorageKeys.notInterestedPosts),
              let ids = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return Set(ids)
    }

    func getAuthorScores() -> [String: Double] {
        guard let data = UserDefaults.standard.data(forKey: RecommendationStorageKeys.authorScores),
              let scores = try? JSONDecoder().decode([String: Double].self, from: data) else {
            return [:]
        }
        return scores
    }

    func getEngagementHistory() -> RecommendationEngagementHistory {
        guard let data = UserDefaults.standard.data(forKey: RecommendationStorageKeys.engagementHistory),
              let history = try? JSONDecoder().decode(RecommendationEngagementHistory.self, from: data) else {
            return RecommendationEngagementHistory()
        }
        return history
    }

    func recordEngagement(type: RecommendationEngagementType, authorPubkey: String) {
        var history = getEngagementHistory()
        switch type {
        case .like:
            history.likedAuthors[authorPubkey, default: 0] += 1
            history.likedAuthors = trimTopEntries(history.likedAuthors, limit: 500)
        case .repost:
            history.repostedAuthors[authorPubkey, default: 0] += 1
            history.repostedAuthors = trimTopEntries(history.repostedAuthors, limit: 500)
        case .reply:
            history.repliedAuthors[authorPubkey, default: 0] += 1
            history.repliedAuthors = trimTopEntries(history.repliedAuthors, limit: 500)
        }
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: RecommendationStorageKeys.engagementHistory)
        }
    }

    func markNotInterested(eventId: String, authorPubkey: String) {
        var notInterested = Array(getNotInterestedPosts())
        if !notInterested.contains(eventId) {
            notInterested.append(eventId)
        }
        if notInterested.count > 500 {
            notInterested.removeFirst(notInterested.count - 500)
        }
        if let data = try? JSONEncoder().encode(notInterested) {
            UserDefaults.standard.set(data, forKey: RecommendationStorageKeys.notInterestedPosts)
        }

        var scores = getAuthorScores()
        let currentScore = scores[authorPubkey] ?? 1.0
        scores[authorPubkey] = max(0.1, currentScore * 0.7)
        scores = trimLowestPriorityAuthorScores(scores, limit: 200)
        if let data = try? JSONEncoder().encode(scores) {
            UserDefaults.standard.set(data, forKey: RecommendationStorageKeys.authorScores)
        }
    }

    func clearRecommendationData() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: RecommendationStorageKeys.notInterestedPosts)
        defaults.removeObject(forKey: RecommendationStorageKeys.authorScores)
        defaults.removeObject(forKey: RecommendationStorageKeys.engagementHistory)
    }

    func fetchRecommendedTimeline(limit: Int = 50) async -> [ScoredPost] {
        let engine = RecommendationEngine()
        guard let myPubkey = prefs.publicKeyHex else {
            let globalPosts = await fetchGlobalTimeline(limit: limit)
            return engine.rankFeed(
                posts: globalPosts,
                engagements: [:],
                followList: [],
                secondDegree: [],
                followers: [],
                engagementHistory: getEngagementHistory(),
                profiles: [:],
                mutedPubkeys: [],
                notInterestedPosts: getNotInterestedPosts(),
                authorScores: getAuthorScores(),
                userGeohash: prefs.userGeohash,
                authorStats: [:],
                limit: limit
            )
        }

        let followArray = await fetchFollowList(pubkey: myPubkey)
        let followSet = Set(followArray)

        async let followsOfFollowsTask = fetchFollowsOfFollows(for: followArray)
        async let followersTask = fetchFollowers(of: myPubkey)
        async let mutedTask = fetchMuteList(pubkeyHex: myPubkey)
        async let networkPostsTask = fetchRecommendationNetworkPosts(follows: followArray, limit: max(limit * 2, 80))
        async let viralPostsTask = fetchRecommendationOutOfNetworkPosts(limit: max(limit * 2, 80))

        let followsOfFollows = await followsOfFollowsTask
        let secondDegree = RecommendationEngine.extract2ndDegreeNetwork(myFollows: followSet, followsOfFollows: followsOfFollows)
        let followers = await followersTask
        let muteLists = await mutedTask

        var candidatePosts = await networkPostsTask + viralPostsTask
        candidatePosts = dedupePostsByEventId(candidatePosts)
        guard !candidatePosts.isEmpty else { return [] }

        let candidateEventIds = candidatePosts.map { $0.event.id }
        let authorPubkeys = Array(Set(candidatePosts.map { $0.event.pubkey }))
        async let profilesTask = fetchProfiles(pubkeys: authorPubkeys)
        async let engagementsTask = fetchRecommendationEngagements(eventIds: candidateEventIds)
        async let authorStatsTask = fetchRecommendationAuthorStats(pubkeys: authorPubkeys)

        let profiles = await profilesTask
        let profileMap = Dictionary(profiles.map { ($0.pubkey, $0) }, uniquingKeysWith: { first, _ in first })
        let engagements = await engagementsTask
        let authorStats = await authorStatsTask
        let mutedPubkeys = Set(muteLists.publicMutes).union(muteLists.privateMutes)

        return engine.rankFeed(
            posts: candidatePosts,
            engagements: engagements,
            followList: followSet,
            secondDegree: secondDegree,
            followers: followers,
            engagementHistory: getEngagementHistory(),
            profiles: profileMap,
            mutedPubkeys: mutedPubkeys,
            notInterestedPosts: getNotInterestedPosts(),
            authorScores: getAuthorScores(),
            userGeohash: prefs.userGeohash,
            authorStats: authorStats,
            limit: limit
        )
    }

    private func fetchRecommendationNetworkPosts(follows: [String], limit: Int) async -> [ScoredPost] {
        guard !follows.isEmpty else { return [] }
        let since = Int64(Date().addingTimeInterval(-86400 * 2).timeIntervalSince1970)
        let kinds = [NostrKind.textNote, NostrKind.longForm, NostrKind.repost]
        let filter = NostrFilter(authors: follows, kinds: kinds, since: since, limit: limit)
        let events = await fetchEvents(filters: [filter], timeoutSeconds: 8.0)
            .filter { kinds.contains($0.kind) }
            .sorted { $0.createdAt > $1.createdAt }
        var posts = recommendationUnwrapRepostEvents(events)
        await enrichPosts(&posts)
        return posts
    }

    private func fetchRecommendationOutOfNetworkPosts(limit: Int) async -> [ScoredPost] {
        let since = Int64(Date().addingTimeInterval(-3600).timeIntervalSince1970)
        let kinds = [NostrKind.textNote, NostrKind.longForm, NostrKind.repost]
        let filter = NostrFilter(kinds: kinds, since: since, limit: limit)
        let events = await fetchEvents(filters: [filter], timeoutSeconds: 8.0)
            .filter { kinds.contains($0.kind) }
            .sorted { $0.createdAt > $1.createdAt }
        var posts = recommendationUnwrapRepostEvents(events)
        await enrichPosts(&posts)
        return posts
    }

    private func fetchFollowers(of pubkey: String) async -> Set<String> {
        let filter = NostrFilter(kinds: [NostrKind.contactList], limit: 500, tags: ["#p": [pubkey]])
        let events = await fetchEvents(filters: [filter], timeoutSeconds: 5.0)
        return Set(events.map(\.pubkey))
    }

    private func fetchFollowsOfFollows(for follows: [String]) async -> [String: [String]] {
        guard !follows.isEmpty else { return [:] }
        let filter = NostrFilter(authors: follows, kinds: [NostrKind.contactList], limit: follows.count)
        let events = await fetchEvents(filters: [filter], timeoutSeconds: 5.0)
        var latestByPubkey: [String: NostrEvent] = [:]
        for event in events where (latestByPubkey[event.pubkey]?.createdAt ?? 0) < event.createdAt {
            latestByPubkey[event.pubkey] = event
        }
        return latestByPubkey.mapValues { event in
            event.tags.filter { $0.first == "p" }.compactMap { $0.dropFirst().first }
        }
    }

    private func fetchRecommendationEngagements(eventIds: [String]) async -> [String: RecommendationEngagementData] {
        let ids = Array(Set(eventIds))
        guard !ids.isEmpty else { return [:] }

        enum FetchResult {
            case reactions([NostrEvent])
            case reposts([NostrEvent])
            case textNotes([NostrEvent])
            case zaps([NostrEvent])
        }

        var reactions: [NostrEvent] = []
        var reposts: [NostrEvent] = []
        var textNotes: [NostrEvent] = []
        var zaps: [NostrEvent] = []

        await withTaskGroup(of: FetchResult.self) { group in
            group.addTask { .reactions(await self.fetchRecommendationReactionEvents(eventIds: ids)) }
            group.addTask { .reposts(await self.fetchRecommendationRepostEvents(eventIds: ids)) }
            group.addTask {
                let filters = [
                    NostrFilter(kinds: [NostrKind.textNote], limit: 1000, tags: ["#e": ids]),
                    NostrFilter(kinds: [NostrKind.textNote], limit: 1000, tags: ["#q": ids])
                ]
                return .textNotes(await self.fetchEvents(filters: filters, timeoutSeconds: 5.0))
            }
            group.addTask {
                let filter = NostrFilter(kinds: [NostrKind.zapReceipt], limit: 500, tags: ["#e": ids])
                return .zaps(await self.fetchEvents(filters: [filter], timeoutSeconds: 5.0))
            }

            for await result in group {
                switch result {
                case .reactions(let value): reactions = value
                case .reposts(let value): reposts = value
                case .textNotes(let value): textNotes = value
                case .zaps(let value): zaps = value
                }
            }
        }

        var engagement = Dictionary(uniqueKeysWithValues: ids.map { ($0, RecommendationEngagementData()) })

        for event in reactions {
            guard let targetId = event.getTagValue("e") else { continue }
            engagement[targetId, default: RecommendationEngagementData()].likes += 1
        }

        for event in reposts {
            guard let targetId = event.getTagValue("e") else { continue }
            engagement[targetId, default: RecommendationEngagementData()].reposts += 1
        }

        for event in zaps {
            guard let targetId = event.getTagValue("e") else { continue }
            engagement[targetId, default: RecommendationEngagementData()].zaps += 1
        }

        for event in textNotes {
            let referencedIds = Set(event.getTagValues("e") + event.getTagValues("q"))
            for targetId in referencedIds where ids.contains(targetId) {
                let isQuote = event.tags.contains { tag in
                    (tag.first == "q" && tag.dropFirst().first == targetId)
                    || (tag.first == "e" && tag.dropFirst().first == targetId && tag.count > 3 && tag[3] == "mention")
                }
                if isQuote {
                    engagement[targetId, default: RecommendationEngagementData()].quotes += 1
                } else {
                    engagement[targetId, default: RecommendationEngagementData()].replies += 1
                }
            }
        }

        return engagement
    }

    private func fetchRecommendationReactionEvents(eventIds: [String]) async -> [NostrEvent] {
        guard !eventIds.isEmpty else { return [] }
        let filter = NostrFilter(kinds: [NostrKind.reaction], limit: 500, tags: ["#e": eventIds])
        return await fetchEvents(filters: [filter], timeoutSeconds: 3.0)
    }

    private func fetchRecommendationRepostEvents(eventIds: [String]) async -> [NostrEvent] {
        guard !eventIds.isEmpty else { return [] }
        let filter = NostrFilter(kinds: [NostrKind.repost], limit: 500, tags: ["#e": eventIds])
        return await fetchEvents(filters: [filter], timeoutSeconds: 3.0)
    }

    private func recommendationUnwrapRepostEvents(_ events: [NostrEvent]) -> [ScoredPost] {
        var posts: [ScoredPost] = []
        var seenIds = Set<String>()

        for event in events {
            if event.kind == NostrKind.repost {
                if let data = event.content.data(using: .utf8),
                   let inner = try? JSONDecoder().decode(NostrEvent.self, from: data),
                   inner.kind == NostrKind.textNote || inner.kind == NostrKind.longForm {
                    guard seenIds.insert(inner.id).inserted else { continue }
                    let post = ScoredPost(event: inner)
                    post.repostedBy = UserProfile(pubkey: event.pubkey)
                    post.repostTime = event.createdAt
                    posts.append(post)
                }
            } else {
                guard seenIds.insert(event.id).inserted else { continue }
                posts.append(ScoredPost(event: event))
            }
        }

        return posts
    }

    private func fetchRecommendationAuthorStats(pubkeys: [String]) async -> [String: RecommendationAuthorStats] {
        let authors = Array(Set(pubkeys))
        guard !authors.isEmpty else { return [:] }
        let filter = NostrFilter(kinds: [NostrKind.contactList], limit: 2000, tags: ["#p": authors])
        let events = await fetchEvents(filters: [filter], timeoutSeconds: 6.0)
        var stats = Dictionary(uniqueKeysWithValues: authors.map { ($0, RecommendationAuthorStats()) })

        for event in events {
            let targets = Set(event.tags.filter { $0.first == "p" }.compactMap { $0.dropFirst().first })
            for target in targets where authors.contains(target) {
                stats[target, default: RecommendationAuthorStats()].followerCount += 1
            }
        }

        return stats
    }

    private func dedupePostsByEventId(_ posts: [ScoredPost]) -> [ScoredPost] {
        var seen = Set<String>()
        return posts.filter { seen.insert($0.event.id).inserted }
    }

    private func trimTopEntries(_ source: [String: Int], limit: Int) -> [String: Int] {
        Dictionary(
            uniqueKeysWithValues: source
                .sorted { lhs, rhs in
                    if lhs.value == rhs.value { return lhs.key < rhs.key }
                    return lhs.value > rhs.value
                }
                .prefix(limit)
                .map { ($0.key, $0.value) }
        )
    }

    private func trimLowestPriorityAuthorScores(_ source: [String: Double], limit: Int) -> [String: Double] {
        Dictionary(
            uniqueKeysWithValues: source
                .sorted { lhs, rhs in
                    if lhs.value == rhs.value { return lhs.key < rhs.key }
                    return lhs.value > rhs.value
                }
                .prefix(limit)
                .map { ($0.key, $0.value) }
        )
    }
}