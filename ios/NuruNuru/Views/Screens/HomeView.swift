import SwiftUI

/// Home screen — own profile (or other user's profile) with posts and likes tabs.
/// Mirrors Android HomeScreen.kt.
///
/// Structure mirrors Android:
///   TopAppBar (fixed) → ZStack { HorizontalPager, ProfileHeader overlay, ProfileTabs overlay }
///   Collapsing header: scroll up → header hides (0 → -headerHeight), scroll down → header reappears.
struct HomeView: View {

    let viewModel:      HomeViewModel
    let repository:     NostrRepository
    var onSettingsTap:  () -> Void        = {}
    var onPostTap:      () -> Void        = {}
    var onProfileTap:   (String) -> Void  = { _ in }   // kept for external callers
    var onMessageTap:   ((String) -> Void)? = nil

    @Environment(\.nuruTheme) private var theme

    // ── Modal states — mirrors Android HomeScreen ────────────────────────
    @State private var postToDelete:      String? = nil
    @State private var showDeleteConfirm          = false
    @State private var showEditProfile            = false
    @State private var showFollowList             = false
    @State private var showBookmarkList           = false   // mirrors Android showBookmarkList
    @State private var showQRCode                 = false   // mirrors Android showQRCode
    /// Other user's pubkey being viewed — mirrors Android viewingPubkey
    @State private var viewingPubkey:     String? = nil
    /// Currently selected pager page — mirrors Android pagerState.currentPage
    @State private var selectedPage:      Int     = 0
    @State private var isRefreshingProfile      = false

    // (Collapsing header removed — profile now scrolls with content naturally)

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {

                // ── Top App Bar — mirrors Android TopAppBar (fixed) ─────
                homeTopBar

                // ── Content area — profile + tabs + posts in single ScrollView ──
                // Profile and tabs scroll naturally with content (mirrors Android scroll behavior)
                scrollableContent
            }
            .background(theme.bgPrimary)

            // ── FAB — mirrors Android FloatingActionButton ───────────────
            if viewModel.isOwnProfile {
                Button(action: onPostTap) {
                    Image(systemName: NuruIcons.compose)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(NuruColors.lineGreen)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                }
                .padding(.trailing, NuruSpacing.space4)
                .padding(.bottom, NuruSpacing.space4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .zIndex(10)
            }

            if isRefreshingProfile {
                SoftRefreshIndicator(title: "更新中", compact: true)
                    .padding(.top, 56 + NuruSpacing.space2)
                    .allowsHitTesting(false)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(30)
            }
        }
        .background(theme.bgPrimary)
        .task { await viewModel.loadProfile() }

