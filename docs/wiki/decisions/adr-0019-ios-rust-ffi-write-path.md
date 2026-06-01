# ADR-0019: iOS Rust FFI write-path migration starts from keygen/sign/publish contracts

## Status

Accepted — 2026-06-01

## Context

The iOS Rust FFI work completed Phase 1 through Phase 1.2 as a read-only MLS diagnostic path: mlsIsEncrypted(), local MLS group counts, sanitized diagnostic errors, manual refresh, and checked-at time are live. Full iOS Rust FFI remains incomplete for signing, publishing, key generation, and broader Talk MLS migration.

The existing iOS app uses Swift implementations for key generation, event signing, NIP-04/NIP-44 helpers, normal publishing, and relay-target fanout. Rust UniFFI already exposes broad MLS and relay APIs, but the iOS app needs a stable write-path contract before replacing Swift paths incrementally. The contract must preserve iOS requirements: Keychain-only private keys, NIP-46 for external signing, Passkey/Nosskey platform signing, NIP-70 relay-targeted publishing, and signed-event JSON reuse for UI/fanout.

## Decision

Full iOS Rust FFI will proceed incrementally. Phase 2 establishes the Rust FFI contract before wiring iOS UI flows:

- generate_keypair() -> FfiGeneratedKeypair for onboarding key generation.
- derive_public_key_from_secret(secret_key_hex_or_nsec) -> String for key validation and parity checks.
- sign_event_json(secret_key_hex_or_nsec, kind, content, tags, created_at?) -> signed_event_json as a standalone contract test/helper.
- NuruNuruClient.sign_event(kind, content, tags, created_at?) -> signed_event_json for logged-in internal-signer clients.
- NuruNuruClient.publish_raw_event_to_relays(event_json, relay_urls) -> event_id for signed-once relay-targeted publishing.

NIP-46 and Passkey/Nosskey remain platform signer paths. Rust may generate unsigned events and publish signed raw events for those paths, but must not replace the external signing UX with an internal Rust secret-key signer.

## Alternatives Considered

- Switch all iOS publishing to Rust immediately. Rejected because iOS currently depends on publishEventAndReturnSigned() semantics and several UI flows need the exact signed event JSON / decoded NostrEvent.
- Keep Swift signing indefinitely and use Rust only for MLS. Rejected because Android already benefits from the shared Rust protocol layer, and iOS needs shared keygen/sign/publish contracts for long-term parity.
- Route NIP-46/Passkey through Rust internal signing. Rejected because those are external/platform authorization flows by design and must not require exporting private keys into Rust.

## Why this fits NuruNuru

This follows [[../culture/principles|五箇条]] by keeping the user-facing experience calm while moving protocol-critical behavior into a shared, testable layer. It also aligns with [[../culture/not-doing|やらないことリスト]] by avoiding a risky all-at-once migration and by not weakening private-key boundaries.

## Consequences

- iOS can adopt Rust keygen, signing, and targeted publish one seam at a time.
- The Rust FFI crate now builds an rlib in addition to cdylib/staticlib so integration tests can import the crate directly.
- Generated Swift/Kotlin bindings and the iOS XCFramework must be committed whenever these APIs change.
- Future phases still need Swift adapters (RustInternalSigner / RustNostrFFIBridge) and repository wiring before the app is considered Full iOS Rust FFI.

## Source references

- rust-engine/nurunuru-ffi/src/lib.rs
- rust-engine/nurunuru-core/src/engine.rs
- rust-engine/nurunuru-ffi/tests/phase2_contract.rs
- rust-engine/nurunuru-ffi/ios/Sources/NuruNuru/nurunuru_ffi.swift
- rust-engine/nurunuru-ffi/bindgen/kotlin-out/uniffi/nurunuru/nurunuru.kt
- rust-engine/nurunuru-ffi/ios/NuruNuruFFI.xcframework/
- ios/NuruNuru/Data/NostrRepository.swift
- ios/GUARDRAILS.md
- docs/wiki/decisions/adr-0003-ios-external-signing-uses-nip46.md
- docs/wiki/decisions/adr-0009-mls-db-encryption.md
- docs/wiki/decisions/adr-0010-passkey-prf-direct-method.md
