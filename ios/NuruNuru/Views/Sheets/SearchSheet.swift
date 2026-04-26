import SwiftUI

/// Full-screen search sheet — mirrors Android SearchModal.kt.
struct SearchSheet: View {

    let repository:   NostrRepository
    let myPubkeyHex:  String
    var onProfileTap: (String) -> Void = { _ in }
    var onDismiss:    () -> Void       = {}

    @Environment(\.nuruTheme) private var theme
    @State private var query:           String         = ""
    @State private var results:         [ScoredPost]   = []
    @State private var profileResults:  [UserProfile]  = []
    @State private var isSearching:     Bool           = false
    @State private var recentSearches:  [String]       = []
    @State private var hasSearched:     Bool           = false
    @State private var activeResultTab: Int            = 0  // 0: 投稿, 1: ユーザー

    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Search bar + close
            HStack(spacing: NuruSpacing.space2) {
                HStack(spacing: NuruSpacing.space2) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(theme.textTertiary)
                    TextField("検索", text: $query)
                        .font(NuruFont.bodyMedium())
                        .foregroundStyle(theme.textPrimary)
                        .focused($focused)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onSubmit { Task { await doSearch() } }
                    if !query.isEmpty {
                        Button { query = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(theme.textTertiary)
                        }
                    }
                }
                .padding(.horizontal, NuruSpacing.space3)
                .padding(.vertical, NuruSpacing.space2)
                .background(theme.bgSecondary)
                .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusMd))

                Button("キャンセル", action: onDismiss)
                    .font(NuruFont.bodyMedium())
                    .foregroundStyle(theme.textSecondary)
            }
            .padding(.horizontal, NuruSpacing.space4)
            .padding(.vertical, NuruSpacing.space3)
            .background(theme.bgPrimary)

            Divider().background(theme.borderColor)

            if isSearching {
                Spacer()
                ProgressView().tint(NuruColors.lineGreen)
                Spacer()
            } else if !hasSearched {
                // Pre-search state: hints + recent searches
                ScrollView {
                    VStack(alignment: .leading, spacing: NuruSpacing.space4) {
                        // Search operators hint
                        operatorsHint

                        // Recent searches
                        if !recentSearches.isEmpty {
                            recentSearchesSection
                        }
                    }
                    .padding(NuruSpacing.space4)
                }
            } else if results.isEmpty && profileResults.isEmpty {
                Spacer()
                VStack(spacing: NuruSpacing.space3) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 36))
                        .foregroundStyle(theme.textTertiary)
                    Text("「\(query)」の検索結果はありません")
                        .font(NuruFont.bodyMedium())
                        .foregroundStyle(theme.textTertiary)
                }
                Spacer()
            } else {
                // Result tab switcher
                resultTabBar

                // Results content
                if activeResultTab == 0 {
                    // 投稿 tab
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            Text("\(results.count)件の結果")
                                .font(NuruFont.labelSmall())
                                .foregroundStyle(theme.textTertiary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, NuruSpacing.space4)
                                .padding(.vertical, NuruSpacing.space2)
                            ForEach(results, id: \.id) { post in
                                PostRow(
                                    post:         post,
                                    repository:   repository,
                                    myPubkeyHex:  myPubkeyHex,
                                    onLike: {
                                        try? await repository.publishReaction(
                                            to: post.event.id,
                                            authorPubkey: post.event.pubkey
                                        )
                                        post.isLiked = true
                                        post.likeCount += 1
                                    },
                                    onRepost: {
                                        try? await repository.publishRepost(event: post.event)
                                        post.isReposted = true
                                        post.repostCount += 1
                                    },
                                    onProfileTap: onProfileTap
                                )
                            }
                        }
                    }
                } else {
                    // ユーザー tab
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            Text("\(profileResults.count)件のユーザー")
                                .font(NuruFont.labelSmall())
                                .foregroundStyle(theme.textTertiary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, NuruSpacing.space4)
                                .padding(.vertical, NuruSpacing.space2)
                            ForEach(profileResults, id: \.pubkey) { profile in
                                profileResultRow(profile)
                            }
                        }
                    }
                }
            }
        }
        .background(theme.bgPrimary.ignoresSafeArea())
        .onAppear {
            focused         = true
            recentSearches  = loadRecentSearches()
        }
    }

    // MARK: - Operators Hint

    private var operatorsHint: some View {
        VStack(alignment: .leading, spacing: NuruSpacing.space2) {
            Text("検索演算子")
                .font(NuruFont.labelSmall())
                .foregroundStyle(theme.textTertiary)

            let hints: [(String, String)] = [
                ("#タグ",       "ハッシュタグで絞り込み"),
                ("from:npub/NIP-05", "特定ユーザーの投稿"),
                ("since:日付", "この日付以降"),
                ("until:日付", "この日付以前"),
            ]
            ForEach(hints, id: \.0) { (op, desc) in
                HStack(spacing: NuruSpacing.space2) {
                    Text(op)
                        .font(NuruFont.bodySmall())
                        .foregroundStyle(NuruColors.lineGreen)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(NuruColors.lineGreen.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusSm))
                    Text(desc)
                        .font(NuruFont.bodySmall())
                        .foregroundStyle(theme.textSecondary)
                }
            }
        }
        .padding(NuruSpacing.space3)
        .background(theme.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusLg))
    }

    // MARK: - Recent Searches

    private var recentSearchesSection: some View {
        VStack(alignment: .leading, spacing: NuruSpacing.space2) {
            HStack {
                Text("最近の検索")
                    .font(NuruFont.labelSmall())
                    .foregroundStyle(theme.textTertiary)
                Spacer()
                Button("クリア") {
                    recentSearches = []
                    saveRecentSearches([])
                }
                .font(NuruFont.labelSmall())
                .foregroundStyle(theme.textTertiary)
            }
            ForEach(recentSearches, id: \.self) { recent in
                Button {
                    query = recent
                    Task { await doSearch() }
                } label: {
                    HStack {
                        Image(systemName: "clock")
                            .font(.system(size: 14))
                            .foregroundStyle(theme.textTertiary)
                        Text(recent)
                            .font(NuruFont.bodyMedium())
                            .foregroundStyle(theme.textPrimary)
                        Spacer()
                        Image(systemName: "arrow.up.left")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.textTertiary)
                    }
                    .padding(.vertical, NuruSpacing.space2)
                }
                .buttonStyle(.plain)
                Divider().background(theme.borderColor)
            }
        }
    }

    // MARK: - Search

    private func doSearch() async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        isSearching = true
        hasSearched = true

        let parsed  = SearchQueryParser.parse(query: q)

        // Parallel: fetch posts and profiles simultaneously
        async let postsTask    = performSearch(parsed: parsed, rawQuery: q)
        async let profilesTask = repository.searchProfiles(query: parsed.text.isEmpty ? q : parsed.text)
        let (events, foundProfiles) = await (postsTask, profilesTask)

        profileResults = foundProfiles

        let scored  = events.map { ScoredPost(event: $0) }

        // Enrich profiles
        let pubkeys  = Array(Set(events.map { $0.pubkey }))
        let profiles = await repository.fetchProfiles(pubkeys: pubkeys)
        let profileMap: [String: UserProfile] = Dictionary(
            profiles.map { ($0.pubkey, $0) },
            uniquingKeysWith: { a, _ in a }
        )
        scored.forEach { $0.profile = profileMap[$0.event.pubkey] }

        // Client-side filters from ParsedQuery
        var filtered = scored.map { $0 }

        // Exclude terms
        if !parsed.excludeTerms.isEmpty {
            filtered = filtered.filter { post in
                let content = post.event.content.lowercased()
                return parsed.excludeTerms.allSatisfy { !content.contains($0.lowercased()) }
            }
        }

        // Exact phrases
        if !parsed.exactPhrases.isEmpty {
            filtered = filtered.filter { post in
                let content = post.event.content.lowercased()
                return parsed.exactPhrases.allSatisfy { content.contains($0.lowercased()) }
            }
        }

        // Media filters (client-side URL pattern matching)
        for mediaFilter in parsed.filters {
            filtered = filtered.filter { post in
                let content = post.event.content
                switch mediaFilter {
                case .image:
                    return content.contains(".jpg") || content.contains(".jpeg") ||
                           content.contains(".png") || content.contains(".gif") ||
                           content.contains(".webp")
                case .video:
                    return content.contains(".mp4") || content.contains(".mov") ||
                           content.contains(".webm")
                case .link:
                    return content.contains("https://") || content.contains("http://")
                }
            }
        }

        results     = filtered
        isSearching = false

        // Save to recent
        var recent = recentSearches.filter { $0 != q }
        recent.insert(q, at: 0)
        if recent.count > 10 { recent = Array(recent.prefix(10)) }
        recentSearches = recent
        saveRecentSearches(recent)
    }

    /// Build filter and fetch events based on ParsedQuery operators.
    private func performSearch(parsed: ParsedQuery, rawQuery: String) async -> [NostrEvent] {
        let limit = 50

        // Build since/until timestamps
        let sinceTimestamp: Int64? = parsed.sinceDate.map { Int64($0.timeIntervalSince1970) }
        let untilTimestamp: Int64? = parsed.untilDate.map { Int64($0.timeIntervalSince1970) }

        // Determine kind(s) — default to text note unless overridden
        let kinds: [Int] = parsed.kind.map { [$0] } ?? [NostrKind.textNote]

        // Build the NIP-50 search string: use text part + hashtags
        var searchTokens: [String] = []
        if !parsed.text.isEmpty { searchTokens.append(parsed.text) }
        for tag in parsed.hashtags  { searchTokens.append("#\(tag)") }
        let searchString = searchTokens.isEmpty ? nil : searchTokens.joined(separator: " ")

        // Build tag filter for hashtags (relay-side #t)
        var tagFilter: [String: [String]]? = nil
        if !parsed.hashtags.isEmpty {
            tagFilter = ["#t": parsed.hashtags]
        }

        // Resolve authors from fromUser — npub/hex direct + NIP-05 async resolution
        var authors: [String]? = nil
        if !parsed.fromTargets.isEmpty {
            var resolvedAuthors: [String] = []
            for target in parsed.fromTargets {
                if target.hasPrefix("npub") {
                    // bech32 → hex conversion
                    if let pubBytes = NostrKeyUtils.parsePublicKey(target) {
                        resolvedAuthors.append(NostrKeyUtils.bytesToHex(pubBytes))
                    }
                } else if target.count == 64 && target.allSatisfy({ $0.isHexDigit }) {
                    resolvedAuthors.append(target)
                } else if target.contains("@") || target.contains(".") {
                    // NIP-05 resolution
                    if let hex = await repository.resolveNip05(target) {
                        resolvedAuthors.append(hex)
                    }
                }
            }
            if !resolvedAuthors.isEmpty { authors = resolvedAuthors }
        }

        var filter = NostrFilter(
            authors: authors,
            kinds:   kinds,
            since:   sinceTimestamp,
            until:   untilTimestamp,
            limit:   limit,
            tags:    tagFilter,
            search:  searchString
        )

        // If nothing was parsed at all, fall back to raw query search
        if filter.search == nil && !parsed.hasOperators {
            filter.search = rawQuery
        }

        // Route NIP-50 search queries to the dedicated search relay
        if filter.search != nil {
            return await repository.searchEvents(query: filter.search!, limit: limit)
        }
        return await repository.fetchEvents(filters: [filter])
            .filter { kinds.contains($0.kind) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Result Tabs

    private var resultTabBar: some View {
        HStack(spacing: 0) {
            resultTabButton(title: "投稿", count: results.count, tab: 0)
            resultTabButton(title: "ユーザー", count: profileResults.count, tab: 1)
        }
        .padding(.horizontal, NuruSpacing.space4)
        .background(theme.bgPrimary)
    }

    private func resultTabButton(title: String, count: Int, tab: Int) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { activeResultTab = tab }
        } label: {
            VStack(spacing: NuruSpacing.space1) {
                Text("\(title) (\(count))")
                    .font(NuruFont.labelSmall())
                    .foregroundStyle(activeResultTab == tab ? NuruColors.lineGreen : theme.textTertiary)
                    .padding(.vertical, NuruSpacing.space2)
                Rectangle()
                    .fill(activeResultTab == tab ? NuruColors.lineGreen : Color.clear)
                    .frame(height: 2)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Profile Result Row

    private func profileResultRow(_ profile: UserProfile) -> some View {
        Button {
            onProfileTap(profile.pubkey)
        } label: {
            HStack(spacing: NuruSpacing.space3) {
                // Avatar
                AsyncImage(url: profile.picture.flatMap { URL(string: $0) }) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Circle().fill(theme.bgSecondary)
                }
                .frame(width: 44, height: 44)
                .clipShape(Circle())

                // Name + NIP-05 + about
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.displayName ?? profile.name ?? NostrKeyUtils.shortenPubkey(profile.pubkey))
                        .font(NuruFont.bodyMedium())
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)
                    if let nip05 = profile.nip05, !nip05.isEmpty {
                        Text(nip05)
                            .font(NuruFont.bodySmall())
                            .foregroundStyle(NuruColors.lineGreen)
                            .lineLimit(1)
                    }
                    if let about = profile.about, !about.isEmpty {
                        Text(about)
                            .font(NuruFont.bodySmall())
                            .foregroundStyle(theme.textSecondary)
                            .lineLimit(2)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textTertiary)
            }
            .padding(.horizontal, NuruSpacing.space4)
            .padding(.vertical, NuruSpacing.space3)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Persistence

    private func loadRecentSearches() -> [String] {
        UserDefaults.standard.stringArray(forKey: "nurunuru_recent_searches") ?? []
    }

    private func saveRecentSearches(_ list: [String]) {
        UserDefaults.standard.set(list, forKey: "nurunuru_recent_searches")
    }
}
