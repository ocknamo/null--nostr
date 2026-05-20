# ADR-0003: iOS external signing uses NIP-46

## Status

Accepted.

## Context

iOS does not have Android's Amber/NIP-55 environment. The project targets iOS 17+ and keeps private keys in Keychain for internal signing.

## Decision

Use NIP-46 / Nostr Connect for iOS external signing. Do not introduce NIP-55 as an iOS external signer path.

## Consequences

- iOS external signer work should touch `ExternalSigner.swift` / auth flow rather than Android `ExternalSigner.kt` assumptions.
- Docs should point iOS external signing to [[nips/nip-46]].

## Source references

- `ios/NuruNuru/Data/ExternalSigner.swift`
- `ios/NuruNuru/ViewModels/AuthViewModel.swift`
- `ios/NuruNuru/Views/Screens/LoginView.swift`
- `lib/nip46.js`
