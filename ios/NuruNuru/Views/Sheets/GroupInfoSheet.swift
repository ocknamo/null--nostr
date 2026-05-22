import SwiftUI

/// グループ情報シート。
/// 管理者の場合はメンバーの追加・削除が可能。
/// Android: TalkScreen.kt の GroupInfoSheet + GroupMemberRow に対応。
struct GroupInfoSheet: View {

    let group:        MlsGroup
    let myPubkeyHex:  String
    let onLeave:      () -> Void
    let onDismiss:    () -> Void

    /// メンバー追加時にフォロー中プロファイルを提供するための ViewModel。
    /// TalkViewModel と同じ参照を渡す。
    var viewModel:    TalkViewModel? = nil

    @Environment(\.nuruTheme)  private var theme
    @State private var showLeaveConfirm     = false
    @State private var showAddMember        = false
    @State private var removeTarget:  String? = nil

    private var isAdmin: Bool {
        group.adminPubkeys.contains(myPubkeyHex)
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetNavBar(title: "グループ情報", onDismiss: onDismiss) {
                Color.clear.frame(width: 40, height: 40)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: NuruSpacing.space4) {

                    // ─── Name ─────────────────────────────────────────────
                    if !group.name.isEmpty {
                        infoSection("グループ名") {
                            Text(group.name)
                                .font(NuruFont.bodyMedium())
                                .foregroundStyle(theme.textPrimary)
                        }
                    }

                    // ─── Description ──────────────────────────────────────
                    if !group.description.isEmpty {
                        infoSection("説明") {
                            Text(group.description)
                                .font(NuruFont.bodyMedium())
                                .foregroundStyle(theme.textPrimary)
                        }
                    }

                    // ─── Group ID ─────────────────────────────────────────
                    infoSection("グループID") {
                        Text(group.groupIdHex)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(theme.textSecondary)
                            .textSelection(.enabled)
                            .lineLimit(nil)
                    }

                    // ─── Members ──────────────────────────────────────────
                    VStack(alignment: .leading, spacing: NuruSpacing.space2) {
                        HStack {
                            sectionLabel("メンバー (\(group.memberPubkeys.count)人)")
                            Spacer()
                            // Admin: add member button
                            if isAdmin {
                                Button {
                                    Task { await viewModel?.loadFollowingProfiles() }
                                    showAddMember = true
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "person.badge.plus")
                                            .font(.system(size: 14))
                                        Text("追加")
                                            .font(NuruFont.labelSmall())
                                    }
                                    .foregroundStyle(NuruColors.lineGreen)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, NuruSpacing.space4)

                        VStack(spacing: 0) {
                            ForEach(group.memberPubkeys, id: \.self) { pubkey in
                                memberRow(pubkey: pubkey)
                                if pubkey != group.memberPubkeys.last {
                                    Divider()
                                        .padding(.leading, 60)
                                        .background(theme.borderColor)
                                }
                            }
                        }
                        .background(theme.bgSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusMd))
                        .padding(.horizontal, NuruSpacing.space4)
                    }

                    // ─── Leave ────────────────────────────────────────────
                    Button(role: .destructive) {
                        showLeaveConfirm = true
                    } label: {
                        Text("グループを退出")
                            .font(NuruFont.bodyMedium())
                            .foregroundStyle(NuruColors.colorError)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, NuruSpacing.space3)
                            .background(NuruColors.colorError.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusMd))
                    }
                    .padding(.horizontal, NuruSpacing.space4)
                    .padding(.top, NuruSpacing.space2)
                }
                .padding(.vertical, NuruSpacing.space4)
            }
        }
        .background(theme.bgPrimary.ignoresSafeArea())
        // Leave confirmation (admin と非admin で文言を区別)
        .confirmationDialog(
            isAdmin ? "管理者としてグループを退出しますか？\n退出後、管理者が不在になる可能性があります。"
                    : "グループを退出しますか？",
            isPresented: $showLeaveConfirm,
            titleVisibility: .visible
        ) {
            Button("退出する", role: .destructive) { onLeave() }
            Button("キャンセル", role: .cancel) {}
        }
        // Remove member confirmation
        .confirmationDialog("メンバーを削除しますか？", isPresented: Binding(
            get: { removeTarget != nil },
            set: { if !$0 { removeTarget = nil } }
        ), titleVisibility: .visible) {
            if let target = removeTarget {
                Button("削除する", role: .destructive) {
                    Task { await viewModel?.removeMemberFromGroup(groupIdHex: group.groupIdHex, memberPubkey: target) }
                    removeTarget = nil
                }
                Button("キャンセル", role: .cancel) { removeTarget = nil }
            }
        }
        // Add member sheet
        .sheet(isPresented: $showAddMember) {
            if let vm = viewModel {
                AddMemberSheet(
                    group:             group,
                    followingProfiles: vm.followingProfiles,
                    isLoading:         vm.followingLoading,
                    onAdd: { pubkey in
                        showAddMember = false
                        Task { await vm.addMemberToGroup(groupIdHex: group.groupIdHex, memberPubkey: pubkey) }
                    },
                    onDismiss: { showAddMember = false }
                )
            }
        }
    }

    // MARK: - Member Row

    @ViewBuilder
    private func memberRow(pubkey: String) -> some View {
        let profile   = group.memberProfiles[pubkey]
        let isMe      = pubkey == myPubkeyHex
        let isMbrAdmin = group.adminPubkeys.contains(pubkey)
        let canRemove = isAdmin && !isMe && !isMbrAdmin

        HStack(spacing: NuruSpacing.space3) {
            AvatarView(url: profile?.picture, name: profile?.displayedName ?? "", size: 40)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(profile?.displayedName ?? String(pubkey.prefix(12)))
                        .font(NuruFont.bodyMedium())
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)
                    if isMbrAdmin {
                        Text("管理者")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(NuruColors.lineGreen)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(NuruColors.lineGreen.opacity(0.15))
                            .clipShape(Capsule())
                    }
                    if isMe {
                        Text("自分")
                            .font(.system(size: 10))
                            .foregroundStyle(theme.textTertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(theme.bgTertiary)
                            .clipShape(Capsule())
                    }
                }
                if let nip05 = profile?.nip05, !nip05.isEmpty {
                    Text(nip05)
                        .font(NuruFont.labelSmall())
                        .foregroundStyle(theme.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Admin: remove button (not self, not other admins)
            if canRemove {
                Button {
                    removeTarget = pubkey
                } label: {
                    Image(systemName: "person.badge.minus")
                        .font(.system(size: 16))
                        .foregroundStyle(NuruColors.colorError)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, NuruSpacing.space3)
        .padding(.vertical, NuruSpacing.space2)
    }

    // MARK: - Helpers

    private func infoSection<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: NuruSpacing.space2) {
            sectionLabel(label)
            content()
                .padding(NuruSpacing.space3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.bgSecondary)
                .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusMd))
        }
        .padding(.horizontal, NuruSpacing.space4)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(NuruFont.labelSmall())
            .foregroundStyle(theme.textTertiary)
    }
}

