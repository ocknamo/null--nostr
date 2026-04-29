import SwiftUI

/// カスタム絵文字 mini-app — Android EmojiSettings に寄せた構成
/// - お気に入り絵文字（kind 10030 の emoji タグ）
/// - セット一覧（kind 10030 の a タグ参照先 30030）
/// - セット内ハートでお気に入り登録/解除
/// - セット追加/削除
struct EmojiSettingsView: View {

    let repository: NostrRepository
    let pubkeyHex:  String

    @Environment(\.nuruTheme) private var theme

    @State private var emojiSets:      [EmojiSet]    = []
    @State private var favoriteEmojis: [CustomEmoji] = []
    @State private var isLoading:      Bool          = true

    @State private var query:          String        = ""
    @State private var searchedSets:   [EmojiSet]    = []
    @State private var isSearching:    Bool          = false
    @State private var addingSetId:    String?       = nil
    @State private var removingSetId:  String?       = nil
    @State private var togglingCode:   String?       = nil
    @State private var toastMessage:   String?       = nil

    var body: some View {
        ScrollView {
            VStack(spacing: NuruSpacing.space4) {
                if isLoading {
                    VStack { Spacer(); ProgressView().tint(NuruColors.lineGreen); Spacer() }
                        .frame(maxWidth: .infinity, minHeight: 160)
                } else {
                    card {
                        VStack(alignment: .leading, spacing: NuruSpacing.space3) {
                            Text("カスタム絵文字")
                                .font(NuruFont.bodyLarge())
                                .fontWeight(.bold)
                                .foregroundStyle(theme.textPrimary)

                            favoriteSection

                            if !emojiSets.isEmpty {
                                VStack(spacing: NuruSpacing.space4) {
                                    ForEach(emojiSets) { set in
                                        EmojiSetBrowserSection(
                                            set: set,
                                            favorites: favoriteEmojis,
                                            togglingShortcode: togglingCode,
                                            onToggle: { emoji in
                                                Task { await toggleFavorite(emoji) }
                                            },
                                            onRemove: {
                                                Task { await removeSet(set) }
                                            },
                                            isRemoving: removingSetId == set.id
                                        )
                                    }
                                }
                            } else {
                                Text("セットを追加するとここに絵文字が表示されます")
                                    .font(NuruFont.bodySmall())
                                    .foregroundStyle(theme.textTertiary)
                            }

                            addSetSection
                        }
                    }
                }
            }
            .padding(NuruSpacing.space4)
        }
        .background(theme.bgPrimary)
        .task { await loadEmojiData() }
        .alert("お知らせ", isPresented: Binding(
            get: { toastMessage != nil },
            set: { if !$0 { toastMessage = nil } }
        )) {
            Button("OK", role: .cancel) { toastMessage = nil }
        } message: {
            Text(toastMessage ?? "")
        }
    }

    // MARK: - Sections

    private var favoriteSection: some View {
        VStack(alignment: .leading, spacing: NuruSpacing.space2) {
            HStack(spacing: 6) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.red)
                Text("お気に入り絵文字")
                    .font(NuruFont.bodySmall())
                    .foregroundStyle(theme.textSecondary)
                Text("\(favoriteEmojis.count)個")
                    .font(NuruFont.labelSmall())
                    .foregroundStyle(theme.textTertiary)
            }

