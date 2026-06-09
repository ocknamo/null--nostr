# NIP-46: Nostr Connect

## Summary

NIP-46 is used for remote/external signing. In this repository it is especially important on iOS, where NIP-55/Amber is not used.

## Current behavior

- Web implements a NIP-46 client/session flow in `lib/nip46.js`.
- iOS has `ExternalSigner.swift`, described as a NIP-46 remote signer client; messages are Nostr Connect kind 24133 encrypted with NIP-44.
- iOS login exposes a Nostr Connect path and `AuthViewModel` completes login after NIP-46 connection.
- Android uses NIP-55/Amber for external signing rather than NIP-46 as the main native external signer path.
- Rust FFI/core supports unsigned event creation and raw signed event publishing, which external signer paths use.

## Platform notes

### iOS

- Use NIP-46 for external signing.
- Do not introduce NIP-55 on iOS.
- Private keys remain in Keychain for internal signing; remote signer sessions should not leak secrets into logs or UserDefaults.

### Web

- `lib/nip46.js` manages session persistence, bunker URL parsing, encrypted requests, response handling, signing, and public-key retrieval.

### Android

- External signer code is Amber/NIP-55-oriented (`ExternalSigner.kt`).

## Source references

- `ios/NuruNuru/Data/ExternalSigner.swift`
- `ios/NuruNuru/ViewModels/AuthViewModel.swift`
- `ios/NuruNuru/Views/Screens/LoginView.swift`
- `lib/nip46.js`
- `rust-engine/nurunuru-ffi/src/lib.rs`
- `android/app/src/main/kotlin/io/nurunuru/app/data/ExternalSigner.kt`

## Related pages

- [[platforms/ios]]
- [[platforms/web]]
- [[nips/README]]
