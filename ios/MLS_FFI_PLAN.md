# iOS MLS-Only UniFFI 統合設計書

> UniFFI の境界を MLS 暗号層だけに限定し、それ以外は pure Swift を維持する。

## 方針

| 機能 | 担当 | 理由 |
|------|------|------|
| MLS (Marmot MIP-00〜03) | Rust UniFFI (mdk-core 0.7.1 + OpenMLS) | Swift で再実装不可能。WhiteNoise 互換に必須 |
| Timeline / Profile / Follow | pure Swift (実装済) | 既に動作中。FFI 経由の意味なし |
| NIP-44 暗号化 | pure Swift (CryptoKit + secp256k1) | `InternalSigner` で実装済 |
| Recommendation | pure Swift (新規) | 439行の計算ロジック。Swift で十分 |
| リレー接続 | pure Swift (`NostrClient` + `ConnectionManager`) | 既に動作中 |
| Publishing | pure Swift | 既に動作中 |

---

## フェーズ一覧

| Phase | 内容 | 工数 | 依存 |
|-------|------|------|------|
| 1 | FFI ブリッジ縮小 (MLS のみ) | 1-2日 | なし |
| 2 | XCFramework 有効化 | 半日 | Phase 1 |
| 3 | MLS 送受信の publish パス pure Swift 化 | 半日 | Phase 1 |
| 4 | Recommendation エンジン Swift 移植 | 1日 | なし |
| 5 | テスト + クリーンアップ | 1日 | Phase 1-3 |
| 6 | Rust バイナリサイズ最適化 (任意) | 将来 | — |

---

## Phase 1: FFI ブリッジ縮小

### 1.1 `NuruNuruFFIBridge.swift` → MLS 専用化

**変更前:** 40+ メソッドのプロトコル (全機能)
**変更後:** 14 メソッド (MLS のみ) + 初期化

```swift
/// MLS 暗号層のみの FFI ブリッジ。
/// Timeline / Profile / Publishing は pure Swift が担当。
/// groupIdHex は Nostr group id hex (Kind 445 `h` tag) であり、
/// internal MLS group id は Rust 内部から外へ出さない。
protocol MlsFFIBridge: AnyObject, Sendable {

    // ── 初期化 ──
    func connect()
    func disconnect() throws

    // ── KeyPackage (Kind 30443, MIP-00) ──
    func mlsCreateKeyPackage() throws -> FfiKeyPackageEventData
    func mlsValidateKeyPackageEvent(eventJSON: String) throws
    func mlsDeleteConsumedKeyPackageFromEventJSON(eventJSON: String) throws
    /// Returns Nostr group id hex values, not internal MLS group ids.
    func mlsGroupsNeedingSelfUpdate(thresholdSecs: UInt64) throws -> [String]

    // ── グループ管理 ──
    func mlsCreateGroup(name: String, adminPubkeys: [String], relays: [String]) throws -> FfiMlsGroupInfo
    func mlsAddMember(groupIdHex: String, keyPackageEventJSON: String) throws -> FfiAddMemberResult
    func mlsRemoveMember(groupIdHex: String, memberPubkeyHex: String) throws -> FfiEncryptedMessageData
    func mlsLeaveGroup(groupIdHex: String) throws -> FfiEncryptedMessageData
    func mlsListGroups() throws -> [FfiMlsGroupInfo]
    func mlsGetGroupInfo(groupIdHex: String) throws -> FfiMlsGroupInfo

    // ── メッセージ送受信 (Kind 445) ──
    func mlsCreateMessage(groupIdHex: String, content: String) throws -> FfiEncryptedMessageData
    func mlsProcessMessage(groupIdHex: String, eventJSON: String) throws -> FfiDecryptedMessage
    func mlsProcessMessageResult(groupIdHex: String, eventJSON: String) throws -> FfiMlsProcessResult

    // ── Welcome (Kind 444 / 1059) ──
    func mlsProcessWelcome(welcomeEventJSON: String) throws -> FfiMlsGroupInfo

    // ── 履歴 + 状態管理 ──
    func mlsGetMessageHistory(groupIdHex: String, limit: UInt64) throws -> [FfiDecryptedMessage]
    func mlsMergePendingCommit(groupIdHex: String) throws
    func mlsCreateRecoveryCommit(groupIdHex: String) throws -> FfiEncryptedMessageData
    func mlsClearPendingCommit(groupIdHex: String) throws
}
```

**削除するメソッド (27個):**