            if favoriteEmojis.isEmpty {
                Text("下のセットから ♥ をタップしてお気に入り登録できます")
                    .font(NuruFont.labelSmall())
                    .foregroundStyle(theme.textTertiary)
                    .padding(.top, 2)
            } else {
                emojiGrid(
                    favoriteEmojis,
                    columns: 6,
                    cellSize: 44,
                    onTap: { emoji in Task { await toggleFavorite(emoji) } },
                    showHeartBadge: true
                )
            }
        }
    }

    private var addSetSection: some View {
        VStack(alignment: .leading, spacing: NuruSpacing.space2) {
            Text("新しいセットを追加")
                .font(NuruFont.bodySmall())
                .foregroundStyle(theme.textSecondary)
                .fontWeight(.medium)

            HStack(spacing: NuruSpacing.space2) {
                TextField("検索...", text: $query)
                    .font(NuruFont.bodyMedium())
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, NuruSpacing.space3)
                    .frame(height: 44)
                    .background(theme.bgTertiary)
                    .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusMd))
                    .onSubmit { Task { await searchSets() } }

                Button {
                    Task { await searchSets() }
                } label: {
                    if isSearching {
                        ProgressView().tint(.white)
                    } else {
                        Text("検索")
                            .font(NuruFont.bodySmall())
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 68, height: 44)
                .background(NuruColors.lineGreen)
                .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusMd))
                .buttonStyle(.plain)
                .disabled(isSearching)
            }

            if !searchedSets.isEmpty {
                VStack(spacing: NuruSpacing.space2) {
                    ForEach(searchedSets) { set in
                        HStack(spacing: NuruSpacing.space2) {
                            Text(set.name)
                                .font(NuruFont.bodySmall())
                                .foregroundStyle(theme.textPrimary)
                                .lineLimit(1)
                            Spacer()
                            Button {
                                Task { await addSet(set) }
                            } label: {
                                Text(addingSetId == set.id ? "追加中..." : "追加")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(NuruColors.lineGreen)
                            }
                            .buttonStyle(.plain)
                            .disabled(addingSetId != nil)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Data actions

    private func loadEmojiData() async {
        isLoading = true
        async let refsTask = repository.fetchEmojiSets(pubkeyHex: pubkeyHex)
        async let favTask = repository.fetchFavoriteEmojis(pubkeyHex: pubkeyHex)
        emojiSets = await refsTask
        favoriteEmojis = await favTask
        isLoading = false
    }

    private func toggleFavorite(_ emoji: CustomEmoji) async {
        guard togglingCode == nil else { return }
        togglingCode = emoji.shortcode
        defer { togglingCode = nil }

        var next = favoriteEmojis
        if let idx = next.firstIndex(where: { $0.shortcode == emoji.shortcode }) {
            next.remove(at: idx)
        } else {
            next.append(emoji)
        }

        do {
            try await repository.updateEmojiListFavoritesAndSets(
                pubkeyHex: pubkeyHex,
                favorites: next,
                sets: emojiSets
            )
            favoriteEmojis = next
        } catch {
            toastMessage = "お気に入り更新に失敗: \(error.localizedDescription)"
        }
    }

    private func addSet(_ set: EmojiSet) async {
        guard addingSetId == nil else { return }
        addingSetId = set.id
        defer { addingSetId = nil }

        do {
            var nextSets = emojiSets
            nextSets.append(set)
            try await repository.updateEmojiListFavoritesAndSets(
                pubkeyHex: pubkeyHex,
                favorites: favoriteEmojis,
                sets: nextSets
            )
            emojiSets = nextSets
            searchedSets.removeAll { $0.id == set.id }
            toastMessage = "絵文字セットを登録しました"
        } catch {
            toastMessage = "登録に失敗: \(error.localizedDescription)"
        }
    }

    private func removeSet(_ set: EmojiSet) async {
        guard removingSetId == nil else { return }
        removingSetId = set.id
        defer { removingSetId = nil }

        do {
            let removedCodes = Set(set.emojis.map { $0.shortcode })
            let nextFav = favoriteEmojis.filter { !removedCodes.contains($0.shortcode) }
            let nextSets = emojiSets.filter { $0.id != set.id }
            try await repository.updateEmojiListFavoritesAndSets(
                pubkeyHex: pubkeyHex,
                favorites: nextFav,
                sets: nextSets
            )
            favoriteEmojis = nextFav
            emojiSets = nextSets
            toastMessage = "絵文字セットを削除しました"
        } catch {
            toastMessage = "削除に失敗: \(error.localizedDescription)"
        }
    }

    private func searchSets() async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else {
            searchedSets = []
            return
        }
        isSearching = true
        let all = await repository.searchEmojiSets(query: q)
        let current = Set(emojiSets.map { $0.id })
        searchedSets = all.filter { !current.contains($0.id) }
        isSearching = false
    }

    // MARK: - UI helpers

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(NuruSpacing.space4)
            .background(
                RoundedRectangle(cornerRadius: NuruSpacing.radiusXl)
                    .fill(theme.bgSecondary)
            )
    }

    @ViewBuilder
    private func emojiGrid(
        _ emojis: [CustomEmoji],
        columns: Int,
        cellSize: CGFloat,
        onTap: @escaping (CustomEmoji) -> Void,
        showHeartBadge: Bool
    ) -> some View {
        let rows = emojis.chunked(into: columns)
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 6) {
                    ForEach(row) { emoji in
                        Button { onTap(emoji) } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(theme.bgTertiary)
                                    .frame(width: cellSize, height: cellSize)

                                if let url = URL(string: emoji.url) {
                                    AnimatedRemoteImage(url: url) {
                                        Color.clear
                                    }
                                    .frame(width: cellSize - 12, height: cellSize - 12)
                                }

                                if showHeartBadge {
                                    VStack {
                                        HStack {
                                            Spacer()
                                            Circle()
                                                .fill(Color.red)
                                                .frame(width: 14, height: 14)
                                                .overlay(
                                                    Image(systemName: "heart.fill")
                                                        .font(.system(size: 8))
                                                        .foregroundStyle(.white)
                                                )
                                        }
                                        Spacer()
                                    }
                                    .frame(width: cellSize, height: cellSize)
                                }
                            }
                            .frame(width: cellSize, height: cellSize)
                        }
                        .buttonStyle(.plain)
                    }
                    if row.count < columns {
                        ForEach(0..<(columns - row.count), id: \.self) { _ in
                            Color.clear.frame(width: cellSize, height: cellSize)
                        }
                    }
                }
            }
        }
    }
}

