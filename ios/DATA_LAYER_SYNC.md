# iOS Data Layer 同期設計書

> 作成日: 2026-03-24
> 目的: Android `data/` ディレクトリを基準として、iOS データ層を完全同期する

---

## 1. 現状差分サマリー

### 最重要ギャップ（バグの根本原因）

| 項目 | Android | iOS 現状 | 影響 |
|------|---------|---------|------|
| **リレー接続数** | Rust FFI が複数リレーへ並列接続 | **単一リレーのみ** (`wss://yabu.me` ハードコード) | バッジ・プロフィール・タイムライン取りこぼし |
| **リレータブ** | 専用 OkHttp WS で選択リレーに直接接続 | `client`（固定リレー）に送るだけ | リレータブが実質 yabu.me 固定 |
| **fetchBadges** | Kind 30008 → 30009 の2段階フェッチ | ~~Kind 8 直接フェッチ~~（修正済み） | バッジ不表示 |
| **Badge ViewModel 事前取得** | HomeViewModel で `async` 並列取得 | ~~未実装~~（修正済み） | バッジ不表示 |
| **Repository 構成** | 8ファイル拡張関数分割 | **1ファイル 640行** | 保守性・テスタビリティ |
| **NIP-65 対応** | Kind 10002 リレーリスト読み書き | **未実装** | ユーザーリレー設定が機能しない |
| **publishEvent 複数リレー** | 接続中の全リレーへ broadcast | 単一リレーのみ | 投稿・いいね等が届かないことがある |
| **enrichPosts (フル)** | プロフィール + リアクション数 + Zap + NIP-05 | プロフィールのみ | いいね数/リポスト数が常に0 |
| **enrichPostsLight** | プロフィールのみ（高速、リレータブ用）| 区別なし | リレータブが重い |
| **削除イベント永続追跡** | SharedPrefs に永続保存 | メモリのみ（再起動でリセット）| 削除投稿が復活 |

---

## 2. アーキテクチャ比較

### Android データ層

```
NostrClient.kt          ← Rust FFI NuruNuruClient（複数リレー並列管理）
  └─ fetchEvents()       ← Rust が全リレーから統合
  └─ fetchFromRelay()    ← 特定リレー指定
  └─ fetchFromSingleRelayWs()  ← OkHttp 直接 WS（リレータブ専用）

NostrRepository.kt      ← コア（プロフィール・共有ロジック）
  ├─ NostrRepositoryTimeline.kt     ← タイムライン
  ├─ NostrRepositoryActions.kt      ← 投稿・フォロー・削除
  ├─ NostrRepositoryReactions.kt    ← リアクション・Zap
  ├─ NostrRepositoryProfiles.kt     ← プロフィール・バッジ・絵文字
  ├─ NostrRepositoryTalk.kt         ← MLS
  ├─ NostrRepositoryNotifications.kt← 通知
  ├─ NostrRepositoryBackup.kt       ← バックアップ・リレー管理
  └─ NostrRepositoryLiveStream.kt   ← ライブ・WebView
```

### iOS 現状

```
NostrClient.swift       ← 単一 URLSessionWebSocketTask
NostrRepository.swift   ← 全機能が1ファイル（640行）
```

### iOS 目標（この設計書の完了後）

```
NostrClient.swift           ← マルチリレー対応（URLSession複数WS）
NostrRepository.swift       ← コア（接続・署名・共通fetchEvents）
NostrRepositoryTimeline.swift    ← タイムライン（Swift extension）
NostrRepositoryActions.swift     ← 投稿・フォロー・削除
NostrRepositoryProfiles.swift    ← プロフィール・バッジ・絵文字
NostrRepositoryNotifications.swift ← 通知
NostrRepositoryBackup.swift      ← バックアップ・NIP-65
```

---

## 3. 実装フェーズ計画

### Phase A — マルチリレー接続（最優先）

**目標**: `AppPreferences.selectedRelays` の全リレーに接続し、fetch を全リレーに broadcast する。

#### A-1. NostrClient をマルチリレー化

