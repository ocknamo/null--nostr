import SwiftUI

// MARK: - ViewModel

/// 投稿詳細画面の状態管理。
/// Android: `PostDetailScreen.kt` の `LaunchedEffect` ブロックに対応。
@Observable
@MainActor
final class PostDetailViewModel {

    // MARK: - State

    /// 対象投稿（元投稿）。
    var post:         ScoredPost? = nil
    /// 祖先投稿（元投稿の `e` タグを再帰的に辿って取得した投稿、最大5件・古い順）。
    /// Android: `PostDetailScreen.kt` の ancestor thread に対応。
    var ancestors:    [ScoredPost] = []
    /// リプライ一覧（Kind 1、#e タグが元投稿 ID のもの）。
    var replies:      [ScoredPost] = []
    var isLoading:    Bool = true
    var isRefreshing: Bool = false
    var errorMessage: String? = nil

    // MARK: - Dependencies

    /// `internal let` — View から PostSheet・PostRow に渡すため公開。
    let repository:  NostrRepository
    let myPubkeyHex: String
    private let eventId: String

    // MARK: - Init

    init(repository: NostrRepository, myPubkeyHex: String, eventId: String) {
        self.repository   = repository
        self.myPubkeyHex  = myPubkeyHex
        self.eventId      = eventId
    }

    // MARK: - Load

    /// 元投稿とリプライを取得する。
    /// Android: `PostDetailScreen.kt` の `LaunchedEffect(eventId)` に対応。
    func loadPostAndReplies() async {
        isLoading    = true
        errorMessage = nil

        // 元投稿取得。更新時にリレーから一時的に取得できない場合でも、既に表示中の投稿は維持する。
        let rawEvent: NostrEvent
        if let fetched = await repository.fetchEvent(eventId: eventId) {
            rawEvent = fetched
        } else if let existing = post?.event {
            rawEvent = existing
        } else {
            errorMessage = "投稿が見つかりませんでした"
            isLoading    = false
            return
        }

        // enrichPosts は inout — 1 要素の配列でラップして呼ぶ
        var mainArr = [ScoredPost(event: rawEvent)]
        await repository.enrichPosts(&mainArr)
        post = mainArr.first

        // ── 祖先投稿を取得（e タグを再帰的に辿り最大5件） ──────────────────────
        // 辿った ID を記録してループを防ぐ
        var visitedIds: Set<String> = [eventId]
        var ancestorList: [ScoredPost] = []
        var currentEvent = rawEvent
        for _ in 0..<5 {
            // 最初の "e" タグ（親 or ルートへの参照）を取得
            guard let parentId = currentEvent.tags
                .first(where: { $0.first == "e" })?
                .dropFirst()
                .first,
                !parentId.isEmpty,
                !visitedIds.contains(parentId)
            else { break }
            visitedIds.insert(parentId)

            guard let parentEvent = await repository.fetchEvent(eventId: parentId) else { break }
            // 先頭（古い順）に挿入して最終的に時系列順にする
            ancestorList.insert(ScoredPost(event: parentEvent), at: 0)
            currentEvent = parentEvent
        }
        if !ancestorList.isEmpty {
            await repository.enrichPosts(&ancestorList)
        }
        ancestors = ancestorList

        // リプライ取得（Kind 1、#e タグが元投稿 ID）
        // Android: `NostrClient.Filter(kinds = listOf(TEXT_NOTE), tags = mapOf("e" to listOf(eventId)), limit = 50)`
        let replyFilter = NostrFilter(
            kinds:  [NostrKind.textNote],
            limit:  50,
            tags:   ["#e": [eventId]]
        )
        let replyEvents = await repository.fetchEvents(
            filters:        [replyFilter],
            timeoutSeconds: 5.0
        )

        var enrichedReplies = replyEvents
            .filter { $0.id != eventId }
            .sorted { $0.createdAt < $1.createdAt }
            .map { ScoredPost(event: $0) }

        await repository.enrichPosts(&enrichedReplies)
        replies   = enrichedReplies
        isLoading = false

        // プロフィール補完（バックグラウンド）
        Task { await enrichProfiles() }
    }

    private func enrichProfiles() async {
        var allPosts = replies + ancestors
        if let p = post { allPosts.append(p) }
        guard !allPosts.isEmpty else { return }

        let pubkeys  = Array(Set(allPosts.map { $0.event.pubkey }))
        let profiles = await repository.fetchProfiles(pubkeys: pubkeys)
        let map      = Dictionary(
            profiles.map { ($0.pubkey, $0) },
            uniquingKeysWith: { a, _ in a }
        )

        post?.profile = map[post?.event.pubkey ?? ""]
        for reply    in replies   { reply.profile    = map[reply.event.pubkey] }
        for ancestor in ancestors { ancestor.profile = map[ancestor.event.pubkey] }
        // @Observable 再描画トリガー（class 配列の内部変更は自動検知されない）
        replies   = replies
        ancestors = ancestors
    }

