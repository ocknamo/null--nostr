# Android Platform

## Summary

Android は Kotlin + Jetpack Compose による native app です。Rust FFI を通じて Nostr 処理や暗号処理を利用します。

## Main structure

```text
android/app/src/main/kotlin/io/nurunuru/app/
  data/           # NostrRepository, NostrClient, models, cache, prefs, signers
  ui/             # Compose screens, components, theme, icons, miniapps
  viewmodel/      # TimelineViewModel, TalkViewModel, HomeViewModel, AuthViewModel, ConnectionViewModel
  MainActivity.kt
  NuruNuruApp.kt
```

## Important rules

- `NostrRepository` が ViewModel から見た単一データアクセスポイント。
- `TimelineViewModel` は フォロー / おすすめ タブを駆動する。
- 投稿文字数は `PostModal.kt` で 140 文字を厳密に enforced。
- Rust FFI、file IO、upload は `Dispatchers.IO`。
- `BasicTextField` に `Modifier.weight(1f)` を scrollable `Column` 内で使わない。
- `ImageViewerDialog` では `Modifier.transformable` を使わず、manual pointer-count branching を使う。
- app-wide font は `LineSeedJP`。

- NIP-55 / Amber external signer via `ExternalSigner.kt`。
- Talk は Marmot MLS 中心。NIP-17 models は legacy/deprecated。
- Relay settings and NIP-65 outbox behavior are implemented in data/settings layers.

## Source references

- `android/app/src/main/kotlin/io/nurunuru/app/data/NostrRepository.kt`
- `android/app/src/main/kotlin/io/nurunuru/app/ui/components/PostModal.kt`
- `android/app/src/main/kotlin/io/nurunuru/app/ui/components/ImageViewerDialog.kt`
- `android/app/src/main/kotlin/io/nurunuru/app/ui/screens/MainScreen.kt`

## Related pages

- [[features/post-composer]]
- [[features/timeline]]
- [[features/notifications]]
- [[ui/android-ios-sync]]
