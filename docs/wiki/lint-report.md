# LLM Wiki Lint Report

## Summary

This page records the latest manual health check of the LLM Wiki. It is not a substitute for source-code verification; it highlights stale claims, open gaps, and next documentation targets.

## Latest check: 2026-05-21

### Fixed in this pass

- Removed stale claim that PostActions has only three buttons. Code shows like / repost / zap plus optional bookmark and no reply button.
- Replaced the static AGENTS supported-NIP list with a pointer to the code-backed NIP table.
- Added code-backed NIP index entries with source references.
- Added detailed pages for image upload, Talk, relay management, Post row rendering, NIP-46, NIP-57, NIP-65, NIP-70, NIP-71, and NIP-98.

### Remaining gaps

- Detailed parity pages for NIP-17/NIP-59 vs Marmot MLS would help avoid confusing legacy Web DM helpers with native Talk behavior.
- Detailed pages for NIP-25 reactions, NIP-30 emoji, NIP-51 lists/bookmarks, and NIP-58 badges were added in the follow-up pass.
- Added glossary, platform parity matrix, ADRs, and wiki lint script in the follow-up maintenance pass.
- Remaining useful protocol pages: NIP-04/NIP-44 encryption helpers, NIP-18 repost/quote repost, and NIP-23 long-form articles.
- A generated cross-reference map is not yet maintained; `index.md` remains the navigation source.

### Lint checklist for future passes

- Search for stale hard-coded platform claims in `AGENTS.md` and `docs/wiki/`.
- Check each NIP claim against at least one source file.
- Ensure new pages are linked from `index.md`.
- Ensure `log.md` has a chronological entry for meaningful doc/code changes.
- Move uncertainty to `Open questions` rather than stating it as fact.

## Source references

- `AGENTS.md`
- `docs/wiki/index.md`
- `docs/wiki/nips/README.md`
- Code references listed in each relevant wiki page.

## Related pages

- [[index]]
- [[nips/README]]
