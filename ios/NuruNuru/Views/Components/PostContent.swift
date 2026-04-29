import SwiftUI

// MARK: - Post Indicators (repost / reply banner)

/// Shows a repost or reply banner above the post body.
/// Mirrors Android PostIndicators composable.
struct PostIndicators: View {
    let post: ScoredPost
    let onProfileTap: (String) -> Void
    var repository: NostrRepository? = nil

    @Environment(\.nuruTheme) private var theme
    @State private var replyUserName: String? = nil
    @State private var repostUserName: String? = nil

    var body: some View {
        if let repostedBy = post.repostedBy {
            // Repost banner
            HStack(spacing: 4) {
                RepostIcon()
                    .frame(width: 12, height: 12)
                    .foregroundStyle(theme.textTertiary)
                Text("\(repostUserName ?? repostedBy.displayedName) がリポスト")
                    .font(NuruFont.labelSmall())
                    .foregroundStyle(theme.textTertiary)
                    .lineLimit(1)
            }
            .padding(.leading, 48 + NuruSpacing.space4) // align with content column
            .padding(.top, NuruSpacing.space2)
            .contentShape(Rectangle())
            .onTapGesture { onProfileTap(repostedBy.pubkey) }
            .task(id: repostedBy.pubkey) {
                guard let repo = repository else { return }

                // まずキャッシュ反映（hex短縮名なら未解決扱い）
                if let cached = repo.getCachedProfile(pubkey: repostedBy.pubkey) {
                    let name = cached.displayedName
                    if !name.hasSuffix("...") {
                        repostUserName = name
                        post.repostedBy = cached
                        return
                    }
                }

                // 未解決なら必ず単体取得
                if let fetched = await repo.fetchProfile(pubkey: repostedBy.pubkey) {
                    let name = fetched.displayedName
                    repostUserName = name
                    post.repostedBy = fetched
                }
            }
        } else if isReplyEvent(post.event) {
            // Reply banner — only show for actual replies (has "reply" marker or root "e" + "p" tag)
            let replyPubkey = post.event.getTagValue("p")
            HStack(spacing: 4) {
                Image(systemName: NuruIcons.talk(filled: false))
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textTertiary)
                if let rp = replyPubkey {
                    Text("@\(replyUserName ?? rp.shortenedPubkey)")
                        .font(NuruFont.labelSmall())
                        .foregroundStyle(NuruColors.lineGreen)
                    + Text(" への返信")
                        .font(NuruFont.labelSmall())
                        .foregroundStyle(theme.textTertiary)
                } else {
                    Text("返信")
                        .font(NuruFont.labelSmall())
                        .foregroundStyle(theme.textTertiary)
                }
            }
            .padding(.leading, 48 + NuruSpacing.space4)
            .padding(.top, NuruSpacing.space2)
            .contentShape(Rectangle())
            .onTapGesture {
                if let rp = replyPubkey { onProfileTap(rp) }
            }
            .task(id: replyPubkey) {
                // 返信先のユーザー名を解決する（Android: repository.getCachedProfile() に対応）
                guard let rp = replyPubkey, let repo = repository else { return }
                if let profile = await repo.fetchProfile(pubkey: rp) {
                    replyUserName = profile.displayedName
                }
            }
        }
    }
}

/// Determine if an event is a reply (not just a quote or mention).
/// NIP-10: "reply" marker tag, or fallback: has "e" tag + "p" tag and no "q" tag.
private func isReplyEvent(_ event: NostrEvent) -> Bool {
    let eTags = event.tags.filter { $0.first == "e" }
    guard !eTags.isEmpty else { return false }
    // NIP-10 marker: explicit "reply" marker
    let hasReplyMarker = eTags.contains { tag in
        tag.count >= 4 && tag[3] == "reply"
    }
    if hasReplyMarker { return true }
    // NIP-10 marker: explicit "root" without "reply" — still a reply to root
    let hasRootMarker = eTags.contains { tag in
        tag.count >= 4 && tag[3] == "root"
    }
    // If has "q" tag, it's a quote not a reply
    let hasQuoteTag = event.tags.contains { $0.first == "q" }
    if hasQuoteTag { return false }
    // Legacy: has both "e" and "p" tags + root marker = reply
    if hasRootMarker && event.getTagValue("p") != nil { return true }
    // Legacy positional: multiple "e" tags with "p" tag = likely reply
    if eTags.count >= 1 && event.getTagValue("p") != nil && !hasRootMarker {
        // Only if the "e" tags don't have mention markers
        let hasMention = eTags.allSatisfy { tag in
            tag.count >= 4 && tag[3] == "mention"
        }
        return !hasMention
    }
    return false
}

// MARK: - Post Header (name + time + ⋮ menu)

/// Author row with optional NIP-05, badges, timestamp, and context menu.
/// Mirrors Android PostHeader composable.
struct PostHeader: View {
    let post: ScoredPost
    let isOwnPost: Bool
    let onProfileTap: (String) -> Void
    var repository:    NostrRepository? = nil
    var onDelete:      (() -> Void)?  = nil
    var onMute:        (() -> Void)?  = nil
    var onReport:      (() -> Void)?  = nil
    var onBirdwatch:   (() -> Void)?  = nil
    var onNotInterested: (() -> Void)? = nil

