# null--nostr LLM Wiki Log

LLM Wiki の時系列ログです。追記専用として扱います。

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
