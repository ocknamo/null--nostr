import SwiftUI

/// Single post row — avatar · header · content · actions.
/// Mirrors Android PostItem.kt layout.
struct PostRow: View {

    let post:          ScoredPost
    var repository:    NostrRepository?              = nil
    var myPubkeyHex:   String                        = ""     // 引用リポストシートで使用
    var myProfile:     UserProfile?                  = nil    // 引用リポストシートで使用
    var onLike:        () async -> Void              = {}
    var onLikeLongPress: (() -> Void)?               = nil
    var onRepost:      () async -> Void              = {}
    var onZap:         (() -> Void)?                 = nil
    var onZapLongPress: (() -> Void)?                = nil
    var onBookmark:    (() async -> Void)?           = nil
    var onProfileTap:  (String) -> Void              = { _ in }
    var onDelete:      (() -> Void)?                 = nil
    var onMute:        (() -> Void)?                 = nil
    var onReport:      ((String, String) -> Void)?   = nil
    var onBirdwatch:   ((String, String, String) -> Void)? = nil
    var onNotInterested: (() -> Void)?               = nil
    var birdwatchNotes: [NostrEvent]                 = []
    /// ElevenLabs APIキー — 設定済みの場合のみ読み上げボタンを表示。
    var elevenLabsApiKey: String                     = ""

    @Environment(\.nuruTheme) private var theme
    @State private var isExpanded              = false
    @State private var isCWExpanded            = false
    @State private var showBirdwatch           = false
    @State private var showReport              = false
    @State private var showReactionPicker      = false
    @State private var showQuoteSheet          = false
    @State private var showPostDetail          = false
    @State private var quotedDetailTarget: ScoredPost? = nil
    /// 遅延ロードした Birdwatch ノート（repository 経由）。
    @State private var fetchedBirdwatchNotes: [NostrEvent] = []
    /// ElevenLabs TTS 再生中フラグ。
    @State private var isSpeaking              = false

    private var cwReason: String? { post.event.getTagValue("content-warning") }

