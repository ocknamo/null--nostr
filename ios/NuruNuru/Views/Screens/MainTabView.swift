import SwiftUI

/// 4-tab navigation shell — ホーム / トーク / タイムライン / ミニアプリ.
/// Mirrors Android MainScreen.kt: AnimatedVisibility tabs, black bottom nav.
struct MainTabView: View {

    let pubkeyHex:    String
    let authViewModel: AuthViewModel

    @Environment(\.nuruTheme) private var theme
    @Environment(\.scenePhase) private var scenePhase
    @State private var activeTab:          BottomTab  = .timeline
    @State private var showPostSheet:      Bool       = false
    @State private var showNotifications:  Bool       = false
    @State private var showSearch:         Bool       = false
    @State private var searchInitialQuery: String     = ""
    @State private var viewingProfile:     ProfileID? = nil
    @State private var zapTarget:          ScoredPost? = nil
    @State private var hideBottomNavForExternalMiniApp: Bool = false
    @State private var didLoadTalkGroups: Bool = false
    @State private var showAppSettings:  Bool       = false

    // Shared repository — created once per session.
    @State private var repository: NostrRepository

    // ViewModels
    @State private var timelineVM:    TimelineViewModel
    @State private var homeVM:        HomeViewModel
    @State private var talkVM:        TalkViewModel
    @State private var connectionVM:  ConnectionViewModel

    init(pubkeyHex: String, authViewModel: AuthViewModel) {
        self.pubkeyHex     = pubkeyHex
        self.authViewModel = authViewModel

        // FFI is initialized lazily inside NostrRepository.ensureMlsClient().
        // Keep startup path stable and avoid early init_engine() lock-in on bad paths.
        let mlsClient: MlsFFIBridge? = nil

        let repo = NostrRepository(
            keyManager: authViewModel.keyManager,
            prefs:      authViewModel.prefs,
            mlsClient:  mlsClient
        )
        _repository     = State(initialValue: repo)
        _timelineVM     = State(initialValue: TimelineViewModel(repository: repo, pubkeyHex: pubkeyHex))
        _homeVM         = State(initialValue: HomeViewModel(repository: repo, myPubkeyHex: pubkeyHex))
        _talkVM         = State(initialValue: TalkViewModel(repository: repo, myPubkeyHex: pubkeyHex))
        _connectionVM   = State(initialValue: ConnectionViewModel(repository: repo))
    }

