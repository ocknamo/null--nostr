# MIP-03 実装PRテンプレート

## 概要
- 対応Issue/背景:
- 目的:
- スコープ（今回PRで対応する範囲）:
- 非スコープ（今回PRで対応しない範囲）:

---

## MIP-03 MUST対応サマリ

> `docs/MIP03_IMPLEMENTATION_STATUS.md` を更新済みであること

- [ ] kind:445 構造/ルーティング（hタグ, 並び順）
- [ ] 暗号失敗モード（invalid base64 / <28 bytes）
- [ ] Application message要件（kind:9, leak防止）
- [ ] disappearing message の expiration制御
- [ ] Commit/Proposal権限制御
- [ ] Relay ACK順序

### 判定
- [ ] 本PR単体で「完全実装」
- [ ] 本PRは「高水準実装」まで（上流依存あり）

理由:

---

## 変更内容（ファイル別）
- `ios/...`:
  -
- `rust-engine/nurunuru-core/...`:
  -
- `docs/MIP03_IMPLEMENTATION_STATUS.md`:
  -

---

## 仕様適合チェック（MUSTごと）

### 1) Group Event (kind:445)
- 要件:
- 実装:
- 根拠コード:
- テスト/確認:

### 2) 失敗モード
- 要件:
- 実装:
- 根拠コード:
- テスト/確認:

### 3) Application messages
- 要件:
- 実装:
- 根拠コード:
- テスト/確認:

### 4) Disappearing messages
- 要件:
- 実装:
- 根拠コード:
- テスト/確認:

### 5) Commit/Proposal権限制御
- 要件:
- 実装:
- 根拠コード:
- テスト/確認:
- 未達（あれば）:

### 6) Relay ACK順序
- 要件:
- 実装:
- 根拠コード:
- テスト/確認:

---

## テスト

### 実施コマンド
- [ ] `cd rust-engine && cargo check -p nurunuru-core`
- [ ] `cd rust-engine && cargo check -p nurunuru-ffi`
- [ ] iOSビルド/起動確認（必要に応じて）

### 確認結果
- 結果:
- ログ/スクリーンショット:

---

## リスクと互換性
- 既存ユーザー影響:
- 後方互換性:
- マイグレーション要否:
- ロールバック方針:

---

## 未解決事項 / 上流依存（MDK等）
- [ ] SelfRemove-only Commit 厳格検証
- [ ] admin depletion 防止
- [ ] admin SelfRemove制限
- [ ] commit分類/拒否理由 API 露出

対応計画:

---

## レビュー観点（mandatory）
- [ ] MIP-03 MUSTと実装の1:1対応が示されている
- [ ] 未達要件が明示され、責務分離（アプリ層/MDK層）が説明されている
- [ ] テスト証跡がある
- [ ] リスク評価が妥当
