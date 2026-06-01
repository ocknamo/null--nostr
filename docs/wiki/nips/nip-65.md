# NIP-65: Relay List Metadata

## Summary

NIP-65 relay list metadata (`kind 10002`) is used for read/write relay preferences and outbox-model routing.

## Current behavior

- Relay lists are parsed into read/write relay entries.
- The logged-in user's relay list can be synced into app preferences.
- Followed users' relay lists can be prefetched and cached.
- Reply publishing uses the parent author's read relays so replies are delivered to relays the author watches.
- Relay settings screens expose NIP-65 relay configuration.

## Platform notes

### Android

- `OutboxModel.kt` documents and implements outbox-model helpers around kind 10002.
- `NostrRepositoryActions.kt` has `fetchNip65WriteRelays()`, `fetchNip65ReadRelays()`, `syncLoggedInUserRelayList()`, and `syncNip65Relays()`.
- `MiniAppsScreen.kt` contains relay setting UI and explanatory copy.
- `AppPreferences.kt` stores `nip65Relays`.

### iOS

- `RelaySettingsView.swift` manages relay settings.
- `publishNote()` can fan out to target relays and reply author's NIP-65 read relays.
- `AppPreferences.swift` stores selected/upload/relay preferences relevant to routing.

### Web

- `lib/outbox.js` parses relay list metadata.
- `lib/nostr.js` can fetch/publish relay list metadata and determine preferred read/write/notification relays.

## Source references

- `android/app/src/main/kotlin/io/nurunuru/app/data/OutboxModel.kt`
- `android/app/src/main/kotlin/io/nurunuru/app/data/NostrRepositoryActions.kt`
- `android/app/src/main/kotlin/io/nurunuru/app/data/prefs/AppPreferences.kt`
- `android/app/src/main/kotlin/io/nurunuru/app/ui/screens/MiniAppsScreen.kt`
- `ios/NuruNuru/Views/MiniApps/RelaySettingsView.swift`
- `ios/NuruNuru/Data/NostrRepository+Actions.swift`
- `lib/outbox.js`
- `lib/nostr.js`

## Related pages

- [[features/relay-management]]
- [[features/post-composer]]
- [[nips/README]]
