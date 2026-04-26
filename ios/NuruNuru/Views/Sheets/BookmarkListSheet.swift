import SwiftUI

/// ブックマーク一覧シート (Kind 10003, NIP-51)。
/// Android の BookmarkListModal.kt に相当。
///
/// ブックマーク済み投稿を `PostRow` で表示し、各行から削除できる。
struct BookmarkListSheet: View {

    let repository:   NostrRepository
    let myPubkeyHex:  String
    var onProfileTap: (String) -> Void = { _ in }

    @Environment(\.dismiss)    private var dismiss
    @Environment(\.nuruTheme) private var theme

    @State private var posts:       [ScoredPost] = []
    @State private var isLoading:   Bool = true
    @State private var isRefreshing: Bool = false
    /// 削除処理中のイベント ID セット（楽観的 UI: 行をグレーアウト）
    @State private var removingIds: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            SheetNavBar(title: "ブックマーク", onDismiss: { dismiss() }) {
                Color.clear.frame(width: 40, height: 40)
            }

            if isLoading {
                Spacer()
                ProgressView().tint(NuruColors.lineGreen)
                Spacer()
            } else if posts.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(posts) { post in
                            postRow(post)
                        }
                    }
                }
                .refreshable {
                    isRefreshing = true
                    await loadBookmarks()
                    isRefreshing = false
                }
            }
        }
        .background(theme.bgPrimary.ignoresSafeArea())
        .task { await loadBookmarks() }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: NuruSpacing.space3) {
            Spacer()
            Image(systemName: NuruIcons.bookmark(filled: false))
                .font(.system(size: 48))
                .foregroundStyle(theme.textTertiary)
            Text("ブックマークがありません")
                .font(NuruFont.bodyMedium())
                .foregroundStyle(theme.textSecondary)
            Spacer()
        }
    }

    // MARK: - Post Row

    @ViewBuilder
    private func postRow(_ post: ScoredPost) -> some View {
        PostRow(
            post:         post,
            repository:   repository,
            onLike:       {},
            onRepost:     {},
            onBookmark: {
                await removeBookmark(post)
            },
            onProfileTap: { pubkey in
                dismiss()
                onProfileTap(pubkey)
            }
        )
        .opacity(removingIds.contains(post.event.id) ? 0.4 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: removingIds.contains(post.event.id))
    }

    // MARK: - Data

    private func loadBookmarks() async {
        isLoading = true
        // fetchBookmarks は enrichPosts 済み（いいね数・リポスト数・Zap 額付与）
        let fetched = await repository.fetchBookmarks(pubkeyHex: myPubkeyHex)
        // isBookmarked フラグをセット（一覧内なので常に true）
        fetched.forEach { $0.isBookmarked = true }
        posts     = fetched
        isLoading = false
    }

    private func removeBookmark(_ post: ScoredPost) async {
        let eventId = post.event.id
        // 楽観的 UI: 即座にグレーアウト
        removingIds.insert(eventId)
        do {
            try await repository.removeBookmark(pubkeyHex: myPubkeyHex, eventId: eventId)
            // 削除成功 → 行を消す
            withAnimation {
                posts.removeAll { $0.event.id == eventId }
            }
        } catch {
            // 失敗 → グレーアウトを戻す
            removingIds.remove(eventId)
        }
    }
}
