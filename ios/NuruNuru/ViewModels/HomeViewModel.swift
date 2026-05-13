import Foundation
import Observation
import UIKit

extension Notification.Name {
    static let nuruHomePublishedPost = Notification.Name("nuruHomePublishedPost")
    static let nuruHomeLikedPost = Notification.Name("nuruHomeLikedPost")
    static let nuruHomeUnlikedPost = Notification.Name("nuruHomeUnlikedPost")
}

/// Profile screen state and logic.
/// Used for both own profile (HomeView) and other users (UserProfileSheet).
/// Mirrors Android HomeViewModel.
@Observable
@MainActor
final class HomeViewModel {

    // MARK: - State

    var profile:       UserProfile? = nil
    var posts:         [ScoredPost] = []
    var likedPosts:    [ScoredPost] = []
    var followList:    [String]     = []   // target user's follows
    var myFollowList:  [String]     = []   // own user's follows (for isFollowing check)
    var followCount:   Int          = 0
    var isLoading:     Bool         = false
    var isRefreshing:  Bool         = false
    var activeTab:     Int          = 0    // 0: 投稿, 1: いいね
    var isFollowing:   Bool         = false
    var isNip05Verified: Bool       = false   // mirrors Android uiState.isNip05Verified (Phase 2)
    var errorMessage:  String?      = nil
    /// NIP-58 badge image URLs — mirrors Android HomeViewModel.badgeUrls
    var badgeUrls:     [String]     = []

    // MARK: - Identity

    let myPubkeyHex:     String
    let targetPubkeyHex: String

    var isOwnProfile: Bool { targetPubkeyHex == myPubkeyHex }

    // MARK: - Dependencies

    private let repository: NostrRepository
    private var homeEventObserverTokens: [NSObjectProtocol] = []
    /// Locally acknowledged operations that may not be visible from relays yet.
    /// Keep these merged into Home across pull-to-refresh so optimistic rows do not disappear.
    private var pendingPublishedEvents: [String: NostrEvent] = [:]
    private var pendingLikedEvents:     [String: NostrEvent] = [:]
    private var pendingUnlikedEventIds: Set<String> = []

    // MARK: - Init

    init(repository: NostrRepository, myPubkeyHex: String, targetPubkeyHex: String? = nil) {
        self.repository      = repository
        self.myPubkeyHex     = myPubkeyHex
        self.targetPubkeyHex = targetPubkeyHex ?? myPubkeyHex
        installHomeEventObservers()
    }


    private func installHomeEventObservers() {
        let center = NotificationCenter.default
        homeEventObserverTokens.append(center.addObserver(
            forName: .nuruHomePublishedPost,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let event = notification.userInfo?["event"] as? NostrEvent else { return }
            Task { @MainActor in self.applyPublishedPost(event) }
        })
        homeEventObserverTokens.append(center.addObserver(
            forName: .nuruHomeLikedPost,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let event = notification.userInfo?["event"] as? NostrEvent else { return }
            Task { @MainActor in self.applyLikedPost(event) }
        })
        homeEventObserverTokens.append(center.addObserver(
            forName: .nuruHomeUnlikedPost,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let eventId = notification.userInfo?["eventId"] as? String else { return }
            Task { @MainActor in self.applyUnlikedPost(eventId: eventId) }
        })
    }

    func applyPublishedPost(_ event: NostrEvent) {
        guard isOwnProfile, event.pubkey == targetPubkeyHex else { return }
        pendingPublishedEvents[event.id] = event
        if posts.contains(where: { $0.event.id == event.id }) { return }
        let scored = makeScoredPost(event)
        posts.insert(scored, at: 0)
        AppLogger.log("HomeVM", "Optimistic home posts insert — id=\(event.id.prefix(8))")
    }

    func applyLikedPost(_ event: NostrEvent) {
        guard isOwnProfile else { return }
        pendingLikedEvents[event.id] = event
        pendingUnlikedEventIds.remove(event.id)
        if likedPosts.contains(where: { $0.event.id == event.id }) { return }
        let scored = makeScoredPost(event, preferExisting: true)
        scored.isLiked = true
        if scored.likeCount == 0 { scored.likeCount = max(scored.likeCount, 1) }
        likedPosts.insert(scored, at: 0)
        AppLogger.log("HomeVM", "Optimistic liked posts insert — id=\(event.id.prefix(8))")
    }

