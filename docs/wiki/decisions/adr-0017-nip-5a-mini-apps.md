# ADR-0017: NIP-5A Mini Apps Use Curated WebView Launch with Safe Manifest Validation

## Status

Accepted — 2026-05-31

## Context

June 2026 introduces NIP-5A mini apps as static sites opened in an in-app WebView. The user delegated the manifest / launch validation details to implementation judgment.

## Decision

Phase 1 NIP-5A mini apps use a conservative launch policy: 2-hop trust graph or curated default list, HTTPS-only start URLs, host/origin validation, explicit native permission sheets for signing/account access, and no private key injection into WebView.

Payment and paid unlock capabilities are disabled in Phase 1. Zap/Lightning can remain support/donation-oriented until a separate payment-rails ADR is accepted.

## Minimum validation rules

1. Entry comes from 2-hop trust graph or curated defaults.
2. URL is HTTPS.
3. Start URL host matches manifest origin.
4. External redirects require confirmation or external browser handoff.
5. Manifest declares name, icon URL, start URL, origin, version, and permissions.
6. No private key injection into WebView.
7. Signing/account access is mediated by native UI.
8. Storage is isolated per origin where possible.
9. Unknown schemes are blocked by default.
10. Payment unlock permissions are disabled in Phase 1.

## Consequences

- Enables a safe mini-app alpha without blocking on monetization.
- Preserves future room for digital content payments.
- Adds implementation work for WebView permission boundaries on Android and iOS.

## Source references

- docs/wiki/strategy/june-2026-roadmap.md
- Nostr Compass NIP-5A: https://nostrcompass.org/ja/topics/nip-5a/
- User decision on 2026-05-31
