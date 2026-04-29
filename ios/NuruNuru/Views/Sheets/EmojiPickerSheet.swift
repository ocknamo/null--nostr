import SwiftUI

/// Custom emoji picker — NIP-30.
/// Fetches kind 10030 (user emoji list) and 30030 (emoji sets).
/// Mirrors Android EmojiPicker.kt.
struct EmojiPickerSheet: View {

    let repository:  NostrRepository
    let pubkeyHex:   String
    /// true: Android PostModal と同じく、通常時は kind-10030 の個別登録(emojiタグ)のみ表示。
    /// 検索時だけ登録済みセットも横断検索する。
    var individualOnly: Bool = false
    var onSelect:    (CustomEmoji) -> Void = { _ in }

    @Environment(\.dismiss)    private var dismiss
    @Environment(\.nuruTheme) private var theme

    @State private var favoriteEmojis: [CustomEmoji] = []
    @State private var emojiSets:      [EmojiSet]    = []
    @State private var isLoading:      Bool          = true
    @State private var searchQuery:    String        = ""
    @State private var selectedTab:    String        = "all"

    private var searchPool: [CustomEmoji] {
        dedupeEmojis(favoriteEmojis + emojiSets.flatMap { $0.emojis })
    }

    private var allEmojis: [CustomEmoji] {
        searchPool
    }

    private var filteredEmojis: [CustomEmoji] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty {
            // Android: individualOnly=true でも検索時は全セット横断
            return searchPool.filter { $0.shortcode.localizedCaseInsensitiveContains(q) }
        }

        if individualOnly {
            // Android PostModal: 検索なしでは個別登録(emojiタグ)だけ表示
            return favoriteEmojis
        }

        if selectedTab == "all" {
            return allEmojis
        } else if selectedTab == "user" {
            return favoriteEmojis
        } else {
            return emojiSets.first(where: { $0.id == selectedTab })?.emojis ?? []
        }
    }

    private var tabs: [(id: String, label: String)] {
        guard !individualOnly else { return [] }
        var out: [(String, String)] = [("all", "すべて")]
        if !favoriteEmojis.isEmpty { out.append(("user", "個別")) }
        out.append(contentsOf: emojiSets.map { ($0.id, $0.name) })
        return out
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetNavBar(title: "絵文字を選択", onDismiss: { dismiss() }) {
                Color.clear.frame(width: 40, height: 40)
            }

            // Search
            HStack(spacing: NuruSpacing.space2) {
                Image(systemName: "magnifyingglass").foregroundStyle(theme.textTertiary)
                TextField("絵文字を検索", text: $searchQuery)
                    .font(NuruFont.bodyMedium())
                    .foregroundStyle(theme.textPrimary)
                    .autocorrectionDisabled()
            }
            .padding(NuruSpacing.space3)
            .background(theme.bgSecondary)
            .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusMd))
            .padding(.horizontal, NuruSpacing.space4)
            .padding(.vertical, NuruSpacing.space2)

            if isLoading {
                Spacer()
                ProgressView().tint(NuruColors.lineGreen)
                Spacer()
            } else if searchPool.isEmpty {
                Spacer()
                VStack(spacing: NuruSpacing.space3) {
                    Image(systemName: "face.smiling")
                        .font(.system(size: 36))
                        .foregroundStyle(theme.textTertiary)
                    Text("カスタム絵文字がありません")
                        .font(NuruFont.bodyMedium())
                        .foregroundStyle(theme.textTertiary)
                    Text("ミニアプリ → カスタム絵文字で追加できます")
                        .font(NuruFont.bodySmall())
                        .foregroundStyle(theme.textTertiary)
                        .multilineTextAlignment(.center)
                }
                Spacer()
            } else {
                // Set tabs
                if searchQuery.isEmpty && tabs.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: NuruSpacing.space2) {
                            ForEach(tabs.indices, id: \.self) { idx in
                                let tab = tabs[idx]
                                tabChip(tab.id, tab.label)
                            }
                        }
                        .padding(.horizontal, NuruSpacing.space4)
                        .padding(.vertical, NuruSpacing.space2)
                    }
                    Divider().background(theme.borderColor)
                }

                // Emoji grid
                if filteredEmojis.isEmpty {
                    Spacer()
                    Text("「\(searchQuery)」は見つかりません")
                        .font(NuruFont.bodyMedium())
                        .foregroundStyle(theme.textTertiary)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6),
                            spacing: 8
                        ) {
                            ForEach(filteredEmojis) { emoji in
                                EmojiCell(emoji: emoji) {
                                    onSelect(emoji)
                                    dismiss()
                                }
                            }
                        }
                        .padding(NuruSpacing.space4)
                    }
                }
            }
        }
        .background(theme.bgPrimary.ignoresSafeArea())
        .task { await loadEmojis() }
    }

    private func tabChip(_ id: String, _ label: String) -> some View {
        let selected = selectedTab == id
        return Button { selectedTab = id } label: {
            Text(label)
                .font(.system(size: 12, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? .white : theme.textPrimary)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(selected ? NuruColors.lineGreen : theme.bgSecondary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func loadEmojis() async {
        isLoading = true
        async let favTask = repository.fetchFavoriteEmojis(pubkeyHex: pubkeyHex)
        async let setsTask = repository.fetchEmojiSets(pubkeyHex: pubkeyHex)
        favoriteEmojis = await favTask
        emojiSets = await setsTask
        isLoading = false
    }

    private func dedupeEmojis(_ emojis: [CustomEmoji]) -> [CustomEmoji] {
        var seen = Set<String>()
        return emojis.filter { seen.insert($0.shortcode).inserted }
    }
}

// MARK: - Emoji Cell

private struct EmojiCell: View {
    let emoji:  CustomEmoji
    let onTap:  () -> Void
    @Environment(\.nuruTheme) private var theme

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                if let url = URL(string: emoji.url) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().scaledToFit()
                                .frame(width: 36, height: 36)
                        default:
                            RoundedRectangle(cornerRadius: 4)
                                .fill(theme.bgSecondary)
                                .frame(width: 36, height: 36)
                        }
                    }
                } else {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(theme.bgSecondary)
                        .frame(width: 36, height: 36)
                }
                Text(":\(emoji.shortcode):")
                    .font(.system(size: 9))
                    .foregroundStyle(theme.textTertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(theme.bgSecondary)
            .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusSm))
        }
        .buttonStyle(.plain)
    }
}