    /// 外部から渡された notes を優先し、なければ遅延ロード済みを使用。
    private var effectiveBirdwatchNotes: [NostrEvent] {
        birdwatchNotes.isEmpty ? fetchedBirdwatchNotes : birdwatchNotes
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PostIndicators(post: post, onProfileTap: onProfileTap, repository: repository)

            HStack(alignment: .top, spacing: 10) {
                AvatarView(
                    url:  post.profile?.picture,
                    name: post.profile?.displayedName ?? "?",
                    size: 42   // mirrors Android PostItem 42dp
                )
                .onTapGesture { onProfileTap(post.event.pubkey) }

                VStack(alignment: .leading, spacing: NuruSpacing.space2) {
                    PostHeader(
                        post:         post,
                        isOwnPost:    onDelete != nil,
                        onProfileTap: onProfileTap,
                        repository:   repository,
                        onDelete:     onDelete,
                        onMute:       onMute,
                        onReport:     onReport != nil ? { showReport = true } : nil,
                        onBirdwatch:  (onBirdwatch != nil || repository != nil) ? { showBirdwatch = true } : nil,
                        onNotInterested: onNotInterested
                    )
                    contentView

                    if !effectiveBirdwatchNotes.isEmpty {
                        BirdwatchDisplay(
                            notes:         effectiveBirdwatchNotes,
                            onAuthorClick: onProfileTap
                        )
                        .padding(.top, NuruSpacing.space1)
                    }

                    // PostActions + TTS ボタン
                    HStack(alignment: .center, spacing: 0) {
                        PostActions(
                            post:              post,
                            onLike:            onLike,
                            onLikeLongPress:   onLikeLongPress ?? ((onBirdwatch != nil || repository != nil) ? { showReactionPicker = true } : nil),
                            onRepost:          onRepost,
                            onRepostLongPress: repository != nil ? { showQuoteSheet = true } : nil,
                            onZap:             onZap,
                            onZapLongPress:    onZapLongPress,
                            onBookmark:        onBookmark
                        )
                        // ElevenLabs TTS 読み上げボタン（APIキー設定済み時のみ）
                        if !elevenLabsApiKey.isEmpty {
                            Spacer()
                            Button {
                                if isSpeaking {
                                    ElevenLabsTTSService.shared.stop()
                                    isSpeaking = false
                                } else {
                                    isSpeaking = true
                                    Task {
                                        try? await ElevenLabsTTSService.shared.speak(
                                            text:   post.event.content,
                                            apiKey: elevenLabsApiKey
                                        )
                                        isSpeaking = false
                                    }
                                }
                            } label: {
                                Image(systemName: isSpeaking ? "speaker.wave.3.fill" : "speaker.wave.2")
                                    .font(.system(size: 15))
                                    .foregroundStyle(isSpeaking ? NuruColors.lineGreen : theme.textTertiary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, NuruSpacing.space1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, NuruSpacing.space4)
            .padding(.top, NuruSpacing.space2)
            .padding(.bottom, NuruSpacing.space3)

            Divider().background(theme.borderColor)
        }
        .background(theme.bgPrimary)
        .contentShape(Rectangle())
        .onLongPressGesture {
            guard repository != nil else { return }
            showPostDetail = true
        }
        // プロフィール未取得時の遅延再取得（Android PostItem LaunchedEffect 同等）
        // ScoredPost は @Observable class なので post.profile 変更で自動再描画
        .task(id: post.event.id) {
            if (post.profile?.picture?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false)
                || (post.profile?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
                    && post.profile?.name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false),
               let repo = repository {
                // キャッシュチェック → リレー取得（Android と同じ 2 段階フォールバック）
                if let cached = repo.getCachedProfile(pubkey: post.event.pubkey),
                   cached.picture?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                    || cached.displayName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                    || cached.name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                    post.profile = cached
                } else {
                    let profiles = await repo.fetchProfiles(pubkeys: [post.event.pubkey])
                    if let fetched = profiles.first,
                       fetched.picture?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                        || fetched.displayName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                        || fetched.name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                        post.profile = fetched
                    }
                }
            }
        }
        // Birdwatch ノートの遅延ロード（repository が存在し外部から notes が渡されない場合のみ）
        .task(id: post.event.id) {
            guard let repo = repository, birdwatchNotes.isEmpty else { return }
            let result = await repo.fetchBirdwatchNotes(eventIds: [post.event.id])
            fetchedBirdwatchNotes = result[post.event.id] ?? []
        }
        .sheet(isPresented: $showBirdwatch) {
            BirdwatchModal(
                onDismiss: { showBirdwatch = false },
                onSubmit: { type, content, url in
                    showBirdwatch = false
                    // repository が利用可能なら直接パブリッシュ
                    if let repo = repository {
                        Task {
                            try? await repo.publishBirdwatchNote(
                                targetEventId: post.event.id,
                                content:       content,
                                contextType:   type,
                                sourceUrl:     url.isEmpty ? nil : url
                            )
                            // パブリッシュ後にノートを再取得
                            let result = await repo.fetchBirdwatchNotes(eventIds: [post.event.id])
                            fetchedBirdwatchNotes = result[post.event.id] ?? []
                        }
                    }
                    onBirdwatch?(type, content, url)
                },
                existingNotes: effectiveBirdwatchNotes
            )
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showReport) {
            if let reportHandler = onReport {
                ReportSheet(
                    onReport:  { type, content in
                        showReport = false
                        reportHandler(type, content)
                    },
                    onDismiss: { showReport = false }
                )
                .presentationDetents([.medium])
            }
        }
        .sheet(isPresented: $showReactionPicker) {
            if let repo = repository {
                ReactionEmojiPicker(
                    pubkeyHex: myPubkeyHex,
                    repository: repo,
                    onSelect: { selection in
                        showReactionPicker = false
                        // カスタム絵文字リアクションを送信
                        Task {
                            switch selection.kind {
                            case .custom:
                                try? await repo.publishReaction(
                                    to: post.event.id,
                                    authorPubkey: post.event.pubkey,
                                    content: ":\(selection.shortcode):",
                                    emojiUrl: selection.url
                                )
                            case .unicode:
                                try? await repo.publishReaction(
                                    to: post.event.id,
                                    authorPubkey: post.event.pubkey,
                                    content: selection.emoji
                                )
                            }
                            post.isLiked = true
                            post.likeCount += 1
                        }
                    },
                    onDismiss: { showReactionPicker = false }
                )
                .presentationDetents([.medium, .large])
            } else {
                ReactionEmojiPickerSheet(
                    onSelect: { _ in showReactionPicker = false },
                    onDismiss: { showReactionPicker = false }
                )
                .presentationDetents([.medium, .large])
            }
        }
        // 引用リポストシート — リポストボタン長押しで表示
        .sheet(isPresented: $showQuoteSheet) {
            if let repo = repository {
                QuoteRepostSheet(
                    post:        post,
                    repository:  repo,
                    myPubkeyHex: myPubkeyHex,
                    myProfile:   myProfile,
                    onDismiss:   { showQuoteSheet = false },
                    onSuccess:   { showQuoteSheet = false }
                )
                .presentationDetents([.large])
            }
        }
        .sheet(item: $quotedDetailTarget) { quoted in
            if let repo = repository {
                PostDetailView(
                    post: quoted,
                    repository: repo,
                    myPubkeyHex: myPubkeyHex,
                    showsInlineCloseButton: true
                )
            }
        }
        .sheet(isPresented: $showPostDetail) {
            if let repo = repository {
                PostDetailView(
                    post: post,
                    repository: repo,
                    myPubkeyHex: myPubkeyHex,
                    showsInlineCloseButton: true
                )
            }
        }
    }

    // MARK: - Content

    private var contentView: some View {
        if let cw = cwReason, !isCWExpanded {
            return AnyView(cwOverlay(reason: cw))
        }
        return AnyView(expandableContent)
    }

    private var expandableContent: some View {
        let full     = post.event.content
        let collapse = !isExpanded && textLengthWithoutLinks(full) > UI.postMaxLength

        return VStack(alignment: .leading, spacing: NuruSpacing.space2) {
            // CW re-hide label when expanded
            if cwReason != nil {
                Button { isCWExpanded = false } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                        Text("隠す")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(Color(red: 0.98, green: 0.67, blue: 0.0))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color(red: 0.98, green: 0.67, blue: 0.0).opacity(0.12))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            // テキスト表示: 折り畳み時は truncated ScoredPost を渡す
            if collapse {
                PostContentView(
                    post: post.truncated(to: UI.postMaxLength),
                    repository: repository,
                    onProfileTap: onProfileTap,
                    quotedPostEventId: post.quotedPost?.event.id
                )
            } else {
                PostContentView(
                    post: post,
                    repository: repository,
                    onProfileTap: onProfileTap,
                    quotedPostEventId: post.quotedPost?.event.id
                )
            }

            // 画像グリッド — Android PostMedia に対応
            PostMedia(post: post)

            // 引用投稿プレビュー: enrichPosts でデータが揃えば全カード、未取得なら引用元インジケーター
            if let quoted = post.quotedPost {
                QuotedPostPreview(post: quoted, onProfileTap: onProfileTap)
                    .padding(.top, NuruSpacing.space2)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        quotedDetailTarget = quoted
                    }
            } else if isQuotePost {
                quotedPostIndicator
                    .padding(.top, NuruSpacing.space2)
            }

            if collapse {
                Button("もっと見る") { isExpanded = true }
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(NuruColors.lineGreen)
                    .padding(.vertical, 4)
                    .buttonStyle(.plain)
            } else if textLengthWithoutLinks(post.event.content) > UI.postMaxLength {
                Button("閉じる") { isExpanded = false }
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(NuruColors.lineGreen)
                    .padding(.vertical, 4)
                    .buttonStyle(.plain)
            }
        }
    }

    private func cwOverlay(reason: String) -> some View {
        let amber = Color(red: 0.98, green: 0.67, blue: 0.0)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(amber)
                VStack(alignment: .leading, spacing: 2) {
                    Text("センシティブな内容")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(amber)
                    if !reason.isEmpty {
                        Text(reason)
                            .font(.system(size: 11))
                            .foregroundStyle(theme.textSecondary)
                    }
                }
            }
            Button { isCWExpanded = true } label: {
                Text("表示する")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(amber)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(NuruSpacing.space3)
        .background(amber.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusMd))
        .overlay(RoundedRectangle(cornerRadius: NuruSpacing.radiusMd).stroke(amber.opacity(0.3), lineWidth: 1))
    }