    // MARK: - Refresh

    func refresh() async {
        isRefreshing = true
        await loadPostAndReplies()
        isRefreshing = false
    }

    // MARK: - Interactions

    func toggleLike(post scoredPost: ScoredPost) async {
        let wasLiked = scoredPost.isLiked
        scoredPost.isLiked   = !wasLiked
        scoredPost.likeCount += wasLiked ? -1 : 1
        triggerUpdate()
        do {
            try await repository.publishReaction(
                to:           scoredPost.event.id,
                authorPubkey: scoredPost.event.pubkey
            )
        } catch {
            scoredPost.isLiked   = wasLiked
            scoredPost.likeCount += wasLiked ? 1 : -1
            triggerUpdate()
        }
    }

    func toggleRepost(post scoredPost: ScoredPost) async {
        guard !scoredPost.isReposted else { return }
        scoredPost.isReposted  = true
        scoredPost.repostCount += 1
        triggerUpdate()
        do {
            try await repository.publishRepost(event: scoredPost.event)
        } catch {
            scoredPost.isReposted  = false
            scoredPost.repostCount -= 1
            triggerUpdate()
        }
    }

    /// @Observable の再描画を強制する（配列要素の変更後）。
    ///
    /// @Observable はクラス配列の「要素内部の変更」を自動検知しない。
    /// replies・ancestors・post すべてを再代入してトリガーする。
    private func triggerUpdate() {
        replies   = replies
        ancestors = ancestors
        // post は直接 class ref なので再代入不要だが、nil ↔ 値変換がある場合に備えて触る
        if let p = post { post = p }
    }
}

// MARK: - View

/// 投稿詳細画面（スレッド表示）。
///
/// - 元投稿を上部に大きく表示
/// - リプライ一覧を下部に `LazyVStack` で表示
/// - リプライ入力 FAB → `PostSheet`（インライン `.sheet`）
/// - プル・トゥ・リフレッシュ
/// - スケルトンローダーで読み込み中状態を表示
///
/// Android 対応: `PostDetailScreen.kt`
struct PostDetailView: View {

