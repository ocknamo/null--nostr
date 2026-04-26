import SwiftUI

/// Notification sheet — reactions, reposts, replies, zaps (past 24h).
/// Mirrors Android NotificationModal.kt.
struct NotificationSheet: View {

    let repository:   NostrRepository
    let myPubkeyHex:  String
    let prefs:        AppPreferences
    var onProfileTap: (String) -> Void = { _ in }

    @Environment(\.dismiss)    private var dismiss
    @Environment(\.nuruTheme) private var theme

    @State private var notifications: [NotificationItem] = []
    @State private var profiles:      [String: UserProfile] = [:]
    @State private var originalPosts: [String: NostrEvent] = [:]
    @State private var isLoading:     Bool = true
    @State private var isRefreshing:  Bool = false

    // ライブポーリング + 新着Pill (Android LaunchedEffect while(true) { delay(10_000) } 相当)
    @State private var pendingNew:   [NotificationItem] = []
    @State private var pollingTask:  Task<Void, Never>?

    // 通知Kind設定 (Android showKindSettings + AlertDialog 相当)
    @State private var showKindSettings: Bool = false
    @State private var enabledKinds:     Set<Int> = []
    @State private var emojiReactionEnabled: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            sheetNavBar

            if isLoading {
                Spacer()
                ProgressView().tint(NuruColors.lineGreen)
                Spacer()
            } else if notifications.isEmpty && pendingNew.isEmpty {
                Spacer()
                emptyState
                Spacer()
            } else {
                ZStack(alignment: .top) {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(notifications) { notif in
                                notificationRow(notif)
                                // Android: HorizontalDivider(Modifier.padding(start = 74.dp))
                                Divider()
                                    .background(theme.borderColor.opacity(0.5))
                                    .padding(.leading, 74)
                            }
                        }
                    }
                    .refreshable {
                        isRefreshing = true
                        await loadNotifications(skipCache: true)
                        pendingNew = []
                        isRefreshing = false
                    }