    // MARK: - 引用投稿 検出 & プレビュー

    /// "q" タグまたは content 内の nostr:note1... パターンで引用投稿を検出する。
    private var isQuotePost: Bool {
        post.event.getTagValue("q") != nil
        || post.event.content.range(
            of: #"nostr:note1[a-z0-9]{58,}"#,
            options: .regularExpression
        ) != nil
    }

    /// quotedPost が未取得の場合に表示するミニマルな引用元インジケーター。
    private var quotedPostIndicator: some View {
        HStack(spacing: 6) {
            Image(systemName: "quote.opening")
                .font(.system(size: 11))
                .foregroundStyle(theme.textTertiary)
            Text("引用元の投稿")
                .font(NuruFont.bodySmall())
                .foregroundStyle(theme.textTertiary)
        }
        .padding(.horizontal, NuruSpacing.space3)
        .padding(.vertical, NuruSpacing.space2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.bgTertiary)
        .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusSm))
        .overlay(
            RoundedRectangle(cornerRadius: NuruSpacing.radiusSm)
                .stroke(theme.borderColor.opacity(0.4), lineWidth: 0.5)
        )
    }

    // MARK: - Helpers

    private func textLengthWithoutLinks(_ text: String) -> Int {
        text.replacingOccurrences(of: #"https?://\S+"#, with: "", options: .regularExpression).count
    }
}

