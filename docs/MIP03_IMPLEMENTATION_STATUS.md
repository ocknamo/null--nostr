# MIP-03 実装状況チェックリスト（iOS + Rust）

最終更新: 2026-04-23

## 判定サマリ
- **iOSアプリ層 + Rust連携層**: 高い水準で実装済み
- **MIP-03「完全実装」宣言**: **未達**（MDK内部責務の厳格検証が前提）

---

## MUST要件チェック

### 1) Group Event (kind:445) 構造・ルーティング
- [x] kind:445 送受信フロー実装
- [x] hタグ必須/一致チェック（Rustで判定、iOSで不正drop）
- [x] 受信順序 tie-break（created_at → id）

### 2) Edge cases（復号失敗系）
- [x] invalid base64 を reject/drop
- [x] decoded length < 28 を reject/drop
- [~] AEAD認証失敗時の厳格dropはMDK実処理に依存

### 3) Application messages
- [x] chatメッセージ kind:9 で生成
- [~] MLS sender と inner pubkey の厳格照合はMDK依存
- [~] inner event無署名/グループ識別子禁止の厳格保証はMDK依存

### 4) disappearing message / expiration
- [x] disappearing有効時: expiration自動計算で上書き
- [x] disappearing無効時: caller供給expiration削除

### 5) Commit/Proposal 権限制御（MIP-03核心）
- [~] 非admin Commit拒否（self-update / SelfRemove-only例外含む）
- [~] self-update Commit の厳格構造検証
- [~] SelfRemove-only Commit の厳格構造検証
- [~] admin SelfRemove制限
- [~] active admin 0 回避（admin depletion防止）

> 上記は実質的に **MDK内部責務**。現行アプリ層APIだけでは完全再実装困難。

### 6) Relay ACK順序
- [x] publish時のOK ACK待機あり
- [x] commit publish → merge順序を維持

---

## 結論
- 実運用上はMIP-03に対して高い準拠状態。
- ただし仕様書の「完全実装」を厳密に宣言するには、
  **MDK側でのCommit種別/権限系MUSTの保証確認**が必要。

## 推奨アクション
1. MDKのMUST実装保証をチェックリスト照合
2. 必要ならMDKに「拒否理由/Commit分類」の公開API追加
3. iOS側はその分類をUI/ログへ反映（既存正規化マップ拡張）
