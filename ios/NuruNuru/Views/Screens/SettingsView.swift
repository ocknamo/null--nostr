import SwiftUI

// MARK: - MiniApp Model

struct MiniApp: Identifiable, Codable {
    let id:          String
    let name:        String
    let description: String
    let icon:        String
    let category:    String
    var type:        String = "internal"
    var url:         String? = nil
}

/// ミニアプリ / Settings screen.
/// Mirrors Android SettingsScreen.kt — collapsing header, profile card, security section,
/// マイミニアプリ horizontal row, 4-category paged tabs, vertical MiniAppRow list.
struct SettingsView: View {

    let pubkeyHex:     String
    let authViewModel: AuthViewModel
    let repository:    NostrRepository
    let prefs:         AppPreferences
    var connectionVM:  ConnectionViewModel? = nil
    var onExternalAppFullscreenChanged: ((Bool) -> Void)? = nil

    @Environment(\.nuruTheme) private var theme
    @State private var searchQuery:    String      = ""
    @State private var selectedTab:    Int         = 0
    @State private var selectedApp:    MiniApp?    = nil
    @State private var showLogout:     Bool        = false
    @State private var profile:        UserProfile? = nil
    @State private var showExternalAdd: Bool       = false
    @State private var editingApp:     MiniApp?    = nil
    @State private var favorites:      [String]    = []
    @State private var externalApps:   [MiniApp]   = []
    @StateObject private var browserNavState = NostrBrowserNavState()

    // Collapsing header state
    @State private var headerHeight:   CGFloat = 0
    @State private var headerOffset:   CGFloat = 0

    // Security
    @State private var securityExpanded: Bool = false
    @State private var autoSignEnabled:  Bool = true
    @State private var showNsec:         Bool = false

    // MARK: - Mini-apps

    private let allApps: [MiniApp] = [
        MiniApp(id: "emoji",      name: "カスタム絵文字",    description: "投稿やリアクションに使える絵文字を管理・追加",  icon: "face.smiling",       category: "entertainment"),
        MiniApp(id: "badge",      name: "プロフィールバッジ", description: "プロフィールに表示するバッジを設定・管理",     icon: "rosette",            category: "entertainment"),
        MiniApp(id: "scheduler",  name: "調整くん",          description: "オフ会や会議の予定を簡単に調整",              icon: "calendar.badge.plus", category: "entertainment"),
        MiniApp(id: "mute",       name: "ミュートリスト",     description: "不快なユーザーやキーワードを非表示に管理",     icon: "speaker.slash.fill",  category: "tools"),
        MiniApp(id: "zap",        name: "Zap設定",          description: "デフォルトのZap金額をクイック設定",            icon: "bitcoinsign.circle",  category: "tools"),
        MiniApp(id: "relay",      name: "リレー設定",         description: "地域に基づいた最適なリレーを自動設定",          icon: "network",             category: "tools"),
        MiniApp(id: "upload",     name: "アップロード設定",    description: "画像のアップロード先サーバーを選択",           icon: "photo",               category: "tools"),
        MiniApp(id: "elevenlabs", name: "音声入力設定",       description: "ElevenLabs Scribeによる高精度な音声入力",     icon: "waveform",            category: "tools"),
        MiniApp(id: "backup",     name: "バックアップ",       description: "自分の投稿データをJSON形式でエクスポート",     icon: "square.and.arrow.up", category: "tools"),
        MiniApp(id: "vanish",     name: "削除リクエスト",     description: "リレーに対して全データの削除を要求",            icon: "flame.fill",          category: "tools"),
        MiniApp(id: "cache",      name: "キャッシュ設定",     description: "キャッシュするkindと保持日数を管理",           icon: "internaldrive",       category: "tools"),
    ]

    private let categoryList: [(String, String)] = [
        ("all", "すべて"),
        ("entertainment", "エンタメ"),
        ("tools", "ツール"),
        ("others", "その他"),
    ]

    private var combinedApps: [MiniApp] {
        allApps + externalApps
    }

    private func filteredApps(for category: String) -> [MiniApp] {
        combinedApps.filter { app in
            (category == "all" || app.category == category) &&
            (searchQuery.isEmpty || app.name.contains(searchQuery) || app.description.contains(searchQuery))
        }
    }

    private var favoriteAppData: [MiniApp] {
        combinedApps.filter { favorites.contains($0.id) }
    }

    private var npub: String {
        NostrKeyUtils.shortenPubkey(pubkeyHex, chars: 8)
    }

