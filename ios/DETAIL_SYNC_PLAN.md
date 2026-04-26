# iOS ↔ Android 細部同期プラン & 設計書

> 作成日: 2026-04-05
> 前提: ホーム / トーク / タイムライン / ミニアプリ の4タブは同期完了済み
> 対象: ログイン / プロフィール / 検索 / 通知 / リレー / キャッシュ / 投稿モーダル

---

## 現状サマリー（同期率）

| 機能領域 | iOS 同期率 | 主なギャップ |
|----------|-----------|------------|
| **ログイン** | 🔶 85% | NIP-46未実装、Amber→NIP-46変換ロジック、Deep Link |
| **プロフィール** | 🔶 80% | バナー画像、EditProfile画像アップロード、npubコピー |
| **検索** | 🔶 75% | NIP-05解決、kind指定、除外/完全一致UIチップ、トレンド |
| **通知** | 🔶 65% | ライブポーリング、新着Pill、Kind設定ダイアログ、元投稿表示 |
| **リレー** | ✅ 90% | 接続状態リアルタイム更新、自動再接続UI |
| **キャッシュ** | 🔶 70% | NostrCache 2層統合、サイズ表示、期限切れ自動清掃 |
| **投稿モーダル** | 🔶 70% | リレー選択パネル、NIP-70、STT、カスタム絵文字、ハッシュタグ色付け |

**目標: 全領域 95%+ 同期**

---

## Phase 1 — ログイン同期 (LoginView ↔ LoginScreen)

### 1-1. 現状比較

| 機能 | Android | iOS 現状 | 差異 |
|------|---------|---------|------|
| nsec ログイン | ✅ | ✅ | 同等 |
| NIP-55 Amber | ✅ `amberLauncher` | N/A | iOS非対応（正常） |
| NIP-46 Nostr Connect | ❌ (Android不要) | 🔶 ボタンのみ・未実装 | **要実装** |
| 新規登録 | ✅ `SignUpModal` | ✅ `SignUpSheet` | ほぼ同等 |
| Deep Link | ✅ `nurunuru://login?nsec=` | ❌ 未実装 | **要実装** |
| ローディングアニメ | ✅ logo pulse | ✅ logo pulse | 同等 |
| 生体認証 | ❌ | ❌ | 将来対応 |

### 1-2. 実装タスク

#### A. NIP-46 Nostr Connect 実装
**ファイル:** `ios/NuruNuru/Data/ExternalSigner.swift`（新規）、`LoginView.swift`

```swift
// ExternalSigner.swift — NIP-46 Remote Signer Client
actor ExternalSigner {
    enum State { case disconnected, connecting, waitingApproval, connected }
    
    private(set) var state: State = .disconnected
    private var client: NostrClient?
    private var remotePubkey: String?
    private var secret: String?
    
    /// nostrconnect:// URI をパースして接続開始
    func connect(uri: String) async throws -> String {
        // 1. URI パース: nostrconnect://<relay>?pubkey=<remote>&secret=<secret>
        // 2. リレーに WebSocket 接続
        // 3. Kind 24133 (NIP-46 request) で "connect" 送信
        // 4. Kind 24133 response 待ち → pubkey 返却
    }
    
    /// リモート署名リクエスト
    func sign(event: UnsignedEvent) async throws -> String {
        // Kind 24133 "sign_event" request → response.sig
    }
}
```

**UI変更:** `LoginView.swift` の `nostrConnectButton` にQRスキャン + URI入力を追加

```
フロー:
1. 「Nostr Connectでログイン」タップ
2. Sheet展開 → QRスキャン or テキスト入力 (nostrconnect://...)
3. 接続中 → ProgressView + 「承認待ち...」
4. 承認完了 → prefs.isExternalSigner = true → loggedIn
```

#### B. Deep Link 対応
**ファイル:** `NuruNuruApp.swift`、`Info.plist`

```swift
// NuruNuruApp.swift
.onOpenURL { url in
    guard url.scheme == "nurunuru" else { return }
    switch url.host {
    case "login":
        if let nsec = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "nsec" })?.value {
            authViewModel.login(nsecOrHex: nsec)
        }
    default: break
    }
}
```

Info.plist に `CFBundleURLTypes` 追加: `nurunuru://`

#### C. LoginView UI 微調整

| 項目 | 変更内容 |
|------|---------|
| ログインボタンタイトル | Android: "キャンセル" テキストボタン（左）+ タイトル（中央）+ "ログイン" ボタン（右） |
| エラー表示位置 | nsec入力フィールド直下（現在と同じ、OK） |
| パスワード入力 | `showKey` toggle 動作確認済み |

### 1-3. 工数・優先度

| タスク | 工数 | 優先度 |
|--------|------|--------|
| NIP-46 基本実装 | 大（3-4日） | 中 |
| Deep Link | 小（0.5日） | 低 |
| UI微調整 | 極小 | 低 |

---

## Phase 2 — プロフィール同期 (Profile ↔ HomeScreen/UserProfileModal)

### 2-1. 現状比較

