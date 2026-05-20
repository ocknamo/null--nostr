# NIP-58: Badges

## Summary

NIP-58 badges are supported through badge awards, badge definitions, and profile badge lists.

## Current behavior

| Kind | Use in project |
|---|---|
| `8` | Badge award event. |
| `30009` | Badge definition. |
| `30008` | Profile badges list. |

- Profiles can fetch displayed profile badges from kind `30008` and resolve referenced kind `30009` definitions.
- Awarded badges are fetched from kind `8` events.
- Users can update profile badges by publishing kind `30008` with `a` references to badge definitions and associated award event IDs.
- Notifications include badge award events.
- Badge data is cached to avoid repeated relay fetches.

## Platform notes

### Android

- `NostrRepositoryProfiles.kt` fetches profile badges, awarded badges, resolves definitions, caches badge info, and updates profile badges.
- `BadgeSettings.kt` provides badge management UI.
- `NostrRepositoryNotifications.kt` and `NotificationModal.kt` include badge notifications.

### iOS

- `NostrRepository+Profiles.swift` implements `fetchBadges`, `fetchAwardedBadges`, and `publishProfileBadges`.
- `NostrCache.swift` has badge cache support.
- `BadgeSettingsView.swift` exposes profile badge and awarded badge management.
- `NostrRepository+Notifications.swift` includes badge award notifications.

### Rust

- `filters.rs` has `badge_filter()` for profile badges kind `30008`.

## Source references

- `android/app/src/main/kotlin/io/nurunuru/app/data/NostrRepositoryProfiles.kt`
- `android/app/src/main/kotlin/io/nurunuru/app/ui/miniapps/BadgeSettings.kt`
- `android/app/src/main/kotlin/io/nurunuru/app/data/NostrRepositoryNotifications.kt`
- `ios/NuruNuru/Data/NostrRepository+Profiles.swift`
- `ios/NuruNuru/Data/NostrCache.swift`
- `ios/NuruNuru/Views/MiniApps/BadgeSettingsView.swift`
- `ios/NuruNuru/Data/NostrRepository+Notifications.swift`
- `rust-engine/nurunuru-core/src/filters.rs`

## Related pages

- [[features/notifications]]
- [[features/timeline]]
- [[nips/README]]
