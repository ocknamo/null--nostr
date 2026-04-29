import SwiftUI

/// フォロー中リスト — アンフォローボタン付き.
/// Mirrors Android FollowListModal composable.
/// Usage: .sheet(isPresented:) { FollowListSheet(...) }
struct FollowListSheet: View {
    let pubkeys:      [String]
    let profiles:     [String: UserProfile]
    var repository:   NostrRepository? = nil
    let onDismiss:    () -> Void
    let onUnfollow:   (String) -> Void
    let onProfileTap: (String) -> Void

    @Environment(\.nuruTheme) private var theme
    @State private var resolvedProfiles: [String: UserProfile] = [:]

    private func profile(for pk: String) -> UserProfile? {
        resolvedProfiles[pk] ?? profiles[pk]
    }

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
                        followRow(pk: pk, profile: profile(for: pk))
                        Divider().background(theme.borderColor)
                    }
                }
            }
        }
        .background(theme.bgPrimary)
        .task(id: pubkeys.joined(separator: ",")) {
            await resolveMissingProfiles()
        }
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
                    .truncationMode(.tail)
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
        .task(id: pk) {
            await resolveProfileIfNeeded(pk)
        }
    }

    @MainActor
    private func mergeProfiles(_ fetched: [UserProfile]) {
        for p in fetched where isDisplayProfileResolved(p) {
            resolvedProfiles[p.pubkey] = p
        }
    }

    private func resolveMissingProfiles() async {
        guard let repository else { return }
        var missing: [String] = []
        for pk in pubkeys {
            if let profile = profiles[pk] ?? resolvedProfiles[pk], isDisplayProfileResolved(profile) {
                continue
            }
            if let cached = repository.getCachedProfile(pubkey: pk), isDisplayProfileResolved(cached) {
                await MainActor.run { resolvedProfiles[pk] = cached }
            } else {
                missing.append(pk)
            }
        }
        guard !missing.isEmpty else { return }

        // Kind 0 の大量 authors クエリはリレー側で欠落することがあるため、まずバッチ取得、
        // 画面に見えている行は followRow の task でも個別補完する。
        let fetched = await repository.fetchProfiles(pubkeys: Array(missing.prefix(200)))
        await mergeProfiles(fetched)
    }

    private func resolveProfileIfNeeded(_ pk: String) async {
        guard let repository else { return }
        if let profile = profiles[pk] ?? resolvedProfiles[pk], isDisplayProfileResolved(profile) {
            return
        }
        if let cached = repository.getCachedProfile(pubkey: pk), isDisplayProfileResolved(cached) {
            await MainActor.run { resolvedProfiles[pk] = cached }
            return
        }
        if let fetched = await repository.fetchProfile(pubkey: pk), isDisplayProfileResolved(fetched) {
            await MainActor.run { resolvedProfiles[pk] = fetched }
        }
    }

    private func isDisplayProfileResolved(_ profile: UserProfile) -> Bool {
        let name = profile.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let username = profile.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let nip05 = profile.nip05?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (name?.isEmpty == false) || (username?.isEmpty == false) || (nip05?.isEmpty == false)
    }
}
