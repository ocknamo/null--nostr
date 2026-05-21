## UI 変更 PR チェックリスト

> このテンプレートは UI 変更を含む PR で使用してください。コード変更のみで UI に影響しない PR では使わなくて構いません。

### 内容

<!-- 変更の概要を1〜3行で -->

### 該当する五箇条

<!-- docs/wiki/culture/principles.md の五箇条のうち、この変更が支える / 関連する条文を1つ以上、1行で書く -->
<!-- 例: 第三条「複雑さは裏側に隠す」: 投稿エラー時の relay 名表示を畳んだ -->

### チェックリスト

- [ ] Before / After スクリーンショットを貼った
- [ ] 影響プラットフォームを明記した (Web / Android / iOS のどれか)
- [ ] design-tokens 外の色・余白・フォントサイズを追加していない
- [ ] 日本語コピーをレビューした (直訳ではないか、既存採用語を変えていないか) — [docs/wiki/culture/copy-style.md](../docs/wiki/culture/copy-style.md)
- [ ] 空状態 (Empty state) を確認した
- [ ] エラー状態を確認した
- [ ] ダーク / ライト両モードで破綻しない
- [ ] [やらないことリスト](../docs/wiki/culture/not-doing.md) に抵触しない
- [ ] 必要なら ADR を `docs/wiki/decisions/` に追加した
- [ ] 該当する `docs/wiki/ui/*.md` を更新した
- [ ] 新規 UI 画面の場合、Weekly Nuru Design Crit で GO ラベルを受けた

### 関連 Issue / ADR

<!-- 関連する Issue 番号、ADR 番号があれば -->
