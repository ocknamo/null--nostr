import SwiftUI

/// Main timeline screen — リレー tab and フォロー tab.
/// Mirrors Android TimelineScreen.kt: HorizontalPager + pull-to-refresh + FAB.
struct TimelineView: View {

    @Bindable var viewModel: TimelineViewModel

    var onPostTap:           () -> Void        = {}
    var onProfileTap:        (String) -> Void  = { _ in }
    var onNotificationBell:  () -> Void        = {}
    var onSearchTap:         () -> Void        = {}

    @Environment(\.nuruTheme) private var theme
    @State private var selectedPage:  Int        = 1   // 0 = リレー, 1 = フォロー (default)
    @State private var showZapSheet:  Bool        = false
    @State private var activeZapPost: ScoredPost? = nil
    /// スクロールトップへのトリガー — pill タップ時にインクリメント
    @State private var scrollToTopTrigger: Int    = 0
    @State private var showRelayPicker: Bool      = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                timelineTopBar

                ZStack(alignment: .top) {
                    TabView(selection: $selectedPage) {
                        relayFeed.tag(0)
                        followingFeed.tag(1)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))

                    // New Posts Pill — mirrors Android TimelineScreen AnimatedVisibility pill
                    let showPill = (selectedPage == 0 && viewModel.hasNewRelayPosts)
                                || (selectedPage == 1 && viewModel.hasNewFollowingPosts)
                    let pillCount = selectedPage == 0
                        ? viewModel.newRelayPostCount
                        : viewModel.newFollowingPostCount
                    if showPill {
                        NewPostsPill(count: pillCount) {
                            viewModel.insertPendingPosts()
                            scrollToTopTrigger += 1
                        }
                        .padding(.top, 8)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .offset(y: -30)),
                            removal:   .opacity.combined(with: .offset(y: -30))
                        ))
                    }
                }
                .animation(.easeInOut(duration: NuruSpacing.durationFast), value: showPillKey)
            }
            .background(theme.bgPrimary)
            // Sync ViewModel feedType ↔ page selection
            .onChange(of: selectedPage) { _, page in
                viewModel.switchFeed(page == 0 ? .relay : .following)
            }
            .onChange(of: viewModel.feedType) { _, feed in
                let page = feed == .relay ? 0 : 1
                if selectedPage != page { selectedPage = page }
            }

            // Zap sheet
            .sheet(isPresented: $showZapSheet) {
                if let zapPost = activeZapPost {
                    ZapSheet(
                        repository:  viewModel.repository,
                        myPubkeyHex: viewModel.pubkeyHex,
                        targetPost:  zapPost
                    )
                    .presentationDetents([.medium])
                }
            }

            if showRelayPicker {
                Color.black.opacity(0.18)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            showRelayPicker = false
                        }
                    }
                    .zIndex(8)

                relayPickerOverlay
                    .zIndex(9)
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .topLeading)))
            }

            // FAB — .safeAreaInset in MainTabView handles tab bar clearance automatically.
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
        }
    }

    // MARK: - Top Bar

    private var timelineTopBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: NuruSpacing.space2) {
                // Pill-style tab switcher (mirrors Android TimelineHeader)
                HStack(spacing: NuruSpacing.space2) {
                    relayPillButton
                    followPillButton
                }
                .padding(4)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 20))

                Spacer(minLength: 0)

                // Search
                Button(action: onSearchTap) {
                    Image(systemName: NuruIcons.search)
                        .font(.system(size: 20))
                        .foregroundStyle(theme.textTertiary)
                        .frame(width: 40, height: 40)
                }
                // Notification bell (no badge — notification unread count is separate from timeline new posts)
                Button(action: onNotificationBell) {
                    Image(systemName: NuruIcons.bell)
                        .font(.system(size: 20))
                        .foregroundStyle(theme.textTertiary)
                        .frame(width: 40, height: 40)
                }
            }
            .frame(height: 56)
            .padding(.horizontal, NuruSpacing.space4)
            .background(Color.black)

            Divider().background(theme.borderColor)
        }
    }

    // MARK: - Pill Buttons

    @ViewBuilder
    private var relayPillButton: some View {
        let selected = selectedPage == 0
        let relayLabel: String = {
            if let url = viewModel.selectedRelayUrl {
                let host = url.replacingOccurrences(of: "wss://", with: "")
                    .replacingOccurrences(of: "ws://", with: "")
                    .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    .components(separatedBy: "/").first ?? "リレー"
                // フォローピルの幅を確保するため短めに固定
                return host.count > 12 ? String(host.prefix(12)) + "…" : host
            }
            return "リレー"
        }()

        ZStack(alignment: .topTrailing) {
            Button {
                selectedPage = 0
                withAnimation(.easeInOut(duration: 0.16)) {
                    showRelayPicker = true
                }
            } label: {
                HStack(spacing: 2) {
                    Text(relayLabel)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(selected ? .white : theme.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: true, vertical: false)
                    if !viewModel.savedRelayUrls.isEmpty {
                        Image(systemName: NuruIcons.chevronDown)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(selected ? .white : theme.textTertiary)
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(selected ? NuruColors.lineGreen : Color.clear)
                .clipShape(Capsule())
                .contentShape(Capsule())
                .fixedSize(horizontal: true, vertical: true)
                .animation(nil, value: relayLabel)
            }
            .buttonStyle(.plain)

            // New-post dot
            if viewModel.hasNewRelayPosts && !selected {
                Circle()
                    .fill(NuruColors.lineGreen)
                    .frame(width: 10, height: 10)
                    .overlay(Circle().stroke(theme.bgSecondary, lineWidth: 2))
                    .offset(x: 2, y: -2)
            }
        }
    }

    private var followPillButton: some View {
        let selected = selectedPage == 1
        return ZStack(alignment: .topTrailing) {
            Button {
                selectedPage = 1
            } label: {
                Text("フォロー")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(selected ? .white : theme.textTertiary)
                    .lineLimit(1)
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .background(selected ? NuruColors.lineGreen : Color.clear)
                    .clipShape(Capsule())
                    .fixedSize(horizontal: true, vertical: true)
            }
            .buttonStyle(.plain)

            // New-post dot
            if viewModel.hasNewFollowingPosts && !selected {
                Circle()
                    .fill(NuruColors.lineGreen)
                    .frame(width: 10, height: 10)
                    .overlay(Circle().stroke(theme.bgSecondary, lineWidth: 2))
                    .offset(x: 2, y: -2)
            }
        }
    }

    // MARK: - Helpers

    /// Key used to drive .animation — changes whenever the visible pill state changes.
    private var showPillKey: Bool {
        (selectedPage == 0 && viewModel.hasNewRelayPosts)
        || (selectedPage == 1 && viewModel.hasNewFollowingPosts)
    }

    @ViewBuilder
    private var relayPickerOverlay: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("リレーを選択")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.95))
                .padding(.horizontal, 12)
                .padding(.top, 4)

            relayPickerRow(
                title: "すべて",
                selected: viewModel.selectedRelayUrl == nil,
                action: {
                    selectedPage = 0
                    viewModel.selectRelay(nil)
                    withAnimation(.easeInOut(duration: 0.16)) { showRelayPicker = false }
                }
            )

            ForEach(viewModel.savedRelayUrls, id: \.self) { url in
                let display = url.replacingOccurrences(of: "wss://", with: "")
                    .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                relayPickerRow(
                    title: display,
                    selected: viewModel.selectedRelayUrl == url,
                    action: {
                        selectedPage = 0
                        let next = viewModel.selectedRelayUrl == url ? nil : url
                        viewModel.selectRelay(next)
                        withAnimation(.easeInOut(duration: 0.16)) { showRelayPicker = false }
                    }
                )
            }
        }
        .padding(12)
        .frame(maxWidth: 300, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(0.22), lineWidth: 1)
                )
        }
        .shadow(color: .black.opacity(0.32), radius: 18, x: 0, y: 8)
        .padding(.leading, 12)
        .padding(.top, 78)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func relayPickerRow(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 19, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                }
            }
            .foregroundStyle(.white.opacity(0.95))
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(selected ? NuruColors.lineGreen.opacity(0.7) : Color.white.opacity(0.14), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Relay Feed (リレー)

    private var relayFeed: some View {
        feedList(
            posts: viewModel.relayPosts,
            isLoading: viewModel.isRelayLoading,
            isRefreshing: viewModel.isRelayRefreshing,
            emptyText: "リレーに投稿がありません",
            emptyIcon: "doc.text",
            onRefresh: { await viewModel.refreshRelay() }
        )
    }

    // MARK: - Following Feed (フォロー)

    private var followingFeed: some View {
        feedList(
            posts: viewModel.followingPosts,
            isLoading: viewModel.isFollowingLoading,
            isRefreshing: viewModel.isFollowingRefreshing,
            emptyText: viewModel.followList.isEmpty
                ? "フォローしているユーザーがいません"
                : "フォロータイムラインに投稿がありません",
            emptyIcon: "heart",
            onRefresh: { await viewModel.refreshFollowing() }
        )
    }

    // MARK: - Feed List

    @ViewBuilder
    private func feedList(
        posts: [ScoredPost],
        isLoading: Bool,
        isRefreshing: Bool,
        emptyText: String,
        emptyIcon: String = "doc.text",
        onRefresh: @escaping () async -> Void
    ) -> some View {
        if isLoading && posts.isEmpty {
            ScrollView {
                TimelineLoadingSkeleton(count: 8)
            }
            .background(theme.bgPrimary)
        } else if posts.isEmpty && !isLoading {
            VStack(spacing: 12) {
                Spacer()
                ZStack {
                    Circle()
                        .fill(theme.bgSecondary)
                        .frame(width: 64, height: 64)
                    Image(systemName: emptyIcon)
                        .font(.system(size: 32))
                        .foregroundStyle(theme.textTertiary)
                }
                Text(emptyText)
                    .font(.system(size: 14))
                    .foregroundStyle(theme.textTertiary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .background(theme.bgPrimary)
            .refreshable { await onRefresh() }
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        // スクロールトップ用アンカー
                        Color.clear.frame(height: 0).id("timeline-top")

                        ForEach(posts, id: \.id) { post in
                            postCell(post)
                        }
                    }
                }
                .background(theme.bgPrimary)
                .refreshable { await onRefresh() }
                .onChange(of: scrollToTopTrigger) { _, _ in
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo("timeline-top", anchor: .top)
                    }
                }
            }
        }
    }

    // MARK: - Post Cell

    @ViewBuilder
    private func postCell(_ post: ScoredPost) -> some View {
        let isOwn = post.event.pubkey == viewModel.pubkeyHex
        let zapAction: () -> Void = {
            activeZapPost = post
            showZapSheet  = true
        }
        let deleteAction: (() -> Void)? = isOwn
            ? { Task { await viewModel.deletePost(post) } } : nil
        let muteAction: (() -> Void)? = !isOwn
            ? { Task { await viewModel.muteUser(post.event.pubkey) } } : nil
        let reportAction: ((String, String) -> Void)? = !isOwn
            ? { type, content in Task { await viewModel.reportEvent(post: post, type: type, content: content) } } : nil
        let birdwatchAction: (String, String, String) -> Void = { type, content, url in
            Task { await viewModel.submitBirdwatch(post: post, type: type, content: content, url: url) }
        }

        if post.event.kind == NostrKind.longForm {
            LongFormPostItem(
                post:         post,
                repository:   viewModel.repository,
                onLike:       { await viewModel.toggleLike(post: post) },
                onRepost:     { await viewModel.toggleRepost(post: post) },
                onProfileTap: onProfileTap,
                onZap:        zapAction,
                onDelete:     deleteAction,
                onMute:       muteAction,
                onReport:     reportAction,
                onBirdwatch:  birdwatchAction
            )
        } else {
            PostRow(
                post:           post,
                repository:     viewModel.repository,
                myPubkeyHex:    viewModel.pubkeyHex,
                onLike:         { await viewModel.toggleLike(post: post) },
                onRepost:       { await viewModel.toggleRepost(post: post) },
                onZap:          zapAction,
                onZapLongPress: zapAction,
                onBookmark:     { await viewModel.toggleBookmark(post: post) },
                onProfileTap:   onProfileTap,
                onDelete:       deleteAction,
                onMute:         muteAction,
                onReport:       reportAction,
                onBirdwatch:    birdwatchAction
            )
        }
    }
}

// MARK: - New Posts Pill

/// Floating pill shown when new posts are available — mirrors Android TimelineScreen pill.
/// Tap to refresh the feed and dismiss.
private struct NewPostsPill: View {
    let count: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 11, weight: .semibold))
                Text("新しい投稿 \(count)件")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(NuruColors.lineGreen)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
}
