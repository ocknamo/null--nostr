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

## Android rebuild flow

```bash
cd rust-engine/nurunuru-ffi && bash bindgen/gen_kotlin.sh

AR_aarch64_linux_android=/home/n/Android/Sdk/ndk/27.3.13750724/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-ar \
  cargo build --release --target aarch64-linux-android -p nurunuru-ffi

cp rust-engine/target/aarch64-linux-android/release/libuniffi_nurunuru.so \
   rust-engine/nurunuru-ffi/android/libs/arm64-v8a/
```

## Source references

- `rust-engine/nurunuru-ffi/src/lib.rs`
- `rust-engine/nurunuru-core/`
- `rust-engine/nurunuru-napi/`
- `rust-engine/Cargo.toml`

## Related pages

- [[architecture]]
- [[features/post-composer]]
