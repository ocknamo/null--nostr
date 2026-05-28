# NIP-50: Search Capability

## Summary

NIP-50 search is used for text search across Nostr events. In null--nostr it supports product search features and the new nurunuru feedback loop MCP.

## Current behavior

- Android search parses structured operators and routes text-present queries to searchnos / NIP-50.
- The feedback automation MCP builds NIP-50 filters with search, kinds, limit, optional time bounds, authors, and tag filters.
- The MCP defaults to wss://search.nos.today and kind 1 notes for public feedback collection.
- Default feedback queries are ぬるぬる, #ぬるぬるはじめました, nullnull Android, nullnull iOS, nullnull, via nullnull Android, via nullnull iOS, and via nullnull.
- via values inside JSON content may be discoverable if the NIP-50 relay indexes the content string. via or client metadata stored only in tags may not be directly searchable, so the MCP also parses retrieved events' client / via tags and JSON metadata during classification.
- MCP search results are classified into feedback labels and GitHub Issue drafts; search results are not treated as authoritative without human review.

## Platform notes

### Android

- SearchQueryParser.kt parses #tag, from:, since:, until:, -word, exact phrases, and filter:image/video/link before repository routing.
- Text-present advanced searches use NIP-50 searchnos routing; text-absent structured queries use standard relay REQ.

### Web / Operations MCP

- scripts/mcp/nurunuru-feedback.mjs implements a small NIP-50 relay query client over WebSocket.
- scripts/mcp/nurunuru-mcp.mjs exposes the search path as MCP tools for goose and other MCP clients.

## Source references

- android/app/src/main/kotlin/io/nurunuru/app/data/SearchQueryParser.kt
- android/app/src/main/kotlin/io/nurunuru/app/data/NostrRepository.kt
- scripts/mcp/nurunuru-feedback.mjs
- scripts/mcp/nurunuru-mcp.mjs
- src/__tests__/mcp/nurunuru-feedback.test.ts

## Related pages

- [[README]]
- [[../features/search]]
- [[../operations/feedback-loop]]

## Open questions

- NIP-50 relay behavior is relay-specific; fallback search relays and query compatibility tests should be added as usage grows.
- Feedback collection currently uses public posts only; private support requests and store reviews need separate ingestion paths.
