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


### Talk chat screen

- Native Talk chat should visually follow LINE dark chat: black header/background, compact 56dp/pt header, right-side search / call / calendar / menu affordances, green outgoing bubbles, dark-gray incoming bubbles, and small outside timestamps for both sides. Read-status labels (e.g. 「既読」) are not rendered because real read-receipts cannot yet be verified end-to-end over MLS.
- Incoming bubbles render avatar + bubble only. Do **not** render the sender's display name above the bubble — the avatar already carries identity and the duplicated name (often appearing on every consecutive message) breaks the LINE silhouette. The display name remains available in the group info sheet.
- Sending must feel instantaneous (ぬるぬる = ultra-smooth). The optimistic message bubble must be appended to `messages` in the same UI frame as the send tap, **before** any DM canonicalize / MLS catch-up / gap repair work. Auto-scroll-to-bottom after send is non-animated (`scrollToItem` on Android, and on iOS a `proxy.scrollTo` wrapped in a `Transaction` with `disablesAnimations = true` so no enclosing `.animation(...)` modifier can attach an implicit ease) — the optimistic bubble is already at the bottom, so any easing only adds perceived latency. If a later DM remap chooses a different canonical group, rewrite the optimistic message's `groupIdHex` in place rather than dropping and re-adding the bubble.
- The send affordance itself must not animate between the mic and paper-plane states. Do **not** add `.animation(...)` modifiers to the send button on iOS, and do **not** wrap the send button color/tint in `animateColorAsState` on Android. The state must flip on the same frame as the tap; any easing reads as the app "thinking" before it sends. Failed sends still surface via `abortOptimisticSend(...)` (bubble removed + error toast), so the only thing easing would communicate is fake latency.
- The send-button spinner (`ProgressView` on iOS, `CircularProgressIndicator` on Android) must reflect **only the actual MLS send call** — that is, the `withTimeout(30s) { repository.sendMlsMessage(...) }` block. It must **not** cover the pre-flight catch-up / repair / deep-catch-up chain. Those timeouts can legitimately stack to 60+ seconds, and a spinner that long contradicts the optimistic bubble that already confirmed the send to the user. Concretely: `sendingMessage = true` is set immediately before the send call, not at the top of `sendMessage(...)`. The optimistic bubble + cleared composer are the affordance for "your message was accepted"; the spinner is the affordance for "the network round-trip is in flight" only. `abortOptimisticSend(...)` still defensively clears `sendingMessage` for any path that flips it true.
- Header action icons must be the same glyph family on both platforms. iOS uses SF Symbols `magnifyingglass` / `phone` / `calendar` / `line.3.horizontal`; Android mirrors them with `Icons.Outlined.Search` / `Call` / `CalendarToday` / `Menu`. Do not substitute Unicode text glyphs (⌕ ☎ 31 ☰) — they render with system font fallbacks and break cross-platform parity.
- Composer left-side icons are 3 distinct glyphs in this order: add (`plus` / `Icons.Outlined.Add`), camera (`camera` / `Icons.Outlined.PhotoCamera`), and photo library (`photo` / `NuruIcons.Image`). The camera and photo slots must use different icons — duplicating the photo glyph in the camera slot is a regression.
- When a Talk conversation is open, the global bottom tab bar is hidden so the composer sits at the bottom like LINE. The tab bar returns on the Talk list and other tabs.
- Debug identifiers must not appear in the chat header, message composer, or conversation list. The MLS group ID is shown only in the group information sheet.

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

- `android/app/src/main/kotlin/io/nurunuru/app/ui/screens/TalkScreen.kt`

- `android/app/src/main/kotlin/io/nurunuru/app/ui/components/TalkComponents.kt`

- `android/app/src/main/kotlin/io/nurunuru/app/ui/components/GroupInfoModal.kt`

- `ios/NuruNuru/Views/Screens/TalkView.swift`

- `ios/NuruNuru/Views/Sheets/GroupInfoSheet.swift`

## Related pages

- [[platforms/android]]
- [[platforms/ios]]
- [[features/timeline]]
- [[features/post-composer]]