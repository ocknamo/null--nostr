# News Tab — NIP-23 Articles and NIP-32 Recommended Labels

## Summary

The News tab is the rebranded Timeline discovery surface for June 2026. It focuses on NIP-23 long-form articles (kind 30023) and uses NIP-32 labels (kind 1985) as trust-scoped discovery signals.

The key product decision is to use NIP-32 labels that mean recommended / おすすめ to promote article discovery inside a 2-hop trust graph. This keeps discovery social and Nostr-native while avoiding unsafe relay-wide feeds.

## Current behavior

- The June roadmap defines News as NIP-23 long-form content plus NIP-32 labels.
- ADR-0016 accepts 2-hop trust-graph curation for News.
- NIP-23 rendering is code-backed on native paths documented in [[../nips/nip-23]].
- NIP-32 kind 1985 helpers exist primarily for Birdwatch/context labels today.
- Recommended-label News ranking is a product/design decision and should not be described as fully implemented until source code supports it.

## Discovery model

News candidate articles are NIP-23 events. Candidates are discovered through a 2-hop trust graph and recommendation labels.

### Candidate sources

| Source | Include? | Notes |
|---|---|---|
| 1-hop author | Yes | User follows the author. |
| 2-hop author | Yes | Author is followed by someone the user follows. |
| 1-hop labeler recommended an article | Yes | Strong recommendation signal. |
| 2-hop labeler recommended an article | Yes | Discovery signal, lower than 1-hop. |
| Relay-wide NIP-23 stream | No | Not a primary News surface. |
| Official curated label | Boost only | Cannot override safety filters. |

## Recommended label semantics

Initial accepted labels:

| Namespace | Value | Meaning |
|---|---|---|
| news | recommended | Recommended article |
| news | おすすめ | Recommended article (Japanese) |
| content | recommended | General content recommendation |
| content | おすすめ | General content recommendation (Japanese) |

Birdwatch labels (`L=birdwatch`) are context/correction labels and are not treated as recommendation labels.

## Ranking outline

Ranking should be deterministic and explainable enough for manual QA.

1. Start with NIP-23 candidates from 1-hop / 2-hop authors.
2. Fetch recognized recommendation labels from 1-hop / 2-hop labelers.
3. Apply positive boosts for trusted recommendation labels.
4. Cap additive boosts so one coordination cluster cannot dominate the feed.
5. Apply mute / block / report / unsafe filters last and let them win.
6. Deduplicate by article coordinate / event id.

## User-facing copy

| UI area | Copy candidate |
|---|---|
| Tab name | ニュース |
| Section title | おすすめの記事 |
| Label chip | おすすめ |
| Reason line, 1-hop | フォロー中の人がおすすめ |
| Reason line, 2-hop | 近くの人たちのおすすめ |
| Empty state | まだ記事が少ないみたい。フォローが増えると、ここにおすすめが並ぶよ。 |
| Error state | 記事を読み込めなかった。電波かリレーの調子かも。もう一度ためしてみる? |

Do not show NIP-23, NIP-32, kind 30023, kind 1985, labeler, relay, or trust graph in beginner-facing copy.

## Manual QA checklist

| Check | Expected |
|---|---|
| No relay-wide article feed | News does not show arbitrary relay-wide NIP-23 stream. |
| 1-hop author article | Appears without recommendation label. |
| 2-hop author article | Appears with lower priority than 1-hop. |
| 1-hop recommended label | Boosts article ranking and shows human copy. |
| 2-hop recommended label | Boosts, but weaker than 1-hop labeler. |
| Birdwatch label | Does not boost as recommendation. |
| Muted author | Hidden even if recommended. |
| Reported unsafe content | Hidden or deprioritized according to safety rules. |
| Empty graph | Shows calm empty state, not protocol explanation. |

## Platform notes

### Web

Web implementation should keep News recommendation labels separate from Birdwatch helper UI in `lib/nostr.js`. Any HTML rendering must continue to use existing sanitization rules.

### Android

Android implementation should build on repository/viewmodel boundaries and avoid reintroducing relay tab behavior. Compose copy must use Japanese daily language and preserve performance constraints.

### iOS

iOS implementation should keep SwiftUI copy aligned with Android and avoid exposing protocol terms. Use stable list identity for articles.

## Source references

- `docs/wiki/decisions/adr-0016-news-curation-model.md`
- `docs/wiki/strategy/june-2026-roadmap.md`
- `docs/wiki/nips/nip-23.md`
- `docs/wiki/nips/nip-32.md`
- `android/app/src/main/kotlin/io/nurunuru/app/data/models/NostrModels.kt`
- `android/app/src/main/kotlin/io/nurunuru/app/data/NostrRepositoryActions.kt`
- `ios/NuruNuru/Models/NostrKind.swift`
- `ios/NuruNuru/Data/NostrRepository+Reactions.swift`
- `lib/nostr.js`

## Related pages

- [[../decisions/adr-0016-news-curation-model]]
- [[../nips/nip-23]]
- [[../nips/nip-32]]
- [[../strategy/june-2026-roadmap]]
- [[../culture/copy-style]]

## Open questions

- Should News initially be read-only for recommendation labels, or should users be able to mark articles as recommended from the UI?
- What scoring weights should be used for 1-hop and 2-hop recommended labelers?
- How many labelers should be shown in the reason line, if any?
- Should official curated labels use the same namespace as community labels or a separate namespace?
