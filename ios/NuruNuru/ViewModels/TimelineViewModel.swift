import Foundation
import Observation

/// Feed type — mirrors Android FeedType enum.
enum FeedType: Equatable {
    case relay      // "リレー" — global feed from connected relay
    case following  // "フォロー" — posts from followed users
}

/// Timeline screen state and logic.
/// @Observable + @MainActor ensures all property updates happen on the main thread.
/// Mirrors Android TimelineViewModel structure.
@Observable
@MainActor
final class TimelineViewModel {

    // MARK: - Published State

    var relayPosts:          [ScoredPost] = []
    var followingPosts:      [ScoredPost] = []
    /// キャッシュが存在する場合は false で初期化（Android 同様、キャッシュファーストでスケルトン表示しない）。
    /// キャッシュが空の場合のみ true でスケルトン表示。
    var isRelayLoading:      Bool = false
    var isFollowingLoading:  Bool = false
    var isRelayRefreshing:   Bool = false
    var isFollowingRefreshing: Bool = false
    var feedType:            FeedType = .following
    var followList:          [String]  = []
    var errorMessage:        String?   = nil
    // Relay selector
    var savedRelayUrls:      [String]  = []
    var selectedRelayUrl:    String?   = nil
    // New-post dot indicators
    var hasNewRelayPosts:    Bool = false
    var hasNewFollowingPosts: Bool = false
    // New-post counts (displayed in pill: "新しい投稿 N件")
    var newRelayPostCount:     Int = 0
    var newFollowingPostCount: Int = 0

    // MARK: - Live Streaming State

    /// アクティブフィードの未読新着投稿数（「新しい投稿」ピルに表示）。
    var pendingLivePostsCount: Int = 0

    // バッファ済み新着投稿（ピルタップで先頭挿入）
    private var pendingRelayPosts:     [ScoredPost] = []
    private var pendingFollowingPosts: [ScoredPost] = []

    // ライブサブスクリプション ID
    private var relayLiveSubId:     String? = nil
    private var followingLiveSubId: String? = nil

    // ポーリングループ Task（画面離脱時にキャンセル）
    private var livePollingTask: Task<Void, Never>? = nil
    // リレー切替リフレッシュの重複実行防止
    private var relaySelectionTask: Task<Void, Never>? = nil

    // MARK: - Dependencies

    let repository: NostrRepository
    let pubkeyHex: String

    // MARK: - Init

    init(repository: NostrRepository, pubkeyHex: String) {
        self.repository = repository
        self.pubkeyHex  = pubkeyHex
        AppLogger.log("Timeline", "TimelineViewModel init — pubkey: \(pubkeyHex.prefix(16))…")

        // ── Step 0: キャッシュから即時表示（nonisolated — actor hop なし） ──
        // Android: loadData() で getCachedTimeline() を Dispatchers.IO で即時読み取り → UI 更新。
        // iOS: nonisolated メソッドで同期的にキャッシュ読み取り → isLoading 解除。
        let cachedGlobal    = repository.getCachedGlobalTimeline()
        let cachedFollowing = repository.getCachedFollowingTimeline()
        let cachedFollows   = repository.getCachedFollowList(pubkey: pubkeyHex)

        if !cachedGlobal.isEmpty {
            relayPosts     = cachedGlobal.map { ScoredPost(event: $0) }
            // キャッシュ済みプロフィールを即時適用（アバター・名前を即時表示 — Android 同様）
            for post in relayPosts {
                if let profile = repository.getCachedProfile(pubkey: post.event.pubkey) {
                    post.profile = profile
                }
            }
            AppLogger.log("Timeline", "Cache-first (sync): \(cachedGlobal.count) relay posts")
        } else {
            // キャッシュが空の場合のみローディングスケルトンを表示
            isRelayLoading = true
        }
        if let follows = cachedFollows, !follows.isEmpty {
            followList = follows
            if !cachedFollowing.isEmpty {
                followingPosts = cachedFollowing.map { ScoredPost(event: $0) }
                // キャッシュ済みプロフィールを即時適用
                for post in followingPosts {
                    if let profile = repository.getCachedProfile(pubkey: post.event.pubkey) {
                        post.profile = profile
                    }
                }
                AppLogger.log("Timeline", "Cache-first (sync): \(cachedFollowing.count) following posts")
            } else {
                isFollowingLoading = true
            }
        } else {
            isFollowingLoading = true
        }

        // ── Step 1: リレーデータ取得 + NIP-65 sync をバックグラウンドで並列実行 ──
        // Android 同様: syncNip65Relays は Dispatchers.IO の launch で UI をブロックしない。
        Task {
            // リレー URL をまず取得（ドロップダウン表示用）
            savedRelayUrls = await repository.getSavedRelayUrls()

            // NIP-65 sync + prefetch をバックグラウンドで実行（メインフローをブロックしない）
            Task {
                await repository.syncNip65Relays()
                savedRelayUrls = await repository.getSavedRelayUrls()
                AppLogger.log("Timeline", "NIP-65 sync complete — relays: \(savedRelayUrls)")
            }

            // リレーからの最新データ取得を並列で即時開始
            await loadFreshData()
        }
    }