| 機能 | Android | iOS 現状 | 差異 |
|------|---------|---------|------|
| ProfileHeader バナー | ✅ AsyncImage banner | 🔶 一部実装 | **バナー表示の確認** |
| npub コピーボタン | ✅ タップでクリップボード | ❌ 未実装 | **要実装** |
| QR表示 | ✅ QRModal | 🔶 QRSheet あり | 確認必要 |
| EditProfile 画像アップロード | ✅ アバター/バナー各アップロード | 🔶 PhotosPicker実装済 | アップロード先同期 |
| フォロー/アンフォロー | ✅ | ✅ | 同等 |
| DM開始ボタン | ✅ | ✅ `onStartDM` | 同等 |
| 投稿削除 | ✅ 長押しメニュー | 🔶 `showDeleteConfirm` | 実装確認 |
| ミュート | ✅ メニューから | ❌ 未実装 | **要実装** |
| 通報 | ✅ `ReportModal` | ✅ `ReportSheet` | 確認 |
| プロフィール内検索 | ✅ | ✅ `showSearch` | 確認 |

### 2-2. 実装タスク

#### A. npub コピーボタン
**ファイル:** `Views/Components/ProfileComponents.swift`

```swift
// ProfileHeader 内、npub表示の横にコピーボタン追加
HStack(spacing: NuruSpacing.space2) {
    Text(shortenNpub(pubkey))
        .font(NuruFont.labelSmall())
        .foregroundStyle(theme.textTertiary)
    
    Button {
        UIPasteboard.general.string = NostrKeyUtils.encodeNpub(
            NostrKeyUtils.hexToBytes(pubkey) ?? []
        )
        // Toast: "npubをコピーしました"
    } label: {
        Image(systemName: "doc.on.doc")
            .font(.system(size: 12))
            .foregroundStyle(theme.textTertiary)
    }
}
```

#### B. ミュート機能（UserProfileSheet メニュー）
**ファイル:** `Views/Sheets/UserProfileSheet.swift`

```swift
// topBar の三点メニューに追加
Menu {
    Button { /* ミュート */ } label: {
        Label("ミュート", systemImage: "speaker.slash")
    }
    Button(role: .destructive) { /* 通報 */ } label: {
        Label("通報", systemImage: "exclamationmark.triangle")
    }
} label: {
    Image(systemName: "ellipsis")
}
```

**Backend:** `NostrRepository+Actions.swift` に `muteUser(pubkey:)` 追加
- Kind 10000 (Mute List) の更新
- Android `NostrRepositoryActions.kt` の `muteUser()` と同等

#### C. プロフィール画像アップロード同期
**ファイル:** `Views/Components/EditProfileSheet.swift`

現状 `PhotosPicker` は実装済み。確認事項:
- アップロード先: `ImageUploadService` の `nostr.build` / `yabu.me` / Blossom
- NIP-98 認証ヘッダー付きアップロード
- Android と同じアップロードサーバー選択を `AppPreferences.uploadServerEnum` で参照

### 2-3. 工数・優先度

| タスク | 工数 | 優先度 |
|--------|------|--------|
| npub コピー | 極小（0.5h） | 高 |
| ミュート機能 | 中（1日） | 高 |
| 画像アップロード確認 | 小（0.5日） | 中 |
| バナー表示確認 | 極小 | 低 |

---

## Phase 3 — 検索同期 (SearchSheet ↔ SearchModal)

### 3-1. 現状比較

| 機能 | Android | iOS 現状 | 差異 |
|------|---------|---------|------|
| NIP-50 テキスト検索 | ✅ searchnos | ✅ | 同等 |
| SearchQueryParser | ✅ 完全実装 | ✅ 同等実装 | 同等 |
| `#tag` 演算子 | ✅ | ✅ | 同等 |
| `from:` 演算子 | ✅ NIP-05解決あり | 🔶 直接キーのみ | **NIP-05解決未実装** |
| `since:`/`until:` | ✅ | ✅ | 同等 |
| `-word` 除外 | ✅ | ✅ クライアント側 | 同等 |
| `"phrase"` 完全一致 | ✅ | ✅ クライアント側 | 同等 |
| `filter:image/video/link` | ✅ | ✅ | 同等 |
| 最近の検索 | ✅ | ✅ UserDefaults | 同等 |
| 検索演算子ヒント | ✅ | ✅ `operatorsHint` | 同等 |
| トレンドタグ | ✅ *(要確認)* | ❌ | **要実装** |
| プロフィール検索結果 | ✅ nip-50 プロフィール | ❌ | **要実装** |
| 検索結果タブ（投稿/ユーザー） | ✅ *(要確認)* | ❌ | **要実装** |
| `kind:` 演算子 | ✅ | 🔶 parsed.kind | 確認 |

### 3-2. 実装タスク

#### A. `from:` NIP-05 解決
**ファイル:** `Views/Sheets/SearchSheet.swift`、`Data/NostrRepository+Profiles.swift`

```swift
// performSearch 内で fromTargets の NIP-05 を解決
if !parsed.fromTargets.isEmpty {
    var resolvedAuthors: [String] = []
    for target in parsed.fromTargets {
        if target.hasPrefix("npub") {
            // bech32 → hex 変換
            if let hex = NostrKeyUtils.npubToHex(target) {
                resolvedAuthors.append(hex)
            }
        } else if target.count == 64 && target.allSatisfy({ $0.isHexDigit }) {
            resolvedAuthors.append(target)
        } else if target.contains("@") || target.contains(".") {
            // NIP-05 解決
            if let hex = await repository.resolveNip05(target) {
                resolvedAuthors.append(hex)
            }
        }
    }
    if !resolvedAuthors.isEmpty { authors = resolvedAuthors }
}
```

