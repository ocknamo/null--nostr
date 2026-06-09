# NIP-5A: Static Websites / nsites

## Summary

Upstream NIP-5A defines static website manifests, also called nsites. It is distinct from null--nostr's Scroll mini-app protocol, which currently uses project/ecosystem kinds 1227 and 10027.

## Current behavior

- null--nostr strategy and Mini Apps docs reference NIP-5A as the safety-first WebView/static-site direction for mini apps.
- Current code evidence for Scroll mini-app definitions/favorites is separate from official NIP-5A nsite manifests.
- No full code-backed nsite launch/publish parity is claimed in this audit.

## Upstream kind notes

| kind | Upstream meaning | null--nostr note |
|---:|---|---|
| 15128 | Root nsite manifest | Official NIP-5A; not the same as Scroll kind 1227. |
| 34128 | Legacy nsite manifest | Upstream marks deprecated. |
| 35128 | Named nsite manifest | Official NIP-5A named site. |

## Platform notes

### Android

- `ScrollRunner.kt` and `ScrollsApp.kt` currently describe “NIP-A5 Scroll” mini-app behavior. That naming should be treated as ecosystem/project-specific unless the implementation is migrated to official NIP-5A nsites.

### iOS

- `ScrollsView.swift` participates in the current Scroll mini-app surface. Official NIP-5A nsite parity is not claimed.

### Web

- Mini-app/static-site execution should follow ADR-0017 safety boundaries before any official NIP-5A nsite support is claimed.

## Source references

- `android/app/src/main/kotlin/io/nurunuru/app/ui/miniapps/ScrollRunner.kt`
- `android/app/src/main/kotlin/io/nurunuru/app/ui/miniapps/ScrollsApp.kt`
- `android/app/src/main/kotlin/io/nurunuru/app/data/NostrRepositoryScrolls.kt`
- `ios/NuruNuru/Views/MiniApps/ScrollsView.swift`
- `docs/wiki/decisions/adr-0017-nip-5a-mini-apps.md`
- `docs/wiki/strategy/june-2026-roadmap.md`

## Related pages

- [[README]]
- [[kind-registry]]
- [[../features/relay-management]]

## Open questions

- Should the current Scroll mini-app copy be renamed away from “NIP-A5” until it implements official NIP-5A nsite manifests?
- Which platform should first validate kind 15128 / 35128 nsite launch behavior?
