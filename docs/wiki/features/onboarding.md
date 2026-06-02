# Onboarding (新規アカウント作成フロー)

## Summary

ぬるぬるは Web / Android / iOS の三プラットフォームで同一の **パスキー専用 5 ステップ**
新規登録ウィザードを提供する。最終段階の前にチュートリアル投稿ステップを
挟むことで、ユーザーが最初のノートを「#nostrはじめました」という共通ハッシュタグ
付きで発行する体験をオンボーディングに組み込んでいる。

## Steps (5-step wizard)

| # | Step       | 主な責務 |
|---|------------|---------|
| 1 | `welcome`  | パスキー登録のみ。新規登録中の nsec 生成/秘密鍵バックアップは出さない |
| 2 | `relay`    | ユーザー向け名称は **地域の設定**。地域選択 (GPS / 手動) からリレーサーバーを自動セットアップ |
| 3 | `profile`  | プロフィール (kind 0) + リレーサーバーリスト (kind 10002) の発行 |
| 4 | `tutorial` | **初期表示では `#nostrはじめました` 付きの最初の kind 1 投稿**。あいさつ案内と例文チップを表示 |
| 5 | `success`  | 「はじめる」遷移。招待導線はホームタブ設定の「招待」へ移設 |

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


## Passkey (nosskey) sign-up path

2026-05-23 以降、3 プラットフォームすべてで Passkey (nosskey "PRF Direct Method")
による新規登録に対応した。詳細仕様は [[../nips/nosskey|nips/nosskey]] と
[[../decisions/adr-0010-passkey-prf-direct-method|ADR-0010]] を参照。

### Step 数の分岐

| 経路 | ステップ数 | フロー |
|---|---|---|
| nsec (従来) | 6 | welcome → backup → relay → profile → tutorial → success |
| Passkey (nosskey) | **5** | welcome → relay → profile → tutorial → success (backup を **スキップ**) |

Passkey 経路で backup を省く理由は「Passkey 自体が iCloud Keychain / Google
Password Manager で同期されるリカバリ手段であり、nsec を別途バックアップさせる
必要がないため」(see ADR-0010)。

### Welcome ステップの UI 分岐

| 環境 | primary ボタン | secondary |
|---|---|---|
| Web | 「アカウントを作成する」(常に Passkey 経路) | — |
| iOS 18+ / Android API 28+ (PRF 対応) | 「**パスキーで登録**」(Face ID / Touch ID / 指紋認証) | — |
| iOS 17 / Android < 28 (PRF 非対応) | 新規登録不可 | キャプション「パスキー登録を利用できません」 |

### 既存セッションのログイン

| 経路 | UI 表示条件 |
|---|---|
| Web | 「パスキーでログイン」常時 (PublicKeyCredential サポート時のみ) |
| Android | 「パスキーでログイン」ボタンは `NosskeyManager.loadStoredKeyInfo() != null` のときだけ表示 |
| iOS 18+ | LoginView 直下に「パスキーでログイン」を表示。ローカル `NosskeyKeyInfo` がない再インストール直後でも discoverable assertion で iCloud Keychain の Passkey picker を開き、`credentialId / pubkey / salt` を復元してログインする。 |

### 投稿フロー内の Signer 解決

サインアップ直後の profile / relayList / tutorial 発行は一時的な
`NostrRepository` で行うが、その signer は `loginMethod` を見て自動で切り替わる:

- iOS: `AuthViewModel.currentSessionSigner() async -> EventSigner?` が
  `prefs.loginMethod == "nosskey"` のとき `NosskeySigner` を返す。null のとき
  Repository は既定の `InternalSigner` を構築する。
- Android: `AuthViewModel.buildSigner(activity)` が同様に分岐する。
  Activity が必要なため、UI 層から明示的に渡す。

### ログアウト時の挙動

- iOS: logout ではローカル `NosskeyKeyInfo` を削除しない。非秘密 metadata
  (credentialId / pubkey / salt) はログアウト後の「パスキーでログイン」に必要なため。
  アプリ再インストールで UserDefaults が消えた場合は、`loginWithPasskey()` が
  discoverable assertion を使って iCloud Keychain から同 metadata を復元する。