    func applyUnlikedPost(eventId: String) {
        guard isOwnProfile else { return }
        pendingLikedEvents.removeValue(forKey: eventId)
        pendingUnlikedEventIds.insert(eventId)
        likedPosts.removeAll { $0.event.id == eventId }
        AppLogger.log("HomeVM", "Optimistic liked posts remove — id=\(eventId.prefix(8))")
    }

    private func makeScoredPost(_ event: NostrEvent, preferExisting: Bool = false) -> ScoredPost {
        if preferExisting, let existing = (posts + likedPosts).first(where: { $0.event.id == event.id }) {
            // Do not overwrite the liked post author with my Home profile. If the
            // existing row still has no profile, resolve the profile for the
            // event author only.
            if existing.profile == nil {
                existing.profile = repository.getCachedProfile(pubkey: event.pubkey)
            }
            return existing
        }
        let scored = ScoredPost(event: event)
        // Only a newly published own post should use Home's own profile fallback.
        // Liked posts may be authored by someone else, so using the Home profile
        // here made the avatar/name appear as myself until enrichment completed.
        if event.pubkey == targetPubkeyHex {
            scored.profile = profile ?? repository.getCachedProfile(pubkey: event.pubkey)
        } else {
            scored.profile = repository.getCachedProfile(pubkey: event.pubkey)
        }
        return scored
    }

    private func mergePendingPosts(into base: [ScoredPost]) -> [ScoredPost] {
        guard isOwnProfile else { return base }
        var merged = base
        let existingIds = Set(merged.map { $0.event.id })
        let pending = pendingPublishedEvents.values
            .filter { !existingIds.contains($0.id) }
            .sorted { $0.createdAt > $1.createdAt }
            .map { makeScoredPost($0) }
        if !pending.isEmpty { merged.insert(contentsOf: pending, at: 0) }
        return merged.sorted { $0.event.createdAt > $1.event.createdAt }
    }

    private func mergePendingLikes(into base: [ScoredPost]) -> [ScoredPost] {
        guard isOwnProfile else { return base }
        var merged = base.filter { !pendingUnlikedEventIds.contains($0.event.id) }
        let existingIds = Set(merged.map { $0.event.id })
        let pending = pendingLikedEvents.values
            .filter { !existingIds.contains($0.id) }
            .sorted { $0.createdAt > $1.createdAt }
            .map { event -> ScoredPost in
                let scored = makeScoredPost(event, preferExisting: true)
                scored.isLiked = true
                if scored.likeCount == 0 { scored.likeCount = max(scored.likeCount, 1) }
                return scored
            }
        if !pending.isEmpty { merged.insert(contentsOf: pending, at: 0) }
        return merged
    }

    // MARK: - Load