    var body: some View {
        Group {
            if let app = selectedApp {
                miniAppDetail(app)
            } else {
                mainContent
            }
        }
        .onAppear {
            onExternalAppFullscreenChanged?(selectedApp?.type == "external")
        }
        .onChange(of: selectedApp?.id) { _, _ in
            onExternalAppFullscreenChanged?(selectedApp?.type == "external")
            if selectedApp?.type != "external" {
                browserNavState.reset()
            }
        }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        VStack(spacing: 0) {
            // TopBar: 56pt, "ミニアプリ" titleLarge bold
            HStack {
                Text("ミニアプリ")
                    .font(NuruFont.titleLarge())
                    .fontWeight(.bold)
                    .foregroundStyle(theme.textPrimary)
                Spacer()
            }
            .frame(height: 56)
            .padding(.horizontal, NuruSpacing.space4)
            .background(theme.bgPrimary)

            // ヘッダー + カテゴリタブ + アプリリストを 1 つの ScrollView に統合
            // (Android SettingsScreen.kt の LazyColumn 相当)
            // カテゴリ横スワイプ対応（Android TabRow + HorizontalPager に対応）
            ScrollView {
                LazyVStack(spacing: 0) {
                    collapsingHeader
                    categoryTabs

                    // アプリ一覧（選択中カテゴリ）
                    let category = categoryList[selectedTab].0
                    ForEach(filteredApps(for: category)) { app in
                        MiniAppRow(
                            app: app,
                            isFavorite: favorites.contains(app.id),
                            onToggleFavorite: {
                                if favorites.contains(app.id) {
                                    favorites.removeAll { $0 == app.id }
                                } else {
                                    favorites.append(app.id)
                                }
                                prefs.favoriteApps = favorites
                            },
                            onClick: { selectedApp = app },
                            onLongPress: app.type == "external" ? { editingApp = app } : nil,
                            onDeleteExternal: app.type == "external" ? {
                                externalApps.removeAll { $0.id == app.id }
                                favorites.removeAll { $0 == app.id }
                                saveExternalApps()
                                prefs.favoriteApps = favorites
                            } : nil
                        )
                    }

                    externalAppAddSection
                        .padding(NuruSpacing.space4)

                    privacyPolicyLink
                }
            }
            // カテゴリ横スワイプ（Android HorizontalPager に対応）
            // simultaneousGesture を使用してマイミニアプリ横スクロールを妨げない
            .simultaneousGesture(
                DragGesture(minimumDistance: 80, coordinateSpace: .local)
                    .onEnded { value in
                        let hDelta = value.translation.width
                        let vDelta = abs(value.translation.height)
                        guard abs(hDelta) > vDelta * 1.5 else { return }
                        let maxTab = categoryList.count - 1
                        if hDelta < -30 && selectedTab < maxTab {
                            withAnimation(.easeInOut(duration: 0.2)) { selectedTab += 1 }
                        } else if hDelta > 30 && selectedTab > 0 {
                            withAnimation(.easeInOut(duration: 0.2)) { selectedTab -= 1 }
                        }
                    }
            )
        }
        .background(theme.bgPrimary)
        .onAppear {
            favorites = prefs.favoriteApps
            autoSignEnabled = prefs.autoSignEnabled
            loadExternalApps()
        }
        .task {
            let profiles = await repository.fetchProfiles(pubkeys: [pubkeyHex])
            profile = profiles.first
        }
        .alert("ログアウト", isPresented: $showLogout) {
            Button("ログアウト", role: .destructive) { authViewModel.logout() }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("ログアウトします。秘密鍵はこのデバイスから削除されます。")
        }
        .sheet(item: $editingApp) { target in
            ExternalAppEditSheet(
                app: target,
                onSave: { newName, newUrl in
                    if let idx = externalApps.firstIndex(where: { $0.id == target.id }) {
                        externalApps[idx] = MiniApp(
                            id: target.id,
                            name: newName,
                            description: "外部ミニアプリ",
                            icon: "globe",
                            category: "others",
                            type: "external",
                            url: newUrl
                        )
                        saveExternalApps()
                    }
                    editingApp = nil
                },
                onDelete: {
                    externalApps.removeAll { $0.id == target.id }
                    favorites.removeAll { $0 == target.id }
                    saveExternalApps()
                    prefs.favoriteApps = favorites
                    editingApp = nil
                },
                onDismiss: { editingApp = nil }
            )
        }
    }

    // MARK: - Collapsing Header

    private var collapsingHeader: some View {
        VStack(spacing: NuruSpacing.space4) {
            // Profile card
            profileCard

            // Security settings (only for non-external signer)
            if !prefs.isExternalSigner {
                securitySection
            }

            // Search bar
            searchBar

            // マイミニアプリ horizontal row
            if !favoriteAppData.isEmpty {
                myMiniAppsRow
            }
        }
        .padding(.horizontal, NuruSpacing.space4)
        .padding(.vertical, NuruSpacing.space3)
        .background(theme.bgPrimary)
    }

    // MARK: - Profile Card

