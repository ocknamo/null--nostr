# null--nostr LLM Wiki Log

LLM Wiki の時系列ログです。追記専用として扱います。

## [2026-05-23] sec | Dependabot 9 件 (high 2 / moderate 2 / low 5) 解消

- GHSA-hc3c-63hc-2r9f **high** `libcrux-chacha20poly1305 0.0.7 → 0.0.8` — Overlong ciphertext buffer での panic を修正。`libcrux-aead` も 0.0.7→0.0.8 へ追従。
- GHSA-82j2-j2ch-gfr8 **high** `rustls-webpki 0.103.9 → 0.103.13` — Malformed CRL BIT STRING による panic / DoS を修正。同時に GHSA-pwjx-qhcg-rvj4 (moderate, CRL distribution-point matching) と GHSA-965h-392x-2mh5 / GHSA-xgp8-3hg3-c2mh (low, URI / wildcard name constraints) も同バージョンで解消。
- GHSA-qx2v-qp2m-jg93 **moderate** `postcss 8.4.38 → 8.5.15` (>=8.5.10) — `</style>` の unescape による XSS を修正。`next` 内部の transitive な 8.4.31 を抑止するため `overrides` を併用。
- GHSA-cq8v-f236-94qc **low** `rand 0.8.5 → 0.8.6`, `0.9.2 → 0.9.3`, `0.10.0 → 0.10.1` — カスタムロガー + `rand::rng()` での unsoundness を修正。
- 直接 `cargo update --precise 0.0.8` は `hpke-rs-libcrux 0.6.1` の `libcrux-aead = "0.0.7"` ピンに阻まれるため、`rust-engine/Cargo.toml` に `[patch.crates-io]` セクションを追加し `cryspen/hpke-rs` の `franziskus/bump-libcrux` PR (#154, rev 110d7477) を一時的に取り込んだ。upstream が 0.6.2 をリリースしたら patch を撤去予定。
- 検証: `cargo check --workspace` 通過 / `cargo test -p nurunuru-core --no-run` 通過 / `npm run test` 189 passed / `npm audit` 0 vulnerabilities / `npm run tokens:check` in sync。
- 変更ファイル: `package.json`, `package-lock.json`, `rust-engine/Cargo.toml`, `rust-engine/Cargo.lock`。Rust ソースコード (`lib.rs` 等) は無変更のため Android `.so` の再ビルドは次回リリース時で十分。

## [2026-05-23] perf | Send-button spinner reflects only the MLS send call (not pre-flight)

- `TalkViewModel.sendMessage` on both iOS and Android no longer sets `sendingMessage = true` at the top of the function. The flag is now set immediately before the `repository.sendMlsMessage(...)` call so the spinner covers only the actual MLS network round-trip.
- Previously the spinner stayed visible for up to ~110s (Android) or ~77s (iOS) because the pre-flight chain (DM canonicalize → catch-up 15s → repair 30s → deep-catch-up 35s) ran while `sendingMessage` was true. User reported the spinner staying on for "about 1 minute" after tapping send.
- The optimistic bubble + cleared composer remain the affordance for "message accepted". The spinner is now only the affordance for "network send in flight". `abortOptimisticSend(...)` still defensively clears the flag on every early-return path.
- Source: `android/app/src/main/kotlin/io/nurunuru/app/viewmodel/TalkViewModel.kt`, `ios/NuruNuru/ViewModels/TalkViewModel.swift`, `docs/wiki/ui/android-ios-sync.md`.

## [2026-05-23] perf | Instant send + drop sender-name label in Talk chat

- Removed the sender display-name `Text` rendered above incoming bubbles on both platforms (`TalkView.swift` `MessageBubble`, `TalkComponents.kt` `MlsMessageBubble`). The avatar already carries identity; duplicating the name on every consecutive incoming message broke the LINE silhouette.
- Moved the optimistic-bubble insertion to the very top of `sendMessage` on both platforms (`TalkViewModel.swift` and `TalkViewModel.kt`). Previously the optimistic `MlsMessage` was appended **after** DM canonicalization, `fetchMlsMessages(repairFull = false/true)` catch-up, and gap-repair with `withTimeout(15_000)` + `withTimeout(30_000)`, so the user could wait up to 45 s between tapping send and seeing their own bubble. Now the bubble appears in the same UI frame as the tap; the heavy convergence work continues in the background. If a later DM remap picks a different canonical group, the optimistic message's `groupIdHex` is rewritten in place rather than dropped/re-added.
- Hardened the optimistic-send path: Android now uses `abortOptimisticSend(...)` and `keepOptimisticBubbleIn(...)`; iOS uses `abortOptimisticSend(...)` and `keepOptimisticBubble(in:)`. Pre-send abort paths remove the temporary bubble and clear `sendingMessage`; canonical remaps preserve or restore the temporary bubble in the target group instead of losing it during message-list replacement.
- Removed the remaining micro-animations on the send affordance and auto-scroll. iOS `TalkView.swift`: dropped `.animation(.easeInOut(duration: 0.15), value: hasText)` on the send button so the mic ↔ paper-plane swap happens on the same frame as the tap, and wrapped both `proxy.scrollTo` calls in a `Transaction` with `disablesAnimations = true` so no enclosing implicit animation can attach. Android `TalkComponents.kt`: replaced the two `animateColorAsState(tween(150))` on the send button background/tint with plain conditional values (and removed the now-unused `animateColorAsState` / `tween` imports). Net effect: every send tap commits in <16 ms with zero easing between tap, bubble insertion, and bottom-snap.
- Replaced the auto-scroll easing in the chat list with instantaneous jumps (`scrollToItem` on Android `TalkScreen.kt`, plain `proxy.scrollTo(..., anchor: .bottom)` without `withAnimation` on iOS `TalkView.swift`). The optimistic bubble is already at the bottom, so any easing only adds perceived latency.
- Documented the new "instant send" rule and the no-sender-name rule in `docs/wiki/ui/android-ios-sync.md`.

## [2026-05-23] fix | Talk chat icon parity + drop read-receipt label

- Aligned Android Talk chat icons with the iOS SF Symbols set. Header `⌕ / ☎ / 31 / ☰` text glyphs replaced with `Icons.Outlined.Search / Call / CalendarToday / Menu` in `TalkScreen.kt`; the obsolete `LineCalendarAction` and Unicode-symbol `LineHeaderAction(symbol: String, …)` helper were removed and the helper now takes an `ImageVector` + `onClick`.
- Composer left-side icons in `TalkComponents.kt` rebuilt: `Icons.Outlined.Add` (＋), `Icons.Outlined.PhotoCamera` (camera), `NuruIcons.Image` (photo). Previously the camera slot reused `NuruIcons.Image`, so two identical photo glyphs were shown.
- Removed the outgoing 「既読」 label on both platforms (`TalkView.swift` `MessageBubble`, `TalkComponents.kt` `MlsMessageBubble`) because end-to-end read receipts are not yet observable; only the timestamp remains beside the bubble.
- Updated `docs/wiki/ui/android-ios-sync.md` with the explicit header / composer icon mapping and the no-read-receipt rule.

## [2026-05-23] fix | LINE-style native Talk chat chrome

- Updated native Talk chat UI on iOS and Android toward the LINE reference: compact black header, LINE-like action icons, green outgoing bubbles, dark-gray incoming bubbles, outside timestamps, and LINE-style composer controls.
- Hidden the global bottom tab bar while a Talk conversation is open so the chat and composer own the full screen; the tab bar remains visible on the Talk list.
- Removed visible MLS group IDs from chat headers, composers, and conversation rows. Added the full group ID to the group information sheet/modal on iOS and Android.
- Source: `ios/NuruNuru/Views/Screens/TalkView.swift`, `ios/NuruNuru/Views/Sheets/GroupInfoSheet.swift`, `ios/NuruNuru/Views/Screens/MainTabView.swift`, `android/app/src/main/kotlin/io/nurunuru/app/ui/screens/TalkScreen.kt`, `android/app/src/main/kotlin/io/nurunuru/app/ui/components/TalkComponents.kt`, `android/app/src/main/kotlin/io/nurunuru/app/ui/components/GroupInfoModal.kt`, `android/app/src/main/kotlin/io/nurunuru/app/ui/screens/MainScreen.kt`.

## [2026-05-23] feat | iOS MLS peer-epoch catch-up parity (issue #190)

- Wired the Issue #183 Rust FFI (`mls_catch_up_to_peer`,
  `mls_prune_replay_cache`, `mls_replay_cache_size`) through
  `NuruNuruFFIBridge` + `MlsFFIStub` + `NuruNuruFFILiveClient`. Added
  Swift mirrors `FfiMlsCatchUpStatus` and `FfiMlsCatchUpReport`.