    // MARK: - Load

    /// リレーから最新データを取得する（キャッシュ表示済みの状態で呼ばれる）。
    /// Android: loadData() 内の loadFollowList/loadGlobalTimeline/loadFollowingTimeline に対応。
    ///
    /// フォロータイムラインを最優先で取得・表示する:
    ///   1. フォローリストを取得（必要なら fetchEvents 側で接続を自動確立）
    ///   2. フォロータイムラインを取得 + enrich（ユーザーの最優先フィード）
    ///   3. グローバルタイムラインをバックグラウンドで取得
    private func loadFreshData() async {
        AppLogger.log("Timeline", "loadFreshData start")

        // ── Step 1: フォローリストを最優先で取得 ──
        let freshFollows = await repository.fetchFollowList(pubkey: pubkeyHex)
        if !freshFollows.isEmpty {
            followList = freshFollows
        }
        AppLogger.log("Timeline", "Follow list loaded: \(followList.count) follows")
        await restartFollowingLiveTimeline()

        // フォロー表示を優先しつつ、リレー取得は並列で先行開始
        async let globalTask: [ScoredPost] = repository.fetchGlobalTimeline()

        // ── Step 2: フォロータイムラインを最優先で取得 ──
        let freshFollowing: [ScoredPost]
        if followList.isEmpty {
            freshFollowing = []
        } else {
            freshFollowing = await repository.fetchFollowingTimeline(authors: followList)
        }
        if !freshFollowing.isEmpty || followingPosts.isEmpty {
            followingPosts = freshFollowing
        }
        isFollowingLoading = false
        AppLogger.log("Timeline", "Following posts loaded: \(freshFollowing.count)")

        // ── Step 3: グローバルタイムライン結果を反映 ──
        let freshGlobal = await globalTask
        if !freshGlobal.isEmpty || relayPosts.isEmpty {
            relayPosts = freshGlobal
        }
        isRelayLoading = false
        AppLogger.log("Timeline", "Relay posts loaded: \(freshGlobal.count)")

        // キャッシュ表示分に欠損がある場合のみ追加 enrich（不要な再取得を避ける）
        if hasMissingProfiles(in: followingPosts) {
            await enrichProfiles(for: .following)
        }
        if hasMissingProfiles(in: relayPosts) {
            await enrichProfiles(for: .relay)
        }

        // ライブポーリング開始（初回データ取得完了後）
        startLivePolling()
    }

    private func restartFollowingLiveTimeline() async {
        if let existing = followingLiveSubId {
            await repository.stopLiveTimeline(subId: existing)
            followingLiveSubId = nil
        }
        guard !followList.isEmpty else {
            AppLogger.log("Timeline", "Following live timeline skipped: empty follow list")
            return
        }
        followingLiveSubId = await repository.startLiveTimeline(authors: followList)
        AppLogger.log("Timeline", "Following live timeline restarted — follows=\(followList.count) subId=\(followingLiveSubId ?? "nil")")
    }

