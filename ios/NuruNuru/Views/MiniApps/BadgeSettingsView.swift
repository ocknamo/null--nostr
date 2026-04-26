import SwiftUI

/// プロフィールバッジ mini-app — manage NIP-58 badges.
/// Mirrors Android BadgeSettings.kt.
/// プロフィールバッジ一覧 + 受け取ったバッジ一覧 + 入れ替え（並び替え）機能。
struct BadgeSettingsView: View {

    let repository:  NostrRepository
    let pubkeyHex:   String

    @Environment(\.nuruTheme) private var theme
    @State private var profileBadges:  [BadgeItem] = []   // Kind 30008 に設定済み
    @State private var awardedBadges:  [BadgeItem] = []   // Kind 8 で受け取った全バッジ
    @State private var isLoading:      Bool        = true
    @State private var isSaving:       Bool        = false
    @State private var hasChanges:     Bool        = false
    @State private var errorMessage:   String?     = nil

    var body: some View {
        Group {
            if isLoading {
                VStack { Spacer(); ProgressView().tint(NuruColors.lineGreen); Spacer() }
                    .frame(maxWidth: .infinity)
            } else if profileBadges.isEmpty && awardedBadges.isEmpty {
                VStack(spacing: NuruSpacing.space3) {
                    Spacer()
                    Image(systemName: "rosette")
                        .font(.system(size: 48))
                        .foregroundStyle(theme.textTertiary)
                    Text("バッジがありません")
                        .font(NuruFont.bodyMedium())
                        .foregroundStyle(theme.textTertiary)
                    Text("他のユーザーからバッジを授与されると\nここに表示されます")
                        .font(NuruFont.bodySmall())
                        .foregroundStyle(theme.textTertiary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List {
                    // MARK: プロフィールバッジ（Kind 30008 設定済み・並び替え可能）
                    Section {
                        if profileBadges.isEmpty {
                            Text("プロフィールにバッジが設定されていません")
                                .font(NuruFont.bodySmall())
                                .foregroundStyle(theme.textTertiary)
                                .listRowBackground(theme.bgSecondary)
                        } else {
                            ForEach(profileBadges) { badge in
                                badgeRow(badge, isProfile: true)
                            }
                            .onMove { source, destination in
                                profileBadges.move(fromOffsets: source, toOffset: destination)
                                hasChanges = true
                            }
                            .onDelete { offsets in
                                let removed = offsets.map { profileBadges[$0] }
                                profileBadges.remove(atOffsets: offsets)
                                // プロフィールから外したバッジを受け取り一覧に戻す
                                for badge in removed {
                                    if !awardedBadges.contains(where: { $0.id == badge.id }) {
                                        awardedBadges.append(badge)
                                    }
                                }
                                hasChanges = true
                            }
                        }
                    } header: {
                        HStack {
                            Text("プロフィールバッジ")
                                .font(NuruFont.labelSmall())
                            Spacer()
                            if !profileBadges.isEmpty {
                                EditButton()
                                    .font(NuruFont.labelSmall())
                                    .foregroundStyle(NuruColors.lineGreen)
                            }
                        }
                    }

                    // MARK: 受け取ったバッジ（Kind 8 から取得、プロフィール未設定のもの）
                    if !unsetAwardedBadges.isEmpty {
                        Section {
                            ForEach(unsetAwardedBadges) { badge in
                                badgeRow(badge, isProfile: false)
                                    .swipeActions(edge: .trailing) {
                                        Button {
                                            addToProfile(badge)
                                        } label: {
                                            Label("追加", systemImage: "plus.circle")
                                        }
                                        .tint(NuruColors.lineGreen)
                                    }
                            }
                        } header: {
                            Text("受け取ったバッジ")
                                .font(NuruFont.labelSmall())
                        }
                    }

                    // Error
                    if let msg = errorMessage {
                        Section {
                            Text(msg)
                                .font(NuruFont.bodySmall())
                                .foregroundStyle(NuruColors.colorError)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(theme.bgPrimary)
                .toolbar {
                    if hasChanges {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                Task { await saveProfileBadges() }
                            } label: {
                                if isSaving {
                                    ProgressView().tint(.white)
                                } else {
                                    Text("保存")
                                        .font(NuruFont.buttonMedium())
                                        .foregroundStyle(NuruColors.lineGreen)
                                }
                            }
                            .disabled(isSaving)
                        }
                    }
                }
            }
        }
        .background(theme.bgPrimary)
        .task { await loadBadges() }
    }

    // MARK: - Badge Row

    @ViewBuilder
    private func badgeRow(_ badge: BadgeItem, isProfile: Bool) -> some View {
        HStack(spacing: NuruSpacing.space3) {
            if let url = URL(string: badge.imageUrl ?? "") {
                AsyncImage(url: url) { phase in
                    if case .success(let img) = phase {
                        img.resizable().scaledToFill()
                    } else {
                        RoundedRectangle(cornerRadius: 4).fill(theme.bgTertiary)
                    }
                }
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusSm))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: NuruSpacing.radiusSm)
                        .fill(theme.bgTertiary)
                    Image(systemName: "rosette")
                        .foregroundStyle(theme.textTertiary)
                }
                .frame(width: 44, height: 44)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(badge.name.isEmpty ? badge.id : badge.name)
                    .font(NuruFont.bodyMedium())
                    .foregroundStyle(theme.textPrimary)
                if let desc = badge.description, !desc.isEmpty {
                    Text(desc)
                        .font(NuruFont.bodySmall())
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            // プロフィール未設定バッジ → 追加ボタン
            if !isProfile {
                Button { addToProfile(badge) } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(NuruColors.lineGreen)
                }
                .buttonStyle(.plain)
            }
        }
        .listRowBackground(theme.bgSecondary)
    }

    // MARK: - Helpers

    /// プロフィールに未設定の受け取りバッジ
    private var unsetAwardedBadges: [BadgeItem] {
        let profileIds = Set(profileBadges.map(\.id))
        return awardedBadges.filter { !profileIds.contains($0.id) }
    }

    /// バッジをプロフィールに追加（最大3つ）
    private func addToProfile(_ badge: BadgeItem) {
        guard profileBadges.count < 3 else {
            errorMessage = "プロフィールバッジは最大3つまでです"
            return
        }
        guard !profileBadges.contains(where: { $0.id == badge.id }) else { return }
        profileBadges.append(badge)
        hasChanges = true
        errorMessage = nil
    }

    // MARK: - Load & Save

    private func loadBadges() async {
        isLoading = true
        async let profileTask  = repository.fetchBadges(pubkeyHex: pubkeyHex)
        async let awardedTask  = repository.fetchAwardedBadges(pubkeyHex: pubkeyHex)
        let (profile, awarded) = await (profileTask, awardedTask)
        profileBadges = profile
        awardedBadges = awarded
        isLoading = false
    }

    private func saveProfileBadges() async {
        isSaving = true
        errorMessage = nil
        do {
            try await repository.publishProfileBadges(badges: profileBadges)
            hasChanges = false
        } catch {
            errorMessage = "保存に失敗しました: \(error.localizedDescription)"
        }
        isSaving = false
    }
}
