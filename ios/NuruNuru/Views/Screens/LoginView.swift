import PhotosUI
import SwiftUI

/// Login screen — mirrors Android LoginScreen.kt pixel-for-pixel.
///
/// Flow:
///   1. Initial → shows 新規登録 / ログイン buttons
///   2. ログイン tapped → shows nsec input + ログインボタン
///   3. その他のログイン方法 → NIP-46 Nostr Connect button (collapsible)
///   4. 新規登録 → SignUpSheet
struct LoginView: View {

    @Environment(AuthViewModel.self) private var viewModel
    @Environment(\.nuruTheme) private var theme

    @State private var nsecInput          = ""
    @State private var showKey            = false
    @State private var showSignUp         = false
    @State private var showNsecLogin      = false
    @State private var showOtherMethods   = false
    @State private var showNostrConnect   = false
    @State private var logoScale: CGFloat = 0.95

    private var isLoading: Bool {
        if case .checking = viewModel.state { return true }
        return false
    }

    private var errorMessage: String? {
        if case .error(let msg) = viewModel.state { return msg }
        return nil
    }

    var body: some View {
        ZStack {
            theme.bgPrimary.ignoresSafeArea()

            if isLoading && !showNsecLogin && !showSignUp {
                loadingView
            } else {
                mainContent
            }
        }
        .sheet(isPresented: $showSignUp) {
            SignUpSheet(isPresented: $showSignUp)
                .environment(viewModel)
        }
        .sheet(isPresented: $showNostrConnect) {
            NostrConnectSheet(isPresented: $showNostrConnect)
                .environment(viewModel)
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: NuruSpacing.space5) {
            Image("logo")
                .resizable()
                .scaledToFill()
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radius2xl))
                .scaleEffect(logoScale)
                .onAppear {
                    withAnimation(
                        .easeInOut(duration: 1.0).repeatForever(autoreverses: true)
                    ) { logoScale = 1.05 }
                }
            Text("読み込み中...")
                .font(NuruFont.bodyMedium())
                .foregroundStyle(theme.textTertiary)
        }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        VStack(spacing: NuruSpacing.space6) {
            Spacer()
            logoSection
            buttonSection
            Spacer()
            footerSection
        }
        .padding(.horizontal, NuruSpacing.space6)
    }

    // MARK: - Logo

    private var logoSection: some View {
        VStack(spacing: NuruSpacing.space4) {
            Image("logo")
                .resizable()
                .scaledToFill()
                .frame(width: 112, height: 112)
                .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radius2xl))
                .shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: 4)

            Text("ぬるぬる")
                .font(NuruFont.displayLarge())
                .foregroundStyle(theme.textPrimary)
        }
    }

    // MARK: - Buttons

    @ViewBuilder
    private var buttonSection: some View {
        if !showNsecLogin {
            // Initial state: 新規登録 + ログイン
            VStack(spacing: NuruSpacing.space4) {
                signUpButton
                loginToggleButton
            }
        } else {
            // nsec login form
            nsecLoginForm
        }
    }

    private var signUpButton: some View {
        Button {
            showSignUp = true
        } label: {
            HStack(spacing: NuruSpacing.space3) {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 20))
                Text("新規登録")
                    .font(NuruFont.buttonLarge())
            }
            .frame(maxWidth: .infinity)
            .frame(height: 64)
        }
        .buttonStyle(NuruPrimaryButtonStyle())
        .shadow(color: NuruColors.lineGreen.opacity(0.25), radius: 8, x: 0, y: 4)
    }

    private var loginToggleButton: some View {
        Button {
            withAnimation(.easeInOut(duration: NuruSpacing.durationNormal)) {
                showNsecLogin = true
            }
        } label: {
            HStack(spacing: NuruSpacing.space3) {
                Image(systemName: "arrow.right.circle")
                    .font(.system(size: 20))
                    .foregroundStyle(theme.textPrimary)
                Text("ログイン")
                    .font(NuruFont.buttonMedium())
                    .foregroundStyle(theme.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
        }
        .buttonStyle(NuruSecondaryButtonStyle(theme: theme))
    }

    // MARK: - nsec Login Form

    private var nsecLoginForm: some View {
        VStack(spacing: NuruSpacing.space4) {

            // nsec input
            nsecTextField

            // Error message
            if let msg = errorMessage {
                Text(msg)
                    .font(NuruFont.bodySmall())
                    .foregroundStyle(NuruColors.colorError)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, NuruSpacing.space2)
                    .transition(.opacity)
            }

            // Login button
            loginButton

            // Collapsible: その他のログイン方法
            otherMethodsSection

            // Cancel
            Button("キャンセル") {
                withAnimation(.easeInOut(duration: NuruSpacing.durationNormal)) {
                    showNsecLogin = false
                    showOtherMethods = false
                    nsecInput = ""
                    viewModel.clearError()
                }
            }
            .font(NuruFont.bodyMedium())
            .foregroundStyle(theme.textTertiary)
        }
    }

    private var nsecTextField: some View {
        HStack {
            if showKey {
                TextField("nsec1...", text: $nsecInput)
                    .font(NuruFont.bodyMedium())
                    .foregroundStyle(theme.textPrimary)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onChange(of: nsecInput) { _, _ in viewModel.clearError() }
            } else {
                SecureField("nsec1...", text: $nsecInput)
                    .font(NuruFont.bodyMedium())
                    .foregroundStyle(theme.textPrimary)
                    .onChange(of: nsecInput) { _, _ in viewModel.clearError() }
            }

            Button {
                showKey.toggle()
            } label: {
                Image(systemName: showKey ? "eye.slash" : "eye")
                    .foregroundStyle(theme.textTertiary)
                    .font(.system(size: NuruSpacing.iconMd))
            }
            .accessibilityLabel(showKey ? "隠す" : "表示")
        }
        .padding(NuruSpacing.space4)
        .background(theme.bgSecondary)
        .cornerRadius(NuruSpacing.radiusXl)
        .overlay(
            RoundedRectangle(cornerRadius: NuruSpacing.radiusXl)
                .stroke(
                    errorMessage != nil ? NuruColors.colorError
                        : (nsecInput.isEmpty ? theme.borderColor : NuruColors.lineGreen),
                    lineWidth: 1.5
                )
        )
    }

    private var loginButton: some View {
        Button {
            viewModel.login(nsecOrHex: nsecInput)
        } label: {
            Group {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .scaleEffect(0.8)
                } else {
                    Text("ログイン")
                        .font(NuruFont.buttonMedium())
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
        }
        .buttonStyle(NuruPrimaryButtonStyle(isDisabled: nsecInput.isEmpty || isLoading))
        .disabled(nsecInput.isEmpty || isLoading)
    }

    // MARK: - Other Login Methods (Collapsible)

    private var otherMethodsSection: some View {
        VStack(spacing: NuruSpacing.space3) {
            Button {
                withAnimation(.easeInOut(duration: NuruSpacing.durationNormal)) {
                    showOtherMethods.toggle()
                }
            } label: {
                HStack(spacing: NuruSpacing.space2) {
                    Text("その他のログイン方法")
                        .font(NuruFont.bodyMedium())
                        .foregroundStyle(theme.textTertiary)
                    Image(systemName: showOtherMethods ? "chevron.up" : "chevron.down")
                        .font(.system(size: 14))
                        .foregroundStyle(theme.textTertiary)
                }
                .frame(maxWidth: .infinity)
            }

            if showOtherMethods {
                // NIP-46 Nostr Connect button (iOS equivalent of Amber/NIP-55)
                nostrConnectButton
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var nostrConnectButton: some View {
        Button {
            showNostrConnect = true
        } label: {
            HStack(spacing: NuruSpacing.space3) {
                Image(systemName: "network")
                    .font(.system(size: NuruSpacing.iconMd))
                    .foregroundStyle(NuruColors.lineGreen)
                Text("Nostr Connectでログイン")
                    .font(NuruFont.buttonMedium())
                    .foregroundStyle(theme.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
        }
        .buttonStyle(NuruOutlineButtonStyle(theme: theme))
    }

    // MARK: - Footer

    private var footerSection: some View {
        VStack(spacing: NuruSpacing.space1) {
            Text("Powered by Nostr")
                .font(NuruFont.bodySmall())
                .foregroundStyle(theme.textTertiary)
            Text("秘密鍵はデバイス外に送信されません")
                .font(NuruFont.labelSmall())
                .foregroundStyle(theme.textTertiary.opacity(0.7))
        }
        .padding(.bottom, NuruSpacing.space4)
    }
}

// MARK: - Button Styles

struct NuruPrimaryButtonStyle: ButtonStyle {
    var isDisabled = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: NuruSpacing.radius2xl)
                    .fill(
                        isDisabled
                            ? NuruColors.lineGreen.opacity(0.3)
                            : NuruColors.lineGreen
                    )
                    .scaleEffect(configuration.isPressed ? 0.97 : 1)
                    .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
            )
    }
}

struct NuruSecondaryButtonStyle: ButtonStyle {
    let theme: NuruTheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: NuruSpacing.radius2xl)
                    .fill(theme.bgSecondary)
                    .scaleEffect(configuration.isPressed ? 0.97 : 1)
                    .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
            )
    }
}