**NostrRepository+Profiles.swift に追加:**
```swift
func resolveNip05(_ identifier: String) async -> String? {
    // name@domain → GET https://domain/.well-known/nostr.json?name=name
    // → response.names[name] → pubkey hex
}
```

#### B. プロフィール検索結果
**ファイル:** `Views/Sheets/SearchSheet.swift`

```swift
// 検索結果にプロフィールセクション追加
@State private var profileResults: [UserProfile] = []
@State private var activeResultTab: Int = 0  // 0: 投稿, 1: ユーザー

// doSearch() 内で並列取得
async let postsTask = performSearch(...)
async let profilesTask = repository.searchProfiles(query: q)
let (events, foundProfiles) = await (postsTask, profilesTask)
profileResults = foundProfiles
```

#### C. トレンドタグ（オプション）
**ファイル:** `Views/Sheets/SearchSheet.swift`

```swift
// 検索前状態にトレンドセクション追加
if !hasSearched {
    trendingTagsSection  // NIP-50 経由 or relay 独自API
    operatorsHint
    recentSearchesSection
}
```

### 3-3. 工数・優先度

| タスク | 工数 | 優先度 |
|--------|------|--------|
| NIP-05 解決 | 中（1日） | 高 |
| プロフィール検索 | 中（1日） | 中 |
| 結果タブ切り替え | 小（0.5日） | 中 |
| トレンドタグ | 小（0.5日） | 低 |

---

## Phase 4 — 通知同期 (NotificationSheet ↔ NotificationModal) 🔴 最大ギャップ

### 4-1. 現状比較

| 機能 | Android | iOS 現状 | 差異 |
|------|---------|---------|------|
| 通知フェッチ | ✅ `fetchNotifications` | ✅ | 同等 |
| 通知種別アイコン | ✅ 8種 (reaction/emoji/zap/repost/reply/mention/badge/birthday) | 🔶 6種 (badge/birthday なし) | **要追加** |
| ライブポーリング (10秒) | ✅ `while(true) { delay(10_000) }` | ❌ | **要実装** |
| 新着Pill アニメーション | ✅ `AnimatedVisibility` + 「N件の新しい通知」 | ❌ | **要実装** |
| Pull-to-refresh | ✅ `PullToRefreshContainer` | ✅ `.refreshable` | 同等 |
| 元投稿プレビュー | ✅ `originalPosts` Map | ❌ | **要実装** |
| 通知Kind設定ダイアログ | ✅ `AlertDialog` + Switch per kind | ❌ | **要実装** |
| 設定ボタン（ヘッダー右） | ✅ `Icons.Outlined.Settings` | ❌ | **要実装** |
| アバターフォールバック | Android: Person icon + bgTertiary | iOS: 先頭文字 + bgSecondary | **要修正** |
| 通知キャッシュ | ✅ | 🔶 | 確認 |

### 4-2. 実装タスク

#### A. ライブポーリング + 新着Pill
**ファイル:** `Views/Sheets/NotificationSheet.swift`

```swift
@State private var pendingNew: [NotificationItem] = []
@State private var pollingTask: Task<Void, Never>?

// .task に追加
.task {
    await loadNotifications()
    
    // 10秒ポーリング（Android LaunchedEffect の while(true) 相当）
    pollingTask = Task {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard !Task.isCancelled else { break }
            let fresh = await repository.fetchNotifications(pubkey: myPubkeyHex, skipCache: true)
            let existingIds = Set(notifications.map(\.id) + pendingNew.map(\.id))
            let newItems = fresh.filter { !existingIds.contains($0.id) }
            if !newItems.isEmpty {
                await MainActor.run { pendingNew = newItems + pendingNew }
            }
        }
    }
}
.onDisappear { pollingTask?.cancel() }

// 新着Pill UI
if !pendingNew.isEmpty {
    Button {
        withAnimation { 
            notifications = pendingNew + notifications
            pendingNew = []
        }
    } label: {
        Text("\(pendingNew.count)件の新しい通知")
            .font(NuruFont.bodySmall())
            .fontWeight(.bold)
            .foregroundStyle(.white)
            .padding(.horizontal, NuruSpacing.space4)
            .padding(.vertical, NuruSpacing.space2)
            .background(Capsule().fill(NuruColors.lineGreen))
    }
    .transition(.move(edge: .top).combined(with: .opacity))
}
```

#### B. 元投稿プレビュー
**ファイル:** `Views/Sheets/NotificationSheet.swift`、`Data/NostrRepository+Notifications.swift`

```swift
// NotificationSheet に追加
@State private var originalPosts: [String: NostrEvent] = [:]

// loadNotifications() を拡張
private func loadNotifications() async {
    isLoading = true
    let result = await repository.fetchNotificationsWithContext(pubkey: myPubkeyHex)
    notifications = result.items
    originalPosts = result.originalPosts  // [eventId: NostrEvent]
    isLoading = false
    // ... profiles fetch
}

// notificationRow 内で元投稿表示
if let originalId = notif.referencedEventId,
   let original = originalPosts[originalId] {
    Text(original.content)
        .font(NuruFont.labelSmall())
        .foregroundStyle(theme.textTertiary)
        .lineLimit(2)
        .padding(.top, 4)
}
```