- `fetchGlobalTimeline`, `fetchFollowTimeline`, `fetchRecommendedTimeline`
- `fetchEventsFromRelay`, `queryLocal`
- `fetchProfile`, `fetchProfiles`, `fetchFollowList`
- `followUser`, `unfollowUser`
- `publishNote`, `publishNoteWithTags`, `publishEvent`, `publishRawEvent`
- `react`, `repost`, `deleteEvent`
- `createUnsignedReaction`, `createUnsignedRepost`, `createUnsignedEvent`
- `search`
- `markNotInterested`, `recordEngagement`
- `startLiveSubscription`, `pollLiveEvents`, `stopLiveSubscription`
- `nip44Encrypt`, `nip44Decrypt`

**削除するデータ型:**

- `FfiUserProfile` (iOS の `UserProfile` モデルで代替)
- `FfiScoredPost` (iOS の `ScoredPost` モデルで代替)
- `FfiConnectionStats`

**維持するデータ型:**

- `FfiMlsGroupInfo`
- `FfiDecryptedMessage`
- `FfiEncryptedMessageData`
- `FfiWelcomeEventData`
- `FfiAddMemberResult`
- `FfiKeyPackageEventData`

**`NuruNuruFFIStub` → `MlsFFIStub`:**

スタブも MLS 14 メソッドのみ。全て空データを返す。

### 1.2 `NuruNuruFFILiveClient.swift` → MLS 専用化

**変更前:** 40+ メソッドの bridging (全機能)
**変更後:** 14 メソッド + 初期化

```swift
#if NURUNURU_FFI_AVAILABLE
import NuruNuruFFILib

final class MlsFFILiveClient: MlsFFIBridge, @unchecked Sendable {
    private let client: NuruNuruClient

    init(secretKeyHex: String, dbPath: String) throws {
        try initEngine(dbPath: dbPath)
        self.client = try NuruNuruClient(secretKeyHex: secretKeyHex)
    }

    init(pubkeyHex: String, dbPath: String) throws {
        try initEngine(dbPath: dbPath)
        self.client = try NuruNuruClient.newReadOnly(pubkeyHex: pubkeyHex)
    }

    // MLS 14 メソッドの bridging のみ
    // ...
}
#endif
```

**削除:** `bridgeUserProfile`, timeline/profile/publishing 全ブリッジメソッド

**維持する型変換ヘルパー:**

- `bridgeGroupInfo(_:)` — `NuruNuruFFILib.FfiMlsGroupInfo` → `NuruNuru.FfiMlsGroupInfo`
- `bridgeDecryptedMessage(_:)` — 同上
- `bridgeEncryptedMsg(_:)` — 同上
- `bridgeWelcomeEvent(_:)` — 同上
- `bridgeKeyPackage(_:)` — 同上
- `bridgeAddMemberResult(_:)` — 同上

### 1.3 `NostrRepository.swift` の変更

```diff
- var ffiClient: NuruNuruFFIBridge?
+ var mlsClient: MlsFFIBridge?

- func ensureFfiClient() -> NuruNuruFFIBridge? {
+ func ensureMlsClient() -> MlsFFIBridge? {
    #if NURUNURU_FFI_AVAILABLE
-   // ... (ロジック同一、型のみ変更)
+   // MlsFFILiveClient を生成
    #else
    return nil
    #endif
  }
```

`connect()` から `ffiClient?.connect()` を削除。MLS engine の `connect()` は relay 接続 (nostr-sdk) を起動するが、MLS 限定利用では不要な可能性がある。要検証。

### 1.4 各 `NostrRepository+*.swift` の変更

**`NostrRepository+Timeline.swift`:**
- `if let ffi { ffi.fetchGlobalTimeline(...) } else { /* pure Swift */ }` → pure Swift パスのみ残す

**`NostrRepository+Actions.swift`:**
- `ffi.publishNoteWithTags` / `ffi.followUser` / `ffi.unfollowUser` / `ffi.deleteEvent` / `ffi.react` / `ffi.repost` → 全て削除、pure Swift のみ

**`NostrRepository+Profiles.swift`:**
- `ffi.fetchProfile` / `ffi.fetchProfiles` / `ffi.fetchFollowList` → 全て削除

**`NostrRepository+Notifications.swift`:**
- FFI 依存なし。変更不要。

**`NostrRepository+LiveStream.swift`:**
- `ffi.startLiveSubscription` / `ffi.pollLiveEvents` → 削除

**`NostrRepository+Talk.swift`:**
- `ensureFfiClient()` → `ensureMlsClient()` に置換
- `publishMlsKind445` / `publishMlsWelcome` 内の `ffi.publishRawEvent` → Phase 3 で pure Swift 化