    @Environment(\.nuruTheme) private var theme
    @State private var showCopyToast = false
    @State private var nip05Verified: Bool? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                // Name + badges (mirrors Android PostHeader)
                HStack(spacing: 4) {
                    Button {
                        onProfileTap(post.event.pubkey)
                    } label: {
                        Text(wrapLongTokens(post.profile?.displayedName ?? post.event.pubkey.shortenedPubkey, chunkSize: 14))
                            .font(NuruFont.bodyMedium())
                            .fontWeight(.semibold)
                            .foregroundStyle(theme.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .buttonStyle(.plain)

                    if let nip05 = post.profile?.nip05, !nip05.isEmpty, (nip05Verified ?? post.isVerified) {
                        VerifiedIcon()
                            .frame(width: 14, height: 14)
                            .fixedSize()
                    }

                    // Badges (self-fetching via BadgeDisplay, or static from post.badges)
                    if let repo = repository {
                        BadgeDisplay(pubkey: post.event.pubkey, repository: repo, initialBadges: post.badges)
                            .fixedSize()
                    } else if !post.badges.isEmpty {
                        badgesStatic
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 4)

                // Timestamp
                Text(post.event.createdAt.relativeTimeString)
                    .font(NuruFont.bodySmall())
                    .foregroundStyle(theme.textTertiary)

                // ⋮ menu — mirrors Android DropdownMenu order:
                // テキストをコピー → この投稿に興味がない → Birdwatch → 通報 → ミュート → 削除
                Menu {
                // テキストをコピー (mirrors Android "テキストをコピー")
                Button {
                    UIPasteboard.general.string = post.event.content
                    // コピー確認フィードバック（Android: Toast に対応）
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                    showCopyToast = true
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        showCopyToast = false
                    }
                } label: {
                    Label("テキストをコピー", systemImage: "doc.on.doc")
                }

                if !isOwnPost {
                    if let ni = onNotInterested {
                        Button { ni() } label: {
                            Label("この投稿に興味がない", systemImage: "hand.thumbsdown")
                        }
                    }
                    if let bw = onBirdwatch {
                        Button { bw() } label: {
                            Label("Birdwatch", systemImage: NuruIcons.birdwatchCheck)
                        }
                    }
                    if let report = onReport {
                        Button { report() } label: {
                            Label("通報", systemImage: NuruIcons.warning)
                        }
                    }
                    if let mute = onMute {
                        Button(role: .destructive) { mute() } label: {
                            Label("ミュート", systemImage: NuruIcons.block)
                        }
                    }
                }
                if isOwnPost, let delete = onDelete {
                    Button(role: .destructive) { delete() } label: {
                        Label("削除", systemImage: NuruIcons.trash)
                    }
                }
                } label: {
                    MoreVertIcon()
                        .frame(width: 16, height: 16)
                        .foregroundStyle(theme.textTertiary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
            }

            // ユーザー名と本文の間に NIP-05 を表示。未設定時は余計な空行を作らない。
            if let nip05 = post.profile?.nip05, !nip05.isEmpty {
                HStack(spacing: 4) {
                    Text(formatNip05(nip05))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle((nip05Verified ?? post.isVerified) ? NuruColors.lineGreen : theme.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .accessibilityLabel("NIP-05 \(formatNip05(nip05))")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: post.profile?.nip05 ?? "") {
            guard let nip05 = post.profile?.nip05, !nip05.isEmpty, let repo = repository else {
                nip05Verified = post.isVerified
                return
            }
            let resolved = await repo.resolveNip05(nip05)
            nip05Verified = (resolved == post.event.pubkey)
            post.isVerified = nip05Verified ?? false
        }
        .overlay(alignment: .trailing) {
            if showCopyToast {
                Text("コピーしました")
                    .font(NuruFont.labelSmall())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.75))
                    .clipShape(Capsule())
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    .animation(.easeInOut(duration: 0.2), value: showCopyToast)
            }
        }
    }

    // Static badge display (no repository available)
    private var badgesStatic: some View {
        HStack(spacing: 4) {
            ForEach(post.badges.prefix(3), id: \.self) { url in
                AsyncImage(url: URL(string: url)) { phase in
                    if case .success(let img) = phase {
                        img.resizable().scaledToFit()
                    }
                }
                .frame(width: 16, height: 16)
                .clipShape(RoundedRectangle(cornerRadius: 2))
            }
        }
    }
}

private func formatNip05(_ nip05: String) -> String {
    nip05.hasPrefix("_@") ? String(nip05.dropFirst(2)) : nip05
}

/// Inserts soft break opportunities into very long unbroken tokens so a single
/// long word / URL-like string cannot force timeline rows wider than the screen.
private func wrapLongTokens(_ text: String, chunkSize: Int = 18) -> String {
    text.split(separator: " ", omittingEmptySubsequences: false).map { tokenSub in
        let token = String(tokenSub)
        guard token.count > chunkSize,
              token.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return token }
        var out = ""
        for (idx, ch) in token.enumerated() {
            if idx > 0 && idx % chunkSize == 0 { out.append("\u{200B}") }
            out.append(ch)
        }
        return out
    }.joined(separator: " ")
}

// MARK: - Post Content (text with URL / hashtag / emoji parsing)

/// Renders post text with tappable hashtags, @mentions, and URL highlights.
/// Mirrors Android PostContent composable.
struct PostContentView: View {
    let post: ScoredPost
    var repository: NostrRepository? = nil
    var onProfileTap: (String) -> Void = { _ in }
    var onHashtagTap: ((String) -> Void)? = nil
    /// 既に QuotedPostPreview で表示されている引用イベント ID（二重表示を防止）。
    var quotedPostEventId: String? = nil