#### C. 通知Kind設定ダイアログ
**ファイル:** `Views/Sheets/NotificationSheet.swift`

```swift
@State private var showKindSettings = false
@State private var enabledKinds: Set<Int> = []  // AppPreferences から読み込み

// ヘッダー右に設定ボタン追加
Button { showKindSettings = true } label: {
    Image(systemName: "gearshape")
        .font(.system(size: 18))
        .foregroundStyle(theme.textSecondary)
        .frame(width: 40, height: 40)
}

// 設定シート
.sheet(isPresented: $showKindSettings) {
    NotificationKindSettingsSheet(
        enabledKinds: $enabledKinds,
        onSave: { prefs.notificationEnabledKinds = enabledKinds }
    )
}
```

Android 通知Kind設定の項目:
| 種類 | Kind | デフォルト |
|------|------|----------|
| リアクション (👍) | 7 | ON |
| 絵文字リアクション | 7 (custom) | ON |
| Zap | 9735 | ON |
| リポスト | 6 | ON |
| 返信・メンション | 1 | ON |
| バッジ | 30009 | ON |

#### D. アバターフォールバック修正
**ファイル:** `Views/Sheets/NotificationSheet.swift`

```swift
// 現状: 先頭文字 + bgSecondary → Android: Person icon + bgTertiary
private func avatarPlaceholder(profile: UserProfile?, size: CGFloat) -> some View {
    ZStack {
        Circle().fill(theme.bgTertiary)  // bgSecondary → bgTertiary
        Image(systemName: "person.fill")  // Text → Image
            .font(.system(size: size * 0.55))
            .foregroundStyle(theme.textTertiary)
    }
}
```

#### E. 通知種別追加
```swift
// badge + birthday style 追加
case "badge":   return .init(icon: "trophy.fill",  color: Color(hex: "#FFD700"), bg: Color(hex: "#FFD700").opacity(0.15))
case "birthday": return .init(icon: "birthday.cake.fill", color: Color(hex: "#AB47BC"), bg: Color(hex: "#AB47BC").opacity(0.15))
```

### 4-3. 工数・優先度

| タスク | 工数 | 優先度 |
|--------|------|--------|
| ライブポーリング + 新着Pill | 中（1日） | **最高** |
| 元投稿プレビュー | 中（1日） | 高 |
| Kind設定ダイアログ | 小（0.5日） | 高 |
| アバターフォールバック | 極小（15分） | 高 |
| 通知種別追加 | 極小（15分） | 中 |

---

## Phase 5 — リレー設定同期 (RelaySettingsView)

### 5-1. 現状比較

| 機能 | Android | iOS 現状 | 差異 |
|------|---------|---------|------|
| 地域選択 | ✅ | ✅ | 同等 |
| GPS自動検出 | ✅ | ✅ `LocationHelper` | 同等 |
| 最寄りリレー | ✅ | ✅ | 同等 |
| NIP-65 保存 | ✅ | ✅ | 同等 |
| read/write トグル | ✅ | ✅ | 同等 |
| 手動リレー追加 | ✅ | ✅ | 同等 |
| 接続状態リアルタイム | ✅ 色付きドット (green/yellow/gray/red) | 🔶 初回のみ | **定期更新要実装** |
| 自動再接続 後のUI更新 | ✅ | ❌ | **要実装** |
| NIP-65 読み込みボタン | ✅ | ✅ | 同等 |

### 5-2. 実装タスク

#### A. 接続状態リアルタイム更新
**ファイル:** `Views/MiniApps/RelaySettingsView.swift`

```swift
// 5秒間隔で接続状態を更新
.task {
    while !Task.isCancelled {
        relayStates = await repository.perRelayStates()
        try? await Task.sleep(nanoseconds: 5_000_000_000)
    }
}
```

### 5-3. 工数・優先度

| タスク | 工数 | 優先度 |
|--------|------|--------|
| 接続状態リアルタイム | 小（2h） | 中 |

---

## Phase 6 — キャッシュ同期 (CacheSettingsView ↔ CacheSettings)

### 6-1. 現状比較

| 機能 | Android | iOS 現状 | 差異 |
|------|---------|---------|------|
| 保持期間選択 | ✅ | ✅ (1/3/7/14/30日) | 同等 |
| キャッシュクリア | ✅ | ✅ | 同等 |
| キャッシュサイズ表示 | ✅ | ❌ | **要実装** |
| NostrCache 2層 | ✅ Memory LRU + SharedPrefs | 🔶 URLCache + UserDefaults | パターン異なるが機能同等 |
| 期限切れ自動清掃 | ✅ | ❌ | **要実装** |
| プロフィールキャッシュ | ✅ 専用キャッシュ | 🔶 NostrCache.swift | 確認 |
| 画像キャッシュクリア | ✅ | 🔶 URLCache のみ | Nuke キャッシュも対象に |

### 6-2. 実装タスク

#### A. キャッシュサイズ表示
**ファイル:** `Views/MiniApps/CacheSettingsView.swift`