    private func enrichProfiles(for feed: FeedType) async {
        var posts = feed == .relay ? relayPosts : followingPosts
        guard !posts.isEmpty else { return }
        guard hasMissingProfiles(in: posts) else { return }

        // 全 pubkey を収集（投稿者 + repostedBy の pubkey）
        var pubkeySet = Set(posts.map { $0.event.pubkey })
        for post in posts {
            if let rp = post.repostedBy { pubkeySet.insert(rp.pubkey) }
        }

        // 1. キャッシュ済みプロフィールを即時適用（ネットワーク待ちなし）
        // ただし表示に必要な情報が欠損しているキャッシュは再取得対象にする
        var missingPubkeys: [String] = []
        var profileMap: [String: UserProfile] = [:]
        let requirePicture = (feed == .following)
        for pk in pubkeySet {
            if let cached = repository.getCachedProfile(pubkey: pk),
               isDisplayProfileResolved(cached, requirePicture: requirePicture) {
                profileMap[pk] = cached
            } else {
                missingPubkeys.append(pk)
            }
        }

        // キャッシュ済みを即時反映（アバター即時表示）
        if !profileMap.isEmpty {
            for post in posts {
                if !isDisplayProfileResolved(post.profile, requirePicture: requirePicture),
                   let p = profileMap[post.event.pubkey] {
                    post.profile = p
                }
                if let rp = post.repostedBy,
                   (!isDisplayProfileResolved(rp, requirePicture: requirePicture) || repostDisplayName(rp).hasSuffix("...")),
                   let p = profileMap[rp.pubkey] {
                    post.repostedBy = p
                }
            }
            if feed == .relay { relayPosts = posts }
            else              { followingPosts = posts }
        }

        // 2. 未取得分のみリレーからフェッチ（Android: missing リストのみ fetch に対応）
        if !missingPubkeys.isEmpty {
            let fetched = await repository.fetchProfiles(pubkeys: missingPubkeys)
            for p in fetched { profileMap[p.pubkey] = p }
            for post in posts {
                if let p = profileMap[post.event.pubkey] { post.profile = p }
                if let rp = post.repostedBy, let fullProfile = profileMap[rp.pubkey] {
                    post.repostedBy = fullProfile
                }
            }
        }

        // 引用投稿（"q" タグ / nostr:note1...）を解決
        await repository.resolveQuotedPosts(&posts)

        // Reassign to trigger @Observable re-render (class mutation not tracked otherwise).
        if feed == .relay { relayPosts = posts }
        else              { followingPosts = posts }
    }

    // MARK: - Refresh (pull-to-refresh)

    func refreshRelay() async {
        isRelayRefreshing = true
        let fresh: [ScoredPost]
        if let url = selectedRelayUrl {
            fresh = await repository.fetchGlobalTimelineFromRelay(url)
        } else {
            fresh = await repository.fetchGlobalTimeline()
        }

        // 新着なしで空レスポンスでも既存表示は維持（誤って空画面にしない）
        if !fresh.isEmpty || relayPosts.isEmpty {
            relayPosts = fresh
        }

        await enrichProfiles(for: .relay)
        isRelayRefreshing = false
    }

    func refreshFollowing() async {
        guard !followList.isEmpty else { isFollowingRefreshing = false; return }
        isFollowingRefreshing = true
        let fresh = await repository.fetchFollowingTimeline(authors: followList)

        // 新着なしで空レスポンスでも既存表示は維持（誤って空画面にしない）
        if !fresh.isEmpty || followingPosts.isEmpty {
            followingPosts = fresh
        }

        await enrichProfiles(for: .following)
        isFollowingRefreshing = false
        await restartFollowingLiveTimeline()
    }

    // MARK: - Feed Switch

    func switchFeed(_ feed: FeedType) {
        feedType = feed
        if feed == .relay {
            hasNewRelayPosts      = false
            // ピルカウントをアクティブフィードに合わせて更新
            pendingLivePostsCount = pendingRelayPosts.count
        }
        if feed == .following {
            hasNewFollowingPosts  = false
            pendingLivePostsCount = pendingFollowingPosts.count
        }
    }

    // MARK: - Relay Selection