struct NuruOutlineButtonStyle: ButtonStyle {
    let theme: NuruTheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: NuruSpacing.radiusXl)
                    .fill(theme.bgSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: NuruSpacing.radiusXl)
                            .stroke(NuruColors.lineGreen, lineWidth: 1)
                    )
                    .scaleEffect(configuration.isPressed ? 0.97 : 1)
                    .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
            )
    }
}

// MARK: - Sign Up Sheet (5-step wizard — mirrors Android SignUpModal.kt)

struct SignUpSheet: View {
    @Binding var isPresented: Bool
    @Environment(AuthViewModel.self) private var viewModel
    @Environment(\.nuruTheme) private var theme

    // Step: welcome → backup → relay → profile → success
    @State private var step = "welcome"
    @State private var generatedAccount: AuthViewModel.GeneratedAccount?
    @State private var selectedRelays: [Nip65Relay]?
    @State private var isLoading = false
    @State private var error = ""

    private var progress: CGFloat {
        switch step {
        case "welcome": return 0.2
        case "backup":  return 0.4
        case "relay":   return 0.6
        case "profile": return 0.8
        default:        return 1.0
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                theme.bgPrimary.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(theme.bgSecondary)
                                .frame(height: 4)
                            Rectangle()
                                .fill(NuruColors.lineGreen)
                                .frame(width: geo.size.width * progress, height: 4)
                                .animation(.easeInOut(duration: 0.3), value: progress)
                        }
                    }
                    .frame(height: 4)