                    // 新着Pill (Android AnimatedVisibility + 「新着 N 件」 相当)
                    if !pendingNew.isEmpty {
                        newNotificationPill
                            .padding(.top, NuruSpacing.space3)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
            }
        }
        .background(theme.bgPrimary.ignoresSafeArea())
        .task {
            // 初期設定読み込み
            enabledKinds = prefs.notificationEnabledKinds
            emojiReactionEnabled = prefs.notificationEmojiReactionEnabled

            await loadNotifications()

            // 10秒ポーリング開始 (Android: while(true) { delay(10_000) })
            pollingTask = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 10_000_000_000)
                    guard !Task.isCancelled else { break }
                    let fresh = await repository.fetchNotificationsWithContext(
                        pubkey: myPubkeyHex, skipCache: true
                    )
                    let existingIds = Set(notifications.map(\.id) + pendingNew.map(\.id))
                    let newItems = fresh.items.filter { !existingIds.contains($0.id) }
                    if !newItems.isEmpty {
                        await MainActor.run {
                            pendingNew = (newItems + pendingNew)
                                .reduce(into: [NotificationItem]()) { result, item in
                                    if !result.contains(where: { $0.id == item.id }) {
                                        result.append(item)
                                    }
                                }
                            // プロフィール・元投稿も更新
                            profiles.merge(fresh.profiles) { _, new in new }
                            originalPosts.merge(fresh.originalPosts) { _, new in new }
                        }
                    }
                }
            }
        }
        .onDisappear { pollingTask?.cancel() }
        .sheet(isPresented: $showKindSettings) {
            NotificationKindSettingsSheet(
                enabledKinds: $enabledKinds,
                emojiReactionEnabled: $emojiReactionEnabled,
                onSave: {
                    prefs.notificationEnabledKinds = enabledKinds
                    prefs.notificationEmojiReactionEnabled = emojiReactionEnabled
                }
            )
            .presentationDetents([.medium])
        }
    }

    // MARK: - Nav Bar

    private var sheetNavBar: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(theme.borderStrong)
                .frame(width: 36, height: 4)
                .padding(.top, NuruSpacing.space2)

            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(theme.textPrimary)
                        .frame(width: 40, height: 40)
                }
                Spacer()
                Text("通知")
                    .font(NuruFont.titleMedium())
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                // 設定ボタン (Android: Icons.Outlined.Settings)
                Button { showKindSettings = true } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 18))
                        .foregroundStyle(theme.textSecondary)
                        .frame(width: 40, height: 40)
                }
            }
            .padding(.horizontal, NuruSpacing.space4)

            Divider().background(theme.borderColor)
        }
    }

    // MARK: - Empty State (Android 空状態と同じ)

    private var emptyState: some View {
        VStack(spacing: NuruSpacing.space4) {
            ZStack {
                Circle().fill(theme.bgSecondary)
                    .frame(width: 72, height: 72)
                Image(systemName: "bell.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(theme.textTertiary)
            }
            Text("通知はまだありません")
                .font(NuruFont.bodyMedium())
                .foregroundStyle(theme.textSecondary)
            Text("リアクションや返信が届くとここに表示されます")
                .font(NuruFont.labelSmall())
                .foregroundStyle(theme.textTertiary)

            Button {
                Task {
                    isRefreshing = true
                    await loadNotifications(skipCache: true)
                    isRefreshing = false
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                    Text("更新")
                }
                .font(NuruFont.bodySmall())
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(NuruColors.lineGreen)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isRefreshing)
        }
    }

    // MARK: - New Notification Pill (Android AnimatedVisibility + Surface 相当)

    private var newNotificationPill: some View {
        Button {
            withAnimation(.spring(response: 0.3)) {
                notifications = (pendingNew + notifications)
                    .reduce(into: [NotificationItem]()) { result, item in
                        if !result.contains(where: { $0.id == item.id }) {
                            result.append(item)
                        }
                    }
                pendingNew = []
            }
        } label: {
            HStack(spacing: 8) {
                // アバタースタック (Android avatarUrls.take(3))
                let avatarUrls = pendingNew
                    .compactMap { profiles[$0.pubkey]?.picture }
                    .reduce(into: [String]()) { result, url in
                        if !result.contains(url) { result.append(url) }
                    }
                    .prefix(3)
                if !avatarUrls.isEmpty {
                    ZStack {
                        ForEach(Array(avatarUrls.enumerated()), id: \.offset) { i, urlStr in
                            if let url = URL(string: urlStr) {
                                AsyncImage(url: url) { phase in
                                    switch phase {
                                    case .success(let img):
                                        img.resizable().scaledToFill()
                                    default:
                                        Circle().fill(Color.white.opacity(0.3))
                                    }
                                }
                                .frame(width: 22, height: 22)
                                .clipShape(Circle())
                                .offset(x: CGFloat(i * 16) - CGFloat((avatarUrls.count - 1) * 8))
                            }
                        }
                    }
                    .frame(width: CGFloat(avatarUrls.count * 16 + 6), height: 22)
                }

                Image(systemName: "bell.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                Text("新着 \(pendingNew.count) 件")
                    .font(NuruFont.bodySmall())
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                Image(systemName: "chevron.up")
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, NuruSpacing.space4)
            .padding(.vertical, 10)
            .background(Capsule().fill(NuruColors.lineGreen))
            .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Notification Row

    @ViewBuilder
    private func notificationRow(_ notif: NotificationItem) -> some View {
        let style = notifStyle(for: notif.type)
        let profile = profiles[notif.pubkey]

        Button {
            onProfileTap(notif.pubkey)
        } label: {
            HStack(alignment: .top, spacing: NuruSpacing.space3) {
                // Avatar + type badge (Android: Box with avatar + BottomEnd badge)
                ZStack(alignment: .bottomTrailing) {
                    avatarView(profile: profile, size: 46)
                        .frame(width: 46, height: 46)

                    // タイプアイコンバッジ (Android: 18dp circle at BottomEnd)
                    ZStack {
                        Circle().fill(style.color)
                        if let emojiUrl = notif.emojiUrl,
                           notif.type == "reaction" || notif.type == "emoji_reaction",
                           let url = URL(string: emojiUrl) {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let img): img.resizable().scaledToFit()
                                default: EmptyView()
                                }
                            }
                            .frame(width: 13, height: 13)
                        } else {
                            Image(systemName: style.icon)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: 18, height: 18)
                    .offset(x: 2, y: 2)
                }

                // Text content
                VStack(alignment: .leading, spacing: 3) {
                    // 名前 + 相対時刻
                    HStack(spacing: 4) {
                        Text(profile?.displayedName ?? shortenPubkey(notif.pubkey))
                            .font(NuruFont.bodyMedium())
                            .fontWeight(.semibold)
                            .foregroundStyle(theme.textPrimary)
                            .lineLimit(1)
                        Spacer()
                        Text(relativeTime(notif.createdAt))
                            .font(NuruFont.labelSmall())
                            .foregroundStyle(theme.textTertiary)
                    }

                    // アクション説明 (Android NotificationRow 各タイプ分岐に対応)
                    actionView(for: notif, style: style)

                    // コメント表示
                    if let comment = notif.comment, !comment.isEmpty,
                       notif.type != "reaction" && notif.type != "emoji_reaction" {
                        Text(comment)
                            .font(NuruFont.bodySmall())
                            .foregroundStyle(
                                notif.type == "reply" || notif.type == "mention"
                                    ? theme.textPrimary.opacity(0.85)
                                    : theme.textSecondary
                            )
                            .lineLimit(notif.type == "reply" || notif.type == "mention" ? 3 : 2)
                            .padding(.top, 3)
                    }

                    // 元投稿プレビュー (Android: originalPost preview card)
                    if let targetId = notif.targetEventId,
                       let original = originalPosts[targetId],
                       ["reaction", "emoji_reaction", "repost", "zap"].contains(notif.type) {
                        let previewText = removeImageUrls(original.content)
                            .prefix(100)
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if !previewText.isEmpty {
                            HStack(spacing: 8) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(NuruColors.lineGreen)
                                    .frame(width: 3, height: 36)
                                Text(previewText)
                                    .font(NuruFont.labelSmall())
                                    .foregroundStyle(theme.textSecondary)
                                    .lineLimit(2)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(theme.bgSecondary)
                            )
                            .padding(.top, 8)
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, NuruSpacing.space4)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Action View (Android NotificationRow type 分岐)

    @ViewBuilder
    private func actionView(for notif: NotificationItem, style: NotifStyle) -> some View {
        switch notif.type {
        case "reaction", "emoji_reaction":
            HStack(spacing: 5) {
                if let emojiUrl = notif.emojiUrl, let url = URL(string: emojiUrl) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img): img.resizable().scaledToFit()
                        default: EmptyView()
                        }
                    }
                    .frame(width: 18, height: 18)
                } else {
                    let emoji: String = {
                        switch notif.reactionEmoji {
                        case "+", nil: return "👍"
                        case "-": return "👎"
                        default: return notif.reactionEmoji ?? "👍"
                        }
                    }()
                    Text(emoji).font(.system(size: 15))
                }
                Text(style.label)
                    .font(NuruFont.bodySmall())
                    .foregroundStyle(theme.textSecondary)
            }
        case "badge":
            HStack(spacing: 5) {
                Text("🏅").font(.system(size: 15))
                Text("バッジを授与されました")
                    .font(NuruFont.bodySmall())
                    .foregroundStyle(theme.textSecondary)
            }
            if let badgeName = notif.comment, !badgeName.isEmpty {
                Text(badgeName)
                    .font(NuruFont.labelSmall())
                    .foregroundStyle(theme.textTertiary)
                    .lineLimit(1)
                    .padding(.top, 2)
            }
        case "birthday":
            HStack(spacing: 5) {
                Text("🎂").font(.system(size: 15))
                Text("お誕生日おめでとうございます!")
                    .font(NuruFont.bodySmall())
                    .foregroundStyle(theme.textSecondary)
            }
        case "zap":
            HStack(spacing: 4) {
                // BIP-177: sats 単位で表示（₿ は BTC 単位なので使わない）
                Text("⚡ \(formatSats(notif.amount ?? 0)) sats")
                    .font(NuruFont.bodySmall())
                    .fontWeight(.bold)
                    .foregroundStyle(NuruColors.colorZap)
                Text("Zap")
                    .font(NuruFont.bodySmall())
                    .foregroundStyle(theme.textSecondary)
            }
        case "reply", "mention":
            Text(style.label)
                .font(NuruFont.bodySmall())
                .foregroundStyle(theme.textSecondary)
        default:
            Text(style.label)
                .font(NuruFont.bodySmall())
                .foregroundStyle(theme.textSecondary)
        }
    }

    // MARK: - Load

    private func loadNotifications(skipCache: Bool = false) async {
        isLoading = notifications.isEmpty
        let result = await repository.fetchNotificationsWithContext(
            pubkey: myPubkeyHex, skipCache: skipCache
        )
        notifications = result.items
        profiles = result.profiles
        originalPosts = result.originalPosts
        isLoading = false
    }

    // MARK: - Styles

    private struct NotifStyle {
        let icon: String; let color: Color; let bg: Color; let label: String
    }

    private func notifStyle(for type: String) -> NotifStyle {
        switch type {
        case "reaction":
            return .init(icon: "heart.fill",          color: .red,                     bg: .red.opacity(0.15),                     label: "リアクション")
        case "emoji_reaction":
            return .init(icon: "face.smiling",        color: NuruColors.colorWarning,  bg: NuruColors.colorWarning.opacity(0.15),  label: "絵文字リアクション")
        case "zap":
            return .init(icon: "bolt.fill",           color: NuruColors.colorZap,      bg: NuruColors.colorZap.opacity(0.15),      label: "Zap")
        case "repost":
            return .init(icon: "arrow.rectanglepath", color: NuruColors.lineGreen,     bg: NuruColors.lineGreen.opacity(0.15),     label: "リポスト")
        case "reply":
            return .init(icon: "arrowshape.turn.up.left.fill", color: NuruColors.lineGreen, bg: NuruColors.lineGreen.opacity(0.15), label: "返信")
        case "mention":
            return .init(icon: "at",                  color: NuruColors.colorInfo,     bg: NuruColors.colorInfo.opacity(0.15),     label: "メンション")
        case "badge":
            return .init(icon: "trophy.fill",         color: Color(red: 1, green: 0.843, blue: 0), bg: Color(red: 1, green: 0.843, blue: 0).opacity(0.15), label: "バッジ")
        case "birthday":
            return .init(icon: "birthday.cake.fill",  color: Color(red: 0.671, green: 0.278, blue: 0.737), bg: Color(red: 0.671, green: 0.278, blue: 0.737).opacity(0.15), label: "誕生日")
        default:
            return .init(icon: "bell.fill",           color: NuruColors.textTertiary,  bg: NuruColors.bgSecondary,                 label: "通知")
        }
    }

    private func actionText(for notif: NotificationItem) -> String {
        switch notif.type {
        case "reaction":       return "いいねしました"
        case "emoji_reaction": return (notif.reactionEmoji ?? "") + " でリアクションしました"
        case "zap":            return notif.amount != nil ? "\(formatSats(notif.amount!)) sats Zapしました" : "Zapしました"
        case "repost":         return "リポストしました"
        case "reply":          return "返信しました"
        case "mention":        return "メンションしました"
        case "badge":          return "バッジを授与されました"
        case "birthday":       return "お誕生日おめでとうございます!"
        default:               return "通知"
        }
    }

    /// BIP-177: millisats → sats 変換 + フォーマット。
    /// 50 sats = 50,000 msats → "50", 1,000 sats → "1K"
    private func formatSats(_ msats: Int64) -> String {
        let sats = msats / 1000
        if sats >= 1_000_000 { return "\(sats / 1_000_000)M" }
        if sats >= 1000      { return "\(sats / 1000)K" }
        return "\(sats)"
    }

    // MARK: - Avatar (Android: bgTertiary + person.fill icon)

    @ViewBuilder
    private func avatarView(profile: UserProfile?, size: CGFloat) -> some View {
        if let urlStr = profile?.picture, let url = URL(string: urlStr) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img): img.resizable().scaledToFill()
                default: avatarPlaceholder(size: size)
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
        } else {
            avatarPlaceholder(size: size)
                .frame(width: size, height: size)
        }
    }

    /// Android と同じ: Person icon + bgTertiary (元は先頭文字 + bgSecondary)
    private func avatarPlaceholder(size: CGFloat) -> some View {
        ZStack {
            Circle().fill(theme.bgTertiary)
            Image(systemName: "person.fill")
                .font(.system(size: size * 0.55))
                .foregroundStyle(theme.textTertiary)
        }
    }

    private func shortenPubkey(_ hex: String) -> String {
        guard hex.count >= 12 else { return hex }
        return String(hex.prefix(6)) + "…" + String(hex.suffix(4))
    }

    /// Android formatPostTimestamp に対応（「1時間」「2時間」「11時間」形式）。
    private func relativeTime(_ ts: Int64) -> String {
        let diff = Int64(Date().timeIntervalSince1970) - ts
        if diff < 60       { return "今" }
        if diff < 3600     { return "\(diff / 60)分" }
        if diff < 86400    { return "\(diff / 3600)時間" }
        if diff < 604800   { return "\(diff / 86400)日" }
        let fmt = DateFormatter()
        fmt.dateFormat = "M/d"
        return fmt.string(from: Date(timeIntervalSince1970: TimeInterval(ts)))
    }
}