    @Environment(\.nuruTheme) private var theme
    @State private var mentionLabels: [String: String] = [:]

    var body: some View {
        let raw     = post.event.content
        // 画像URL・動画URLをテキスト表示から除外（カードとして別途レンダリング）。
        // 引用元カードを別表示する場合は content 末尾の nostr:note/nevent も本文から除去し、
        // 「本文」と「引用カード」の間に改行だけの大きな余白が残らないようにする。
        var display = removeMediaUrls(raw)
        if quotedPostEventId != nil {
            display = removeNostrEventLinks(display)
        }
        display = display.trimmingCharacters(in: .whitespacesAndNewlines)
        if display.isEmpty { return AnyView(EmptyView()) }

        let parts = parseContent(display)
        // 1投稿あたり最大1動画（Android VideoPlayer.kt と同仕様）
        let videoUrl: String? = {
            let raw = post.event.content
            let regex = try? NSRegularExpression(
                pattern: #"https?://[^\s]+\.(?:mp4|mov|webm|m3u8)(\?[^\s]*)?"#,
                options: [.caseInsensitive]
            )
            let ns = raw as NSString
            if let m = regex?.firstMatch(in: raw, range: NSRange(location: 0, length: ns.length)) {
                return ns.substring(with: m.range)
            }
            return nil
        }()

        return AnyView(
            VStack(alignment: .leading, spacing: NuruSpacing.space2) {
                // インラインテキスト（動画URL・画像URL・引用リンクは除外済み）
                inlineText(parts: parts)

                // 動画インライン再生（最大1本）
                // Android: VideoPlayer.kt の ExoPlayer インライン再生に対応
                if let vUrl = videoUrl {
                    VideoPlayer(videoUrl: vUrl)
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusMd))
                }

                // URL プレビューカード（動画・画像以外）
                ForEach(parts.indices, id: \.self) { i in
                    switch parts[i] {
                    case .link(let url):
                        if !isVideoUrl(url) {
                            URLPreview(url: url)
                        }
                    case .nostr(let link):
                        // nostr:note1.../nevent1... の埋め込みカード（Android EmbeddedNostrContent に対応）
                        EmbeddedNostrCard(
                            link: link,
                            repository: repository,
                            onProfileTap: onProfileTap,
                            skipEventId: quotedPostEventId
                        )
                    default:
                        EmptyView()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
        )
    }

    // MARK: Inline Text

    /// カスタム絵文字画像がテキスト内に存在するか判定。
    private var hasCustomEmojiImages: Bool {
        let emojis: [String: String] = post.event.tags
            .filter { $0.first == "emoji" && $0.count >= 3 }
            .reduce(into: [:]) { dict, tag in dict[tag[1]] = tag[2] }
        return !emojis.isEmpty && post.event.content.contains(":")
    }

    @ViewBuilder
    private func inlineText(parts: [ContentPart]) -> some View {
        if hasCustomEmojiImages {
            // カスタム絵文字画像を含む場合: FlowLayout でテキスト + 画像を混合レンダリング
            // Android の InlineTextContent + appendInlineContent に対応
            EmojiRichText(parts: parts, mentionLabels: mentionLabels, theme: theme)
        } else {
            // 絵文字画像なし: 従来の Text 連結（パフォーマンス最適）
            plainInlineText(parts: parts)
        }
    }

    private func plainInlineText(parts: [ContentPart]) -> some View {
        Text(attributedInlineText(parts: parts))
            .font(NuruFont.bodyMedium())
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.openURL, OpenURLAction { url in
                guard url.scheme == "nurunuru" else { return .systemAction }
                if url.host == "hashtag" {
                    let tag = url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
                    onHashtagTap?(tag)
                    return .handled
                }
                if url.host == "profile" {
                    let pubkey = url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
                    onProfileTap(pubkey)
                    return .handled
                }
                return .systemAction
            })
            .task(id: post.event.id) { await resolveMentionLabels(parts: parts) }
    }

