# NIP-32: Labels

## Summary

NIP-32 uses kind 1985 label events. null--nostr currently has code-backed support for Birdwatch/context labels and now documents a News discovery design that uses recommended / おすすめ labels as boost signals for NIP-23 articles.

Important: Birdwatch/context labels are implemented helper paths today; News recommended-label ranking is a documented product decision and implementation target, not yet claimed as fully implemented unless source code adds it.

## Current behavior

- Android defines `NostrKind.LABEL = 1985` and can publish Birdwatch labels through `publishBirdwatchLabel`.
- iOS defines `NostrKind.label = 1985` and has Birdwatch label publishing/fetch helpers.
- Web `lib/nostr.js` has `createBirdwatchLabel`, `fetchBirdwatchLabels`, `hasUserBirdwatchLabel`, and `rateBirdwatchLabel` helpers.
- Existing Birdwatch labels use namespaces such as `birdwatch` / `social.birdwatch` and context values like misleading, missing_context, factual_error, outdated, satire.
- News recommended-label use is specified in ADR-0016 and [[../features/news]].

## Label namespaces in null--nostr

| Namespace | Values | Current use |
|---|---|---|
| birdwatch | misleading / missing_context / factual_error / outdated / satire | Context/correction labels. Implemented helper paths. |
| social.birdwatch | same semantic family | Compatibility accepted on iOS fetch path. |
| news | recommended / おすすめ | Proposed preferred namespace for News recommendation labels. |
| content | recommended / おすすめ | Proposed secondary namespace for general content recommendation labels. |

## News recommended labels

For News, a recommendation label is a kind 1985 event that references a NIP-23 article and carries a recognized recommendation namespace/value pair. The labeler must be inside the user's 1-hop or 2-hop trust graph for the label to boost discovery in Phase 1.

Recommended labels are boost signals, not display permission. Mute, block, report, and safety filters override them.

## Example tag shapes

These are documentation examples, not a claim that all clients emit them today.

| Purpose | Tags |
|---|---|
| Recommend article in News namespace | `L=news`, `l=recommended,news`, `e=<article event id>` or `a=30023:<pubkey>:<d>` |
| Recommend article in Japanese | `L=news`, `l=おすすめ,news`, `e=<article event id>` or `a=30023:<pubkey>:<d>` |
| Birdwatch context | `L=birdwatch`, `l=missing_context,birdwatch`, `e=<event id>` |

Implementation should prefer addressable `a` tags for kind 30023 coordinates when available, while accepting `e` references for compatibility.

## Platform notes

### Android

- Source references: `NostrModels.kt` and `NostrRepositoryActions.kt`.
- Existing function `publishBirdwatchLabel` should not be repurposed silently for News recommendations; create separate repository/API paths if recommendation publishing is added.

### iOS

- Source references: `NostrKind.swift` and `NostrRepository+Reactions.swift`.
- Existing Birdwatch fetch allows Birdwatch namespaces. News recommendation label fetching should use explicit recognized namespaces.

### Web

- Source reference: `lib/nostr.js`.
- Existing Birdwatch helpers should remain separate from News recommendation labels.

## Source references

- `android/app/src/main/kotlin/io/nurunuru/app/data/models/NostrModels.kt`
- `android/app/src/main/kotlin/io/nurunuru/app/data/NostrRepositoryActions.kt`
- `ios/NuruNuru/Models/NostrKind.swift`
- `ios/NuruNuru/Data/NostrRepository+Reactions.swift`
- `lib/nostr.js`
- `docs/wiki/decisions/adr-0016-news-curation-model.md`
- `docs/wiki/features/news.md`

## Related pages

- [[README]]
- [[nip-23]]
- [[../features/news]]
- [[../decisions/adr-0016-news-curation-model]]

## Open questions

- Should null--nostr emit both Japanese and English recommendation labels for interoperability?
- Should the recommendation namespace be standardized with other Nostr clients before write support ships?
- Should recommended labels target `a` coordinates only, or both `a` and `e` references?