// MARK: - NotificationKindSettingsSheet (Android AlertDialog 相当)

private struct NotificationKindSettingsSheet: View {
    @Binding var enabledKinds: Set<Int>
    @Binding var emojiReactionEnabled: Bool
    var onSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.nuruTheme) private var theme

    var body: some View {
        NavigationStack {
            List {
                kindToggle(label: "リアクション (👍)", kind: NostrKind.reaction)
                emojiToggle()
                kindToggle(label: "Zap", kind: NostrKind.zapReceipt)
                kindToggle(label: "リポスト", kind: NostrKind.repost)
                kindToggle(label: "返信・メンション", kind: NostrKind.textNote)
                kindToggle(label: "バッジ", kind: NostrKind.badgeAward)
            }
            .listStyle(.insetGrouped)
            .navigationTitle("通知の種類")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") {
                        onSave()
                        dismiss()
                    }
                    .foregroundStyle(NuruColors.lineGreen)
                }
            }
        }
    }

    @ViewBuilder
    private func kindToggle(label: String, kind: Int) -> some View {
        Toggle(label, isOn: Binding(
            get: { enabledKinds.contains(kind) },
            set: { on in
                if on { enabledKinds.insert(kind) } else { enabledKinds.remove(kind) }
            }
        ))
        .tint(NuruColors.lineGreen)
    }

    @ViewBuilder
    private func emojiToggle() -> some View {
        Toggle("絵文字リアクション", isOn: $emojiReactionEnabled)
            .tint(NuruColors.lineGreen)
    }
}
