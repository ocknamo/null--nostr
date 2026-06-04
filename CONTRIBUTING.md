# Contributing to ぬるぬる

ぬるぬる (null--nostr) への貢献ありがとうございます。
このプロジェクトは「10年後の主権的コミュニケーションを、日本語の日常として先に実装する」ことを目指しています。

最初の PR は、小さく、検証しやすく、既存の文化を壊さない範囲から始めてください。

## 最初に読むもの

1. [README.md](./README.md) — ユーザー向け概要
2. [AGENTS.md](./AGENTS.md) — ビルド手順、プラットフォーム制約、AI agent 向け運用ルール
3. [docs/wiki/culture/principles.md](./docs/wiki/culture/principles.md) — 五箇条
4. [docs/wiki/culture/not-doing.md](./docs/wiki/culture/not-doing.md) — やらないことリスト
5. [docs/wiki/culture/llm-onboarding.md](./docs/wiki/culture/llm-onboarding.md) — LLM-assisted contribution の注意

コードや仕様で Wiki と source が衝突する場合は、source code / `design-tokens/constants.json` / platform guardrails が優先です。

## はじめての PR の流れ

1. Issue または小さい修正対象を1つ選ぶ。
2. 影響範囲を1 platform / 1 feature / 1 docs topic に絞る。
3. 変更前に関連 wiki と該当 source file を読む。
4. 小さく変更し、検証したこと・検証していないことを PR に書く。
5. 必要なら `docs/wiki/` と `docs/wiki/log.md` も更新する。

最初の PR に向いているもの:

- typo / broken link / wiki lint 修正
- source references の追加
- 小さな dependency update
- 既存仕様に沿った軽微な bug fix
- docs/wiki の Open Questions 整理

最初の PR に向かないもの:

- 新規 UI 画面
- 新しい NIP 対応
- 鍵・署名・暗号化・passkey の大きな設計変更
- 複数 platform をまたぐ大変更
- 「リファクタリング」だけで動機が薄い変更

## Contribution Ladder

| 段 | 名前 | 例 | レビュー強度 |
|---|---|---|---|
| L0 | 観測 (Reader) | Wiki / Issue を読む | なし |
| L1 | 修正 (Fixer) | typo / link / wiki lint | 軽 |
| L2 | 追従 (Follower) | dependency update / NIP 文書化 | 中 |
| L3 | 修繕 (Mender) | parity 修正 / a11y / 既存 bug fix | 中 |
| L4 | 育成 (Cultivator) | 新規 UI / 新機能 / 新 NIP | 強: Design Crit |
| L5 | 共生 (Co-resident) | ADR / 文化憲章への影響 | 強: Design Crit + 合議 |

`good first issue` は L1 / L2 だけに付けます。L3 以上の変更は、最初の PR ではなく、背景共有後に進めてください。

## 五箇条チェック

PR 本文には、この変更が支える五箇条を1つ以上書いてください。

- 一、日常を壊さない。
- 二、日本語を第一級市民にする。
- 三、複雑さは裏側に隠す。
- 四、一貫性は新機能より重い。
- 五、かわいさと、秘密鍵への厳格さを、同時に持つ。

例: 第四条「一貫性は新機能より重い」: Android と iOS の表示差分を既存仕様に合わせた。

## Build / test commands

詳細は [AGENTS.md](./AGENTS.md) を参照してください。よく使う最小コマンド:

```bash
npm install
npm run test
npm run build
npm run wiki:lint
npm run tokens:check
```

Android / iOS / Rust FFI を触る場合は、AGENTS.md の platform-specific commands と guardrails を必ず確認してください。

## Wiki 更新ルール

アーキテクチャ、機能、NIP、セキュリティ制約、Design tokens、platform parity に意味のある変更を入れる場合:

1. `docs/wiki/index.md` で関連ページを探す。
2. 関連 wiki page を更新する。
3. ページ追加・改名・大幅変更なら `docs/wiki/index.md` を更新する。
4. `docs/wiki/log.md` に `## [YYYY-MM-DD] type | title` 形式で追記する。
5. 不確実なことは `Open Questions` に分離する。

## Security / private vulnerability reports

秘密鍵、署名、鍵導出、暗号化、passkey、Keychain / secure storage に関わる脆弱性の詳細を **公開 Issue に書かないでください**。

まず [SECURITY.md](./SECURITY.md) を読んでください。
公開 Issue には、再現手順・秘密鍵・個人情報・exploit details を載せず、必要なら「private security contact が必要」とだけ書いてください。

## Dependency update verification

依存更新 PR は、通常の lockfile 更新よりも「何を検証したか」を重視します。

| 種別 | PR に書くこと |
|---|---|
| UI / docs only | screenshot / wiki lint / 該当確認 |
| 一般 dependency update | upstream release note、build/test、影響ファイル |
| 鍵・署名・passkey・暗号化 dependency update | upstream release note、移行差分、test/build、秘密鍵が `window.*` / logs / UserDefaults に出ない確認、既存ログイン/新規登録/再起動復帰の確認 |
| Rust FFI / Nostr protocol dependency update | cargo/npm test、FFI bindings 影響、NIP wiki 更新要否 |

検証していないことは、隠さず `Not verified` に書いてください。未検証を正直に書く PR は歓迎します。

## LLM-assisted contribution

LLM を使った PR は歓迎します。ただし、人間の責任者が必要です。

- LLM が生成した変更でも、PR を出す人が内容を理解し、検証してください。
- 可能なら `Co-authored-by:` または PR 本文で LLM 使用を明記してください。
- LLM に任せきりの大量 typo PR / 翻訳 PR / 無目的リファクタリングは close することがあります。
- LLM は [AGENTS.md](./AGENTS.md) と [docs/wiki/culture/llm-onboarding.md](./docs/wiki/culture/llm-onboarding.md) を読んだ前提で使ってください。

## Review expectations

- 小さい PR ほど review しやすいです。
- UI / 新機能 / 新 NIP / culture に影響する変更は Weekly Nuru Design Crit が必要になることがあります。
- 月曜リリース列車を優先します。レビューは best-effort であり、強い SLA はありません。
- 「動くから」だけではマージしません。なぜぬるぬるに合うのかを書いてください。

## License

このプロジェクトは [Unlicense](./LICENSE) です。PR を送ることで、あなたの貢献も同じライセンスで提供されることに同意したものとして扱います。
