import Foundation

// MARK: - Timeline
// Android 対応ファイル: NostrRepositoryTimeline.kt
// Phase A で分割確定。fetchGlobalTimeline / fetchFollowingTimeline / fetchEventsFromRelay を管理。
// Phase 3: enrichPosts を TaskGroup で並列実装済み。

extension NostrRepository {

    // MARK: - Single-relay fetch

    /// 単一リレーからイベントを取得する（リレータブ / ターゲット指定フェッチ用）。
    /// Android: NostrRepository.fetchEventsFrom() に相当。
    func fetchEventsFromRelay(
        _ relayUrl: String,
        filters: [NostrFilter],
        timeoutSeconds: Double = 8.0
    ) async -> [NostrEvent] {
        await client.fetchEventsFromRelay(relayUrl, filters: filters, timeoutSeconds: timeoutSeconds)
    }

    func getCachedRelayTimeline(_ relayUrl: String, maxAgeSeconds: TimeInterval = 120) -> [ScoredPost]? {
        guard let cached = relayTimelineCache[relayUrl],
              Date().timeIntervalSince(cached.cachedAt) < maxAgeSeconds else { return nil }
        return cached.posts
    }

    func prefetchRelayTimeline(_ relayUrl: String, limit: Int = 30) async {
        // Do not background-prefetch relays currently in operator-friendly cooldown policy.
        // They remain selectable, but the app should not generate automatic traffic.
        guard !Self.temporarilyDeprioritizedRelays.contains(relayUrl) else { return }
        guard relayTimelineCache[relayUrl] == nil else { return }
        _ = await fetchGlobalTimelineFromRelay(relayUrl, limit: limit, fast: true)
    }

    // MARK: - Global timeline

    /// First-paint global timeline: raw posts + cached profiles only.
    func fetchGlobalTimelineFast(limit: Int = 50, timeoutSeconds: Double = 2.5) async -> [ScoredPost] {
        let since  = Int64(Date().addingTimeInterval(-3600).timeIntervalSince1970)
        let kinds  = [NostrKind.textNote, NostrKind.longForm, NostrKind.repost]
        let filter = NostrFilter(kinds: kinds, since: since, limit: limit)
        let rawEvents = await fetchEvents(filters: [filter], timeoutSeconds: timeoutSeconds)
            .filter { kinds.contains($0.kind) }
            .sorted { $0.createdAt > $1.createdAt }
        var posts = unwrapRepostEvents(rawEvents)
        posts = await filterMutedPosts(posts)
        cache.setCachedTimeline(posts.map(\.event), key: "global")
        applyCachedProfiles(to: &posts)
        return posts
    }

    /// グローバルタイムライン（kind 1、直近1時間）を取得し、エンゲージメントカウントを付与して返す。
    ///
    /// タイムライン取得は pure Swift 実装のみを使用する。
    /// `enrichPosts` によりいいね数・リポスト数・Zap 金額が並列取得される。
    /// Android: fetchGlobalTimeline() に対応。
    func fetchGlobalTimeline(limit: Int = 50) async -> [ScoredPost] {
        let since  = Int64(Date().addingTimeInterval(-3600).timeIntervalSince1970)
        let kinds  = [NostrKind.textNote, NostrKind.longForm, NostrKind.repost]
        let filter = NostrFilter(kinds: kinds, since: since, limit: limit)
        let rawEvents = await fetchEvents(filters: [filter])
            .filter { kinds.contains($0.kind) }
            .sorted { $0.createdAt > $1.createdAt }

        var posts = unwrapRepostEvents(rawEvents)
        posts = await filterMutedPosts(posts)
        cache.setCachedTimeline(posts.map(\.event), key: "global")

        await enrichPosts(&posts)
        return posts
    }

    /// 特定リレーからグローバルタイムラインを取得する（リレー選択ドロップダウン用）。
    func fetchGlobalTimelineFromRelay(_ relayUrl: String, limit: Int = 50, fast: Bool = false) async -> [ScoredPost] {
        if let cached = getCachedRelayTimeline(relayUrl), !cached.isEmpty {
            return cached
        }
        let since  = Int64(Date().addingTimeInterval(-3600).timeIntervalSince1970)
        let kinds  = [NostrKind.textNote, NostrKind.longForm, NostrKind.repost]
        let filter = NostrFilter(kinds: kinds, since: since, limit: limit)
        let rawEvents = await fetchEventsFromRelay(relayUrl, filters: [filter], timeoutSeconds: fast ? 3.0 : 5.0)
            .filter { kinds.contains($0.kind) }
            .sorted { $0.createdAt > $1.createdAt }
        var posts = unwrapRepostEvents(rawEvents)
        posts = await filterMutedPosts(posts)

        applyCachedProfiles(to: &posts)
        if fast {
            await resolveQuotedPosts(&posts, fast: true)
        } else {
            await enrichPosts(&posts)
        }
        relayTimelineCache[relayUrl] = (posts: posts, cachedAt: Date())
        return posts
    }

