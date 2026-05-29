# ADR-0012: 月曜リリース列車と Nuru Production System を採用する

## Status

Accepted (2026-05-29)。CI / scheduler / GitHub labels などの機械的 enforcement は未実装だが、release / quality / culture の判断規約としては本日から有効。

## Context

Thema DAY「企業文化 / カルチャー構築」の方針として、以下が明示された。

- 週刊少年ジャンプのように、リリースサイクルを月曜日へ固定する。
- 品質管理と安定のために、トヨタ生産方式 (TPS) を導入する。
- ぬるぬるは Nostr 最高品質でなければならない。
- 実機テストは、iOS / Android / Web を同じ時間に曖昧に触るのではなく、午前 iOS・午後 Android のように platform ごとの時間帯を分ける。
- テストは「日常的に使う」だけではなく、明示した test case を一つずつ丁寧に、複数周回して確認する。
- 目標はトヨタのような世界最高水準の品質と、安定した供給である。

ぬるぬるは Web / Android / iOS / Rust Engine をまたぐ Nostr クライアントであり、単一プラットフォームのスピードだけを追うと、署名・鍵管理・relay 挙動・Talk MLS・日本語 UI・store 配布のどこかが崩れる。既に [[../culture/principles|Charter v0.1]] は「日常を壊さない」「一貫性は新機能より重い」「かわいさと、秘密鍵への厳格さを、同時に持つ」を掲げているが、release cadence と品質停止権限は明文化されていなかった。

また、[[../operations/feedback-loop]] では自動化境界として「merge / production release / signing / secrets は human-approved」としている。これを release rhythm と quality system に接続する必要がある。

## Decision

ぬるぬるは月曜リリース列車を採用する。定期公開は原則として月曜日 (JST) に集約し、金曜夜・週末の通常リリースは避ける。月曜日に品質ゲートを通らない場合は、リリースを強行せず HOLD / STOP として次の列車へ回す。

同時に、TPS を Nostr クライアント向けに翻訳した Nuru Production System (NPS) を採用する。NPS は以下を中核とする。

1. Jidoka: 秘密鍵・署名・重大クラッシュ・データ損失・Talk 破壊・NIP 互換性破壊は release line を止める。
2. Andon: 異常は STOP/HOLD/HOTFIX として見える化し、理由を1行で残す。
3. Just-in-Time / small batch: 月曜列車へ載せる差分を小さくし、巨大機能の駆け込みを避ける。
4. Heijunka: 金曜夜や週末に負荷を寄せない。
5. Standardized Work: release checklist、build/test、wiki/log、release notes、platform 別実機 test slot の順序を標準化する。
6. Genchi Genbutsu: 実機・実 relay・実 store・実 Nostr 投稿で確認する。
7. Kaizen: escaped defect は 5 Whys で原因を残し、次の月曜列車までに標準作業を1つ改善する。

詳細運用は [[../culture/release-quality]] に置く。運用ページは数値・チェックリスト・曜日ごとの作業を更新できるが、「月曜リリース列車」「NPS」「品質ゲート失敗時は出さない」「platform ごとの dedicated 実機テスト slot」「test case に基づく反復確認」という中核判断を変える場合は、本 ADR の改訂または後続 ADR を必要とする。

## Alternatives Considered

1. 随時リリース — 速度は上がるが、週末障害・platform parity 崩れ・release notes 漏れが増える。Charter 第四条「一貫性は新機能より重い」と衝突する。
2. 金曜リリース — 一般的な週末前公開だが、障害初動が週末に乗り、個人開発 / 小規模チームには過負荷。品質文化に反する。
3. 月末まとめリリース — 安定しやすいが batch size が大きくなり、Nostr protocol / UI regression の原因特定が遅れる。
4. 完全自動 release train — 将来の一部自動化は有効だが、現時点で secrets / signing / store / Design Crit を機械判断に委ねるのは [[../operations/feedback-loop]] の境界に反する。
5. 日常 dogfood のみ — 実体験は重要だが、test case と記録がなければ再現性がなく、トヨタ級の安定供給には届かない。
6. TPS を採用せず通常 QA だけにする — build/test の羅列に留まり、「異常なら止める」「原因を潰す」「標準作業を改善する」が文化として残らない。