private struct EmojiSetBrowserSection: View {
    let set: EmojiSet
    let favorites: [CustomEmoji]
    let togglingShortcode: String?
    let onToggle: (CustomEmoji) -> Void
    let onRemove: () -> Void
    let isRemoving: Bool

    @Environment(\.nuruTheme) private var theme
    @State private var expanded = false

    var body: some View {
        let favoriteCodes = Set(favorites.map { $0.shortcode })
        let display = expanded ? set.emojis : Array(set.emojis.prefix(18))

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(set.name)
                    .font(NuruFont.bodySmall())
                    .foregroundStyle(theme.textSecondary)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Spacer()
                let favCount = set.emojis.filter { favoriteCodes.contains($0.shortcode) }.count
                if favCount > 0 {
                    Text("♥ \(favCount)")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.red)
                }
                Button {
                    expanded.toggle()
                } label: {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.textTertiary)
                }
                .buttonStyle(.plain)

                Button(role: .destructive, action: onRemove) {
                    Text(isRemoving ? "..." : "削除")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .disabled(isRemoving)
            }

            let rows = display.chunked(into: 6)
            VStack(spacing: 6) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 6) {
                        ForEach(row) { emoji in
                            let isFav = favoriteCodes.contains(emoji.shortcode)
                            let busy = togglingShortcode == emoji.shortcode
                            Button {
                                onToggle(emoji)
                            } label: {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(isFav ? NuruColors.lineGreen.opacity(0.12) : theme.bgTertiary)
                                        .frame(width: 44, height: 44)

                                    if busy {
                                        ProgressView().tint(NuruColors.lineGreen)
                                    } else if let url = URL(string: emoji.url) {
                                        AnimatedRemoteImage(url: url) {
                                            Color.clear
                                        }
                                        .frame(width: 30, height: 30)
                                    }

                                    VStack {
                                        HStack {
                                            Spacer()
                                            Image(systemName: isFav ? "heart.fill" : "heart")
                                                .font(.system(size: 11))
                                                .foregroundStyle(isFav ? Color.red : theme.textTertiary.opacity(0.5))
                                        }
                                        Spacer()
                                    }
                                    .frame(width: 44, height: 44)
                                }
                                .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.plain)
                            .disabled(busy)
                        }
                        if row.count < 6 {
                            ForEach(0..<(6 - row.count), id: \.self) { _ in
                                Color.clear.frame(width: 44, height: 44)
                            }
                        }
                    }
                }
            }

            if !expanded && set.emojis.count > 18 {
                Button {
                    expanded = true
                } label: {
                    Text("残り \(set.emojis.count - 18) 個を表示")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textTertiary)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [] }
        return stride(from: 0, to: count, by: size).map { i in
            Array(self[i..<Swift.min(i + size, count)])
        }
    }
}