    // MARK: - Following timeline

    /// First-paint following timeline: raw posts + cached profiles only.
    func fetchFollowingTimelineFast(authors: [String], limit: Int = 50, timeoutSeconds: Double = 2.5) async -> [ScoredPost] {
        guard !authors.isEmpty else { return [] }
        let since  = Int64(Date().addingTimeInterval(-86400 * 2).timeIntervalSince1970)
        let kinds  = [NostrKind.textNote, NostrKind.longForm, NostrKind.repost]
        let filter = NostrFilter(authors: authors, kinds: kinds, since: since, limit: limit)
        let rawEvents = await fetchEvents(filters: [filter], timeoutSeconds: timeoutSeconds)
            .filter { kinds.contains($0.kind) }
            .sorted { $0.createdAt > $1.createdAt }
        var posts = unwrapRepostEvents(rawEvents)
        posts = await filterMutedPosts(posts)
        cache.setCachedTimeline(posts.map(\.event), key: "following")
        applyCachedProfiles(to: &posts)
        return posts
    }

    func enrichTimelinePosts(_ posts: [ScoredPost]) async -> [ScoredPost] {
        var copy = posts
        await enrichPosts(&copy)
        return copy
    }

    /// フォロー中ユーザーのタイムライン（kind 1、直近48時間）を取得し、エンゲージメントカウントを付与して返す。
    ///
    /// フォロータイムライン取得は pure Swift 実装のみを使用する。
    /// `enrichPosts` によりいいね数・リポスト数・Zap 金額が並列取得される。
    /// Android: fetchFollowTimeline() に対応。
    func fetchFollowingTimeline(authors: [String], limit: Int = 50) async -> [ScoredPost] {
        guard !authors.isEmpty else { return [] }
        let since  = Int64(Date().addingTimeInterval(-86400 * 2).timeIntervalSince1970)
        let kinds  = [NostrKind.textNote, NostrKind.longForm, NostrKind.repost]
        let filter = NostrFilter(authors: authors, kinds: kinds, since: since, limit: limit)
        let rawEvents = await fetchEvents(filters: [filter])
            .filter { kinds.contains($0.kind) }
            .sorted { $0.createdAt > $1.createdAt }

        var posts = unwrapRepostEvents(rawEvents)
        posts = await filterMutedPosts(posts)
        // キャッシュに保存（Android: cache.setCachedTimeline("following") に対応）
        cache.setCachedTimeline(posts.map(\.event), key: "following")
        await enrichPosts(&posts)
        return posts
    }

    private func isTimelineDisplayProfileResolved(_ profile: UserProfile) -> Bool {
        let hasName = profile.displayName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            || profile.name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let hasPicture = profile.picture?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        return hasName || hasPicture
    }

    private func applyCachedProfiles(to posts: inout [ScoredPost]) {
        for post in posts {
            if post.profile == nil, let p = cache.getCachedProfile(post.event.pubkey) {
                post.profile = p
            }
            if let rp = post.repostedBy,
               (rp.name == nil && rp.displayName == nil),
               let p = cache.getCachedProfile(rp.pubkey) {
                post.repostedBy = p
            }
        }
    }

    // MARK: - enrichPosts