    private func attributedInlineText(parts: [ContentPart]) -> AttributedString {
        var out = AttributedString("")
        for part in parts {
            switch part {
            case .plain(let s):
                var attr = AttributedString(wrapLongTokens(s))
                attr.foregroundColor = theme.textPrimary
                out.append(attr)
            case .hashtag(let tag):
                var attr = AttributedString(tag)
                attr.foregroundColor = NuruColors.lineGreen
                attr.font = NuruFont.bodyMedium().weight(.medium)
                let rawTag = String(tag.dropFirst())
                if let encoded = rawTag.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                   let url = URL(string: "nurunuru://hashtag/\(encoded)") {
                    attr.link = url
                    attr.underlineStyle = nil
                }
                out.append(attr)
            case .mention(let raw, let label):
                let bech32 = raw.replacingOccurrences(of: "nostr:", with: "").lowercased()
                let resolved = mentionLabels[bech32] ?? label
                var attr = AttributedString(resolved)
                attr.foregroundColor = NuruColors.lineGreen
                attr.font = NuruFont.bodyMedium().weight(.medium)
                if let parsed = NostrBech32.decode(bech32),
                   (parsed.type == .npub || parsed.type == .nprofile),
                   let encoded = parsed.hex.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                   let url = URL(string: "nurunuru://profile/\(encoded)") {
                    attr.link = url
                    attr.underlineStyle = nil
                }
                out.append(attr)
            case .link(let url):
                if !isVideoUrl(url) {
                    let shortened = url.count > 40 ? String(url.prefix(40)) + "…" : url
                    var attr = AttributedString(shortened)
                    attr.foregroundColor = NuruColors.lineGreen
                    if let link = URL(string: url) { attr.link = link }
                    out.append(attr)
                }
            case .nostr:
                break
            case .emoji(let code, _):
                var attr = AttributedString(code)
                attr.foregroundColor = theme.textPrimary
                out.append(attr)
            }
        }
        return out
    }

    // MARK: Content Parser

    private func resolveMentionLabels(parts: [ContentPart]) async {
        guard let repo = repository else { return }
        let bech32s = parts.compactMap { part -> String? in
            if case .mention(let raw, _) = part {
                return raw.replacingOccurrences(of: "nostr:", with: "").lowercased()
            }
            return nil
        }
        guard !bech32s.isEmpty else { return }

        var updated = mentionLabels
        for bech32 in Set(bech32s) {
            guard updated[bech32] == nil,
                  let parsed = NostrBech32.decode(bech32),
                  parsed.type == .npub || parsed.type == .nprofile else { continue }
            if let p = await repo.fetchProfile(pubkey: parsed.hex) {
                updated[bech32] = "@\(p.displayedName)"
            }
        }
        mentionLabels = updated
    }

    private func parseContent(_ text: String) -> [ContentPart] {
        var parts: [ContentPart] = []
        let pattern = #"(https?://[^\s]+|nostr:(?:note1|nevent1|npub1|nprofile1|naddr1)[a-z0-9]+|(?<!nostr:)(?:note1|nevent1|npub1|nprofile1)[a-z0-9]+|#[\p{L}\p{N}_]+|:\w+:)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return [.plain(text)]
        }

        let nsText   = text as NSString
        let matches  = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        var lastEnd  = 0

        let emojis: [String: String] = post.event.tags
            .filter { $0.first == "emoji" && $0.count >= 3 }
            .reduce(into: [:]) { dict, tag in dict[tag[1]] = tag[2] }

        for match in matches {
            let range = match.range
            if range.location > lastEnd {
                let plain = nsText.substring(with: NSRange(location: lastEnd, length: range.location - lastEnd))
                parts.append(.plain(plain))
            }
            let value = nsText.substring(with: range)
            let loweredValue = value.lowercased()
            if loweredValue.hasPrefix("http") {
                parts.append(.link(value))
            } else if loweredValue.hasPrefix("nostr:") {
                let bech32 = String(value.dropFirst("nostr:".count)).lowercased()
                if bech32.hasPrefix("npub1") || bech32.hasPrefix("nprofile1") {
                    parts.append(.mention(value, "@" + bech32.prefix(12) + "…"))
                } else {
                    parts.append(.nostr(value))
                }
            } else if loweredValue.hasPrefix("npub1") || loweredValue.hasPrefix("nprofile1") {
                parts.append(.mention(value, "@" + loweredValue.prefix(12) + "…"))
            } else if loweredValue.hasPrefix("note1") || loweredValue.hasPrefix("nevent1") {
                parts.append(.nostr(value))
            } else if value.hasPrefix("#") {
                parts.append(.hashtag(value))
            } else if value.hasPrefix(":") && value.hasSuffix(":") {
                let shortcode = String(value.dropFirst().dropLast())
                parts.append(.emoji(value, emojis[shortcode]))
            }
            lastEnd = range.location + range.length
        }
        if lastEnd < nsText.length {
            parts.append(.plain(nsText.substring(from: lastEnd)))
        }
        return parts
    }
}

// MARK: - Content Parts

private enum ContentPart {
    case plain(String)
    case link(String)
    case nostr(String)
    case mention(String, String)   // (nostrLink, displayLabel)
    case hashtag(String)
    case emoji(String, String?)    // (code e.g. ":smile:", url?)
}

// MARK: - Emoji Rich Text (custom emoji inline rendering)

/// カスタム絵文字画像をインラインテキスト中に表示する。
/// Android の InlineTextContent + appendInlineContent に対応。
/// SwiftUI の Text は画像のインライン埋め込みに制限があるため、
/// テキストを行単位に分割し FlowLayout 風に Text + AsyncImage を混合レンダリングする。
private struct EmojiRichText: View {
    let parts: [ContentPart]
    let mentionLabels: [String: String]
    let theme: NuruTheme

