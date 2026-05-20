# Talk / Messaging

## Summary

Talk is the messaging area. Current native direction is Marmot MLS / NIP-EE-style group messaging, while older NIP-17 DM models remain as legacy/deprecated compatibility.

## Current behavior

- Android and iOS data models include `MlsGroup` / `MlsMessage` and NIP-17 legacy models marked deprecated or legacy.
- Settings copy notes that Talk screen is Marmot MLS-only and does not display NIP-17 messages.
- MLS-related kinds include key packages, welcomes, group messages, and key package relay lists.
- NIP-59 gift wraps (`kind 1059`) are used for Welcome delivery.
- Web still contains NIP-17 encrypted DM utilities including kind 14, kind 15 file messages, and kind 10050 DM relay list helpers.

## Important kinds / protocols

| Kind | Meaning in current code |
|---|---|
| 30443 | Marmot canonical key package. |
| 443 | Legacy key package fallback. |
| 1059 | NIP-59 gift wrap / MLS Welcome wrapper. |
| 444 / 10444 | Inner Welcome rumor variants handled for interop. |
| 445 | MLS group message. |
| 10051 | MLS key package relays. |
| 14 / 15 / 10050 | NIP-17 legacy chat/file/DM relay list helpers. |

## Platform notes

### Android

- `NostrRepositoryTalk.kt` handles Marmot MLS and interop/fallback paths.
- `NostrModels.kt` marks NIP-17 DM conversation/message models as deprecated.

### iOS

- `NostrRepository+Talk.swift` has MLS group/message sync and WhiteNoise/Marmot interop logic.
- `TalkViewModel.swift` handles canonical DM/group selection, local-first loading, polling, and send repair behavior.

### Web

- `lib/nostr.js` has NIP-17 encrypted DM and encrypted file message helpers.

## Source references

- `android/app/src/main/kotlin/io/nurunuru/app/data/NostrRepositoryTalk.kt`
- `android/app/src/main/kotlin/io/nurunuru/app/data/models/NostrModels.kt`
- `android/app/src/main/kotlin/io/nurunuru/app/ui/screens/SettingsScreen.kt`
- `ios/NuruNuru/Data/NostrRepository+Talk.swift`
- `ios/NuruNuru/ViewModels/TalkViewModel.swift`
- `rust-engine/nurunuru-core/src/mls.rs`
- `lib/nostr.js`

## Related pages

- [[features/talk-marmot-mls]]
- [[features/talk-relays]]
- [[features/talk-debugging]]
- [[features/talk-ios-android-parity]]
- [[nips/README]]
- [[platforms/android]]
- [[platforms/ios]]

## Open questions

- Exact public protocol naming for `NIP-EE` / Marmot MLS should be kept aligned with upstream Marmot/WhiteNoise terminology.