    /// タイムライン投稿のいいね数・リポスト数・Zap 金額を並列取得して付与する。
    ///
    /// Kind 7 / Kind 6 / Kind 9735 の 3 クエリを `withTaskGroup` で並列実行し、
    /// 各 `ScoredPost` の `likeCount` / `repostCount` / `zapAmount` に格納する。
    /// Android: `NostrRepository.enrichPosts()` に対応。
    ///
    /// - Parameter posts: 付与対象の `ScoredPost` 配列 (in-out)。
    func enrichPosts(_ posts: inout [ScoredPost]) async {
        guard !posts.isEmpty else { return }
        let myPubkey = prefs.publicKeyHex
        let ids = posts.map(\.event.id)

        /// TaskGroup の各子タスクが返す結果を識別するための列挙型。
        enum FetchResult {
            case reactions([NostrEvent])
            case reposts([NostrEvent])
            case zaps([String: Int64])
            case bookmarks(Set<String>)
        }

        var reactionEvents: [NostrEvent] = []
        var repostEvents:   [NostrEvent] = []
        var zapAmounts:     [String: Int64] = [:]
        var bookmarkedIds:  Set<String> = []

        // 並列フェッチ: reactions + reposts + zaps + bookmarks
        await withTaskGroup(of: FetchResult.self) { group in
            group.addTask { .reactions(await self.fetchReactionEvents(eventIds: ids)) }
            group.addTask { .reposts(await self.fetchRepostEvents(eventIds: ids)) }
            group.addTask { .zaps(await self.fetchZapAmounts(eventIds: ids)) }
            if let pk = myPubkey {
                group.addTask {
                    let bmIds = await self.fetchBookmarkEventIds(pubkeyHex: pk)
                    return .bookmarks(Set(bmIds))
                }
            }

            for await result in group {
                switch result {
                case .reactions(let r): reactionEvents = r
                case .reposts(let r):   repostEvents = r
                case .zaps(let z):      zapAmounts = z
                case .bookmarks(let b): bookmarkedIds = b
                }
            }
        }

        // Count reactions per event
        let reactionCounts = Dictionary(
            grouping: reactionEvents.compactMap { $0.getTagValue("e") },
            by: { $0 }
        ).mapValues(\.count)

        // My reaction event IDs (for undo)
        let myReactionMap: [String: String] = {
            guard let pk = myPubkey else { return [:] }
            var map: [String: String] = [:]
            for ev in reactionEvents where ev.pubkey == pk {
                if let targetId = ev.getTagValue("e") { map[targetId] = ev.id }
            }
            return map
        }()

        // Count reposts per event
        let repostCounts = Dictionary(
            grouping: repostEvents.compactMap { $0.getTagValue("e") },
            by: { $0 }
        ).mapValues(\.count)

        // My repost event IDs (for undo)
        let myRepostMap: [String: String] = {
            guard let pk = myPubkey else { return [:] }
            var map: [String: String] = [:]
            for ev in repostEvents where ev.pubkey == pk {
                if let targetId = ev.getTagValue("e") { map[targetId] = ev.id }
            }
            return map
        }()

        // プロフィールはキャッシュを即時反映し、不足分だけリレー取得する
        let allPubkeys = Array(Set(
            posts.map(\.event.pubkey) + posts.compactMap(\.repostedBy?.pubkey)
        ))
        var profileMap: [String: UserProfile] = [:]
        var missingProfiles: [String] = []
        for pk in allPubkeys {
            if let cached = cache.getCachedProfile(pk), isTimelineDisplayProfileResolved(cached) {
                profileMap[pk] = cached
            } else {
                missingProfiles.append(pk)
            }
        }
        if !missingProfiles.isEmpty {
            let profiles = await fetchProfiles(pubkeys: missingProfiles)
            for p in profiles { profileMap[p.pubkey] = p }
        }

        // バッジはキャッシュからのみ取得（ネットワーク不要、即時表示）。
        // フルフェッチはプロフィール画面でのみ実行（Android 同様）。
        var badgeMap: [String: [String]] = [:]
        for pk in allPubkeys {
            if let cached = cache.getCachedBadges(pubkey: pk) {
                badgeMap[pk] = cached
            }
        }

        // 各 ScoredPost にカウント・状態・プロフィール・バッジを付与
        for post in posts {
            post.likeCount       = reactionCounts[post.event.id] ?? 0
            post.repostCount     = repostCounts[post.event.id]   ?? 0
            post.zapAmount       = zapAmounts[post.event.id]     ?? 0
            post.isLiked         = myReactionMap[post.event.id] != nil
            post.myLikeEventId   = myReactionMap[post.event.id]
            post.isReposted      = myRepostMap[post.event.id] != nil
            post.myRepostEventId = myRepostMap[post.event.id]
            post.isBookmarked    = bookmarkedIds.contains(post.event.id)
            // プロフィール設定
            if post.profile == nil {
                post.profile = profileMap[post.event.pubkey]
            }
            // repostedBy のプロフィール解決
            if let rp = post.repostedBy, rp.name == nil, let fullProfile = profileMap[rp.pubkey] {
                post.repostedBy = fullProfile
            }
            // バッジ設定（キャッシュ済みのみ — ネットワーク不要）
            post.badges = badgeMap[post.event.pubkey] ?? []
        }

        // NIP-05 検証を並列実行（Android: enrichPosts 内の並列 NIP-05 検証に対応）
        // 最大10件を同時検証してタイムアウトを防ぐ
        let postsWithNip05 = posts.filter { $0.profile?.nip05 != nil }.prefix(10)
        if !postsWithNip05.isEmpty {
            await withTaskGroup(of: (String, Bool).self) { group in
                for post in postsWithNip05 {
                    guard let nip05 = post.profile?.nip05, !nip05.isEmpty else { continue }
                    let pubkey = post.event.pubkey
                    group.addTask {
                        let resolvedPubkey = await self.resolveNip05(nip05)
                        let verified = resolvedPubkey == pubkey
                        return (pubkey, verified)
                    }
                }
                for await (pubkey, verified) in group {
                    for post in posts where post.event.pubkey == pubkey {
                        post.isVerified = verified
                    }
                }
            }
        }

        // 引用投稿の解決
        await resolveQuotedPosts(&posts)
    }