    var body: some View {
        // テキストセグメントを絵文字で分割して Text + Image の連結を構築
        let segments = buildSegments()
        // 各セグメントを Text(...) で連結（絵文字はプレースホルダー表示後 overlay で画像を重ねる）
        // 最もシンプルなアプローチ: 1行ずつ HStack に Text と画像を並べる
        WrappingHStack(alignment: .leading, spacing: 0) {
            ForEach(segments.indices, id: \.self) { i in
                switch segments[i] {
                case .text(let attrText):
                    Text(attrText)
                        .font(NuruFont.bodyMedium())
                        .lineSpacing(2)
                case .emojiImage(let url):
                    if let imageUrl = URL(string: url) {
                        AnimatedRemoteImage(url: imageUrl) {
                            Color.clear
                                .frame(width: 20, height: 20)
                        }
                        .frame(width: 20, height: 20)
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                        .padding(.horizontal, 1)
                        .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] }
                    }
                }
            }
        }
    }

    private enum Segment {
        case text(AttributedString)
        case emojiImage(String) // url
    }

    /// ContentPart 配列を Text/EmojiImage セグメントに変換。
    /// 連続するテキスト系パートは1つの AttributedString にマージ。
    private func buildSegments() -> [Segment] {
        var segments: [Segment] = []
        var currentText = AttributedString("")

        func flushText() {
            if !currentText.characters.isEmpty {
                segments.append(.text(currentText))
                currentText = AttributedString("")
            }
        }

        func appendTextChunks(_ text: String, color: Color) {
            // SwiftUI Text は長い1セグメントだと幅を占有し、後続のカスタム絵文字が
            // 不自然に次行へ落ちやすい。投稿は140文字上限なので、短い単位に分割して
            // Android InlineTextContent に近い折り返しにする。
            var buffer = ""
            func emit(_ value: String) {
                guard !value.isEmpty else { return }
                var attr = AttributedString(value)
                attr.foregroundColor = color
                currentText.append(attr)
                flushText()
            }

            for ch in text {
                if ch.isWhitespace || ch.isNewline {
                    emit(buffer)
                    buffer = ""
                    emit(String(ch))
                } else if ch.unicodeScalars.allSatisfy({ $0.value <= 0x007F }) {
                    buffer.append(ch)
                    if buffer.count >= 12 {
                        emit(buffer)
                        buffer = ""
                    }
                } else {
                    emit(buffer)
                    buffer = ""
                    emit(String(ch))
                }
            }
            emit(buffer)
        }

        for part in parts {
            switch part {
            case .plain(let s):
                appendTextChunks(wrapLongTokens(s), color: theme.textPrimary)
            case .hashtag(let tag):
                var attr = AttributedString(tag)
                attr.foregroundColor = NuruColors.lineGreen
                currentText.append(attr)
            case .mention(let raw, let label):
                let bech32 = raw.replacingOccurrences(of: "nostr:", with: "").lowercased()
                var attr = AttributedString(mentionLabels[bech32] ?? label)
                attr.foregroundColor = NuruColors.lineGreen
                currentText.append(attr)
            case .link(let url):
                if !isVideoUrl(url) {
                    let shortened = url.count > 40 ? String(url.prefix(40)) + "…" : url
                    var attr = AttributedString(shortened)
                    attr.foregroundColor = NuruColors.lineGreen
                    currentText.append(attr)
                }
            case .nostr:
                break
            case .emoji(let code, let url):
                if let url {
                    flushText()
                    segments.append(.emojiImage(url))
                } else {
                    // URL なし: テキストとして表示
                    var attr = AttributedString(code)
                    attr.foregroundColor = theme.textPrimary
                    currentText.append(attr)
                }
            }
        }
        flushText()
        return segments
    }
}

// MARK: - Wrapping HStack (FlowLayout)

/// 子ビューを水平に並べ、行末で自動折り返しするレイアウト。
/// Android の InlineTextContent のテキスト折り返しに対応。
struct WrappingHStack: Layout {
    var alignment: HorizontalAlignment = .leading
    var spacing: CGFloat = 0

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() where index < subviews.count {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private struct LayoutResult {
        var size: CGSize
        var positions: [CGPoint]
    }

    private func computeLayout(proposal: ProposedViewSize, subviews: Subviews) -> LayoutResult {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: maxWidth.isFinite ? maxWidth : nil, height: nil))
            if x + size.width > maxWidth && x > 0 {
                // 改行
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            totalWidth = max(totalWidth, x)
        }

        return LayoutResult(
            size: CGSize(width: maxWidth.isFinite ? min(totalWidth, maxWidth) : totalWidth, height: y + rowHeight),
            positions: positions
        )
    }
}

// MARK: - Post Media (images extracted from content)

/// Displays image grid extracted from post content.
/// Mirrors Android PostMedia composable.
struct PostMedia: View {
    let post: ScoredPost

    @State private var viewerImages:  [String]? = nil
    @State private var viewerIndex:   Int        = 0
    @State private var showViewer     = false

    private var mediaUrls: [String] {
        // NIP-92: content内URL + imeta URL を統合（順序保持・重複排除）
        var seen = Set<String>()
        var out: [String] = []

        for u in extractPostImages(post.event.content) {
            let normalized = normalizeMediaUrlString(u)
            if seen.insert(normalized).inserted { out.append(normalized) }
        }
        for u in post.event.extractImetaUrls() {
            let normalized = normalizeMediaUrlString(u)
            if seen.insert(normalized).inserted { out.append(normalized) }
        }
        return out
    }