- Android: SharedPreferences の metadata はログアウト後も維持する。Google Password
  Manager 側の Passkey 自体は OS / provider 管理。
- 3 プラットフォーム共通で `prefs.loginMethod` は null にクリアし、次回ログインで再設定する。

### Profile sharing and referral follow

The final success page no longer asks users to copy their public key. Android and iOS now show a profile-share action instead. The native share sheet shares only the canonical HTTPS invite URL (`https://www.nullnull.app/p/<npub>`) so Twitter/X, LINE, Messages, and other apps can render a modern link card using Open Graph metadata. Custom-scheme links remain accepted by native deep-link handlers but are not included in the shared text.

When a recipient opens a supported profile/referral deep link before registration, `AuthViewModel` stores the referred pubkey as a pending follow. After the new account taps **はじめる**, registration transitions to the main app immediately and a background task publishes a kind:3 contact list that includes the shared profile.

Source references:
- `android/app/src/main/kotlin/io/nurunuru/app/ui/components/SignUpModal.kt`
- `android/app/src/main/kotlin/io/nurunuru/app/viewmodel/AuthViewModel.kt`
- `android/app/src/main/kotlin/io/nurunuru/app/MainActivity.kt`
- `android/app/src/main/AndroidManifest.xml`
- `ios/NuruNuru/Views/Screens/LoginView.swift`
- `ios/NuruNuru/ViewModels/AuthViewModel.swift`

Install-cross retention and preview additions:
- Web landing page `app/p/[npub]/page.js` renders the invited profile, stores the referral in browser `localStorage`, offers app-open/install actions, and exposes Open Graph / Twitter Card metadata plus a generated thumbnail image for rich share previews.
- Android persists the pending referral in `AppPreferences.pendingReferralPubkeyHex`, restores it after process restart, and shows an invite preview card on `LoginScreen` using the profile fetched from relays.
- iOS persists the pending referral in `AppPreferences.pendingReferralPubkeyHex`, restores it after app restart, and shows the same invite preview card on `LoginView`.
- Associated link config now includes `/p/*`: Android App Links via `AndroidManifest.xml` + `assetlinks.json`; iOS Universal Links via `NuruNuru.entitlements` + `apple-app-site-association`.

Source references (install-cross / preview):
- `app/p/[npub]/page.js`
- `app/.well-known/apple-app-site-association/route.js`
- `public/.well-known/apple-app-site-association`
- `app/.well-known/assetlinks.json/route.js`
- `android/app/src/main/kotlin/io/nurunuru/app/data/prefs/AppPreferences.kt`
- `android/app/src/main/kotlin/io/nurunuru/app/ui/screens/LoginScreen.kt`
- `ios/NuruNuru/Data/AppPreferences.swift`
- `ios/NuruNuru/NuruNuru.entitlements`
- `ios/NuruNuru/Views/Screens/LoginView.swift`

Open Questions:
- True deferred deep linking where a store installs the app and automatically passes the original referral into the first launch still depends on App Store / Play Store campaign/deferred-link infrastructure. Current native support preserves referral across app restarts and across install when the user returns to or reopens the same `/p/<npub>` invite link after install.

### Android profile setup continuation

Android treats the initial kind:0 profile publish during onboarding as best-effort. If relay publish fails or times out, the setup button still advances to the tutorial step so a new user is not trapped before entering the app. The profile can be republished later via profile editing.

Source references:
- `android/app/src/main/kotlin/io/nurunuru/app/ui/components/SignUpModal.kt`

### Post rich sharing

Android and iOS post overflow menus include **投稿を共有**. The shared URL is the canonical HTTPS event URL (`https://www.nullnull.app/e/<event-id>`), so LINE, X, Messages, and blog platforms can render URL cards instead of raw text. The Web route `app/e/[eventId]/page.js` provides Open Graph/Twitter metadata and `app/e/[eventId]/opengraph-image.js` provides the thumbnail.

Source references:
- `android/app/src/main/kotlin/io/nurunuru/app/ui/components/PostContent.kt`
- `ios/NuruNuru/Views/Components/PostContent.swift`
- `app/e/[eventId]/page.js`
- `app/e/[eventId]/EventInviteClient.js`
- `app/e/[eventId]/opengraph-image.js`
