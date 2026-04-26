import SwiftUI

/// フォロー中リスト — アンフォローボタン付き.
/// Mirrors Android FollowListModal composable.
/// Usage: .sheet(isPresented:) { FollowListSheet(...) }
struct FollowListSheet: View {
    let pubkeys:      [String]
    let profiles:     [String: UserProfile]
    let onDismiss:    () -> Void
    let onUnfollow:   (String) -> Void
    let onProfileTap: (String) -> Void

    @Environment(\.nuruTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            // Handle
            Capsule()
                .fill(theme.textTertiary.opacity(0.4))
                .frame(width: 40, height: 4)
                .padding(.top, NuruSpacing.space3)

            // Title
            Text("フォロー中 (\(pubkeys.count))")
                .font(NuruFont.titleMedium())
                .fontWeight(.bold)
                .foregroundStyle(theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, NuruSpacing.space4)
                .padding(.vertical, NuruSpacing.space4)

            Divider().background(theme.borderColor)

            // List
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(pubkeys, id: \.self) { pk in
                        followRow(pk: pk, profile: profiles[pk])
                        Divider().background(theme.borderColor)
                    }
                }
            }
        }
        .background(theme.bgPrimary)
    }

    private func followRow(pk: String, profile: UserProfile?) -> some View {
        HStack(spacing: NuruSpacing.space3) {
            // Avatar
            AvatarView(
                url:  profile?.picture,
                name: profile?.displayedName ?? "?",
                size: 40
            )
            .onTapGesture { onProfileTap(pk) }

            // Name + NIP-05
            VStack(alignment: .leading, spacing: 2) {
                Text(profile?.displayedName ?? pk.shortenedPubkey)
                    .font(NuruFont.bodyMedium())
                    .fontWeight(.bold)
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                if let nip05 = profile?.nip05, !nip05.isEmpty {
                    Text(nip05)
                        .font(NuruFont.bodySmall())
                        .foregroundStyle(NuruColors.lineGreen)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { onProfileTap(pk) }

            // Unfollow button
            Button {
                onUnfollow(pk)
            } label: {
                Text("解除")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.red)
                    .frame(height: 32)
                    .padding(.horizontal, NuruSpacing.space3)
                    .background(Color.clear)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.red, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, NuruSpacing.space4)
        .padding(.vertical, NuruSpacing.space3)
    }
}
