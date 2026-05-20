# Timeline

## Summary

Timeline は投稿一覧表示とリアクション状態を扱う主要機能です。Android では `TimelineViewModel` が フォロー / おすすめ タブを駆動します。

## Current behavior

- Timeline fetches/rendering include text notes, reposts, long-form posts, and short video/event kinds where platform code supports them.
- 投稿の like / repost 状態は `ScoredPost` の `myLikeEventId` / `myRepostEventId` で追跡する。
- 2 回目の like / repost tap は NIP-09 delete event により undo し、counter を減らす。
- Android の timeline では entrance animation を避ける。
- iOS では `.id(post.event.id)` を使い、stable identity を維持する。

## Platform notes

### Android

- `TimelineViewModel` が フォロー / おすすめ を担当。
- `NostrRepositoryTimeline.kt` fetches `TEXT_NOTE`, `VIDEO_LOOP`, `LONG_FORM`, and `REPOST` in fast timeline paths.
- `NostrRepository.enrichPosts()` が自分のリアクション event id を付与する。
- `PostItem.kt` では `remember(post.event.id)` を使う。

### iOS

- Timeline list では stable identity と no entrance animation を守る。
- Android との UI copy / icon / button set の同期が重要。

## Source references

- `android/app/src/main/kotlin/io/nurunuru/app/data/NostrRepository.kt`
- `android/app/src/main/kotlin/io/nurunuru/app/viewmodel/TimelineViewModel.kt`
- `ios/NuruNuru/ViewModels/TimelineViewModel.swift`
- `ios/GUARDRAILS.md`

## Related pages

- [[ui/android-ios-sync]]
- [[features/notifications]]
- [[ui/post-row]]