    var body: some View {
        let images = mediaUrls
        if images.isEmpty { return AnyView(EmptyView()) }

        return AnyView(
            PostImageGrid(images: images, authorPubkey: post.event.pubkey) { idx in
                viewerImages = images
                viewerIndex  = idx
                showViewer   = true
            }
            .padding(.top, NuruSpacing.space2)
            .fullScreenCover(isPresented: $showViewer) {
                ImageViewerView(
                    images: viewerImages ?? images,
                    authorPubkey: post.event.pubkey,
                    initialIndex: viewerIndex,
                    onDismiss: { showViewer = false }
                )
            }
        )
    }
}

// MARK: - Post Image Grid

/// Adaptive image grid (1 / 2 / 3 / 4+ images).
/// Mirrors Android PostImageGrid composable.
struct PostImageGrid: View {
    let images: [String]
    let authorPubkey: String?
    var onImageTap: ((Int) -> Void)? = nil

    @State private var showAll = false

    private let maxVisible = 4

    var body: some View {
        let display = showAll ? images : Array(images.prefix(maxVisible))
        let hiddenCount = !showAll && images.count > maxVisible ? images.count - maxVisible : 0

        Group {
            if images.count == 1 {
                // Single image: modern full-bleed card. scaledToFill avoids the old letterboxed side bars
                // while the explicit geometry keeps horizontal overflow impossible.
                GeometryReader { geo in
                    let width = max(0, geo.size.width)
                    let height = min(320, max(190, width * 0.72))
                    CachedAsyncImage(url: URL(string: images[0]), authorPubkey: authorPubkey, contentMode: .fill) {
                        RoundedRectangle(cornerRadius: NuruSpacing.radiusLg)
                            .fill(Color(white: 0.12))
                            .overlay(ProgressView().tint(.white).scaleEffect(0.6))
                    }
                    .frame(width: width, height: height)
                    .clipped()
                    .overlay(
                        LinearGradient(
                            colors: [Color.black.opacity(0.0), Color.black.opacity(0.08)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusLg, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusLg, style: .continuous))
                    .onTapGesture { onImageTap?(0) }
                }
                .frame(height: 220)
                .frame(maxWidth: .infinity)
                .clipped()

            } else if images.count == 3 && !showAll {
                // 3 images: left full-height + right 2-stacked
                // GeometryReaderで列幅を固定し、横方向オーバーフローを防ぐ。
                GeometryReader { geo in
                    let totalWidth = max(0, geo.size.width)
                    let colWidth = max(0, (totalWidth - 4) / 2)

                    HStack(spacing: 4) {
                        asyncImage(url: images[0], height: 240, maxHeight: nil)
                            .frame(width: colWidth, height: 240)
                            .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusSm))
                            .onTapGesture { onImageTap?(0) }

                        VStack(spacing: 4) {
                            asyncImage(url: images[1], height: 118, maxHeight: nil)
                                .frame(width: colWidth, height: 118)
                                .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusSm))
                                .onTapGesture { onImageTap?(1) }
                            asyncImage(url: images[2], height: 118, maxHeight: nil)
                                .frame(width: colWidth, height: 118)
                                .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusSm))
                                .onTapGesture { onImageTap?(2) }
                        }
                    }
                    .frame(width: totalWidth, height: 240, alignment: .leading)
                }
                .frame(height: 240)

            } else {
                // 2 or 4+ images: 2-column grid
                // 列幅を明示計算して、画像サイズに依存した横はみ出しを防止。
                let rows = (display.count + 1) / 2
                GeometryReader { geo in
                    let totalWidth = max(0, geo.size.width)
                    let cellWidth = max(0, (totalWidth - 4) / 2)

                    VStack(spacing: 4) {
                        ForEach(0..<rows, id: \.self) { r in
                            HStack(spacing: 4) {
                                ForEach(0..<2, id: \.self) { c in
                                    let idx = r * 2 + c
                                    if idx < display.count {
                                        ZStack {
                                            asyncImage(url: display[idx], height: 120, maxHeight: nil)
                                                .frame(width: cellWidth, height: 120)
                                                .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusSm))

                                            // "+N" overlay on last visible cell
                                            if idx == maxVisible - 1 && hiddenCount > 0 {
                                                RoundedRectangle(cornerRadius: NuruSpacing.radiusSm)
                                                    .fill(Color.black.opacity(0.6))
                                                    .frame(width: cellWidth, height: 120)
                                                Text("+\(hiddenCount)")
                                                    .font(.system(size: 20, weight: .bold))
                                                    .foregroundStyle(.white)
                                            }
                                        }
                                        .frame(width: cellWidth, height: 120)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            if idx == maxVisible - 1 && hiddenCount > 0 {
                                                showAll = true
                                            } else {
                                                onImageTap?(idx)
                                            }
                                        }
                                    } else {
                                        Color.clear
                                            .frame(width: cellWidth, height: 120)
                                    }
                                }
                            }
                        }
                    }
                    .frame(width: totalWidth, alignment: .leading)
                }
                .frame(height: CGFloat(rows * 120 + max(0, rows - 1) * 4))

                if showAll {
                    Button("閉じる") { showAll = false }
                        .font(NuruFont.labelSmall())
                        .foregroundStyle(NuruColors.lineGreen)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
    }

    @ViewBuilder
    private func asyncImage(url: String, height: CGFloat?, maxHeight: CGFloat?) -> some View {
        let content = CachedAsyncImage(url: URL(string: url), authorPubkey: authorPubkey) {
            Color(white: 0.12)
                .overlay(ProgressView().tint(.white).scaleEffect(0.6))
        }
        .frame(maxWidth: .infinity)

        // clipped() を height/maxHeight 適用後に実行して scaledToFill のオーバーフローを防ぐ
        // 高さ未指定セルは呼び出し側で明示フレーム/aspectRatioを付与して安定化する。
        if let h = height {
            content.frame(height: h).clipped()
        } else if let mh = maxHeight {
            content.frame(maxHeight: mh).clipped()
        } else {
            content
        }
    }
}

