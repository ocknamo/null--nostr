# NIPs

## Summary

null--nostr は複数の Nostr Implementation Possibilities を扱います。このディレクトリは NIP ごとの実装状況、関連ファイル、platform 差分、注意点を蓄積する場所です。

> Source of truth: 実際の対応状況はソースコードが正です。この一覧は 2026-05-21 時点でコード参照に基づき更新しています。`Level` は「完全対応」ではなく、現在の実装範囲を短く示します。

## Official numbered NIPs

| NIP | Level | Status in this repo | Main evidence |
|---|---|---|---|
| NIP-01 | Core | Core event model, kind 0/1 publish/fetch, relay REQ/EVENT/OK handling. | `lib/nostr.js`, `NostrClient.kt`, `NostrClient.swift`, `rust-engine/.../engine.rs` |
| NIP-02 | Active | Contact lists kind 3: fetch/follow/unfollow by republishing full list. | `NostrRepositoryActions.kt`, `NostrRepository+Actions.swift`, `lib/nostr.js`, `filters.rs` |
| NIP-04 | Compatibility/helper | Legacy encryption helpers and signer/browser APIs. | `InternalSigner.kt`, `ExternalSigner.kt`, `NostrBrowserApp.kt`, `rust-engine/nurunuru-ffi/src/lib.rs`, `lib/nostr.js` |
| NIP-05 | Active | Identifier verify/resolve and profile/search support. | `Nip05Utils.kt`, `NostrRepository+Profiles.swift`, `lib/nostr.js`, `lib/validation.js` |
| NIP-07 | Web/browser active | Web extension signing and native mini-app browser `window.nostr` bridges. | `lib/nostr.js`, `NostrBrowserApp.kt`, `NostrBrowserView.swift` |
| NIP-09 | Active | Deletion kind 5; unlike/unrepost via delete. | `NostrRepositoryActions.kt`, `NostrRepository+Actions.swift`, `lib/nostr.js`, `engine.rs` |
| NIP-10 | Active | Reply markers/tags and reply display heuristics. | `PostModal.kt`, `PostSheet.swift`, `PostContent.swift`, `PostDetailScreen.kt` |
| NIP-11 | Web helper | Relay information document helpers on Web. | `lib/nostr.js` |
| NIP-17 | Legacy/native boundary + Web helpers | Web supports NIP-17 helpers; native Talk is Marmot MLS-oriented and treats NIP-17 as legacy/compatibility. | [[nip-17]] |
| NIP-18 | Active | Repost kind 6 and quote repost via kind 1 + `q` tag / `nostr:note1`. | `PostActions.kt`, `QuoteRepostModal.kt`, `QuoteRepostSheet.swift`, `NostrRepository+Actions.swift` |
| NIP-19 | Active | Bech32 `npub`/`note`/`nevent`/`nprofile`/`naddr` parsing/rendering. | `NostrKeyUtils.kt`, `PostContent.kt`, `PostContent.swift`, `lib/nostr.js` |
| NIP-23 | Active/native rendering | Long-form articles kind 30023 are fetched/rendered. | `LongFormPostItem.swift`, `NostrKind.*LONG_FORM`, `NostrRepositoryTimeline.kt` |
| NIP-25 | Active | Reactions kind 7 including custom emoji reactions. | [[nip-25]] |
| NIP-27 | Active | Text notes render and create `nostr:` mentions for profiles/events. | `PostContent.kt`, `PostSheet.swift`, `lib/nostr.js` |
| NIP-30 | Active/native strong | Custom emoji lists/sets kind 10030/30030 and emoji picker/cache. | [[nip-30]] |
| NIP-32 | Active/helper | Labeling/Birdwatch kind 1985. | `NostrRepositoryActions.kt`, `lib/nostr.js` |
| NIP-42 | Web helper | Relay auth kind 22242 on Web. | `lib/nostr.js` |
| NIP-44 | Active/helper | Encryption for NIP-17/NIP-46/private mute lists; signer APIs. | `InternalSigner.kt`, `ExternalSigner.kt`, `InternalSigner.swift`, `ExternalSigner.swift`, `lib/nip46.js` |
| NIP-46 | Active on iOS/Web | Nostr Connect on Web and iOS; iOS external signing uses NIP-46 rather than NIP-55. | [[nip-46]] |
| NIP-50 | Active | Search filters and searchnos routing. | `SearchQueryParser.kt`, `NostrRepositoryTimeline.kt`, `NostrRepository+Profiles.swift`, `lib/nostr.js` |
| NIP-51 | Active | Lists: mute list kind 10000, bookmarks kind 10003, emoji list kind 10030. | [[nip-51]] |
| NIP-55 | Android active | Android Amber external signer. Not used on iOS. | `ExternalSigner.kt`, `LoginScreen.kt`, `MainActivity.kt`, `lib/nostr.js` |
| NIP-56 | Active/helper | Reporting kind 1984. | `NostrRepositoryActions.kt`, `lib/nostr.js` |
| NIP-57 | Active | Zap request/receipt, LNURL invoice generation, zap totals. | [[nip-57]] |
| NIP-58 | Active/native | Badges kind 8/30008/30009. | [[nip-58]] |
| NIP-59 | Active/transport | Gift wraps kind 1059 for Web NIP-17 and Marmot MLS Welcome delivery. | [[nip-59]] |
| NIP-62 | Active/helper | Request to Vanish kind 62. | `VanishRequest.kt`, `VanishRequestView.swift`, `NostrRepository+Actions.swift`, `lib/nostr.js` |
| NIP-65 | Active | Relay List Metadata kind 10002 / outbox model. | [[nip-65]] |
| NIP-70 | Active | Protected events `['-']` tag in composer and import/export handling. | [[nip-70]] |
| NIP-71 | Active/native feature | Short video / `ろくなな` kind 34236 and related video discovery. | [[nip-71]] |
| NIP-92 | Read/render | `imeta` URL extraction/rendering for media. | `NostrEvent.swift`, `PostContent.swift`, `NostrRepository+Rokunana.swift` |
| NIP-96 | Upload helper | Upload endpoints for nostr.build/share.yabu.me style multipart uploads. | `ImageUploadService.swift`, `NostrRepository+Backup.swift`, `ImageUploadUtils.kt`, `lib/nostr.js` |
| NIP-98 | Active/upload auth | HTTP auth kind 27235 for uploads; Blossom uses kind 24242 auth in code. | [[nip-98]] |