```swift
// 変更前
actor NostrClient {
    let relayURL: URL
    private var webSocketTask: URLSessionWebSocketTask?
}

// 変更後
actor NostrClient {
    private var connections: [String: RelayConnection] = [:]  // URL → WebSocket

    struct RelayConnection {
        let url: URL
        var task: URLSessionWebSocketTask?
        var state: ConnectionState
        var subscriptions: [String: Subscription]
    }

    func connect(relayUrls: [String]) async
    func disconnect() async

    /// 全接続リレーから並列フェッチ、結果を dedup して返す
    func fetchEvents(filters: [NostrFilter], timeoutSeconds: Double) async -> [NostrEvent]

    /// 特定リレー1つのみに接続してフェッチ（リレータブ用）
    func fetchEventsFromRelay(_ relayUrl: String, filters: [NostrFilter], timeoutSeconds: Double) async -> [NostrEvent]

    /// 全リレーへ publish
    func publish(event: NostrEvent) async throws
}
```

#### A-2. NostrRepository の init 変更

```swift
// 変更前
init(relayURL: URL = URL(string: "wss://yabu.me")!, ...)

// 変更後
init(keyManager: SecureKeyManager, prefs: AppPreferences, ffiClient: NuruNuruFFIBridge? = nil) {
    // prefs.selectedRelays の全リレーに接続
    self.client = NostrClient()
}

func connect() async {
    await client.connect(relayUrls: prefs.selectedRelays)
}
```

#### A-3. fetchEvents → 全リレー並列

```swift
// NostrClient.fetchEvents の内部実装
func fetchEvents(filters: [NostrFilter], timeoutSeconds: Double) async -> [NostrEvent] {
    // 全接続リレーへ同じ REQ を送り、結果を event.id で dedup
    await withTaskGroup(of: [NostrEvent].self) { group in
        for conn in connections.values where conn.state == .connected {
            group.addTask { await self.fetchFromConnection(conn, filters: filters, timeout: timeoutSeconds) }
        }
        var seen = Set<String>()
        var result: [NostrEvent] = []
        for await events in group {
            for e in events where seen.insert(e.id).inserted { result.append(e) }
        }
        return result
    }
}
```

#### A-4. リレータブ専用フェッチ

```swift
// NostrRepository に追加（Android fetchRelayTimeline に対応）
func fetchRelayTimeline(relayUrl: String, limit: Int = 50) async -> [ScoredPost] {
    let since = Int64(Date().addingTimeInterval(-3600).timeIntervalSince1970)
    let filter = NostrFilter(kinds: [NostrKind.textNote], since: since, limit: limit)
    let events = await client.fetchEventsFromRelay(relayUrl, filters: [filter], timeoutSeconds: 8)
    return await enrichPostsLight(events)
}
```

---

### Phase B — Repository ファイル分割

Android の Kotlin extension 関数パターンを Swift extension で再現する。

#### ファイル構成

```
ios/NuruNuru/Data/
  NostrRepository.swift              ← コア (actor 定義・init・fetchEvents・publishEvent)
  NostrRepositoryTimeline.swift      ← extension NostrRepository: timeline
  NostrRepositoryActions.swift       ← extension NostrRepository: actions
  NostrRepositoryProfiles.swift      ← extension NostrRepository: profiles, badges, emoji
  NostrRepositoryNotifications.swift ← extension NostrRepository: notifications
  NostrRepositoryBackup.swift        ← extension NostrRepository: backup, NIP-65
```

#### 各ファイルの担当（Android 対応表）

| iOS ファイル | Android ファイル | 主要メソッド |
|---|---|---|
| `NostrRepositoryTimeline.swift` | `NostrRepositoryTimeline.kt` | `fetchGlobalTimeline`, `fetchFollowingTimeline`, `fetchRelayTimeline`, `searchEvents`, `enrichPosts`, `enrichPostsLight` |
| `NostrRepositoryActions.swift` | `NostrRepositoryActions.kt` | `publishNote`, `publishFollowList`, `publishDelete`, `toggleLike`, `toggleRepost`, `fetchMuteList`, `publishMuteList`, `muteUser`, `reportEvent` |
| `NostrRepositoryProfiles.swift` | `NostrRepositoryProfiles.kt` | `fetchProfile`, `fetchProfiles`, `fetchUserNotes`, `fetchLikedEvents`, `fetchBadges`, `fetchEmojiList`, `fetchEmojiSet` |
| `NostrRepositoryNotifications.swift` | `NostrRepositoryNotifications.kt` | `fetchNotifications` |
| `NostrRepositoryBackup.swift` | `NostrRepositoryBackup.kt` | `fetchRelayList`(NIP-65), `publishRelayList`, `updateProfile`, `fetchAllUserEvents` |

---

### Phase C — enrichPosts 完全実装

