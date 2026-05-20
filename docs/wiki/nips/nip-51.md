# NIP-51: Lists

## Summary

null--nostr uses NIP-51-style lists for mute lists, bookmarks, and emoji lists. The implementation is replaceable-event oriented: fetch latest list, modify tags, republish.

## Current behavior

| Kind | Use in project |
|---|---|
| `10000` | Mute list. Public tags are preserved; encrypted/private content is supported where signer/encryption path allows. |
| `10003` | Bookmarks. Stores bookmarked event IDs in `e` tags and is republished on add/remove. |
| `10030` | Emoji list. Stores direct emoji tags and `a` references to kind `30030` emoji sets. |

## Platform notes

### Android

- `NostrRepositoryActions.kt` fetches, mutates, encrypts/decrypts where possible, and republishes kind `10000` mute lists.
- `NostrRepositoryBookmarks.kt` handles kind `10003` bookmark fetch/add/remove.
- `NostrRepositoryProfiles.kt` handles kind `10030` emoji-list fetch/update.
- Cache settings expose TTLs for mute lists and emoji data.

### iOS

- `NostrRepository+Actions.swift` handles kind `10000` mute-list fetch/update/mute/unmute.
- `NostrRepository+Bookmarks.swift` handles kind `10003` bookmarks.
- `NostrRepository+Profiles.swift` handles kind `10030` emoji lists.
- `HomeViewModel.swift` and `TimelineViewModel.swift` expose bookmark/mute actions.

### Web

- `lib/nostr.js` includes mute-list helpers and bookmark helpers.
- Web comments group NIP-51 bookmarks with Zap totals/repost counts in timeline utilities.

### Rust

- `filters.rs` has mute-list and emoji-list filters.
- FFI comments include kind `10000` in replaceable event handling coverage.

## Source references

- `android/app/src/main/kotlin/io/nurunuru/app/data/NostrRepositoryActions.kt`
- `android/app/src/main/kotlin/io/nurunuru/app/data/NostrRepositoryBookmarks.kt`
- `android/app/src/main/kotlin/io/nurunuru/app/data/NostrRepositoryProfiles.kt`
- `ios/NuruNuru/Data/NostrRepository+Actions.swift`
- `ios/NuruNuru/Data/NostrRepository+Bookmarks.swift`
- `ios/NuruNuru/Data/NostrRepository+Profiles.swift`
- `lib/nostr.js`
- `rust-engine/nurunuru-core/src/filters.rs`
- `rust-engine/nurunuru-ffi/src/lib.rs`

## Related pages

- [[nip-30]]
- [[features/timeline]]
- [[nips/README]]
