# ADR-0020: Safe Starter Graph for First Home Experience

## Status

Proposed — 2026-06-03

## Summary

新規ユーザーが登録後に空の Home を見て離脱しないように、初回 Home で安全な日本語投稿が見える **safe starter graph** を導入する。ただし、リレーフィード廃止の判断を反転させず、任意リレー生フィードを復活させない。

表層コピーでは Nostr / relay / graph などの専門用語を出さず、「日本語の投稿が見られるようにする」「はじめた人たちの投稿を見る」程度の日常語にする。

## Context

6月ロードマップではリレーフィードを廃止し、発見面を 2-hop trust graph 型に制限する方針が確定している。一方で、新規ユーザーにとって空の Home は強い離脱要因であり、Week-1 復帰率の改善を阻害する。

2026-W23 Design Crit では、safe starter graph の必要性は合意されたが、管理責任・更新頻度・悪用防止・表層コピーを詰める必要があるため REVISE 判定となった。

## Decision

初回 Home には、以下の安全な starter graph 候補を用意する。

1. 公式 npub
2. ぬるる npub (本格運用前は素材 / 絵文字 / 図鑑導線のみでも可)
3. 手動管理された日本語 starter account list
4. `#nostrはじめました` の直近投稿 (安全フィルタ / 2-hop / 手動確認の範囲に限定)

ただし、これらは **自動フォロー**ではなく、初期表示・おすすめ・導線の候補として扱う。自動フォローを行う場合は、別途 Design Crit と ADR が必要。

## Current behavior

Home renewal は「アクティビティ / コンテンツ」の2層構造へ向かっている。任意リレー生フィードは削除済み。starter graph はまだ実装されていない。

## User-facing copy candidates

| 内部概念 | 表層コピー候補 |
|---|---|
| starter graph | 日本語の投稿が見られるようにする |
| follow recommendation | はじめに見る人 |
| official account | ぬるぬるからのお知らせ |
| nuruh account | ぬるるの投稿 |
| hashtag onboarding | はじめた人たちの投稿 |

## Guardrails

- 任意リレー生フィードを復活させない。
- starter account list を「公式おすすめユーザー」と強く見せすぎない。
- 政治・宗教・成人向け・違法性が高い文脈に見える account は Phase 0 では入れない。
- リスト管理者が恣意的にユーザー関係を支配しないように、更新履歴を wiki / issue に残す。
- ミュート / ブロック / report label は常に優先する。
- Nostr 用語を初心者向け画面に出さない。

## Ownership

| Hat | Responsibility |
|---|---|
| Product / Growth hat | starter graph の目的と成功条件 |
| Culture / IP Lead | 日本語コピーと文化適合 |
| Quality / NPS Lead | manual cohort での離脱観察 |
| Wiki / Knowledge Lead | リスト更新履歴と ADR 更新 |
| Engineering Lead | 実装時の安全境界と platform parity |

## Alternatives considered

1. **何もしない** — Home が空になり、Week-1 復帰率を改善しにくい。
2. **任意リレー生フィードを復活** — リレーフィード廃止の安全判断と衝突するため不可。
3. **完全自動フォロー** — ユーザー主権を弱めるため Phase 0 では避ける。
4. **公式アカウントのみ表示** — 安全だが、日常の人間感が薄い。
5. **2-hop trust graph のみ** — 既存 Nostr ユーザーには良いが、一般ユーザーは graph が空で機能しない。

## Consequences

### Positive

- 初回 Home の空白を減らせる。
- Week-1 復帰率の改善につながる可能性が高い。
- リレーフィード廃止と両立しながら、Nostr の開放性を安全に翻訳できる。

### Negative / risks

- starter list が実質的な editorial power になる。
- 管理が属人化すると信頼を失う。
- 表層コピーを誤ると「勝手にフォローされた」と感じられる。
- 公式 / ぬるるへの依存が強くなりすぎる可能性がある。

## Platform notes

- Android / iOS / Web で同じ説明と同等の初期候補表示にする。
- 1プラットフォームだけ starter graph を先行させる場合は ADR / Design Crit で理由を残す。
- 初期候補表示は秘密鍵 / signer / DM と無関係に実装する。

## Open questions

- starter account list の初期人数は何人が適切か (5 / 10 / 20)。
- starter list の更新頻度は週次か月次か。
- リストに入る / 外れる基準を公開するか。
- `#nostrはじめました` 投稿をどこまで自動で拾うか。
- 自動フォローではなく「見る候補」として UI に出す場合の具体デザイン。

## Source references

- `docs/wiki/strategy/themaday-2026-06-03-marketing-growth.md`
- `docs/wiki/culture/crit-logs/2026-W23.md`
- `docs/wiki/strategy/june-2026-roadmap.md`
- `docs/wiki/culture/not-doing.md`
- `docs/wiki/culture/copy-style.md`
- `docs/wiki/decisions/adr-0013-relay-feed-removal.md`
- `docs/wiki/decisions/adr-0015-home-tab-renewal.md`

## Related pages

- [[../strategy/themaday-2026-06-03-marketing-growth]]
- [[../culture/crit-logs/2026-W23]]
- [[../quality/manual-cohort-observation]]
