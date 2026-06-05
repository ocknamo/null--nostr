# 4軸自由ドクトリン (Four Freedoms Doctrine)

## Status

`Proposed` (長期ミッション、Charter v0.1 の北極星を支える)。実装着手の前提として [[../decisions/adr-0008-four-freedoms-mission|ADR-0008]] を参照。

## Summary

ぬるぬるが10年先を狙う上で、Nostr / Bitcoin / mini-apps を**4つの自由軸**として再整理した戦略文書。コミュニケーションだけでなく経済と配布まで、中央集権検閲を経由せずに日常体験に落とすことを目指す。

## 4つの自由

| # | 軸 | 守るもの | 中央集権の脅威 | ぬるぬるの基盤 |
|---|---|---|---|---|
| 1 | **言論の自由** | 発言・公開・引用 | プラットフォーム凍結 / モデレーション偏向 | Nostr リレー (NIP-01 / 65 / 70) |
| 2 | **プライバシーの自由** | 私信・所属の秘匿 | 企業による収集・プロファイリング | NIP-44 / NIP-17 / Marmot MLS / NIP-46 |
| 3 | **経済活動の自由** | 受け取り・送り・売る | Visa/MC/銀行口座の遮断、決済代行の表現規制 | Lightning / NIP-57 Zap / NIP-47 NWC / 将来 Cashu |
| 4 | **流通・配布の自由** | コード・コンテンツの配信 | App Store / Play / GitHub の審査・削除 | NIP-89 handlers / kind 30023 / 署名付きバンドル |

軸 1 / 2 は既に [[../platforms/parity-matrix|現行実装]] でカバーされている。軸 3 / 4 は段階的に実装する。

## なぜ「日本の日常」で強いか

日本市場での説得力は、欧米的クリプト自由主義の輸入ではなく、**既存の日本文化との接続性**に由来する。

| 領域 | 日本固有の状況 | ぬるぬる × Nostr が刺さる理由 |
|---|---|---|
| 決済検閲 | Visa/MC 経由で DLsite / FANZA / Pixiv / 同人誌業者への圧力が常態化 | 投げ銭文化が既にある国で、Zap = 「主権的おひねり」として違和感ゼロ |
| 銀行アクセス | 外国人 / フリーランス / 表現者の口座開設が硬い | ウォレット = 銀行口座代替が、ニーズが見えている層に直接刺さる |
| アプリ配布 | 同人ソフト / 個人開発 / 成人向けは AppStore 審査と相性が悪い | コミケ / 同人文化を**ネイティブに飲み込める配布レール**は、日本市場が最も準備できている |
| プラットフォーム依存 | LINE が事実上の社会インフラ化 | 「LINE と同じ手触りで、自分の鍵で動く」と言える日本語クライアントは現状ゼロ |

## 設計原則 (4軸共通)

1. **思想は基盤に、所作は表層に。** 「Bitcoin」「dApp」「Web3」を UI 表面に出さない。
2. **既存の日本語日常語に擬態させる。** Zap → おひねり、mini-app → 道具 / あそび、wallet → お財布。
3. **ストア審査と恒常的に共存する設計。** 配布の自由を持ちながら、本体配布の継続性を守るネーミング・UI を選ぶ。
4. **4軸を**「同時にやる」**のではなく**「同時に**設計する**」。実装は順序立てる (後述ロードマップ)。

## 軸ごとの実装方針 (概略)

### 軸 1: 言論 (Speech)

- 言論の自由は、発言・公開・引用・退出の自由を指す。全員のタイムラインに表示される権利ではない。
- ぬるぬるは **発言権と表示 / 到達権を分ける**。Nostr event は公開できるが、主要 UI に表示するかはフォロー graph、2-hop trust graph、starter graph、mute / block / report、共同体境界で判断する。
- iOS / Android / Web はすべて投稿可能なクライアントとして維持する。ネイティブアプリだけを閲覧専用にする投稿制限は採用しない ([[../decisions/adr-0021-open-speech-scoped-reach|ADR-0021]])。
- リレー生フィードを主要 UI に置かないことは検閲ではなく、共同体と日常体験を守る表示設計である ([[../decisions/adr-0013-relay-feed-removal|ADR-0013]])。

