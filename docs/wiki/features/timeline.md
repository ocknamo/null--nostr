# Timeline

## Summary

Timeline は投稿一覧表示とリアクション状態を扱う主要機能です。Android では `TimelineViewModel` が フォロー / おすすめ タブを駆動します。

## Current behavior

- Regular timelines fetch/render text notes, long-form posts, and Kind 6 reposts. Short-video events (kind 34236 / NIP-71) are kept out of normal timelines and belong to the dedicated ろくなな surface.
- Timeline is network-first for event pages: stale event cache must not be rendered as the normal first paint or silently mixed into the time axis.
- Timeline event cache is fallback-only for offline / hard relay failure cases; profile/avatar/follow-list caches remain cache-first.
- Timeline refresh is cache-safe: transient empty relay responses must not replace an already-visible non-empty timeline or overwrite healthy cached timelines.
- Pagination cursors track the oldest post in the fresh contiguous head, not the oldest stale cached post, so users can fill gaps between new posts and old cache.
- Older-page fetches are bounded to a 6-hour window and return raw posts with cached profiles first; engagement/profile enrichment runs after render. Empty pagination windows are skipped across several bounded windows, and a single empty/failed page no longer permanently disables further old-post loading.
- Follow pagination uses active-author discovery plus smaller author chunks instead of one huge 500-author REQ.
- Follow pagination also races the default connected-relay fetch with NIP-65 outbox relay-hinted fetches for active authors.
- Selected relay timelines also support older-page pagination using the same bounded `until` window.
- Recent reposts are positioned by repost time and carry repostedBy, so follow timelines can show followed-user repost provenance instead of looking like unfollowed direct posts.
- Selected relay timelines use the same repost-time normalization as all-relay/follow timelines.
- Timeline supports infinite-scroll pagination for older global/following notes using NIP-01 `until` filters.
- 投稿の like / repost 状態は `ScoredPost` の `myLikeEventId` / `myRepostEventId` で追跡する。
- 2 回目の like / repost tap は NIP-09 delete event により undo し、counter を減らす。
- Android の timeline では entrance animation を避ける。
- iOS では `.id(post.event.id)` を使い、stable identity を維持する。

## Platform notes

### Android

- `TimelineViewModel` が フォロー / おすすめ を担当。
- `TimelineViewModel.loadFollowingTimeline()` and `loadGlobalTimeline()` keep existing posts when a refresh returns an empty list and the UI already has posts.
- NostrRepositoryTimeline.kt fetches TEXT_NOTE, LONG_FORM, and REPOST in regular timeline paths; VIDEO_LOOP is excluded from normal timelines.
- `NostrRepositoryTimeline.kt` falls back to cached nostrdb follow-timeline data when Rust/relay fetch returns no events, the follow list is temporarily empty, or parsed events are empty.
- `TimelineScreen.kt` triggers load-more near the bottom of `LazyColumn`; `TimelineViewModel.loadMore()` appends deduped older pages.
- `NostrRepository.enrichPosts()` が自分のリアクション event id を付与する。
- `PostItem.kt` では `remember(post.event.id)` を使う。

### iOS

- Timeline list では stable identity と no entrance animation を守る。
- `NostrRepository+Timeline.swift` writes timeline cache only for non-empty network results; full following fetch falls back to cached following events when relays return empty.
- `TimelineView` triggers load-more from row `onAppear`; `TimelineViewModel` appends deduped older pages.
- Android との UI copy / icon / button set の同期が重要。

## Source references

- `android/app/src/main/kotlin/io/nurunuru/app/data/NostrRepository.kt`
- `android/app/src/main/kotlin/io/nurunuru/app/viewmodel/TimelineViewModel.kt`
- `android/app/src/main/kotlin/io/nurunuru/app/ui/screens/TimelineScreen.kt`
- `ios/NuruNuru/ViewModels/TimelineViewModel.swift`
- `ios/NuruNuru/Views/Screens/TimelineView.swift`
- `ios/NuruNuru/Data/NostrRepository+Timeline.swift`
- `rust-engine/nurunuru-core/src/engine.rs`
- `ios/GUARDRAILS.md`

## Related pages

- [[ui/android-ios-sync]]
- [[features/notifications]]
- [[ui/post-row]]