```swift
@State private var cacheSize: String = "計算中..."

Section("キャッシュ情報") {
    HStack {
        Text("使用量")
            .font(NuruFont.bodyMedium())
            .foregroundStyle(theme.textPrimary)
        Spacer()
        Text(cacheSize)
            .font(NuruFont.bodyMedium())
            .foregroundStyle(theme.textSecondary)
    }
    .listRowBackground(theme.bgSecondary)
}
.task {
    cacheSize = await calculateCacheSize()
}

func calculateCacheSize() async -> String {
    let urlCacheSize = URLCache.shared.currentDiskUsage
    // + UserDefaults cache keys size estimation
    // + Nuke image cache size
    let totalBytes = urlCacheSize
    return ByteCountFormatter.string(fromByteCount: Int64(totalBytes), countStyle: .file)
}
```

#### B. 期限切れ自動清掃
**ファイル:** `Data/NostrCache.swift`

```swift
// NostrCache に追加
func cleanExpiredEntries() {
    let retentionDays = UserDefaults.standard.integer(forKey: "nurunuru_cache_retention_days")
        .nonZeroOrDefault(7)
    let cutoff = Date().addingTimeInterval(-Double(retentionDays * 86400))
    
    // Memory cache: timestamp が cutoff より古いエントリを削除
    profileCache = profileCache.filter { $0.value.timestamp > cutoff }
    eventCache = eventCache.filter { $0.value.timestamp > cutoff }
    
    // Disk cache: UserDefaults の該当キーも清掃
}

// アプリ起動時に実行
// NuruNuruApp.swift .task { cache.cleanExpiredEntries() }
```

#### C. Nuke キャッシュ対応
**ファイル:** `Views/MiniApps/CacheSettingsView.swift`

```swift
private func clearCache() {
    URLCache.shared.removeAllCachedResponses()
    
    // Nuke image cache
    // ImagePipeline.shared.cache.removeAll()
    
    let defaults = UserDefaults.standard
    for key in ["nurunuru_profile_cache", "nurunuru_event_cache"] {
        defaults.removeObject(forKey: key)
    }
    didClear = true
}
```

### 6-3. 工数・優先度

| タスク | 工数 | 優先度 |
|--------|------|--------|
| キャッシュサイズ表示 | 小（2h） | 中 |
| 期限切れ自動清掃 | 小（3h） | 中 |
| Nuke キャッシュ対応 | 極小（30分） | 低 |

---

## Phase 7 — 投稿モーダル同期 (PostSheet ↔ PostModal) 🔴 大きなギャップ

### 7-1. 現状比較

| 機能 | Android | iOS 現状 | 差異 |
|------|---------|---------|------|
| テキスト入力 (140文字) | ✅ `BasicTextField` | ✅ `TextEditor` | 同等 |
| 画像添付 (3枚) | ✅ | ✅ `PhotosPicker` | 同等 |
| 並列画像アップロード | ✅ `async { } + awaitAll` | ✅ `TaskGroup` | 同等 |
| CW (Content Warning) | ✅ | ✅ | 同等 |
| **リレー選択パネル** | ✅ `RelaySelectPanel` | ❌ | **🔴 要実装** |
| **NIP-70 保護タグ** | ✅ `nip70Protected` | ❌ | **🔴 要実装** |
| **カスタム絵文字挿入** | ✅ `EmojiPicker` + `:shortcode:` | ❌ | **🔴 要実装** |
| **ハッシュタグ色付け** | ✅ `AnnotatedString` LineGreen | ❌ | **要実装** |
| **STT (音声入力)** | ✅ `SpeechRecognizer` | ❌ | **要実装 (iOS: SFSpeechRecognizer)** |
| 返信モード | ✅ `replyToId` | ✅ `replyToId` | 同等 |
| プレースホルダー | ✅ "いまどうしてる？" | ✅ | 同等 |
| 文字数カウンター | ✅ 円形プログレス | ✅ 円形プログレス | 同等 |
| ヘッダーレイアウト | ✅ キャンセル(左) + タイトル(中) + 投稿(右) | 🔶 xmark(左) + 投稿(右) | **要修正** |

### 7-2. 実装タスク

#### A. リレー選択パネル + NIP-70 🔴
**ファイル:** `Views/Sheets/PostSheet.swift`

```swift
// State 追加
@State private var allRelays: [String] = []
@State private var selectedRelays: Set<String> = []
@State private var nip70Protected: Bool = false
@State private var showRelayPanel: Bool = false

// init/onAppear で
allRelays = repository.getSavedRelayUrls()
selectedRelays = Set(allRelays)

// ツールバーにリレーボタン追加
Button {
    withAnimation { showRelayPanel.toggle() }
} label: {
    HStack(spacing: 4) {
        Image(systemName: "antenna.radiowaves.left.and.right")
            .font(.system(size: NuruSpacing.iconMd))
        if selectedRelays.count != allRelays.count || nip70Protected {
            Circle().fill(NuruColors.lineGreen).frame(width: 6, height: 6)
        }
    }
    .foregroundStyle(
        (selectedRelays.count != allRelays.count || nip70Protected)
        ? NuruColors.lineGreen : theme.textTertiary
    )
}

// リレー選択パネル（折りたたみ）
if showRelayPanel {
    RelaySelectPanel(
        relays: allRelays,
        selectedRelays: $selectedRelays,
        nip70Protected: $nip70Protected
    )
    .transition(.move(edge: .bottom).combined(with: .opacity))
}
```