                    ScrollView {
                        VStack(spacing: NuruSpacing.space5) {
                            switch step {
                            case "welcome":
                                SignUpWelcomeStep(
                                    onNext: { generateAccount() },
                                    onClose: { isPresented = false },
                                    isLoading: isLoading,
                                    error: error
                                )
                            case "backup":
                                if let account = generatedAccount {
                                    SignUpBackupStep(
                                        account: account,
                                        onNext: { step = "relay" }
                                    )
                                }
                            case "relay":
                                SignUpRelayStep(onRelaysSelected: { relays in
                                    selectedRelays = relays
                                    step = "profile"
                                })
                            case "profile":
                                SignUpProfileStep(
                                    onFinish: { name, about, picture, banner, nip05, lud16, website, birthday in
                                        publishAndComplete(
                                            name: name, about: about, picture: picture,
                                            banner: banner, nip05: nip05, lud16: lud16,
                                            website: website, birthday: birthday
                                        )
                                    },
                                    isLoading: isLoading
                                )
                            case "success":
                                SignUpSuccessStep(
                                    npub: generatedAccount?.npub ?? "",
                                    onComplete: {
                                        if let hex = generatedAccount?.pubkeyHex {
                                            viewModel.completeRegistration(pubkeyHex: hex)
                                        }
                                        isPresented = false
                                    }
                                )
                            default:
                                EmptyView()
                            }
                        }
                        .padding(NuruSpacing.space6)
                    }
                }
            }
            .navigationTitle("新規登録")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if step != "success" {
                        Button("キャンセル") { isPresented = false }
                            .foregroundStyle(theme.textSecondary)
                    }
                }
            }
        }
        .interactiveDismissDisabled(step == "success")
    }

    // MARK: - Actions

    private func generateAccount() {
        isLoading = true
        error = ""
        Task {
            let acc = await viewModel.generateNewAccount()
            if let acc {
                generatedAccount = acc
                step = "backup"
            } else {
                error = "アカウント作成に失敗しました"
            }
            isLoading = false
        }
    }

    private func publishAndComplete(
        name: String, about: String, picture: String,
        banner: String, nip05: String, lud16: String,
        website: String, birthday: String
    ) {
        isLoading = true
        Task {
            let relayTriples = selectedRelays
            _ = await viewModel.publishInitialMetadata(
                name: name,
                about: about,
                picture: picture,
                banner: banner,
                nip05: nip05,
                lud16: lud16,
                website: website,
                birthday: birthday,
                relays: relayTriples
            )
            step = "success"
            isLoading = false
        }
    }
}

// MARK: - Step 1: Welcome

private struct SignUpWelcomeStep: View {
    let onNext: () -> Void
    let onClose: () -> Void
    let isLoading: Bool
    let error: String

    @Environment(\.nuruTheme) private var theme

