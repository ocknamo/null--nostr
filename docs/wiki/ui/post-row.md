# Post Row / Post Rendering

## Summary

Post rendering covers profile header, text/link parsing, media extraction, embedded Nostr cards, long-form posts, short videos, action row, and reply/quote context.

## Current behavior

- Android `PostItem.kt` / `PostContent.kt` render normal posts, repost headers, reply context, media grids, and embedded `nostr:` content cards.
- iOS `PostRow.swift` / `PostContent.swift` mirror the same broad responsibilities.
- `PostActions` is a child component and may include bookmark in addition to like / repost / zap.
- Long-form articles use dedicated `LongFormPostItem` components. Article readers render Markdown and resolve Nostr references (`nostr:note1...`, `nostr:nevent1...`, `nostr:naddr1...`, `nostr:npub1...`, `nostr:nprofile1...`; native readers also accept bare bech32 forms) into embedded cards/mentions instead of leaving them as plain text links.
- Media extraction uses content URLs and, on iOS, NIP-92 `imeta` tags.
- Quote reposts use `q` tags and/or `nostr:note1...` references.

## Platform notes

### Android

- `PostItem.kt` should use `remember(post.event.id)` for performance.
- `PostContent.kt` parses links, hashtags, custom emoji shortcodes, and Nostr bech32 references.
- `EmbeddedNostrContent` handles Nostr cards, including references emitted from long-form Markdown paragraphs/list items.

### iOS

- `PostRow.swift` detects quote posts via `q` tags or `nostr:note1...` patterns.
- `PostContent.swift` detects replies using NIP-10 marker tags and renders embedded cards.
- `LongFormPostItem.swift` renders NIP-23 articles and passes repository context into `MarkdownContent` so embedded Nostr cards can be resolved inside article bodies.

## Source references

- `android/app/src/main/kotlin/io/nurunuru/app/ui/components/PostItem.kt`
- `android/app/src/main/kotlin/io/nurunuru/app/ui/components/PostContent.kt`
- `android/app/src/main/kotlin/io/nurunuru/app/ui/components/PostActions.kt`
- `ios/NuruNuru/Views/Components/PostRow.swift`
- `ios/NuruNuru/Views/Components/PostContent.swift`
- `ios/NuruNuru/Views/Components/PostActions.swift`
- `ios/NuruNuru/Views/Components/LongFormPostItem.swift`
- `android/app/src/main/kotlin/io/nurunuru/app/ui/components/MarkdownContent.kt`
- `ios/NuruNuru/Views/Components/MarkdownContent.swift`
- `components/LongFormPostItem.js`

## Related pages

- [[features/timeline]]
- [[ui/android-ios-sync]]
- [[nips/README]]
