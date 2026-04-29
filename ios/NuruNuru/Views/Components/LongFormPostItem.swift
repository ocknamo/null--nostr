import SwiftUI

/// NIP-23 long-form article row + full-screen article reader.
/// Mirrors Android LongFormPostItem + ArticleReaderModal.
struct LongFormPostItem: View {

    let post:         ScoredPost
    var repository:   NostrRepository?           = nil
    var onLike:       () async -> Void           = {}
    var onRepost:     () async -> Void           = {}
    var onProfileTap: (String) -> Void           = { _ in }
    var onZap:        (() -> Void)?              = nil
    var onDelete:     (() -> Void)?              = nil
    var onMute:       (() -> Void)?              = nil
    var onReport:     ((String, String) -> Void)? = nil
    var onBirdwatch:  ((String, String, String) -> Void)? = nil
    var birdwatchNotes: [NostrEvent]             = []

    @State private var showReader        = false
    @State private var showBirdwatch     = false
    @State private var showReport        = false
    @State private var fetchedBirdwatchNotes: [NostrEvent] = []

    @Environment(\.nuruTheme) private var theme

    private var title:   String? { post.event.getTagValue("title") }
    private var image:   String? { post.event.getTagValue("image") }
    private var summary: String  {
        post.event.getTagValue("summary") ?? String(post.event.content.prefix(200))
    }

    private var effectiveBirdwatchNotes: [NostrEvent] {
        birdwatchNotes.isEmpty ? fetchedBirdwatchNotes : birdwatchNotes
    }