    private var profileCard: some View {
        HStack(spacing: NuruSpacing.space3) {
            // Lock icon: 40pt circle, lineGreen bg, white lock 20pt
            ZStack {
                Circle()
                    .fill(NuruColors.lineGreen)
                    .frame(width: 40, height: 40)
                Image(systemName: NuruIcons.lock)
                    .font(.system(size: 20))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(prefs.isExternalSigner ? "外部署名でログイン中" : "ログイン中")
                    .font(NuruFont.bodyMedium())
                    .fontWeight(.bold)
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                Text(npub)
                    .font(NuruFont.bodySmall())
                    .foregroundStyle(theme.textTertiary)
                    .lineLimit(1)
            }

            Spacer()

            Button { showLogout = true } label: {
                Text("ログアウト")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.red.opacity(0.1))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(NuruSpacing.space4)
        .background(
            RoundedRectangle(cornerRadius: NuruSpacing.radiusXl)
                .fill(theme.bgSecondary)
        )
    }

    // MARK: - Security Settings Section

    private var securitySection: some View {
        VStack(spacing: 0) {
            // Header row
            Button {
                withAnimation(.easeInOut(duration: NuruSpacing.durationFast)) {
                    securityExpanded.toggle()
                }
            } label: {
                HStack(spacing: NuruSpacing.space3) {
                    Image(systemName: NuruIcons.lock)
                        .font(.system(size: 20))
                        .foregroundStyle(theme.textSecondary)
                    Text("セキュリティ設定")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                    Spacer()
                    Image(systemName: securityExpanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(theme.textTertiary)
                }
                .padding(NuruSpacing.space4)
            }
            .buttonStyle(.plain)

            if securityExpanded {
                VStack(spacing: NuruSpacing.space4) {
                    // Auto Sign Toggle
                    HStack(spacing: NuruSpacing.space3) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("自動署名")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(theme.textPrimary)
                            Text(autoSignEnabled ? "投稿時に認証なし" : "毎回認証を要求")
                                .font(.system(size: 12))
                                .foregroundStyle(theme.textTertiary)
                        }
                        Spacer()
                        Toggle("", isOn: $autoSignEnabled)
                            .tint(NuruColors.lineGreen)
                            .labelsHidden()
                            .onChange(of: autoSignEnabled) { _, val in
                                prefs.autoSignEnabled = val
                            }
                    }
                    .padding(NuruSpacing.space3)
                    .background(
                        RoundedRectangle(cornerRadius: NuruSpacing.radiusLg)
                            .fill(theme.bgTertiary)
                    )

                    // Show Nsec Button
                    Button {
                        showNsec.toggle()
                    } label: {
                        Text(showNsec ? "秘密鍵を隠す" : "秘密鍵を表示")
                            .font(.system(size: 14))
                            .foregroundStyle(theme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, NuruSpacing.space3)
                            .background(
                                RoundedRectangle(cornerRadius: NuruSpacing.radiusLg)
                                    .fill(theme.bgTertiary)
                            )
                    }
                    .buttonStyle(.plain)

                    if showNsec {
                        nsecDisplay
                    }
                }
                .padding(.horizontal, NuruSpacing.space4)
                .padding(.bottom, NuruSpacing.space4)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: NuruSpacing.radiusXl)
                .fill(theme.bgSecondary)
        )
    }