- Added `NostrRepository.deepCatchUpMlsGroup`,
  `pruneMlsReplayCache`, `mlsRecoveryStatusFor`,
  `clearMlsRecoveryStatus`, and `recreateDmConversation` plus the
  `MlsRecoveryStatus` / `MlsDeepCatchUpResult` Swift types — names and
  semantics mirror Android one-to-one. The replay-cache prune now
  piggy-backs on the first `fetchMlsGroups` call per session via a
  `mlsReplayCachePrunedThisSession` gate.
- Added `TalkViewModel.recoveryStatus`, `recreatingConversation`,
  `recreateActiveDmConversation`, and `dismissRecoveryBanner`. Deep
  catch-up is escalated after the standard preflight in `sendMessage`
  and after `repairCurrentGroup` leaves a DM gap; the cached banner
  state is restored on `openGroup` and cleared on `closeGroup`.
- Added the SwiftUI `MlsRecoveryBanner` to `TalkView.swift` with copy
  matching Android exactly (「メッセージを完全に復元できません」 +
  「作り直す」 / 「後で」). Native SwiftUI per `ios/GUARDRAILS.md`.
- Rebuilt the `NuruNuruFFI.xcframework` (device + sim slices) so the
  new UniFFI symbols are linkable; verified
  `_uniffi_uniffi_nurunuru_fn_method_nurunuruclient_mls_catch_up_to_peer`
  / `mls_prune_replay_cache` / `mls_replay_cache_size` are exported
  from both slices. iOS Simulator (iPhone 17) Debug build succeeded
  with no new errors.
- Closes the AC4 requirement from issue #183.

## [2026-05-23] fix | Android MLS peer-epoch catch-up (issue #183)

- Added a sidecar SQLite replay cache (`{mls_db_path}.replay.sqlite3`, 30-day
  TTL, 2,000-row per-group cap) so peer Kind-445 wrappers survive relay aging
  and app process death. Cache writes are best-effort and never alter
  PR #180's receive-path semantics.
- Added `MlsManager::catch_up_to_peer(group_id_hex, candidates)` which
  replays caller-supplied + cached wrappers in `created_at` order across up
  to 8 retry passes and returns a typed `MlsCatchUpReport` with status
  `Recovered` / `PartiallyRecovered` / `NotRecoverable` / `NoSuchGroup`.
  Never touches pending-commit state, so PR #180's invariants are preserved.
- FFI: added `mls_catch_up_to_peer`, `mls_prune_replay_cache`,
  `mls_replay_cache_size` plus `FfiMlsCatchUpReport` /
  `FfiMlsCatchUpStatus`; regenerated Kotlin bindings and cross-compiled the
  arm64-v8a `.so`.
- Android: `NostrRepositoryTalk.deepCatchUpMlsGroup` orchestrates the wider
  Kind-445 relay pull and the FFI catch-up call; `recreateDmConversation`
  automates "workaround A" (leave + create fresh DM). `TalkViewModel`
  escalates to deep catch-up after every standard repair and after the
  send-preflight fullRepair fallback; new `recoveryStatus` UI state plus
  `MlsRecoveryBanner` in `TalkScreen` prompts the user with
  「メッセージを完全に復元できません — 作り直す / 後で」 when the missing
  Commit is no longer retrievable from configured relays and is not in the
  cache (AC2).
- Tests: new `rust-engine/nurunuru-core/tests/issue_183_catch_up.rs`
  (8 tests, all passing); existing 47-test core suite still green.
- Wiki: new `docs/wiki/features/mls-peer-epoch-catch-up.md` and updated
  `docs/wiki/index.md`.

## [2026-05-21] setup | Initial LLM Wiki scaffold

- `AGENTS.md` に LLM Wiki 運用ルールを追加。
- `docs/wiki/` 配下に初期構成を作成。
- Core / Platforms / Features / UI / NIPs / Decisions の最小ページを追加。
- 真実の源泉はソースコード・design tokens・設計文書であり、Wiki は派生ナビゲーション層であることを明記。

