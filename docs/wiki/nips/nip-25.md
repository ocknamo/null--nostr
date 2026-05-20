# NIP-25: Reactions

## Summary

NIP-25 reactions use kind `7`. null--nostr supports normal likes, custom emoji reactions, reaction counts, notifications, and undo by deleting the reaction event.

## Current behavior

- Like publishes a kind `7` reaction with content `+` by default.
- Custom emoji reactions use content like `:shortcode:` and an `emoji` tag with the image URL.
- Reaction counts are fetched by querying kind `7` events tagged with target event IDs.
- The current user's reaction event ID is tracked as `myLikeEventId`; tapping again deletes that reaction event via NIP-09.
- Long press on like opens custom reaction picker on native post items.
- Notifications distinguish normal reactions and custom emoji reactions.

## Platform notes

### Android

- `NostrRepositoryActions.likePost()` creates reactions through Rust when available and supports custom emoji URL tags.
- `ReactionEmojiPicker.kt` shares emoji cache/fetch behavior with `EmojiPicker.kt`.
- `NostrRepositoryReactions.kt` fetches reaction counts.
- `NostrRepository.enrichPosts()` computes `myLikeEventId`.
- `NotificationModal.kt` and `NostrRepositoryNotifications.kt` include reaction/emoji reaction notifications.

### iOS

- `NostrRepository+Actions.publishReaction()` publishes kind `7` and adds NIP-30 emoji tags when `emojiUrl` is provided.
- `NostrRepository+Reactions.swift` fetches reaction counts.
- `NostrRepository+Timeline.swift` enriches posts with reaction state and current-user reaction IDs.
- `ReactionEmojiPicker.swift` provides custom reaction UI.

### Web

- `lib/nostr.js` contains reaction-related helpers indirectly through event publish/delete and enrichment helpers.

### Rust

- `engine.rs` has `react_to_event()` for kind `7`.
- `filters.rs` has `reaction_filter()`.
- FFI exposes `reactToEvent` / reaction creation paths.

## Source references

- `android/app/src/main/kotlin/io/nurunuru/app/data/NostrRepositoryActions.kt`
- `android/app/src/main/kotlin/io/nurunuru/app/data/NostrRepositoryReactions.kt`
- `android/app/src/main/kotlin/io/nurunuru/app/data/NostrRepository.kt`
- `android/app/src/main/kotlin/io/nurunuru/app/ui/components/ReactionEmojiPicker.kt`
- `ios/NuruNuru/Data/NostrRepository+Actions.swift`
- `ios/NuruNuru/Data/NostrRepository+Reactions.swift`
- `ios/NuruNuru/Data/NostrRepository+Timeline.swift`
- `ios/NuruNuru/Views/Components/ReactionEmojiPicker.swift`
- `rust-engine/nurunuru-core/src/engine.rs`
- `rust-engine/nurunuru-core/src/filters.rs`
- `rust-engine/nurunuru-ffi/src/lib.rs`

## Related pages

- [[nip-30]]
- [[features/timeline]]
- [[features/notifications]]