        // ── Delete confirmation — mirrors Android AlertDialog ────────────
        .confirmationDialog("この投稿を削除しますか？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("削除", role: .destructive) {
                if let id = postToDelete { Task { await viewModel.deletePost(id) } }
            }
            Button("キャンセル", role: .cancel) {}
        }

        // ── Bookmark list — mirrors Android BookmarkListModal ────────────
        .sheet(isPresented: $showBookmarkList) {
            BookmarkListSheet(
                repository:   repository,
                myPubkeyHex:  viewModel.myPubkeyHex,
                onProfileTap: { pk in
                    showBookmarkList = false
                    viewingPubkey = pk
                }
            )
        }

        // ── QR code — mirrors Android QRModal ────────────────────────────
        .sheet(isPresented: $showQRCode) {
            QRSheet(
                pubkeyHex: viewModel.myPubkeyHex,
                onScannedPubkey: { pk in
                    if pk != viewModel.myPubkeyHex {
                        viewingPubkey = pk
                    }
                }
            )
        }

        // ── Edit profile — mirrors Android EditProfileModal ───────────────
        .sheet(isPresented: $showEditProfile) {
            if let profile = viewModel.profile {
                EditProfileSheet(
                    profile:    profile,
                    repository: repository,
                    onSave:     { updated in
                        showEditProfile = false
                        Task { await saveProfile(updated) }
                    },
                    onDismiss: { showEditProfile = false }
                )
            }
        }

        // ── Follow list — mirrors Android FollowListModal ────────────────
        .sheet(isPresented: $showFollowList) {
            followListSheet
        }

        // ── Viewing other user's profile — mirrors Android viewingPubkey ─
        // UserProfileSheet is the iOS equivalent of Android UserProfileModal.
        .sheet(isPresented: Binding(
            get:  { viewingPubkey != nil },
            set:  { if !$0 { viewingPubkey = nil } }
        )) {
            viewingPubkeySheet
        }
    }

    // MARK: - Scrollable Content (profile + tabs + posts in single ScrollView)
    // プロフィールヘッダーが投稿と一緒にスクロールし、横スワイプでタブ切り替え。
    // Android の NestedScrollConnection + HorizontalPager に対応。

    @ViewBuilder
    private var scrollableContent: some View {
        let currentPosts = selectedPage == 0 ? viewModel.posts : viewModel.likedPosts

        ScrollView {
            LazyVStack(spacing: 0) {
                // プロフィールヘッダー（コンテンツと一緒にスクロール）
                profileHeaderSection

                // タブバー（Android HorizontalPager のタブに対応）
                ProfileTabs(
                    activeTab:     selectedPage,
                    onTabSelected: { page in
                        withAnimation(.easeInOut(duration: 0.2)) { selectedPage = page }
                        viewModel.activeTab = page
                    },
                    postCount:     viewModel.posts.count,
                    likeCount:     viewModel.likedPosts.count
                )

                // 投稿リスト（選択中のタブ）
                if viewModel.isLoading && viewModel.profile == nil {
                    TimelineLoadingSkeleton(count: 5)
                } else if currentPosts.isEmpty && viewModel.isLoading {
                    VStack { Spacer(); ProgressView().tint(NuruColors.lineGreen); Spacer() }
                        .frame(height: 200)
                } else if currentPosts.isEmpty {
                    emptyState(tab: selectedPage)
                } else {
                    ForEach(currentPosts, id: \.event.id) { post in
                        postRow(post: post)
                    }
                    Color.clear.frame(height: 80)
                }
            }
        }
        .refreshable {
            await MainActor.run {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) { isRefreshingProfile = true }
            }
            await viewModel.refresh()
            try? await Task.sleep(nanoseconds: 250_000_000)
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.22)) { isRefreshingProfile = false }
            }
        }
        // 横スワイプでタブ切り替え（Android HorizontalPager に対応）
        // simultaneousGesture を使用して ScrollView のスクロールを妨げない
        .simultaneousGesture(
            DragGesture(minimumDistance: 80, coordinateSpace: .local)
                .onEnded { value in
                    let hDelta = value.translation.width
                    let vDelta = abs(value.translation.height)
                    guard abs(hDelta) > vDelta * 1.5 else { return } // 縦スクロール優先
                    // Avoid stealing horizontal drags from multi-image carousels in posts.
                    // Profile tab swipes are accepted only from screen edges; tab buttons remain available.
                    let screenWidth = UIScreen.main.bounds.width
                    let edgeWidth: CGFloat = 32
                    guard value.startLocation.x <= edgeWidth || value.startLocation.x >= screenWidth - edgeWidth else { return }
                    if hDelta < -30 && selectedPage == 0 {
                        withAnimation(.easeInOut(duration: 0.2)) { selectedPage = 1 }
                        viewModel.activeTab = 1
                    } else if hDelta > 30 && selectedPage == 1 {
                        withAnimation(.easeInOut(duration: 0.2)) { selectedPage = 0 }
                        viewModel.activeTab = 0
                    }
                }
        )
    }

    // MARK: - PostRow builder (mirrors Android PostItem with all callbacks)

    @ViewBuilder
    private func postRow(post: ScoredPost) -> some View {
        PostRow(
            post:          post,
            repository:    repository,
            myPubkeyHex:   viewModel.myPubkeyHex,
            myProfile:     viewModel.profile,
            // ── Like (NIP-25, Kind 7) — mirrors Android onLike ─────────
            onLike: {
                viewModel.likePost(post.event.id)
            },
            // ── Repost (NIP-18, Kind 6) — mirrors Android onRepost ─────
            onRepost: {
                viewModel.repostPost(post.event.id)
            },
            // ── Bookmark (NIP-51, Kind 10003) — mirrors Android onBookmark
            onBookmark: {
                viewModel.addBookmark(post.event.id)
            },
            // ── Profile tap — mirrors Android onProfileClick ─────────────
            onProfileTap: { pubkey in
                if pubkey != viewModel.myPubkeyHex {
                    viewingPubkey = pubkey   // → UserProfileSheet (mirrors UserProfileModal)
                }
            },
            // ── Delete — mirrors Android onDelete ────────────────────────
            onDelete: post.event.pubkey == viewModel.myPubkeyHex ? {
                postToDelete     = post.event.id
                showDeleteConfirm = true
            } : nil,
            // ── Mute — mirrors Android onMute ────────────────────────────
            onMute: {
                viewModel.muteUser(post.event.pubkey)
            },
            // ── Report (NIP-56, Kind 1984) — mirrors Android onReport ───
            onReport: { type, content in
                viewModel.reportEvent(post.event.id, post.event.pubkey, type: type, content: content)
            },
            // ── Birdwatch — mirrors Android onBirdwatch ──────────────────
            onBirdwatch: { type, content, url in
                viewModel.submitBirdwatch(post.event.id, post.event.pubkey, type: type, content: content, url: url)
            }
        )
        .id(post.event.id)
    }

    // MARK: - Viewing Pubkey Sheet (mirrors Android UserProfileModal)

    @ViewBuilder
    private var viewingPubkeySheet: some View {
        if let pubkey = viewingPubkey {
            UserProfileSheet(
                pubkey:      pubkey,
                myPubkeyHex: viewModel.myPubkeyHex,
                repository:  repository,
                onStartDM: onMessageTap.map { handler in
                    { pk in viewingPubkey = nil; handler(pk) }
                }
            )
        }
    }

    // MARK: - Profile Header Section

    /// Extracted to help the Swift type-checker — mirrors Android ProfileHeader overlay.
    @ViewBuilder
    private var profileHeaderSection: some View {
        if viewModel.isLoading && viewModel.profile == nil {
            ProfileSkeleton()
                .background(theme.bgPrimary)
        } else {
            ProfileHeader(
                profile:          viewModel.profile,
                pubkey:           viewModel.targetPubkeyHex,
                isOwnProfile:     viewModel.isOwnProfile,
                isFollowing:      viewModel.isFollowing,
                isNip05Verified:  viewModel.isNip05Verified,
                followCount:      viewModel.followCount,
                badgeUrls:        viewModel.badgeUrls,
                repository:       repository,
                onEditClick:      { showEditProfile = true },
                onQRClick:        viewModel.isOwnProfile ? { showQRCode = true } : nil,
                onFollowClick: {
                    Task {
                        if viewModel.isFollowing { await viewModel.unfollowUser() }
                        else                     { await viewModel.followUser()   }
                    }
                },
                onMessageClick: onMessageTap.map { handler in
                    { handler(viewModel.targetPubkeyHex) }
                },
                onFollowListClick: { showFollowList = true }
            )
            .background(theme.bgPrimary)
        }
    }

    // MARK: - Top Bar

    private var homeTopBar: some View {
        VStack(spacing: 0) {
            HStack {
                Text("ホーム")
                    .font(NuruFont.titleLarge())
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                if viewModel.isOwnProfile {
                    // Mirrors Android: bookmark IconButton + settings IconButton
                    HStack(spacing: 2) {
                        Button(action: { showBookmarkList = true }) {
                            BookmarkIcon(filled: false)
                                .frame(width: 22, height: 22)
                                .foregroundStyle(theme.textSecondary)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Button(action: onSettingsTap) {
                            Image(systemName: "gearshape")
                                .font(.system(size: 21))
                                .foregroundStyle(theme.textSecondary)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(height: 56)
            .padding(.horizontal, NuruSpacing.space4)
            .background(theme.bgPrimary)

            Divider().background(theme.borderColor)
        }
    }

    // MARK: - Follow List Sheet

    private var followListSheet: some View {
        FollowListSheet(
            pubkeys:  viewModel.followList,
            profiles: [:],
            repository: repository,
            onDismiss:   { showFollowList = false },
            onUnfollow:  { pk in
                Task {
                    try? await repository.unfollowUser(targetPubkeyHex: pk)
                    await viewModel.loadProfile()
                }
                showFollowList = false
            },
            onProfileTap: { pk in
                showFollowList = false
                viewingPubkey = pk
            }
        )
    }

    // MARK: - Empty State (mirrors Android EmptyState composable)

    @ViewBuilder
    private func emptyState(tab: Int) -> some View {
        VStack(spacing: NuruSpacing.space4) {
            ZStack {
                Circle()
                    .fill(theme.bgSecondary)
                    .frame(width: 64, height: 64)
                Image(systemName: tab == 0 ? "square.and.pencil" : NuruIcons.like(filled: false))
                    .font(.system(size: 32))
                    .foregroundStyle(theme.textTertiary)
            }
            Text(tab == 0 ? "投稿がありません" : "いいねがありません")
                .font(.system(size: 14))
                .foregroundStyle(theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, NuruSpacing.space10)
    }

    // MARK: - Save Profile

    private func saveProfile(_ updated: UserProfile) async {

        // Optimistic UI update + cache update — mirrors Android HomeViewModel.updateProfile
        viewModel.profile = updated
        await repository.cacheProfile(updated)
        do {
            try await repository.updateProfile(profile: updated)
            AppLogger.log("HomeView", "Profile (Kind 0) published successfully — banner=\(updated.banner ?? "nil")")
        } catch {
            AppLogger.log("HomeView", "Profile publish failed: \(error.localizedDescription)")
        }
    }


}
