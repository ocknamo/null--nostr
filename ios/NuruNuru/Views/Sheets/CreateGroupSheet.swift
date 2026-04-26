import SwiftUI

/// グループ作成シート。
/// フォロー中ユーザーを検索・選択してグループを作成する。
/// Android: TalkScreen.kt の CreateGroupSheet に対応。
struct CreateGroupSheet: View {

    let followingProfiles: [UserProfile]
    let isLoading:         Bool
    let onCreate:          (String, [String]) -> Void
    let onDismiss:         () -> Void

    @Environment(\.nuruTheme) private var theme
    @State private var groupName:     String     = ""
    @State private var searchQuery:   String     = ""
    @State private var selectedKeys:  Set<String> = []
    @State private var isCreating:    Bool        = false

    private var canCreate: Bool {
        !groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !selectedKeys.isEmpty && !isCreating
    }

    private var filteredProfiles: [UserProfile] {
        guard !searchQuery.isEmpty else { return followingProfiles }
        let q = searchQuery.lowercased()
        return followingProfiles.filter {
            $0.displayedName.lowercased().contains(q) ||
            ($0.nip05 ?? "").lowercased().contains(q) ||
            $0.pubkey.hasPrefix(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // ─── Nav Bar ─────────────────────────────────────────────────
            SheetNavBar(title: "グループ作成", onDismiss: onDismiss) {
                Button {
                    guard canCreate else { return }
                    isCreating = true
                    onCreate(
                        groupName.trimmingCharacters(in: .whitespacesAndNewlines),
                        Array(selectedKeys)
                    )
                } label: {
                    if isCreating {
                        ProgressView().tint(NuruColors.lineGreen)
                            .frame(width: 40, height: 40)
                    } else {
                        Text("作成")
                            .font(NuruFont.titleMedium())
                            .foregroundStyle(canCreate ? NuruColors.lineGreen : theme.textTertiary)
                            .frame(width: 40, height: 40)
                    }
                }
                .disabled(!canCreate)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: NuruSpacing.space4) {

                    // ─── Group Name ───────────────────────────────────────
                    VStack(alignment: .leading, spacing: NuruSpacing.space2) {
                        sectionHeader("グループ名")
                        TextField("グループ名を入力", text: $groupName)
                            .font(NuruFont.bodyMedium())
                            .foregroundStyle(theme.textPrimary)
                            .padding(NuruSpacing.space3)
                            .background(theme.bgSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusMd))
                    }
                    .padding(.horizontal, NuruSpacing.space4)

                    // ─── Selected chips ───────────────────────────────────
                    if !selectedKeys.isEmpty {
                        selectedChips
                            .padding(.horizontal, NuruSpacing.space4)
                    }

                    // ─── Member Picker ────────────────────────────────────
                    VStack(alignment: .leading, spacing: NuruSpacing.space2) {
                        HStack {
                            sectionHeader("メンバーを選択")
                            if !selectedKeys.isEmpty {
                                Text("\(selectedKeys.count)人")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(NuruColors.lineGreen)
                                    .clipShape(Capsule())
                            }
                            Spacer()
                        }

                        // Search field
                        HStack(spacing: NuruSpacing.space2) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 14))
                                .foregroundStyle(theme.textTertiary)
                            TextField("名前・NIP-05 で絞り込む", text: $searchQuery)
                                .font(NuruFont.bodyMedium())
                                .foregroundStyle(theme.textPrimary)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        }
                        .padding(NuruSpacing.space3)
                        .background(theme.bgSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusMd))

                        // Profile list
                        if isLoading {
                            HStack {
                                Spacer()
                                ProgressView().tint(NuruColors.lineGreen)
                                Spacer()
                            }
                            .padding(.vertical, NuruSpacing.space4)
                        } else if filteredProfiles.isEmpty {
                            Text(followingProfiles.isEmpty
                                 ? "フォロー中のユーザーがいません"
                                 : "\"\\(searchQuery)\" に一致するユーザーが見つかりません")
                                .font(NuruFont.bodySmall())
                                .foregroundStyle(theme.textTertiary)
                                .padding(.vertical, NuruSpacing.space3)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(filteredProfiles, id: \.pubkey) { profile in
                                    profileRow(profile)
                                    if profile.pubkey != filteredProfiles.last?.pubkey {
                                        Divider()
                                            .padding(.leading, 56)
                                            .background(theme.borderColor)
                                    }
                                }
                            }
                            .background(theme.bgSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusMd))
                        }
                    }
                    .padding(.horizontal, NuruSpacing.space4)
                }
                .padding(.vertical, NuruSpacing.space4)
            }
        }
        .background(theme.bgPrimary.ignoresSafeArea())
    }

    // MARK: - Row

    private func profileRow(_ profile: UserProfile) -> some View {
        let isSelected = selectedKeys.contains(profile.pubkey)
        return Button {
            if isSelected { selectedKeys.remove(profile.pubkey) }
            else          { selectedKeys.insert(profile.pubkey) }
        } label: {
            HStack(spacing: NuruSpacing.space3) {
                // Avatar
                AvatarView(url: profile.picture, name: profile.displayedName, size: 40)

                // Name / NIP-05
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.displayedName)
                        .font(NuruFont.bodyMedium())
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)
                    if let nip05 = profile.nip05, !nip05.isEmpty {
                        Text(nip05)
                            .font(NuruFont.labelSmall())
                            .foregroundStyle(theme.textTertiary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Checkmark
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? NuruColors.lineGreen : theme.textTertiary)
            }
            .padding(.horizontal, NuruSpacing.space3)
            .padding(.vertical, NuruSpacing.space2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Selected Chips

    private var selectedChips: some View {
        let profiles = followingProfiles.filter { selectedKeys.contains($0.pubkey) }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: NuruSpacing.space2) {
                ForEach(profiles, id: \.pubkey) { profile in
                    HStack(spacing: 6) {
                        AvatarView(url: profile.picture, name: profile.displayedName, size: 20)
                        Text(profile.displayedName)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Button {
                            selectedKeys.remove(profile.pubkey)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, NuruSpacing.space2)
                    .padding(.vertical, 6)
                    .background(NuruColors.lineGreen)
                    .clipShape(Capsule())
                }
            }
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(NuruFont.labelSmall())
            .foregroundStyle(theme.textTertiary)
    }
}
