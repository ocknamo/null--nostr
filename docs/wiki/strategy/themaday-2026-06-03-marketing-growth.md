# ThemaDAY 2026-06-03 — マーケティング & 成長戦略 / コミュニケーション (統合版 v2)

## Status

**Synthesized** (2026-06-03 19:16 JST)。Agent1 提案 + Agent2 批判的レビューを統合した最終版。
本ページが現行 working copy。前版 (v1) は git 履歴に残る。

## 戦略仮説 (再定義)

> ぬるぬるの成長は、新規流入を増やすことではなく、
> **初回投稿後 7 日以内に「戻る理由」を作ること**から始まる。
> その戻る理由は、広告ではなく、
> (1) **自分の投稿への反応**、(2) 日本語の日常感、(3) 安全な Home、
> (4) ぬるるの文化接点、(5) 外部から検証できる信頼 — の5つで作る。

## 1. ICP — 90日で誰を取るか (NEW / Agent2 提案を採用)

| 優先 | セグメント | 90日方針 | 主メッセージ |
|---:|---|---|---|
| 1 | 日本の Nostr 既存ユーザー | **主戦場** | 「日本語の日常として使える」 |
| 2 | プライバシー意識のある一般ユーザー | **主戦場** | 「指紋や顔認証だけ、広告なし」 |
| 3 | 絵師 / 同人 / クリエイター | Phase 1 以降 (おひねり整備後) | 「自分の場所を消されにくく」 |
| 4 | 開発者 / Nostr ecosystem | 受動 (Wiki/GitHub/Compass) | source-verifiable |

90日中は **1+2 に集中**。3 は IP / おひねりが整ってから、4 は trust surface で受動的に育てる。

## 2. 北極星 + 測定 (Agent2 補強)

> **Week-1 復帰率 = 新規登録後 7日以内に、2回目の起動 or 自分の投稿への反応を確認した人の割合**

ADR-0014 で製品計測コードは入れない。代わりに **manual cohort 観察プロトコル** を毎週回す。

### 週次スコアカード (manual / ThemaDAY 記録)

| 指標 | 入力元 | 目標 |
|---|---|---:|
| 新規登録観察人数 | 手動 | 5人/週 |
| 初投稿完了人数 | 手動 | 3人/週 |
| 初投稿後に反応を見た人数 | 手動 | 2人/週 |
| Week-1 復帰人数 | 手動 | 2人/週 |
| `#nostrはじめました` 投稿数 | NIP-50 search | 増加傾向 |
| `/p/<npub>` 招待リンク確認 | manual QA | 週1 |
| store page view / download | store CSV | 月次 |
| ガードレール違反 | Crit / review | 0 |

### KPI 6軸 + 補助2軸 (Nuruh IP §7 と同期)

Phase 1 (6ヶ月) 目標値は Nuruh IP v1.0 §7 をそのまま採用。Phase 0 (90日) は **Week-1 復帰率の cohort 観察が回ること** が成功条件。

## 3. 成長フレーム — AARRT v2

Agent1 案 (AARRT) を維持しつつ、**A3 Anchoring の主役を「初投稿への反応ループ」に再定義**:

```
A1 Acquisition  →  A2 Activation  →  A3 Anchoring (主役)  →  R Recommend  →  T Trust
  受動 +              5-step +            ★ 反応ループ ★          /p/ /e/ OG       Compass +
  小実験              starter graph       (ぬるるは脇役)          ぬるるアイコン   危機対応
```

### A1 Acquisition — 受動 + 小実験5本 (Agent2 補強)

| 施策 | リスク |
|---|---|
| Store screenshot 1枚目「メール/電話/パスワード不要」明示 | 低 |
| `/p/<npub>` OG カードを LINE/X/iMessage で見栄え確認 | 低 |
| ぬるぬる紹介投稿テンプレ (既存ユーザー向け) | 低 |
| 日本語 Nostr コミュニティに週1「今週よくなったこと」 | 低 |
| GitHub README first-time user 導線改善 | 低 |

**やらない**: 広告、SEO ハック、'Web3 SNS' を名乗っての検索流入狙い、Australia anomaly を成果扱い。

### A2 Activation — 5-step polish + safe starter graph (Agent2 補強)

Nostr / 分散 SNS の最大の初期離脱理由 = 「誰を見ればいいかわからない (空のネットワーク)」。
**裏側は 2-hop trust graph / curated account、表層は Nostr 用語を出さない**:

- 「日本語の投稿が見られるようにする」
- 「ぬるぬるからのお知らせを見る」
- 「はじめた人たちの投稿を見る」

実装最小:
1. 公式 npub を初期 follow 候補
2. ぬるる npub を初期 follow 候補
3. 日本語 starter account list を手動管理
4. `#nostrはじめました` 投稿者に公式 thumbs-up
5. 初回 Home に「ここに少しずつ投稿が並ぶよ」型の空状態

