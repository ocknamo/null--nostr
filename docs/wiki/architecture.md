# Architecture

## Summary

null--nostr は、Web / Android / iOS の UI 層と、Nostr 処理・暗号・リレー管理を担う Rust Engine を組み合わせる構成です。ただし Web では現状 Rust bridge は stub で、Nostr 操作は `lib/nostr.js` を直接使います。

## Platform stack

| Layer | Technology |
|---|---|
| Web | Next.js 14, nostr-tools, rx-nostr, Tailwind CSS |
| Android | Kotlin, Jetpack Compose, CameraX, ExoPlayer/Media3 |
| iOS | Swift, SwiftUI, iOS 17+ Observation |
| Rust FFI | UniFFI → Kotlin/Swift bindings |
| Rust Core | `nurunuru-core`, nostr-sdk 0.44.x, nostrdb |
| Desktop | `nurunuru-napi` |

## Data access pattern

- Android: `NostrRepository` が ViewModel の単一データアクセスポイント。
- iOS: `NostrRepository` は `actor`。Android と同様にデータアクセスの中心。
- Web: `lib/nostr.js`、`lib/connection-manager.js`、`lib/cache.js` などが責務を分担。

## Cross-cutting concerns

- **Design tokens:** `design-tokens/constants.json` から Web / Android / iOS に生成。
- **Private keys:** Web は module closure、iOS は Keychain、Android は platform signer / Rust FFI 経由の制約を守る。
- **Relay limits:** Web は global 4 / per-relay 2 concurrent connection を守る。
- **IO discipline:** Android の Rust FFI / file IO / uploads は `Dispatchers.IO`。

## Source references

- `AGENTS.md`
- `lib/nostr.js`
- `lib/connection-manager.js`
- `android/app/src/main/kotlin/io/nurunuru/app/data/NostrRepository.kt`
- `ios/NuruNuru/Data/`
- `rust-engine/nurunuru-ffi/src/lib.rs`

## Related pages

- [[ui/design-tokens]]
- [[platforms/web]]
- [[platforms/android]]
- [[platforms/ios]]
- [[platforms/rust-engine]]
