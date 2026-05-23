# ADR-0010: Passkey登録は nosskey "PRF Direct Method" を採用する

## Status

`Accepted` — 2026-05-23

## Context

新規登録オンボーディングで「秘密鍵 (nsec) をユーザーに見せて手動バックアップさせる」
体験が、Nostr 初心者にとって最大のドロップポイントになっていた。Web では既に
[nosskey-sdk](https://github.com/ocknamo/nosskey-sdk) を使った Passkey 登録が
存在したが、iOS / Android では「パスキーでログイン」ボタンが
コメントアウト状態 (Android `LoginScreen.kt:327`) または完全に未着手 (iOS) のままだった。

ユーザーから「nosskey をすべて学習し、iOS / Android も新規登録時パスキーを使用
できるようにしてほしい」という依頼を受け、3 プラットフォーム共通の Passkey 体験を
設計する必要が生じた。

主な選択肢は 2 つあった:

1. **PRF Direct Method** — WebAuthn PRF 拡張の出力 (32 バイト) を直接 secp256k1
   秘密鍵として使う。秘密鍵自体は保存せず、署名時に毎回バイオメトリ認証で再導出する。
2. **Encryption/Decryption Method** — 秘密鍵を別途生成し、PRF 出力で暗号化して
   保存する。署名時は復号して使う。

## Decision

**PRF Direct Method を 3 プラットフォーム共通で採用する。**

- Web: 既存実装の延長 (nosskey-sdk@^0.0.4)。salt を旧誤値 `6e6f7374722d6b6579`
  (`"nostr-key"`) から標準値 `6e6f7374722d70776b` (`"nostr-pwk"`) へ正規化
  (SDK 自身が読み込み時に旧誤値を自動正規化するため互換性は維持)。
- iOS: 新規 `NosskeyManager.swift` (`AuthenticationServices` ラッパー、iOS 18+ 必須)
  + `NosskeySigner.swift` (`EventSigner` 実装)。iOS 17 ではフォールバックとして
  従来の nsec 登録を残し、UI に「パスキー対応は iOS 18 以降で利用できます」と明示。
- Android: 新規 `NosskeyManager.kt` (`androidx.credentials.CredentialManager`
  ラッパー、API 28+ 必須) + `NosskeySigner.kt` (`AppSigner` 実装)。

3 プラットフォームすべてで:

- 既定 salt は `"nostr-pwk"` (hex `6e6f7374722d70776b`) で統一。
- 永続化するのは `{ credentialId, pubkey, salt, username? }` のみ。秘密鍵は
  ディスクに残らない。
- 新規登録ウィザードは Passkey 経路で **5 ステップ** (welcome → relay → profile
  → tutorial → success)。nsec 経路は従来通り 6 ステップ (welcome → backup → … )。

## Alternatives Considered

### Encryption/Decryption Method を採用する

- 既存の nsec 移行 (import) も同じ仕組みでカバーできる利点があった。
- しかし「PRF 出力が高エントロピーなのに NIP-49 scrypt や AES-GCM ラップを
  足す価値が薄い」「保存物が増えると XSS / バックアップ漏洩のリスク面積が広がる」
  という nosskey-sdk のスペック (`docs/en/nosskey-specification.en.md`) の議論を
  支持し、新規登録専用は PRF Direct Method に絞った。
- nsec import は別ルート (Web は nostr-login の `local` メソッド、iOS/Android は
  既存の nsec 直接入力) で引き続き提供する。

### Passkey を「Keychain / Keystore 解錠のゲート」としてだけ使う

- iOS では `kSecAttrAccessControl + .biometryCurrentSet` で nsec を Face ID で
  保護する案が候補に挙がった。
- しかしこれは「秘密鍵を生成し続ける」モデルから抜け出せず、デバイス移行・
  リカバリ・複数デバイス利用 (iCloud Keychain / Google Password Manager の同期)
  の体験で PRF Direct Method に劣る。
- 採用しない。

### iOS 17 でも Passkey 体験を提供する

- iOS 17 には WebAuthn の PRF 拡張がないため、PRF Direct Method は実装不可能。
- iOS 17 のために別フローを書き分けると保守コストが倍化する。「iOS 18 以降」
  と明示しつつ、iOS 17 ユーザーには従来の nsec フローを温存する判断にした。
- 1.6.x で deployment target を iOS 18.0 に bump する選択肢は将来 ADR で再検討する。

## Why this fits NuruNuru

- [[../culture/principles|五箇条]] の「美意識を制度化する」: 「nsec をユーザーに
  見せて『絶対無くすな』と告げる」のは Nostr 慣習だが美しくない。Passkey で
  代替できるなら nsec 表示を撤去するのが正しい (Passkey 経路は backup ステップを
  完全に廃止する)。
- [[../culture/not-doing|やらないことリスト]] の「初心者ユーザーに 32 バイトの
  hex を扱わせない」方針と整合。
- [[../culture/four-freedoms|4 軸自由ドクトリン]] の「経済的自由・配布の自由」を
  害さない: Passkey は Apple / Google にロックインしているが、いつでも nsec
  export で離脱できる経路を残してある (設定 → Nosskey 設定 → nsec 表示)。

## Consequences

### 良い影響

- 新規ユーザーの「秘密鍵バックアップ」ステップが消える (Passkey 経路)。
- 秘密鍵がディスクに残らないため、デバイス盗難・root 取得時の漏洩リスクが低下。
- iCloud Keychain / Google Password Manager 経由で複数デバイスに自動同期される。
- 3 プラットフォームで salt 値が統一され、`6e6f7374722d70776b` を使う将来の
  Nostr クライアント (nosskey app, 他の nosskey-sdk 利用者) と相互運用可能になった。
- iOS / Android で `EventSigner` / `AppSigner` 抽象が成立し、将来の
  NIP-46 / NIP-55 / Passkey 以外の signer 追加が容易になった。

### 悪い影響 / 技術的負債

- iOS 17 では Passkey 経路が無効。`#available(iOS 18.0, *)` ガードが点在する。
- 本番デプロイには `https://www.nullnull.app/.well-known/apple-app-site-association`
  と `https://nullnull.app/.well-known/assetlinks.json` の整備が必須。これらが
  ない間は Simulator / Emulator のみで動作確認可能。
- Android `NosskeySigner` の PRF 取得は毎回 `Activity` が必要 (バイオメトリ
  ダイアログを出すため)。バックグラウンド再同期 (`syncRelayListOnLogin` 等) では
  Activity を持てない呼び出し経路があり、現状はそこをスキップしている (TODO)。
- iOS `NosskeyManager` は `@MainActor` 隔離のため、`AuthViewModel.init` から
  呼ぶときに `MainActor.assumeIsolated` のラップが必要 (App 起動経路は main
  thread なので妥当)。
- 5 ステップ / 6 ステップ分岐が `SignUpModal` / `SignUpSheet` の progress 計算に
  入り込んだ。今後ステップを増減するときの注意点として
  [[../features/onboarding|features/onboarding]] に記載した。

### 将来の見直し条件

この ADR を撤回・更新すべきトリガー:

1. WebAuthn PRF 拡張に深刻な脆弱性が発覚した、または iOS / Android の
   Passkey 実装で PRF 出力の確定性が崩れる仕様変更があった場合。
2. Apple / Google が Passkey の同期を意図的に劣化させ、ユーザーが
   デバイス移行で identity を失うクレームが多発した場合。
3. Nostr エコシステムが「Passkey 由来鍵」を一級市民として扱わず、Zap や DM の
   経路で具体的な機能不全が発生する場合。
4. iOS 17 サポートを完全に切れる時 (deployment target iOS 18.0+) は ADR-0011
   などで `#available` ガード撤去を別途決議する。