**RelaySelectPanel コンポーネント（新規）:**
**ファイル:** `Views/Components/RelaySelectPanel.swift`

```swift
struct RelaySelectPanel: View {
    let relays: [String]
    @Binding var selectedRelays: Set<String>
    @Binding var nip70Protected: Bool
    
    @Environment(\.nuruTheme) private var theme
    
    var body: some View {
        VStack(alignment: .leading, spacing: NuruSpacing.space2) {
            ForEach(relays, id: \.self) { url in
                HStack {
                    Image(systemName: selectedRelays.contains(url)
                          ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selectedRelays.contains(url)
                                         ? NuruColors.lineGreen : theme.textTertiary)
                    Text(url.replacingOccurrences(of: "wss://", with: ""))
                        .font(NuruFont.bodySmall())
                        .foregroundStyle(theme.textPrimary)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if selectedRelays.contains(url) {
                        selectedRelays.remove(url)
                    } else {
                        selectedRelays.insert(url)
                    }
                }
            }
            
            Divider().background(theme.borderColor)
            
            // NIP-70 toggle
            HStack {
                Image(systemName: nip70Protected ? "lock.fill" : "lock.open")
                    .foregroundStyle(nip70Protected ? NuruColors.lineGreen : theme.textTertiary)
                Text("リレーによる再配信を防止")
                    .font(NuruFont.bodySmall())
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                Toggle("", isOn: $nip70Protected)
                    .toggleStyle(SwitchToggleStyle(tint: NuruColors.lineGreen))
                    .labelsHidden()
            }
        }
        .padding(NuruSpacing.space3)
        .background(theme.bgSecondary)
    }
}
```

**handlePost() 修正:**
```swift
// targetRelays 計算
let targetRelayList: [String]? = selectedRelays.count != allRelays.count
    ? Array(selectedRelays) : nil

try await repository.publishNote(
    content:        content,
    replyToId:      replyToId,
    contentWarning: showCWInput && !contentWarning.isEmpty ? contentWarning : nil,
    targetRelays:   targetRelayList,
    nip70Protected: nip70Protected
)
```

#### B. カスタム絵文字挿入 🔴
**ファイル:** `Views/Sheets/PostSheet.swift`

```swift
@State private var showEmojiPicker: Bool = false
@State private var selectedCustomEmojis: [CustomEmoji] = []

// ツールバーに絵文字ボタン追加
Button { showEmojiPicker.toggle() } label: {
    Image(systemName: "face.smiling")
        .font(.system(size: NuruSpacing.iconMd))
        .foregroundStyle(theme.textTertiary)
}

// EmojiPickerSheet 表示
if showEmojiPicker {
    EmojiPickerSheet(
        pubkey: myPubkeyHex,
        repository: repository,
        individualOnly: true,
        onSelect: { emoji in
            let insert = ":\(emoji.shortcode):"
            if (text + insert).count <= UI.postMaxLength {
                text += insert
                if !selectedCustomEmojis.contains(where: { $0.shortcode == emoji.shortcode }) {
                    selectedCustomEmojis.append(emoji)
                }
            }
            showEmojiPicker = false
        },
        onDismiss: { showEmojiPicker = false }
    )
}

// handlePost() で emoji タグ追加
// selectedCustomEmojis.forEach { emoji in
//     tags.append(["emoji", emoji.shortcode, emoji.url])
// }
```

#### C. ハッシュタグ色付け
**ファイル:** `Views/Sheets/PostSheet.swift`

iOS の `TextEditor` は `AttributedString` を直接サポートしないため、オーバーレイ方式を採用:

```swift
// 方法1: テキストエディタの後ろに色付きテキストをオーバーレイ
// 方法2: iOS 17+ の場合、TextEditor + AttributedString

// 実用的なアプローチ: プレビューエリアで色付き表示
// （Android の BasicTextField は AnnotatedString を直接サポート）
// → iOS では入力中は通常テキスト、プレビューで色付き表示がベストプラクティス
```

#### D. STT (音声入力) — iOS版
**ファイル:** `Views/Sheets/PostSheet.swift`

```swift
import Speech

@State private var isSTTActive = false

// ツールバーにマイクボタン追加
Button {
    if isSTTActive { stopSTT() } else { startSTT() }
} label: {
    Image(systemName: isSTTActive ? "mic.fill" : "mic")
        .font(.system(size: NuruSpacing.iconMd))
        .foregroundStyle(isSTTActive ? NuruColors.lineGreen : theme.textTertiary)
}

private func startSTT() {
    SFSpeechRecognizer.requestAuthorization { status in
        guard status == .authorized else { return }
        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja-JP"))
        // AVAudioSession + SFSpeechAudioBufferRecognitionRequest
        // → result.bestTranscription.formattedString → text に追加
    }
}
```

#### E. ヘッダーレイアウト修正
**ファイル:** `Views/Sheets/PostSheet.swift`

```swift
// 現状: xmark(左) + Spacer + 投稿(右)
// Android: キャンセル(テキスト左) + タイトル(中央) + 投稿(ボタン右)

HStack {
    Button("キャンセル", action: onDismiss)  // xmark → テキスト
        .font(NuruFont.bodyMedium())
        .foregroundStyle(theme.textSecondary)
    
    Spacer()
    
    Text(replyToId != nil ? "返信" : "新規投稿")  // タイトル追加
        .font(NuruFont.titleMedium())
        .fontWeight(.bold)
        .foregroundStyle(theme.textPrimary)
    
    Spacer()
    
    Button("投稿") { Task { await handlePost() } }
        .font(NuruFont.buttonMedium())
        // ... 既存スタイル
}
```