## [2026-05-21] docs | Code-backed Wiki corrections and NIP audit

- Corrected stale PostActions documentation: current code has like / repost / zap plus optional bookmark, with no reply button.
- Replaced the short Supported NIPs line with a code-backed NIP support table in `docs/wiki/nips/README.md`.
- Added high-priority pages: `features/image-upload`, `features/talk`, `features/relay-management`, `ui/post-row`, `nips/nip-46`, `nips/nip-57`, `nips/nip-65`, `nips/nip-70`, `nips/nip-71`, and `nips/nip-98`, plus `lint-report`.
- Updated platform and feature pages with source references from Android, iOS, Web, and Rust code.

## [2026-05-21] docs | Detailed NIP boundary pages

- Added detailed pages for `nip-17`, `nip-25`, `nip-30`, `nip-51`, `nip-58`, and `nip-59`.
- Clarified the native Talk boundary: NIP-17 remains legacy/compatibility while Talk is Marmot MLS-oriented; NIP-59 kind 1059 is used for Marmot Welcome delivery.
- Updated `index.md`, `nips/README.md`, and `lint-report.md` to reflect the new pages and remaining doc targets.

## [2026-05-21] docs | Wiki maintenance, parity, glossary, and ADRs

- Removed stale `ios/DESIGN.md` and `ios/SYNC_PLAN.md` links from `AGENTS.md`, replacing them with existing guardrail/wiki links.
- Added `logs/` to `.gitignore` after identifying it as local Android/iOS Talk/Marmot diagnostic output.
- Added `docs/wiki/platforms/parity-matrix.md` and `docs/wiki/glossary.md`.
- Added ADRs for native Marmot MLS Talk, iOS NIP-46 external signing, design tokens, PostActions, and Web Rust bridge stubs.
- Updated `docs/wiki/nips/README.md` with a `Level` column and separated official numbered NIPs from ecosystem/BUD/project-specific protocols.
- Added `scripts/wiki-lint.mjs` for basic Wiki health checks.

## [2026-05-21] tooling | Wiki lint npm script

- Added `npm run wiki:lint` to `package.json` and documented it in `AGENTS.md`.
- Verified the lint script directly with Node because this tool environment does not expose `npm` on PATH.

## [2026-05-21] docs | Low-priority wiki completion

- Added GitHub Actions workflow `.github/workflows/wiki-lint.yml` to run `npm run wiki:lint` on relevant PR/push changes.
- Split Talk documentation into Marmot MLS internals, relay strategy, debugging guidance, and Android/iOS parity pages.
- Added detailed pages for `nip-04`, `nip-18`, `nip-23`, and `nip-44`.
- Updated `index.md`, `nips/README.md`, and `lint-report.md` with the new pages and remaining future targets.

## [2026-05-22] culture | NuruNuru Charter v0.1 と4軸自由ドクトリンを起票

- Theme Day「企業文化・カルチャー構築」の成果として `docs/wiki/culture/` を新設。
- 北極星 + 五箇条を [[culture/principles]] に明文化 (Charter v0.1)。
- [[culture/not-doing]] にやらないことリストを起票 (体験 / 日本語 / 一貫性 / 鍵 / 設計判断 / NIP / 経済 / 配布 / 短期 KPI)。
- [[culture/design-crit]] に Weekly Nuru Design Crit の運用 (沈黙批評 → 発話批評 → 4 ラベル) を定義し、[[decisions/adr-0007-design-crit-ritual]] として制度化を起票。
- [[culture/copy-style]] に日本語コピー規約 (直訳禁止 / 既存採用語保護 / 場面別ガイド) を起票。
- [[culture/llm-onboarding]] に LLM コントリビュータ向けの編集前チェックリストと出力規約を起票。
- ユーザーからの「業界の10年先を行く」「経済 / 配布の自由も視野に入れる」という方針を [[culture/four-freedoms]] に整理し、[[decisions/adr-0008-four-freedoms-mission]] として長期ミッションを Proposed で起票。
- 新規 ADR テンプレート [[decisions/_template]] を追加。
- `.github/pull_request_template_ui.md` に UI 変更 PR チェックリストを追加。
- `AGENTS.md` に Culture セクションを追加し、Wiki から AGENTS へのエントリを確立。
- `docs/wiki/index.md` に Culture セクションを追加し、ADR-0007/0008 とテンプレートをリストに追加。
- 本件はコード変更を伴わない文化憲章 (Proposed)。Phase 1 (Talk Marmot 完成) → Phase 2 (経済) → Phase 3 (配布) のロードマップは [[culture/four-freedoms]] を参照。

## [2026-05-22] security | Issue #181 MLS DB encryption (Android verified, iOS shipped)

- Rust core: `mls_db_path_for(db_path)` as single source of truth for the on-disk MLS SQLite path. `bind_mls_for_pubkey` errors hard on `had_key && bind_failed` (B5). New `mls_is_encrypted() -> Option<bool>` (B7) lifted through UniFFI + napi-rs for app-layer assertion.
- FFI: `NuruNuruClient::new_with_mls_db_key` / `new_read_only_with_mls_db_key` validate 32-byte key length before SQLCipher bind. `derive_mls_db_key_from_secret(secret_hex, app_salt)` exposes HKDF-SHA256 derivation to Kotlin + Swift.
- Android: new `MlsDbKeyStore` (HKDF for internal signer, `EncryptedSharedPreferences` + `MasterKey` for external signer, `synchronized` lock + `commit()` for B4 race). New `MlsLegacyMigration` (content-based plaintext detection via FFI `mls_db_path_for`, runs every launch — B1+B2). `NuruNuruApp.onCreate()` purges before `initEngine()` (M5). Logout clears external key before `prefs.clear()`.
- iOS: mirror `MlsDbKeyStore` (Keychain `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` + `NSLock`) and `MlsLegacyMigration` (`isExcludedFromBackup` on DB/WAL/SHM — M6 partial). `MlsFFILiveClient` uses new encrypted ctors with `inout Data` zeroize via `Data.resetBytes(in:)` (B3). `mlsIsEncrypted() -> Bool?` lifted to `MlsFFIBridge` protocol + stub.
- Verified: a physical Android device runtime confirms plaintext purge + SQLCipher header (`53 51 4c…00` → `21 1d c0…c4`) + `MLS DB encrypted (SQLCipher) — issue #181 guard OK` log. iOS xcodebuild for iPhone 17 simulator returns BUILD SUCCEEDED.
- Bindings: `gen_swift.sh` switched to debug build (workspace `release` profile has `strip = true` which removes UniFFI metadata `.symtab`, causing silent missing-types in bindgen output).
- Wiki: added [[features/mls-db-encryption]] (threat model + verification trace) and [[decisions/adr-0009-mls-db-encryption]] (rationale + alternatives + consequences). Updated `index.md`.
- Open: CI lint to block legacy unkeyed ctor reintroduction (M2), Settings UI status indicator (M4), release notes + CHANGELOG (M6 user-facing).

