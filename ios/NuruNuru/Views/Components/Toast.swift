import SwiftUI

// MARK: - Toast Type

enum ToastType {
    case success, info, warning, error

    var icon: String {
        switch self {
        case .success: return NuruIcons.like(filled: true)
        case .info:    return NuruIcons.timeline(filled: true)
        case .warning: return NuruIcons.warning
        case .error:   return NuruIcons.warning
        }
    }

    var color: Color {
        switch self {
        case .success: return NuruColors.lineGreen
        case .info:    return Color(white: 0.5)
        case .warning: return Color(red: 1, green: 0.6, blue: 0)
        case .error:   return Color.red
        }
    }
}

// MARK: - Toast Message

struct ToastMessage: Identifiable {
    let id: UUID = UUID()
    let message: String
    let type: ToastType
    let durationMs: Double

    init(_ message: String, type: ToastType = .info, durationMs: Double = 3500) {
        self.message   = message
        self.type      = type
        self.durationMs = durationMs
    }
}

// MARK: - Toast State (Observable)

@Observable
final class ToastState {
    var toasts: [ToastMessage] = []

    func show(_ message: String, type: ToastType = .info, durationMs: Double = 3500) {
        toasts.append(ToastMessage(message, type: type, durationMs: durationMs))
    }

    func dismiss(id: UUID) {
        toasts.removeAll { $0.id == id }
    }
}

// MARK: - Environment Key

private struct ToastStateKey: EnvironmentKey {
    static let defaultValue = ToastState()
}

extension EnvironmentValues {
    var toastState: ToastState {
        get { self[ToastStateKey.self] }
        set { self[ToastStateKey.self] = newValue }
    }
}

// MARK: - Toast Provider (root wrapper)

struct ToastProvider<Content: View>: View {
    @State private var state = ToastState()
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            content
                .environment(\.toastState, state)

            VStack(spacing: NuruSpacing.space2) {
                ForEach(state.toasts) { toast in
                    ToastItem(toast: toast) { state.dismiss(id: toast.id) }
                }
            }
            .padding(.horizontal, NuruSpacing.space4)
            .padding(.bottom, 80)
        }
    }
}

// MARK: - Toast Item

private struct ToastItem: View {
    let toast: ToastMessage
    let onDismiss: () -> Void

    @Environment(\.nuruTheme) private var theme

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: toast.type.icon)
                .font(.system(size: 16))
                .foregroundStyle(toast.type.color)

            Text(toast.message)
                .font(NuruFont.bodySmall())
                .foregroundStyle(theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onDismiss) {
                Image(systemName: NuruIcons.close)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, NuruSpacing.space3)
        .padding(.vertical, 10)
        .frame(minWidth: 200, maxWidth: 340)
        .background(theme.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusMd))
        .overlay(
            RoundedRectangle(cornerRadius: NuruSpacing.radiusMd)
                .stroke(theme.borderColor.opacity(0.5), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 4)
        .task {
            try? await Task.sleep(for: .milliseconds(Int(toast.durationMs)))
            onDismiss()
        }
    }
}

// MARK: - Toast Messages Constants

enum ToastMessages {
    static let postSuccess     = "投稿しました"
    static let postFailed      = "投稿できませんでした"
    static let likeSuccess     = "いいねしました"
    static let repostSuccess   = "リポストしました"
    static let zapSuccess      = "Zapを送りました"
    static let zapFailed       = "Zapを送れませんでした"
    static let followSuccess   = "フォローしました"
    static let profileUpdated  = "プロフィールを更新しました"
    static let copied          = "コピーしました"
}