## Why this fits NuruNuru

- 第一条「日常を壊さない」: 月曜日固定と STOP/HOLD により、週末障害や不完全 release で日常体験を壊さない。
- 第二条「日本語を第一級市民にする」: 週刊少年ジャンプ型のリズムは日本語圏の「毎週月曜に届く」感覚と相性がよい。release communication も日本語コピー品質を gate に含める。
- 第三条「複雑さは裏側に隠す」: NIP / relay / FFI / signing の複雑さは NPS の裏側 gate で吸収し、ユーザーには安定した日常体験として渡す。
- 第四条「一貫性は新機能より重い」: platform parity gate と platform 別実機 slot により、1プラットフォームだけの先行破壊を防ぐ。
- 第五条「かわいさと、秘密鍵への厳格さを、同時に持つ」: 秘密鍵・署名・暗号化ストレージの異常は最優先で release line を止める。
- [[../culture/not-doing|やらないこと]]: DAU / star / 短期話題化のために品質を曲げない。自動化ができることと、自動 release してよいことを混同しない。

## Consequences

### 良い影響

- Release rhythm と platform 別実機テスト時間割が固定され、ユーザー・メンテナ・LLM エージェントが同じ時間軸で動ける。
- 品質ゲート不通過時に「出さない」判断が文化的に正当化される。
- Nostr protocol correctness、relay resilience、秘密鍵保護、platform parity を release 判断の中心へ置ける。
- 実機テストが「なんとなく触った」から「項目・結果・再確認が残る標準作業」へ変わる。
- escaped defect が単発の謝罪で終わらず、5 Whys と標準作業更新へ接続される。
- Thema DAY / Design Crit / feedback loop / release recipe が一つの運用体系に接続される。

### 悪い影響 / 技術的負債

- 月曜固定により、完成済み機能の公開が最大1週間遅れる。
- Platform 別実機 slot により、release candidate test day の拘束時間が増える。
- Store review の遅延により、実際の Google Play / App Store 公開日が月曜からずれる可能性がある。
- 小規模チームでは Release conductor / Quality owner / Platform test owner / Protocol owner / UX owner を兼務するため、役割分離が形式化しやすい。
- 現時点では CI / GitHub labels / release dashboard / test record template が未整備で、人間の規律に依存する。
- TPS 用語が形骸化すると、逆に品質問題を隠す儀式になるリスクがある。

### 将来の見直し条件

- 4回連続の月曜列車運用後、GO/HOLD/STOP/HOTFIX 件数、実機 test completion、escaped defect を Design Crit でレビューする。
- Store review の実測により、月曜を「提出日」とするか「公開日」とするかを再定義する必要が出た場合。
- CI / scheduler / GitHub labels / test record template による enforcement を導入する場合。
- Platform parity debt が増え、月曜列車だけでは同期しきれない場合。
- P0/P1 の定義が現実の障害と合わない場合。

## Source references

- [[../culture/release-quality]] — 月曜リリース列車と Nuru Production System の運用詳細。
- [[../culture/principles]] — Charter v0.1。
- [[../culture/not-doing]] — やらないことリスト。
- [[../culture/design-crit]] — Weekly Nuru Design Crit。
- [[../operations/feedback-loop]] — automation と human approval 境界。
- [[../operations/goose-recipes]] — release recipe context。
- [[../platforms/parity-matrix]] — platform parity 管理。
- [[../ui/android-ios-sync]] — Android / iOS pixel-perfect guardrails。
- AGENTS.md — build/test/release commands and platform guardrails。
- docs/sync/CHECKLIST.md — existing release checklist precedent。
- User directive (2026-05-29): Thema DAY 企業文化 / カルチャー構築、月曜固定リリース、TPS、Nostr 最高品質。
- User directive (2026-05-29): platform ごとの実機テスト時間割、明示 test case に基づく反復確認、トヨタ級の安定供給。