// MARK: - Helpers

private func isVideoUrl(_ url: String) -> Bool {
    let lower = url.lowercased()
    return lower.contains(".mp4") || lower.contains(".mov") ||
           lower.contains(".webm") || lower.contains(".m3u8")
}

private let imageRegex: NSRegularExpression? = {
    // 拡張子ありの典型的な画像URL（従来互換）
    try? NSRegularExpression(
        pattern: #"https?://[^\s]+\.(?:jpg|jpeg|png|gif|webp|avif)(\?[^\s]*)?"#,
        options: [.caseInsensitive]
    )
}()

private let genericUrlRegex: NSRegularExpression? = {
    // NIP-92 / yabu URL のような拡張子なしURLも拾う
    try? NSRegularExpression(
        pattern: #"https?://[^\s]+"#,
        options: [.caseInsensitive]
    )
}()

func extractPostImages(_ content: String) -> [String] {
    let ns = content as NSString

    // Android 実装（findAll().distinct().toList()）と同様に、
    // "最初に出現した順序" を保ったまま重複だけ除去する。
    var seen = Set<String>()
    var ordered: [String] = []

    // 1) まず拡張子あり画像URL
    if let imageRegex {
        for match in imageRegex.matches(in: content, range: NSRange(location: 0, length: ns.length)) {
            let url = ns.substring(with: match.range)
            if seen.insert(url).inserted {
                ordered.append(url)
            }
        }
    }

    // 2) 次に一般URLを走査し、画像/Blossom系URLのみ追加
    if let genericUrlRegex {
        for match in genericUrlRegex.matches(in: content, range: NSRange(location: 0, length: ns.length)) {
            let raw = ns.substring(with: match.range)
            guard let u = URL(string: raw),
                  let scheme = u.scheme?.lowercased(), (scheme == "http" || scheme == "https") else { continue }

            let lower = raw.lowercased()
            let looksLikeImage = lower.contains(".jpg") || lower.contains(".jpeg") ||
                lower.contains(".png") || lower.contains(".gif") ||
                lower.contains(".webp") || lower.contains(".avif")

            // 拡張子なしでも、sha256 64hex を含むURLは Blossom / NIP-92 画像候補として扱う
            let hasSha256 = BlossomB7Resolver.extractLastSha256Hex(from: raw) != nil

            if (looksLikeImage || hasSha256), seen.insert(raw).inserted {
                ordered.append(raw)
            }
        }
    }

    return ordered
}

func removeImageUrls(_ content: String) -> String {
    guard let regex = imageRegex else { return content }
    let ns = content as NSString
    return regex.stringByReplacingMatches(
        in: content,
        range: NSRange(location: 0, length: ns.length),
        withTemplate: ""
    ).trimmingCharacters(in: .whitespacesAndNewlines)
}

private func normalizeMediaUrlString(_ raw: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return raw }

    // Try round-trip URL first
    if let url = URL(string: trimmed) {
        return url.absoluteString
    }

    // Fallback percent-encoding for unicode/space-containing URLs
    if let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed),
       let url = URL(string: encoded) {
        return url.absoluteString
    }

    return raw
}

private let videoRegex: NSRegularExpression? = {
    try? NSRegularExpression(
        pattern: #"https?://[^\s]+\.(?:mp4|mov|webm|m3u8)(\?[^\s]*)?"#,
        options: [.caseInsensitive]
    )
}()

// MARK: - Embedded Nostr Card (nostr:note1.../nevent1...)

/// Android の EmbeddedNostrContent に対応。
/// nostr:note1.../nevent1.../npub1.../nprofile1... のリンクをインライン表示する。
/// PostRow の QuotedPostPreview で既に表示済みのイベントは skipEventId で除外。
struct EmbeddedNostrCard: View {
    let link: String              // "nostr:note1..." or "nostr:nevent1..."
    var repository: NostrRepository? = nil
    var onProfileTap: (String) -> Void = { _ in }
    /// PostRow.QuotedPostPreview で既に表示されているイベント ID（二重表示防止）。
    var skipEventId: String? = nil

    @Environment(\.nuruTheme) private var theme

