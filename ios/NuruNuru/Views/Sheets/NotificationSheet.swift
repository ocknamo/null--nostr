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
    @State private var originalPostLoadingIds: Set<String> = []
    @State private var originalPostFailedIds: Set<String> = []
    @State private var isLoading:     Bool = true
    @State private var isRefreshing:  Bool = false
    @State private var selectedPostTarget: NotificationPostTarget? = nil
    @State private var expandedPreviewPost: NotificationPreviewPost? = nil

    // ライブポーリング + 新着Pill (Android LaunchedEffect while(true) { delay(10_000) } 相当)
    @State private var pendingNew:   [NotificationItem] = []
    @State private var pollingTask:  Task<Void, Never>?

    // 通知Kind設定 (Android showKindSettings + AlertDialog 相当)
    @State private var showKindSettings: Bool = false
    @State private var enabledKinds:     Set<Int> = []
    @State private var emojiReactionEnabled: Bool = true
    @State private var senderScope: NotificationSenderScope = .all

    var body: some View {
        VStack(spacing: 0) {
            sheetNavBar

            if isLoading {
                Spacer()
                SoftRefreshIndicator(title: "通知を読み込み中")
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
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

                    if isRefreshing {
                        SoftRefreshIndicator(title: "更新中", compact: true)
                            .padding(.top, NuruSpacing.space3)
                            .transition(.move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.96)))
                            .zIndex(2)
                    }

                    // 新着Pill (Android AnimatedVisibility + 「新着 N 件」 相当)
                    if !pendingNew.isEmpty {
                        newNotificationPill
                            .padding(.top, isRefreshing ? 62 : NuruSpacing.space3)
                            .transition(.move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.96)))
                            .zIndex(1)
                    }
                }
            }
        }
        .background(theme.bgPrimary.ignoresSafeArea())
        .task {
            // 初期設定読み込み
            enabledKinds = prefs.notificationEnabledKinds
            emojiReactionEnabled = prefs.notificationEmojiReactionEnabled
            senderScope = prefs.notificationSenderScope

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
                    let latestVisibleCreatedAt = (notifications + pendingNew).map(\.createdAt).max() ?? 0
                    // 遅れてリレーから返ってきた古い通知は「新着」として上に積まない。
                    // 新着Pill は現在表示中の最新時刻より新しいものだけに限定する。
                    let newItems = fresh.items.filter {
                        !existingIds.contains($0.id) && $0.createdAt > latestVisibleCreatedAt
                    }
                    if !newItems.isEmpty {
                        await MainActor.run {
                            pendingNew = dedupAndSortNotifications(newItems + pendingNew)
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
                senderScope: $senderScope,
                onSave: {
                    prefs.notificationEnabledKinds = enabledKinds
                    prefs.notificationEmojiReactionEnabled = emojiReactionEnabled
                    prefs.notificationSenderScope = senderScope
                    pendingNew = []
                    Task { await loadNotifications(skipCache: true) }
                }
            )
            .presentationDetents([.large])
        }
        .sheet(item: $selectedPostTarget) { target in
            NavigationStack {
                if let event = target.initialEvent {
                    // 通知から開く投稿詳細は全種別で同じ表示に統一する。
                    // `showsInlineCloseButton` はスクロール本文内に「閉じる」を置くため、
                    // 種別によって位置が下がって見える。通知では通常のナビゲーションバーの
                    // 「閉じる」に統一し、返信通知と同じ表示にする。
                    PostDetailView(
                        post: ScoredPost(event: event),
                        repository: repository,
                        myPubkeyHex: myPubkeyHex,
                        showsInlineCloseButton: false
                    )
                } else {
                    PostDetailView(
                        eventId: target.eventId,
                        repository: repository,
                        myPubkeyHex: myPubkeyHex
                    )
                }
            }
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
                notifications = dedupAndSortNotifications(pendingNew + notifications)
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
            .background(
                Capsule()
                    .fill(LinearGradient(
                        colors: [NuruColors.lineGreen, NuruColors.lineGreenDark],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
            )
            .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 1))
            .shadow(color: NuruColors.lineGreen.opacity(0.22), radius: 14, x: 0, y: 7)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Notification Row

    @ViewBuilder
    private func notificationRow(_ notif: NotificationItem) -> some View {
        let style = notifStyle(for: notif.type)
        let profile = profiles[notif.pubkey]

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
                        } else if notif.type == "repost" {
                            RepostIcon()
                                .frame(width: 12, height: 12)
                                .foregroundStyle(.white)
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
                        Text(wrapLongNotificationText(profile?.displayedName ?? shortenPubkey(notif.pubkey), chunkSize: 14))
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

                    // コメント表示（nostr参照・URL・カスタム絵文字を読み込んで表示）
                    if let commentEvent = notificationCommentEvent(for: notif),
                       notif.type != "reaction" && notif.type != "emoji_reaction" {
                        NotificationContentPreview(
                            event: commentEvent,
                            repository: repository,
                            onProfileTap: onProfileTap,
                            onPostTap: { eventId in selectedPostTarget = NotificationPostTarget(eventId: eventId, initialEvent: originalPosts[eventId]) },
                            compact: true
                        )
                        .padding(.top, 3)
                    }

                    // 元投稿プレビュー (Android: originalPost preview card)
                    if let targetId = notif.targetEventId,
                       ["reaction", "emoji_reaction", "repost", "zap", "quote"].contains(notif.type) {
                        if let original = originalPosts[targetId] {
                            NotificationOriginalPostPreview(
                                event: original,
                                repository: repository,
                                onProfileTap: onProfileTap,
                                onPostTap: { eventId in selectedPostTarget = NotificationPostTarget(eventId: eventId, initialEvent: originalPosts[eventId]) },
                                onOpen: { selectedPostTarget = NotificationPostTarget(eventId: targetId, initialEvent: original) }
                            )
                            .padding(.top, 8)
                        } else {
                            NotificationOriginalPostPlaceholder(
                                isLoading: originalPostLoadingIds.contains(targetId),
                                didFail: originalPostFailedIds.contains(targetId),
                                onRetry: { Task { await loadOriginalPostIfNeeded(targetId, force: true) } }
                            )
                            .padding(.top, 8)
                            .task(id: targetId) { await loadOriginalPostIfNeeded(targetId) }
                        }
                    }
                }

                Spacer(minLength: 0)
        }
        .padding(.horizontal, NuruSpacing.space4)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            openNotificationTarget(notif)
        }
    }

    private func openNotificationTarget(_ notif: NotificationItem) {
        if let eventId = postTargetEventId(for: notif) {
            selectedPostTarget = NotificationPostTarget(
                eventId: eventId,
                initialEvent: originalPosts[eventId]
            )
        } else {
            onProfileTap(notif.pubkey)
        }
    }

    @MainActor
    private func loadOriginalPostIfNeeded(_ eventId: String, force: Bool = false) async {
        if originalPosts[eventId] != nil { return }
        if originalPostLoadingIds.contains(eventId) { return }
        if originalPostFailedIds.contains(eventId) && !force { return }

        originalPostLoadingIds.insert(eventId)
        if force { originalPostFailedIds.remove(eventId) }

        let event = await repository.fetchEvent(eventId: eventId)
        if let event {
            originalPosts[eventId] = event
            originalPostFailedIds.remove(eventId)
        } else {
            originalPostFailedIds.insert(eventId)
        }
        originalPostLoadingIds.remove(eventId)
    }

    private func postTargetEventId(for notif: NotificationItem) -> String? {
        switch notif.type {
        case "reply", "mention", "quote":
            // 返信・メンション・引用は「通知を発生させた投稿」へ遷移する。
            return notif.id
        case "reaction", "emoji_reaction", "repost", "zap":
            // リアクション等は対象元投稿へ遷移する。
            return notif.targetEventId
        default:
            return notif.targetEventId
        }
    }

    private func notificationCommentEvent(for notif: NotificationItem) -> NostrEvent? {
        guard let comment = notif.comment, !comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return NostrEvent(id: notif.id + "_comment", pubkey: notif.pubkey, createdAt: notif.createdAt, kind: NostrKind.textNote, tags: [], content: comment, sig: "")
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
        case "reply", "mention", "quote", "follow":
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


    private func dedupAndSortNotifications(_ items: [NotificationItem]) -> [NotificationItem] {
        items.reduce(into: [NotificationItem]()) { result, item in
            if !result.contains(where: { $0.id == item.id }) {
                result.append(item)
            }
        }
        .sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt { return lhs.id > rhs.id }
            return lhs.createdAt > rhs.createdAt
        }
    }

    private func loadNotifications(skipCache: Bool = false) async {
        isLoading = notifications.isEmpty
        let result = await repository.fetchNotificationsWithContext(
            pubkey: myPubkeyHex, skipCache: skipCache
        )
        notifications = dedupAndSortNotifications(result.items)
        profiles = result.profiles
        originalPosts = result.originalPosts
        originalPostFailedIds.subtract(result.originalPosts.keys)
        originalPostLoadingIds = []
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
        case "quote":
            return .init(icon: "quote.opening",       color: NuruColors.lineGreen,     bg: NuruColors.lineGreen.opacity(0.15),     label: "引用")
        case "follow":
            return .init(icon: "person.crop.circle.badge.plus", color: NuruColors.lineGreen, bg: NuruColors.lineGreen.opacity(0.15), label: "フォローしました")
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
        case "quote":          return "引用しました"
        case "follow":         return "フォローしました"
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

private struct NotificationPostTarget: Identifiable {
    let eventId: String
    let initialEvent: NostrEvent?
    var id: String { eventId }

    init(eventId: String, initialEvent: NostrEvent? = nil) {
        self.eventId = eventId
        self.initialEvent = initialEvent
    }
}


private struct NotificationPreviewPost: Identifiable { let event: NostrEvent; var id: String { event.id } }

private struct NotificationOriginalPostPreview: View {
    let event: NostrEvent
    let repository: NostrRepository
    var onProfileTap: (String) -> Void
    var onPostTap: (String) -> Void
    var onOpen: () -> Void

    @Environment(\.nuruTheme) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(NuruColors.lineGreen)
                .frame(width: 3)
            NotificationContentPreview(
                event: event,
                repository: repository,
                onProfileTap: onProfileTap,
                onPostTap: onPostTap,
                compact: true
            )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(theme.bgSecondary))
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture { onOpen() }
    }
}

