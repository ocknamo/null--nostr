# Android / iOS UI Sync

## Summary

Android と iOS は LINE 風 UI を platform native に実装しつつ、見た目・文言・挙動を可能な限り揃えます。このページの内容はコードを優先して更新する必要があります。

## Current behavior

### Typography and list behavior

- Android app-wide typography は `LineSeedJP`。
- iOS body text は LINE Seed JP のみ。system font fallback を避ける。
- Timeline は entrance animation を避ける。
- iOS list identity は `.id(post.event.id)` を使う。

### Navigation

- iOS tab bar は `.safeAreaInset(edge: .bottom, spacing: 0)`。
- Bottom nav は 5 tabs: ホーム / トーク / ろくなな / タイムライン / ミニアプリ。
- Bottom nav icons は `house` / `message` / `67` / `newspaper` / `square.grid.2x2`。
- Home icon に `person.crop.circle` を使わない。

### PostActions

現行コードでは PostActions は **常時 3 ボタンではありません**。

- Android `PostActions.kt` は like / repost / zap を常時表示し、`onBookmark` が渡された場合は bookmark も表示する。
- iOS `PostActions.swift` も like / repost / zap / bookmark の並びを持つ。
- Reply button は PostActions にはない。返信は詳細画面や投稿シートの `replyTo*` 経由で扱う。
- Repost は通常タップで kind 6 repost、長押しで quote repost を起動できる。
- Like は thumbs-up 系アイコン。heart ではない。
- Android / iOS とも末尾に `client` tag がある場合 `via ...` 表示を行う。

### Copy and modals

- Collapse text は「もっと見る」/「閉じる」。 「続きを読む」は使わない。
- Full-screen image viewer は iOS `.fullScreenCover`、Android fullscreen overlay / dialog 方針を守る。

## Source references

- `android/app/src/main/kotlin/io/nurunuru/app/ui/components/PostActions.kt`
- `ios/NuruNuru/Views/Components/PostActions.swift`
- `android/app/src/main/kotlin/io/nurunuru/app/ui/screens/MainScreen.kt`
- `ios/NuruNuru/Views/Screens/MainTabView.swift`
- `ios/GUARDRAILS.md`

## Related pages

- [[platforms/android]]
- [[platforms/ios]]
- [[features/timeline]]
- [[features/post-composer]]