    /// Fetch raw reaction events (Kind 7) — returns full events for pubkey matching.
    private func fetchReactionEvents(eventIds: [String]) async -> [NostrEvent] {
        guard !eventIds.isEmpty else { return [] }
        let filter = NostrFilter(kinds: [NostrKind.reaction], limit: 500, tags: ["#e": eventIds])
        return await fetchEvents(filters: [filter], timeoutSeconds: 3.0)
    }

    /// Fetch raw repost events (Kind 6) — returns full events for pubkey matching.
    private func fetchRepostEvents(eventIds: [String]) async -> [NostrEvent] {
        guard !eventIds.isEmpty else { return [] }
        let filter = NostrFilter(kinds: [NostrKind.repost], limit: 500, tags: ["#e": eventIds])
        return await fetchEvents(filters: [filter], timeoutSeconds: 3.0)
    }

    // MARK: - Repost Unwrap (Kind 6 → inner event + repostedBy)

    /// Kind 6 リポストイベントの content から内包イベントを取り出し、
    /// `repostedBy` をセットした `ScoredPost` に変換する。
    /// Kind 1 などはそのまま `ScoredPost` にする。
    /// Android: enrichPosts 内のリポスト展開ロジックに対応。
    private func unwrapRepostEvents(_ events: [NostrEvent]) -> [ScoredPost] {
        var posts: [ScoredPost] = []
        var seenIds = Set<String>()

        for event in events {
            if event.kind == NostrKind.repost {
                // Kind 6: content にオリジナルイベントの JSON が入っている
                if let data = event.content.data(using: .utf8),
                   let inner = try? JSONDecoder().decode(NostrEvent.self, from: data),
                   inner.kind == NostrKind.textNote || inner.kind == NostrKind.longForm {
                    guard seenIds.insert(inner.id).inserted else { continue }
                    let post = ScoredPost(event: inner)
                    // repostedBy はプロフィール取得後に設定される（pubkey のみ仮設定）
                    post.repostedBy = UserProfile(pubkey: event.pubkey)
                    post.repostTime = event.createdAt
                    posts.append(post)
                }
                // content が空の場合は "e" タグのみのリポスト（後で解決する必要あり）
            } else {
                guard seenIds.insert(event.id).inserted else { continue }
                posts.append(ScoredPost(event: event))
            }
        }

        return posts
    }

    /// 公開/非公開ミュート対象の投稿を除外する（author と repostedBy の両方を判定）。
    private func filterMutedPosts(_ posts: [ScoredPost]) async -> [ScoredPost] {
        guard let myPubkey = prefs.publicKeyHex else { return posts }
        let mute = await fetchMuteList(pubkeyHex: myPubkey)
        let muted = Set(mute.publicMutes).union(mute.privateMutes)
        guard !muted.isEmpty else { return posts }
        return posts.filter { post in
            if muted.contains(post.event.pubkey) { return false }
            if let rp = post.repostedBy, muted.contains(rp.pubkey) { return false }
            return true
        }
    }

    // MARK: - Resolve Quoted Posts