    func selectRelay(_ url: String?) {
        // 同一選択時は再取得しない（UI崩れ・無駄通信防止）
        if selectedRelayUrl == url {
            feedType = .relay
            return
        }

        selectedRelayUrl = url
        feedType = .relay

        // 進行中の切替処理をキャンセルして最新選択のみ反映
        relaySelectionTask?.cancel()
        isRelayRefreshing = true
        relaySelectionTask = Task { [weak self] in
            guard let self else { return }
            await refreshRelay()
            guard !Task.isCancelled else { return }
            isRelayRefreshing = false
            // リレー変更時にライブポーリングを再起動して、選択リレーのみから新着を受信する
            restartRelayLivePolling()
        }
    }

    // MARK: - Interactions

    func toggleLike(post: ScoredPost) async {
        let wasLiked = post.isLiked
        post.isLiked   = !wasLiked
        post.likeCount += wasLiked ? -1 : 1
        triggerUpdate()
        do {
            try await repository.publishReaction(to: post.event.id, authorPubkey: post.event.pubkey)
        } catch {
            post.isLiked   = wasLiked
            post.likeCount += wasLiked ? 1 : -1
            triggerUpdate()
        }
    }

    func toggleRepost(post: ScoredPost) async {
        guard !post.isReposted else { return }
        post.isReposted  = true
        post.repostCount += 1
        triggerUpdate()
        do {
            try await repository.publishRepost(event: post.event)
        } catch {
            post.isReposted  = false
            post.repostCount -= 1
            triggerUpdate()
        }
    }

    // MARK: - Bookmark (NIP-51, Kind 10003) — mirrors Android toggleBookmark

    func toggleBookmark(post: ScoredPost) async {
        let wasBookmarked = post.isBookmarked
        post.isBookmarked = !wasBookmarked
        triggerUpdate()
        do {
            if wasBookmarked {
                try await repository.removeBookmark(pubkeyHex: pubkeyHex, eventId: post.event.id)
            } else {
                try await repository.addBookmark(pubkeyHex: pubkeyHex, eventId: post.event.id)
            }
        } catch {
            post.isBookmarked = wasBookmarked
            triggerUpdate()
        }
    }

    // MARK: - Post Actions

    func deletePost(_ post: ScoredPost) async {
        relayPosts     = relayPosts.filter     { $0.event.id != post.event.id }
        followingPosts = followingPosts.filter { $0.event.id != post.event.id }
        try? await repository.publishDelete(eventId: post.event.id)
    }

    func muteUser(_ pubkeyHex: String) async {
        relayPosts     = relayPosts.filter     { $0.event.pubkey != pubkeyHex }
        followingPosts = followingPosts.filter { $0.event.pubkey != pubkeyHex }
        try? await repository.muteUser(pubkeyHex: pubkeyHex, isPrivate: true)
    }

    func reportEvent(post: ScoredPost, type: String, content: String) async {
        let tags: [[String]] = [["e", post.event.id, type], ["p", post.event.pubkey]]
        try? await repository.publishEvent(kind: NostrKind.report, tags: tags, content: content)
    }

    func submitBirdwatch(post: ScoredPost, type: String, content: String, url: String) async {
        var tags: [[String]] = [
            ["e", post.event.id],
            ["p", post.event.pubkey],
            ["L", "social.birdwatch"],
            ["l", type, "social.birdwatch"]
        ]
        if !url.isEmpty { tags.append(["r", url]) }
        try? await repository.publishEvent(kind: NostrKind.label, tags: tags, content: content)
    }

    // Forces @Observable to re-render views that read the arrays.
    private func triggerUpdate() {
        relayPosts     = relayPosts
        followingPosts = followingPosts
    }

    /// 画像/表示名/名前が未解決の投稿が含まれるかを判定。
    /// 無駄な profile fetch を避けるためのガード。
    private func hasMissingProfiles(in posts: [ScoredPost]) -> Bool {
        let requirePicture = (feedType == .following)
        return posts.contains {
            if !isDisplayProfileResolved($0.profile, requirePicture: requirePicture) { return true }
            if let rp = $0.repostedBy {
                return !isDisplayProfileResolved(rp, requirePicture: requirePicture)
                    || repostDisplayName(rp).hasSuffix("...")
            }
            return false
        }
    }

    private func repostDisplayName(_ profile: UserProfile) -> String {
        profile.displayedName
    }

