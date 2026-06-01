# ADR-0016: News Tab Uses 2-hop Trust-Graph Curation

## Status

Accepted — 2026-05-31

## Context

The old relay/timeline surface can expose users to spam and illegal content when arbitrary relay feeds are shown directly. June 2026 rebrands Timeline into News using NIP-23 long-form content and NIP-32 labels.

## Decision

News uses a 2-hop trust graph: the user's follows plus accounts followed by those follows. NIP-23 articles are candidates when the author or NIP-32 labeler is inside that trust graph. Arbitrary relay-wide article discovery is not a primary surface.

## Consequences

- Reduces spam and illegal-content exposure compared with relay-wide feeds.
- Keeps Nostr discovery social rather than centrally editorial.
- Requires follow-list expansion and caching.
- Official curated accounts may be added as boost signals later, but are not required for Phase 1.

## Source references

- docs/wiki/strategy/june-2026-roadmap.md
- docs/wiki/nips/nip-23.md
- User decision on 2026-05-31
