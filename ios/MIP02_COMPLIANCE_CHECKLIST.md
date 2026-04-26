# MIP-02 Compliance Checklist (iOS)

最終更新: 2026-04-22
対象: `ios/NuruNuru`（Swift）+ `rust-engine/nurunuru-*`（Rust/FFI）

このドキュメントは、Marmot Protocol **MIP-02 (Welcome Events)** の iOS 側実装を、
**MUST / mandatory** 要件中心に監査・維持するための固定チェックリストです。

---

## 1. 送信シーケンス（Fork防止）

### MUST
- 既存グループへのメンバー追加時、**Commit が relay に受理（OK ACK）される前に Welcome を送らない**。

### 実装
- ACK待機実装: `ios/NuruNuru/Data/NostrClient.swift`
  - `ClientError.publishRejected`
  - `ClientError.publishAckTimeout`
  - `waitForPublishAck(...)`
- 呼び出し順序: `ios/NuruNuru/Data/NostrRepository+Talk.swift`
  - `mlsAddMember` → `publishMlsKind445(commit)` → `publishMlsWelcome(...)`

### 回帰チェック
- [ ] Commit publish が `try await` で失敗伝播する
- [ ] Welcome publish が Commit publish 成功後にのみ実行される

---

## 2. Welcome 構造・受信バリデーション

### MUST
- Welcome rumor は `kind:444`（または gift-wrap `kind:1059` unwrap 後 `444`）
- `encoding` タグは `base64` のみ許可（未指定/未知値は reject）
- `e` タグ（consumed KeyPackage event id）必須
- `relays` タグに有効 relay URL を含む

### 実装
- `ios/NuruNuru/Data/NostrRepository+Talk.swift`
  - `validateWelcomeEventForMip02(...)`
- Rust unwrap: `rust-engine/nurunuru-core/src/engine.rs`
  - `mls_process_welcome(...)`（1059 unwrap → 444）

### 回帰チェック
- [ ] `invalidWelcomeEncoding` が UI 文言にマップされる
- [ ] `invalidWelcomeMissingKeyPackageRef` が UI 文言にマップされる
- [ ] `invalidWelcomeRelays` が UI 文言にマップされる

---

## 3. KeyPackage Lifecycle（rotation + consumed material delete）

### MUST
- Welcome成功後、consumed KeyPackage をローテーション
  - consumed が `kind:30443` の場合: **同じ `d`** で再発行
  - consumed が `kind:443` の場合: 新規 `d` の `kind:30443` 発行
- consumed init_key/private material をローカルから削除

### 実装
- iOS: `ios/NuruNuru/Data/NostrRepository+Talk.swift`
  - `rotateConsumedKeyPackageAfterWelcomeIfNeeded(...)`
  - 30443の `d` 再利用
  - relay取得失敗時 fallback: `AppPreferences.mlsKeyPackageEventJsonById`
- local tracking: `ios/NuruNuru/Data/AppPreferences.swift`
  - `mlsKeyPackageEventJsonById`
- Rust core: `rust-engine/nurunuru-core/src/mls.rs`
  - `delete_consumed_key_package_from_event_json(...)`
- Rust engine/FFI:
  - `mls_delete_consumed_key_package_from_event_json(...)`
- iOS bridge:
  - `MlsFFIBridge.mlsDeleteConsumedKeyPackageFromEventJSON(...)`

### 仕様データ準拠（重要）
- `FfiKeyPackageEventData` は以下を保持すること
  - `tags`（kind:30443 canonical）
  - `legacyTags`（kind:443 migration 用。MDK由来）
  - `dTag`（30443スロット識別子。MDK由来）
- iOS は `legacyTags` を優先使用して 443 を publish し、`d` 除去推測は **fallback のみ**

### 回帰チェック
- [ ] Welcome処理後に rotation が呼ばれる
- [ ] 30443 consumed で `d` 再利用が効く
- [ ] `mlsDeleteConsumedKeyPackageFromEventJSON` が成功/失敗をログ出力する
- [ ] 443 publish が `legacyTags` 優先で行われる

---