## Lettered / draft / ecosystem NIPs

| Spec | Level | Status | Main evidence |
|---|---|---|---|
| NIP-A5 | Mini-app feature | Scroll mini-app definitions/favorites kind 1227/10027. | `ScrollRunner.kt`, `ScrollsApp.kt`, `NostrRepositoryScrolls.kt`, `ScrollsView.swift` |
| NIP-B7 | Blossom-related | Blossom blob upload/fallback handling. | `ImageUploadService.swift`, `AvatarView.swift`, `ImageUploadUtils.kt` |
| Nosskey (draft NIP) | Active across 3 platforms | Passkey-derived Nostr keys via WebAuthn PRF extension. New-user onboarding default on Web; opt-in primary button on iOS 18+ / Android API 28+. | [[nosskey]] |

## Blossom / BUD specs

| Spec | Level | Status | Main evidence |
|---|---|---|---|
| BUD-03 | iOS/settings + upload ecosystem | Blossom user server list kind 10063 and fallback server discovery. | `ImageUploadService.swift`, `AvatarView.swift`, `SettingsView.swift` |

## Project-specific / non-NIP protocol support

| Protocol | Level | Status | Main evidence |
|---|---|---|---|
| Marmot MLS / NIP-EE family | Native Talk core | Native Talk uses MLS groups/messages with key packages, welcomes, and group messages. NIP-17 models remain legacy/deprecated. | `NostrRepositoryTalk.kt`, `NostrRepository+Talk.swift`, `rust-engine/nurunuru-core/src/mls.rs` |
| NIP-ProofMode | Android feature | Android video proof mode manager exists. | `ProofModeManager.kt` |

## Detailed NIP pages

- [[nip-17]] — Private Direct Messages / native Talk legacy boundary.
- [[nip-18]] — reposts and quote repost behavior.
- [[nip-23]] — long-form content.
- [[nip-25]] — reactions and custom reactions.
- [[nip-30]] — custom emoji lists and sets.
- [[nip-44]] — versioned encryption.
- [[nip-46]] — Nostr Connect / external signing.
- [[nip-50]] — search capability / searchnos / feedback-loop MCP.
- [[nip-51]] — lists: mute, bookmarks, emoji list.
- [[nip-57]] — Lightning Zaps.
- [[nip-58]] — badges.
- [[nip-59]] — gift wrap.
- [[nip-65]] — Relay List Metadata / outbox model.
- [[nosskey]] — Passkey-derived Nostr keys (PRF Direct Method, draft NIP).
- [[nip-70]] — protected events.
- [[nip-71]] — short video / ろくなな.
- [[nip-98]] — HTTP upload auth and Blossom auth.

## Recommended future pages

- `nip-04.md` / `nip-44.md` — encryption helpers and signer APIs.
- `nip-18.md` — repost and quote repost behavior.
- `nip-23.md` — long-form articles.

## Open questions

- Some constants in `NostrKind` are declared for completeness but may not have full UI flows. Treat this table as code-backed by explicit implementation references, not merely by constants.
- Web has broader utility functions than native in some areas; platform parity should be checked per feature before claiming full support.

## Source references

- `android/app/src/main/kotlin/io/nurunuru/app/data/models/NostrModels.kt`
- `ios/NuruNuru/Models/NostrKind.swift`
- `lib/nostr.js`
- `lib/nip46.js`
- `rust-engine/nurunuru-core/src/filters.rs`
- `rust-engine/nurunuru-core/src/engine.rs`
- `rust-engine/nurunuru-ffi/src/lib.rs`

## Related pages

- [[../platforms/parity-matrix]]
- [[../glossary]]
- [[../features/post-composer]]
- [[../features/search]]
- [[../features/image-upload]]
- [[../features/talk]]
- [[../features/relay-management]]