    func loadProfile() async {
        // ── Cache-first: キャッシュからプロフィールを即時表示（Android HomeViewModel 同様） ──
        // nonisolated メソッドなので actor hop なしで即時返却。
        let cachedProfile = repository.getCachedProfile(pubkey: targetPubkeyHex)
        if let cached = cachedProfile {
            profile = cached
            // キャッシュがある場合はスケルトンを表示しない（Android 同様キャッシュファースト）
            AppLogger.log("HomeVM", "Cache-first: showing cached profile — banner=\(cached.banner ?? "nil")")
        } else {
            // キャッシュが空の場合のみローディング表示
            isLoading = true
        }


        // ── Cache-first posts/likes: avoid blank Home tabs on relay hiccups ──
        let cachedNotes = repository.getCachedUserNotes(pubkey: targetPubkeyHex)
        if !cachedNotes.isEmpty, posts.isEmpty {
            posts = cachedNotes.map { ScoredPost(event: $0) }
            AppLogger.log("HomeVM", "Cache-first: showing cached user notes — count=\(cachedNotes.count)")
        }
        let cachedLikes = repository.getCachedLikedEvents(pubkey: targetPubkeyHex)
        if !cachedLikes.isEmpty, likedPosts.isEmpty {
            likedPosts = cachedLikes.map { ScoredPost(event: $0) }
            AppLogger.log("HomeVM", "Cache-first: showing cached liked posts — count=\(cachedLikes.count)")
        }

        // グレース期間チェック（プロフィール編集直後はリレーデータで上書きしない）
        let inGracePeriod = isOwnProfile && repository.isProfileInGracePeriod(pubkey: targetPubkeyHex)

        // Profile, follow list, and badges in parallel — mirrors Android HomeViewModel async { }
        async let profileTask = repository.fetchProfile(pubkey: targetPubkeyHex)
        async let followTask  = repository.fetchFollowList(pubkey: targetPubkeyHex)
        async let badgesTask  = repository.fetchBadges(pubkeyHex: targetPubkeyHex)

        let (p, follows, badges) = await (profileTask, followTask, badgesTask)
        badgeUrls = badges.compactMap { $0.imageUrl }

        AppLogger.log("HomeVM", "fetchProfile result — banner=\(p?.banner ?? "nil"), name=\(p?.name ?? "nil")")

        if let fetched = p {
            if inGracePeriod, cachedProfile != nil {
                // グレース期間中: キャッシュ（編集後の最新データ）を維持し、リレーの古いデータを無視
                AppLogger.log("HomeVM", "Grace period: keeping cached profile (relay data ignored)")
            } else {
                // リレー/FFI のプロフィールにバナーがない場合、キャッシュから補完
                // （FFI や一部リレーはバナーを返さないことがある）
                if fetched.banner == nil, let cached = cachedProfile, cached.banner != nil {
                    let merged = UserProfile(
                        pubkey:      fetched.pubkey,
                        name:        fetched.name        ?? cached.name,
                        displayName: fetched.displayName ?? cached.displayName,
                        about:       fetched.about       ?? cached.about,
                        picture:     fetched.picture     ?? cached.picture,
                        nip05:       fetched.nip05       ?? cached.nip05,
                        banner:      cached.banner,
                        lud16:       fetched.lud16       ?? cached.lud16,
                        website:     fetched.website     ?? cached.website,
                        birthday:    fetched.birthday    ?? cached.birthday,
                        geohash:     fetched.geohash     ?? cached.geohash
                    )
                    profile = merged
                    AppLogger.log("HomeVM", "Merged profile (preserving cached banner)")
                } else {
                    profile = fetched
                }
            }
        }
        followList  = follows
        followCount = follows.count
        isLoading   = false   // show profile now; posts load below

        // Posts と likes を並列取得（Android: async { } で並列に対応）
        async let postsTask   = repository.fetchUserNotes(pubkey: targetPubkeyHex)
        async let likedTask   = repository.fetchLikedEvents(pubkey: targetPubkeyHex)
        let (postsEvents, likedEvents) = await (postsTask, likedTask)
        var resolvedPosts = mergePendingPosts(into: postsEvents.map { ScoredPost(event: $0) })
        var resolvedLikedPosts = mergePendingLikes(into: likedEvents.map { ScoredPost(event: $0) })

        if !resolvedPosts.isEmpty || posts.isEmpty {
            posts = resolvedPosts
            Task { [weak self, resolvedPosts] in
                guard let self else { return }
                var withQuotes = resolvedPosts
                await repository.resolveQuotedPosts(&withQuotes)
                let mergedWithPending = await MainActor.run { self.mergePendingPosts(into: withQuotes) }
                if await MainActor.run(body: { self.samePostIds(self.posts, resolvedPosts) || self.samePostIds(self.posts, mergedWithPending) }) {
                    await MainActor.run { self.posts = mergedWithPending }
                }
            }
        } else {
            AppLogger.log("HomeVM", "Keeping existing posts because refresh returned 0 events")
        }
        if !resolvedLikedPosts.isEmpty || likedPosts.isEmpty {
            likedPosts = resolvedLikedPosts
            Task { [weak self, resolvedLikedPosts] in
                guard let self else { return }
                var withQuotes = resolvedLikedPosts
                await repository.resolveQuotedPosts(&withQuotes)
                let mergedWithPending = await MainActor.run { self.mergePendingLikes(into: withQuotes) }
                if await MainActor.run(body: { self.samePostIds(self.likedPosts, resolvedLikedPosts) || self.samePostIds(self.likedPosts, mergedWithPending) }) {
                    await MainActor.run { self.likedPosts = mergedWithPending }
                }
            }
        } else {
            AppLogger.log("HomeVM", "Keeping existing liked posts because refresh returned 0 events")
        }

        // Determine isFollowing for other users.
        if !isOwnProfile {
            let myFollows = await repository.fetchFollowList(pubkey: myPubkeyHex)
            myFollowList  = myFollows
            isFollowing   = myFollows.contains(targetPubkeyHex)
        } else {
            myFollowList = follows
        }

        // NIP-05 検証 + プロフィールエンリッチメントを並列で実行（バックグラウンド）
        let fetchedProfile = p
        Task {
            if let nip05 = fetchedProfile?.nip05, !nip05.isEmpty {
                let resolvedPubkey = await repository.resolveNip05(nip05)
                isNip05Verified = (resolvedPubkey == targetPubkeyHex)
            }
        }
        // プロフィールエンリッチメント（1回のみ、重複回避）
        await enrichProfiles()
    }