    private var nsecDisplay: some View {
        let nsec = authViewModel.getNsecTemporary() ?? "取得できません"
        return VStack(spacing: NuruSpacing.space2) {
            // Warning
            VStack(alignment: .leading, spacing: 4) {
                Text("⚠️ 警告: 秘密鍵の取り扱い")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.red)
                Text("この鍵はあなたの身元を証明する唯一の手段です。他人に教えたり、安全でない場所に保存したりしないでください。")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.red.opacity(0.8))
                    .lineSpacing(2)
            }
            .padding(NuruSpacing.space3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: NuruSpacing.radiusLg)
                    .fill(Color.red.opacity(0.1))
            )

            // Nsec value + copy
            HStack(spacing: NuruSpacing.space2) {
                Text(nsec)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                Spacer()
                Button {
                    UIPasteboard.general.string = nsec
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 16))
                        .foregroundStyle(theme.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(NuruSpacing.space3)
            .background(
                RoundedRectangle(cornerRadius: NuruSpacing.radiusLg)
                    .fill(theme.bgTertiary)
            )
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: NuruSpacing.space2) {
            Image(systemName: NuruIcons.search)
                .font(.system(size: 20))
                .foregroundStyle(theme.textTertiary)
            TextField("ミニアプリを検索", text: $searchQuery)
                .font(.system(size: 14))
                .foregroundStyle(theme.textPrimary)
        }
        .padding(NuruSpacing.space3)
        .frame(height: 48)
        .background(
            RoundedRectangle(cornerRadius: NuruSpacing.radiusLg)
                .fill(theme.bgSecondary)
        )
    }

    // MARK: - マイミニアプリ Horizontal Row

    private var myMiniAppsRow: some View {
        VStack(alignment: .leading, spacing: NuruSpacing.space3) {
            HStack {
                Text("マイミニアプリ")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 16))
                    .foregroundStyle(theme.textTertiary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: NuruSpacing.space4) {
                    ForEach(favoriteAppData) { app in
                        Button { selectedApp = app } label: {
                            VStack(spacing: 6) {
                                ZStack {
                                    Circle()
                                        .fill(theme.bgSecondary)
                                        .frame(width: 56, height: 56)
                                        .overlay(
                                            Circle()
                                                .stroke(theme.borderColor, lineWidth: 0.5)
                                        )
                                    if app.id == "zap" {
                                        BitcoinIcon()
                                            .frame(width: 28, height: 28)
                                            .foregroundStyle(theme.textSecondary)
                                    } else {
                                        Image(systemName: app.icon)
                                            .font(.system(size: 28))
                                            .foregroundStyle(theme.textSecondary)
                                    }
                                }
                                Text(app.name)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(theme.textPrimary)
                                    .lineLimit(1)
                                    .frame(width: 64)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.vertical, NuruSpacing.space3)
    }

    // MARK: - Category Tabs

    private var categoryTabs: some View {
        VStack(spacing: 0) {
            HStack(spacing: NuruSpacing.space4) {
                ForEach(Array(categoryList.enumerated()), id: \.offset) { index, cat in
                    categoryTab(index: index, label: cat.1)
                }
                Spacer()
            }
            .padding(.horizontal, NuruSpacing.space4)

            Divider().background(theme.borderColor)
        }
        .background(theme.bgPrimary)
    }

    private func categoryTab(index: Int, label: String) -> some View {
        let isSelected = selectedTab == index
        return Button {
            withAnimation(.easeInOut(duration: NuruSpacing.durationFast)) {
                selectedTab = index
            }
        } label: {
            VStack(spacing: 0) {
                Text(label)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isSelected ? NuruColors.lineGreen : theme.textTertiary)
                    .frame(height: 40)
                Rectangle()
                    .fill(isSelected ? NuruColors.lineGreen : Color.clear)
                    .frame(width: 32, height: 2)
                    .cornerRadius(1)
                    .animation(.easeInOut(duration: NuruSpacing.durationFast), value: isSelected)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - App List Page (Vertical MiniAppRow list)

    private func appListPage(category: String) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Top padding for header (headerHeight = collapsing header, +42 for category tabs)
                Color.clear.frame(height: (headerHeight > 0 ? headerHeight : 0) + 42)

                ForEach(filteredApps(for: category)) { app in
                    MiniAppRow(
                        app: app,
                        isFavorite: favorites.contains(app.id),
                        onToggleFavorite: {
                            if favorites.contains(app.id) {
                                favorites.removeAll { $0 == app.id }
                            } else {
                                favorites.append(app.id)
                            }
                            prefs.favoriteApps = favorites
                        },
                        onClick: { selectedApp = app },
                        onLongPress: app.type == "external" ? { editingApp = app } : nil,
                        onDeleteExternal: app.type == "external" ? {
                            externalApps.removeAll { $0.id == app.id }
                            favorites.removeAll { $0 == app.id }
                            saveExternalApps()
                            prefs.favoriteApps = favorites
                        } : nil
                    )
                }

                // External app add section
                externalAppAddSection
                    .padding(NuruSpacing.space4)

                // Privacy policy link
                privacyPolicyLink
            }
        }
    }

    // MARK: - External App Add

    private var externalAppAddSection: some View {
        VStack(spacing: NuruSpacing.space3) {
            Divider().background(theme.borderColor)

            if showExternalAdd {
                externalAppForm
            } else {
                Button { showExternalAdd = true } label: {
                    HStack(spacing: NuruSpacing.space2) {
                        Image(systemName: "plus")
                            .foregroundStyle(theme.textSecondary)
                        Text("外部ミニアプリを追加")
                            .font(.system(size: 14))
                            .foregroundStyle(theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 64)
                    .overlay(
                        RoundedRectangle(cornerRadius: NuruSpacing.radiusXl)
                            .stroke(theme.borderColor, lineWidth: 2)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    @State private var externalName: String = ""
    @State private var externalUrl:  String = ""

    private var externalAppForm: some View {
        VStack(spacing: NuruSpacing.space3) {
            TextField("アプリ名 (任意)", text: $externalName)
                .font(.system(size: 14))
                .padding(NuruSpacing.space3)
                .background(
                    RoundedRectangle(cornerRadius: NuruSpacing.radiusLg)
                        .stroke(theme.borderColor)
                )

            HStack(spacing: NuruSpacing.space2) {
                TextField("https://...", text: $externalUrl)
                    .font(.system(size: 14))
                    .padding(NuruSpacing.space3)
                    .background(
                        RoundedRectangle(cornerRadius: NuruSpacing.radiusLg)
                            .stroke(theme.borderColor)
                    )

                Button {
                    guard externalUrl.hasPrefix("http") else { return }
                    let name = externalName.isEmpty
                        ? (URL(string: externalUrl)?.host ?? "外部アプリ")
                        : externalName
                    let newApp = MiniApp(
                        id: "external_\(Int(Date().timeIntervalSince1970 * 1000))",
                        name: name,
                        description: "外部ミニアプリ",
                        icon: "globe",
                        category: "others",
                        type: "external",
                        url: externalUrl
                    )
                    externalApps.append(newApp)
                    saveExternalApps()
                    externalName = ""
                    externalUrl = ""
                    showExternalAdd = false
                } label: {
                    Text("追加")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, NuruSpacing.space4)
                        .frame(height: 56)
                        .background(
                            RoundedRectangle(cornerRadius: NuruSpacing.radiusLg)
                                .fill(NuruColors.lineGreen)
                        )
                }
                .buttonStyle(.plain)
            }

            Button { showExternalAdd = false } label: {
                Text("キャンセル")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textTertiary)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        }
        .padding(NuruSpacing.space4)
        .background(
            RoundedRectangle(cornerRadius: NuruSpacing.radiusXl)
                .fill(theme.bgSecondary)
        )
    }

    // MARK: - Privacy Policy

    private var privacyPolicyLink: some View {
        Button {
            if let url = URL(string: "https://tami1A84.github.io/null--nostr/privacy.html") {
                UIApplication.shared.open(url)
            }
        } label: {
            Text("プライバシーポリシー")
                .font(.system(size: 13))
                .foregroundStyle(theme.textTertiary)
                .underline()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Mini App Detail

    @ViewBuilder
    private func miniAppDetail(_ app: MiniApp) -> some View {
        VStack(spacing: 0) {
            // Back nav bar
            HStack {
                Button {
                    if app.type == "external" {
                        browserNavState.navigateBack {
                            selectedApp = nil
                        }
                    } else {
                        selectedApp = nil
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
                Spacer()
                Text(miniAppTitle(app))
                    .font(NuruFont.titleMedium())
                    .fontWeight(.semibold)
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                Button { selectedApp = nil } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
            }
            .frame(height: 56)
            .padding(.horizontal, NuruSpacing.space4)
            .background(theme.bgPrimary)

            Divider().background(theme.borderColor)

            // Content
            if app.type == "external" {
                NostrBrowserView(
                    repository: repository,
                    pubkeyHex: pubkeyHex,
                    initialUrl: app.url,
                    navState: browserNavState,
                    onCloseRequested: { selectedApp = nil }
                )
            } else {
                switch app.id {
                case "emoji":      EmojiSettingsView(repository: repository, pubkeyHex: pubkeyHex)
                case "badge":      BadgeSettingsView(repository: repository, pubkeyHex: pubkeyHex)
                case "zap":        ZapSettingsView(prefs: prefs)
                case "relay":      RelaySettingsView(repository: repository, prefs: prefs, pubkeyHex: pubkeyHex, connectionVM: connectionVM)
                case "upload":     UploadSettingsView(prefs: prefs, repository: repository, pubkeyHex: pubkeyHex)
                case "mute":       MuteListView(repository: repository, pubkeyHex: pubkeyHex)
                case "backup":     EventBackupView(repository: repository, pubkeyHex: pubkeyHex)
                case "cache":      CacheSettingsView(repository: repository, prefs: prefs)
                case "scheduler":  SchedulerView(repository: repository, pubkeyHex: pubkeyHex)
                case "elevenlabs": ElevenLabsSettingsView(prefs: prefs)
                case "vanish":     VanishRequestView(repository: repository)
                case "scrolls":    ScrollsView(repository: repository, pubkeyHex: pubkeyHex)
                default:           placeholderDetail(app)
                }
            }
        }
        .background(theme.bgPrimary)
    }

    private func miniAppTitle(_ app: MiniApp) -> String {
        switch app.id {
        case "zap":        return "Zap設定"
        case "relay":      return "リレー設定"
        case "upload":     return "アップロード設定"
        case "badge":      return "プロフィールバッジ"
        case "emoji":      return "カスタム絵文字"
        case "mute":       return "ミュートリスト"
        case "elevenlabs": return "音声入力設定"
        case "backup":     return "バックアップ"
        case "vanish":     return "削除リクエスト"
        case "cache":      return "キャッシュ設定"
        default:           return app.name
        }
    }

    private func placeholderDetail(_ app: MiniApp) -> some View {
        VStack(spacing: NuruSpacing.space3) {
            Spacer()
            Image(systemName: app.icon)
                .font(.system(size: 48))
                .foregroundStyle(NuruColors.lineGreen)
            Text(app.name)
                .font(NuruFont.titleMedium())
                .foregroundStyle(theme.textPrimary)
            Text("準備中")
                .font(NuruFont.bodyMedium())
                .foregroundStyle(theme.textTertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.bgPrimary)
    }

    // MARK: - Helpers

    private func loadExternalApps() {
        let json = prefs.externalApps
        guard let data = json.data(using: .utf8),
              let list = try? JSONDecoder().decode([MiniApp].self, from: data) else { return }
        externalApps = list
    }

    private func saveExternalApps() {
        guard let data = try? JSONEncoder().encode(externalApps),
              let json = String(data: data, encoding: .utf8) else { return }
        prefs.externalApps = json
    }
}

// MARK: - MiniAppRow (Vertical list item)

private struct MiniAppRow: View {
    let app: MiniApp
    let isFavorite: Bool
    let onToggleFavorite: () -> Void
    let onClick: () -> Void
    var onLongPress: (() -> Void)? = nil
    var onDeleteExternal: (() -> Void)? = nil

    @Environment(\.nuruTheme) private var theme

    var body: some View {
        Button(action: onClick) {
            HStack(spacing: NuruSpacing.space4) {
                // 56pt icon box (bgSecondary, 16pt radius)
                ZStack {
                    RoundedRectangle(cornerRadius: NuruSpacing.radiusXl)
                        .fill(theme.bgSecondary)
                        .frame(width: 56, height: 56)
                    miniAppIcon(app)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: NuruSpacing.space2) {
                        Text(app.name)
                            .font(NuruFont.bodyMedium())
                            .fontWeight(.bold)
                            .foregroundStyle(theme.textPrimary)
                        categoryBadge
                    }
                    Text(app.description)
                        .font(NuruFont.bodySmall())
                        .foregroundStyle(theme.textTertiary)
                        .lineLimit(1)
                }

                Spacer()

                if app.type == "external" {
                    Button(action: { onDeleteExternal?() }) {
                        Image(systemName: "trash")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.red.opacity(0.9))
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(action: onToggleFavorite) {
                        Image(systemName: NuruIcons.star(filled: isFavorite))
                            .font(.system(size: 20))
                            .foregroundStyle(isFavorite ? Color(hex: "#FFD700") : theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }

            }
            .padding(.horizontal, NuruSpacing.space4)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .onLongPressGesture {
            onLongPress?()
        }
        .contextMenu {
            if app.type == "external" {
                Button("編集") { onLongPress?() }
                Button("削除", role: .destructive) { onDeleteExternal?() }
            }
        }
    }

    /// Renders the appropriate icon for a mini-app.
    /// ZAP uses the custom BitcoinIcon (matching timeline), everything else uses SF Symbols.
    @ViewBuilder
    private func miniAppIcon(_ app: MiniApp) -> some View {
        if app.id == "zap" {
            BitcoinIcon()
                .frame(width: 28, height: 28)
                .foregroundStyle(theme.textSecondary)
        } else {
            Image(systemName: app.icon)
                .font(.system(size: 28))
                .foregroundStyle(theme.textSecondary)
        }
    }

    @ViewBuilder
    private var categoryBadge: some View {
        let (bg, text, fg) = badgeColors(for: app.category)
        Text(text)
            .font(.system(size: 10))
            .foregroundStyle(fg)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(bg)
            )
    }

    private func badgeColors(for category: String) -> (Color, String, Color) {
        switch category {
        case "entertainment":
            return (Color(hex: "#E1BEE7").opacity(0.2), "エンタメ", Color(hex: "#9C27B0"))
        case "others":
            return (Color(hex: "#FFE0B2").opacity(0.2), "その他", Color(hex: "#E65100"))
        default: // tools
            return (Color(hex: "#BBDEFB").opacity(0.2), "ツール", Color(hex: "#2196F3"))
        }
    }
}

// MARK: - Upload Settings View

private struct UploadSettingsView: View {
    let prefs: AppPreferences
    let repository: NostrRepository
    let pubkeyHex: String

    @Environment(\.nuruTheme) private var theme

    @State private var uploadServer: String = ""
    @State private var discoveredServers: [String] = []
    @State private var customServers: [String] = []
    @State private var customServerInput: String = ""
    @State private var showAddCustom: Bool = false
    @State private var publishMessage: String? = nil

    // Keep legacy upload targets for compatibility, but default is Blossom.
    private let fixedServers: [(String, String)] = [
        ("Blossom (nostr.build)", "https://blossom.nostr.build"),
        ("nostr.build", "nostr.build"),
        ("やぶみ", "share.yabu.me"),
    ]

    private var allServers: [(String, String)] {
        var items = fixedServers

        for server in discoveredServers {
            if !items.contains(where: { normalized($0.1) == normalized(server) }) {
                let host = URL(string: server)?.host ?? server
                items.append(("公開設定: \(host)", server))
            }
        }

        for server in customServers {
            if !items.contains(where: { normalized($0.1) == normalized(server) }) {
                let host = URL(string: server)?.host ?? server
                items.append(("カスタム: \(host)", server))
            }
        }

        return items
    }

    var body: some View {
        ScrollView {
            VStack(spacing: NuruSpacing.space4) {
                VStack(alignment: .leading, spacing: NuruSpacing.space4) {
                    Text("画像アップロード")
                        .font(NuruFont.bodyMedium())
                        .fontWeight(.bold)
                        .foregroundStyle(theme.textPrimary)
                    Text("プロフィール画像のアップロード先")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textTertiary)

                    if !discoveredServers.isEmpty {
                        Text("公開Blossom設定 (kind:10063) を読み込み済み")
                            .font(NuruFont.labelSmall())
                            .foregroundStyle(theme.textTertiary)
                    }

                    ForEach(allServers, id: \.1) { name, url in
                        let isSelected = normalized(uploadServer) == normalized(url)
                        Button {
                            uploadServer = url
                            prefs.uploadServer = url
                        } label: {
                            HStack {
                                Text(name)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(isSelected ? .white : theme.textPrimary)
                                Spacer()
                                if isSelected {
                                    Image(systemName: NuruIcons.check)
                                        .foregroundStyle(.white)
                                        .font(.system(size: 20))
                                }
                            }
                            .frame(height: 48)
                            .padding(.horizontal, NuruSpacing.space4)
                            .background(
                                RoundedRectangle(cornerRadius: NuruSpacing.radiusLg)
                                    .fill(isSelected ? NuruColors.lineGreen : theme.bgTertiary)
                            )
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            if customServers.contains(where: { normalized($0) == normalized(url) }) {
                                Button("削除", role: .destructive) { removeCustomServer(url) }
                            }
                        }
                    }

                    if showAddCustom {
                        HStack(spacing: NuruSpacing.space2) {
                            TextField("https://example.com", text: $customServerInput)
                                .font(NuruFont.bodyMedium())
                                .foregroundStyle(theme.textPrimary)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.URL)
                                .autocorrectionDisabled(true)
                                .padding(.horizontal, NuruSpacing.space3)
                                .frame(height: 44)
                                .background(theme.bgTertiary)
                                .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusMd))

                            Button("追加") { addCustomServer() }
                                .font(NuruFont.bodySmall())
                                .foregroundStyle(.white)
                                .padding(.horizontal, NuruSpacing.space3)
                                .frame(height: 44)
                                .background(NuruColors.lineGreen)
                                .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusMd))

                            Button {
                                customServerInput = ""
                                showAddCustom = false
                            } label: {
                                Image(systemName: "xmark")
                                    .foregroundStyle(theme.textTertiary)
                                    .frame(width: 30, height: 30)
                            }
                            .buttonStyle(.plain)
                        }
                    } else {
                        Button { showAddCustom = true } label: {
                            Label("アップロード先を追加", systemImage: "plus")
                                .font(NuruFont.bodyMedium())
                                .foregroundStyle(NuruColors.lineGreen)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        Task { await publishBlossomUserServerList() }
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Blossom設定をNostrに公開")
                                .font(NuruFont.bodyMedium())
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(NuruColors.lineGreen)
                        .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusMd))
                    }
                    .buttonStyle(.plain)

                    if let publishMessage {
                        Text(publishMessage)
                            .font(NuruFont.labelSmall())
                            .foregroundStyle(theme.textTertiary)
                    }
                }
                .padding(NuruSpacing.space4)
                .background(
                    RoundedRectangle(cornerRadius: NuruSpacing.radiusXl)
                        .fill(theme.bgSecondary)
                )
            }
            .padding(NuruSpacing.space4)
        }
        .onAppear {
            // default to Blossom (nostr.build)
            if prefs.uploadServer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                prefs.uploadServer = UploadServer.defaultBlossomUrl
            }
            if prefs.uploadServer == UploadServer.nostrBuild.rawValue {
                // migrate old default to Blossom default
                prefs.uploadServer = UploadServer.defaultBlossomUrl
            }
            uploadServer = prefs.uploadServer
            customServers = normalizedUnique(prefs.customUploadServers)
        }
        .task {
            await loadBlossomServerListFromKind10063()
        }
    }

    /// BUD-03: read latest kind:10063 from my pubkey.
    private func loadBlossomServerListFromKind10063() async {
        let filter = NostrFilter(
            ids: nil,
            authors: [pubkeyHex],
            kinds: [NostrKind.blossomUserServerList],
            since: nil,
            until: nil,
            limit: 1,
            tags: nil,
            search: nil
        )

        let events = await repository.fetchEvents(filters: [filter], timeoutSeconds: 8.0)
            .sorted { $0.createdAt > $1.createdAt }

        guard let latest = events.first else {
            discoveredServers = []
            return
        }

        let servers = latest.tags
            .filter { $0.first == "server" }
            .compactMap { $0.count > 1 ? $0[1] : nil }
            .compactMap(normalizedServerUrl)

        discoveredServers = normalizedUnique(servers)
    }

    /// BUD-03: publish replaceable kind:10063 with ordered "server" tags (full URLs only).
    private func publishBlossomUserServerList() async {
        let ordered = publishCandidateServers()
        guard !ordered.isEmpty else {
            publishMessage = "公開する Blossom サーバーURL がありません"
            return
        }

        let tags = ordered.map { ["server", $0] }
        do {
            try await repository.publishEvent(
                kind: NostrKind.blossomUserServerList,
                tags: tags,
                content: ""
            )
            discoveredServers = ordered
            publishMessage = "公開しました (kind:10063)"
        } catch {
            publishMessage = "公開に失敗しました: \(error.localizedDescription)"
        }
    }

    /// Publish order: selected -> discovered -> custom -> default Blossom.
    private func publishCandidateServers() -> [String] {
        var candidates: [String] = []

        if let selected = blossomPublishUrl(from: uploadServer) {
            candidates.append(selected)
        }
        candidates.append(contentsOf: discoveredServers.compactMap(normalizedServerUrl))
        candidates.append(contentsOf: customServers.compactMap(normalizedServerUrl))
        candidates.append(UploadServer.defaultBlossomUrl)

        return normalizedUnique(candidates)
    }

    /// Convert current UI selection into BUD-03 server URL if possible.
    private func blossomPublishUrl(from value: String) -> String? {
        let lower = value.lowercased()
        if lower == UploadServer.nostrBuild.rawValue {
            return UploadServer.defaultBlossomUrl
        }
        if lower == UploadServer.yabuMe.rawValue || lower.contains("yabu") {
            return nil
        }
        return normalizedServerUrl(value)
    }

    private func addCustomServer() {
        guard let normalizedUrl = normalizedServerUrl(customServerInput) else { return }
        if !customServers.contains(where: { normalized($0) == normalized(normalizedUrl) }) {
            customServers.append(normalizedUrl)
            customServers = normalizedUnique(customServers)
            prefs.customUploadServers = customServers
        }
        uploadServer = normalizedUrl
        prefs.uploadServer = normalizedUrl
        customServerInput = ""
        showAddCustom = false
    }

    private func removeCustomServer(_ server: String) {
        customServers.removeAll { normalized($0) == normalized(server) }
        prefs.customUploadServers = customServers

        if normalized(uploadServer) == normalized(server) {
            uploadServer = UploadServer.defaultBlossomUrl
            prefs.uploadServer = uploadServer
        }
    }

    private func normalizedUnique(_ servers: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for value in servers {
            let n = normalized(value)
            if !seen.contains(n) {
                seen.insert(n)
                out.append(value)
            }
        }
        return out
    }

    private func normalizedServerUrl(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let withScheme = (trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")) ? trimmed : "https://\(trimmed)"

        guard var components = URLComponents(string: withScheme),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.host != nil else { return nil }

        components.scheme = scheme
        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = path.isEmpty ? "" : "/\(path)"
        components.query = nil
        components.fragment = nil

        return components.string
    }

    private func normalized(_ value: String) -> String {
        normalizedServerUrl(value)?.lowercased() ?? value.lowercased()
    }
}

// MARK: - External App Edit Sheet

private struct ExternalAppEditSheet: View {
    let app: MiniApp
    let onSave: (String, String) -> Void
    let onDelete: () -> Void
    let onDismiss: () -> Void

    @Environment(\.nuruTheme) private var theme
    @State private var name: String = ""
    @State private var url: String = ""
    @State private var showDeleteConfirm: Bool = false

    var body: some View {
        NavigationStack {
            VStack(spacing: NuruSpacing.space4) {
                Text("外部ミニアプリを編集")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(theme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                TextField("アプリ名", text: $name)
                    .font(.system(size: 14))
                    .padding(NuruSpacing.space3)
                    .overlay(
                        RoundedRectangle(cornerRadius: NuruSpacing.radiusLg)
                            .stroke(theme.borderColor)
                    )

                TextField("https://...", text: $url)
                    .font(.system(size: 14))
                    .padding(NuruSpacing.space3)
                    .overlay(
                        RoundedRectangle(cornerRadius: NuruSpacing.radiusLg)
                            .stroke(theme.borderColor)
                    )

                Button {
                    let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard trimmed.hasPrefix("http") else { return }
                    let finalName = name.isEmpty
                        ? (URL(string: trimmed)?.host ?? "外部アプリ")
                        : name
                    onSave(finalName, trimmed)
                } label: {
                    Text("保存")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: NuruSpacing.radiusLg)
                                .fill(NuruColors.lineGreen)
                        )
                }
                .buttonStyle(.plain)

                if showDeleteConfirm {
                    VStack(spacing: NuruSpacing.space2) {
                        Text("本当に削除しますか？")
                            .font(.system(size: 14))
                            .foregroundStyle(theme.textPrimary)
                        HStack(spacing: NuruSpacing.space3) {
                            Button {
                                onDelete()
                            } label: {
                                Text("削除")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 40)
                                    .background(
                                        RoundedRectangle(cornerRadius: NuruSpacing.radiusLg)
                                            .fill(Color.red)
                                    )
                            }
                            .buttonStyle(.plain)
                            Button {
                                showDeleteConfirm = false
                            } label: {
                                Text("キャンセル")
                                    .font(.system(size: 14))
                                    .foregroundStyle(theme.textTertiary)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 40)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(NuruSpacing.space3)
                    .background(
                        RoundedRectangle(cornerRadius: NuruSpacing.radiusLg)
                            .fill(Color.red.opacity(0.1))
                    )
                } else {
                    Button {
                        showDeleteConfirm = true
                    } label: {
                        HStack(spacing: NuruSpacing.space2) {
                            Image(systemName: NuruIcons.trash)
                                .font(.system(size: 14))
                            Text("削除")
                                .font(.system(size: 14))
                        }
                        .foregroundStyle(Color.red)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }
            .padding(NuruSpacing.space4)
            .background(theme.bgPrimary)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { onDismiss() }
                }
            }
        }
        .onAppear {
            name = app.name
            url = app.url ?? ""
        }
        .presentationDetents([.medium])
    }
}

