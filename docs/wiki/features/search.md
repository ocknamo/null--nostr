# Search

## Summary

Search は Android で高度検索 operator を解析し、NIP-50 searchnos または standard relay REQ に routing します。

## Operators

| Operator | Example | Backend / behavior |
|---|---|---|
| `#tag` | `#japan` | `#t` tag filter → relay REQ |
| `from:` | `from:npub1...` / `from:user@domain` | authors filter。NIP-05 は async resolve。 |
| `since:` / `until:` | `since:2025-01-01` | timestamp filter。 |
| `-word` | `-spam` | client-side Unicode-aware exclude。 |
| `"phrase"` | `"完全一致"` | client-side exact match。 |
| `filter:image/video/link` | `filter:image` | client-side media URL pattern filter。 |

## Routing

- text present → searchnos NIP-50。structured filters を 1 REQ に combined。
- text absent → standard relay REQ。tag / author / time filters のみ。
- exclude / exact / media は全結果に client-side post-filter。

## Operations MCP

- `scripts/mcp/nurunuru-mcp.mjs` exposes `nip50_search`, `collect_feedback`, `classify_feedback`, and `draft_github_issue` tools for goose / MCP clients.
- Feedback collection uses wss://search.nos.today by default, searches nullnull/via terms, infers platform from client/via metadata, and treats NIP-50 results as public user-signal candidates requiring human review before Issue creation.

## Source references

- `scripts/mcp/nurunuru-mcp.mjs`
- `scripts/mcp/nurunuru-feedback.mjs`
- `android/app/src/main/kotlin/io/nurunuru/app/data/SearchQueryParser.kt`
- `android/app/src/main/kotlin/io/nurunuru/app/data/NostrRepository.kt`

## Related pages

- [[nips/README]]
- [[../operations/feedback-loop]]
- [[platforms/android]]
