# ADR-0013: Remove Relay Feed from Primary UI

## Status

Accepted — 2026-05-31

## Context

The Timeline relay sub-feed exposed users to arbitrary relay content. User observation on 2026-05-31 confirmed that the relay tab was filled with spam and illegal content. This conflicts with null--nostr's culture charter, store-release quality expectations, and the June 2026 plan to move discovery surfaces toward 2-hop trust-graph constraints.

Relay infrastructure is still required for Nostr publishing, NIP-65 relay metadata, search, notifications, and advanced settings. The unsafe part is the primary UI surface that shows an uncurated relay-wide feed.

## Decision

Remove the relay feed from the primary user interface across Android, iOS, and Web.

Keep:

- Relay settings and NIP-65 relay metadata.
- Relay-targeted publishing and NIP-70 protected events.
- Search / notification relay usage.
- Internal relay APIs when needed for non-primary, scoped, or future curated flows.

Remove / disable:

- The Timeline relay tab / relay picker in the main feed UI.
- Background relay-feed prefetch/live-polling used only to populate that UI.
- Desktop dual-column relay feed on Web.

## Consequences

- Reduces exposure to spam and illegal content.
- Simplifies the June Home / News / Mini Apps tab redesign.
- Following feed becomes the safe default social feed until Home tab migration moves it into Home.
- Some legacy ViewModel/repository relay-feed methods may remain temporarily as dead code while later phases refactor Timeline into News.

## Source references

- docs/wiki/strategy/june-2026-roadmap.md
- android/app/src/main/kotlin/io/nurunuru/app/ui/screens/TimelineScreen.kt
- android/app/src/main/kotlin/io/nurunuru/app/ui/components/TimelineComponents.kt
- android/app/src/main/kotlin/io/nurunuru/app/viewmodel/TimelineViewModel.kt
- ios/NuruNuru/Views/Screens/TimelineView.swift
- ios/NuruNuru/ViewModels/TimelineViewModel.swift
- components/TimelineTab.js

## Related pages

- [[strategy/june-2026-roadmap]]
- [[decisions/adr-0016-news-curation-model]]

## Open Questions

- When Timeline becomes News, should the remaining global/recommended timeline code be deleted entirely or repurposed for NIP-23/NIP-32 News?
