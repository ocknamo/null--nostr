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