    private func isDisplayProfileResolved(_ profile: UserProfile?, requirePicture: Bool = false) -> Bool {
        guard let profile else { return false }
        let hasName = profile.displayName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            || profile.name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let hasPicture = profile.picture?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        return requirePicture ? (hasName && hasPicture) : (hasName || hasPicture)
    }

    // MARK: - Live Streaming

    /// ライブポーリングを開始する。
    ///
    /// 初回データ取得完了後に `loadInitialData()` から呼び出される。
    /// 既存のポーリングタスクがあればキャンセルしてから再起動する。
    /// フォロー・リレー両フィードを同時に購読し、5 秒間隔でポーリングする。
    /// リレーフィードのライブポーリングのみ再起動する（リレー選択変更時）。
    private func restartRelayLivePolling() {
        // 既存のリレーサブスクリプションを停止
        if let sid = relayLiveSubId {
            let oldSid = sid
            relayLiveSubId = nil
            pendingRelayPosts = []
            newRelayPostCount = 0
            hasNewRelayPosts = false
            Task { await repository.stopLiveTimeline(subId: oldSid) }
        }
        // 選択リレーで新しいサブスクリプションを開始
        Task { [weak self] in
            guard let self else { return }
            let newSubId = await repository.startLiveTimeline(authors: [], relayUrl: selectedRelayUrl)
            relayLiveSubId = newSubId
        }
    }

