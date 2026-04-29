import SwiftUI

/// 他ユーザーのプロフィールシート.
/// Mirrors Android UserProfileModal.kt.
struct UserProfileSheet: View {

    let pubkey:      String
    let myPubkeyHex: String
    let repository:  NostrRepository
    var onStartDM:   ((String) -> Void)? = nil

    @Environment(\.dismiss)    private var dismiss
    @Environment(\.nuruTheme) private var theme

    @State private var vm: HomeViewModel
    @State private var showFollowList = false
    @State private var showSearch     = false
    @State private var searchQuery    = ""
    @State private var showMenu       = false
    @State private var postToDelete:  String? = nil
    @State private var showDeleteConfirm      = false
    @State private var showMentionPostSheet   = false

    init(pubkey: String, myPubkeyHex: String, repository: NostrRepository, onStartDM: ((String) -> Void)? = nil) {
        self.pubkey      = pubkey
        self.myPubkeyHex = myPubkeyHex
        self.repository  = repository
        self.onStartDM   = onStartDM
        _vm = State(initialValue: HomeViewModel(
            repository: repository, myPubkeyHex: myPubkeyHex, targetPubkeyHex: pubkey
        ))
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                // ── Top bar ─────────────────────────────────────────────────
            topBar

                // ── Search bar ───────────────────────────────────────────────
                if showSearch {
                searchBar
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

                Divider().background(theme.borderColor)

                // ── Content ─────────────────────────────────────────────────
                ScrollView {
                LazyVStack(spacing: 0) {
                    ProfileHeader(
                        profile:          vm.profile,
                        pubkey:           pubkey,
                        isOwnProfile:     false,
                        isFollowing:      vm.isFollowing,
                        isNip05Verified:  vm.isNip05Verified,
                        followCount:      vm.followCount,
                        badgeUrls:        vm.badgeUrls,
                        repository:       repository,
                        onFollowClick: {
                            Task {
                                if vm.isFollowing { await vm.unfollowUser() }
                                else              { await vm.followUser()   }
                            }
                        },
                        onMessageClick: onStartDM.map { handler in { handler(pubkey) } },
                        onFollowListClick: { showFollowList = true }
                    )

                    ProfileTabs(
                        activeTab:     vm.activeTab,
                        onTabSelected: { vm.activeTab = $0 },
                        postCount:     vm.posts.count,
                        likeCount:     vm.likedPosts.count
                    )

                    if vm.isLoading {
                        TimelineLoadingSkeleton(count: 4)
                    } else {
                        let display = vm.activeTab == 0 ? vm.posts : vm.likedPosts
                        if display.isEmpty {
                            emptyState(tab: vm.activeTab)
                        } else {
                            ForEach(display, id: \.id) { post in
                                PostRow(
                                    post:         post,
                                    repository:   repository,
                                    myPubkeyHex:  myPubkeyHex,
                                    onLike: {
                                        try? await repository.publishReaction(to: post.event.id, authorPubkey: post.event.pubkey)
                                        post.isLiked = true
                                        post.likeCount += 1
                                    },
                                    onRepost: {
                                        try? await repository.publishRepost(event: post.event)
                                        post.isReposted = true
                                        post.repostCount += 1
                                    },
                                    onProfileTap: { _ in }
                                )
                                .id(post.event.id)
                            }
                        }
                    }
                }
            }
            .refreshable { await vm.refresh() }
            .background(theme.bgPrimary)
            // 横スワイプでタブ切り替え
            .gesture(
                DragGesture(minimumDistance: 50, coordinateSpace: .local)
                    .onEnded { value in
                        let hDelta = value.translation.width
                        let vDelta = abs(value.translation.height)
                        guard abs(hDelta) > vDelta else { return }
                        if hDelta < -30 && vm.activeTab == 0 {
                            withAnimation(.easeInOut(duration: 0.2)) { vm.activeTab = 1 }
                        } else if hDelta > 30 && vm.activeTab == 1 {
                            withAnimation(.easeInOut(duration: 0.2)) { vm.activeTab = 0 }
                        }
                    }
            )
            }

            Button { showMentionPostSheet = true } label: {
                Image(systemName: NuruIcons.compose)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(NuruColors.lineGreen)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
            }
            .buttonStyle(.plain)
            .padding(.trailing, NuruSpacing.space4)
            .padding(.bottom, NuruSpacing.space4)
            .zIndex(10)
        }
        .background(theme.bgPrimary.ignoresSafeArea())
        .task { await vm.loadProfile() }
        .animation(.easeInOut(duration: 0.2), value: showSearch)
        .confirmationDialog("この投稿を削除しますか？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("削除", role: .destructive) {
                if let id = postToDelete { Task { await vm.deletePost(id) } }
            }
            Button("キャンセル", role: .cancel) {}
        }
        .sheet(isPresented: $showMentionPostSheet) {
            PostSheet(
                repository:  repository,
                myPubkeyHex: myPubkeyHex,
                myProfile:   repository.getCachedProfile(pubkey: myPubkeyHex),
                initialMentionProfile: vm.profile ?? UserProfile(pubkey: pubkey),
                onDismiss:   { showMentionPostSheet = false },
                onSuccess:   {
                    showMentionPostSheet = false
                    Task { await vm.refresh() }
                }
            )
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showFollowList) {
            FollowListSheet(
                pubkeys:      vm.followList,
                profiles:     [:],
                repository:   repository,
                onDismiss:    { showFollowList = false },
                onUnfollow:   { _ in showFollowList = false },
                onProfileTap: { _ in showFollowList = false }
            )
        }
    }


    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 0) {
            Button {
                dismiss()
            } label: {
                Image(systemName: NuruIcons.back)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(theme.textPrimary)
                    .frame(width: 44, height: 56)
            }
            .buttonStyle(.plain)

            Text("プロフィール")
                .font(NuruFont.titleMedium())
                .fontWeight(.bold)
                .foregroundStyle(theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, NuruSpacing.space2)

            // Search toggle
            Button {
                withAnimation { showSearch.toggle() }
                if !showSearch { searchQuery = "" }
            } label: {
                Image(systemName: NuruIcons.search)
                    .font(.system(size: 20))
                    .foregroundStyle(showSearch ? NuruColors.lineGreen : theme.textSecondary)
                    .frame(width: 44, height: 56)
            }
            .buttonStyle(.plain)

            // ⋮ menu (mute)
            Menu {
                Button(role: .destructive) {
                    Task {
                        try? await repository.muteUser(pubkeyHex: pubkey, isPrivate: true)
                        dismiss()
                    }
                } label: {
                    Label("ミュート", systemImage: NuruIcons.mute)
                }
            } label: {
                Image(systemName: NuruIcons.moreVert)
                    .font(.system(size: 20))
                    .foregroundStyle(theme.textSecondary)
                    .frame(width: 44, height: 56)
            }
        }
        .frame(height: 56)
        .padding(.horizontal, NuruSpacing.space2)
        .background(theme.bgPrimary)
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: NuruSpacing.space2) {
            Image(systemName: NuruIcons.search)
                .font(.system(size: 14))
                .foregroundStyle(theme.textTertiary)
            TextField("投稿を検索...", text: $searchQuery)
                .font(NuruFont.bodySmall())
                .foregroundStyle(theme.textPrimary)
                .submitLabel(.search)
        }
        .padding(NuruSpacing.space3)
        .background(theme.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusMd))
        .padding(.horizontal, NuruSpacing.space4)
        .padding(.vertical, NuruSpacing.space2)
        .background(theme.bgPrimary)
    }

    // MARK: - Empty State

    @ViewBuilder
    private func emptyState(tab: Int) -> some View {
        VStack(spacing: NuruSpacing.space3) {
            Image(systemName: tab == 0 ? "square.and.pencil" : NuruIcons.like(filled: true))
                .font(.system(size: NuruSpacing.avatarSm))
                .foregroundStyle(theme.textTertiary)
            Text(tab == 0 ? "投稿がありません" : "いいねがありません")
                .font(NuruFont.bodyMedium())
                .foregroundStyle(theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, NuruSpacing.space10)
    }
}
