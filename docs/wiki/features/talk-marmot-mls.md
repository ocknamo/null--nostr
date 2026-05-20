# Talk Marmot MLS

## Summary

Native Talk uses Marmot / WhiteNoise-compatible MLS instead of displaying legacy NIP-17 DMs. This page captures the MLS-specific protocol shape and implementation anchors.

## Current behavior

- MLS groups are represented by `MlsGroup` and `MlsMessage` models on native platforms.
- KeyPackages use canonical kind `30443` and legacy fallback kind `443` during migration/interop.
- Welcomes are Marmot MIP-02: inner Welcome rumor kind `444` or alias `10444`, gift-wrapped as kind `1059` via NIP-59.
- Group messages use outer kind `445` and carry an `h` tag for group identity/routing.
- Rust MDK/MLS code owns key package generation, Welcome processing, group message encrypt/decrypt, and self-update/key lifecycle mechanics.
- Native repositories publish exact Rust-produced signed/unsigned event JSON and avoid mutating peer-signed KeyPackage events.

## Platform notes

### Android

- `NostrRepositoryTalk.kt` handles group creation, key package discovery, welcome processing, message fetch, send, retry, and relay fanout.
- `NostrModels.kt` defines Marmot/MLS model and kind constants.

### iOS

- `NostrRepository+Talk.swift` mirrors Android interop behavior and contains detailed timing/order comments for Marmot MIP-02/MIP-03.
- `TalkViewModel.swift` handles local-first groups/messages, polling, open-group state, and repair/retry behaviors.

### Rust

- `mls.rs` documents Marmot kinds and performs MLS cryptographic operations.
- `engine.rs` wraps/unpacks Welcomes, creates group messages, validates key packages, and exposes high-level MLS operations to FFI.
- `nurunuru-ffi/src/lib.rs` exports MLS APIs to Kotlin/Swift.

## Source references

- `android/app/src/main/kotlin/io/nurunuru/app/data/NostrRepositoryTalk.kt`
  - group create/send/fetch/Welcome/key package flows
- `android/app/src/main/kotlin/io/nurunuru/app/data/models/NostrModels.kt`
  - `MlsGroup`, `MlsMessage`, `NostrKind.MLS_*`
- `ios/NuruNuru/Data/NostrRepository+Talk.swift`
  - Marmot/WhiteNoise interop, Welcome handling, kind 445 history fetch
- `ios/NuruNuru/ViewModels/TalkViewModel.swift`
  - local-first Talk state and polling
- `rust-engine/nurunuru-core/src/mls.rs`
  - KeyPackage, Welcome, group message cryptographic operations
- `rust-engine/nurunuru-core/src/engine.rs`
  - `generate_mls_key_package`, `create_mls_welcome`, `process_mls_welcome`, group message APIs
- `rust-engine/nurunuru-ffi/src/lib.rs`
  - UniFFI MLS bridge methods

## Related pages

- [[features/talk]]
- [[features/talk-relays]]
- [[features/talk-ios-android-parity]]
- [[nips/nip-59]]
- [[nips/nip-17]]

## Open questions

- Keep public naming aligned with upstream Marmot/WhiteNoise and any future NIP-EE naming changes.