private struct NotificationOriginalPostPlaceholder: View {
    let isLoading: Bool
    let didFail: Bool
    var onRetry: () -> Void

    @Environment(\.nuruTheme) private var theme

    var body: some View {
        Button(action: onRetry) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(NuruColors.lineGreen.opacity(0.65))
                    .frame(width: 3)
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.65)
                        .tint(NuruColors.lineGreen)
                    Text("投稿を読み込み中…")
                } else if didFail {
                    Image(systemName: "arrow.clockwise")
                    Text("投稿を再取得")
                } else {
                    ProgressView()
                        .scaleEffect(0.65)
                        .tint(NuruColors.lineGreen)
                    Text("投稿を準備中…")
                }
                Spacer(minLength: 0)
            }
            .font(NuruFont.labelSmall())
            .foregroundStyle(theme.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(theme.bgSecondary))
        }
        .buttonStyle(.plain)
    }
}

private struct NotificationContentPreview: View {
    let event: NostrEvent; let repository: NostrRepository; var onProfileTap: (String) -> Void; var onPostTap: (String) -> Void; var compact: Bool = true
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            NotificationRichText(event: event, repository: repository, onProfileTap: onProfileTap, onPostTap: onPostTap, compact: compact)
            if !compact {
                let images = notificationImageUrls(for: event)
                if !images.isEmpty { PostImageGrid(images: images, authorPubkey: event.pubkey).frame(maxHeight: .infinity).clipped() }
                if let video = notificationVideoUrl(in: event.content) { VideoPlayer(videoUrl: video).frame(height: 220).clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusMd)) }
            } else {
                NotificationMediaSummary(event: event)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct NotificationMediaSummary: View {
    let event: NostrEvent
    @Environment(\.nuruTheme) private var theme

    var body: some View {
        let imageCount = notificationImageUrls(for: event).count
        let hasVideo = notificationVideoUrl(in: event.content) != nil
        let hasReference = parseNotificationContent(event.content, emojiTags: event.tags).contains { part in
            if case .nostr = part { return true }
            return false
        }
        if imageCount > 0 || hasVideo || hasReference {
            HStack(spacing: 6) {
                if imageCount > 0 { chip(icon: "photo", text: imageCount == 1 ? "画像" : "画像 \(imageCount)枚") }
                if hasVideo { chip(icon: "play.rectangle", text: "動画") }
                if hasReference { chip(icon: "link", text: "参照") }
            }
        }
    }

    private func chip(icon: String, text: String) -> some View {
        Label(text, systemImage: icon)
            .font(NuruFont.labelSmall())
            .foregroundStyle(theme.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(theme.bgTertiary.opacity(0.8)))
    }
}

private struct NotificationRichText: View {
    let event: NostrEvent; let repository: NostrRepository; var onProfileTap: (String) -> Void; var onPostTap: (String) -> Void; var compact: Bool
    @Environment(\.nuruTheme) private var theme
    @State private var mentionLabels: [String: String] = [:]
    private var parts: [NotificationContentPart] { parseNotificationContent(event.content, emojiTags: event.tags) }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if compact {
                Text(notificationCompactText(parts: parts))
                    .font(NuruFont.bodySmall())
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                WrappingHStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(parts.enumerated()), id: \.offset) { _, part in partView(part) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                    if case .nostr(let link) = part {
                        NotificationNostrReferenceCard(link: link, repository: repository, onProfileTap: onProfileTap, onPostTap: onPostTap)
                    }
                }
            }
        }.task(id: event.id) { if !compact { await resolveMentions() } }
    }
    @ViewBuilder private func partView(_ part: NotificationContentPart) -> some View {
        switch part {
        case .plain(let text): Text(wrapLongNotificationText(text)).font(NuruFont.labelSmall()).foregroundStyle(theme.textSecondary)
        case .link(let url): Text(shortUrl(url)).font(NuruFont.labelSmall()).foregroundStyle(NuruColors.lineGreen)
        case .mention(let bech32): Text(mentionLabels[bech32] ?? "@" + String(bech32.prefix(12)) + "…").font(NuruFont.labelSmall()).foregroundStyle(NuruColors.lineGreen).onTapGesture { if let parsed = NostrBech32.decode(bech32) { onProfileTap(parsed.hex) } }
        case .nostr: EmptyView()
        case .emoji(let code, let url): if !compact, let url, let imageUrl = URL(string: url) { CachedAsyncImage(url: imageUrl) { Color.clear.frame(width: 18, height: 18) }.frame(width: 18, height: 18).clipShape(RoundedRectangle(cornerRadius: 2)).padding(.horizontal, 1) } else { Text(code).font(NuruFont.labelSmall()).foregroundStyle(theme.textSecondary) }
        }
    }
    private func resolveMentions() async { var updated = mentionLabels; for part in parts { guard case .mention(let bech32) = part, updated[bech32] == nil, let parsed = NostrBech32.decode(bech32) else { continue }; if let profile = await repository.fetchProfile(pubkey: parsed.hex) { updated[bech32] = "@\(profile.displayedName)" } }; mentionLabels = updated }
}