    @State private var viewModel: PostDetailViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.nuruTheme) private var theme

    @State private var showReplySheet = false
    @State private var viewingProfile: ProfileID? = nil

    /// `ScoredPost` 直接渡し時の初期値（ロード前に表示するため）。
    private let initialPost: ScoredPost?
    private let showsInlineCloseButton: Bool

    // MARK: - Init

    /// `eventId` 指定で開く（NavigationLink 経由など）。
    init(
        eventId:     String,
        repository:  NostrRepository,
        myPubkeyHex: String
    ) {
        self.initialPost = nil
        self.showsInlineCloseButton = false
        _viewModel = State(
            wrappedValue: PostDetailViewModel(
                repository:  repository,
                myPubkeyHex: myPubkeyHex,
                eventId:     eventId
            )
        )
    }

    /// 既存の `ScoredPost` から開く（フィード上のセルタップ遷移）。
    init(
        post:        ScoredPost,
        repository:  NostrRepository,
        myPubkeyHex: String,
        showsInlineCloseButton: Bool = false
    ) {
        self.initialPost = post
        self.showsInlineCloseButton = showsInlineCloseButton
        _viewModel = State(
            wrappedValue: PostDetailViewModel(
                repository:  repository,
                myPubkeyHex: myPubkeyHex,
                eventId:     post.event.id
            )
        )
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            theme.bgPrimary.ignoresSafeArea()

            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: []) {
                    if showsInlineCloseButton {
                        HStack {
                            Button {
                                dismiss()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "chevron.backward")
                                        .font(.system(size: 13, weight: .semibold))
                                    Text("閉じる")
                                        .font(NuruFont.bodySmall())
                                        .fontWeight(.semibold)
                                }
                                .foregroundStyle(theme.textPrimary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(theme.bgSecondary)
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            Spacer()
                        }
                        .padding(.horizontal, NuruSpacing.space4)
                        .padding(.top, NuruSpacing.space3)
                        .padding(.bottom, NuruSpacing.space2)
                    }

                    contentBody
                }
            }
            .refreshable { await viewModel.refresh() }

            // リプライ入力フローティングボタン
            if !viewModel.isLoading && viewModel.errorMessage == nil {
                replyFAB
            }
        }
        .navigationTitle("投稿")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !showsInlineCloseButton {
                ToolbarItem(placement: .topBarLeading) {
                    Button("閉じる") { dismiss() }
                        .foregroundStyle(theme.textPrimary)
                }
            }
        }
        .toolbarBackground(theme.bgPrimary, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task {
            if let p = initialPost {
                // 元 ScoredPost が渡されていればまず表示し、バックグラウンドで詳細をロード
                viewModel.post      = p
                viewModel.isLoading = false
                Task { await viewModel.loadPostAndReplies() }
            } else {
                await viewModel.loadPostAndReplies()
            }
        }
        .sheet(item: $viewingProfile) { pid in
            UserProfileSheet(
                pubkey: pid.id,
                myPubkeyHex: viewModel.myPubkeyHex,
                repository: viewModel.repository
            )
        }
        .sheet(isPresented: $showReplySheet) {
            PostSheet(
                repository:  viewModel.repository,
                myPubkeyHex: viewModel.myPubkeyHex,
                myProfile:   viewModel.post?.profile,
                replyToId:   viewModel.post?.event.id,
                onDismiss:   { showReplySheet = false },
                onSuccess:   {
                    showReplySheet = false
                    Task { await viewModel.refresh() }
                }
            )
            .presentationDetents([.medium, .large])
        }
    }

    private func openProfile(_ pubkey: String) {
        viewingProfile = ProfileID(pubkey)
    }

    // MARK: - Content Body

    @ViewBuilder
    private var contentBody: some View {
        if viewModel.isLoading {
            // 引用元表示時は軽量なローディング（タイムライン用スケルトンを流用しない）
            VStack(spacing: NuruSpacing.space3) {
                ProgressView().tint(NuruColors.lineGreen)
                Text("投稿を読み込み中…")
                    .font(NuruFont.bodySmall())
                    .foregroundStyle(theme.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 72)
            .padding(.bottom, 40)
        } else if let errorMsg = viewModel.errorMessage {
            errorView(message: errorMsg)
        } else if let mainPost = viewModel.post {
            // 祖先投稿（古い順に上から表示）
            if !viewModel.ancestors.isEmpty {
                ForEach(viewModel.ancestors) { ancestor in
                    ancestorPostRow(ancestor)
                }
                // スレッドコネクター区切り
                ancestorDivider
            }

            // 元投稿（bgSecondary でハイライト）
            mainPostRow(mainPost)

            // リプライ区切り
            replyDivider

            // リプライ一覧
            repliesContent
        }
    }

    // MARK: - Ancestor Posts

    @ViewBuilder
    private func ancestorPostRow(_ ancestor: ScoredPost) -> some View {
        PostRow(
            post:         ancestor,
            repository:   viewModel.repository,
            onLike:       { await viewModel.toggleLike(post: ancestor) },
            onRepost:     { await viewModel.toggleRepost(post: ancestor) },
            onProfileTap: openProfile
        )
        .id(ancestor.event.id)
    }

    @ViewBuilder
    private var ancestorDivider: some View {
        EmptyView()
    }

    // MARK: - Main Post

    @ViewBuilder
    private func mainPostRow(_ mainPost: ScoredPost) -> some View {
        PostRow(
            post:        mainPost,
            repository:  viewModel.repository,
            onLike:      { await viewModel.toggleLike(post: mainPost) },
            onRepost:    { await viewModel.toggleRepost(post: mainPost) },
            onProfileTap: openProfile
        )
        // Android の PostDetailScreen 同様、元投稿を bgSecondary でハイライト
        .background(NuruColors.bgSecondary)
    }

    // MARK: - Reply Divider

    @ViewBuilder
    private var replyDivider: some View {
        EmptyView()
    }

    // MARK: - Replies

    @ViewBuilder
    private var repliesContent: some View {
        if viewModel.replies.isEmpty {
            // 空状態
            VStack(spacing: NuruSpacing.space3) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 36))
                    .foregroundStyle(theme.textTertiary)
                Text("まだリプライはありません")
                    .font(NuruFont.bodyMedium())
                    .foregroundStyle(theme.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 48)
            .padding(.bottom, 80) // FAB との重なり防止
        } else {
            ForEach(viewModel.replies) { reply in
                PostRow(
                    post:        reply,
                    repository:  viewModel.repository,
                    onLike:      { await viewModel.toggleLike(post: reply) },
                    onRepost:    { await viewModel.toggleRepost(post: reply) },
                    onProfileTap: openProfile
                )
                .id(reply.event.id)
            }
            // FAB との重なり防止パディング
            Color.clear.frame(height: 80)
        }
    }

    // MARK: - Error

    private func errorView(message: String) -> some View {
        VStack(spacing: NuruSpacing.space3) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundStyle(theme.textTertiary)
            Text(message)
                .font(NuruFont.bodyMedium())
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
        .padding(.horizontal, NuruSpacing.space4)
    }

    // MARK: - Reply FAB

    private var replyFAB: some View {
        Button {
            showReplySheet = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "bubble.left")
                    .font(.system(size: 16, weight: .semibold))
                Text("返信")
                    .font(NuruFont.buttonMedium())
            }
            .foregroundStyle(.white)
            .padding(.horizontal, NuruSpacing.space4)
            .padding(.vertical, 12)
            .background(NuruColors.lineGreen)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 3)
        }
        .padding(.trailing, NuruSpacing.space4)
        .padding(.bottom, NuruSpacing.space5)
    }
}
