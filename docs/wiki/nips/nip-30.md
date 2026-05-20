# NIP-30: Custom Emoji

## Summary

Custom emoji support uses user emoji lists (`kind 10030`) and emoji sets (`kind 30030`). It is used in post rendering, emoji pickers, custom reactions, and settings.

## Current behavior

- User emoji list kind `10030` can contain direct `emoji` tags and `a` tags referencing emoji sets.
- Emoji set kind `30030` is fetched by `30030:<pubkey>:<d>` references.
- Android and iOS can fetch, cache, search, add, remove, and publish emoji-list references.
- Reaction picker uses the same emoji data to publish NIP-25 custom emoji reactions.
- Post content rendering resolves custom emoji shortcodes where platform code supports it.

## Platform notes

### Android

- `EmojiPicker.kt` defines shared in-memory cache and fetch helpers used by `ReactionEmojiPicker.kt`.
- `NostrRepositoryProfiles.kt` fetches emoji lists/sets, searches emoji sets, and updates kind `10030`.
- `EmojiSettings.kt` provides settings UI for emoji lists/sets.

### iOS

- `NostrRepository+Profiles.swift` has `fetchEmojiSets`, add/remove set reference, favorite emoji, save emoji list, and search helpers.
- `NostrCache.swift` has NIP-30 emoji cache.
- `EmojiSettingsView.swift` and `ReactionEmojiPicker.swift` expose UI.

### Web

- Web reaction/content support should be checked per component before claiming full UI parity; core Nostr helpers include generic event publishing.

### Rust

- `engine.rs` and `filters.rs` include custom emoji helpers/filters for kind `10030`.

## Source references

- `android/app/src/main/kotlin/io/nurunuru/app/ui/components/EmojiPicker.kt`
- `android/app/src/main/kotlin/io/nurunuru/app/ui/components/ReactionEmojiPicker.kt`
- `android/app/src/main/kotlin/io/nurunuru/app/ui/miniapps/EmojiSettings.kt`
- `android/app/src/main/kotlin/io/nurunuru/app/data/NostrRepositoryProfiles.kt`
- `ios/NuruNuru/Data/NostrRepository+Profiles.swift`
- `ios/NuruNuru/Data/NostrCache.swift`
- `ios/NuruNuru/Views/MiniApps/EmojiSettingsView.swift`
- `ios/NuruNuru/Views/Components/ReactionEmojiPicker.swift`
- `rust-engine/nurunuru-core/src/engine.rs`
- `rust-engine/nurunuru-core/src/filters.rs`

## Related pages

- [[nip-25]]
- [[nips/README]]