    private func samePostIds(_ lhs: [ScoredPost], _ rhs: [ScoredPost]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).allSatisfy { $0.event.id == $1.event.id }
    }

    private func enrichProfiles() async {
        let all = posts + likedPosts
        guard !all.isEmpty else { return }
        let pubkeys = Array(Set(all.map { $0.event.pubkey }))

        // 1. キャッシュ済みプロフィールを即時適用（ネットワーク待ちなし）
        var profileMap: [String: UserProfile] = [:]
        var missingPubkeys: [String] = []
        for pk in pubkeys {
            if let cached = repository.getCachedProfile(pubkey: pk),
               cached.picture?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
               cached.displayedName.hasSuffix("...") == false {
                profileMap[pk] = cached
            } else {
                missingPubkeys.append(pk)
            }
        }

        // キャッシュ分を即時反映（アバター即時表示 — Android 同様）
        if !profileMap.isEmpty {
            for post in all {
                if post.profile == nil, let p = profileMap[post.event.pubkey] {
                    post.profile = p
                }
            }
            posts      = posts
            likedPosts = likedPosts
        }

        // 2. 未取得分のみリレーからフェッチ
        if !missingPubkeys.isEmpty {
            let fetched = await repository.fetchProfiles(pubkeys: missingPubkeys)
            for p in fetched { profileMap[p.pubkey] = p }
            for post in all {
                if let p = profileMap[post.event.pubkey] { post.profile = p }
            }
            posts      = posts
            likedPosts = likedPosts
        }

        // 3. NIP-05 検証状態と NIP-58 バッジを投稿一覧へ反映
        let authors = Array(Set(all.map { $0.event.pubkey }))
        var verificationMap: [String: Bool] = [:]
        var badgeMap: [String: [String]] = [:]

        for author in authors {
            if let nip05 = profileMap[author]?.nip05, !nip05.isEmpty {
                let resolved = await repository.resolveNip05(nip05)
                verificationMap[author] = (resolved == author)
            } else {
                verificationMap[author] = false
            }

            let badges = await repository.fetchBadges(pubkeyHex: author)
            badgeMap[author] = badges.compactMap { $0.imageUrl }
        }

        for post in all {
            let author = post.event.pubkey
            post.isVerified = verificationMap[author] ?? false
            post.badges = badgeMap[author] ?? []
        }

        posts      = posts
        likedPosts = likedPosts
    }

    // MARK: - Refresh

    func refresh() async {
        isRefreshing = true
        await loadProfile()
        isRefreshing = false
    }

    // MARK: - Follow / Unfollow

    func followUser() async {
        guard !isFollowing else { return }
        isFollowing  = true
        let newList  = myFollowList + [targetPubkeyHex]
        myFollowList = newList
        do {
            try await repository.publishFollowList(follows: newList)
        } catch {
            isFollowing  = false
            myFollowList = myFollowList.filter { $0 != targetPubkeyHex }
        }
    }

    func unfollowUser() async {
        guard isFollowing else { return }
        isFollowing  = false
        myFollowList = myFollowList.filter { $0 != targetPubkeyHex }
        do {
            try await repository.publishFollowList(follows: myFollowList)
        } catch {
            isFollowing  = true
            myFollowList = myFollowList + [targetPubkeyHex]
        }
    }

    // MARK: - Delete Post

    func deletePost(_ eventId: String) async {
        do {
            try await repository.publishDelete(eventId: eventId)
            posts      = posts.filter      { $0.event.id != eventId }
            likedPosts = likedPosts.filter { $0.event.id != eventId }
        } catch {
            errorMessage = "削除に失敗しました"
        }
    }

    // MARK: - Like (Kind 7, NIP-25) — mirrors Android HomeViewModel.likePost

    func likePost(_ eventId: String, emoji: String = "+", tags: [[String]] = []) {
        // Find the event's author pubkey from posts/likedPosts
        let all = posts + likedPosts
        guard let post = all.first(where: { $0.event.id == eventId }) else { return }
        let willLike = !post.isLiked
        // Optimistic UI update
        post.isLiked    = willLike
        post.likeCount += willLike ? 1 : -1
        if isOwnProfile {
            if willLike {
                applyLikedPost(post.event)
            } else {
                applyUnlikedPost(eventId: eventId)
            }
        }
        Task {
            do {
                if willLike {
                    try await repository.publishReaction(
                        to:          eventId,
                        authorPubkey: post.event.pubkey,
                        content:     emoji.isEmpty ? "+" : emoji
                    )
                    NotificationCenter.default.post(name: .nuruHomeLikedPost, object: nil, userInfo: ["event": post.event])
                } else if let likeId = post.myLikeEventId {
                    try await repository.publishDelete(eventId: likeId)
                    post.myLikeEventId = nil
                    NotificationCenter.default.post(name: .nuruHomeUnlikedPost, object: nil, userInfo: ["eventId": eventId])
                }
            } catch {
                // Revert on failure
                post.isLiked    = !post.isLiked
                post.likeCount += post.isLiked ? 1 : -1
                if self.isOwnProfile {
                    if willLike { self.applyUnlikedPost(eventId: eventId) }
                    else { self.applyLikedPost(post.event) }
                }
            }
        }
    }

    // MARK: - Repost (Kind 6, NIP-18) — mirrors Android HomeViewModel.repostPost

    func repostPost(_ eventId: String) {
        let all = posts + likedPosts
        guard let post = all.first(where: { $0.event.id == eventId }) else { return }
        post.isReposted    = !post.isReposted
        post.repostCount  += post.isReposted ? 1 : -1
        Task {
            do {
                if post.isReposted {
                    try await repository.publishRepost(event: post.event)
                } else if let repostId = post.myRepostEventId {
                    try await repository.publishDelete(eventId: repostId)
                    post.myRepostEventId = nil
                }
            } catch {
                post.isReposted    = !post.isReposted
                post.repostCount  += post.isReposted ? 1 : -1
            }
        }
    }

    // MARK: - Mute (Kind 10000, NIP-51) — mirrors Android HomeViewModel.muteUser

    func muteUser(_ pubkeyHex: String) {
        Task {
            try? await repository.muteUser(pubkeyHex: pubkeyHex, isPrivate: true)
            // Remove muted user's posts from feed
            posts      = posts.filter      { $0.event.pubkey != pubkeyHex }
            likedPosts = likedPosts.filter { $0.event.pubkey != pubkeyHex }
        }
    }

    // MARK: - Report (Kind 1984, NIP-56) — mirrors Android HomeViewModel.reportEvent

    func reportEvent(_ eventId: String, _ pubkeyHex: String, type: String, content: String) {
        Task {
            let tags: [[String]] = [["e", eventId, type], ["p", pubkeyHex]]
            try? await repository.publishEvent(kind: 1984, tags: tags, content: content)
        }
    }

    // MARK: - Birdwatch — mirrors Android HomeViewModel.submitBirdwatch

    func submitBirdwatch(_ eventId: String, _ pubkeyHex: String, type: String, content: String, url: String) {
        Task {
            try? await repository.publishBirdwatchNote(
                targetEventId: eventId,
                content:       content,
                contextType:   type,
                sourceUrl:     url.isEmpty ? nil : url
            )
        }
    }

    // MARK: - Bookmark (Kind 10003, NIP-51) — mirrors Android HomeViewModel.addBookmark

    func addBookmark(_ eventId: String) {
        Task {
            try? await repository.addBookmark(pubkeyHex: myPubkeyHex, eventId: eventId)
            // Optimistic: mark the post as bookmarked
            let all = posts + likedPosts
            all.first(where: { $0.event.id == eventId })?.isBookmarked = true
        }
    }
}
