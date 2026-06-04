# ThemaDAY 2026-06-04 — 外部提携 & 開発者施策 (2人目コントリビュータ受領)

## Status

**Synthesized** (2026-06-04 14:20 JST)。Agent1 提案 + Agent2 批判的レビューを統合した working copy。Design Crit W23+1 (次回) に、Phase 0 を **Contributor Entrance MVP** へ縮小した議題として提出する。

## Summary

2026-06-04 02:25 JST に **ocknamo さんによる PR #201** がマージされ、ぬるぬるは **2人目の外部コントリビュータ**を迎えた。本ページは、この出来事を **trust surface のシグナル**として記録し、Charter v0.1 五箇条・[[themaday-2026-05-28-partnerships|partnerships v0.1]]・[[themaday-2026-06-03-marketing-growth|marketing v2 (三声モデル)]] と整合する形で、**今後90日の外部提携・開発者施策**を提案する。

結論を先に書く:

1. コントリビュータ数を **KPI にしない**。「文化適合 PR / レビュー後マージ率」を観察指標にする。
2. 外部提携は引き続き **非独占・ソース検証可能・文化保存・ユーザー利益・人間レビュー**の5要件を満たすものだけ。
3. 開発者施策は **「入口を整える」「道筋を見せる」「過剰に呼ばない」**の三段でやる。bounty / CLA / 翻訳募集はしない。
4. 三声モデル (運営 / ぬるる / 開発者向け) の **「開発者向けの声」** は、まず Contributor Entrance MVP と本人許諾後の Spotlight で小さく始める。Dev Hour は条件付きで後送りする。

## Current behavior

### コントリビュータ状況

