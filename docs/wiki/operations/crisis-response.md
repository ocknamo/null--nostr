# Crisis Response — Trust Surface FAQ

## Summary

ぬるぬるのマーケティング / 成長戦略では、短期流入よりも trust surface を重視する。外部露出・ストア審査・Nostr 上の議論で誤解や懸念が出たとき、恐怖を煽らず、専門用語を浴びせず、事実と設計判断を落ち着いて説明する。

このページは、想定される 5 つの危機 / 誤解シナリオに対する返答方針とコピー候補をまとめる。

## Current behavior

現状は個別の ThemaDAY / strategy / copy-style に trust surface 方針が分散している。本ページは外部向け返答の初期テンプレートとして集約する。

## Response principles

1. **やわらかい敬体**で返す。
2. 最初の返答で Nostr / relay / NIP / pubkey などの専門語を出しすぎない。
3. 技術詳細は「詳しく知りたい人向け」に畳む。
4. 秘密鍵・署名・鍵管理の話は事実だけ伝え、恐怖を煽らない。
5. 反論ではなく、不安の解像度を上げる。
6. 未確認事項は「確認します」と言い、断定しない。
7. ガードレール違反の疑いがある場合は成長施策を止め、Design Crit / ThemaDAY に戻す。

## Scenario 1 — 「危ないアプリでは？」

### Short response

ぬるぬるは、メールアドレス・電話番号・パスワードなしではじめられる SNS です。広告は出さず、位置情報や購買履歴なども集めません。アカウントの鍵は、できるだけ端末の安全な場所で扱う設計にしています。

### Detail

- Web / Android / iOS で秘密鍵を不用意にログへ出さない。
- iOS は Keychain、Web は module closure、Android は platform signer / Rust FFI の制約を守る。
- OpenSats Nostr Grant と source code / wiki により、外部から検証できる trust surface を持つ。

## Scenario 2 — 「違法コンテンツやスパムが流れるのでは？」

### Short response

ぬるぬるでは、誰でも何でも流れてくる生のリレーフィードは主要画面から外しています。最初に見えるものは、フォロー関係や安全な候補をもとに絞る方針です。

### Detail

- リレーフィードは廃止済み。
- News / Mini Apps / discovery は 2-hop trust graph 型に制限する方針。
- mute / block / report label を優先する。
- safe starter graph は任意リレー生フィードの復活ではない。

## Scenario 3 — 「Nostr って何？」

### Short response

ひとことで言うと、会社のサーバーだけにアカウントを預けないための、分散型のしくみです。ぬるぬるでは、難しい部分はできるだけ裏側に隠して、ふつうの SNS として使えるようにしています。

### Detail

- 初心者向け画面では relay / NIP / pubkey といった語を出さない。
- 開発者向けには NIP support map / source references を出す。

## Scenario 4 — 「鍵をなくしたら？」

### Short response

鍵はアカウントそのものなので、とても大事です。ぬるぬるでは、指紋や顔認証で使えるパスキー経路を用意し、できるだけ安全に扱えるようにしています。ただし、どの方法でも完全に万能ではないので、復旧できる範囲は使い方によって変わります。

### Detail

- Passkey / Nosskey 経路では OS の passkey 同期による復旧可能性がある。
- nsec / private key の扱いは安全画面でのみ説明する。
- 秘密鍵を UserDefaults / window.* / logs へ出さない。

## Scenario 5 — 「ストアから消えたら？」

### Short response

ぬるぬるは、Web、Android、iOS など複数の配布先を持っています。ストアで使える形を大切にしながら、ひとつの配布先だけに依存しない設計を進めています。

### Detail

- GitHub Releases / Zapstore / Web PWA など複数の配布面がある。
- ただし、ストア審査と意図的に衝突する表現は避ける。
- 配布の自由は Four Freedoms の長期軸であり、Phase 0 では落ち着いて整備する。

## Escalation matrix

| Severity | Example | Action |
|---|---|---|
| P0 | 秘密鍵漏洩、署名不能、重大クラッシュ | Release STOP / hotfix / public note |
| P1 | 違法コンテンツ導線、ストア審査重大リスク | Growth施策停止 / Design Crit |
| P2 | 誤解が広がる外部投稿、記事誤記 | Calm reply / fact-check / wiki update |
| P3 | 個別質問、軽微な用語誤解 | FAQ 誘導 / 次回 copy 改善 |

## Copy style notes

- ❌「Nostr は検閲耐性があり…」
- ✅「会社のサーバーだけにアカウントを預けないしくみです。」

- ❌「秘密鍵を紛失すると全て終わりです」
- ✅「鍵はアカウントそのものなので、とても大事です。復旧できる範囲は使い方によって変わります。」

- ❌「違法コンテンツはプロトコル上防げません」
- ✅「生のリレーフィードは主要画面から外し、最初に見えるものを安全側に絞っています。」

## Platform notes

- Web / Android / iOS の安全説明は、それぞれの実装 guardrails と矛盾させない。
- ストア向けコピーと一般ユーザー向けコピーは、同じ事実を別の粒度で書く。
- 開発者向け詳細は wiki / source references へ逃がす。

## Source references

- `docs/wiki/strategy/themaday-2026-06-03-marketing-growth.md`
- `docs/wiki/culture/principles.md`
- `docs/wiki/culture/not-doing.md`
- `docs/wiki/culture/copy-style.md`
- `docs/wiki/culture/four-freedoms.md`
- `docs/wiki/strategy/june-2026-roadmap.md`
- `docs/wiki/decisions/adr-0013-relay-feed-removal.md`
- `docs/wiki/decisions/adr-0014-local-first-product-metrics.md`
- `docs/wiki/decisions/adr-0020-safe-starter-graph.md`

## Related pages

- [[../strategy/themaday-2026-06-03-marketing-growth]]
- [[../decisions/adr-0020-safe-starter-graph]]
- [[../culture/copy-style]]
- [[feedback-loop]]

## Open questions

- どの FAQ を README / nullnull.app に出し、どれを wiki-only にするか。
- ストア審査向け説明と一般ユーザー向け説明を分けるか。
- P1 以上の crisis が起きた場合の Nostr 公式 npub 投稿テンプレを別途作るか。