    var body: some View {
        VStack(spacing: 0) {
            PostIndicators(post: post, onProfileTap: onProfileTap, repository: repository)

            HStack(alignment: .top, spacing: 10) {
                AvatarView(
                    url:  post.profile?.picture,
                    name: post.profile?.displayedName ?? "?",
                    size: 42
                )
                .onTapGesture { onProfileTap(post.event.pubkey) }

                VStack(alignment: .leading, spacing: 0) {
                    PostHeader(
                        post:         post,
                        isOwnPost:    onDelete != nil,
                        onProfileTap: onProfileTap,
                        repository:   repository,
                        onDelete:     onDelete,
                        onMute:       onMute,
                        onReport:     onReport != nil ? { showReport = true } : nil,
                        onBirdwatch:  (onBirdwatch != nil || repository != nil) ? { showBirdwatch = true } : nil
                    )

                    Spacer().frame(height: 8)

                    // Article badge
                    HStack(spacing: 4) {
                        Image(systemName: "doc.richtext")
                            .font(.system(size: 10))
                            .foregroundStyle(NuruColors.lineGreen)
                        Text("長文記事")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(NuruColors.lineGreen)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(NuruColors.lineGreen.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .padding(.bottom, 8)

                    // Article card
                    Button { showReader = true } label: {
                        articleCard
                    }
                    .buttonStyle(.plain)

                    Spacer().frame(height: 12)

                    if !effectiveBirdwatchNotes.isEmpty {
                        BirdwatchDisplay(
                            notes:         effectiveBirdwatchNotes,
                            onAuthorClick: onProfileTap
                        )
                        Spacer().frame(height: 8)
                    }

                    PostActions(post: post, onLike: onLike, onRepost: onRepost, onZap: onZap)
                }
            }
            .padding(.horizontal, NuruSpacing.space4)
            .padding(.top, NuruSpacing.space2)
            .padding(.bottom, NuruSpacing.space3)

            Divider().background(theme.borderColor)
        }
        .background(theme.bgPrimary)
        // プロフィール未取得時の遅延再取得（Android LongFormPostItem LaunchedEffect 同等）
        .task(id: post.event.id) {
            if (post.profile?.picture?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false)
                || (post.profile?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
                    && post.profile?.name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false),
               let repo = repository {
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
        .task(id: post.event.id) {
            guard let repo = repository, birdwatchNotes.isEmpty else { return }
            let result = await repo.fetchBirdwatchNotes(eventIds: [post.event.id])
            fetchedBirdwatchNotes = result[post.event.id] ?? []
        }
        .fullScreenCover(isPresented: $showReader) {
            ArticleReaderView(
                post:        post,
                title:       title,
                image:       image,
                onDismiss:   { showReader = false },
                onProfileTap: onProfileTap
            )
        }
        .sheet(isPresented: $showBirdwatch) {
            BirdwatchModal(
                onDismiss: { showBirdwatch = false },
                onSubmit: { type, content, url in
                    showBirdwatch = false
                    if let repo = repository {
                        Task {
                            if let signed = try? await repo.publishBirdwatchNote(
                                targetEventId: post.event.id,
                                content:       content,
                                contextType:   type,
                                sourceUrl:     url.isEmpty ? nil : url
                            ) {
                                fetchedBirdwatchNotes.append(signed)
                            }
                        }
                    } else {
                        onBirdwatch?(type, content, url)
                    }
                },
                existingNotes: effectiveBirdwatchNotes
            )
            .presentationDetents([.large])
            .interactiveDismissDisabled(true)
        }
        .sheet(isPresented: $showReport) {
            ReportSheet(
                onReport:  { type, content in
                    showReport = false
                    onReport?(type, content)
                },
                onDismiss: { showReport = false }
            )
            .presentationDetents([.medium])
        }
    }

    private var articleCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let image, !image.isEmpty {
                AsyncImage(url: URL(string: image)) { phase in
                    if case .success(let img) = phase {
                        img.resizable().scaledToFill()
                    } else {
                        Rectangle().fill(theme.bgSecondary)
                    }
                }
                .frame(height: 140)
                .clipped()
            }

            VStack(alignment: .leading, spacing: 4) {
                if let title {
                    Text(title)
                        .font(NuruFont.titleMedium())
                        .fontWeight(.bold)
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(2)
                }
                Text(summary)
                    .font(NuruFont.bodySmall())
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(3)
                Text("記事を読む →")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(NuruColors.lineGreen)
                    .padding(.top, 4)
            }
            .padding(12)
        }
        .background(theme.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(theme.borderColor, lineWidth: 1)
        )
    }
}

// MARK: - ArticleReaderView

/// Full-screen scrollable NIP-23 article reader.
/// Mirrors Android ArticleReaderModal.
struct ArticleReaderView: View {

    let post:         ScoredPost
    let title:        String?
    let image:        String?
    let onDismiss:    () -> Void
    let onProfileTap: (String) -> Void

    @Environment(\.nuruTheme) private var theme

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Cover image
                    if let image, !image.isEmpty {
                        AsyncImage(url: URL(string: image)) { phase in
                            if case .success(let img) = phase {
                                img.resizable().scaledToFill()
                            } else {
                                Rectangle().fill(theme.bgSecondary)
                            }
                        }
                        .frame(height: 240)
                        .clipped()
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        // Title
                        if let title {
                            Text(title)
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(theme.textPrimary)
                                .lineSpacing(10)
                                .padding(.bottom, 16)
                        }

                        // Author row
                        Button {
                            onDismiss()
                            onProfileTap(post.event.pubkey)
                        } label: {
                            HStack(spacing: 12) {
                                AvatarView(
                                    url:  post.profile?.picture,
                                    name: post.profile?.displayedName ?? "?",
                                    size: 40
                                )
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(post.profile?.displayedName ?? "Anonymous")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(theme.textPrimary)
                                    Text(post.event.createdAt.relativeTimeString)
                                        .font(.system(size: 12))
                                        .foregroundStyle(theme.textTertiary)
                                }
                                Spacer()
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        .padding(.bottom, 20)

                        Divider().background(theme.borderColor)
                        Spacer().frame(height: 20)

                        // Markdown content
                        MarkdownContent(content: post.event.content)

                        Spacer().frame(height: 40)
                    }
                    .padding(20)
                }
            }
            .background(theme.bgPrimary)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: onDismiss) {
                        Image(systemName: NuruIcons.back)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(theme.textPrimary)
                    }
                    .buttonStyle(.plain)
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.richtext")
                            .font(.system(size: 12))
                            .foregroundStyle(NuruColors.lineGreen)
                        Text("長文記事")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(NuruColors.lineGreen)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(NuruColors.lineGreen.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Text(post.event.createdAt.relativeTimeString)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textTertiary)
                }
            }
        }
    }
}
