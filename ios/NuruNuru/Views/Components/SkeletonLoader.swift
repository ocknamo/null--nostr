import SwiftUI

// MARK: - Base Skeleton Shape

/// Pulsing placeholder shape — mirrors Android Skeleton composable.
struct Skeleton: View {
    var cornerRadius: CGFloat = NuruSpacing.radiusSm

    @State private var opacity: Double = 0.3
    @Environment(\.nuruTheme) private var theme

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(theme.bgTertiary)
            .opacity(opacity)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 1.0).repeatForever(autoreverses: true)
                ) { opacity = 0.7 }
            }
    }
}

// MARK: - Post Skeleton

/// Single post placeholder row — mirrors Android PostSkeleton.
struct PostSkeleton: View {
    @Environment(\.nuruTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: NuruSpacing.space3) {
                // Avatar
                Skeleton(cornerRadius: 21)
                    .frame(width: 42, height: 42)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: NuruSpacing.space2) {
                    // Name
                    Skeleton().frame(width: 120, height: 16)
                    // Content lines
                    Skeleton().frame(maxWidth: .infinity).frame(height: 14)
                    Skeleton().frame(maxWidth: 200).frame(height: 14)
                }
            }
            .padding(.horizontal, NuruSpacing.space4)
            .padding(.vertical, NuruSpacing.space3)

            Divider().background(theme.borderColor)
        }
        .background(theme.bgPrimary)
    }
}

// MARK: - Timeline Loading Skeleton

/// Stack of post skeletons for timeline loading state — mirrors Android TimelineLoadingSkeleton.
struct TimelineLoadingSkeleton: View {
    var count: Int = 6

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { _ in
                PostSkeleton()
            }
        }
    }
}

// MARK: - Message Skeleton

/// Chat bubble placeholder — mirrors Android MessageSkeleton.
struct MessageSkeleton: View {
    var alignRight: Bool = false

    var body: some View {
        HStack {
            if alignRight { Spacer() }
            Skeleton(cornerRadius: alignRight ? NuruSpacing.radiusLg : NuruSpacing.radiusSm)
                .frame(maxWidth: UIScreen.main.bounds.width * 0.6)
                .frame(height: 40)
            if !alignRight { Spacer() }
        }
        .padding(.horizontal, NuruSpacing.space4)
        .padding(.vertical, 4)
    }
}

// MARK: - Profile Skeleton

/// Profile header loading placeholder — mirrors Android ProfileSkeleton composable.
struct ProfileSkeleton: View {
    @Environment(\.nuruTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            // Banner placeholder
            theme.bgSecondary
                .frame(maxWidth: .infinity)
                .frame(height: 112)

            // Card placeholder
            VStack(alignment: .leading, spacing: NuruSpacing.space3) {
                // Name row spacer (avatar overlap area)
                HStack {
                    Spacer().frame(width: 92)
                    VStack(alignment: .leading, spacing: NuruSpacing.space2) {
                        Skeleton().frame(width: 120, height: 18)
                        Skeleton().frame(width: 80, height: 14)
                    }
                }
                .padding(.top, NuruSpacing.space2)

                // About lines
                Skeleton().frame(maxWidth: .infinity).frame(height: 14)
                Skeleton().frame(maxWidth: 200).frame(height: 14)

                // Meta info
                Skeleton().frame(width: 160, height: 14)

                // Follow count
                Skeleton().frame(width: 100, height: 14)
            }
            .padding(NuruSpacing.space4)
            .background(theme.bgPrimary)
            .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusLg))
            .padding(.horizontal, NuruSpacing.space4)
            .offset(y: -56)
            .padding(.bottom, -56)
        }
    }
}

// MARK: - List Item Skeleton

/// Generic list row placeholder — mirrors Android ListItemSkeleton.
struct ListItemSkeleton: View {
    @Environment(\.nuruTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: NuruSpacing.space3) {
                Skeleton(cornerRadius: 20)
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: NuruSpacing.space2) {
                    Skeleton().frame(width: 100, height: 14)
                    Skeleton().frame(width: 180, height: 12)
                }
            }
            .padding(NuruSpacing.space4)

            Divider().background(theme.borderColor)
        }
        .background(theme.bgPrimary)
    }
}

// MARK: - Soft Refresh Indicator

/// 柔らかい更新/ロード表示。標準 ProgressView より機械的に見えないよう、
/// ふわっと脈動するブランドカラーのドットで表現する。
struct SoftRefreshIndicator: View {
    var title: String? = nil
    var compact: Bool = false

    @Environment(\.nuruTheme) private var theme
    @State private var animate = false

    var body: some View {
        HStack(spacing: compact ? 8 : 10) {
            ZStack {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(NuruColors.lineGreen.opacity(0.28 - Double(i) * 0.06))
                        .frame(width: compact ? 24 : 34, height: compact ? 24 : 34)
                        .scaleEffect(animate ? 1.0 + CGFloat(i) * 0.18 : 0.58 + CGFloat(i) * 0.08)
                        .opacity(animate ? 0.12 : 0.42)
                        .animation(
                            .easeInOut(duration: 1.25)
                                .repeatForever(autoreverses: true)
                                .delay(Double(i) * 0.13),
                            value: animate
                        )
                }
                Circle()
                    .fill(NuruColors.lineGreen)
                    .frame(width: compact ? 8 : 10, height: compact ? 8 : 10)
                    .scaleEffect(animate ? 1.18 : 0.82)
                    .animation(.easeInOut(duration: 0.72).repeatForever(autoreverses: true), value: animate)
            }
            .frame(width: compact ? 28 : 38, height: compact ? 28 : 38)

            if let title {
                Text(title)
                    .font(compact ? NuruFont.labelSmall() : NuruFont.bodySmall())
                    .fontWeight(.semibold)
                    .foregroundStyle(theme.textPrimary)
            }
        }
        .padding(.horizontal, compact ? 12 : 16)
        .padding(.vertical, compact ? 8 : 12)
        .background(
            Capsule()
                .fill(theme.bgSecondary.opacity(0.94))
                .overlay(Capsule().stroke(NuruColors.lineGreen.opacity(0.18), lineWidth: 1))
        )
        .shadow(color: .black.opacity(0.18), radius: 14, x: 0, y: 8)
        .onAppear { animate = true }
    }
}