    var body: some View {
        VStack(spacing: NuruSpacing.space5) {
            SignUpIconBox(
                systemName: "person.badge.plus",
                containerColor: NuruColors.lineGreen.opacity(0.1),
                iconColor: NuruColors.lineGreen
            )

            VStack(spacing: NuruSpacing.space2) {
                Text("新規登録")
                    .font(NuruFont.titleLarge())
                    .foregroundStyle(theme.textPrimary)
                Text("新しいNostrアカウントを作成します。\n秘密鍵はデバイス内に安全に保存されます。")
                    .font(NuruFont.bodySmall())
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            if !error.isEmpty {
                Text(error)
                    .font(NuruFont.labelSmall())
                    .foregroundStyle(NuruColors.colorError)
            }

            Button(action: onNext) {
                Group {
                    if isLoading {
                        ProgressView().tint(.white).scaleEffect(0.8)
                    } else {
                        Text("アカウントを作成する")
                            .font(NuruFont.buttonLarge())
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 56)
            }
            .buttonStyle(NuruPrimaryButtonStyle(isDisabled: isLoading))
            .disabled(isLoading)

            Button("キャンセル", action: onClose)
                .font(NuruFont.bodyMedium())
                .foregroundStyle(theme.textTertiary)
        }
    }
}

// MARK: - Step 2: Backup

private struct SignUpBackupStep: View {
    let account: AuthViewModel.GeneratedAccount
    let onNext: () -> Void

    @Environment(\.nuruTheme) private var theme
    @State private var copied = false

    var body: some View {
        VStack(spacing: NuruSpacing.space5) {
            SignUpIconBox(
                systemName: "lock.shield",
                containerColor: Color.orange.opacity(0.1),
                iconColor: .orange
            )

            VStack(spacing: NuruSpacing.space2) {
                Text("秘密鍵のバックアップ")
                    .font(NuruFont.titleMedium())
                    .foregroundStyle(theme.textPrimary)
                Text("アカウントを復旧するために必要な「秘密鍵」です。この鍵は誰にも教えないでください。")
                    .font(NuruFont.bodySmall())
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            // nsec card
            VStack(alignment: .leading, spacing: NuruSpacing.space2) {
                Text("あなたの秘密鍵 (nsec)")
                    .font(NuruFont.labelSmall())
                    .fontWeight(.bold)
                    .foregroundStyle(.orange)

                Text(account.nsec)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(theme.textPrimary)
                    .padding(NuruSpacing.space2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.black.opacity(0.2))
                    .cornerRadius(NuruSpacing.radiusMd)

                Button {
                    UIPasteboard.general.string = account.nsec
                    copied = true
                } label: {
                    HStack(spacing: NuruSpacing.space2) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 14))
                            .foregroundStyle(copied ? NuruColors.lineGreen : theme.textPrimary)
                        Text(copied ? "コピーしました" : "秘密鍵をコピー")
                            .font(NuruFont.bodySmall())
                            .foregroundStyle(theme.textPrimary)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(theme.bgTertiary)
                    .cornerRadius(NuruSpacing.radiusMd)
                }
            }
            .padding(NuruSpacing.space4)
            .background(theme.bgSecondary)
            .cornerRadius(NuruSpacing.radiusXl)

            Button(action: onNext) {
                Text("次へ進む")
                    .font(NuruFont.buttonMedium())
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
            }
            .buttonStyle(NuruPrimaryButtonStyle())
        }
    }
}

// MARK: - Step 3: Relay

private struct SignUpRelayStep: View {
    let onRelaysSelected: ([Nip65Relay]) -> Void

    @Environment(\.nuruTheme) private var theme
    @State private var selectionMode = "manual"
    @State private var recommendedRelays: [Nip65Relay]
    @State private var regionName = "東京"
    @State private var isLoading = false
    @State private var showRegionPicker = false

    init(onRelaysSelected: @escaping ([Nip65Relay]) -> Void) {
        self.onRelaysSelected = onRelaysSelected
        let config = RelayDiscovery.generateRelayListByLocation(userLat: 35.6762, userLon: 139.6503)
        _recommendedRelays = State(initialValue: config.combined)
    }