### 7-3. 工数・優先度

| タスク | 工数 | 優先度 |
|--------|------|--------|
| リレー選択パネル + NIP-70 | 中（1.5日） | **最高** |
| カスタム絵文字挿入 | 中（1日） | 高 |
| ヘッダーレイアウト修正 | 極小（30分） | 高 |
| ハッシュタグ色付け | 小（0.5日） | 中 |
| STT 音声入力 | 中（1日） | 低 |

---

## 全体実装スケジュール

### Week 1: 最重要ギャップ解消

| 日 | タスク | Phase |
|----|--------|-------|
| Day 1 | 通知: ライブポーリング + 新着Pill | Phase 4-A |
| Day 2 | 通知: 元投稿プレビュー + Kind設定 | Phase 4-B/C |
| Day 3 | 投稿: リレー選択パネル + NIP-70 | Phase 7-A |
| Day 4 | 投稿: カスタム絵文字挿入 | Phase 7-B |
| Day 5 | 投稿: ヘッダー修正 + 検索: NIP-05解決 | Phase 7-E / 3-A |

### Week 2: 中優先度の同期

| 日 | タスク | Phase |
|----|--------|-------|
| Day 1 | プロフィール: npubコピー + ミュート | Phase 2-A/B |
| Day 2 | 検索: プロフィール検索 + 結果タブ | Phase 3-B/C |
| Day 3 | キャッシュ: サイズ表示 + 自動清掃 | Phase 6-A/B |
| Day 4 | 通知: アバター修正 + 種別追加 | Phase 4-D/E |
| Day 5 | リレー: 接続状態リアルタイム | Phase 5-A |

### Week 3: 低優先度 + 仕上げ

| 日 | タスク | Phase |
|----|--------|-------|
| Day 1 | ログイン: NIP-46 実装 | Phase 1-A |
| Day 2 | NIP-46 続き + テスト | Phase 1-A |
| Day 3 | 投稿: ハッシュタグ色付け + STT | Phase 7-C/D |
| Day 4 | ログイン: Deep Link | Phase 1-B |
| Day 5 | 総合テスト + 微調整 | 全体 |

---

## ファイル変更マップ

### 新規ファイル

| ファイル | 目的 |
|---------|------|
| `Data/ExternalSigner.swift` | NIP-46 Nostr Connect クライアント |
| `Views/Components/RelaySelectPanel.swift` | 投稿時リレー選択パネル |
| `Views/Sheets/NotificationKindSettingsSheet.swift` | 通知種類設定シート |

### 変更ファイル

| ファイル | 変更内容 |
|---------|---------|
| `Views/Screens/LoginView.swift` | NIP-46 UI、Deep Link |
| `Views/Sheets/PostSheet.swift` | リレー選択、NIP-70、カスタム絵文字、STT、ヘッダー |
| `Views/Sheets/SearchSheet.swift` | NIP-05解決、プロフィール検索、結果タブ |
| `Views/Sheets/NotificationSheet.swift` | ライブポーリング、新着Pill、Kind設定、元投稿、アバター |
| `Views/Sheets/UserProfileSheet.swift` | ミュートメニュー |
| `Views/Components/ProfileComponents.swift` | npubコピーボタン |
| `Views/MiniApps/CacheSettingsView.swift` | サイズ表示、Nuke対応 |
| `Views/MiniApps/RelaySettingsView.swift` | 接続状態リアルタイム |
| `Data/NostrRepository+Profiles.swift` | `resolveNip05()` |
| `Data/NostrRepository+Notifications.swift` | `fetchNotificationsWithContext()` |
| `Data/NostrRepository+Actions.swift` | `muteUser()` |
| `Data/NostrCache.swift` | 期限切れ自動清掃 |
| `NuruNuruApp.swift` | Deep Link ハンドラー |

---

## 同期完了後の期待同期率

| 機能領域 | 現在 | 完了後 |
|----------|------|--------|
| ログイン | 85% | 97% |
| プロフィール | 80% | 95% |
| 検索 | 75% | 95% |
| 通知 | 65% | **97%** |
| リレー | 90% | 97% |
| キャッシュ | 70% | 95% |
| 投稿モーダル | 70% | **97%** |
| **総合** | **~76%** | **~96%** |

---

## Android専用機能（iOS対象外）

| 機能 | 理由 |
|------|------|
| NIP-55 Amber外部署名 | Android専用（iOS は NIP-46 で��替） |
| ProofMode (PGP + Play Integrity) | Android専用ハードウェア |
| SpeechRecognizer (Android STT) | iOS は SFSpeechRecognizer で代替実装 |
| `BackHandler` | iOS は swipe-to-dismiss がネイティブ |
| ContentProvider 署名 | Amber 5.x 向け（iOS は NIP-46 WS ベース） |

---

## 補足: Android 調査で判明した追加同期ポイント

### A. 通知の NIP-65 read リレー優先（Android固有パターン）

