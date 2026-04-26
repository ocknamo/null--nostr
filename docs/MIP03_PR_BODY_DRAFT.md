# MIP-03 実装PR（最終ドラフト / ブランチ反映版）

## 概要
- 対応Issue/背景: MIP-03 Group Messages の準拠強化（iOS + Rust）
- 目的: kind:445 の安全性・互換性・運用安定性を向上し、MIP-03 MUST対応を明確化する
- スコープ:
  - Rust MLS受信前ガードの追加（kind/h/base64/len）
  - iOS Talk受信・publish経路の防御強化（expiration/h/payload/drop-policy）
  - TalkViewModel のMDK/FFIエラー正規化
  - 仕様追跡ドキュメント作成
- 非スコープ:
  - SelfRemove/admin/commit構造の厳格検証（MDK内部責務）

---

## MIP-03 MUST対応サマリ

> `docs/MIP03_IMPLEMENTATION_STATUS.md` を更新済み

- [x] kind:445 構造/ルーティング（hタグ, 並び順）
- [x] 暗号失敗モード（invalid base64 / <28 bytes）
- [x] Application message要件（kind:9）
- [x] disappearing message の expiration制御
- [~] Commit/Proposal権限制御（MDK内部責務に依存）
- [x] Relay ACK順序（publish時のOK ACK待ち）

### 判定
- [ ] 本PR単体で「完全実装」
- [x] 本PRは「高水準実装」まで（上流依存あり）

理由:
- SelfRemove-only Commit厳格検証 / admin depletion防止 / admin SelfRemove制限はMDK側責務。
- 本PRではアプリ層・連携層で実装可能な防御と整合性を最大化。

---

## 変更内容（ファイル別）
- `rust-engine/nurunuru-core/src/mls.rs`
  - kind:445受信前ガード（invalid_kind / h整合 / base64 / length<28）
  - inner event kind を 9（chat）で生成
- `rust-engine/Cargo.toml`
  - `base64` を workspace dependency に追加
- `rust-engine/nurunuru-core/Cargo.toml`
  - `base64 = { workspace = true }` を追加
- `ios/NuruNuru/Data/NostrRepository+Talk.swift`
  - kind:445 publish前の最小構造検証（hタグ）
  - disappearing有効時expiration上書き / 無効時expiration削除
  - invalid payload（base64不正・長さ不足）を受信時drop
  - non-retryable Unprocessable（missing_h_tag/group_id_mismatch/invalid_kind）を即drop
  - 受信順序 tie-break（created_at → id）
- `ios/NuruNuru/ViewModels/TalkViewModel.swift`
  - MDK/FFIエラー正規化マップ追加
  - load/open/send/add/remove/create catch 経路で統一利用
- `docs/MIP03_IMPLEMENTATION_STATUS.md`
- `docs/MIP03_PR_BODY_TEMPLATE.md`
- `docs/MIP03_PR_BODY_DRAFT.md`（本ファイル）

---

## 根拠コード（行番号）
- Rust `mls.rs`
  - `Kind::from(9u16)`
  - `invalid_base64_content`, `malformed_content_too_short`
  - `missing_h_tag`, `group_id_mismatch`, `invalid_kind`
- iOS `NostrRepository+Talk.swift`
  - `Validate minimum outer shape for kind:445`
  - `remove any caller-provided expiration tag`
  - `invalidMlsOuterPayloadReason`
  - `drop non-retryable state-update`
- iOS `TalkViewModel.swift`
  - `normalizeMlsError`
  - `setNormalizedError`
  - `context: "loadGroups" / "openGroup" / "sendMessage"`

---

## テスト

### 実施コマンド
- [x] `cd rust-engine && cargo check -p nurunuru-core`
- [x] `cd rust-engine && cargo check -p nurunuru-ffi`
- [ ] iOSビルド/起動確認（別環境/別PRで実施）

### 結果
- Rust check 通過（warningのみ、errorなし）

---

## リスクと互換性
- 既存ユーザー影響: 低〜中（不正イベントdropが増え、挙動はより厳密化）
- 後方互換性: 正常系は維持
- マイグレーション: なし
- ロールバック: 対象ファイルのrevertで可能

---

## 未解決事項 / 上流依存（MDK等）
- [ ] SelfRemove-only Commit 厳格検証
- [ ] admin depletion 防止
- [ ] admin SelfRemove制限
- [ ] commit分類/拒否理由 API 露出

対応計画:
1. MDK側のMUST保証照合
2. 不足時は上流PR
3. API露出後、iOSで文言/ログをさらに厳密化
