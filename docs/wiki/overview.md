# Project Overview

## Summary

**null--nostr（ぬるぬる）** は、日本語コミュニティ向けの LINE 風 Nostr クライアントです。

Web、Android、iOS、Rust Engine を持つクロスプラットフォーム構成で、Nostr の投稿・リアクション・通知・検索・DM/Talk・Zap・画像アップロードなどを扱います。

## Platforms

- **Web:** Next.js 14 PWA
- **Android:** Kotlin + Jetpack Compose + Rust FFI
- **iOS:** Swift / SwiftUI / iOS 17+ Observation
- **Rust Engine:** `nurunuru-core`、`nurunuru-ffi`、`nurunuru-napi`

## Design principles

- 日本語コミュニティ向けの軽快な LINE 風 UI。
- Android と iOS は pixel-perfect に近い同期を目指す。
- デザイン値は `design-tokens/constants.json` を単一の真実の源泉とする。
- 秘密鍵は各プラットフォームの安全な保存方式を使い、ログやグローバルオブジェクトへ出さない。
- Nostr の NIP 対応はプラットフォーム差分を明確に管理する。

## Source references

- `AGENTS.md`
- `README.md`
- `design-tokens/constants.json`
- `android/app/src/main/kotlin/io/nurunuru/app/`
- `ios/NuruNuru/`
- `lib/`
- `rust-engine/`

## Related pages

- [[architecture]]
- [[platforms/web]]
- [[platforms/android]]
- [[platforms/ios]]
- [[platforms/rust-engine]]