    var body: some View {
        VStack(spacing: NuruSpacing.space5) {
            SignUpIconBox(
                systemName: "location",
                containerColor: Color.blue.opacity(0.1),
                iconColor: .blue
            )

            VStack(spacing: NuruSpacing.space2) {
                Text("リレーのセットアップ")
                    .font(NuruFont.titleMedium())
                    .foregroundStyle(theme.textPrimary)
                Text("地域を選択すると最適なリレーが自動設定されます。")
                    .font(NuruFont.bodySmall())
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            // Mode toggle: GPS / Manual
            HStack(spacing: 0) {
                ForEach([("auto", "GPSで自動検出"), ("manual", "手動で選択")], id: \.0) { id, label in
                    Button {
                        selectionMode = id
                    } label: {
                        Text(label)
                            .font(NuruFont.labelSmall())
                            .fontWeight(.bold)
                            .foregroundStyle(selectionMode == id ? NuruColors.lineGreen : theme.textTertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, NuruSpacing.space2)
                            .background(selectionMode == id ? theme.bgPrimary : Color.clear)
                            .cornerRadius(NuruSpacing.radiusMd)
                    }
                }
            }
            .padding(4)
            .background(theme.bgSecondary)
            .cornerRadius(NuruSpacing.radiusMd)

            // Manual region selector
            if selectionMode == "manual" {
                Button { showRegionPicker = true } label: {
                    HStack {
                        Text(regionName)
                            .font(NuruFont.bodyMedium())
                            .foregroundStyle(theme.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .foregroundStyle(theme.textTertiary)
                    }
                    .padding(NuruSpacing.space3)
                    .overlay(
                        RoundedRectangle(cornerRadius: NuruSpacing.radiusMd)
                            .stroke(theme.borderColor, lineWidth: 1)
                    )
                }
                .confirmationDialog("地域を選択", isPresented: $showRegionPicker) {
                    ForEach(RelayDiscovery.regionCoordinates) { region in
                        Button(region.name) {
                            regionName = region.name
                            let config = RelayDiscovery.generateRelayListByLocation(
                                userLat: region.lat, userLon: region.lon
                            )
                            recommendedRelays = config.combined
                        }
                    }
                }
            }

            // Relay list card
            VStack(alignment: .leading, spacing: NuruSpacing.space2) {
                Text("推奨リレー (\(regionName))")
                    .font(NuruFont.labelSmall())
                    .fontWeight(.bold)
                    .foregroundStyle(theme.textTertiary)

                if isLoading {
                    ProgressView().tint(NuruColors.lineGreen)
                        .frame(maxWidth: .infinity)
                } else {
                    ForEach(recommendedRelays) { relay in
                        HStack(spacing: NuruSpacing.space2) {
                            Image(systemName: "server.rack")
                                .font(.system(size: 12))
                                .foregroundStyle(NuruColors.lineGreen)
                            Text(relay.url.replacingOccurrences(of: "wss://", with: ""))
                                .font(NuruFont.bodySmall())
                                .foregroundStyle(theme.textPrimary)
                            Spacer()
                            if relay.permission == .read || relay.permission == .readWrite {
                                Text("R")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.blue)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.2))
                                    .cornerRadius(4)
                            }
                            if relay.permission == .write || relay.permission == .readWrite {
                                Text("W")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(NuruColors.lineGreen)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(NuruColors.lineGreen.opacity(0.2))
                                    .cornerRadius(4)
                            }
                        }
                    }
                }
            }
            .padding(NuruSpacing.space4)
            .background(theme.bgSecondary)
            .cornerRadius(NuruSpacing.radiusXl)

            Button {
                onRelaysSelected(recommendedRelays)
            } label: {
                Text("次へ進む")
                    .font(NuruFont.buttonMedium())
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
            }
            .buttonStyle(NuruPrimaryButtonStyle(isDisabled: isLoading))
            .disabled(isLoading)
        }
        .onChange(of: selectionMode) { _, newValue in
            if newValue == "auto" {
                requestGPSRelays()
            }
        }
    }

    private func requestGPSRelays() {
        // iOS CoreLocation — simplified: request once
        isLoading = true
        // For now, default to Tokyo if location unavailable
        regionName = "東京 (GPS推定)"
        let config = RelayDiscovery.generateRelayListByLocation(userLat: 35.6762, userLon: 139.6503)
        recommendedRelays = config.combined
        isLoading = false
    }
}

// MARK: - Step 4: Profile

private struct SignUpProfileStep: View {
    let onFinish: (String, String, String, String, String, String, String, String) -> Void
    let isLoading: Bool

    @Environment(\.nuruTheme) private var theme
    @State private var name = ""
    @State private var about = ""
    @State private var picture = ""
    @State private var banner = ""
    @State private var nip05 = ""
    @State private var lud16 = ""
    @State private var website = ""
    @State private var birthday = ""
    @State private var showAdvanced = false

