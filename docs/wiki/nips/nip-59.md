# NIP-59: Gift Wrap

## Summary

NIP-59 gift wrapping is used for Web NIP-17 DMs and native Marmot MLS Welcome delivery. In native Talk, kind `1059` is especially important as the outer gift-wrap for Marmot MIP-02 Welcome events.

## Current behavior

- Web creates NIP-59 gift wraps for NIP-17 DMs.
- Rust MLS code creates a Marmot Welcome rumor (`kind 444`) and gift-wraps it through `kind 13` seal to outer `kind 1059`.
- Android/iOS Talk fetch/process kind `1059` Welcomes and hand them to Rust for unwrap/validation.
- Native code also accepts legacy/plain Welcome variants (`kind 444`) and Marmot/WhiteNoise alias (`kind 10444`) for interop.
- Not every kind `1059` in native Talk is a NIP-17 message; for Talk it is usually Marmot Welcome transport.

## Platform notes

### Android

- `NostrRepositoryTalk.kt` fetches `MLS_WELCOME = 1059`, `MLS_WELCOME_INNER = 444`, and `MLS_WELCOME_INNER_MARMOT = 10444`.
- `publishMlsWelcome` publishes gift-wrapped Welcome data from Rust.
- Comments distinguish NIP-17 kind 14 payloads from Marmot kind 1059 Welcome processing.

### iOS

- `NostrRepository+Talk.swift` fetches kind `1059`, `444`, and `10444` Welcome variants.
- It validates outer kind `1059` by delegating unwrap/inner validation to Rust MDK.
- The repository tracks invalid kind `1059` events to avoid repeated processing.

### Web

- `createGiftWrap()` constructs gift wraps for NIP-17 DMs.
- `sendEncryptedDM()` publishes wrapped DM payloads.

### Rust

- `mls.rs` describes Marmot kinds and notes that kind `444` Welcome rumors are gift-wrapped via NIP-59 in `engine.rs`.
- `engine.rs` unwraps kind `1059` to kind `13` seal and then kind `444` rumor for MLS Welcome processing.
- FFI exposes returned gift-wrapped Welcome JSON for native publish.

## Source references

- `lib/nostr.js`
- `android/app/src/main/kotlin/io/nurunuru/app/data/NostrRepositoryTalk.kt`
- `ios/NuruNuru/Data/NostrRepository+Talk.swift`
- `rust-engine/nurunuru-core/src/mls.rs`
- `rust-engine/nurunuru-core/src/engine.rs`
- `rust-engine/nurunuru-ffi/src/lib.rs`

## Related pages

- [[nip-17]]
- [[features/talk]]
- [[nips/README]]
