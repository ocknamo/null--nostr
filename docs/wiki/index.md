# null--nostr LLM Wiki Index

このディレクトリは **null--nostr の LLM Wiki** です。LLM がソースコード・設計文書・明示された意思決定を読み、プロジェクト知識を Markdown として継続的に整理します。

> **重要:** 真実の源泉はソースコード、design tokens、ビルド設定、公式設計文書です。Wiki はそれらから派生したナビゲーション層です。

## Core

| Page | Summary |
|---|---|
| [[overview]] | プロジェクトの目的、対象プラットフォーム、主要な設計原則。 |
| [[architecture]] | Web / Android / iOS / Rust Engine の横断アーキテクチャ。 |
| [[log]] | LLM Wiki の更新履歴。 |
| [[glossary]] | Nostr / Marmot / Blossom / platform parity 用語集。 |
| [[lint-report]] | Wiki の最新ヘルスチェック、修正済み stale claim、残ギャップ。 |

## Platforms

| Page | Summary |
|---|---|
| [[platforms/web]] | Next.js PWA、Web レイヤー、セキュリティ、接続管理。 |
| [[platforms/android]] | Kotlin / Jetpack Compose / Rust FFI を使う Android 実装。 |
| [[platforms/ios]] | SwiftUI / Observation / Keychain / pixel-perfect sync 方針。 |
| [[platforms/rust-engine]] | `nurunuru-core`、UniFFI、Android/iOS/Desktop 連携。 |
| [[platforms/parity-matrix]] | Web / Android / iOS / Rust の機能・protocol parity matrix。 |

## Features

| Page | Summary |
|---|---|
| [[features/timeline]] | フォロー / おすすめタイムライン、投稿表示、リアクション状態。 |
| [[features/post-composer]] | 投稿作成、140文字制限、画像アップロード、リレー指定、NIP-70。 |
| [[features/notifications]] | 通知一覧、Kind 6 / Kind 1 #p、ポーリング、表示仕様。 |
| [[features/search]] | Android の高度検索、NIP-50、検索演算子、クライアント側フィルタ。 |
| [[features/image-upload]] | 画像アップロード、NIP-98、Blossom/BUD-03、NIP-92 media handling。 |
| [[features/talk]] | Talk / messaging、Marmot MLS、legacy NIP-17 境界。 |
| [[features/talk-marmot-mls]] | Native Talk の Marmot MLS protocol details。 |
| [[features/talk-relays]] | Talk 用 KeyPackage / Welcome / message relay strategy。 |
| [[features/talk-debugging]] | Talk/Marmot debugging guidance and raw-log handling。 |
| [[features/talk-ios-android-parity]] | Android/iOS native Talk protocol parity checklist。 |
| [[features/relay-management]] | NIP-65 relay list、outbox model、target relay publish、接続制限。 |

## UI / Design

| Page | Summary |
|---|---|
| [[ui/android-ios-sync]] | Android と iOS の見た目・挙動を揃えるための重要制約。 |
| [[ui/design-tokens]] | `design-tokens/constants.json` と生成物の関係。 |
| [[ui/post-row]] | 投稿行、PostActions、media、embedded Nostr card、quote/reply rendering。 |

## NIPs

| Page | Summary |
|---|---|
| [[nips/README]] | コード確認に基づく対応 NIP 一覧と規約。 |
| [[nips/nip-04]] | Legacy encrypted DM compatibility paths。 |
| [[nips/nip-17]] | Private Direct Messages と native Talk の legacy 境界。 |
| [[nips/nip-18]] | Reposts and quote repost behavior。 |
| [[nips/nip-23]] | Long-form content / kind 30023。 |
| [[nips/nip-25]] | Reactions / custom reactions。 |
| [[nips/nip-30]] | Custom emoji lists and sets。 |
| [[nips/nip-44]] | Versioned encryption for DMs, NIP-46, signer helpers。 |
| [[nips/nip-51]] | Lists: mute, bookmarks, emoji list。 |
| [[nips/nip-58]] | Badges: awards, definitions, profile badges。 |
| [[nips/nip-59]] | Gift wrap: NIP-17 DMs and Marmot Welcome delivery。 |
| [[nips/nip-46]] | Nostr Connect / 外部署名。 |
| [[nips/nip-57]] | Lightning Zaps。 |
| [[nips/nip-65]] | Relay List Metadata / outbox model。 |
| [[nips/nip-70]] | Protected events / `[-]` tag。 |
| [[nips/nip-71]] | ろくなな short video / kind 34236。 |
| [[nips/nip-98]] | Upload HTTP auth / Blossom auth。 |

## Decisions

| Page | Summary |
|---|---|
| [[decisions/README]] | ADR 形式で設計判断を蓄積する場所。 |
| [[decisions/adr-0001-ios-observation]] | iOS ViewModel に iOS 17+ Observation を使う判断。 |
| [[decisions/adr-0002-native-talk-uses-marmot-mls]] | Native Talk は Marmot MLS 中心。 |
| [[decisions/adr-0003-ios-external-signing-uses-nip46]] | iOS external signing は NIP-46。 |
| [[decisions/adr-0004-design-tokens-are-source-of-truth]] | Design tokens を source of truth とする判断。 |
| [[decisions/adr-0005-postactions-no-reply-button]] | PostActions に reply button を置かない判断。 |
| [[decisions/adr-0006-web-rust-bridge-is-stub]] | Web Rust bridge は現状 stub。 |

## Maintenance checklist for agents

意味のある実装変更をしたら、以下を確認してください。

- 関連する Wiki ページを更新したか。
- 新規ページを追加した場合、この `index.md` に追記したか。
- `log.md` に `## [YYYY-MM-DD] type | title` 形式で追記したか。
- Wiki の主張に根拠ファイルを付けたか。
- 不明点や推測を `Open Questions` に分離したか。
## Source references

- `AGENTS.md`
- `docs/wiki/log.md`
- Source references listed in each linked wiki page.

