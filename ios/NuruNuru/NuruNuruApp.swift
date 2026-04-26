import SwiftUI

@main
struct NuruNuruApp: App {

    @State private var authViewModel = AuthViewModel()

    init() {
        // Clear log file on launch + log startup
        AppLogger.clearLogFile()
        AppLogger.log("General", "🚀 NuruNuru launching — log file: \(AppLogger.logFilePath)")
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(authViewModel)
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    authViewModel.handleDeepLink(url: url)
                }
                .task {
                    // 起動時に期限切れキャッシュを自動清掃（Android 同等）
                    let removed = NostrCache().clearExpiredCache()
                    if removed > 0 {
                        AppLogger.log("Cache", "Startup: cleaned \(removed) expired entries")
                    }
                }
        }
    }
}

private struct RootView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme: NuruTheme = colorScheme == .dark ? .dark : .light

        Group {
            switch authViewModel.state {
            case .checking:
                SplashView()
            case .loggedOut, .error:
                LoginView()
            case .loggedIn(let pubkeyHex):
                MainTabView(pubkeyHex: pubkeyHex, authViewModel: authViewModel)
                    // ⚠️ id を固定して SwiftUI が state 変更のたびに MainTabView を再作成するのを防止。
                    // id がないと authViewModel の @Observable プロパティ変更で body が再評価され、
                    // MainTabView が新インスタンスとして再作成 → TimelineViewModel が複数回初期化される。
                    .id(pubkeyHex)
            }
        }
        .environment(\.nuruTheme, theme)
    }
}

private struct SplashView: View {
    @Environment(\.nuruTheme) private var theme
    @State private var logoScale: CGFloat = 1.0

    var body: some View {
        ZStack {
            theme.bgPrimary.ignoresSafeArea()
            VStack(spacing: NuruSpacing.space5) {
                Image("logo")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radius2xl))
                    .scaleEffect(logoScale)
                    .onAppear {
                        // 起動体験を優先し、長い反復アニメーションは行わない
                        withAnimation(.easeOut(duration: 0.12)) { logoScale = 1.02 }
                    }
                Text("読み込み中...")
                    .font(NuruFont.bodyMedium())
                    .foregroundStyle(theme.textTertiary)
            }
        }
    }
}