### A3 Anchoring — 主役は「自分の投稿に反応がつく」体験 (Agent2 提案)

| トリガー | 役割 |
|---|---|
| **★ 自分の初投稿に反応がつく** | **最強の復帰理由** |
| フォローした人の投稿が Home に出る | 日常化 |
| ぬるるのおやつ投稿 | 柔らかい再訪理由 |
| 週末ぬるる図鑑 | 文化参加 |
| 月曜リリース投稿 | 信頼形成 |
| 金曜「今週わかったこと」 | 開発への参加感 |

→ **ぬるるは復帰理由の一つに格下げ**。主役は反応ループ。
→ スケールしない手動運用で OK。Phase 0 は「人がいる感覚」を作るのが目的。

### R Recommend — /p/ /e/ OG の徹底 polish

最低限:
- LINE / X / iMessage / Discord で OGP 確認
- Android / iOS / Web の遷移確認
- 未インストール時 / インストール済み deep link 動作確認
- ぬるるアイコン素材集 (L1 / 商用可・改変可) を公開し、名刺化させる

### T Trust — Compass + Wiki + **危機対応** (Agent2 提案を採用)

平時の trust surface 更新に加え、**有事の返答テンプレ** を先に用意する:

| シナリオ | 返答方針 |
|---|---|
| 「危ないアプリでは？」 | メール/電話番号/パスワード不要・秘密鍵管理・広告なしを説明 |
| 「違法コンテンツが流れるのでは？」 | リレーフィード廃止・2-hop trust graph・mute/report を説明 |
| 「Nostr って何？」 | 表では説明しすぎない。必要なら「分散型のしくみ」だけ |
| 「鍵をなくしたら？」 | 怖がらせず事実説明 + Passkey 同期で回復可能なケースを案内 |
| 「ストアから消えたら？」 | Web / GitHub / Zapstore など配布の自由を静かに説明 |

## 4. コミュニケーション — 三声モデル (Agent2 補強)

声を **3 つに分け、混ぜない**:

| 声 | 役割 | 禁止 |
|---|---|---|
| 運営の声 | 信頼 / リリース / 学び (敬体) | 技術自慢 |
| ぬるるの声 | 日常 / 文化 / 柔らかさ | 宣伝役化 |
| 開発者向けの声 | Wiki / GitHub / NIP / 実装説明 | 一般ユーザー向けに混ぜない |

### 修正版カデンス (Agent1 案より頻度を抑制)

| 頻度 | 声 | 内容 |
|---|---|---|
| 月曜 | 運営 | release / GO-HOLD-STOP |
| 水曜 | 内部 | Design Crit 記録 |
| 金曜 | 運営 | 「今週わかったこと」(ユーザー失敗→含意) |
| **週3** (毎日ではなく) | ぬるる | おやつ / おやすみ / 図鑑のどれか |
| 月1 | 運営+ぬるる | とろけ便り / ThemaDAY digest |

→ Phase 0 は **週3から開始**、反応が自然なら毎日に広げる。ソロ運用の崩壊を防ぐ + 第三条「ぬるるは溶ける」整合。

### ぬるる施策とプロダクト面の接続 (Agent2 提案)

| ぬるる施策 | プロダクト内の接続 |
|---|---|
| 8表情絵文字 | リアクション文化 |
| おやつ15時 | Home 再訪 |
| 週末図鑑 | 二次創作投稿 |
| とろけ便り | 長文 / News タブ |
| ぬるるルーム | Talk 定着 |
| 8/8 ぬるるの日 | 招待 / 共有 / 壁紙配布 |

## 5. 90日ロードマップ (反応ループ起点)

| 期間 | やること | 成功条件 |
|---|---|---|
| 6/03-6/09 (W23) | 本日 Crit + 北極星 + manual cohort テンプレ確定 | Week-1 観察が始まる |
| 6/08 | **1.5.5 release** (Theme 0 verification) | GO 判定 |
| 6/10-6/16 (W24) | 初投稿反応ループ開始 + おやつ15時/おやすみ23時 (週3) | `#nostrはじめました` に毎日反応 |
| 6/17-6/23 (W25) | 8表情 NIP-30 配布 + Home renewal 設計 Crit + 危機対応 FAQ 起票 | プロダクト内にぬるるが入る |
| 6/24-6/30 (W26) | 週末ぬるる図鑑 第1回 + News α 内部 dogfood | Recommend 起動 |
| 6/29 | **1.6.0 release** (Home renewal) + 月例とろけ便り 第1号 | アクティビティ層が戻る理由 |
| 7月前半 | `/p` `/e` 共有 polish (LINE/X/iMessage/Discord) | OG が綺麗に見える |
| 7月後半 | NIP-5A WebView α / Mini Apps 安全境界 / ぬるる図鑑検討 | 配布の自由へ |
| 7/27 | **1.6.x release** (Mini Apps α) | — |
| 8/3-8/9 | **1.7.0 release** + ステッカー小ロット 第1回 | IP 物理化 |
| **8/8** | **ぬるるの日 第1回** (限定壁紙 / 図鑑特別号) | 売らずに祝う |
| 8/24-8/31 | **90日レビュー** (KPI + ガードレール + 北極星) | Phase 1 移行判定 |