    /// 引用リポスト（"q" タグ or nostr:note1... in content）の引用元イベントを取得して
    /// `ScoredPost.quotedPost` にセットする。
    /// Android: enrichPosts 内の引用解決ロジックに対応。
    func resolveQuotedPosts(_ posts: inout [ScoredPost], fast: Bool = false) async {
        // "q" タグまたは content 内の nostr:nevent/note から引用先 ID を収集
        var quoteMap: [String: [Int]] = [:] // eventId → indices in posts
        for (i, post) in posts.enumerated() {
            // 既に解決済みの引用はスキップ
            guard post.quotedPost == nil else { continue }

            if let qId = post.event.getTagValue("q"), !qId.isEmpty {
                quoteMap[qId, default: []].append(i)
            } else {
                // content 内の nostr:note/nevent と bare note1/nevent1 を検出。
                // nevent は TLV により可変長なので {20,} で広めにマッチする。
                let pattern = #"(?:nostr:)?(note1[a-z0-9]{58}|nevent1[a-z0-9]{20,})"#
                if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                   let match = regex.firstMatch(
                    in: post.event.content,
                    range: NSRange(location: 0, length: (post.event.content as NSString).length)
                   ) {
                    let bech32 = (post.event.content as NSString).substring(with: match.range(at: 1))
                    // bech32 → hex id（NIP-19 デコード）
                    if let eventId = NostrBech32.decodeEventId(bech32) {
                        quoteMap[eventId, default: []].append(i)
                    } else if let eId = post.event.tags.first(where: { $0.first == "e" && $0.count >= 2 })?.dropFirst().first {
                        // フォールバック: "e" タグから取得
                        quoteMap[eId, default: []].append(i)
                    }
                } else if let eId = post.event.getTagValue("e"), !eId.isEmpty,
                          post.event.content.contains("nostr:") {
                    // regex がマッチしなかった場合でも "e" タグ + content に nostr: がある場合は引用と判断
                    quoteMap[eId, default: []].append(i)
                }
            }
        }

        guard !quoteMap.isEmpty else { return }

        let quotedIds = Array(quoteMap.keys)

        // 1) キャッシュ済み引用は即時反映
        var missingIds: [String] = []
        for id in quotedIds {
            if let cached = quotedPostCache[id] {
                for i in quoteMap[id] ?? [] where i < posts.count { posts[i].quotedPost = cached }
            } else {
                missingIds.append(id)
            }
        }
        guard !missingIds.isEmpty else { return }

        var allQuotedEvents = missingIds.compactMap { cache.getCachedEvent(eventId: $0) }
        let cachedQuotedIds = Set(allQuotedEvents.map(\.id))
        let stillNetworkIds = missingIds.filter { !cachedQuotedIds.contains($0) }
        if !stillNetworkIds.isEmpty {
            let filter = NostrFilter(ids: stillNetworkIds, limit: stillNetworkIds.count)
            let fetched = await fetchEvents(filters: [filter], timeoutSeconds: fast ? 2.0 : 3.0)
            cache.setCachedEvents(fetched)
            allQuotedEvents.append(contentsOf: fetched)
        }

        // 取得できなかった ID を個別リレーでリトライ（fast時は体感優先で省略）
        if !fast {
            let foundIds = Set(allQuotedEvents.map(\.id))
            let stillMissing = missingIds.filter { !foundIds.contains($0) }
            if !stillMissing.isEmpty {
                let retryFilter = NostrFilter(ids: Array(stillMissing.prefix(5)), limit: stillMissing.count)
                let relayUrls = getSavedRelayUrls()
                await withTaskGroup(of: [NostrEvent].self) { group in
                    for url in relayUrls.prefix(2) {
                        group.addTask { await self.client.fetchEventsFromRelay(url, filters: [retryFilter], timeoutSeconds: 3.0) }
                    }
                    for await retryEvents in group { allQuotedEvents.append(contentsOf: retryEvents) }
                }
            }
        }

        // プロフィールもキャッシュ優先、不足分のみ取得
        var profileMap: [String: UserProfile] = [:]
        var missingProfilePubkeys: [String] = []
        for pk in Set(allQuotedEvents.map(\.pubkey)) {
            if let cached = cache.getCachedProfile(pk), isTimelineDisplayProfileResolved(cached) {
                profileMap[pk] = cached
            } else {
                missingProfilePubkeys.append(pk)
            }
        }
        if !missingProfilePubkeys.isEmpty && !fast {
            let quotedProfiles = await fetchProfiles(pubkeys: missingProfilePubkeys)
            for p in quotedProfiles { profileMap[p.pubkey] = p }
        }

        for event in allQuotedEvents {
            guard let indices = quoteMap[event.id] else { continue }
            let qPost = ScoredPost(event: event, profile: profileMap[event.pubkey])
            quotedPostCache[event.id] = qPost
            for i in indices where i < posts.count { posts[i].quotedPost = qPost }
        }
    }
}