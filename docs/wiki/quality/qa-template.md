# Manual QA Template — YYYY-MM-DD

## Summary

Short summary of the real-device QA session. This template supports ADR-0014: June Phase 1 uses manual qualitative QA instead of local-first product counters.

## Session metadata

| Field | Value |
|---|---|
| Date | YYYY-MM-DD |
| Tester / hat | Quality / NPS Lead |
| Platform | Android / iOS / Web |
| App version / build |  |
| Device / OS |  |
| Network | Wi-Fi / cellular / offline / constrained |

## Scope

- [ ] Onboarding: new registration, passkey login, nsec/external signer where supported, first-post guidance
- [ ] Posting: text post, image post, failure message, 140-char limit, reply/quote paths
- [ ] Home: follow feed migration, profile/login state, settings entry
- [ ] News: no relay-wide feed, NIP-23 long-form focus, NIP-32/2-hop trust graph behaviour
- [ ] Mini Apps: NIP-5A static-site open, unsafe navigation handling, no private-key injection, native permission mediation
- [ ] Release train gates: relevant AND/IOS/WEB/XPF checklist items

## Findings

| ID | Severity | Area | Finding | Expected | Actual | Owner hat | Status |
|---|---|---|---|---|---|---|---|
| QA-YYYYMMDD-01 | P1/P2/P3 |  |  |  |  |  | TODO |

## 5 Whys / Kaizen notes

Use this only for P1/P2 regressions or repeated friction.

1. Why?
2. Why?
3. Why?
4. Why?
5. Why?

## Decisions / Follow-up

- [ ] Add issue / PR / ADR if needed
- [ ] Update ThemaDAY or Design Crit notes if this affects June direction

## Source references

- docs/wiki/decisions/adr-0014-local-first-product-metrics.md
- docs/wiki/strategy/june-2026-roadmap.md
- docs/wiki/strategy/themaday-2026-06-01-management.md