// MARK: - 引用投稿プレビューカード

/// 引用元投稿の全プレビューカード。ScoredPost.quotedPost が設定された場合に表示。
/// Mirrors Android EmbeddedNostrContent composable。
private struct QuotedPostPreview: View {
    let post:         ScoredPost
    let onProfileTap: (String) -> Void

    @Environment(\.nuruTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: NuruSpacing.space2) {
            // 著者行
            HStack(spacing: 6) {
                AvatarView(
                    url:  post.profile?.picture,
                    name: post.profile?.displayedName ?? "?",
                    size: 20
                )
                Text(post.profile?.displayedName ?? post.event.pubkey.shortenedPubkey)
                    .font(NuruFont.bodySmall())
                    .fontWeight(.semibold)
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
            .onTapGesture { onProfileTap(post.event.pubkey) }

            // 本文（最大3行）
            Text(removeImageUrls(post.event.content))
                .font(NuruFont.bodySmall())
                .foregroundStyle(theme.textSecondary)
                .lineLimit(3)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(NuruSpacing.space3)
        .background(theme.bgTertiary)
        .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusMd))
        .overlay(
            RoundedRectangle(cornerRadius: NuruSpacing.radiusMd)
                .stroke(theme.borderColor.opacity(0.5), lineWidth: 0.5)
        )
    }
}

// MARK: - Reaction Emoji Picker Sheet wrapper

private struct ReactionEmojiPickerSheet: View {
    let onSelect:  (ReactionSelection) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 36, height: 4)
                .padding(.top, 8)
            Text("リアクション")
                .font(NuruFont.titleMedium())
                .fontWeight(.bold)
                .padding(.vertical, 12)
            Divider()
            // Full emoji picker requires repository — simplified version shows standard reactions
            HStack(spacing: NuruSpacing.space4) {
                ForEach(["👍", "❤️", "🔥", "😂", "😢", "😮"], id: \.self) { emoji in
                    Button {
                        onSelect(ReactionSelection.unicode(emoji))
                        onDismiss()
                    } label: {
                        Text(emoji).font(.system(size: 32))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, NuruSpacing.space4)
            Spacer()
        }
    }
}
