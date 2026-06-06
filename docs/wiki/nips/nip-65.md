# NIP-65: Relay List Metadata

## Summary

NIP-65 relay list metadata (`kind 10002`) is used for read/write relay preferences and outbox-model routing.

## Current behavior

- Relay lists are parsed into read/write relay entries.
- The logged-in user's relay list can be synced into app preferences.
- Followed users' relay lists can be prefetched and cached.
- Reply publishing uses the parent author's read relays so replies are delivered to relays the author watches.
- Relay settings screens expose NIP-65 relay configuration.
- `client` tags are intentionally not added to kind 10002. The `client` tag is used for `via ...` post-source display, not for relay-list metadata.

## Platform notes

### Android

- `OutboxModel.kt` documents and implements outbox-model helpers around kind 10002.
- `NostrRepositoryActions.kt` has `fetchNip65WriteRelays()`, `fetchNip65ReadRelays()`, `syncLoggedInUserRelayList()`, and `syncNip65Relays()`.
- `NostrRepository.kt` keeps generic `publishNewEvent()` client-tag-free by default; `NostrRepositoryBackup.kt` `updateRelayList()` publishes kind 10002 through that default path.
- `MiniAppsScreen.kt` contains relay setting UI and explanatory copy.
- `AppPreferences.kt` stores `nip65Relays`.

### iOS

- `RelaySettingsView.swift` manages relay settings.
- `publishNote()` can fan out to target relays and reply author's NIP-65 read relays.
- `NostrRepository+Backup.swift` `updateRelayList()` publishes kind 10002 via generic `publishEvent(...)` without adding a `client` tag.
- `AppPreferences.swift` stores selected/upload/relay preferences relevant to routing.

### Web

- `lib/outbox.js` parses relay list metadata.
- `lib/nostr.js` can fetch/publish relay list metadata and determine preferred read/write/notification relays; `publishRelayListMetadata()` builds only `r` tags for kind 10002.

## Source references

- `android/app/src/main/kotlin/io/nurunuru/app/data/OutboxModel.kt`
- `android/app/src/main/kotlin/io/nurunuru/app/data/NostrRepository.kt`
- `android/app/src/main/kotlin/io/nurunuru/app/data/NostrRepositoryActions.kt`
- `android/app/src/main/kotlin/io/nurunuru/app/data/NostrRepositoryBackup.kt`
- `android/app/src/main/kotlin/io/nurunuru/app/data/prefs/AppPreferences.kt`
- `android/app/src/main/kotlin/io/nurunuru/app/ui/screens/MiniAppsScreen.kt`
- `ios/NuruNuru/Views/MiniApps/RelaySettingsView.swift`
- `ios/NuruNuru/Data/NostrRepository+Actions.swift`
- `ios/NuruNuru/Data/NostrRepository+Backup.swift`
- `lib/outbox.js`
- `lib/nostr.js`

## Related pages

- [[features/relay-management]]
- [[features/post-composer]]
- [[nips/README]]