## 6. 本日 Crit 議題 — 最終5本

Agent1 案 (A/B/C) に Agent2 提案 (D/E) を加えた最終構成。

### A: 北極星を「Week-1 復帰率」に固定

- **判定候補: GO (条件付き)**
- **条件**: 6月中に manual cohort 観察テンプレ (`docs/wiki/quality/qa-YYYY-MM-DD.md` 系) を確定。テンプレなしで GO すると指標が飾りになる。

### B: 三声モデル + 頻度を週3から開始

- **判定候補: GO (頻度抑制版)**
- Agent1 「ぬるる毎日」→ **Phase 0 は週3から**。反応が自然なら段階的に毎日へ拡張。
- 第三条「ぬるるは溶ける」と整合。ソロ運用の崩壊防止。

### D: 90日 ICP を 1+2 に固定 (NEW / Agent2 提案)

- **判定候補: GO**
- 90日は (1) 日本の Nostr 既存ユーザー + (2) プライバシー意識のある一般ユーザー に集中。
- (3) クリエイターは IP / おひねりが整う Phase 1 以降、(4) 開発者は受動。

### E: 初回 Home の safe starter graph (NEW / Agent2 提案)

- **判定候補: REVISE**
- 新規ユーザーが空の Home で離脱しないように、公式 / ぬるる / 日本語 starter accounts を裏側で用意。
- UX と安全性設計が必要 (誰がリスト管理するか、更新頻度、悪用防止)。
- ただしこれをやらないと Week-1 復帰は伸びにくい。最優先で ADR ドラフト。

### C: ぬるる本体 npub の NIP-46 bunker / 2-of-N (Agent2 補強で **格下げ**)

- **判定候補: REVISE (マーケティング施策の blocker にしない)**
- 方向性は良いが、技術検証が必要。鍵運用は事故ると信頼を失う。
- **修正案**: Phase 0 early はぬるる素材/絵文字/図鑑を先行 → Phase 0 mid で npub 運用設計 ADR → Phase 0 late で NIP-46 bunker 検証 → Phase 1 で本格運用。
- ぬるる施策全体の blocker にしない。

## 7. 危機対応マトリクス (NEW / Agent2 提案を採用)

§3 T の表を `docs/wiki/operations/crisis-response.md` (新規候補) として独立起票する。返答テンプレは copy-style.md 準拠 (やわらかい敬体、恐怖を煽らない、技術詳細はオプショナル)。

## 8. 量の上限 (再確認)

- 新規 NIP の採用 → しない (Phase 0 中)
- 新規大型機能 → しない (Talk/MLS/ライブ系は Phase 1 以降)
- 広告出稿・プレスリリース → しない
- ストア / Compass / wiki に「対応 NIP 数」を書かない

## Source references

- [[../culture/principles]], [[../culture/not-doing]], [[../culture/copy-style]], [[../culture/release-quality]], [[../culture/four-freedoms]]
- [[nuruh-ip-2026-05-28]], [[june-2026-roadmap]]
- [[themaday-2026-05-25]], [[themaday-2026-05-28-partnerships]], [[themaday-2026-05-31-week-review]]
- [[themaday-2026-06-01-management]], [[themaday-2026-06-02-product-eng-design]]
- [[../decisions/adr-0011-nuruh-ip-doctrine]], [[../decisions/adr-0012-monday-release-nuru-production-system]]
- [[../decisions/adr-0014-local-first-product-metrics]]
- [[../copy/store-listing]], [[../features/onboarding]], [[../operations/feedback-loop]]

## Related pages

- [[themaday-2026-05-25]], [[themaday-2026-05-31-week-review]], [[themaday-2026-06-01-management]]
- [[themaday-2026-06-02-product-eng-design]], [[nuruh-ip-2026-05-28]], [[june-2026-roadmap]]

## Open Questions

- manual cohort 観察の「5人/週」をどこで集めるか (知人 / Nostr Compass 経由 / yabu.me 周辺)
- safe starter graph の管理責任者 hat (Culture/IP Lead か、別 hat か)
- 危機対応 FAQ を README に出すか、wiki only にするか
- 三声モデルで「開発者向けの声」を Nostr 上でどこに置くか (公式 npub / 別 npub / wiki only)
