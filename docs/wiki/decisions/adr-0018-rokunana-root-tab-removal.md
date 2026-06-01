# ADR-0018: Rokunana Root Tab Removal with Feature Retention

## Status

Accepted — 2026-05-31
Amended — 2026-06-01 (ThemaDAY management meeting)

## Context

June 2026 simplifies the root navigation from five tabs toward Home / Talk / News / Mini Apps. The user decided that the rokunana root tab is unnecessary, but the underlying feature should be kept.

### Amendment (2026-06-01)

The 2026-06-01 ThemaDAY management meeting tightened this decision: during June 2026 the feature will **not** be migrated into Home or Mini Apps. The implementation stays in the repository as **dead-but-preserved** code without a user-facing entry point. Migration target is deferred until after the 4-tab architecture stabilises (post-June).

Rationale: the June monthly objective was confirmed with onboarding as the leading clause, and adding rokunana surfaces into Home/Mini Apps during the same month would compete with onboarding polish and the 4-tab launch.

## Decision

Remove rokunana from the root tab bar. Keep the source code in the repository as **dead-but-preserved** with **no UI entry point in June 2026**. Do not migrate rokunana into Home or Mini Apps during June; the migration target (Home shortcut / Mini App / Settings entry / discard / permanent code-only retention) is deferred.

## Consequences

- Root navigation simplifies to Home / Talk / News / Mini Apps without a rokunana surface.
- Rokunana code remains compilable in the repository and is not deleted.
- No active rokunana UI exists in June 2026 — existing users lose direct access during June; accepted as a known trade-off in exchange for a cleaner 4-tab launch and onboarding focus.
- A future ADR will revisit the migration target after the 4-tab architecture is stable (post-June).
- Wiki and roadmap text must avoid implying that rokunana will be migrated into Home or Mini Apps in June.

## Source references

- docs/wiki/strategy/june-2026-roadmap.md
- User decision on 2026-05-31
