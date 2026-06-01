# ストア掲載コピー (Store Listing Copy)

## Summary

ぬるぬるのストア・README 掲載コピーを「指紋や顔認証だけではじめられる、あたらしい SNS」というポジショニングに統一した。
表層コピーでは "Nostr" を使わない ([[../culture/not-doing|not-doing]] / [[../culture/principles|五箇条 三]] に整合)。技術ドキュメント・開発者向けページでは固有名詞として引き続き使う。

OpenSats 関連のクレジットは事実情報として README に残す。OpenSats Nostr Grant の固有名詞はそのまま使ってよい。

## ポジショニングの骨子

- **見出し**: 指紋や顔認証だけではじめられる、あたらしい SNS。
- **英文**: A social app you start with just your fingerprint or face. No email, no phone number, no password.
- **要素**:
  - メール / 電話番号 / パスワード不要
  - 指紋や顔認証で開始
  - チャットはデフォルトで暗号化
  - 広告なし
  - 子供の有無、最終学歴、職業、業種などの属性情報を収集しない
  - 位置情報、決済・購買などの行動履歴を収集しない
  - アカウントは端末の中にあるので、運営凍結も電話番号バレもない

## チャネル別の文字数と現状コピー

| チャネル | 上限 | 採用コピー (要約) |
|---|---|---|
| README 見出し (JP) | — | 指紋や顔認証だけではじめられる、あたらしいSNS。 |
| README 見出し (EN) | — | A social app you start with just your fingerprint or face. No email, no phone number, no password. |
| Google Play title | 30 | ぬるぬる |
| Google Play short_description | 80 | 指紋や顔認証だけではじめられるSNS。チャット暗号化、広告なし、行動履歴の収集なし。 |
| Google Play full_description | 4000 | README 本文を流用 + 機能リスト |
| App Store name | 30 | ぬるぬる |
| App Store subtitle | 30 | 指紋・顔認証ではじめるSNS |
| App Store promotional_text | 170 | メールも電話番号もパスワードも不要。チャットはデフォルトで暗号化。広告なし。属性情報・位置情報・決済や購買などの行動履歴を収集しません。 |
| App Store description | 4000 | README 本文を流用 + 機能リスト |
| App Store keywords | 100 | SNS,生体認証,指紋認証,顔認証,プライバシー,パスワードレス,メッセージ,日本語,軽量,自由 |
| zapstore.yaml summary | ~80 | 指紋や顔認証だけではじめられる、あたらしいSNS。 |
| 公式サイトヒーロー下 | — | メールも電話番号もパスワードもいりません。 |


## データ収集なしコピー

ストア / README では以下を明示する。

- チャットはデフォルトで暗号化される。
- 広告は出さない。
- 子供の有無、最終学歴、職業、業種などの属性情報を収集しない。
- 位置情報を収集しない。
- 決済・購買などの行動履歴を収集しない。

## 用語マッピング (表層 / 内部)

| 内部用語 | ストア・README で使う語 |
|---|---|
| Nostr | (使わない。必要なら「分散型のしくみ」「あなたの端末の中のアカウント」と言い換える) |
| relay | 届け先 / 配送先 |
| pubkey / npub | (見せない。必要なら「あなたの目印」) |
| nsec / private key | (絶対に表に出さない) |
| signer / NIP-46 / Amber | 外部の鍵管理アプリ |
| DM / NIP-17 / MLS | トーク / ダイレクトメッセージ / グループチャット |
| Zap / Lightning / invoice | おひねり / ありがとうを少額で送る / 外部のお財布アプリ |
| mini-app | ミニアプリ / 道具 / あそび |

## 注意点

- ストア審査向けに「電話番号も、パスワードもいらない」は事実として正しい (起動時の必須入力なし、Keychain / Android Keystore に鍵を生成して指紋・顔認証でロック)。
- 「アカウントはあなたの端末の中」は鍵保管の事実説明。ストア審査者が機能の所在を確認できる文言にしている。
- OpenSats 関連テキストでは OpenSats Nostr Grant の固有名詞を使ってよい。

## Source references

- `README.md` — 見出し / 日本語イントロ / English intro
- `zapstore.yaml` — summary, description, tags
- `fastlane/metadata/android/ja-JP/{title,short_description,full_description}.txt`
- `fastlane/metadata/ios/ja/{name,subtitle,promotional_text,description,keywords}.txt`
- [[../culture/copy-style]] — 直訳禁止、既存採用コピー保護
- [[../culture/not-doing]] — Nostr 用語を初心者向け画面に浴びせない
- [[../culture/principles]] — 五箇条 三 (複雑さは裏側に隠す)

- components/LoginScreen.js — 公式サイト / PWA の未ログイン時ヒーローコピー
- app/layout.js, public/manifest.json — 公式サイト / PWA メタデータ

## Related pages

- [[../culture/copy-style]]
- [[../culture/not-doing]]
- [[../culture/four-freedoms]]

## Open Questions

- Google Play / App Store の en-US / en ロケールを切るか? (現状 ja のみ)。切る場合は同じトーンで英訳ペアを起こす。
- 「ぬるぬる」というブランド名と「指紋・顔認証で動く SNS」というポジショニングが、検索流入で衝突しないか検証 (ストア検索キーワード A/B)。
- "あたらしい SNS" は他社が広く使う表現。ぬるぬる固有の差別化フレーズ (例:「鍵だけで動く SNS」「端末の中だけの SNS」) を将来差し替え候補にする。
- 公式サイトヒーローは「指紋や顔認証だけではじめられる、あたらしい SNS。」+「メールも電話番号もパスワードもいりません。」の二段構成で運用する。
