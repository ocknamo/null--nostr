# iOS ↔ Android UI 同期プラン

> 作成日: 2026-03-23
> 目的: iOS版をAndroid版と細部まで pixel-for-pixel に揃える
> 作業順序: ホームタブ → トークタブ → タイムラインタブ → ミニアプリタブ

---

## 現状の主な差異サマリー

| # | 分類 | 差異内容 | 影響度 |
|---|------|---------|--------|
| 1 | Like icon color | iOS: red / Android: lineGreen (#06C755) | 高 |
| 2 | Avatar fallback | iOS: first letter + bgSecondary / Android: Person icon + bgTertiary | 中 |
| 3 | タイムライン タブスタイル | iOS: underline式 / Android: pill（緑背景ボタン）式 | 高 |
| 4 | リレー選択ドロップダウン | iOS: 未実装 / Android: リレータブ内 ▼ ドロップダウン | 高 |
| 5 | 新着ドット | iOS: 未確認 / Android: 10dp lineGreen circle on tab corner | 中 |
| 6 | PostRow アバターサイズ | iOS: 40pt / Android: 42dp | 低 |
| 7 | PostActions 間隔 | iOS: HStack+Spacer / Android: spacing 32dp | 中 |
| 8 | ミニアプリ 4種未実装 | ElevenLabs, Scheduler, Nostr Browser, Vanish | 高 |

---

## Phase 1 — 共通コンポーネント修正（全タブに影響）

### 1-1. Like アイコン色統一

**正解: Android 仕様**
```kotlin
tint = if (post.isLiked) NuruColors.lineGreen else NuruColors.textTertiary
```

**iOS 修正対象:** `Views/Components/PostActions.swift`
```swift
// Before
.foregroundStyle(post.isLiked ? .red : theme.textTertiary)

// After
.foregroundStyle(post.isLiked ? NuruColors.lineGreen : theme.textTertiary)
```

アニメーション仕様（両プラットフォーム共通）:
- scale: 1.0 → 1.3 → 1.0
- duration: 200ms (spring, dampingFraction 0.4)
- アイコン: heart（未liked）→ heart.fill（liked）

---

### 1-2. Avatar フォールバック統一

**正解: Android 仕様**
```kotlin
// 背景: bgTertiary (#2C2C2E)
// アイコン: Icons.Default.Person, tint = textTertiary
// サイズ: avatarSize × 0.55
```

**iOS 修正対象:** `Views/Components/AvatarView.swift`
```swift
// Before: 先頭文字テキスト on bgSecondary
Circle().fill(theme.bgSecondary)
Text(String(name.prefix(1)).uppercased())

// After: Person icon on bgTertiary
Circle().fill(theme.bgTertiary)
Image(systemName: "person.fill")
    .font(.system(size: size * 0.55))
    .foregroundStyle(theme.textTertiary)
```

---

## Phase 2 — ホームタブ同期

### トップバー
| 要素 | 仕様 |
|------|------|
| タイトル | "ホーム" — titleLarge bold (20pt), LINE Seed JP |
| 右ボタン | ログアウト: person.crop.circle, 24pt, textSecondary |
| 高さ | 56pt (status bar除く) |
| 背景 | bgPrimary (#0A0A0A) |
| 下境界線 | Divider, borderColor (#38383A), 0.5pt |

### プロフィールヘッダー
```
┌──────────────────────────────────────────┐
│ padding top: space4 (16pt)               │
│                                          │
│   ┌──────────┐  displayName (bold 16pt)  │
│   │  avatar  │  followers count (14pt)   │
│   │  80×80pt │                           │
│   └──────────┘  [フォロー / 編集] button │
│                                          │
│ padding H: space4 (16pt)                 │
└──────────────────────────────────────────┘
```

| 要素 | 寸法・仕様 |
|------|-----------|
| avatar | 80×80pt, Circle |
| displayName | titleMedium bold (16pt) |
| followCount | "N フォロー" bodyMedium (14pt), textSecondary |
| フォロー/編集ボタン | height 36pt, radiusFull, lineGreen outline→filled |
| カード padding H | space4 (16pt) |
| カード padding V | space4 top, space3 bottom |

### タブバー（投稿 / いいね）
| 要素 | 仕様 |
|------|------|
| height | 40pt |
| active text color | textPrimary |
| inactive text color | textSecondary |
| active underline | 2pt height, lineGreen, width = tab width |
| font | bodyMedium (14pt) |
| animation | easeInOut, 150ms |
| 境界線 | Divider bottom, borderColor |

### 投稿リスト (PostRow)
→ Phase 4「PostRow 共通仕様」参照

---

## Phase 3 — トークタブ同期

### グループリスト画面

#### トップバー
| 要素 | 仕様 |
|------|------|
| タイトル | "トーク" — titleLarge bold (20pt) |
| 右ボタン | + circle: 32×32pt, lineGreen bg, white icon |
| DropdownMenu | "新しいトーク" / "グループ作成" |
| 背景・境界線 | bgPrimary, Divider |

#### フィルターチップ
```swift
// 横スクロール ScrollView
// chips: "すべて" / "友だち" / "グループ"
// active:   lineGreen bg, white text
// inactive: bgTertiary bg, textSecondary text
// height: 32pt, H padding: space3 (12pt), radius: radiusFull
// chip spacing: space2 (8pt)
// container: padding H space4, V space2
```

#### グループ行 (GroupRow)
```
┌─────────────────────────────────────────────┐
│ space4 │ avatar(48pt) │ space3 │            │
│        │              │        │ [name][time]│
│        │              │        │ lastMsg     │
│        │ [unread dot] │        │             │
│ total row height: 72pt                       │
└──────────────────────────────────────────────┘
```

| 要素 | 仕様 |
|------|------|
| avatar | 48×48pt |
| row height | 72pt |
| name font | bodyLarge bold (16pt) |
| time font | labelSmall (10pt), textTertiary |
| lastMsg font | bodyMedium (14pt), textSecondary |
| unread badge | lineGreen capsule, labelSmall white bold |
| divider | borderColor, left indent = space4+48+space3 |

---

### グループチャット画面

#### トップバー
| 要素 | 仕様 |
|------|------|
| 左 | chevron.left (back) |
| 中央 | group name, titleMedium bold, truncated |
| 右 | info.circle, 24pt |

#### メッセージバブル
```
自分（右寄せ）:
┌──────────────────────────────────┐
│                   ┌────────────┐ │
│                   │ 本文テキスト│ │  白 text on lineGreen bg
│                   └────────────┘ │  cornerRadius: radiusLg (12pt) all
│                   [時刻 labelSm] │
└──────────────────────────────────┘

相手（左寄せ）:
┌──────────────────────────────────┐
│ avatar  ┌────────────────────┐   │
│  32pt   │ 本文テキスト        │   │  textPrimary on bgSecondary
│         └────────────────────┘   │  左上: radiusSm (4pt), 他: radiusLg
│         [時刻 labelSm]           │
└──────────────────────────────────┘
```

| 要素 | 自分 | 相手 |
|------|------|------|
| 背景色 | lineGreen | bgSecondary (#1C1C1E) |
| テキスト色 | white | textPrimary |
| 角丸 | radiusLg (12pt) all | 左上 radiusSm (4pt), 他 radiusLg |
| padding H | space3 (12pt) | space3 |
| padding V | space2 (8pt) | space2 |
| max width | 75% of screen | 75% of screen |
| avatar | なし | 32×32pt, Circle |
| 名前ラベル | なし | labelSmall (10pt), textTertiary |
| 時刻 | labelSmall below right | labelSmall below left |

#### 入力エリア
```
┌─────────────────────────────────────────────┐
│ Divider (borderColor, 0.5pt)                │
│ padding V: space2 (8pt)                     │
│ [😊 24pt]  [TextField (min 40pt h)]  [▶ 40pt] │
│ padding H: space3 (12pt)                    │
└─────────────────────────────────────────────┘
```

| 要素 | 仕様 |
|------|------|
| TextField | bodyMedium, bgSecondary bg, radiusMd, min height 40pt |
| 送信ボタン | 40×40pt Circle, lineGreen bg, disabled if empty |
| 絵文字ボタン | face.smiling, 24pt, textSecondary |
| 背景 | bgPrimary |

---

## Phase 4 — タイムラインタブ同期

### トップバー（Pill スタイル）

**Android 実装の正確な仕様:**
```
┌──────────────────────────────────────────────────┐
│ padding H: 16dp, height: 56dp, bg: black         │
│                                                  │
│ ┌──────────────────────────────────────────┐    │
│ │ black bg, radius 20dp, padding 4dp       │    │
│ │ spacing 8dp                              │    │
│ │                                          │    │
│ │  ┌─────────────────┐  ┌──────────────┐  │    │
│ │  │  リレー  ▼ (●)  │  │   フォロー   │  │    │
│ │  │ green bg h:32dp │  │  transparent │  │    │
│ │  └─────────────────┘  └──────────────┘  │    │
│ └──────────────────────────────────────────┘    │
│                                 [🔍] [🔔(●)]   │
└──────────────────────────────────────────────────┘
```

**iOS 修正対象:** `Views/Screens/TimelineView.swift`

タブボタン仕様:
| 要素 | active (選択中) | inactive |
|------|----------------|----------|
| 背景 | lineGreen | transparent |
| テキスト色 | white | textTertiary |
| 高さ | 32pt | 32pt |
| cornerRadius | 16pt (radiusFull) | 16pt |
| font | 12pt bold | 12pt |
| padding H | 16pt (通常), 6pt end (ドロップダウンあり) | |

外側コンテナ:
| 要素 | 仕様 |
|------|------|
| 背景 | black |
| cornerRadius | 20pt |
| padding | 4pt |
| spacing | space2 (8pt) |

#### リレー選択ドロップダウン（iOS 未実装 → 要実装）
```swift
// リレータブの ▼ アイコン
// savedRelayUrls が空でない場合のみ表示
// タップで Menu/Sheet 展開
// 選択中リレーは "wss://" 除去・末尾スラッシュ除去・最初のパス前まで
// 例: wss://relay.nostr.band/ → "relay.nostr.band"
// 非選択時: "リレー"

// 新着ドット: 10pt circle, lineGreen bg, border 2pt bgSecondary
// offset: trailing top corner (+2pt, -2pt)
```

#### アクションボタン（右側）
| ボタン | アイコン | サイズ |
|--------|---------|--------|
| 検索 | magnifyingglass | 20pt, textSecondary |
| 通知 | bell | 20pt, textSecondary |
| 通知ドット | circle fill | 8pt, lineGreen, offset trailing-top |

---

### フィードリスト

#### ローディング状態
```swift
ProgressView()
    .tint(NuruColors.lineGreen)
    .frame(maxWidth: .infinity, minHeight: 200)
    .padding(.top, NuruSpacing.space8)
```

#### 空状態
```
Icon: antenna.radiowaves.left.and.right (リレー) / person.2 (フォロー)
  → 48pt, textTertiary
Text: "まだ投稿がありません"
  → bodyLarge, textSecondary, center
フォロー空状態追加:
Text: "プロフィールページでユーザーをフォローしましょう"
  → bodySmall, textTertiary, center
```

---

### PostRow 共通仕様（全タブ共通）

```
┌───────────────────────────────────────────────┐
│ padding H: space4 (16pt)                      │
│ padding top: space2 (8pt)                     │
│                                               │
│ ┌──────┐  ┌──────────────────────────────┐   │
│ │avatar│  │ [name bold] · [time label]   │   │
│ │ 42pt │  ├──────────────────────────────┤   │
│ └──────┘  │ content (bodyMedium 14pt)    │   │
│  space2   │ [もっと見る] if >140 chars  │   │
│  (10pt)   │ [閉じる] if expanded        │   │
│           │                              │   │
│           │ [OGP card if link]           │   │
│           └──────────────────────────────┘   │
│                                               │
│ PostActions (see below)                       │
│ padding bottom: space3 (12pt)                 │
│ Divider (0.5pt, borderColor, full width)      │
└───────────────────────────────────────────────┘
```

**PostActions レイアウト:**
```
HStack (Arrangement.spacedBy(32dp)):
  [like]    [repost]    [zap]    Spacer()    [via client text]
```

| ボタン | アイコン | active色 | inactive色 | アイコンサイズ |
|--------|---------|----------|-----------|------------|
| repost | arrow.2.squarepath | lineGreen | textTertiary | 20pt |
| like | hand.thumbsup.fill / hand.thumbsup | lineGreen | textTertiary | 20pt |
| zap | bolt.fill | colorZap (#FFB74D) | textTertiary | 20pt |
| via client | — | textTertiary @60% | — | 10pt text |

- **reply ボタンなし**（Android PostActions に存在しない）
- **間隔**: `Arrangement.spacedBy(32dp)` ≠ equal Spacers
- **via client**: 末尾 "via $clientName" (10sp, TextTertiary @ 60% alpha)
- count ラベル: bodySmall (12pt), アイコン右に 4pt
- **like アイコン**: thumbs up（heart ではない）— Android NuruIcons 準拠

**もっと見る / 閉じる:**
```swift
// Android: "もっと見る" / "閉じる" (12sp Bold LineGreen, 4dp vertical padding)
Button(isExpanded ? "閉じる" : "もっと見る") { isExpanded.toggle() }
    .font(.system(size: 12, weight: .bold))
    .foregroundStyle(NuruColors.lineGreen)
    .padding(.vertical, 4)
// 折りたたみ条件: textLengthWithoutLinks(content) > 140
// ※ iOS の "続きを読む" は Android 仕様と異なるため要変更
```

---

## Phase 5 — ミニアプリタブ同期

### SettingsView レイアウト

#### トップ: プロフィールヘッダー
```
┌──────────────────────────────────────────────┐
│ padding H: space4, V: space3                 │
│                                              │
│ ┌──────────┐  name (bold 14pt)               │
│ │ avatar   │  npub…xxxx (10pt, textTertiary) │
│ │ 40×40pt  │                    [ログアウト] │
│ └──────────┘                                 │
│ Divider                                      │
└──────────────────────────────────────────────┘
```

#### 検索バー
```swift
HStack(spacing: NuruSpacing.space2) {
    Image(systemName: "magnifyingglass")
        .foregroundStyle(theme.textTertiary)
        .font(.system(size: 16))
    TextField("ミニアプリを検索", text: $searchText)
        .font(NuruFont.bodyMedium())
        .foregroundStyle(theme.textPrimary)
}
.padding(NuruSpacing.space3)
.background(theme.bgSecondary)
.clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusMd))
.padding(.horizontal, NuruSpacing.space4)
.padding(.vertical, NuruSpacing.space2)
```

#### カテゴリータブ（underline スタイル）
```swift
// Android 仕様: underline インジケーター（pill/chip スタイルではない）
// "すべて" / "エンタメ" / "ツール"
// ScrollView(.horizontal, showsIndicators: false)
// Row: padding H space4 (16pt), spacing space4 (16pt)
// active text:   textPrimary (14pt)
// inactive text: textTertiary (14pt)
// active underline: 32pt wide, 2pt high, lineGreen
// inactive: underline なし
// ※ pill/capsule スタイルは TalkScreen のフィルターのみ
```

#### MiniAppCell
```
┌──────────────────────────┐
│ padding: space3 (12pt)   │
│ ┌──────────────────────┐ │
│ │   icon (28pt)        │ │  bgTertiary bg, radiusLg (12pt), 48×48pt
│ └──────────────────────┘ │
│ name (bodySmall bold 12pt│
│ desc (labelSmall 10pt    │
│       textTertiary)      │
│ bg: bgSecondary, radiusMd│
└──────────────────────────┘
```

**グリッド:** `LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: space4)`

#### ミニアプリ一覧（Android 完全同期）
| ID | 名前 | カテゴリー | iOS状態 |
|----|------|-----------|--------|
| emoji | カスタム絵文字 | エンタメ | 実装済 |
| badge | プロフィールバッジ | ツール | 実装済 |
| zap | Zap設定 | ツール | 実装済 |
| relay | リレー設定 | ツール | 実装済 |
| mute | ミュートリスト | ツール | 実装済 |
| backup | バックアップ | ツール | 実装済 |
| cache | キャッシュ設定 | ツール | 実装済 |
| elevenlabs | 音声テキスト変換 | ツール | **未実装** |
| scheduler | 投稿スケジューラー | ツール | **未実装** |
| browser | Nostrブラウザ | エンタメ | **未実装** |
| vanish | 削除リクエスト | ツール | **未実装** |

---

## 共通仕様

### FAB (Floating Action Button)
```swift
Button(action: onTap) {
    Image(systemName: "plus")
        .font(.system(size: 24, weight: .medium))
        .foregroundStyle(.white)
}
.frame(width: 56, height: 56)
.background(NuruColors.lineGreen)
.clipShape(Circle())
.shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
.padding(.trailing, NuruSpacing.space4)
.padding(.bottom, NuruSpacing.space4)
```

### Bottom Navigation Bar
| 要素 | 仕様 |
|------|------|
| 高さ | 56pt + safe area |
| 背景 | black |
| 上境界線 | borderColor, 0.5pt |
| active tint | lineGreen (filled icon) |
| inactive tint | textTertiary (outline icon) |
| label | labelSmall (10pt) |

| Tab | filled icon | outline icon | ラベル |
|-----|-------------|--------------|--------|
| home | house.fill | house | ホーム |
| talk | message.fill | message | トーク |
| timeline | newspaper.fill | newspaper | タイムライン |
| miniapp | square.grid.2x2.fill | square.grid.2x2 | ミニアプリ |

### シート共通ヘッダー
```swift
// drag indicator: 4×4pt capsule, bgTertiary, top center
// title: titleMedium (16pt bold), center
// 閉じるボタン: xmark.circle.fill, 24pt, textTertiary, trailing
// header height: 52pt
// 下境界線: Divider
```

### PostSheet（投稿作成）
| 要素 | 仕様 |
|------|------|
| 文字数カウンター | "残り N 文字" or "N / 140" |
| N ≤ 120 | textTertiary |
| 121 ≤ N ≤ 139 | colorWarning (#FFCC80) |
| N = 140 | textPrimary |
| N > 140 | colorError (#EF9A9A) |
| 送信ボタン | disabled if empty or N > 140 |

---

## 作業チェックリスト

> 最終確認日: 2026-03-24

### Phase 1: 共通コンポーネント
- [x] `PostActions.swift` — Like色 lineGreen 実装済 (`NuruColors.lineGreen`)
- [x] `PostActions.swift` — reply ボタン削除済（Android PostActions に存在しない）
- [x] `AvatarView.swift` — fallback: person.fill + bgTertiary 実装済
- [x] `MainTabView.swift` — タブアイコン修正済（house/message/newspaper/square.grid.2x2）
- [x] `MainTabView.swift` — safeAreaInset(edge: .bottom) で iPhone safe area 対応済
- [x] `PostActions.swift` — ボタン間隔: `HStack(spacing: 32)` + `Spacer()` + via client 実装済
- [x] `PostActions.swift` — via client タグ表示（10pt, textTertiary @60%）実装済
- [x] `PostActions.swift` — like アイコン: `NuruIcons.like(filled:)` = hand.thumbsup (元々正しい)
- [x] `PostRow.swift` — "続きを読む" → "もっと見る" / "閉じる" (12pt bold, 4pt padding)
- [x] `PostRow.swift` — アバター: 42pt (Android 42dp)
- [x] `BadgeDisplay.swift` — `ProfileHeader(repository:)` 経由で自動フェッチ接続済

### Phase 2: ホームタブ
- [x] `HomeView.swift` — トップバー高さ 56pt・titleLarge フォント確認済
- [x] `HomeView.swift` — ログアウト: icon → TextButton "ログアウト" (14pt, textSecondary)
- [x] `HomeView.swift` — Empty state: 64pt 円形 bgSecondary コンテナ + textSecondary テキスト
- [x] `ProfileComponents.swift` ProfileTabs — height 40pt, active text: textPrimary, inactive: textSecondary, underline animation easeInOut 150ms
- [x] `ProfileHeader.swift` — BadgeDisplay 自動フェッチ接続済（`repository` 引数経由）
- [x] `ProfileHeader.swift` — アバターサイズ: 72pt → 80pt (NuruSpacing.avatarXl)
- [x] `HomeView.swift` — New Posts Pill: HomeViewModel に pending 概念なし・対象外（Android HomeScreen も同様）

### Phase 3: トークタブ
- [x] `TalkView.swift` — グループ行 minHeight: 72pt 確認済
- [x] `TalkView.swift` — フィルターチップ styling 統一済（lineGreen/bgTertiary, height 32pt, radius 20pt）
- [x] `TalkView.swift` — バブル cornerRadius: 左上 radiusSm(4pt) 実装済
- [x] `TalkView.swift` — 入力エリア高さ・spacing 統一済
- [x] `TalkView.swift` — auto-scroll to bottom on new message 実装済
- [x] `TalkView.swift` — 絵文字ボタン: `photo` → `face.smiling` (NuruIcons.emoji)、常時表示

### Phase 4: タイムラインタブ
- [x] `TimelineView.swift` — pill スタイル（lineGreen bg, black container, 4pt padding）実装済
- [x] `TimelineView.swift` — リレー選択ドロップダウン実装済
- [x] `TimelineView.swift` — 新着ドット実装済（10pt, lineGreen, 2pt bgSecondary border）
- [x] `TimelineView.swift` — 検索・通知ボタン確認済
- [x] `TimelineView.swift` — New Posts Pill: `hasNewRelayPosts`/`hasNewFollowingPosts` フラグ + fade+slide animation

### Phase 5: ミニアプリタブ
- [x] `SettingsView.swift` — MiniAppCell 仕様統一済（48×48pt icon, bgTertiary/bgSecondary）
- [x] `SettingsView.swift` — 検索バー styling 統一済
- [x] 全ミニアプリ実装済
- [x] `SettingsView.swift` — カテゴリータブ: pill/chip → underline スタイル（40pt height, 32pt indicator）
- [x] `SettingsView.swift` — プロフィールカード: bgSecondary bg, radiusXl(16pt), space4(16pt) padding、ログアウト: colorError テキストボタン

### 優先度別残課題

#### 高優先度（視覚的に目立つ差異）
1. `PostActions.swift` — like アイコン: heart → hand.thumbsup
2. `PostRow.swift` — "続きを読む" → "もっと見る" / "閉じる"
3. `SettingsView.swift` — カテゴリータブ underline スタイル化
4. `ProfileHeader.swift` — アバター 72→80pt

#### 中優先度（詳細差異）
5. `PostActions.swift` — ボタン間隔 spacedBy(32pt) 相当
6. `PostActions.swift` — via client タグ表示
7. `TalkView.swift` — 絵文字ボタン face.smiling
8. `ProfileHeader.swift` — BadgeDisplay 接続

#### 低優先度（機能差異）
9. New Posts Pill（両タブ）
10. `PostRow.swift` — アバター 40→42pt

---

## 参照ファイルマップ

### iOS（修正対象）
| 役割 | パス |
|------|------|
| ボトムナビ | `ios/NuruNuru/Views/Screens/MainTabView.swift` |
| ホーム | `ios/NuruNuru/Views/Screens/HomeView.swift` |
| タイムライン | `ios/NuruNuru/Views/Screens/TimelineView.swift` |
| トーク | `ios/NuruNuru/Views/Screens/TalkView.swift` |
| ミニアプリ | `ios/NuruNuru/Views/Screens/SettingsView.swift` |
| 投稿行 | `ios/NuruNuru/Views/Components/PostRow.swift` |
| アクション | `ios/NuruNuru/Views/Components/PostActions.swift` |
| アバター | `ios/NuruNuru/Views/Components/AvatarView.swift` |
| 投稿作成 | `ios/NuruNuru/Views/Sheets/PostSheet.swift` |
| カラー | `ios/NuruNuru/Theme/NuruColors.swift` |
| フォント | `ios/NuruNuru/Theme/NuruTypography.swift` |
| スペーシング | `ios/NuruNuru/Theme/NuruSpacing.swift` |

### Android（参照元）
| 役割 | パス |
|------|------|
| ボトムナビ | `android/.../ui/screens/MainScreen.kt` |
| ホーム | `android/.../ui/screens/HomeScreen.kt` |
| タイムライン | `android/.../ui/screens/TimelineScreen.kt` |
| トーク | `android/.../ui/screens/TalkScreen.kt` |
| ミニアプリ | `android/.../ui/screens/SettingsScreen.kt` |
| タイムラインヘッダー | `android/.../ui/components/TimelineComponents.kt` |
| 投稿行 | `android/.../ui/components/PostItem.kt` |
| アクション | `android/.../ui/components/PostActions.kt` |
| アバター | `android/.../ui/components/UserAvatar.kt` |
| デザイントークン | `android/.../ui/theme/NuruTokens.kt` |

### 共有
| 役割 | パス |
|------|------|
| デザイントークン原典 | `design-tokens/constants.json` |
| iOS 設計書 | `ios/DESIGN.md` |
| iOS ガードレール | `ios/GUARDRAILS.md` |
