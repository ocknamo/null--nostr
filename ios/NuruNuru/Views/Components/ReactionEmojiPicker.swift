import SwiftUI

// MARK: - Reaction Selection

struct ReactionSelection {
    enum Kind { case custom, unicode }
    let kind:      Kind
    let shortcode: String
    let url:       String
    let emoji:     String

    static func custom(shortcode: String, url: String) -> ReactionSelection {
        ReactionSelection(kind: .custom, shortcode: shortcode, url: url, emoji: "")
    }
    static func unicode(_ emoji: String) -> ReactionSelection {
        ReactionSelection(kind: .unicode, shortcode: "", url: "", emoji: emoji)
    }
}

// MARK: - ReactionEmojiPicker

/// NIP-30 custom emoji reaction picker — bottom sheet.
/// Mirrors Android ReactionEmojiPicker composable.
/// Usage: .sheet(isPresented:) { ReactionEmojiPicker(...) }
struct ReactionEmojiPicker: View {
    let pubkeyHex:  String
    let repository: NostrRepository
    let onSelect:   (ReactionSelection) -> Void
    let onDismiss:  () -> Void

    @State private var emojis:    [CustomEmoji] = []
    @State private var isLoading: Bool          = true
    @State private var searchQuery: String      = ""
    @Environment(\.nuruTheme) private var theme

    private var filtered: [CustomEmoji] {
        searchQuery.isEmpty ? emojis : emojis.filter { $0.shortcode.localizedCaseInsensitiveContains(searchQuery) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Drag handle
            Capsule()
                .fill(theme.textTertiary.opacity(0.4))
                .frame(width: 40, height: 4)
                .padding(.top, NuruSpacing.space3)
                .padding(.bottom, 4)

            // Header
            Text("リアクション")
                .font(NuruFont.bodyMedium())
                .fontWeight(.semibold)
                .foregroundStyle(theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, NuruSpacing.space4)
                .padding(.vertical, NuruSpacing.space2)

            // Search bar
            HStack(spacing: NuruSpacing.space2) {
                Image(systemName: NuruIcons.search)
                    .font(.system(size: 14))
                    .foregroundStyle(theme.textTertiary)
                TextField("カスタム絵文字を検索...", text: $searchQuery)
                    .font(NuruFont.bodySmall())
                    .foregroundStyle(theme.textPrimary)
            }
            .padding(NuruSpacing.space3)
            .background(theme.bgSecondary)
            .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusMd))
            .padding(.horizontal, NuruSpacing.space4)
            .padding(.bottom, NuruSpacing.space2)

            // Emoji grid
            ZStack {
                if isLoading {
                    ProgressView()
                        .tint(NuruColors.lineGreen)
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else if emojis.isEmpty {
                    VStack(spacing: NuruSpacing.space2) {
                        Text("お気に入り絵文字がありません")
                            .font(NuruFont.bodySmall())
                            .foregroundStyle(theme.textTertiary)
                        Text("ミニアプリのカスタム絵文字設定から登録できます")
                            .font(NuruFont.labelSmall())
                            .foregroundStyle(theme.textTertiary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 120)
                } else if filtered.isEmpty {
                    Text("該当する絵文字がありません")
                        .font(NuruFont.bodySmall())
                        .foregroundStyle(theme.textTertiary)
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    // 8-column grid
                    let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 8)
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 4) {
                            ForEach(filtered) { emoji in
                                Button {
                                    onSelect(.custom(shortcode: emoji.shortcode, url: emoji.url))
                                } label: {
                                    AnimatedRemoteImage(url: URL(string: emoji.url)) {
                                        Color.clear
                                    }
                                    .aspectRatio(1, contentMode: .fit)
                                    .padding(4)
                                }
                                .buttonStyle(.plain)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                        .padding(.horizontal, NuruSpacing.space4)
                    }
                    .frame(maxHeight: 250)
                }
            }

            Spacer(minLength: NuruSpacing.space4)
        }
        .background(theme.bgPrimary)
        .task(id: pubkeyHex) {
            await loadEmojis()
        }
    }

    private func loadEmojis() async {
        isLoading = true
        // Android同様: リアクション長押しは kind10030 の個別お気に入りのみ表示
        emojis = await repository.fetchFavoriteEmojis(pubkeyHex: pubkeyHex)
        isLoading = false
    }
}