private struct NotificationNostrReferenceCard: View {
    let link: String; let repository: NostrRepository; var onProfileTap: (String) -> Void; var onPostTap: (String) -> Void
    @Environment(\.nuruTheme) private var theme
    @State private var event: NostrEvent?; @State private var profile: UserProfile?; @State private var loading = true
    var body: some View { Group { if let event { Button { onPostTap(event.id) } label: { VStack(alignment: .leading, spacing: 4) { Text(profile?.displayedName ?? event.pubkey.shortenedPubkey).font(NuruFont.labelSmall()).fontWeight(.semibold).foregroundStyle(theme.textPrimary).lineLimit(1); NotificationContentPreview(event: event, repository: repository, onProfileTap: onProfileTap, onPostTap: onPostTap, compact: true) }.padding(8).background(RoundedRectangle(cornerRadius: 10).fill(theme.bgTertiary.opacity(0.35))).overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.borderColor.opacity(0.45), lineWidth: 0.5)) }.buttonStyle(.plain) } else if let profile { Button { onProfileTap(profile.pubkey) } label: { HStack(spacing: 8) { AvatarView(url: profile.picture, name: profile.displayedName, size: 24); Text(profile.displayedName).font(NuruFont.labelSmall()).fontWeight(.semibold).foregroundStyle(theme.textPrimary).lineLimit(1) }.padding(8).background(RoundedRectangle(cornerRadius: 10).fill(theme.bgTertiary.opacity(0.35))) }.buttonStyle(.plain) } else if loading { ProgressView().scaleEffect(0.6) } }.task(id: link) { await load() } }
    private func load() async { loading = true; let bech32 = normalizedNostrBech32(link); if let parsed = NostrBech32.decode(bech32) { switch parsed.type { case .note, .nevent: event = await repository.fetchEvent(eventId: parsed.hex); if let event { profile = await repository.fetchProfile(pubkey: event.pubkey) }; case .npub, .nprofile: if let p = await repository.fetchProfile(pubkey: parsed.hex) { profile = p } } } else if bech32.hasPrefix("naddr1"), let a = NostrBech32.decodeNaddrToA(bech32) { event = await repository.fetchAddressableEvent(aTag: a); if let event { profile = await repository.fetchProfile(pubkey: event.pubkey) } }; loading = false }
}