    var body: some View {
        ZStack {
            // CONNECTION STATUS BANNER (shown when disconnected/offline)
            VStack(spacing: 0) {
                ConnectionStatusBanner(viewModel: connectionVM)
                Spacer(minLength: 0)
            }
            .zIndex(10)
            .animation(.easeInOut(duration: 0.2), value: connectionVM.isFullyConnected)

            // TIMELINE (keep alive)
            tabContent(for: .timeline) {
                TimelineView(
                    viewModel:           timelineVM,
                    onPostTap:           { showPostSheet     = true },
                    onProfileTap:        { viewingProfile    = ProfileID($0) },
                    onNotificationBell:  { showNotifications = true },
                    onSearchTap:         {
                        searchInitialQuery = ""
                        showSearch        = true
                    },
                    onHashtagTap: { tag in
                        // Present the search sheet on the next run loop after updating
                        // the initial query. With a Bool sheet, SwiftUI can build the
                        // sheet content from the previous state snapshot, which made the
                        // first hashtag tap open an empty search and only the second tap
                        // run the #tag search.
                        searchInitialQuery = "#\(tag)"
                        if showSearch {
                            showSearch = false
                        }
                        DispatchQueue.main.async {
                            showSearch = true
                        }
                    }
                )
            }

            // HOME (keep alive)
            tabContent(for: .home) {
                HomeView(
                    viewModel:    homeVM,
                    repository:   repository,
                    onSettingsTap: { showAppSettings = true },
                    onPostTap:    { showPostSheet  = true },
                    onProfileTap: { viewingProfile = ProfileID($0) },
                    onMessageTap: { pubkey in
                        // DM ボタン — Android 同様トークタブに遷移 + DM 作成
                        activeTab = .talk
                        if !didLoadTalkGroups { didLoadTalkGroups = true }
                        Task { await talkVM.loadGroups(); await talkVM.createDmConversation(pubkey: pubkey) }
                    }
                )
            }

            // TALK (keep alive)
            tabContent(for: .talk) {
                TalkView(viewModel: talkVM)
            }

            // MINIAPP (recreated on demand)
            if activeTab == .miniapp {
                SettingsView(
                    pubkeyHex:    pubkeyHex,
                    authViewModel: authViewModel,
                    repository:   repository,
                    prefs:        authViewModel.prefs,
                    connectionVM: connectionVM,
                    onExternalAppFullscreenChanged: { hidden in
                        hideBottomNavForExternalMiniApp = hidden
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity.animation(.easeInOut(duration: NuruSpacing.durationFast)))
            }
        }
        // safeAreaInset places the tab bar below content and automatically
        // adjusts child safe areas so FABs and scroll views clear the tab bar.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !(activeTab == .miniapp && hideBottomNavForExternalMiniApp) {
                bottomNavBar
            }
        }
        // PostSheet
        .sheet(isPresented: $showPostSheet) {
            PostSheet(
                repository:  repository,
                myPubkeyHex: pubkeyHex,
                myProfile:   homeVM.profile,
                onDismiss:   { showPostSheet = false },
                onSuccess:   {
                    showPostSheet = false
                    Task {
                        await timelineVM.refreshRelay()
                        if homeVM.isOwnProfile { await homeVM.refresh() }
                    }
                }
            )
        }
        // NotificationSheet
        .sheet(isPresented: $showNotifications) {
            NotificationSheet(
                repository:   repository,
                myPubkeyHex:  pubkeyHex,
                prefs:        authViewModel.prefs,
                onProfileTap: { pubkey in
                    showNotifications = false
                    viewingProfile    = ProfileID(pubkey)
                }
            )
        }
        // SearchSheet
        .sheet(isPresented: $showSearch) {
            SearchSheet(
                repository:   repository,
                myPubkeyHex:  pubkeyHex,
                onProfileTap: { pubkey in
                    showSearch     = false
                    viewingProfile = ProfileID(pubkey)
                },
                initialQuery: searchInitialQuery,
                onDismiss: { showSearch = false; searchInitialQuery = "" }
            )
        }
        // ZapSheet
        .sheet(item: $zapTarget) { post in
            ZapSheet(
                repository:   repository,
                myPubkeyHex:  pubkeyHex,
                targetPost:   post
            )
        }
        .sheet(isPresented: $showAppSettings) {
            AppSettingsView(
                onDismiss: { showAppSettings = false },
                onLogout: { authViewModel.logout() }
            )
        }
        // UserProfileSheet — mirrors Android UserProfileModal with DM button
        .sheet(item: $viewingProfile) { pid in
            UserProfileSheet(
                pubkey:      pid.id,
                myPubkeyHex: pubkeyHex,
                repository:  repository,
                onStartDM: { pubkey in
                    viewingProfile = nil
                    activeTab = .talk
                    if !didLoadTalkGroups { didLoadTalkGroups = true }
                    Task { await talkVM.loadGroups(); await talkVM.createDmConversation(pubkey: pubkey) }
                }
            )
        }
        .task {
            timelineVM.startInitialLoadIfNeeded()
            await repository.connect()
            await repository.drainMlsRetryQueue(trigger: "mainTabTask", maxItems: 3)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await repository.drainMlsRetryQueue(trigger: "foreground", maxItems: 4) }
            }
        }
    }

    // MARK: - Tab Content

    @ViewBuilder
    private func tabContent<V: View>(for tab: BottomTab, @ViewBuilder content: () -> V) -> some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(activeTab == tab ? 1 : 0)
            .animation(.easeInOut(duration: NuruSpacing.durationFast), value: activeTab)
            .allowsHitTesting(activeTab == tab)
    }

    // MARK: - Bottom Nav Bar

    private var bottomNavBar: some View {
        VStack(spacing: 0) {
            Divider()
                .background(theme.borderColor)
                .frame(height: 0.5)
            HStack(spacing: 0) {
                ForEach(BottomTab.allCases, id: \.self) { tab in
                    bottomTabItem(tab)
                }
            }
            .frame(height: 56)
        }
        // Extend the black background into the home-indicator safe area.
        .background(Color.black.ignoresSafeArea(edges: .bottom))
    }

    private func bottomTabItem(_ tab: BottomTab) -> some View {
        let selected = activeTab == tab
        let iconColor = selected ? NuruColors.lineGreen : theme.textTertiary
        return Button {
            if activeTab == tab {
                switch tab {
                case .timeline: Task { await timelineVM.refreshRelay() }
                case .home:     Task { await homeVM.refresh() }
                default: break
                }
            }
            activeTab = tab
            if tab == .talk, !didLoadTalkGroups {
                didLoadTalkGroups = true
                Task { await talkVM.loadGroups() }
            }
        } label: {
            VStack(spacing: 2) {
                // All custom icons — matches Android NuruIcons exactly
                Group {
                    switch tab {
                    case .home:     HomeIcon(filled: selected)
                    case .talk:     TalkIcon(filled: selected)
                    case .timeline: TimelineIcon(filled: selected)
                    case .miniapp:  GridIcon(filled: selected)
                    }
                }
                .frame(width: NuruSpacing.iconLg, height: NuruSpacing.iconLg)
                .foregroundStyle(iconColor)

                Text(tab.label)
                    .font(NuruFont.labelSmall())
                    .fontWeight(selected ? .semibold : .regular)
                    .foregroundStyle(iconColor)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Supporting Types

/// Identifiable wrapper for String, used with .sheet(item:) for profile navigation.
struct ProfileID: Identifiable {
    let id: String
    init(_ id: String) { self.id = id }
}

// MARK: - Bottom Tab Enum

enum BottomTab: CaseIterable {
    case home, talk, timeline, miniapp

    var label: String {
        switch self {
        case .home:     return "ホーム"
        case .talk:     return "トーク"
        case .timeline: return "タイムライン"
        case .miniapp:  return "ミニアプリ"
        }
    }

    var iconFilled: String {
        switch self {
        case .home:     return NuruIcons.home(filled: true)
        case .talk:     return NuruIcons.talk(filled: true)
        case .timeline: return NuruIcons.timeline(filled: true)
        case .miniapp:  return NuruIcons.grid(filled: true)
        }
    }

    var iconOutline: String {
        switch self {
        case .home:     return NuruIcons.home(filled: false)
        case .talk:     return NuruIcons.talk(filled: false)
        case .timeline: return NuruIcons.timeline(filled: false)
        case .miniapp:  return NuruIcons.grid(filled: false)
        }
    }
}

// MARK: - Connection Status Banner

/// オフライン・切断時に画面上部に表示するバナー。
/// Mirrors Android のネットワーク状態インジケーター。
private struct ConnectionStatusBanner: View {
    let viewModel: ConnectionViewModel

    var body: some View {
        if !viewModel.isFullyConnected {
            HStack(spacing: 6) {
                Image(systemName: viewModel.isOnline ? "wifi.exclamationmark" : "wifi.slash")
                    .font(.system(size: 12, weight: .semibold))
                Text(viewModel.statusMessage)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                if viewModel.isOnline && viewModel.connectionState != .connecting {
                    Button {
                        Task { await viewModel.reconnect() }
                    } label: {
                        Text("再接続")
                            .font(.system(size: 12, weight: .bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 3)
                            .background(Color.white.opacity(0.2))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, NuruSpacing.space4)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(bannerColor)
        }
    }

    private var bannerColor: Color {
        viewModel.isOnline ? Color(red: 0.8, green: 0.4, blue: 0.0) : Color(red: 0.7, green: 0.1, blue: 0.1)
    }
}

// MARK: - Placeholder

private struct PlaceholderTab: View {
    let title:   String
    let message: String
    @Environment(\.nuruTheme) private var theme
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: NuruSpacing.space3) {
            Text(title).font(NuruFont.titleLarge()).foregroundStyle(theme.textPrimary)
            Text(message).font(NuruFont.bodyMedium()).foregroundStyle(theme.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.bgPrimary)
    }
}

import SwiftUI

/// Lightweight app settings page opened from the Home header gear button.
/// Keep this separate from the Mini Apps tab so the gear does not switch tabs.
struct AppSettingsView: View {
    var onDismiss: () -> Void = {}
    var onLogout:  () -> Void = {}

    @Environment(\.nuruTheme) private var theme
    @State private var showLogoutConfirm = false

    private let privacyURL = URL(string: "https://tami1A84.github.io/null--nostr/privacy.html")!

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: NuruSpacing.space4) {
                    settingsRow(
                        icon: "hand.raised",
                        title: "プライバシーポリシー",
                        subtitle: "個人情報とデータの取り扱いを確認",
                        trailing: "chevron.right"
                    ) {
                        UIApplication.shared.open(privacyURL)
                    }

                    settingsRow(
                        icon: "rectangle.portrait.and.arrow.right",
                        title: "ログアウト",
                        subtitle: "このデバイスから秘密鍵を削除します",
                        titleColor: .red,
                        trailing: nil
                    ) {
                        showLogoutConfirm = true
                    }
                }
                .padding(NuruSpacing.space4)
            }
            .background(theme.bgPrimary)
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(theme.textSecondary)
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .alert("ログアウト", isPresented: $showLogoutConfirm) {
            Button("ログアウト", role: .destructive) { onLogout() }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("ログアウトします。秘密鍵はこのデバイスから削除されます。")
        }
    }

    private func settingsRow(
        icon: String,
        title: String,
        subtitle: String,
        titleColor: Color? = nil,
        trailing: String?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: NuruSpacing.space3) {
                ZStack {
                    Circle()
                        .fill(theme.bgPrimary)
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(titleColor ?? theme.textSecondary)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(NuruFont.bodyMedium())
                        .fontWeight(.bold)
                        .foregroundStyle(titleColor ?? theme.textPrimary)
                    Text(subtitle)
                        .font(NuruFont.bodySmall())
                        .foregroundStyle(theme.textTertiary)
                        .lineLimit(2)
                }

                Spacer()

                if let trailing {
                    Image(systemName: trailing)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.textTertiary)
                }
            }
            .padding(NuruSpacing.space4)
            .background(
                RoundedRectangle(cornerRadius: NuruSpacing.radiusXl)
                    .fill(theme.bgSecondary)
            )
        }
        .buttonStyle(.plain)
    }
}