### 軸 3: 経済 (Economy)

- **NIP-57 Zap** を「投げ銭」「おひねり」「ご祝儀」として LINE スタンプ送信レベルの軽さで再設計する。
- **NIP-47 NWC (Nostr Wallet Connect)** を採用し、ウォレットを「お財布」として裏で接続する。
- **将来**: Cashu eCash / merchant flows (NIP-15 系) / 法定通貨換算の任意表示。
- **やらないこと**: VISA / MC / 国内銀行への依存、KYC を前提とする UI、価格を恐怖訴求で見せる行為。

### 軸 4: 配布 (Distribution)

- **NIP-89 Client Handlers** と **kind 30023 long-form** を組み合わせ、ぬるぬる内で「道具 / あそび」として外部機能を提示する。
- **署名付きバンドル**で配布の出所と完全性を保証する。任意のコード実行は許可せず、サンドボックスとパーミッション境界を必ず通す。
- **やらないこと**: 「dApp」「Web3」呼称、AppStore / Play との意図的な敵対表現、無署名コードの実行。

## ロードマップ (実装順)

ぬるぬるの強みは「日常体験の polish」であり、これを守ることが10年戦略の前提。同時着手は polish を破壊する。

| Phase | 期間目安 | 軸 | 主タスク |
|---|---|---|---|
| 0 | 進行中 | 1 / 2 | Charter v0.1 確立、Design Crit 制度化、既存通信機能の磨き込み |
| 1 | + 3〜6ヶ月 | 1 / 2 | Talk (Marmot MLS) の完成、parity matrix のホワイト化 |
| 2 | + 6〜12ヶ月 | 3 | Zap UX 再設計 (「おひねり」化)、NIP-47 NWC、merchant flows のα |
| 3 | + 12〜24ヶ月 | 4 | mini-app 配布基盤のα、署名・サンドボックス、初期 mini-apps |
| 4 | + 24ヶ月〜 | 1〜4 | Charter v1.0 昇格、4軸統合のフルパッケージ化 |

各 Phase は前 Phase の polish を犠牲にしてはならない。Polish が落ちた場合、ロードマップを止める。

## 失敗モード

| 失敗モード | 兆候 | 防御 |
|---|---|---|
| 思想先行 | 「ぬるぬるは Web3 アプリ」と語られ始める | [[copy-style]] と [[not-doing]] に明示。表層から思想語彙を排除 |
| 同時着手 | Phase 2 / 3 / 4 を並行 | ロードマップを ADR で厳守。例外には ADR-NNNN を要求 |
| スーパーアプリ膨張 | タブが10個に増える | [[principles|第一条「日常を壊さない」]] / 第四条「一貫性は新機能より重い」 |
| ストア排除 | App Store / Play から消える | Phase 4 までストア審査と共存できる命名・UI を維持 |

## Open Questions

- Charter v1.0 への昇格タイミングは「Phase 2 完了時」か「Phase 3 完了時」か。
- 4軸を Charter の**第六条**として追加するか、別文書のままにするか。
- iOS / Android / Web のうち、軸 3 / 4 のα着地はどのプラットフォームから行うか。
- mini-app 実行環境 (WebView ベース / WASM / 制限付き JS) の選定。
- 経済軸を Lightning に限定するか、Cashu / eCash まで早期に含めるか。

## Related pages

- [[principles]]
- [[not-doing]]
- [[copy-style]]
- [[../decisions/adr-0008-four-freedoms-mission]]
- [[../decisions/adr-0021-open-speech-scoped-reach]]
- [[../platforms/parity-matrix]]
- [[../nips/nip-57]]

## Source references

- [[principles]]
- [[../nips/nip-57]]
- [[../nips/nip-65]]
- [[../nips/nip-70]]
- [[../decisions/adr-0008-four-freedoms-mission]]
- [[../decisions/adr-0021-open-speech-scoped-reach]]
- `AGENTS.md`