// MARK: - Add Member Sheet

/// メンバー追加シート — フォロー中ユーザーから1人を選んで追加。
private struct AddMemberSheet: View {

    let group:             MlsGroup
    let followingProfiles: [UserProfile]
    let isLoading:         Bool
    let onAdd:             (String) -> Void
    let onDismiss:         () -> Void

    @Environment(\.nuruTheme) private var theme
    @State private var searchQuery = ""

    /// 既にグループメンバーでないプロファイルのみ表示。
    private var candidates: [UserProfile] {
        let existing = Set(group.memberPubkeys)
        let base = followingProfiles.filter { !existing.contains($0.pubkey) }
        guard !searchQuery.isEmpty else { return base }
        let q = searchQuery.lowercased()
        return base.filter {
            $0.displayedName.lowercased().contains(q) ||
            ($0.nip05 ?? "").lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetNavBar(title: "メンバーを追加", onDismiss: onDismiss) {
                Color.clear.frame(width: 40, height: 40)
            }

            // Search
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
            .padding(.horizontal, NuruSpacing.space4)
            .padding(.vertical, NuruSpacing.space3)

            Group {
                if isLoading {
                    VStack { Spacer(); ProgressView().tint(NuruColors.lineGreen); Spacer() }
                } else if candidates.isEmpty {
                    VStack(spacing: NuruSpacing.space2) {
                        Spacer()
                        Image(systemName: "person.slash")
                            .font(.system(size: 40))
                            .foregroundStyle(theme.textTertiary)
                        Text("追加できるユーザーがいません")
                            .font(NuruFont.bodyMedium())
                            .foregroundStyle(theme.textTertiary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(candidates, id: \.pubkey) { profile in
                                Button {
                                    onAdd(profile.pubkey)
                                } label: {
                                    HStack(spacing: NuruSpacing.space3) {
                                        AvatarView(url: profile.picture, name: profile.displayedName, size: 40)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(profile.displayedName)
                                                .font(NuruFont.bodyMedium())
                                                .foregroundStyle(theme.textPrimary)
                                                .lineLimit(1)
                                            if let n = profile.nip05, !n.isEmpty {
                                                Text(n).font(NuruFont.labelSmall()).foregroundStyle(theme.textTertiary)
                                            }
                                        }
                                        Spacer()
                                        Image(systemName: "plus.circle")
                                            .font(.system(size: 20))
                                            .foregroundStyle(NuruColors.lineGreen)
                                    }
                                    .padding(.horizontal, NuruSpacing.space4)
                                    .padding(.vertical, NuruSpacing.space3)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                Divider().padding(.leading, 64).background(theme.borderColor)
                            }
                        }
                    }
                    .background(theme.bgPrimary)
                }
            }
        }
        .background(theme.bgPrimary.ignoresSafeArea())
    }
}
