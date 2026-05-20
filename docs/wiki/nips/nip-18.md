# NIP-18: Reposts

## Summary

NIP-18 reposts use kind `6`. null--nostr also supports quote repost UX using a kind `1` note with `q` tags and/or embedded `nostr:` references.

## Current behavior

- Repost action publishes kind `6` with `e` and `p` tags and optional original event JSON content.
- Repost state is tracked by `myRepostEventId`; tapping repost again deletes the repost event via NIP-09.
- Quote repost is separate from kind `6`: UI opens a quote composer that publishes a text note with quote references.
- Timeline and notification enrichment count/display reposts.

## Platform notes

### Android

- `NostrRepositoryActions.repostPost()` publishes kind `6`.
- `TimelineViewModel` / repository enrichment tracks `myRepostEventId` and undo behavior.
- `PostActions.kt` normal tap reposts; long press opens `QuoteRepostModal.kt`.
- `PostContent.kt` / `PostItem.kt` render repost and quote contexts.

### iOS

- `NostrRepository+Actions.swift` publishes reposts and quote repost notes.
- `QuoteRepostSheet.swift` is the quote composer UI.
- `PostRow.swift` detects quote posts via `q` tags or `nostr:note1...` references.

### Web

- `lib/nostr.js` includes unrepost/delete helpers and repost count helpers.

## Source references

- `android/app/src/main/kotlin/io/nurunuru/app/data/NostrRepositoryActions.kt`
  - `repostPost()`
- `android/app/src/main/kotlin/io/nurunuru/app/ui/components/PostActions.kt`
  - normal repost and quote long-press UI
- `android/app/src/main/kotlin/io/nurunuru/app/ui/components/QuoteRepostModal.kt`
- `ios/NuruNuru/Data/NostrRepository+Actions.swift`
  - repost and quote repost publish paths
- `ios/NuruNuru/Views/Sheets/QuoteRepostSheet.swift`
- `ios/NuruNuru/Views/Components/PostRow.swift`
- `lib/nostr.js`
  - `unrepostEvent()`, `fetchRepostCounts()`

## Related pages

- [[features/timeline]]
- [[ui/post-row]]

## Open questions

- If a dedicated NIP-09 page is added, link undo semantics there rather than relying on this note.
