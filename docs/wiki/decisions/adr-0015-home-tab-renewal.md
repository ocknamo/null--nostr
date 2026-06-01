# ADR-0015: Renew Home Tab as the LINE-style Center of the App

## Status

Accepted — 2026-05-31

## Context

June 2026 moves null--nostr closer to a LINE-style information architecture. The current root navigation separates Home, Timeline, and Mini Apps in ways that scatter profile/account state, following feed, settings, and experimental features.

The user chose to follow LINE Home renewal direction, move the current Timeline following feed into Home, remove rokunana from root navigation while keeping its code in the repository (without a June UI entry point), and later rebrand Timeline into News.

## Decision

Renew Home as the central tab.

Move into Home or Home settings:

- Following feed currently shown under Timeline.
- Profile card and login/account state.
- Settings mini-apps such as badge, emoji, zap, relay, cache, mute, and event backup settings.

Home feed must remain follow-graph based and must not mix in uncurated relay-wide content.

**Note (2026-06-01 amendment)**: The rokunana feature is **not** migrated into Home in June 2026.
Per ADR-0018 amendment, the rokunana code stays in the repository as dead-but-preserved without a user-facing entry point in June. Future migration target is deferred.

## Consequences

- Home becomes the primary activation/retention surface.
- The root tab bar can simplify toward Home / Talk / News / Mini Apps.
- Existing Timeline code can be migrated in stages: first remove relay feed, then move following feed to Home, then rebrand remaining Timeline surface to News.
- Settings mini-apps need a migration plan so Mini Apps can focus on NIP-5A apps.
- Rokunana is intentionally excluded from June Home scope; its code-only retention is tracked in ADR-0018.

## Source references

- docs/wiki/strategy/june-2026-roadmap.md
- LINE Home renewal 2026: https://guide.line.me/ja/update/home-renewal2026.html
- android/app/src/main/kotlin/io/nurunuru/app/ui/screens/HomeScreen.kt
- ios/NuruNuru/Views/Screens/HomeView.swift
- components/HomeTab.js

## Related pages

- [[strategy/june-2026-roadmap]]
- [[decisions/adr-0013-relay-feed-removal]]
- [[decisions/adr-0018-rokunana-root-tab-removal]]

## Open Questions

- Should Home show local-first metrics (ADR-0014) directly or keep them under settings?
- (Deferred) Post-June rokunana migration target: Home shortcut / NIP-5A Mini App / Settings entry / permanent code-only retention. See ADR-0018 amendment.