---

## Phase 2: XCFramework 有効化

### 2.1 ビルド手順

```bash
# 1. Rust ターゲット追加 (初回のみ)
rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios

# 2. XCFramework ビルド
cd rust-engine/nurunuru-ffi/bindgen && make xcframework

# 3. 出力確認
ls -la rust-engine/nurunuru-ffi/ios/NuruNuruFFI.xcframework/
```

### 2.2 Xcode プロジェクト設定

`ios/project.yml` に必要な設定 (既に存在するはず):

```yaml
settings:
  SWIFT_ACTIVE_COMPILATION_CONDITIONS: NURUNURU_FFI_AVAILABLE

packages:
  NuruNuru:
    path: ../rust-engine/nurunuru-ffi/ios

targets:
  NuruNuru:
    dependencies:
      - package: NuruNuru
        product: NuruNuruFFILib
```

### 2.3 動作確認

```bash
cd ios && xcodegen generate --spec project.yml
xcodebuild -scheme NuruNuru \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation build
```

`NURUNURU_FFI_AVAILABLE` が ON になり、`MlsFFILiveClient` が `NuruNuruFFILib` をインポートしてコンパイルされることを確認。

---

## Phase 3: MLS publish パスの pure Swift 化

### 問題

`NostrRepository+Talk.swift` 内の `publishMlsKind445` と `publishMlsWelcome` は、MLS で暗号化したイベントをリレーに送出するために `ffi.publishRawEvent(eventJson:)` を使用している。

Phase 1 で非 MLS の `publishRawEvent` を FFI から削除したため、これを pure Swift に切り替える。

### 変更

```swift
// 変更前
private func publishMlsKind445(data: FfiEncryptedMessageData, ffi: NuruNuruFFIBridge) async throws {
    try ffi.publishRawEvent(eventJson: data.content)
}

// 変更後
private func publishMlsKind445(data: FfiEncryptedMessageData) async throws {
    // data.content は署名済み Kind-445 イベント JSON (mdk-core が ephemeral key で署名)
    // pure Swift の NostrClient 経由でリレーに送出
    guard let eventData = data.content.data(using: .utf8),
          let eventDict = try? JSONSerialization.jsonObject(with: eventData) as? [String: Any] else {
        throw MlsError.invalidEventJson
    }
    try await client.publishRawEventJSON(data.content, to: prefs.selectedRelays)
}
```

`NostrClient` に `publishRawEventJSON(_:to:)` メソッドを追加する必要がある (署名済み JSON をそのまま WebSocket に `["EVENT", ...]` として送出)。

---

## Phase 4: Recommendation エンジン Swift 移植

### 新規ファイル

#### `ios/NuruNuru/Data/RecommendationConfig.swift`

```swift
/// Recommendation scoring weights.
/// Source of truth: design-tokens/constants.json + rust-engine/nurunuru-core/src/config.rs
struct RecommendationConfig {
    // Engagement weights
    let zapWeight: Double       = 100.0
    let quoteWeight: Double     = 35.0
    let replyWeight: Double     = 30.0
    let repostWeight: Double    = 25.0
    let bookmarkWeight: Double  = 15.0
    let likeWeight: Double      = 5.0

    // Time decay
    let halfLifeSeconds: Double = 21600   // 6h
    let maxAgeSeconds: Double   = 172800  // 48h
    let freshnessBoost: Double  = 1.5     // <1h boost
    let minScore: Double        = 0.1

    // Social
    let secondDegreeBoost: Double        = 3.0
    let mutualFollowBoost: Double        = 2.5
    let highEngagementAuthorBoost: Double = 2.0
    let firstDegreeBoost: Double         = 0.5
    let unknownBoost: Double             = 1.0

    // Feed mix
    let secondDegreeFraction: Double  = 0.50
    let outOfNetworkFraction: Double  = 0.30
    let firstDegreeFraction: Double   = 0.20
}
```

#### `ios/NuruNuru/Data/RecommendationEngine.swift`

```swift
/// Feed scoring engine. Mirrors rust-engine/nurunuru-core/src/recommendation.rs.
struct RecommendationEngine {
    let config: RecommendationConfig

    init(config: RecommendationConfig = .init()) {
        self.config = config
    }

    func timeDecay(createdAt: Int64) -> Double { ... }
    func engagementScore(likes: Int, reposts: Int, replies: Int, zaps: Int, quotes: Int) -> Double { ... }
    func socialBoost(authorPubkey: String, followList: Set<String>, secondDegree: Set<String>) -> Double { ... }
    func scorePost(_ post: ScoredPost, followList: Set<String>, secondDegree: Set<String>) -> Double { ... }
    func rankFeed(posts: [ScoredPost], followList: Set<String>, secondDegree: Set<String>) -> [ScoredPost] { ... }
}
```

