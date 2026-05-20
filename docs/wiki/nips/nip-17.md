# NIP-17: Private Direct Messages

## Summary

null--nostr has code-backed NIP-17 support, but native Talk is currently **Marmot MLS oriented**. Treat NIP-17 as a legacy / compatibility boundary in native apps, while Web still exposes NIP-17 DM helpers.

## Current behavior

- NIP-17 chat message kind `14`, file message kind `15`, and DM relay list kind `10050` are declared in Android and iOS models.
- Android `NostrModels.kt` marks NIP-17 DM conversation/message models as legacy, kept for read-only display during migration.
- iOS `NostrRepository+Talk.swift` states that Talk is Marmot MLS only and does not read/display NIP-17/NIP-44 DM payloads.
- Web `lib/nostr.js` implements NIP-17 encrypted DM helpers, file messages, and DM relay list helpers.
- Rust core/FFI still exposes legacy NIP-17 DM methods during the migration period.
- Native Talk uses kind `10050` as an inbox relay-list signal for Welcomes/MLS wrappers, not as proof that NIP-17 messages are displayed in Talk.

## Platform notes

### Android

- `NostrKind.DIRECT_MESSAGE = 14`, `FILE_MESSAGE = 15`, and `DM_RELAY_LIST = 10050` exist.
- `DmConversation` and `DmMessage` are documented as legacy migration types.
- `SettingsScreen.kt` copy says Talk is Marmot MLS-only and does not display NIP-17 messages.
- `NostrRepositoryTalk.kt` publishes/uses `DM_RELAY_LIST` for inbox relay discovery in MLS flows.

### iOS

- `NostrKind.directMessage`, `fileMessage`, and `dmRelayList` exist.
- `NostrRepository+Talk.swift` explicitly excludes NIP-17/NIP-44 DM display from Talk.
- `AppPreferences.swift` stores NIP-17/MLS inbox relays as relay-list settings.

### Web

- `sendEncryptedDM()` creates NIP-17 encrypted DMs using NIP-44 and NIP-59 gift wrapping.
- `sendEncryptedFileMessage()` handles kind `15` file messages.
- `fetchDMRelayList()` / `setDMRelayList()` handle kind `10050`.

### Rust

- `engine.rs` and `lib.rs` expose legacy NIP-17 DM send/fetch helpers.
- FFI comments call these legacy during NIP-17 → NIP-EE / Marmot migration.

## Open questions

- If native NIP-17 display is reintroduced, update this page and [[features/talk]] to clarify coexistence with Marmot MLS.

## Source references

- `android/app/src/main/kotlin/io/nurunuru/app/data/models/NostrModels.kt`
- `android/app/src/main/kotlin/io/nurunuru/app/data/NostrRepositoryTalk.kt`
- `android/app/src/main/kotlin/io/nurunuru/app/ui/screens/SettingsScreen.kt`
- `ios/NuruNuru/Models/NostrKind.swift`
- `ios/NuruNuru/Data/NostrRepository+Talk.swift`
- `ios/NuruNuru/Data/AppPreferences.swift`
- `lib/nostr.js`
- `rust-engine/nurunuru-core/src/engine.rs`
- `rust-engine/nurunuru-ffi/src/lib.rs`

## Related pages

- [[nip-59]]
- [[features/talk]]
- [[nips/README]]
