# Talk iOS / Android Parity

## Summary

Android and iOS native Talk should remain compatible at the Marmot MLS protocol level even though UI and platform implementation details differ.

## Current behavior

- Both native platforms use Marmot MLS groups/messages rather than displaying legacy NIP-17 DMs in Talk.
- Both platforms model MLS groups/messages and share kind constants for KeyPackage, Welcome, group message, and relay-list events.
- Both platforms rely on Rust/MDK for cryptographic MLS operations and use repository-level orchestration for relay fetch/publish/retry.
- Group ID / `h` tag normalization, Welcome timing, and message apply order are critical for parity.
- Android and iOS both must avoid mutating peer-signed KeyPackage events.

## Parity checklist

| Area | Android | iOS | Notes |
|---|---|---|---|
| MLS models | `MlsGroup`, `MlsMessage` | `MlsGroup`, `MlsMessage` | Keep fields semantically aligned. |
| KeyPackage canonical kind | `30443` | `30443` | Legacy `443` fallback exists. |
| Welcome outer kind | `1059` | `1059` | NIP-59 gift-wrapped Marmot Welcome. |
| Welcome inner variants | `444`, `10444` | `444`, `10444` | Interop handling. |
| Group message kind | `445` | `445` | Requires matching `h` tag. |
| Inbox relay signal | `10050` | `10050` | Used for Welcome/MLS wrapper delivery signal. |
| KeyPackage relay list | `10051` | `10051` | Marmot relay discovery. |
| Legacy NIP-17 display | Deprecated/legacy | Not native Talk display | Do not confuse with Web helpers. |

## Source references

- `android/app/src/main/kotlin/io/nurunuru/app/data/models/NostrModels.kt`
  - model and kind definitions
- `android/app/src/main/kotlin/io/nurunuru/app/data/NostrRepositoryTalk.kt`
  - native Talk orchestration
- `ios/NuruNuru/Models/NostrKind.swift`
  - kind definitions
- `ios/NuruNuru/Data/NostrRepository+Talk.swift`
  - native Talk orchestration
- `ios/NuruNuru/ViewModels/TalkViewModel.swift`
- `rust-engine/nurunuru-core/src/mls.rs`
- `rust-engine/nurunuru-ffi/src/lib.rs`

## Related pages

- [[features/talk]]
- [[features/talk-marmot-mls]]
- [[features/talk-relays]]
- [[nips/nip-17]]
- [[nips/nip-59]]

## Open questions

- Add UI-level parity notes if Android/iOS Talk UI diverges in user-visible ways.