Android の `enrichPosts` に合わせてリアクション数・Zap 額を取得する。

```swift
// 現状: プロフィールのみ
// 目標: Android enrichPosts と同等

func enrichPosts(_ events: [NostrEvent]) async -> [ScoredPost] {
    let posts = events.map { ScoredPost(event: $0) }
    let pubkeys = Array(Set(events.map { $0.pubkey }))
    let eventIds = events.map { $0.id }

    // 並列フェッチ（Android: coroutineScope { async { } }）
    async let profilesTask   = fetchProfiles(pubkeys: pubkeys)
    async let reactionsTask  = fetchReactionCounts(eventIds: eventIds)
    async let repostsTask    = fetchRepostCounts(eventIds: eventIds)
    async let isLikedTask    = fetchMyLikes(eventIds: eventIds, myPubkey: myPubkeyHex)

    let (profiles, reactions, reposts, myLikes) = await (profilesTask, reactionsTask, repostsTask, isLikedTask)

    let profileMap = Dictionary(profiles.map { ($0.pubkey, $0) }, uniquingKeysWith: { a, _ in a })
    for post in posts {
        post.profile     = profileMap[post.event.pubkey]
        post.likeCount   = reactions[post.event.id] ?? 0
        post.repostCount = reposts[post.event.id] ?? 0
        post.isLiked     = myLikes.contains(post.event.id)
    }
    return posts
}

/// 軽量版 — プロフィールのみ（リレータブ用）
func enrichPostsLight(_ events: [NostrEvent]) async -> [ScoredPost] {
    let posts = events.map { ScoredPost(event: $0) }
    let pubkeys = Array(Set(events.map { $0.pubkey }))
    let profiles = await fetchProfiles(pubkeys: pubkeys)
    let profileMap = Dictionary(profiles.map { ($0.pubkey, $0) }, uniquingKeysWith: { a, _ in a })
    for post in posts { post.profile = profileMap[post.event.pubkey] }
    return posts
}
```

---

### Phase D — NIP-65 リレーリスト

Kind 10002 でユーザーのリレーリストを取得・発行する。

```swift
// NostrRepositoryBackup.swift
struct Nip65Relay {
    let url: String
    let read: Bool
    let write: Bool
}

func fetchRelayList(pubkeyHex: String) async -> [Nip65Relay] {
    let filter = NostrFilter(authors: [pubkeyHex], kinds: [NostrKind.relayList], limit: 1)
    let events = await fetchEvents(filters: [filter], timeoutSeconds: 5)
    guard let event = events.max(by: { $0.createdAt < $1.createdAt }) else { return [] }
    return event.tags
        .filter { $0.first == "r" && $0.count >= 2 }
        .map { tag -> Nip65Relay in
            let url = tag[1]
            let marker = tag.count >= 3 ? tag[2] : ""
            return Nip65Relay(url: url, read: marker != "write", write: marker != "read")
        }
}

func publishRelayList(_ relays: [Nip65Relay]) async throws {
    let tags: [[String]] = relays.map { relay in
        if relay.read && relay.write { return ["r", relay.url] }
        else if relay.read           { return ["r", relay.url, "read"] }
        else                         { return ["r", relay.url, "write"] }
    }
    try await publishEvent(kind: NostrKind.relayList, tags: tags, content: "")
}
```

---

### Phase E — 削除イベント永続追跡強化

```swift
// NostrCache に追加（現状はメモリのみ、Android は SharedPreferences 永続）
// 現状の addDeletedEventId / getDeletedEventIds は UserDefaults 使用で OK
// ただし filterDeleted を NostrRepository 全フェッチに適用する

// NostrRepository に追加
private func filterDeleted(_ events: [NostrEvent]) -> [NostrEvent] {
    let deleted = cache.getDeletedEventIds()
    return events.filter { !deleted.contains($0.id) }
}
```

---

## 4. 実装順序とリスク評価

| # | フェーズ | 工数目安 | リスク | 優先度 |
|---|---------|--------|--------|--------|
| **A-1** | NostrClient マルチリレー化 | 大 | 高（WebSocket 管理複雑化） | **最優先** |
| **A-2/A-3** | NostrRepository connect + fetchEvents | 中 | 中 | **最優先** |
| **A-4** | リレータブ専用フェッチ | 小 | 低 | 高 |
| **B** | Repository ファイル分割 | 中 | 低（動作変わらず） | 中 |
| **C** | enrichPosts フル実装 | 中 | 低 | 高 |
| **D** | NIP-65 | 小 | 低 | 中 |
| **E** | 削除永続追跡 | 小 | 低 | 低 |

