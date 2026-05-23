# Onboarding (新規アカウント作成フロー)

## Summary

ぬるぬるは Web / Android / iOS の三プラットフォームで同一の 6 ステップ
新規登録ウィザードを提供する。最終段階の前にチュートリアル投稿ステップを
挟むことで、ユーザーが最初のノートを「#nostrはじめました」という共通ハッシュタグ
付きで発行する体験をオンボーディングに組み込んでいる。

## Steps (6-step wizard)

| # | Step       | 主な責務 |
|---|------------|---------|
| 1 | `welcome`  | パスキー / 秘密鍵生成のトリガー |
| 2 | `backup`   | 生成された nsec の表示・コピー |
| 3 | `relay`    | 地域選択 (GPS / 手動) からのリレー推奨 |
| 4 | `profile`  | プロフィール (kind 0) + リレーリスト (kind 10002) の発行 |
| 5 | `tutorial` | **初期表示では `#nostrはじめました` 付きの最初の kind 1 投稿** |
| 6 | `success`  | 公開鍵表示と「はじめる」遷移 |

`profile` 成功後に直接 `success` へ遷移していた従来のフローを変更し、
`profile` → `tutorial` → `success` の順とした (`profile` 発行に失敗した場合でも
アカウントは作成済みなので `tutorial` に進む)。

## Tutorial step contract

- **既定本文 (pre-fill)**: `\n#nostrはじめました` をエディタに pre-fill する。
  これにより、エディタを開いた瞬間から `#nostrはじめました` が常時可視化され、
  ユーザーが「付けてもないハッシュタグを勝手につけられた」と感じる不信感を回避する。
  1 行目が空のため、ユーザーが先頭にカーソルを置いて本文を書けば
  「本文 → 改行 → ハッシュタグ」の配置が自然に成立する。
- **ユーザー操作の尊重 (no auto-completion)**: ユーザーが意図的にハッシュタグ行を
  削除した場合は、その状態のまま投稿される。`publishTutorialPost` (Web/Android/iOS いずれも)
  は本文への自動補完・末尾付与を一切行わない (3 プラットフォーム共通の規約)。
- **プレースホルダー**: `いまどうしてる？\n#nostrはじめました` を薄い灰色
  (`var(--text-tertiary)` / `nuruColors.textTertiary` / `theme.textTertiary`)
  で表示する。pre-fill されているため通常は非表示で、ユーザーが本文を全て消した時の
  ガイドとしてのみ機能する。iOS は `TextEditor` が placeholder API
  を持たないため、`ZStack` + `content.isEmpty` + `allowsHitTesting(false)` の重ね描画で実装。
- **アイコン**: 吹き出しアイコンを **ぬるぬるブランドカラー (LineGreen)** に統一
  (Web `var(--line-green)` / Android `LineGreen` / iOS `NuruColors.lineGreen`)。
  containerColor は同色の 10% アルファ。
- **140 文字制限**: 既存の投稿 UI と同じ `UI.postMaxLength = 140` を強制。
- **ハッシュタグ tag (`t`)**:
  - 本文中に含まれる `#xxx` を Unicode 対応の正規表現
    `#([\\w\\u3040-\\u309F\\u30A0-\\u30FF\\u4E00-\\u9FFF\\uFF00-\\uFFEF]+)`
    (Web は `/#([^\s#\u3000]+)/g`) で抽出し、lowercase 化して `["t", value]` を生成。
  - ユーザーが `#nostrはじめました` を消していれば `t` タグも付与されない
    (本文と `t` タグの内容が常に一致する、意図尊重の規約)。
- **送信先**: `profile` ステップで確定したリレー (`selectedRelays`)。
  null の場合は default JP relays (`yabu.me` / `relay-jp.nostr.wirednet.jp` / `r.kojira.io`) にフォールバック。
- **スキップ可能**: 「スキップ」ボタンで投稿せずに `success` へ進める。
- **投稿ボタン**: 投稿中でない、かつ 140 文字以下、かつ本文が空 (trim 後 0 文字) で
  ない場合に有効。pre-fill された `#nostrはじめました` を残せばそのまま投稿可能。
- **投稿成功後**: 確認カード (`投稿しました！` + 案内文) を表示。「次へ進む」で `success` へ。
- **投稿失敗時**: ユーザー向けエラー文言を表示し、再試行 or スキップを選べる。

## Implementation notes per platform

### Web — `components/SignUpModal.js`

- 状態: `tutorialContent`, `tutorialPosting`, `tutorialPosted`, `tutorialError`。
- 投稿ロジックは `handlePostTutorial()`:
  - `createEventTemplate(1, content, tags)` → `signEventNip07()` → `publishEvent(signed, targetRelays)`。
  - PostModal.js の `extractHashtags` と同じ regex (`/#([^\s#\u3000]+)/g`) を使用。