private struct NotificationPreviewDetailView: View {
    let event: NostrEvent
    let repository: NostrRepository
    var onDismiss: () -> Void
    var onProfileTap: (String) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                PostRow(
                    post: ScoredPost(event: event),
                    repository: repository,
                    onProfileTap: onProfileTap
                )
            }
            .navigationTitle("投稿")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("閉じる") { onDismiss() } } }
        }
    }
}

private enum NotificationContentPart { case plain(String), link(String), nostr(String), mention(String), emoji(String, String?) }
private func notificationCompactText(parts: [NotificationContentPart]) -> String {
    var out = ""
    for part in parts {
        switch part {
        case .plain(let text):
            out += text
        case .link(let url):
            out += shortUrl(url)
        case .mention(let bech32):
            out += "@" + String(bech32.prefix(12)) + "…"
        case .nostr:
            // 参照は NotificationMediaSummary の「参照」チップで示す。本文には長い bech32 を出さない。
            if !out.hasSuffix(" ") && !out.isEmpty { out += " " }
        case .emoji(let code, _):
            out += code
        }
    }
    let normalized = out.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return wrapLongNotificationText(normalized.isEmpty ? " " : normalized, chunkSize: 14)
}
private func parseNotificationContent(_ text: String, emojiTags: [[String]]) -> [NotificationContentPart] {
    let emojiMap: [String: String] = emojiTags.filter { $0.first == "emoji" && $0.count >= 3 }.reduce(into: [:]) { $0[$1[1]] = $1[2] }
    let pattern = #"(nostr:(?:note1|nevent1|npub1|nprofile1|naddr1)[a-z0-9]+|(?<!nostr:)(?:note1|nevent1)[a-z0-9]+|https?://[^\s]+|#[\p{L}\p{N}_]+|:[A-Za-z0-9_+\-]+:)"#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [.plain(text)] }
    let ns = text as NSString; let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length)); var parts: [NotificationContentPart] = []; var last = 0
    for m in matches { if m.range.location > last { parts.append(.plain(ns.substring(with: NSRange(location: last, length: m.range.location - last)))) }; let value = ns.substring(with: m.range); if value.hasPrefix("http") { if !notificationIsMediaUrl(value) { parts.append(.link(value)) } } else if value.hasPrefix("#") { parts.append(.plain(value)) } else if value.hasPrefix(":") { let code = String(value.dropFirst().dropLast()); parts.append(.emoji(value, emojiMap[code])) } else { let b = normalizedNostrBech32(value); if b.hasPrefix("npub1") || b.hasPrefix("nprofile1") { parts.append(.mention(b)) } else { parts.append(.nostr(value)) } }; last = m.range.location + m.range.length }
    if last < ns.length { parts.append(.plain(ns.substring(from: last))) }
    return parts.filter { if case .plain(let s) = $0 { return !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }; return true }
}
private func normalizedNostrBech32(_ raw: String) -> String { raw.hasPrefix("nostr:") ? String(raw.dropFirst("nostr:".count)) : raw }
private func notificationImageUrls(for event: NostrEvent) -> [String] { var seen = Set<String>(); var out: [String] = []; for u in extractPostImages(event.content) + event.extractImetaUrls() { let t = u.trimmingCharacters(in: .whitespacesAndNewlines); if seen.insert(t).inserted { out.append(t) } }; return out }
private func notificationVideoUrl(in content: String) -> String? { let ns = content as NSString; guard let regex = try? NSRegularExpression(pattern: #"https?://[^\s]+\.(?:mp4|mov|webm|m3u8)(?:\?[^\s]*)?"#, options: [.caseInsensitive]), let m = regex.firstMatch(in: content, range: NSRange(location: 0, length: ns.length)) else { return nil }; return ns.substring(with: m.range) }
private func notificationIsMediaUrl(_ url: String) -> Bool { if notificationVideoUrl(in: url) != nil { return true }; return !extractPostImages(url).isEmpty }
private func shortUrl(_ url: String) -> String { url.count > 40 ? String(url.prefix(40)) + "…" : url }

// MARK: - NotificationKindSettingsSheet (Android AlertDialog 相当)

private struct NotificationKindSettingsSheet: View {
    @Binding var enabledKinds: Set<Int>
    @Binding var emojiReactionEnabled: Bool
    @Binding var senderScope: NotificationSenderScope
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
                kindToggle(label: "フォロー", kind: NostrKind.contactList)
                kindToggle(label: "バッジ", kind: NostrKind.badgeAward)

                Section("表示する送信者") {
                    Picker("範囲", selection: $senderScope) {
                        ForEach(NotificationSenderScope.allCases) { scope in
                            Text(scope.label).tag(scope)
                        }
                    }
                    .pickerStyle(.inline)

                    Text(senderScope.description)
                        .font(NuruFont.labelSmall())
                        .foregroundStyle(theme.textSecondary)
                }
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

private func wrapLongNotificationText(_ text: String, chunkSize: Int = 18) -> String {
    text.split(separator: " ", omittingEmptySubsequences: false).map { tokenSub in
        let token = String(tokenSub)
        guard token.count > chunkSize else { return token }
        var out = ""
        for (idx, ch) in token.enumerated() {
            if idx > 0 && idx % chunkSize == 0 { out.append("\u{200B}") }
            out.append(ch)
        }
        return out
    }.joined(separator: " ")
}