- 1人目: プロジェクトオーナー (tami1A84) — Web / Android / iOS / Rust core / docs/wiki 全領域。
- **2人目: ocknamo さん (PR #201, 2026-06-04 01:25 JST マージ)**
  - 変更: `nosskey-sdk` `^0.0.4` → `^0.1.2` への追従。
  - 影響範囲: `components/SignUpModal.js` / `src/adapters/signing/NosskeySigner.ts` / `package.json` / `package-lock.json` の4ファイル。
  - 内容: 0.1.x の必須シグネチャ `exportNostrKey(keyInfo)` への正規化、フラット API (`nip04Encrypt` / `nip44Encrypt`) への修正、機能検出を実メソッド存在チェックへ。
  - 特徴: **依存ライブラリ追従 + サインアップフロー保護**という低リスク高価値領域。
  - Co-authored-by: Claude (LLM-assisted)。

### 既存の外部接点 (確認済み)

- **OpenSats Nostr Grant** (16th Wave) — README に明示。
- **and other stuff / Nostr Compass #24** — 公開前レビュー実績 ([[themaday-2026-05-28-partnerships]])。
- **NIP-50 search relay** (`wss://search.nos.today`) — feedback-loop MCP の基盤。
- **nosskey-sdk** (外部 npm パッケージ) — Passkey + Nostr key derivation。今回の PR 起点。
- **OSS 依存**: `nostr-tools` / `rx-nostr` / `nostr-sdk` (Rust) / `nostrdb` / 他多数。

### 既存の開発者向け資産 (確認済み)

| 資産 | 状態 | 評価 |
|---|---|---|
| `AGENTS.md` | 充実 (17929 bytes) | ◎ |
| `docs/wiki/culture/llm-onboarding.md` | 充実 | ◎ |
| `docs/wiki/architecture.md` | 存在 | ○ |
| `docs/wiki/nips/README.md` | 整備中 | ○ |
| `.github/pull_request_template_ui.md` | UI 用のみ | △ (一般 PR テンプレが無い) |
| `.github/workflows/wiki-lint.yml` | 動作中 | ◎ |
| `README.md` の "For Developers" | AGENTS.md への1リンクのみ | △ |
| `CONTRIBUTING.md` (root) | **無し** | × |
| `CODE_OF_CONDUCT.md` | **無し** | × |
| `.github/ISSUE_TEMPLATE/` | **無し** | × |
| good first issue ラベル運用 | 未確認 | ? |
| Contributor Spotlight 慣行 | **無し** | × |

## 1. 戦略仮説 (再定義)

> ぬるぬるのコントリビュータ成長は、人数を増やすことではなく、
> **「読みやすい入口」「歩ける道筋」「壊さない歓迎」の3点が揃った時、
> 文化に合った人が自分で見つけて来る** ことから始まる。
>
> その来訪は、bounty・翻訳募集・派手な campaign では作らず、
> (1) **ソース検証可能な Wiki**、(2) 小さい good first issue、
> (3) Contributor Spotlight、(4) 条件発火の Dev Hour、(5) 危機時の人間応答 — の5つで作る。

## 2. ICP (誰を呼ぶか / 90日固定)

[[themaday-2026-06-03-marketing-growth|marketing v2]] の ICP §1 を**そのまま継承**し、コントリビュータ層を **優先4** に位置付ける。

| 優先 | セグメント | 90日方針 | 来訪設計 |
|---:|---|---|---|
| 1 | 日本の Nostr 既存ユーザー | 主戦場 (ユーザー) | (該当外) |
| 2 | プライバシー意識のある一般ユーザー | 主戦場 (ユーザー) | (該当外) |
| 3 | 絵師 / 同人 / クリエイター | Phase 1 以降 | (該当外) |
| **4** | **開発者 / Nostr ecosystem** | **受動 + 入口整備** | **本ページ** |

### 開発者層の中の優先順位 (90日)

| 優先 | 開発者タイプ | 期待される第一歩 |
|---:|---|---|
| 1 | **日本の Nostr 開発者 (既存ユーザー兼)** | wiki PR / typo fix / 依存追従 |
| 2 | **LLM-assisted 開発者** | bounded scope の小修正 (今回の PR #201 型) |
| 3 | iOS / Android 専門開発者 | parity 修正 / a11y / 既存仕様準拠 |
| 4 | Nostr クライアント開発者 (海外含む) | interoperability bug report / NIP 互換 |
| 5 | Rust core / FFI 専門 | nurunuru-core 周辺 (要 ADR 想定) |

→ **90日中は 1〜3 に集中**。4〜5 は受動的に対応するのみ。

## 3. 外部提携 (Partnership)

### 3.1 引き継ぐ提携要件 (v0.1 確定)

[[themaday-2026-05-28-partnerships]] の5要件を**そのまま維持**:

1. **Non-exclusive** — 一つのリレー / ストア / メディア / ベンダーに依存させない。
2. **Source-verifiable** — プロトコル対応・セキュリティ・プラットフォーム挙動の主張はソース or wiki で検証可能。
3. **Culture-preserving** — 日本語トーン・やわらかさ・ぬるる住人ドクトリンを上書きさせない。
4. **User-benefiting** — オンボーディング / 信頼 / 相互運用性 / 配布の自由 / フィードバック品質を改善する。
5. **Human-reviewed** — マージ / リリース / 署名 / 秘密 / 文化判断は人間が確定。

### 3.2 提携カテゴリ (実態の棚卸し)

| カテゴリ | 既存 / 候補 | 90日方針 | 距離感 |
|---|---|---|---|
| **A. OSS 依存ライブラリ** | nosskey-sdk, nostr-tools, rx-nostr, nostr-sdk, nostrdb | 追従 PR を歓迎する明示的な姿勢を README に1行 | 既に提携 |
| **B. メディア / 評論** | Nostr Compass (and other stuff) | pre-publication review pattern を継続。第三者声 1〜2件まで | 受動 |
| **C. リレー運営** | yabu.me, relay-jp.nostr.wirednet.jp, r.kojira.io, search.nos.today | 障害情報の双方向観測 (こちらから push しない) | 観測 |
| **D. グラント / 助成** | OpenSats | 16th Wave 後の publishing リズム継続 (月次サマリ) | 既存 |
| **E. 他クライアント** | Damus / Amethyst / Coracle / Iris 等 | interoperability bug 受け入れのみ。協業前提にしない | 受動 |
| **F. 日本コミュニティ** | makimono / 日本 Nostr SIG 等 | 「今週よくなったこと」週1投稿の伝播のみ | 自然伝播 |
| **G. アカデミア / 公的機関** | 未着手 | Phase 2 以降 (経済・配布の自由が動いてから) | 後送り |
| **H. 企業スポンサー** | **やらない** (90日中) | 第五条・第三条・北極星と整合させづらい | 不採用 |

### 3.3 新規提携の判断テンプレ (Decision sheet)

新しい提携の打診が来たら、Design Crit で以下5行を埋めてから判断する:

```text
提携先:
提携形態: (配信/レビュー/コードホスト/相互参照/グラント/その他)
依存方向: (こちらが依存 / 相手が依存 / 相互 / 無依存)
5要件チェック: [Non-excl / Source-verif / Culture / User / Human]
Phase 影響: (Phase 0 / 1 / 2 / 3 / 4 のどれを早めるか遅めるか)
```

### 3.4 提携で **やらないこと** (本ページで新規追加)

- 公式 partner ロゴ・badge 制度の創設 (関係性を制度化すると独立性を失う)。
- 「公式統合」「公式連携」を表層で謳う (思想は基盤に隠す / 第三条)。
- 1社の SDK / リレー / ストアに鍵管理 or サインアップフローを依存させる。
- 翻訳プロジェクト / i18n パートナーを公募 (二条「日本語第一級」)。
- 「NIP の数」を共同マーケしない。

## 4. 開発者施策 (Developer Initiative)

### 4.1 入口を整える (Week 1〜2 実装)

`AGENTS.md` は **LLM 向け運用ルール**として完成度が高い。一方、**人間の初心者開発者向けの一枚目**が抜けている。

| 新規作成 | 目的 | サイズ目安 |
|---|---|---|
| `CONTRIBUTING.md` (root) | 「最初の PR までの道筋」を3画面で説明 | 200〜300行 |
| `CODE_OF_CONDUCT.md` (root) | Charter v0.1 五箇条と整合する歓迎・抑制ルール | 80〜120行 |
| `.github/ISSUE_TEMPLATE/bug_report.md` | バグ報告 (プラットフォーム必須) | 50行 |
| `.github/ISSUE_TEMPLATE/feature_request.md` | 機能提案 (五箇条・Open Questions を要求) | 60行 |
| `.github/ISSUE_TEMPLATE/nip_support.md` | NIP 追加提案 (日常体験への寄与必須) | 50行 |
| `.github/ISSUE_TEMPLATE/wiki_update.md` | Wiki 修正提案 | 30行 |
| `.github/pull_request_template.md` | UI 以外も含む一般 PR テンプレ (既存 UI 用は `pull_request_template_ui.md` のまま残す) | 60行 |

`CONTRIBUTING.md` は次の8節を含む:

1. ぬるぬるとは (1段落)
2. はじめての PR (5ステップ: clone → 試す → wiki を読む → 小さく書く → PR)
3. 五箇条と「やらないこと」へのリンク
4. プラットフォーム別ビルド (AGENTS.md 抜粋 + 該当 README)
5. 良い PR / 悪い PR ([[../culture/llm-onboarding]] からの抜粋)
6. **LLM コントリビュータについて** (Co-authored-by: 表記の作法、AGENTS.md 必読)
7. レビュー期待 (月曜リリース列車との関係、Design Crit を通る場合)
8. 連絡先 (npub + GitHub issue)

### 4.2 道筋を見せる — Contribution Ladder (Phase 0)

「貢献は数ではなく文化適合」という principle を**運用に落とす**仕組み。

| 段 | 名前 | 例 | レビュー強度 |
|---|---|---|---|
| **L0** | 観測 (Reader) | Wiki / Issue を読む | (なし) |
| **L1** | 修正 (Fixer) | typo / 翻訳ではない誤字 / link 切れ / wiki lint 修正 | 軽 |
| **L2** | 追従 (Follower) | 依存ライブラリ追従 (今回の PR #201 型) / NIP 文書化 | 中 (テスト要求) |
| **L3** | 修繕 (Mender) | parity 修正 / a11y / 既存仕様準拠の bug fix | 中 (Before/After 必須) |
| **L4** | 育成 (Cultivator) | 新規 UI / 新機能 / 新 NIP | **強** (Design Crit GO 必須) |
| **L5** | 共生 (Co-resident) | ADR 起票 / 文化憲章への影響 | **強** (Design Crit 2回連続合意 / 第五条準拠) |

→ `good first issue` は **L1 / L2 のみ**に付与。L3 以上には付けない。
→ 「数」ではなく「段ごとに何人いるか」で観察する。

### 4.3 過剰に呼ばない — 抑制設計

| 制度 | やる / やらない | 理由 |
|---|---|---|
| good first issue ラベル | **やる** (最初は手 curated 3本だけ) | 1人メンテナの review capacity を超えないため |
| help wanted ラベル | **やる** (最初は 0〜2本) | L2/L3 を急に増やさない |
| **bounty 制度** | **やらない** | 金銭インセンティブは文化適合を歪める |
| **Hacktoberfest 参加** | **やらない** | 善意の凡庸 PR を呼び込む典型 |
| **CLA 締結** | **やらない** | Unlicense と整合しない / 囲い込み |
| **コントリビュータランキング** | **やらない** | 数値競争にしない (Charter 短期KPI規約) |
| **翻訳公募** | **やらない** | 二条「日本語第一級」 |
| **Discord 開設** | **やらない (90日中)** | 既存窓口 (GitHub + Talk room) で足りる |

### 4.4 Contributor Entrance MVP (Phase 0)

Agent2 レビューを受け、Phase 0 は月例イベントを増やす前に **入口の最小セット**へ縮小する。1人メンテナ体制では、施策の数より review burden を制御することが第一。

| 優先 | 種別 | Phase 0 の扱い | GO 条件 |
|---:|---|---|---|
| 1 | `CONTRIBUTING.md` v0.1 | **実施** | 最初の PR までの手順、五箇条、LLM-assisted 表記、検証コマンドを1枚にまとめる |
| 2 | 一般 PR テンプレ + Issue template 最小2種 | **実施** | PR template / bug_report / wiki_update から開始。feature_request と nip_support は後続 |
| 3 | curated `good first issue` | **実施** | L1/L2 を手で3本だけ選ぶ。常時維持を義務にしない |
| 4 | Contributor Spotlight | **条件付き実施** | 本人許諾後、マージ済み PR を1段落だけ紹介。月1上限 |
| 5 | Dev Hour | **PARK** | 外部 active contributor が2名以上、または同種質問が3件以上出た時点で再検討 |
| 6 | Wiki Walk | **PARK** | CONTRIBUTING.md への反応を見てから判断 |

### 4.4b 月例リズム (Phase 0 の上限)

| 頻度 | 種別 | 内容 |
|---|---|---|
| **月1まで** | Contributor Spotlight | その月にマージされた外部 PR をブログ / npub で1段落紹介 (本人許諾後)。該当 PR が無い月は実施しない |
| **条件発火** | Dev Hour | active contributor 2名以上、または同種質問3件以上で初回のみ試す。定例化はしない |
| 週1 (金曜) | 「今週わかったこと」 | 既存。Contributor 由来の発見は Spotlight 側に集約し、金曜投稿を開発者向けに寄せない |

### 4.5 LLM コントリビュータ施策 (PR #201 を踏まえた強化)

今回の PR #201 が `Co-authored-by: Claude` を含んでいたことは、**ぬるぬるが既に LLM-assisted contribution の現場である**ことを示す。これに対する明示的方針を立てる。

| 項目 | 方針 |
|---|---|
| Co-authored-by: 表記 | **推奨から開始**。LLM-assisted であることを隠さない文化を作る。ただし強制文言は CONTRIBUTING.md 起票時に再検討 |
| LLM 単独 PR | **不可**。人間の責任者を必ず置く。人間が検証コマンドと影響範囲を PR 本文に書く |
| AGENTS.md / llm-onboarding.md | LLM が読むべき**最初の2文書**として CONTRIBUTING.md から強調リンク |
| LLM 由来 PR レビュー強度 | **同じ**。LLM-assisted だからといって甘くも厳しくもしない |
| 「LLM bot」ラベル | **作らない** (差別的運用になる / 第二条整合) |
| LLM 用 issue 自動 trial | **やらない** (人間の Design Crit を素通りさせない) |

### 4.6 危機時応答 (trust surface としての開発者対応)

[[../operations/crisis-response]] にユーザー向け危機対応は既にある。**開発者向け**は、通常 Issue と private vulnerability intake を分けて扱う。秘密鍵・署名・鍵導出・暗号化・passkey に関わる報告を公開 Issue に誘導しない。

| シナリオ | 返答方針 |
|---|---|
| 「秘密鍵の扱いがおかしい」CVE / 脆弱性報告 | **公開 Issue に書かせない**。GitHub Security Advisory / private channel を README と CONTRIBUTING.md に明示。初動目標は 24h 以内だが、強い SLA ではなく best-effort と書く |
| 鍵導出・署名・passkey・暗号化に関わる dependency update | 通常の依存更新と分ける。差分・上流 release note・検証コマンド・秘密鍵非露出確認を PR template で要求 |
| 「他クライアントと相互運用しない」報告 | 該当 NIP wiki ページに Open Question として記録 → Design Crit |
| 「コピーライセンスが分かりづらい」 | Unlicense + 個別ファイルヘッダ無しの方針を再説明 |
| 「ぬるるの画像を二次創作で使っていいか」 | [[nuruh-ip-2026-05-28|ぬるる IP §4 ライセンス階段]] に誘導 |
| LLM 由来の大量 PR スパム | Design Crit を理由に close。文化を理由にしてよい (第三条「複雑さは裏側に」/ 「やらないこと §設計判断」) |


### 4.7 Dependency update verification path (PR #201 型)

PR #201 は低リスク高価値だったが、`nosskey-sdk` は鍵導出・署名・passkey に近い依存である。今後の依存更新 PR は、通常の `package-lock.json` 更新より少し強い検証を要求する。

| 種別 | 要求する確認 |
|---|---|
| UI / copy / docs だけ | screenshot / wiki lint / 該当プラットフォーム確認 |
| 一般 dependency update | upstream release note、build/test、影響ファイル一覧 |
| **鍵・署名・passkey・暗号化 dependency update** | upstream release note、移行差分、`npm run test` / relevant build、秘密鍵が `window.*`・logs・UserDefaults に出ない確認、既存ログイン/新規登録/再起動復帰の手動確認 |
| Rust FFI / Nostr protocol dependency update | cargo/npm test、FFI bindings 影響、NIP wiki 更新要否、interop Open Questions |

PR template には「検証したこと」と「検証していないこと」を分けて書かせる。未検証を正直に書く PR は歓迎し、未検証を隠す PR は REVISE にする。

## 5. 三声モデルへの統合

[[themaday-2026-06-03-marketing-growth|marketing v2 §4]] の三声モデルに、本ページが対応する位置を確定する。

| 声 | 役割 | 本ページの担当領域 |
|---|---|---|
| 運営の声 | 信頼 / リリース / 学び | Contributor Spotlight (月1 / 第1金曜) |
| ぬるるの声 | 日常 / 文化 / 柔らかさ | 開発者貢献に**ぬるるは介入しない** (第三条「ぬるるは溶ける」) |
| **開発者向けの声** | Wiki / GitHub / NIP / 実装 | **CONTRIBUTING.md、AGENTS.md、本 wiki 全体、条件発火の Dev Hour** |

→ 「開発者向けの声」は**一般ユーザーの目に触れる場所に混ぜない**。
→ 一方で**完全に分離もしない**: Contributor Spotlight だけは「運営の声」で**月1**だけ橋渡しする。

## 6. 90日 ロードマップ (Phase 0 / reduced)

Agent2 レビューにより、Phase 0 は **Contributor Entrance MVP** に縮小する。月例イベントを増やすより、まず「安全に1本目の PR を出せる導線」を作る。

| Week | 日付目安 | アクション | 担当 |
|---|---|---|---|
| **W23+1** | 06-08 月 | 本ページを Design Crit にかける (縮小版5議題) | tami1A84 + Crit |
| W24 | 06-11 水 | `CONTRIBUTING.md` v0.1 起票 (LLM-assisted / security intake / verification path を含む) | tami1A84 |
| W24 | 06-13 金 | 一般 `pull_request_template.md` + `bug_report.md` + `wiki_update.md` のみ起票 | tami1A84 |
| W25 | 06-15 月 | L1/L2 の curated `good first issue` を **3本だけ**選ぶ | tami1A84 |
| W25 | 06-19 金 | PR #201 ocknamo さん Spotlight を**本人許諾後に**1段落だけ実施。許諾なしなら skip | tami1A84 (運営の声) |
| W26〜W30 | 6〜7月 | 外部 PR / Issue の review burden を観察。Dev Hour はまだ定例化しない | Crit |
| W31〜W35 | 8月 | active contributor 2名以上、または同種質問3件以上なら Dev Hour 初回を検討 | Crit |
| **W36** | 08-31 月 | **90日レビュー** (容量・品質・文化適合を点検) | Crit |

## 7. 観察指標 (KPI ではなく cohort 観察)

[[../decisions/adr-0014-local-first-product-metrics|ADR-0014]] に従い、product telemetry は入れない。**手動観察 + GitHub native の指標のみ**で運用する。

### 7.1 観察するもの (positive / capacity-first)

Agent2 レビューを反映し、**人数・PR本数・Wiki PR数の目標値を置かない**。これらは容易に growth KPI 化し、Charter の短期 KPI 規約と衝突するため。

| 指標 | 入力元 | 90日で見ること | 数値より大事なこと |
|---|---|---|---|
| Contributor Entrance MVP 完了 | GitHub | `CONTRIBUTING.md` / 一般 PR template / bug_report / wiki_update が揃ったか | 1枚目の入口が迷子を減らすか |
| curated issue の質 | GitHub | L1/L2 issue 3本が明確な検証手順を持つか | 常時維持ではなく、出すなら安全な粒度か |
| review burden | manual | 外部 PR / Issue が月曜リリース列車を圧迫していないか | 圧迫するなら施策を止める |
| 文化適合の判断記録 | Design Crit | REVISE / PARK を理由付きで出せているか | 「善意の凡庸」を丁寧に断れるか |
| LLM-assisted 透明性 | GitHub | Co-authored 表記または PR 本文で LLM 使用が説明されているか | 隠匿より説明を促す文化 |
| dependency update verification | GitHub | 鍵・署名・passkey 影響 PR に release note / 検証コマンド / secret 非露出確認があるか | PR #201 型の安全な再現 |
| private vulnerability intake | manual | 公開 Issue に秘密鍵・脆弱性詳細を書かせない導線があるか | 24h SLA より漏洩防止 |
| Spotlight 実施可否 | manual | 本人許諾後に1段落紹介できたか。無理なら skip できたか | 継続義務にしない |
| Dev Hour 発火条件 | manual | active contributor 2名以上 or 同種質問3件以上になったか | 条件未達なら開かない |

### 7.2 観察してはいけないもの (negative guardrail)

| 指標 | 理由 |
|---|---|
| GitHub stars / forks / watch | Charter「短期 KPI で文化判断を覆さない」 |
| Twitter/X impression | やらないことリスト §体験 |
| Contributor ランキング | 数値競争にしない |
| 「他 Nostr クライアントとの contributor 数比較」 | やらないことリスト §設計判断 |
| 「LLM PR の本数」を成果として扱う | LLM-onboarding §「LLM への文化的注意」 |

## 8. 既存戦略・ADR との整合チェック

| 文書 | 整合性 | 備考 |
|---|---|---|
| [[../culture/principles|Charter v0.1]] 五箇条 | ✓ | 第四条 (一貫性) と第五条 (鍵への厳格さ) を侵さない |
| [[../culture/not-doing]] | ✓ | bounty / CLA / NIP数競争 / 一斉動員を排除 |
| [[../culture/llm-onboarding]] | ✓ | むしろ強化 (Co-authored 表記の正規化) |
| [[themaday-2026-05-28-partnerships]] | ✓ | 5要件をそのまま継承 |
| [[themaday-2026-06-03-marketing-growth|marketing v2]] | ✓ | ICP §1 と三声モデル §4 に接続 |
| [[../decisions/adr-0007-design-crit-ritual|ADR-0007]] | ✓ | 本ページ自体を Crit に提出 |
| [[../decisions/adr-0012-monday-release-nuru-production-system|ADR-0012]] | ✓ | Dev Hour を条件発火に後送りし、月曜リリース列車と review capacity を優先 |
| [[../decisions/adr-0014-local-first-product-metrics|ADR-0014]] | ✓ | 観察指標は manual + GitHub native のみ |
| [[nuruh-ip-2026-05-28|ぬるる IP v1.0]] | ✓ | 第三条「ぬるるは溶ける」: 開発者領域にはぬるるを出さない |

## 9. Design Crit 即決議題 (5本)

W23+1 (2026-06-08 月) の Design Crit では、Agent2 レビューを反映した **縮小版5議題** を出す:

| # | 議題 | 提案ラベル | 理由 |
|---|---|---|---|
| **A** | `CONTRIBUTING.md` (root) v0.1 起票 | **GO** | 不在は明確な負債。security intake と verification path を含める |
| **B** | 一般 PR template + `bug_report.md` + `wiki_update.md` | **GO** | 4種同時ではなく最小2種から開始 |
| **C** | curated `good first issue` 3本だけ | **GO** | 常時 3〜5本維持を義務にしない |
| **D** | Contribution Ladder (L0〜L5) を観察軸として採用 | **GO** | 数ではなく段と review burden で見る |
| **E** | bounty / CLA / Hacktoberfest 不採用を明文化 | **GO** | 第三者誘惑への事前防御 |

**REVISE 候補** (即決しない):

| # | 議題 | ラベル | 理由 |
|---|---|---|---|
| F | Dev Hour 月1開設 | **PARK** | active contributor 2名以上 or 同種質問3件以上まで待つ |
| G | LLM 単独 PR 不可ポリシー明文化 | **REVISE** | 「人間の責任者必須」は維持しつつ、排除に見えない文言を検討 |
| I | `CODE_OF_CONDUCT.md` v0.1 | **REVISE** | 重要だが W24 に同時実装すると重い。CONTRIBUTING.md 後に独自文案を作る |
| H | Discord 開設 | **HOLD (90日中は無)** | 既存窓口で足りる |

## 10. やらないこと (本ページ新規)

- **bounty / 金銭インセンティブ**で人を呼ばない。
- **CLA (Contributor License Agreement)** を結ばない (Unlicense と整合しない)。
- **Hacktoberfest** 等の外部 campaign で contributor 数を一時的に膨らませない。
- **公式 partner badge / sponsor ロゴ列**を README に置かない。
- **LLM bot 専用ラベル**を作って差別運用しない。
- **翻訳プロジェクト**を公募しない (二条)。
- **コントリビュータランキング / leaderboard**を作らない。
- **「他クライアントの開発者を引き抜く」言説**を取らない (Compass の独立性を尊ぶ姿勢と矛盾)。
- **Discord / Slack を90日中に開設しない** (GitHub + Talk room で足りる)。
- **企業スポンサー受け入れを 90日中はしない** (Phase 1 以降の議論)。

## 11. Open Questions

- `CODE_OF_CONDUCT.md` を Contributor Covenant 派生にするか、ぬるぬる独自に書くか (提案: 独自)。
- LLM 単独 PR の扱い: 「人間が責任者として配置されれば LLM ドラフト可」を明文化するか (Co-author 表記の運用と接続)。
- Contributor Spotlight の **公開チャネル** (Wiki / Talk 公式 npub 投稿 / GitHub Discussions / 全て)。
- Dev Hour の **配信形式** (Talk グループ / nostr live / Jitsi / 録画あり/なし)。
- **good first issue は誰が起票するか** (現状 1人プロジェクト → bot 候補 ?)。
- 「**外部 PR レビュー SLA**」を明示するか (例: 7日以内に1次応答)。緩い目標は良いが、強い SLA は1人運用と衝突する。
- 1.6.0 リリースに **README の "For Developers" セクション拡張**を含めるか (Crit B 採用なら自然に含まれる)。
- Nuruh IP v1.0 と本ページの **「開発者は L4 まで自由 / L5 は文化的合議」** の境界が運用で曖昧になる懸念 → Phase 0 末で見直し。

## 12. 失敗モード

| 失敗モード | 兆候 | 防御 |
|---|---|---|
| 数を追う | 「contributors が 10 名超えました!」を運営の声で発する | KPI から外す + Spotlight は月1のみ |
| 善意の凡庸 | 「リファクタリング」「コードを綺麗にした」だけの PR が増える | llm-onboarding §「悪い PR」を CONTRIBUTING に転載 |
| LLM スパム | 大量 typo PR / 大量翻訳 PR | Design Crit を理由に close (文化を理由にしてよい) |
| 文化希釈 | ぬるるが宣伝役になる / 開発者向け説明がユーザー画面に漏れる | 三声モデル §5 の分離を厳守 |
| 1人運用崩壊 | template / issue / Spotlight / Dev Hour が月曜リリース列車を圧迫する | **Dev Hour は開かない。Spotlight は skip 可。good first issue は3本以上増やさない** |
| 提携過剰 | partner ロゴ列 / 「公式統合」表現が README に出現 | やらないこと §10 を防壁 |

## Source references

- `AGENTS.md`
- `README.md`
- `.github/pull_request_template_ui.md`
- `.github/workflows/wiki-lint.yml`
- PR #201 マージコミット: `7d4b33f1ec024f8a0bb72762a9c0231f6b7d0a6d`
- ocknamo さん PR: <https://github.com/tami1A84/null--nostr/commit/7d4b33f1ec024f8a0bb72762a9c0231f6b7d0a6d>
- `docs/wiki/culture/principles.md`
- `docs/wiki/culture/not-doing.md`
- `docs/wiki/culture/llm-onboarding.md`
- `docs/wiki/strategy/themaday-2026-05-28-partnerships.md`
- `docs/wiki/strategy/themaday-2026-06-03-marketing-growth.md`
- `docs/wiki/strategy/nuruh-ip-2026-05-28.md`
- `docs/wiki/operations/feedback-loop.md`
- `docs/wiki/operations/crisis-response.md`
- `docs/wiki/decisions/adr-0007-design-crit-ritual.md`
- `docs/wiki/decisions/adr-0011-nuruh-ip-doctrine.md`
- `docs/wiki/decisions/adr-0012-monday-release-nuru-production-system.md`
- `docs/wiki/decisions/adr-0014-local-first-product-metrics.md`
- `docs/wiki/nips/README.md`

## Related pages

- [[themaday-2026-05-28-partnerships]] (前回 partnerships v0.1)
- [[themaday-2026-06-03-marketing-growth]] (三声モデル + ICP)
- [[nuruh-ip-2026-05-28]] (ぬるる IP)
- [[../culture/principles]]
- [[../culture/not-doing]]
- [[../culture/llm-onboarding]]
- [[../culture/copy-style]]
- [[../culture/design-crit]]
- [[../operations/feedback-loop]]
- [[../operations/crisis-response]]
- [[../decisions/adr-0011-nuruh-ip-doctrine]]
- [[../decisions/adr-0014-local-first-product-metrics]]
