import SwiftUI

// MARK: - Error View (standalone)

/// エラー画面 — 励ましメッセージ + ヒント + リトライボタン.
/// Mirrors Android ErrorBoundary composable.
struct ErrorView: View {
    let onRetry: () -> Void

    @Environment(\.nuruTheme) private var theme

    private let message = encouragingMessages.randomElement() ?? encouragingMessages[0]
    private let hint    = helpfulHints.randomElement()        ?? helpfulHints[0]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: NuruIcons.emoji)
                .font(.system(size: 48))
                .foregroundStyle(theme.textTertiary)

            Spacer().frame(height: NuruSpacing.space4)

            Text("うまくいきませんでした")
                .font(NuruFont.titleLarge())
                .fontWeight(.bold)
                .foregroundStyle(theme.textPrimary)
                .multilineTextAlignment(.center)

            Spacer().frame(height: NuruSpacing.space2)

            Text(message)
                .font(NuruFont.bodyMedium())
                .foregroundStyle(theme.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, NuruSpacing.space8)

            Spacer().frame(height: NuruSpacing.space6)

            // Hint card
            HStack {
                Text("💡 \(hint)")
                    .font(NuruFont.bodySmall())
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(NuruSpacing.space4)
            .background(theme.bgSecondary)
            .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusMd))
            .padding(.horizontal, NuruSpacing.space4)

            Spacer().frame(height: NuruSpacing.space8)

            // Retry button
            Button(action: onRetry) {
                HStack(spacing: NuruSpacing.space2) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 16))
                    Text("もう一度試す")
                        .font(NuruFont.bodyMedium())
                        .fontWeight(.medium)
                }
                .foregroundStyle(.white)
                .frame(height: 48)
                .padding(.horizontal, NuruSpacing.space8)
                .background(NuruColors.lineGreen)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.bgPrimary)
    }
}

// MARK: - Error Boundary (container)

/// コンテンツをラップしてエラー状態をオーバーレイ表示するコンテナ.
/// `hasError` を外部から制御する形で使用:
/// ```swift
/// ErrorBoundary(hasError: $hasError, onRetry: { /* reload */ }) {
///     MyContentView()
/// }
/// ```
struct ErrorBoundary<Content: View>: View {
    @Binding var hasError: Bool
    let onRetry:  () -> Void
    let content:  Content

    init(hasError: Binding<Bool>, onRetry: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        _hasError   = hasError
        self.onRetry  = onRetry
        self.content  = content()
    }

    var body: some View {
        if hasError {
            ErrorView {
                hasError = false
                onRetry()
            }
        } else {
            content
        }
    }
}

// MARK: - Messages

private let encouragingMessages = [
    "ちょっと休憩してから、もう一度試してみましょう",
    "大丈夫、もう一度試せばきっとうまくいきます",
    "一時的な問題かもしれません。少し待ってからお試しください",
    "アプリを更新中かもしれません。少々お待ちください"
]

private let helpfulHints = [
    "インターネット接続を確認してみてください",
    "アプリを再起動すると解決することがあります",
    "しばらく待ってから再試行してみてください"
]
