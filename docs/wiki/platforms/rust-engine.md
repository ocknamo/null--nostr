# Rust Engine

## Summary

Rust Engine は共通の Nostr / crypto / relay 管理処理を担う層です。Android は UniFFI 生成 Kotlin bindings を通じて利用します。Desktop 用には `nurunuru-napi` があります。

## Components

| Path | Role |
|---|---|
| `rust-engine/nurunuru-core/` | shared Rust core。 |
| `rust-engine/nurunuru-ffi/` | UniFFI bridge。 |
| `rust-engine/nurunuru-napi/` | napi-rs desktop bridge。 |

## FFI notes

- `rust-engine/nurunuru-ffi/src/lib.rs` の API を変更したら Kotlin bindings の再生成が必要。
- `bindgen/kotlin-out/uniffi/nurunuru/nurunuru.kt` は `lib.rs` API 変更と一緒に commit する。
- `parse_ffi_tags` は parse 不能な tag を silent skip する。
- `publishEvent(kind, content, tags)` は custom NIP tag を含む任意 tag name を扱える。


## iOS Rust FFI write-path contract

Phase 2 of Full iOS Rust FFI adds the shared contract that iOS will wire in later phases:

- generate_keypair() returns FfiGeneratedKeypair (private_key_hex, nsec, public_key_hex, npub) for onboarding. Secret fields must be stored only in platform secure storage / explicit backup UX.
- derive_public_key_from_secret(secret_key_hex) derives x-only public key hex from hex or nsec input.
- sign_event_json(secret_key_hex, kind, content, tags, created_at) signs a generic Nostr event and returns signed JSON.
- NuruNuruClient.sign_event(kind, content, tags, created_at) signs through an internal-signer client without repeatedly passing secret material over FFI.
- NuruNuruClient.publish_raw_event_to_relays(event_json, relay_urls) publishes one already-signed event to selected relays.

The FFI crate now includes rlib in crate-type so Rust integration tests can import the UniFFI crate directly. Generated Kotlin/Swift bindings and the iOS XCFramework must stay in sync with src/lib.rs.

## Android rebuild flow

```bash
cd rust-engine/nurunuru-ffi && bash bindgen/gen_kotlin.sh

AR_aarch64_linux_android=/home/n/Android/Sdk/ndk/27.3.13750724/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-ar \
  cargo build --release --target aarch64-linux-android -p nurunuru-ffi

cp rust-engine/target/aarch64-linux-android/release/libuniffi_nurunuru.so \
   rust-engine/nurunuru-ffi/android/libs/arm64-v8a/
```


## iOS Phase 2-5 write-path status

The iOS write path now consumes the Rust FFI contract through RustInternalSigner and RustNostrFFIClient. NuruNuruClient.sign_event and sign_event_json cover NIP-01 signing; nip04/nip44 helpers cover internal nsec crypto helpers; publish_raw_event_to_relays covers signed-once targeted relay publishing.

## Source references

- `rust-engine/nurunuru-ffi/src/lib.rs`
- `rust-engine/nurunuru-core/`
- `rust-engine/nurunuru-napi/`
- `rust-engine/Cargo.toml`

## Related pages

- [[architecture]]
- [[features/post-composer]]