- Progress bar は 6 分割 (`w-1/6` … `w-full`)。

### Android — `android/.../ui/components/SignUpModal.kt`

- 状態は `TutorialStep` composable 内に localize (`content`, `isPosting`, `posted`, `errorMsg`)。
- 投稿は `viewModel.publishTutorialPost(signer, content, relays)` を経由
  (`AuthViewModel.kt`)。
  - 一時 `NostrClient` + `NostrRepository` を `publishInitialMetadata` と同じパターンで生成。
  - `NostrRepository.publishNote(content, customTags = foundTags.map { listOf("t", it.lowercase()) })`。
    `customTags` は本文中に実在する `#xxx` のみから生成されるため、ユーザーが
    `#nostrはじめました` を削除した場合は `nostrはじめました` の `t` タグも送信されない。
- `InternalSigner` を `remember { … }` で確保 (生成済み秘密鍵が SecureKeyManager にある前提)。
- `OutlinedTextField` で 140 文字制限を強制 (`onValueChange` で `length <= 140` を確認)。
- `placeholder = { Text(TUTORIAL_PLACEHOLDER, color = nuruColors.textTertiary) }` で
  薄い灰色の例示テキストを表示。
- アイコンは `Icons.Default.Forum` を **LineGreen** で表示
  (`containerColor = LineGreen.copy(alpha = 0.1f)`, `iconColor = LineGreen`)。
- 投稿ボタンの `enabled` は `!isPosting && content.trim().isNotEmpty()`
  (pre-fill された `#nostrはじめました` を残せば自動的に enable)。

### iOS — `ios/NuruNuru/Views/Screens/LoginView.swift`, `ViewModels/AuthViewModel.swift`

- `SignUpTutorialStep` 構造体を `LoginView.swift` に追加。
- 投稿は `viewModel.publishTutorialPost(content:, relays:)`:
  - 一時 `NostrRepository` を `publishInitialMetadata` と同じパターンで生成
    (`prefs.publicKeyHex` は完了まで未設定なので `keyManager.getStoredPublicKeyHex()` 経由で署名)。
  - `repo.publishNote(content:, customTags:)` を経由。
- `TextEditor` + `onChange` で 140 文字制限を enforce。
- `TextEditor` は placeholder API を持たないため、`ZStack(alignment: .topLeading)` で
  `content.isEmpty` 時のみ `Text(kTutorialPlaceholder)` を `theme.textTertiary` で重ね描画
  (`allowsHitTesting(false)` で下層 `TextEditor` にタップを通す)。
- アイコンは `bubble.left.and.bubble.right.fill` を **`NuruColors.lineGreen`** で表示。
- `canPost = remaining >= 0 && !isPosting && !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty`
  (pre-fill された `#nostrはじめました` を残せば自動的に enable)。
- `NuruPrimaryButtonStyle(isDisabled:)` を canPost / isLoading で切替。

## Source references

- `components/SignUpModal.js` (Web 6-step wizard)
- `android/app/src/main/kotlin/io/nurunuru/app/ui/components/SignUpModal.kt` (Android)
- `android/app/src/main/kotlin/io/nurunuru/app/viewmodel/AuthViewModel.kt` (`publishTutorialPost`)
- `ios/NuruNuru/Views/Screens/LoginView.swift` (`SignUpTutorialStep`)
- `ios/NuruNuru/ViewModels/AuthViewModel.swift` (`publishTutorialPost`)
- `android/.../data/NostrRepositoryActions.kt` (`publishNote`)
- `ios/NuruNuru/Data/NostrRepository+Actions.swift` (`publishNote`)

## Related pages

- [[features/post-composer]] — 140 文字制限・hashtag 抽出ロジック
- [[features/relay-management]] — NIP-65 relay 選択
- [[platforms/web]] / [[platforms/android]] / [[platforms/ios]]
- [[ui/android-ios-sync]] — 三プラットフォームで同一の copy / step ordering を保つ

## Open questions

- プレースホルダー文面 (`いまどうしてる？\n#nostrはじめました`) はパーソナライズ可能
  (i18n / ユーザー名挿入 / 時間帯別の例示文) にすべきか。
- 同タグでの "おすすめユーザー" 自動フォロー機能との連携は未実装。
- スキップ率 / 投稿成功率の analytics は現状なし。Charter「制度化」の観点で計測すべきか要検討。
- pre-fill された `\n#nostrはじめました` の先頭改行は 1 文字としてカウントされる
  (140 文字制限に対して 13 文字分を初期消費する)。本文を 127 文字以内に収める制約を
  どう案内するか (例: カウンター UI で「のこり 127 文字」を表示する等) は要再検討。