## 4. Post-Join Self-Update（24h要件）

### MUST
- Welcome成功後、可能な限り早く self-update
- 遅くとも 24h 以内に self-update（relay不達時は再試行）

### 実装
- `ios/NuruNuru/Data/NostrRepository+Talk.swift`
  - `postWelcomeBestEffortCatchUpAndSelfUpdate(...)`
  - `enforceSelfUpdateDeadlineIfNeeded(...)`
- Rust側の状態ソースを優先
  - `mls_groups_needing_self_update(86400)`
- Fallback tracking
  - `AppPreferences.mlsJoinedAtByGroupId`
  - `AppPreferences.mlsSelfUpdateCompletedAtByGroupId`

### 回帰チェック
- [ ] Welcome直後に catch-up → self-update が試行される
- [ ] self-update 成功時に completion timestamp が保存される
- [ ] `mlsGroupsNeedingSelfUpdate` 利用が有効

---

## 5. Legacy 443 migration window

### 運用方針（移行期）
- canonical publish は `kind:30443`（常時）
- 互換 publish は `kind:443`（期限付き）

### 実装
- `ios/NuruNuru/Data/NostrRepository+Talk.swift`
  - `shouldDualPublishLegacy443()`
  - cutoff: `2026-05-01T00:00:00Z`
  - `publishKeyPackage(...)` と rotation publish の両方に適用
- `rust-engine/nurunuru-core/src/types.rs` / `rust-engine/nurunuru-ffi/src/lib.rs`
  - `KeyPackageEventData` / `FfiKeyPackageEventData` が `legacy_tags` / `d_tag` を持つ

### 回帰チェック
- [ ] 期限前は 30443 + 443
- [ ] 期限後は 30443 のみ
- [ ] 443のタグは `legacyTags`（MDK由来）を優先利用

---

## 6. エラー処理とUX

### MUST
- 処理失敗時にユーザーへ明確なメッセージ
- 技術ログを保持（デバッグ可能）

### 実装
- `ios/NuruNuru/Data/NostrRepository+Talk.swift`
  - `MlsError` 拡張（Welcome関連）
- `ios/NuruNuru/ViewModels/TalkViewModel.swift`
  - エラー種別ごとの日本語メッセージ
- `AppLogger.log("MLS", ...)`

### 回帰チェック
- [ ] Welcome種別不正/encoding不正/e欠落/relays不正の個別表示
- [ ] publishAckTimeout / publishRejected の上位伝播

---

## 7. リリース前チェック（実行手順）

```bash
# iOS build
cd ios && xcodebuild -scheme NuruNuru -destination 'platform=iOS Simulator,name=iPhone 17' -skipPackagePluginValidation build

# (Rust/FFI変更時) Swift binding + XCFramework
cd rust-engine/nurunuru-ffi/bindgen && make swift && make xcframework
```

### 合格基準
- [ ] `BUILD SUCCEEDED`
- [ ] Welcome受信→join→rotation→consumed delete→self-update のログが1周確認できる
- [ ] 既存会話送受信（kind:445）退行なし
- [ ] FFI追加API/フィールドが `ios/Sources/NuruNuru/nurunuru_ffi.swift` と `NuruNuruFFI.xcframework` の双方に反映され、checksum mismatch がない

---

## 8. 既知の依存/注意

- MIP本文の一部検証（拡張詳細・内部鍵ライフサイクル）は MDK 側責務が大きい
- iOS は FFI API で state/query/delete を呼び出し、MUSTフローを担保
- FFI API追加時は **Swift生成コードとXCFrameworkの同時更新**が必要

---

## 9. 変更時の最小ルール

- MUST項目を落とす変更は不可
- `NostrRepository+Talk.swift` の以下関数変更時は本チェックリスト更新必須
  - `publishKeyPackage`
  - `publishMlsWelcome`
  - `validateWelcomeEventForMip02`
  - `rotateConsumedKeyPackageAfterWelcomeIfNeeded`
  - `postWelcomeBestEffortCatchUpAndSelfUpdate`
  - `enforceSelfUpdateDeadlineIfNeeded`