    // PhotosPicker
    @State private var picturePickerItem: PhotosPickerItem?
    @State private var bannerPickerItem: PhotosPickerItem?
    @State private var uploadingPicture = false
    @State private var uploadingBanner = false

    var body: some View {
        VStack(spacing: NuruSpacing.space5) {
            // Avatar upload via PhotosPicker
            VStack(spacing: NuruSpacing.space3) {
                PhotosPicker(selection: $picturePickerItem, matching: .images) {
                    ZStack {
                        Circle()
                            .fill(theme.bgSecondary)
                            .frame(width: 100, height: 100)

                        if picture.isEmpty {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 36))
                                .foregroundStyle(theme.textTertiary)
                        } else {
                            AsyncImage(url: URL(string: picture)) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                ProgressView().tint(NuruColors.lineGreen)
                            }
                            .frame(width: 100, height: 100)
                            .clipShape(Circle())
                        }

                        if uploadingPicture {
                            Circle()
                                .fill(Color.black.opacity(0.5))
                                .frame(width: 100, height: 100)
                            ProgressView().tint(NuruColors.lineGreen)
                        }
                    }
                }
                .disabled(uploadingPicture)

                Text(uploadingPicture ? "アップロード中..." : "アイコン画像をアップロード")
                    .font(NuruFont.labelSmall())
                    .foregroundStyle(uploadingPicture ? NuruColors.lineGreen : theme.textTertiary)
            }
            .onChange(of: picturePickerItem) { _, item in
                guard let item else { return }
                uploadImage(item: item, target: .picture)
            }

            VStack(spacing: NuruSpacing.space1) {
                Text("プロフィールの設定")
                    .font(NuruFont.titleMedium())
                    .foregroundStyle(theme.textPrimary)
                Text("あなたの情報を入力しましょう。")
                    .font(NuruFont.bodySmall())
                    .foregroundStyle(theme.textSecondary)
            }

            VStack(spacing: NuruSpacing.space3) {
                signUpTextField("名前", placeholder: "表示名", text: $name)

                // アイコン画像URL + アップロードボタン
                signUpTextFieldWithUpload(
                    "アイコン画像URL",
                    placeholder: "https://...",
                    text: $picture,
                    pickerItem: $picturePickerItem,
                    isUploading: uploadingPicture
                )

                signUpTextField("自己紹介", placeholder: "", text: $about, axis: .vertical)

                Button { showAdvanced.toggle() } label: {
                    Text(showAdvanced ? "詳細設定を隠す" : "詳細設定を表示")
                        .font(NuruFont.labelSmall())
                        .foregroundStyle(NuruColors.lineGreen)
                }

                if showAdvanced {
                    // バナー画像URL + アップロードボタン
                    signUpTextFieldWithUpload(
                        "バナー画像URL",
                        placeholder: "https://...",
                        text: $banner,
                        pickerItem: $bannerPickerItem,
                        isUploading: uploadingBanner
                    )
                    .onChange(of: bannerPickerItem) { _, item in
                        guard let item else { return }
                        uploadImage(item: item, target: .banner)
                    }

                    signUpTextField("NIP-05 (認証)", placeholder: "user@example.com", text: $nip05)
                    signUpTextField("ライトニングアドレス", placeholder: "user@wallet.com", text: $lud16)
                    signUpTextField("ウェブサイト", placeholder: "https://...", text: $website)
                    signUpTextField("誕生日 (MM-DD)", placeholder: "01-01", text: $birthday)
                }
            }

            Button {
                onFinish(name, about, picture, banner, nip05, lud16, website, birthday)
            } label: {
                Group {
                    if isLoading {
                        ProgressView().tint(.white).scaleEffect(0.8)
                    } else {
                        Text("セットアップを完了する")
                            .font(NuruFont.buttonMedium())
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 56)
            }
            .buttonStyle(NuruPrimaryButtonStyle(isDisabled: isLoading))
            .disabled(isLoading)
        }
    }

    // MARK: - Image Upload

    private enum UploadTarget { case picture, banner }

    private func uploadImage(item: PhotosPickerItem, target: UploadTarget) {
        switch target {
        case .picture: uploadingPicture = true
        case .banner:  uploadingBanner = true
        }
        Task {
            defer {
                switch target {
                case .picture: uploadingPicture = false
                case .banner:  uploadingBanner = false
                }
            }
            guard let data = try? await item.loadTransferable(type: Data.self) else { return }
            let service = ImageUploadService(signer: nil)
            let compressed = service.compressImage(data: data)
            guard let url = try? await service.uploadImage(
                imageData: compressed,
                server: .nostrBuild
            ) else { return }

            switch target {
            case .picture: picture = url
            case .banner:  banner = url
            }
        }
    }

    // MARK: - Text Fields

    @ViewBuilder
    private func signUpTextField(
        _ label: String,
        placeholder: String,
        text: Binding<String>,
        axis: Axis = .horizontal
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(NuruFont.labelSmall())
                .foregroundStyle(theme.textSecondary)

            if axis == .vertical {
                TextField(placeholder, text: text, axis: .vertical)
                    .font(NuruFont.bodyMedium())
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(3...5)
                    .padding(NuruSpacing.space3)
                    .background(theme.bgSecondary)
                    .cornerRadius(NuruSpacing.radiusMd)
                    .overlay(
                        RoundedRectangle(cornerRadius: NuruSpacing.radiusMd)
                            .stroke(NuruColors.lineGreen, lineWidth: 1)
                    )
            } else {
                TextField(placeholder, text: text)
                    .font(NuruFont.bodyMedium())
                    .foregroundStyle(theme.textPrimary)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding(NuruSpacing.space3)
                    .background(theme.bgSecondary)
                    .cornerRadius(NuruSpacing.radiusMd)
                    .overlay(
                        RoundedRectangle(cornerRadius: NuruSpacing.radiusMd)
                            .stroke(NuruColors.lineGreen, lineWidth: 1)
                    )
            }
        }
    }

    @ViewBuilder
    private func signUpTextFieldWithUpload(
        _ label: String,
        placeholder: String,
        text: Binding<String>,
        pickerItem: Binding<PhotosPickerItem?>,
        isUploading: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(NuruFont.labelSmall())
                .foregroundStyle(theme.textSecondary)

            HStack(spacing: NuruSpacing.space2) {
                TextField(placeholder, text: text)
                    .font(NuruFont.bodyMedium())
                    .foregroundStyle(theme.textPrimary)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                PhotosPicker(selection: pickerItem, matching: .images) {
                    if isUploading {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(NuruColors.lineGreen)
                            .frame(width: 24, height: 24)
                    } else {
                        Image(systemName: "icloud.and.arrow.up")
                            .font(.system(size: 18))
                            .foregroundStyle(NuruColors.lineGreen)
                    }
                }
                .disabled(isUploading)
            }
            .padding(NuruSpacing.space3)
            .background(theme.bgSecondary)
            .cornerRadius(NuruSpacing.radiusMd)
            .overlay(
                RoundedRectangle(cornerRadius: NuruSpacing.radiusMd)
                    .stroke(NuruColors.lineGreen, lineWidth: 1)
            )
        }
    }
}

