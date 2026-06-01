import SwiftUI

/// Lightweight app settings page opened from the Home header gear button.
/// Keep this separate from the Mini Apps tab so the gear does not switch tabs.
struct AppSettingsView: View {
    let pubkeyHex: String
    let authViewModel: AuthViewModel
    let repository: NostrRepository
    let prefs: AppPreferences
    var onDismiss: () -> Void = {}
    var onLogout:  () -> Void = {}

    @Environment(\.nuruTheme) private var theme
    private let privacyURL = URL(string: "https://tami1A84.github.io/null--nostr/privacy.html")!
    private let termsURL = URL(string: "https://tami1A84.github.io/null--nostr/terms.html")!

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: NuruSpacing.space4) {
                    AccountSecuritySettingsView(
                        pubkeyHex: pubkeyHex,
                        authViewModel: authViewModel,
                        repository: repository,
                        prefs: prefs,
                        onLogout: onLogout
                    )

                    settingsRow(
                        icon: "hand.raised",
                        title: "プライバシーポリシー",
                        subtitle: "個人情報とデータの取り扱いを確認",
                        trailing: "chevron.right"
                    ) {
                        UIApplication.shared.open(privacyURL)
                    }

                    settingsRow(
                        icon: "doc.text",
                        title: "利用規約",
                        subtitle: "禁止事項、通報、ブロックについて確認",
                        trailing: "chevron.right"
                    ) {
                        UIApplication.shared.open(termsURL)
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