    func startLivePolling() {
        livePollingTask?.cancel()
        livePollingTask = Task { [weak self] in
            guard let self else { return }

            // 両フィードのサブスクリプションを並行開始（リレーフィードは選択リレーを指定）
            async let relayStart:     String? = repository.startLiveTimeline(authors: [], relayUrl: selectedRelayUrl)
            async let followingStart: String? = repository.startLiveTimeline(authors: followList)
            let (relayId, followId) = await (relayStart, followingStart)

            relayLiveSubId     = relayId
            followingLiveSubId = followId

            // ミュート一覧（公開 + 非公開）を先に取得
            let muteResult = await repository.fetchMuteList(pubkeyHex: pubkeyHex)
            let mutedPubkeys = Set(muteResult.publicMutes).union(muteResult.privateMutes)

            // 5 秒間隔ポーリングループ
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled else { break }

                // リレーフィードのポーリング
                if let sid = relayLiveSubId {
                    let newEvents = await repository.pollNewPosts(subId: sid)
                    if !newEvents.isEmpty {
                        var existingIds = Set(relayPosts.map(\.event.id) + pendingRelayPosts.map(\.event.id))
                        var unique: [NostrEvent] = []
                        for ev in newEvents where existingIds.insert(ev.id).inserted {
                            guard !mutedPubkeys.contains(ev.pubkey) else { continue }
                            unique.append(ev)
                        }
                        if !unique.isEmpty {
                            // プロフィールを事前取得（Android enrichPostsDirect 同等）
                            let pubkeys = Array(Set(unique.map(\.pubkey)))
                            let profiles = await repository.fetchProfiles(pubkeys: pubkeys)
                            let profileMap = Dictionary(profiles.map { ($0.pubkey, $0) }, uniquingKeysWith: { a, _ in a })
                            let posts = unique.map { ev -> ScoredPost in
                                let p = ScoredPost(event: ev)
                                p.profile = profileMap[ev.pubkey]
                                return p
                            }
                            pendingRelayPosts.append(contentsOf: posts)
                            hasNewRelayPosts    = true
                            newRelayPostCount   = pendingRelayPosts.count
                        }
                    }
                }

                // フォローフィードのポーリング
                if let sid = followingLiveSubId {
                    let newEvents = await repository.pollNewPosts(subId: sid)
                    if !newEvents.isEmpty {
                        var existingIds = Set(followingPosts.map(\.event.id) + pendingFollowingPosts.map(\.event.id))
                        var unique: [NostrEvent] = []
                        for ev in newEvents where existingIds.insert(ev.id).inserted {
                            guard !mutedPubkeys.contains(ev.pubkey) else { continue }
                            unique.append(ev)
                        }
                        if !unique.isEmpty {
                            // プロフィールを事前取得（Android enrichPostsDirect 同等）
                            let pubkeys = Array(Set(unique.map(\.pubkey)))
                            let profiles = await repository.fetchProfiles(pubkeys: pubkeys)
                            let profileMap = Dictionary(profiles.map { ($0.pubkey, $0) }, uniquingKeysWith: { a, _ in a })
                            let posts = unique.map { ev -> ScoredPost in
                                let p = ScoredPost(event: ev)
                                p.profile = profileMap[ev.pubkey]
                                return p
                            }
                            pendingFollowingPosts.append(contentsOf: posts)
                            hasNewFollowingPosts    = true
                            newFollowingPostCount   = pendingFollowingPosts.count
                        }
                    }
                }

                // アクティブフィードのピルカウントを更新
                let active = feedType == .relay ? pendingRelayPosts : pendingFollowingPosts
                pendingLivePostsCount = active.count
            }
        }
    }

    /// ライブポーリングを停止してリソースを解放する。
    ///
    /// 画面離脱時（View の `onDisappear` または `.task` キャンセル時）に呼び出す。
    func stopLivePolling() {
        livePollingTask?.cancel()
        livePollingTask = nil

        // サブスクリプション ID をローカルコピーしてからクリア（Task クロージャ内で使うため）
        let relayId    = relayLiveSubId
        let followId   = followingLiveSubId
        relayLiveSubId     = nil
        followingLiveSubId = nil

        pendingRelayPosts     = []
        pendingFollowingPosts = []
        pendingLivePostsCount = 0
        newRelayPostCount     = 0
        newFollowingPostCount = 0

        Task { [weak self] in
            guard let self else { return }
            if let sid = relayId    { await repository.stopLiveTimeline(subId: sid) }
            if let sid = followId   { await repository.stopLiveTimeline(subId: sid) }
        }
    }

    /// 「新しい投稿」ピルがタップされたとき、バッファ済み投稿を現在のフィードの先頭に挿入する。
    ///
    /// 挿入後、ピルカウントとドット indicator をリセットする。
    /// Android の flushPendingPosts() + reEnrichMissingProfiles() に対応。
    func insertPendingPosts() {
        var inserted: [ScoredPost] = []
        if feedType == .relay {
            let existingIds = Set(relayPosts.map(\.event.id))
            let unique = pendingRelayPosts.filter { !existingIds.contains($0.event.id) }
            inserted = unique
            relayPosts          = unique + relayPosts
            pendingRelayPosts   = []
            hasNewRelayPosts    = false
            newRelayPostCount   = 0
        } else {
            let existingIds = Set(followingPosts.map(\.event.id))
            let unique = pendingFollowingPosts.filter { !existingIds.contains($0.event.id) }
            inserted = unique
            followingPosts          = unique + followingPosts
            pendingFollowingPosts   = []
            hasNewFollowingPosts    = false
            newFollowingPostCount   = 0
        }
        pendingLivePostsCount = 0

        // Android reEnrichMissingProfiles 同等: プロフィール未取得の投稿を再取得
        reEnrichMissingProfiles(inserted)
    }

    /// プロフィールが不完全な投稿のプロフィールをバックグラウンドで再取得する。
    /// Android TimelineViewModel.reEnrichMissingProfiles() に対応。
    private func reEnrichMissingProfiles(_ posts: [ScoredPost]) {
        let missing = posts.filter { p in
            p.profile?.picture == nil && p.profile?.displayName == nil && p.profile?.name == nil
        }
        guard !missing.isEmpty else { return }
        let pubkeys = Array(Set(missing.map(\.event.pubkey)))
        Task {
            let profiles = await repository.fetchProfiles(pubkeys: pubkeys)
            let profileMap = Dictionary(profiles.map { ($0.pubkey, $0) }, uniquingKeysWith: { a, _ in a })
            let resolved = profileMap.filter { (_, v) in
                v.picture != nil || v.displayName != nil || v.name != nil
            }
            guard !resolved.isEmpty else { return }
            // ScoredPost は @Observable class なのでプロパティ変更で自動再描画
            for post in missing {
                if let p = resolved[post.event.pubkey] {
                    post.profile = p
                }
            }
            // 配列の再代入で @Observable の変更を確実に通知
            relayPosts     = relayPosts
            followingPosts = followingPosts
        }
    }
}