// MARK: - Step 5: Success

private struct SignUpSuccessStep: View {
    let npub: String
    let onComplete: () -> Void

    @Environment(\.nuruTheme) private var theme

    var body: some View {
        VStack(spacing: NuruSpacing.space5) {
            SignUpIconBox(
                systemName: "checkmark.circle.fill",
                containerColor: NuruColors.lineGreen.opacity(0.1),
                iconColor: NuruColors.lineGreen
            )

            VStack(spacing: NuruSpacing.space2) {
                Text("準備完了！")
                    .font(NuruFont.titleLarge())
                    .foregroundStyle(theme.textPrimary)
                Text("アカウントが作成されました。ぬるぬるへようこそ！")
                    .font(NuruFont.bodySmall())
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: NuruSpacing.space1) {
                Text("あなたの公開鍵 (npub)")
                    .font(NuruFont.labelSmall())
                    .foregroundStyle(theme.textTertiary)
                Text(npub)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(2)
            }
            .padding(NuruSpacing.space4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.bgSecondary)
            .cornerRadius(NuruSpacing.radiusXl)

            Button(action: onComplete) {
                Text("はじめる")
                    .font(NuruFont.buttonMedium())
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
            }
            .buttonStyle(NuruPrimaryButtonStyle())
        }
    }
}

// MARK: - Shared Icon Box

private struct SignUpIconBox: View {
    let systemName: String
    let containerColor: Color
    let iconColor: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(containerColor)
                .frame(width: 64, height: 64)
            Image(systemName: systemName)
                .font(.system(size: 28))
                .foregroundStyle(iconColor)
        }
    }
}

// MARK: - Nostr Connect Sheet (NIP-46)

struct NostrConnectSheet: View {
    @Binding var isPresented: Bool
    @Environment(AuthViewModel.self) private var viewModel
    @Environment(\.nuruTheme) private var theme

    @State private var bunkerInput = ""
    @State private var connectState: ConnectState = .input
    @State private var errorMessage: String?