ロジックは `recommendation.rs` の `rank_feed()` と 1:1 対応。

---

## Phase 5: テスト + クリーンアップ

### テスト項目

**MLS E2E テスト (手動):**

1. iOS で MLS グループ作成 → Android に Welcome 送信 → Android で参加確認
2. Android でメッセージ送信 → iOS で Kind-445 受信 → `mlsProcessMessage` で復号
3. iOS でメッセージ送信 → `mlsCreateMessage` → pure Swift `publishRawEventJSON` → Android で復号
4. WhiteNoise クライアントとの相互運用

**Pure Swift 回帰テスト:**

- [ ] Timeline 取得 (global / following) が FFI なしで動作
- [ ] Profile 取得 / Follow / Unfollow が動作
- [ ] Note 投稿 / React / Repost / Delete が動作
- [ ] NIP-44 暗号化が動作
- [ ] 通知が動作
- [ ] 検索が動作

**Recommendation テスト (単体):**

- [ ] `timeDecay` が Rust 版と同じ値を返す
- [ ] `engagementScore` が Rust 版と同じ値を返す
- [ ] `rankFeed` のソート順が Rust 版と一致

### クリーンアップ

削除対象ファイル/コード:
- `NuruNuruFFIBridge.swift` 内の非 MLS メソッド定義 + スタブ
- `NuruNuruFFILiveClient.swift` 内の非 MLS ブリッジ + `bridgeUserProfile`
- 各 `NostrRepository+*.swift` 内の `if let ffi` 分岐 (MLS 以外)
- `FfiUserProfile`, `FfiScoredPost`, `FfiConnectionStats` 型定義

---

## リスクと対策

| リスク | 影響 | 対策 |
|--------|------|------|
| XCFramework ビルドが macOS CI で失敗 | 高 | ビルド済 XCFramework を Git LFS でコミット。CI はリンクのみ |
| `NuruNuruClient` 初期化で nostrdb がクラッシュ | 中 | `ensureMlsClient()` で writable ディレクトリを渡す (既存コードで対応済) |
| `NuruNuruClient.connect()` が MLS のみ利用時に不要な relay 接続を起動 | 中 | `connect()` を呼ばないか、MLS 操作前にのみ lazy に呼ぶ。MLS 自体はローカル SQLite 操作なので relay 不要 |
| Kind-445 の `publishRawEventJSON` が一部リレーで REJECT される | 中 | MLS グループの `relays` リストのリレーにのみ送出 |
| Recommendation の Swift 版と Rust 版で数値微差 | 低 | Rust テストケースの期待値を Swift テストに移植して ±0.001 で検証 |

---

## ファイル変更サマリー

| ファイル | 操作 |
|----------|------|
| `ios/NuruNuru/Data/NuruNuruFFIBridge.swift` | 大幅縮小 (MLS 14メソッド + 6データ型のみ) |
| `ios/NuruNuru/Data/NuruNuruFFILiveClient.swift` | 大幅縮小 (MLS bridging のみ) |
| `ios/NuruNuru/Data/NostrRepository.swift` | `ffiClient` → `mlsClient`, `ensureMlsClient()` |
| `ios/NuruNuru/Data/NostrRepository+Talk.swift` | `ensureFfiClient` → `ensureMlsClient`, publish pure Swift 化 |
| `ios/NuruNuru/Data/NostrRepository+Timeline.swift` | FFI 分岐削除、pure Swift のみ |
| `ios/NuruNuru/Data/NostrRepository+Actions.swift` | FFI 分岐削除、pure Swift のみ |
| `ios/NuruNuru/Data/NostrRepository+Profiles.swift` | FFI 分岐削除、pure Swift のみ |
| `ios/NuruNuru/Data/NostrRepository+LiveStream.swift` | FFI 分岐削除、pure Swift のみ |
| `ios/NuruNuru/Data/NostrClient.swift` | `publishRawEventJSON(_:to:)` 追加 |
| `ios/NuruNuru/Data/RecommendationEngine.swift` | **新規** |
| `ios/NuruNuru/Data/RecommendationConfig.swift` | **新規** |
| `rust-engine/nurunuru-ffi/src/lib.rs` | **変更なし** (Android 互換維持) |
| `rust-engine/nurunuru-ffi/bindgen/Makefile` | **変更なし** |