    @State private var note:          ScoredPost?  = nil
    @State private var profileData:   UserProfile? = nil
    @State private var profilePubkey: String?       = nil
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                // Android: PostSkeleton() — 簡易ローディング表示
                EmptyView()
            } else if let note = note {
                // ノート埋め込みカード（Android EmbeddedNostrContent の note != null 分岐）
                VStack(alignment: .leading, spacing: NuruSpacing.space2) {
                    HStack(spacing: 6) {
                        AvatarView(
                            url:  note.profile?.picture,
                            name: note.profile?.displayedName ?? "?",
                            size: 20
                        )
                        Text(wrapLongTokens(note.profile?.displayedName ?? note.event.pubkey.shortenedPubkey, chunkSize: 14))
                            .font(NuruFont.bodySmall())
                            .fontWeight(.bold)
                            .foregroundStyle(theme.textPrimary)
                            .lineLimit(1)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { onProfileTap(note.event.pubkey) }

                    Text(wrapLongTokens(note.event.content))
                        .font(NuruFont.bodySmall())
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(3)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(NuruSpacing.space3)
                .background(
                    RoundedRectangle(cornerRadius: NuruSpacing.radiusXl)
                        .fill(theme.bgSecondary.opacity(0.92))
                        .overlay(LinearGradient(colors: [NuruColors.lineGreen.opacity(0.10), Color.clear], startPoint: .topLeading, endPoint: .bottomTrailing))
                )
                .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusXl))
                .overlay(
                    RoundedRectangle(cornerRadius: NuruSpacing.radiusXl)
                        .stroke(NuruColors.lineGreen.opacity(0.22), lineWidth: 1)
                )
                .padding(.vertical, 6)
            } else if let pk = profilePubkey {
                // プロフィール埋め込みカード（Android EmbeddedNostrContent の profilePubkey != null 分岐）
                HStack(spacing: 8) {
                    AvatarView(
                        url:  profileData?.picture,
                        name: profileData?.displayedName ?? "?",
                        size: 32
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(profileData?.displayedName ?? pk.shortenedPubkey)
                            .font(NuruFont.bodySmall())
                            .fontWeight(.bold)
                            .foregroundStyle(theme.textPrimary)
                            .lineLimit(1)
                        if let about = profileData?.about, !about.isEmpty {
                            Text(about)
                                .font(NuruFont.labelSmall())
                                .foregroundStyle(theme.textSecondary)
                                .lineLimit(2)
                                .truncationMode(.tail)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(NuruSpacing.space3)
                .background(theme.bgTertiary.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusMd))
                .overlay(
                    RoundedRectangle(cornerRadius: NuruSpacing.radiusMd)
                        .stroke(theme.borderColor.opacity(0.5), lineWidth: 0.5)
                )
                .padding(.vertical, 6)
                .contentShape(Rectangle())
                .onTapGesture { onProfileTap(pk) }
            } else {
                // フォールバック: リンクテキスト表示（Android: Text(link, color = lineGreen)）
                Text(link)
                    .font(NuruFont.bodySmall())
                    .foregroundStyle(NuruColors.lineGreen)
            }
        }
        .task {
            guard let repo = repository else {
                isLoading = false
                return
            }
            let bech32 = link.hasPrefix("nostr:") ? String(link.dropFirst(6)) : link
            if let parsed = NostrBech32.decode(bech32) {
                switch parsed.type {
                case .note, .nevent:
                    // skipEventId と一致する場合は表示しない（QuotedPostPreview で表示済み）
                    if let skip = skipEventId, skip == parsed.hex {
                        isLoading = false
                        return
                    }
                    if let event = await repo.fetchEvent(eventId: parsed.hex) {
                        let scored = ScoredPost(event: event)
                        // プロフィール取得
                        if let profile = await repo.fetchProfile(pubkey: event.pubkey) {
                            scored.profile = profile
                        }
                        note = scored
                    }
                case .npub, .nprofile:
                    profilePubkey = parsed.hex
                    profileData = await repo.fetchProfile(pubkey: parsed.hex)
                }
            }
            isLoading = false
        }
    }
}


/// content 内の nostr:note1... / nostr:nevent1... を除去する。
/// 引用カードを別レンダリングする場合、本文末尾の引用リンクだけが改行として残って
/// 大きな余白に見えるのを防ぐ。
func removeNostrEventLinks(_ content: String) -> String {
    let pattern = #"(?:nostr:)?(?:note1|nevent1)[a-z0-9]+"#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
        return content
    }
    let ns = content as NSString
    return regex.stringByReplacingMatches(
        in: content,
        range: NSRange(location: 0, length: ns.length),
        withTemplate: ""
    )
}

/// 動画URL と画像URL の両方をテキストから除去する。
/// インラインテキスト表示用（VideoPlayer / PostMedia として別途レンダリング）。
/// Markdown 画像構文 `![alt](url)` も除去する。
func removeMediaUrls(_ content: String) -> String {
    var result = removeImageUrls(content)
    // Markdown 画像構文 ![alt](url) を除去
    if let mdRegex = try? NSRegularExpression(pattern: #"!\[[^\]]*\]\([^\)]*\)"#) {
        let ns = result as NSString
        result = mdRegex.stringByReplacingMatches(
            in: result,
            range: NSRange(location: 0, length: ns.length),
            withTemplate: ""
        )
    }
    guard let vRegex = videoRegex else { return result.trimmingCharacters(in: .whitespacesAndNewlines) }
    let ns = result as NSString
    result = vRegex.stringByReplacingMatches(
        in: result,
        range: NSRange(location: 0, length: ns.length),
        withTemplate: ""
    ).trimmingCharacters(in: .whitespacesAndNewlines)
    return result
}