## [2026-05-23] security | Issue #181 follow-up (M2 CI guard + M6 release notes; M4 dropped)

- M2 (CI guard): added `scripts/issue-181-guard.mjs` + `npm run lint:issue-181`. Walks `ios/NuruNuru/` and `android/app/src/main/kotlin/`, fails on reintroduction of unkeyed `NuruNuruClient(secretKeyHex:)` / `NuruNuruClient.newReadOnly(pubkeyHex:)` ctors. Skips generated `bindgen/` directories. Verified: 214 files scanned, 141 596 pattern checks, 0 violations on clean tree; negative test with 2 injected violations reports both with file:line + remediation hint.
- M6 (release notes): added `[Unreleased] > Security` + `Upgrade notes` to `CHANGELOG.md` documenting the SQLCipher migration and the unavoidable past-message loss on upgrade. Added `docs/release-notes/issue-181-mls-db-encryption.md` with JP + EN short forms for zapstore / GitHub Release / Google Play / TestFlight, plus a support-facing FAQ ("過去メッセージが見えなくなった理由").
- M4 (Settings UI "encrypted ✓"): dropped by product decision. The runtime guard already hard-fails on missing encryption (`MLS DB encrypted (SQLCipher) — issue #181 guard OK` line is mandatory), so a green checkmark would be redundant UI noise without an actionable user signal.
- Verification log unchanged: a physical Android device + a physical iPhone 12 mini both show the guard line on cold launch + SQLCipher random-bytes header on disk. Talk receive-loop logic (PR #180) is NOT touched by this change — `git diff HEAD --stat -- ios/NuruNuru/Data/NostrRepository+Talk.swift android/app/src/main/kotlin/io/nurunuru/app/data/NostrRepositoryTalk.kt` returns empty.
- Unrelated open issue surfaced during log analysis: iOS-sent kind:445 messages occasionally retry-queue on Android as `state_not_ready` (MDK epoch lag). Tracked separately — not an Issue #181 regression.

## [2026-05-23] ux | Android Talk pull-to-refresh and auto-repair

- Added Android open-conversation pull-to-refresh for Talk MLS history catch-up, aligned with the existing Material3 pull-to-refresh pattern used by Timeline.
- Added guarded Android Talk auto-repair after repeated empty Kind-445 relay fetches for an already-populated conversation, using relay fetch stats from `NostrRepositoryTalk.kt`.
- Kept explicit Group Info "メッセージを修復" as the stronger manual repair path while pull/auto refresh avoid clearing pending commits.
## [2026-05-23] fix | Android Talk pull-to-refresh top-edge fallback

- Root cause: Material3 `PullToRefreshContainer` only receives downward drags via `nestedScrollConnection` when the inner scrollable is already at scroll position 0. `GroupChatScreen` runs `listState.animateScrollToItem(messages.size - 1)` on every message update so the LazyColumn is almost always scrolled toward the newest message; the user's pull gesture was consumed by the list as a normal upward scroll and never reached `PullToRefresh`.
- Fix: added a `pointerInput` top-edge drag detector around the message-area `Box` in `TalkScreen.kt`. Touches that start within ~120dp of the conversation viewport top and accumulate ~72dp of downward travel call `pullRefreshState.startRefresh()` directly, which triggers the existing `refreshCurrentGroup()` → `runMlsRepair(source = "pull", clearPendingCommit = false)` path. The Material3 `nestedScrollConnection` is kept as the secondary path for the case where the user has scrolled to the oldest message.
- Visual layout is unchanged (oldest → newest top → bottom, auto-scroll to newest); only the gesture surface is extended.
- Verified by rebuild + reinstall: `BUILD SUCCESSFUL`, versionName=1.5.0, on a physical Android device. iOS parity for this fallback is tracked separately.
## [2026-05-23] ux | Android Talk pull-to-refresh redesigned for LINE-grade parity

- Removed the temporary TopBar refresh icon and the `gid:xxx msg:N` debug subtitle on the conversation screen. Both were diagnostic, not aligned with the LINE-grade visual language.
- Changed conversation auto-scroll to only follow new messages when the user is already within 3 items of the list bottom (`lastVisibleIndex >= totalItems - 3`). While the user is scrolled up to read history, the LazyColumn stays put, so the Material3 `PullToRefreshContainer.nestedScrollConnection` can receive downward drags and pull-to-refresh works naturally from any scroll position.
- The conversation `pointerInput` top-edge fallback is retained as a secondary trigger.
- Conversation pull-to-refresh now performs a STRONG repair (`clearPendingCommit = true`) instead of the weak `repairFull=true`-only path. iOS frequently advances MLS epoch ahead of Android; an explicit user-initiated refresh should clear any stranded Android pending commit so iOS-originated messages decrypt. This matches the strength of the Group Info「メッセージを修復」action.
- Added pull-to-refresh to the Talk list (GroupListScreen) across all three filter pages (すべて / 友だち / グループ) via a shared `PullToRefreshState` and `refreshGroupList()` on the ViewModel. Achieves iOS Talk-list parity.
- Verified by rebuild + reinstall: `BUILD SUCCESSFUL`, versionName=1.5.0, on a physical Android device.
## [2026-05-23] fix | Android Talk render decrypted iOS messages despite residual MLS gaps

- Root cause for "iOS new message fetched but not shown on Android": Android was successfully fetching Kind-445 events and could apply at least one iOS-originated application message, but `TalkViewModel.startMessageStream()` stopped the polling loop on a residual DM MLS gap before writing the normalized message list into `_uiState.messages`. Logs showed `application id=... len=3` followed by residual `state_not_ready` retryables, so the relay/decrypt path was not the only issue; the UI render path was dropping usable history.
- Fix: update `_uiState.messages` before handling residual DM gap diagnostics, and do not break the stream solely because `mlsStateGapCount() > 0` when usable normalized history exists. Manual pull and guarded auto-repair remain responsible for reducing the remaining gap.
- Kept the LINE-grade Talk UX changes: no TopBar refresh icon, no debug `gid:/msg:` subtitle, Android Talk-list pull-to-refresh added, and conversation pull-to-refresh uses strong repair.
- Verified by rebuild + reinstall + launch on a physical Android device: versionName=1.5.0.
## [2026-05-23] fix | iOS Talk fresh DM isolation and cache-first open

- iOS explicit DM creation now treats「新しくトークを作成」as a hard reset for that DM conversation key: older sibling DM groups are locally hidden, removed from the visible ViewModel lists, and the fresh group is pinned as the canonical send/open target.
- iOS `fetchMlsGroups` now applies DM hidden tombstones when an unhidden sibling DM exists for the same peer, so old hidden DM history does not resurrect after app restart and get merged into the new Talk. If all valid peer DMs are hidden (legacy auto-recovery tombstone bug), the valid shared group remains visible to avoid orphan sends.
- iOS `loadGroups` now paints locally-known Rust SQLite groups before relay Welcome/profile discovery, and `openGroup` paints local SQLite message history immediately (then local sibling histories) before relay-backed repair/canonical scanning. Relay catch-up remains background refinement, so opening Talk after launch is cache-first.
## [2026-05-23] fix | iOS Talk exited groups stay hidden

- iOS Talk now records explicit MLS exits in the persistent left-group blocklist and applies that blocklist in both `getLocalMlsGroups` (cache-first startup) and `fetchMlsGroups` (relay refresh).
- `visibleFfiMlsGroups` now treats local hidden/left tombstones as authoritative for DMs and named groups, and no longer auto-prunes tombstones just because the visible list would otherwise be empty. This prevents a deliberately empty Talk list after leaving the last group from being repopulated from Rust SQLite/relay state.
- `TalkViewModel.leaveGroup` removes exited named groups from both visible lists immediately, mirrors DM sibling exits into the persistent left set, and clears fresh-DM session pins for exited groups.

## [2026-05-23] feat | Onboarding tutorial post step (#nostrはじめました)

- Added a new "tutorial" step between `profile` and `success` in the 新規登録 (sign-up) wizard across all 3 platforms.
- The step pre-fills `#nostrはじめました\n`, enforces 140-char limit, lets the user freely edit / append, and publishes a kind-1 note via the existing publish path with auto-extracted `t` tags (lowercased). The `nostrはじめました` tag is auto-appended to both content and `t` tags if the user removes it.
- Web (`components/SignUpModal.js`): new `tutorial` step state + `handlePostTutorial()` using `createEventTemplate(1, ...)` → `signEventNip07` → `publishEvent`. Progress bar reflects 6 segments (was 5).
- Android (`SignUpModal.kt` + `AuthViewModel.kt`): new `TutorialStep` composable + `AuthViewModel.publishTutorialPost(signer, content, relays)`. Uses the same temporary `NostrClient` + `NostrRepository` pattern as `publishInitialMetadata`, then calls `NostrRepository.publishNote(content, customTags = [["t", ...], ...])`.
- iOS (`LoginView.swift` + `AuthViewModel.swift`): new `SignUpTutorialStep` view + `AuthViewModel.publishTutorialPost(content:, relays:)`. Mirrors the Android pattern with a temporary `NostrRepository`, signing via `keyManager`-backed `signer`.
- Both confirmation copy ("投稿しました！" + 「タイムラインで「#nostrはじめました」を検索すると、同じ仲間が見つかります。」) and skip behavior are identical across platforms per [[ui/android-ios-sync]].
- New wiki page: [[features/onboarding]] documents the 6-step contract, tutorial-step semantics, hashtag handling, and per-platform notes.
- No NIP support change; no design-token change; no new dependency. AGENTS.md unchanged.

## [2026-05-23] polish | Onboarding tutorial step (production hardening)

- iOS `SignUpTutorialStep` の `TextEditor` に `scrollContentBackground(.hidden)` を追加。リポジトリ内の他 `TextEditor` 使用箇所 (PostSheet / QuoteRepostSheet / ReportSheet / 各 MiniApp) と同じ扱いに揃え、ダーク/ライトテーマでデフォルト背景 (白) が透けてしまう問題を防止。
- Android `AuthViewModel.publishTutorialPost` で `client.connect()` 以降を `try/finally` で囲み、例外パスでも必ず `client.disconnect()` を呼ぶよう修正 (リレー接続リーク防止)。
- iOS `AuthViewModel.publishTutorialPost` で `publishNote` 例外パスにも `await repo.client.disconnect()` を追加 (同上)。
- 仕様・UI フロー・wiki ドキュメント (`docs/wiki/features/onboarding.md` / `docs/wiki/index.md` / `docs/wiki/log.md`) に変更なし。`wiki-lint: 0 failure(s), 0 warning(s)`。

## [2026-05-23] polish | Onboarding tutorial step (UX revision: hashtag-at-end, green bubble, placeholder)

- ハッシュタグ配置を変更: pre-fill していた `#nostrはじめました\n` (本文先頭) を撤廃し、デフォルト本文を空に。投稿時に `publishTutorialPost` (Web/Android/iOS いずれも) が本文末尾へ改行 + `#nostrはじめました` を自動付与するため、結果として「本文 → 改行 → ハッシュタグ」という配置が常に成立する。本文を完全に空にしたまま投稿した場合は `#nostrはじめました` 単独で送信される。
- プレースホルダー追加: `いまどうしてる？\n#nostrはじめました` を薄い灰色 (`var(--text-tertiary)` / `nuruColors.textTertiary` / `theme.textTertiary`) で表示し、ユーザーが何を書けばよいかの例示にする。
  - Web (`components/SignUpModal.js`): `<textarea>` の `placeholder` 属性 + `placeholder:text-[var(--text-tertiary)] placeholder:opacity-70`。
  - Android (`SignUpModal.kt`): `OutlinedTextField` の `placeholder = { Text(TUTORIAL_PLACEHOLDER, color = nuruColors.textTertiary) }`。
  - iOS (`LoginView.swift`): `TextEditor` が placeholder API を持たないため、`ZStack(alignment: .topLeading)` で `content.isEmpty` 時だけ `Text(kTutorialPlaceholder)` を `theme.textTertiary` で重ね描画。`allowsHitTesting(false)` で下層 `TextEditor` にタップを通す。
- ブランド統一: チュートリアル吹き出しアイコンの色を pink (`#E91E63` / `Color.pink`) からぬるぬるブランドカラーの **LineGreen** に変更。
  - Web: `bg-pink-500/10` + `text-pink-500` → `rgba(6,199,85,0.1)` + `var(--line-green)`。
  - Android: `Color(0xFFE91E63)` → `LineGreen`。
  - iOS: `Color.pink` / `.pink` → `NuruColors.lineGreen`。
- 投稿ボタンの `enabled` 条件を緩和: 本文が空でも `#nostrはじめました` 単独投稿が可能になるよう、すべてのプラットフォームで「投稿中でなく、かつ 140 文字以下」のみを有効条件とした (空文字拒否を削除)。Android/iOS の `publishTutorialPost` も `trimmed.isEmpty()` の場合は `#nostrはじめました` を本文として送信する分岐を追加。
- 修正ファイル: `components/SignUpModal.js`, `android/app/src/main/kotlin/io/nurunuru/app/ui/components/SignUpModal.kt`, `android/app/src/main/kotlin/io/nurunuru/app/viewmodel/AuthViewModel.kt`, `ios/NuruNuru/Views/Screens/LoginView.swift`, `ios/NuruNuru/ViewModels/AuthViewModel.swift`, `docs/wiki/features/onboarding.md`。NIP サポート / design-token / 依存に変更なし。

## [2026-05-23] polish | Onboarding tutorial step (UX revision 2: visible hashtag + user-respect deletion)

- 「#nostrはじめました が見えないまま自動付与されるのは不信感を生む」「ユーザーが消したら消えたまま投稿したい」というユーザー要望に基づき、3 プラットフォームの仕様を以下の通り改訂:
  - **pre-fill 復活**: 既定本文を空ではなく `\n#nostrはじめました` に変更。エディタを開いた瞬間からハッシュタグが常時可視化される。1 行目を空にしてカーソルを先頭に置けば「本文 → 改行 → ハッシュタグ」の配置が自然に成立する。
  - **自動補完ロジック完全撤廃**: `publishTutorialPost` (Web/Android/iOS) から「本文末尾に `\n#nostrはじめました` を 3 分岐で付与する」処理を削除。ユーザーがハッシュタグ行を消したら、消した状態のまま送信される。
  - **t タグ抽出も意図尊重**: 本文中の `#xxx` のみを `["t", value]` として送信。ユーザーが `#nostrはじめました` を消していれば `t` タグも付かない (本文と `t` タグの内容が常に一致する規約)。
  - **空本文ガード追加**: 投稿ボタン enabled 条件を「投稿中でない && 140 文字以下 && trim 後 0 文字でない」に強化。pre-fill された `#nostrはじめました` を残せば自動的に enable のため、UX としては自然。Web は throw、Android/iOS は `return false` で空送信を防ぐ。
- 修正ファイル (コード 5 + ドキュメント 2):
  - `components/SignUpModal.js`: `TUTORIAL_DEFAULT_CONTENT` 復活 + `handlePostTutorial` 内の末尾自動補完 3 分岐削除 + 空本文 throw 追加 + ボタン disabled 条件に `trim().length === 0` 追加。
  - `android/.../ui/components/SignUpModal.kt`: `TUTORIAL_DEFAULT_CONTENT = "\n#nostrはじめました"` + KDoc 新仕様化 + 投稿ボタン `enabled = !isPosting && content.trim().isNotEmpty()`。
  - `android/.../viewmodel/AuthViewModel.kt`: `publishTutorialPost` の末尾自動補完 `when` ブロック削除 + 空本文ガード + KDoc 新仕様化。
  - `ios/.../Views/Screens/LoginView.swift`: `kTutorialDefaultContent = "\n#nostrはじめました"` + docstring 新仕様化 + `canPost` に空本文判定追加。
  - `ios/.../ViewModels/AuthViewModel.swift`: `publishTutorialPost` の末尾自動補完分岐削除 + 空本文 guard + docstring 新仕様化。
  - `docs/wiki/features/onboarding.md`: 「Tutorial step contract」セクションを pre-fill + no-auto-completion 規約に書き換え + Android/iOS の投稿ボタン条件を更新 + Open questions に「先頭改行 1 文字分の 140 文字制限への影響」を追記。
- finalize: Android `publishTutorialPost` の t タグ抽出を `distinct → lowercase` から `lowercase → distinct` に修正。Web (`toLowerCase()` 後に `seen` 重複排除) / iOS (`lowercased()` 後に `seen.insert`) と同じ「lowercase-first → distinct」順に揃え、`#Foo` と `#foo` を本文に混在させた時の `t` タグ重複を 3 プラットフォーム同一挙動 (1 個に正規化) で扱うようにした。下流 `tags = foundTags.map { listOf("t", it) }` も二重 lowercase を解消。シナリオ検証 6 ケース (pre-fill そのまま / 本文追記 + pre-fill 残し / ハッシュタグだけ削除 + 本文あり / 全部削除 / 140 文字超 / `#Foo` と `#foo` 混在) すべて 3 プラットフォーム同一結果で通過。
- NIP サポート / design-token / 依存に変更なし。AGENTS.md 不変。


## [2026-05-23] feat | Nosskey (Passkey/PRF direct) sign-up across iOS + Android

- **新規登録オンボーディングに Passkey 経路を追加**。iOS と Android で
  [nosskey "PRF Direct Method"](./nips/nosskey.md) ベースの新規登録を実装した。
  Web は 2025 年以前から `nosskey-sdk@^0.0.4` で対応済みのため、本変更で
  3 プラットフォームの parity を確立。
- **設計判断**: [[decisions/adr-0010-passkey-prf-direct-method|ADR-0010]] を新規起票。
  PRF Direct Method を採用し、秘密鍵をディスクに保存しない方針。
- **Salt 統一**: Web の `components/SignUpModal.js` が使っていた旧誤値
  `6e6f7374722d6b6579` (`"nostr-key"`) を、nosskey-sdk 標準値
  `6e6f7374722d70776b` (`"nostr-pwk"`) に修正。SDK 自身が読み込み時に旧値を
  自動正規化するため既存ユーザーへの影響なし。
- **iOS (iOS 18+ 必須)**:
  - 新規ファイル: `ios/NuruNuru/Data/NosskeyManager.swift` (≈410 行,
    `AuthenticationServices` の `ASAuthorizationController` +
    `ASAuthorizationPlatformPublicKeyCredential*` を MainActor でラップし、
    PRF 拡張による secret 導出を実装)。
  - 新規ファイル: `ios/NuruNuru/Data/NosskeySigner.swift` (≈357 行,
    新規 `EventSigner` プロトコルを実装。5 分 TTL の in-memory PRF キャッシュ
    + NIP-04 / NIP-44 v2 / Schnorr 署名)。
  - 新規ファイル: `ios/NuruNuru/Data/EventSigner.swift` (`InternalSigner` と
    `NosskeySigner` の共通プロトコル)。`InternalSigner` は同プロトコルに準拠する
    よう改修 (シグネチャ互換)。
  - 修正: `ios/NuruNuru/ViewModels/AuthViewModel.swift` に
    `generateNewAccountWithPasskey(username:)`, `loginWithPasskey()`,
    `currentSessionSigner()` を追加。`checkStoredLogin()` に
    `loginMethod == "nosskey"` ブランチ。`logout()` で
    `nosskeyManager.clearStoredKeyInfo()` も実行。
  - 修正: `ios/NuruNuru/Views/Screens/LoginView.swift` の `SignUpWelcomeStep` に
    `onNextWithPasskey` クロージャと `passkeyAvailable` プロパティを追加。
    Passkey 対応端末では「**パスキーで登録**」が primary、
    「従来の方法で作成（nsec）」が secondary。`SignUpSheet.usingPasskey` 状態と
    `progress` 5 分割計算を追加 (Passkey 経路は backup ステップをスキップ)。
  - 修正: `ios/NuruNuru/Data/NostrRepository.swift` の `signer` 型を
    `InternalSigner` から `EventSigner` プロトコルへ。`init` に
    `signer: EventSigner? = nil` 引数を追加し、サインアップ経路から
    `NosskeySigner` を注入可能に。
  - 修正: `ios/NuruNuru/Data/AppPreferences.swift` に `loginMethod: String?`
    (`"nsec" | "nosskey" | "external"`) を追加 + `clear()` でも削除。
  - 既定 RP ID は `"www.nullnull.app"`。本番デプロイには
    `https://www.nullnull.app/.well-known/apple-app-site-association` と
    `webcredentials:www.nullnull.app` Associated Domains entitlement が必要
    (現状未デプロイ → 物理端末では未動作、Simulator では動作)。
- **Android (API 28+ 必須)**:
  - 新規ファイル:
    `android/app/src/main/kotlin/io/nurunuru/app/data/NosskeyManager.kt`
    (≈365 行, `androidx.credentials.CredentialManager` + PRF 拡張 JSON)。
  - 新規ファイル:
    `android/app/src/main/kotlin/io/nurunuru/app/data/signers/NosskeySigner.kt`
    (≈153 行, `AppSigner` 実装)。
  - 修正: `AuthViewModel.kt` に `generateNewAccountWithPasskey(activity,
    username)`, native `loginWithPasskey(activity)` (旧 Custom Tabs スタブを置換),
    `buildSigner(activity)` を追加。`checkStoredLogin` に
    `loginMethod == "nosskey"` ブランチ。
  - 修正: `ui/components/SignUpModal.kt` の `WelcomeStep` に
    `onNextWithPasskey` パラメータと「**パスキーで登録**」/
    「従来の方法で作成（nsec）」UI を追加。`SignUpModal` に
    `usingPasskey` 状態 + 5/6 ステップ progress 切替。
  - 修正: `ui/screens/LoginScreen.kt` でコメントアウトされていた
    「パスキーでログイン」ボタンを復活し、`NosskeyManager.loadStoredKeyInfo()` が
    存在するときだけ表示。Web round-trip スタブを native
    `CredentialManager` 経由のフローに置換。
  - 修正: `data/prefs/AppPreferences.kt` に `loginMethod` 追加 (plainPrefs)。
  - 既定 RP ID は `"www.nullnull.app"`。本番デプロイには
    `https://nullnull.app/.well-known/assetlinks.json` で
    `applicationId = io.nurunuru.app` を RP に紐付ける必要あり
    (現状未デプロイ → Emulator/Play Store-installed device の Google Password
    Manager 経路のみ動作確認可能)。
- **Wiki**: `docs/wiki/nips/nosskey.md` (新規, ≈186 行), 既存
  `docs/wiki/features/onboarding.md` に「Passkey (nosskey) sign-up path」
  セクション追加, `docs/wiki/nips/README.md` に Nosskey draft 行追加,
  `docs/wiki/decisions/adr-0010-passkey-prf-direct-method.md` (新規, ≈126 行)。
- **依存追加なし**: iOS は OS 同梱の `AuthenticationServices` のみ。Android は
  既にあった `androidx.credentials:1.2.2` + `credentials-play-services-auth` を
  そのまま使用。
- **互換性**: nsec / NIP-46 (iOS) / NIP-55 Amber (Android) / nostr-login (Web)
  の既存ログイン経路はすべて温存。

## [2026-05-24] fix | iOS real-device Passkey registration requires Associated Domains

- 実機テストで「パスキーの登録に失敗しました」が表示される問題を調査。原因は iOS native Passkey が `rpId = "www.nullnull.app"` を使う場合に必須となる Associated Domains / AASA が未設定だったため。
- iOS アプリ側:
  - `ios/NuruNuru/NuruNuru.entitlements` を新規追加し、`com.apple.developer.associated-domains = ["webcredentials:www.nullnull.app"]` を設定。
  - `ios/project.yml` に `CODE_SIGN_ENTITLEMENTS: NuruNuru/NuruNuru.entitlements` を追加し、XcodeGen 後の project に反映。
- Web 配信側:
  - `public/.well-known/apple-app-site-association` を新規追加。内容は `webcredentials.apps = ["66G7S3P755.io.nurunuru.app"]`。
  - `next.config.js` に `/.well-known/apple-app-site-association` と `/.well-known/assetlinks.json` の `Content-Type: application/json` header を追加。
  - 既存 `public/.well-known/assetlinks.json` の package 名を `app.nurunuru` から実際の Android `applicationId = io.nurunuru.app` に修正。証明書 fingerprint は `REPLACE_WITH_YOUR_SIGNING_CERTIFICATE_SHA256` のままなので、本番 Play/App signing fingerprint で差し替えが必要。
- UX: `SignUpSheet.generateAccountWithPasskey()` の fallback error を「実機では nullnull.app の webcredentials 設定が必要です」と明示する文言に改善。
- 検証: `cd ios && /opt/homebrew/bin/xcodegen generate --spec project.yml && xcodebuild -scheme NuruNuru -destination 'platform=iOS Simulator,name=iPhone 17' -skipPackagePluginValidation -quiet build` 成功 (warnings のみ)。
- 注意: 実機で再テストするには、Web 側の AASA file を `https://www.nullnull.app/.well-known/apple-app-site-association` にデプロイし、Apple Developer portal の App ID で Associated Domains capability を有効化した provisioning profile で再署名・再インストールする必要がある。iOS は AASA を cache するため、失敗が続く場合は app 削除→再インストール、または端末再起動を行う。

## [2026-05-24] fix | iOS Passkey RP ID follows canonical www.nullnull.app

- 実機で引き続き「webcredentials 設定が必要です」と表示される件を live URL で確認。
  `https://nullnull.app/.well-known/apple-app-site-association` は `https://www.nullnull.app/...` に 307 redirect し、その先が 404 だった。
- iOS native Passkey / Associated Domains は redirect や 404 に厳しく、アプリ entitlement が正しくても AASA が canonical host で 200 JSON 配信されていないと登録できない。
- 対応:
  - `NosskeyManager.defaultRpId` を `"nullnull.app"` から canonical host の `"www.nullnull.app"` に変更。
  - entitlement に `webcredentials:www.nullnull.app` を追加し、互換用に `webcredentials:nullnull.app` も残した。
  - `app/.well-known/apple-app-site-association/route.js` を追加し、Vercel / Next.js App Router で AASA を 200 JSON として返す route handler を追加。
  - `app/.well-known/assetlinks.json/route.js` も追加し、Android Digital Asset Links も App Router 側から返せるようにした。
  - `LoginView.swift` のエラー文言を `www.nullnull.app` に更新。
- 検証: iOS Simulator build OK (`xcodebuild ... build`, exit 0)。
- 実機再テスト手順: この Web 変更を Vercel にデプロイ後、`curl -i https://www.nullnull.app/.well-known/apple-app-site-association` が `200` + `Content-Type: application/json` + `webcredentials.apps = ["66G7S3P755.io.nurunuru.app"]` を返すことを確認し、アプリを削除→再インストールして AASA cache を更新する。

## [2026-05-24] fix | iOS Nosskey prompt count, nsec export, and passkey login

- iOS 実機テストで Passkey 認証が 4 回前後繰り返される問題を修正。
  - `NosskeyManager.createPasskeyWithSecret()` を追加し、登録時に得た PRF secret を `keyInfo` と一緒に返すようにした。
  - 登録リクエストの PRF 指定を `.checkForSupport` から `.inputValues("nostr-pwk")` に変更。iOS が registration PRF output を返せる場合は登録シート 1 回で secret 取得まで完了する。返せない環境では fallback assertion 1 回のみ。
  - `AuthViewModel.generateNewAccountWithPasskey()` から重複 `deriveSecretKey()` と `NosskeySigner.warmCache()` を削除し、同じ secret を `NosskeySigner.primeCache(secret:)` に投入。profile / relayList / tutorial 投稿直前の追加プロンプトを避ける。
  - `loginWithPasskey()` も取得済み secret を signer cache に投入するよう変更。
- ログアウト後に Passkey ログインできない問題を修正。
  - `logout()` で `NosskeyKeyInfo` を削除しないように変更。`credentialId/pubkey/salt` は非秘密 metadata であり、ログアウト後の「パスキーでログイン」に必要。
  - `LoginView` の初期ボタン群に「パスキーでログイン」を追加し、`AuthViewModel.loginWithPasskey()` に接続。
- ミニアプリタブ > セキュリティ設定で nosskey ユーザーの秘密鍵取得ができない問題を修正。
  - `AuthViewModel.getNsecForCurrentAccount() async` を追加。`loginMethod == "nosskey"` の場合は Passkey 認証で PRF secret を導出し、nsec encode 後に secret を zeroize。
  - `SettingsView` の秘密鍵表示を async 化し、「取得中…」表示を追加。
- 検証: iOS Simulator build OK (`xcodebuild ... build`, exit 0)。

## [2026-05-24] fix | Android Passkey RP ID and debug assetlinks for real-device test

- Android Nosskey実機テスト準備として、`NosskeyManager.RP_ID` を iOS/Web と同じ canonical host の `www.nullnull.app` に統一。
- ローカル debug keystore の SHA-256 fingerprint を取得し、`app/.well-known/assetlinks.json/route.js` と `public/.well-known/assetlinks.json` に追加。
  - Debug SHA-256: `45:CD:CB:AD:A9:F4:35:A0:A3:62:80:05:9C:02:FE:7A:B1:7C:CB:09:CE:05:E2:93:BB:C6:CF:08:27:04:05:60`
- `./gradlew assembleDebug` 成功。
- 接続済み Android 実機 `9DNBNF45Y9AQFEY9` に debug APK を `adb install -r` でインストール成功。
- 注意: production / Play Store 配布では Play App Signing の SHA-256 fingerprint を assetlinks に追加する必要がある。Proton Pass / 1Password / Bitwarden 等の外部 Passkey provider は、その provider が WebAuthn PRF/hmac-secret extension に対応している場合のみ Nosskey direct method で動作する。

## [2026-05-24] fix | Disable assetlinks cache during Android Passkey testing

- `https://www.nullnull.app/.well-known/assetlinks.json` が Vercel/CDN 上で古い placeholder fingerprint を返し続けるため、Android 実機テスト中は cache を無効化。
- `app/.well-known/assetlinks.json/route.js` と `next.config.js` の Cache-Control を `no-cache, no-store, must-revalidate` に変更。
