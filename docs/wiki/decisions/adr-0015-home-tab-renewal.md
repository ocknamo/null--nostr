# ADR-0015: Renew Home Tab as the LINE-style Center of the App

## Status

Accepted — 2026-05-31
Amended — 2026-06-02 (Home two-layer structure)

## Context

June 2026 moves null--nostr closer to a LINE-style information architecture. The current root navigation separates Home, Timeline, and Mini Apps in ways that scatter profile/account state, following feed, settings, and experimental features.

The user chose to follow LINE Home renewal direction, move the current Timeline following feed into Home, remove rokunana from root navigation while keeping its code in the repository (without a June UI entry point), and later rebrand Timeline into News.


On 2026-06-02, the user tightened the Home direction after confirming that relay-feed removal and the current iOS Rust FFI scope were already complete. Home should now follow LINE Home renewal 2026 more directly: existing profile, my posts, and likes move behind a Home-header account/profile icon, while the Home body becomes a two-layer surface: **アクティビティ** and **コンテンツ**. The existing Timeline following feed moves into **コンテンツ**.

## Decision

Renew Home as the central tab with a LINE Home renewal 2026-inspired structure.

Home has two distinct areas:

1. **Header account/profile icon** — contains the existing profile surface, my posts list, and likes list. This keeps personal/account surfaces reachable without making the Home body a profile dashboard.
2. **Body two-layer structure** — **アクティビティ** and **コンテンツ**.

The existing Timeline following feed moves into **コンテンツ**. It must remain follow-graph based and must not mix in uncurated relay-wide content. **アクティビティ** may contain notifications, reactions, replies, mentions, or account activity, but must not become a relay-wide feed replacement.

Settings mini-apps such as badge, emoji, zap, relay, cache, mute, and event backup may remain Home/Home-settings responsibilities, but sensitive settings must follow platform guardrails.

**Note (2026-06-01 amendment)**: The rokunana feature is **not** migrated into Home in June 2026.
Per ADR-0018 amendment, the rokunana code stays in the repository as dead-but-preserved without a user-facing entry point in June. Future migration target is deferred.

## Consequences

- Home becomes the primary activation/retention surface.
- The root tab bar can simplify toward Home / Talk / News / Mini Apps.
- Existing Timeline following-feed code should migrate into Home **コンテンツ** while preserving pagination, stable identity, PostActions rules, and no-entrance-animation constraints.
- Existing profile / my posts / likes move behind a Home-header account/profile icon.
- The **アクティビティ** layer needs a bounded first data source; it must not recreate a relay-wide feed.
- Settings mini-apps need a migration plan so Mini Apps can focus on NIP-5A apps.
- Rokunana is intentionally excluded from June Home scope; its code-only retention is tracked in ADR-0018.

## Source references

- docs/wiki/strategy/june-2026-roadmap.md
- docs/wiki/strategy/themaday-2026-06-02-product-eng-design.md
- LINE Home renewal 2026: https://guide.line.me/ja/update/home-renewal2026.html
- android/app/src/main/kotlin/io/nurunuru/app/ui/screens/HomeScreen.kt
- ios/NuruNuru/Views/Screens/HomeView.swift
- components/HomeTab.js

## Related pages

- [[strategy/june-2026-roadmap]]
- [[strategy/themaday-2026-06-02-product-eng-design]]
- [[decisions/adr-0013-relay-feed-removal]]
- [[decisions/adr-0018-rokunana-root-tab-removal]]

## Open Questions

- What is the minimal first implementation of the **アクティビティ** layer: notifications, reactions, replies, mentions, account activity, or a subset?
- Should the header account/profile icon include settings immediately, or keep settings as a separate gear while profile / my posts / likes move behind the icon?
- (Deferred) Post-June rokunana migration target: Home shortcut / NIP-5A Mini App / Settings entry / permanent code-only retention. See ADR-0018 amendment.