    private enum ConnectState {
        case input
        case connecting
        case success(pubkeyHex: String)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                theme.bgPrimary.ignoresSafeArea()

                VStack(spacing: NuruSpacing.space5) {
                    switch connectState {
                    case .input:
                        inputView
                    case .connecting:
                        connectingView
                    case .success:
                        successView
                    }
                }
                .padding(NuruSpacing.space5)
            }
            .navigationTitle("Nostr Connect")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        isPresented = false
                    }
                    .foregroundStyle(theme.textSecondary)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Input View

    private var inputView: some View {
        VStack(spacing: NuruSpacing.space5) {
            Image(systemName: "network")
                .font(.system(size: 48))
                .foregroundStyle(NuruColors.lineGreen)

            Text("リモートサイナーに接続")
                .font(NuruFont.titleMedium())
                .foregroundStyle(theme.textPrimary)

            Text("Nostr Connectに対応したアプリ（nsecBunker等）からbunker:// URIを取得してください。")
                .font(NuruFont.bodySmall())
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)

            // URI input
            VStack(alignment: .leading, spacing: NuruSpacing.space2) {
                TextField("bunker://...", text: $bunkerInput)
                    .font(NuruFont.bodyMedium())
                    .foregroundStyle(theme.textPrimary)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding(NuruSpacing.space4)
                    .background(theme.bgSecondary)
                    .cornerRadius(NuruSpacing.radiusXl)
                    .overlay(
                        RoundedRectangle(cornerRadius: NuruSpacing.radiusXl)
                            .stroke(
                                errorMessage != nil ? NuruColors.colorError
                                    : (bunkerInput.isEmpty ? theme.borderColor : NuruColors.lineGreen),
                                lineWidth: 1.5
                            )
                    )

                if let err = errorMessage {
                    Text(err)
                        .font(NuruFont.bodySmall())
                        .foregroundStyle(NuruColors.colorError)
                        .padding(.horizontal, NuruSpacing.space2)
                }
            }

            // Paste from clipboard
            Button {
                if let clipboardText = UIPasteboard.general.string {
                    bunkerInput = clipboardText
                }
            } label: {
                HStack(spacing: NuruSpacing.space2) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 16))
                    Text("クリップボードから貼り付け")
                        .font(NuruFont.bodySmall())
                }
                .foregroundStyle(NuruColors.lineGreen)
            }

            // Connect button
            Button {
                Task { await startConnect() }
            } label: {
                Text("接続する")
                    .font(NuruFont.buttonMedium())
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
            }
            .buttonStyle(NuruPrimaryButtonStyle(isDisabled: bunkerInput.isEmpty))
            .disabled(bunkerInput.isEmpty)
        }
    }

    // MARK: - Connecting View

    private var connectingView: some View {
        VStack(spacing: NuruSpacing.space5) {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(1.5)
                .tint(NuruColors.lineGreen)

            Text("接続中...")
                .font(NuruFont.titleMedium())
                .foregroundStyle(theme.textPrimary)

            Text("リモートサイナーからの承認を待っています。\nサイナーアプリで接続を承認してください。")
                .font(NuruFont.bodySmall())
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Success View

    private var successView: some View {
        VStack(spacing: NuruSpacing.space5) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(NuruColors.lineGreen)

            Text("接続完了")
                .font(NuruFont.titleMedium())
                .foregroundStyle(theme.textPrimary)

            if case .success(let pubkeyHex) = connectState {
                let npub = NostrKeyUtils.shortenPubkey(pubkeyHex)
                Text(npub)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(theme.textSecondary)
                    .padding(NuruSpacing.space3)
                    .background(theme.bgSecondary)
                    .cornerRadius(NuruSpacing.radiusMd)
            }

            Button {
                if case .success(let pubkeyHex) = connectState {
                    viewModel.loginWithExternalSigner(pubkeyHex: pubkeyHex)
                }
                isPresented = false
            } label: {
                Text("ログインする")
                    .font(NuruFont.buttonMedium())
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
            }
            .buttonStyle(NuruPrimaryButtonStyle())
        }
    }

    // MARK: - Connect Logic

    @MainActor
    private func startConnect() async {
        errorMessage = nil
        connectState = .connecting

        do {
            let pubkeyHex = try await viewModel.connectExternalSigner(uri: bunkerInput)
            connectState = .success(pubkeyHex: pubkeyHex)
        } catch {
            connectState = .input
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Preview

#Preview {
    LoginView()
        .environment(AuthViewModel())
        .environment(\.nuruTheme, .dark)
}
