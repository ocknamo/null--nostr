# Relay Management

## Summary

Relay management combines local selected relays, NIP-65 relay list metadata, outbox-model routing, search relay usage, and platform connection limits.

## Current behavior

- Default relays prioritize Japanese relays plus a global fallback and search relay.
- NIP-65 kind 10002 read/write relay lists are fetched and cached.
- Android signup/login can initialize `prefs.nip65Relays`; settings can edit relay lists.
- Reply publishing fans out to selected relays and/or the parent author's NIP-65 read relays so replies reach the author's preferred read relays.
- Web has connection pooling and rate limiting: max 4 global / 2 per-relay concurrent connections, 10 req/s.

## Platform notes

### Android

- `OutboxModel.kt` implements relay list parsing/discovery concepts.
- `NostrRepositoryActions.kt` fetches NIP-65 read/write relays and syncs logged-in user relay list.
- `PostModal.kt` supports target relay selection.

### iOS

- `RelaySettingsView.swift` manages relay settings.
- `publishNote()` in `NostrRepository+Actions.swift` can fan out to explicit `targetRelays` and reply author's NIP-65 read relays after initial ACK.

### Web

- `lib/outbox.js` and `lib/nostr.js` implement NIP-65 relay list helpers.
- `lib/connection-manager.js` owns pooling/rate-limit/cooldown behavior.

## Source references

- `android/app/src/main/kotlin/io/nurunuru/app/data/OutboxModel.kt`
- `android/app/src/main/kotlin/io/nurunuru/app/data/NostrRepositoryActions.kt`
- `android/app/src/main/kotlin/io/nurunuru/app/ui/screens/MiniAppsScreen.kt`
- `ios/NuruNuru/Views/MiniApps/RelaySettingsView.swift`
- `ios/NuruNuru/Data/NostrRepository+Actions.swift`
- `lib/outbox.js`
- `lib/connection-manager.js`
- `lib/nostr.js`

## Related pages

- [[features/post-composer]]
- [[features/search]]
- [[nips/README]]