---

## 5. Phase A 詳細設計 — NostrClient マルチリレー化

### 5.1 接続ライフサイクル

```
MainTabView.onAppear
  └─ repository.connect()
       └─ client.connect(relayUrls: prefs.selectedRelays)
            ├─ connect("wss://yabu.me")
            ├─ connect("wss://relay.damus.io")
            └─ connect("wss://nos.lol")

MainTabView.onDisappear
  └─ repository.disconnect()
       └─ client.disconnect()  ← 全 WebSocket を閉じる
```

### 5.2 サブスクリプション管理

```
subscribe(filters, id)
  ├─ 全接続リレーに ["REQ", id, ...filter] を送信
  └─ 全リレーの応答を単一 AsyncStream にマージして返す

fetchEvents(filters, timeout)
  ├─ subscribe を呼ぶ
  ├─ 最初の EOSE が来たら即返す（他リレーのイベントも収集済み）
  └─ timeout で打ち切り
```

### 5.3 dedup 戦略

- `event.id`（32バイト hex）で dedup
- 同一イベントが複数リレーから返ってきても1件のみ保持
- `createdAt` 降順でソートして返す

### 5.4 接続障害時の扱い

- 接続失敗リレーはスキップ（他リレーで続行）
- 再接続試行: 120秒クールダウン（Android `Connection.relayCooldownMs` 相当）
- 全リレー障害時: `connectionState = .failed`

---

## 6. Phase A で解決するバグ

| バグ | 原因 | 解決 |
|-----|------|------|
| バッジが表示されない | yabu.me に kind 30008 がない場合 | ユーザーリレー全てを検索 |
| フォロータイムラインが少ない | 単一リレーしか見ていない | 全リレーから並列取得 |
| リレータブが実質 yabu.me 固定 | `client` が単一リレーのみ | `fetchEventsFromRelay` で専用接続 |
| 投稿が届かないことがある | 単一リレーにのみ publish | 全リレーへ broadcast |
| プロフィールが取れないことがある | 単一リレーしか検索しない | 全リレーから取得 |

---

## 7. 後方互換性メモ

- `MainTabView` の `NostrRepository(relayURL:...)` → `NostrRepository(...)` に変更
- `AppPreferences.selectedRelays` はすでに存在し `defaultRelays` で初期値あり
- `defaultRelays` の定義が見つからない場合は `["wss://yabu.me"]` をフォールバックとする
- `NostrClient` の公開 API (`subscribe`, `publish`, `connect`, `disconnect`) は変更しない（内部のみ変更）

---

## 8. 現在修正済み項目（参考）

| 項目 | 修正内容 | ステータス |
|-----|---------|---------|
| fetchBadges | Kind 30008 → 30009 2段階フェッチに修正 | ✅ 完了 |
| NIP-05 表示 | `isVerified` 条件を削除、nip05 フィールドがあれば表示 | ✅ 完了 |
| HomeViewModel バッジ事前取得 | `loadProfile()` で並列取得 | ✅ 完了 |
| ProfileHeader initialBadges | ViewModel 取得結果を BadgeDisplay に渡す | ✅ 完了 |
| PostActions 順序 | Like → Repost（Android 準拠） | ✅ 完了 |
| タブアイコン統一 | Android 準拠 | ✅ 完了 |
| PostActions 配置 | content VStack 内（アバター横）に移動 | ✅ 完了 |
| "もっと見る" / "閉じる" | Android exact copy | ✅ 完了 |

---

## 9. 参照ファイル

| ファイル | 役割 |
|---------|------|
| `android/data/NostrClient.kt` | Rust FFI 接続管理（参考実装）|
| `android/data/NostrRepositoryTimeline.kt` | タイムライン・enrichPosts |
| `android/data/NostrRepositoryProfiles.kt` | バッジ2段階フェッチ・詳細実装 |
| `android/data/AppPreferences.kt` | リレー設定・NIP-65 |
| `android/data/cache/NostrCache.kt` | 2層キャッシュ設計 |
| `ios/NuruNuru/Data/NostrClient.swift` | 変更対象 |
| `ios/NuruNuru/Data/NostrRepository.swift` | 変更対象 |
| `ios/NuruNuru/Data/AppPreferences.swift` | selectedRelays 確認済 |