Android `NostrRepositoryNotifications.kt` では通知フェッチ時に **NIP-65 read リレー** を優先使用する:
```kotlin
// Android: NIP-65 read relays → fallback to default client relays
val readRelays = prefs.nip65Relays.filter { it.read }.map { it.url }
if (readRelays.isNotEmpty()) { /* read relays で fetch */ }
```

**iOS 対応:** `NostrRepository+Notifications.swift` の `fetchNotifications()` で同様のロジックを追加:
```swift
let readRelays = prefs.nip65Relays
    .filter { $0.permission == .read || $0.permission == .readWrite }
    .map(\.url)
// readRelays が空でなければ、それらのリレーから優先的にフェッチ
```

### B. 通知キャッシュ（NotificationResult 一括キャッシュ）

Android は `NotificationResult` 全体（items + profiles + originalPosts）を一括キャッシュ:
```kotlin
data class NotificationResult(
    val items: List<NotificationItem>,
    val profiles: Map<String, UserProfile>,
    val originalPosts: Map<String, NostrEvent>
)
// cache.setCachedNotifications(result) / cache.getCachedNotifications()
```

**iOS 対応:** `NostrCache.swift` に `NotificationResult` キャッシュ層を追加。

### C. NIP-05 解決キャッシュ（5分TTL）

Android `Nip05Utils.kt` は解決結果を `ConcurrentHashMap` に5分間キャッシュ:
```kotlin
private val verifyCache = ConcurrentHashMap<String, Pair<Boolean, Long>>()  // 5min TTL
```

**iOS 対応:** `NostrRepository+Profiles.swift` の `resolveNip05()` にも同様のキャッシュを追加。

### D. 外部署名のフォールバック戦略

Android `ExternalSigner.kt` は **ContentProvider → Intent** の2段階フォールバック:
1. ContentProvider クエリ（Amber 5.x+, 同一プロセス内で高速）
2. Intent app switching（旧バージョン互換）

iOS の NIP-46 は WebSocket ベースのため、フォールバックは不要だが **接続タイムアウト + リトライ** を実装すべき。

### E. 画像アップロードサーバー選択のUI同期

Android `PostModal.kt` のツールバーには直接的なサーバー選択UIはないが、`AppPreferences.uploadServer` で設定。

iOS の `PostSheet.swift` でもアップロードサーバーは `repository.prefs.uploadServerEnum` を参照しているが、**PostSheet 内でのサーバー切替UI** は Android にも iOS にもないので同期不要。

### F. キャッシュ容量の差異

| キャッシュ種別 | Android 容量 | iOS 推奨容量 |
|--------------|-------------|-------------|
| Profile LRU | 500 entries | 256 entries（現状OK、メモリ制約考慮） |
| Timeline LRU | 1000 entries | 64 entries（要拡張検討） |
| Follow List TTL | 24h | 24h（同等） |
| Mute List TTL | 24h | 12h → **24h に変更** |
| Notification TTL | 24h | 未実装 → **24h で新規追加** |

### G. PostModal の `client` タグ

Android は投稿時に自動で `["client", "nullnull"]` タグを追加:
```kotlin
tags.add(listOf("client", "nullnull"))
```

**iOS 対応:** `NostrRepository+Actions.swift` の `publishNote()` で同様のタグを追加しているか確認。未実装なら追加。

---

## 参照ファイルマップ

### Android（参照元）

| 役割 | パス |
|------|------|
| ログイン画面 | `android/.../ui/screens/LoginScreen.kt` |
| 認証VM | `android/.../viewmodel/AuthViewModel.kt` |
| 投稿モーダル | `android/.../ui/components/PostModal.kt` |
| 検索モーダル | `android/.../ui/components/SearchModal.kt` |
| 通知モーダル | `android/.../ui/components/NotificationModal.kt` |
| 検索パーサー | `android/.../data/SearchQueryParser.kt` |
| キャッシュ | `android/.../data/cache/NostrCache.kt` |
| キャッシュ設定UI | `android/.../ui/miniapps/CacheSettings.kt` |
| 外部署名 | `android/.../data/ExternalSigner.kt` |
| 通知リポジトリ | `android/.../data/NostrRepositoryNotifications.kt` |

### iOS（変更対象）

| 役割 | パス |
|------|------|
| ログイン画面 | `ios/NuruNuru/Views/Screens/LoginView.swift` |
| 認証VM | `ios/NuruNuru/ViewModels/AuthViewModel.swift` |
| 投稿シート | `ios/NuruNuru/Views/Sheets/PostSheet.swift` |
| 検索シート | `ios/NuruNuru/Views/Sheets/SearchSheet.swift` |
| 通知シート | `ios/NuruNuru/Views/Sheets/NotificationSheet.swift` |
| 検索パーサー | `ios/NuruNuru/Utilities/SearchQueryParser.swift` |
| キャッシュ | `ios/NuruNuru/Data/NostrCache.swift` |
| キャッシュ設定UI | `ios/NuruNuru/Views/MiniApps/CacheSettingsView.swift` |
| リレー設定 | `ios/NuruNuru/Views/MiniApps/RelaySettingsView.swift` |
| プロフィール | `ios/NuruNuru/Views/Components/ProfileComponents.swift` |
| ユーザープロフィール | `ios/NuruNuru/Views/Sheets/UserProfileSheet.swift` |
