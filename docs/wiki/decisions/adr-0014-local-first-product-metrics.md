# ADR-0014: Defer Local-first Product Metrics; Use Manual QA for June Onboarding Work

## Status

Deferred — 2026-05-31

## Summary

Local-first product metrics remain a valid future option, but they are **not necessary for June 2026 Phase 1**.

The June plan is dominated by UI / information-architecture changes: onboarding improvement, Home renewal, Timeline → News rebranding, NIP-5A Mini Apps, and relay-feed removal. Adding cross-platform metrics now would create implementation and validation overhead that is not justified while the product is still being reshaped and the maintainer will perform direct real-device testing.

## Context

The original P1 proposal was to add device-local counters such as:

- onboarding started / completed
- first post completed
- image upload success / failure
- last active at / active days

This was designed as a privacy-first alternative to external analytics: no telemetry, no server upload, no Nostr events.

After review, the user clarified that they will perform real-device testing directly and questioned whether local-first metrics are excessive at this stage.

## Decision

Do **not** implement local-first metrics in June Phase 1.

Replace P1 with **Manual QA + real-device feedback operation**:

- The maintainer's Android / iOS / Web real-device testing is treated as the primary source of product feedback.
- Use a short checklist for onboarding, posting, Home, News, Mini Apps, and relay-feed removal.
- Record qualitative findings in ThemaDAY / Design Crit notes instead of adding counters to product code.
- Revisit metrics only if manual QA becomes insufficient or if there is a clear user-facing reason to show activity counters.

## Manual QA checklist

### Onboarding

- New registration completes.
- Passkey login works.
- Nsec / external signer paths still work where supported.
- Registration leads naturally into the app without bouncing back to Login.
- First-post guidance is understandable.

### Posting

- Text post succeeds.
- Image post succeeds.
- Image upload failure message is understandable.
- 140-character limit behaves correctly.
- Reply / quote flows are not broken by tab changes.

### Home

- Follow feed migration feels natural.
- Profile / login state is understandable.
- Settings entry is discoverable.
- Rokunana retained feature entry is not lost.

### News

- Relay-wide feed is not shown.
- NIP-23 long-form content is the core surface.
- NIP-32 labels and 2-hop trust graph reduce spam exposure.

### Mini Apps

- NIP-5A static-site / WebView app opens safely.
- Unknown redirects and unsafe schemes do not feel silent or dangerous.
- Private keys are never injected into WebView.
- Signing/account access remains explicitly mediated by native UI.

## Consequences

- Reduces scope and implementation risk for June.
- Keeps focus on tab architecture and safety work.
- Avoids adding product counters that may feel unnecessary or philosophically ambiguous.
- Leaves a clear path to reintroduce local-first metrics later if real usage demands it.

## Source references

- docs/wiki/strategy/june-2026-roadmap.md
- docs/wiki/strategy/themaday-2026-05-31-week-review.md
- User decision on 2026-05-31: local-first metrics implementation is likely excessive because the maintainer will perform real-device testing.

## Related pages

- [[strategy/june-2026-roadmap]]
- [[decisions/adr-0013-relay-feed-removal]]
- [[decisions/adr-0015-home-tab-renewal]]

## Open Questions

- Should manual QA findings be stored in weekly ThemaDAY notes or separate Design Crit notes?
- If metrics are revisited later, should they remain purely local or become opt-in exportable JSON?
