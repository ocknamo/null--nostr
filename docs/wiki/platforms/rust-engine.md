# Rust Engine

## Summary

Rust Engine は共通の Nostr / crypto / relay 管理処理を担う層です。Android は UniFFI 生成 Kotlin bindings を通じて利用します。Desktop 用には `nurunuru-napi` があります。

## Components

| Path | Role |
|---|---|
| `rust-engine/nurunuru-core/` | shared Rust core。 |
| `rust-engine/nurunuru-ffi/` | UniFFI bridge。 |
| `rust-engine/nurunuru-napi/` | napi-rs desktop bridge。 |

## Relay routing and durable publish groundwork

Phase 1/2 performance groundwork adds local Rust-side primitives for stable relay behavior, signed-event durability, structured publish results, and manual retry:

- `rust-engine/nurunuru-core/src/relay.rs` defines `RelayRouter`, `RelayRole`, `RelayHealth`, and `RelayHealthSnapshot`.
  - It tracks successes/failures, cooldown windows, last error, and availability.
  - `fetch_events_from_relays()` and targeted raw publish paths consult router availability and record health results.
  - If all candidate relays are in cooldown, the router returns the original candidates so explicit user/MLS relay targeting is not silently blocked.
- `rust-engine/nurunuru-core/src/outbox.rs` defines `PublishOutbox`, a JSON-on-disk durable queue for **fully-signed event JSON only**.
  - It never stores private keys, unsigned events, or signer material.
  - `publish_note()`, `publish_note_to_relays()`, `publish_raw_event()`, and `publish_raw_event_to_relays()` enqueue before network publish, then mark items published or failed.
  - Phase 2 adds `PublishResult` with `event_id`, `ok`, `ok_relays`, `failed_relays`, `first_ok_ms`, `retry_queued`, and `error`. Relay-level OK detail is currently aggregate best-effort because nostr-sdk high-level send methods do not expose per-relay OK packets here.
  - The outbox file lives under `db_path/publish_outbox.json`; iOS MLS-only mode (`db_path == ""`) uses a no-op in-memory-disabled path for now.
- `rust-engine/nurunuru-ffi/src/lib.rs` exposes diagnostics/accessors:
  - `relay_health_snapshots()`
  - `enqueue_publish_outbox(event_json, relay_urls)`
  - `pending_publish_outbox(limit)`
  - `retry_pending_publish_outbox(limit)`
  - `publish_raw_event_result(event_json)` / `publish_raw_event_to_relays_result(event_json, relay_urls)`
  - `publish_note_with_tags_result(content, tags)` / `publish_note_with_tags_to_relays_result(content, tags, relay_urls)`
- UniFFI Kotlin and Swift bindings were regenerated for these APIs.

This is still not the final autonomous retry worker: platform UI can inspect pending/failed signed events and explicitly trigger retry, while a later phase should add background retry scheduling, per-relay ACK detail, and user-facing delivery state. Android and iOS now wire structured publish results into repository publish paths and perform best-effort pending outbox retry after Rust connect.


- `rust-engine/nurunuru-ffi/src/lib.rs` の API を変更したら Kotlin bindings の再生成が必要。
- `bindgen/kotlin-out/uniffi/nurunuru/nurunuru.kt` は `lib.rs` API 変更と一緒に commit する。
- `parse_ffi_tags` は parse 不能な tag を silent skip する。
- `publishEvent(kind, content, tags)` は custom NIP tag を含む任意 tag name を扱える。
- `relay_health_snapshots()` exposes local relay success/failure/cooldown snapshots for diagnostics.
- `pending_publish_outbox(limit)` returns pending/failed fully-signed event JSON items; do not display sensitive event content without user intent.
- `retry_pending_publish_outbox(limit)` retries pending/failed signed events using the stored relay target list and existing RelayRouter cooldown rules.
- `FfiPublishResult` is the preferred write-path result for new UI integrations; legacy publish APIs still return event id or throw.


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
- `rust-engine/nurunuru-ffi/bindgen/swift-out/nurunuru.swift`
- `rust-engine/nurunuru-ffi/bindgen/kotlin-out/uniffi/nurunuru/nurunuru.kt`
- `rust-engine/nurunuru-core/src/outbox.rs`
- `rust-engine/nurunuru-core/src/relay.rs`
- `rust-engine/nurunuru-napi/`
- `rust-engine/Cargo.toml`

## Related pages

- [[architecture]]
- [[features/post-composer]]
