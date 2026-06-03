# ADR-0016: News Tab Uses NIP-23 + NIP-32 Recommended Labels in a 2-hop Trust Graph

## Status

Accepted — 2026-05-31

Amended — 2026-06-03: News discovery explicitly uses NIP-32 recommended labels as boost signals for NIP-23 long-form articles.

## Summary

The News tab uses NIP-23 long-form articles (kind 30023) as its primary content type. NIP-32 labels (kind 1985) are used as discovery and ranking signals inside a 2-hop trust graph. In particular, labels that mean recommended / おすすめ can boost article discovery when the labeler is trusted by the user's graph.

This does not reintroduce arbitrary relay-wide feeds. A recommended label is a boost signal, not an unconditional display permission.

## Context

The old relay/timeline surface can expose users to spam and illegal content when arbitrary relay feeds are shown directly. June 2026 rebrands Timeline into News using NIP-23 long-form content and NIP-32 labels.

The initial ADR accepted a 2-hop trust graph where NIP-23 articles are candidates when the author or NIP-32 labeler is inside that graph. On 2026-06-03, the user clarified that News should use NIP-23 and NIP-32 recommended labels to promote content discovery.

## Decision

News uses a 2-hop trust graph: the user's follows plus accounts followed by those follows. NIP-23 articles are candidates when the author or NIP-32 labeler is inside that trust graph. Arbitrary relay-wide article discovery is not a primary surface.

### 2026-06-03 amendment — recommended labels

NIP-32 labels that express recommendation are treated as positive discovery signals for NIP-23 articles.

Initial recognized label namespaces / values:

| Tag pattern | Meaning | Notes |
|---|---|---|
| `L=news` + `l=recommended` | News recommendation | Preferred internal namespace candidate for News discovery. |
| `L=news` + `l=おすすめ` | News recommendation (Japanese) | Accepted for Japanese community usage. |
| `L=content` + `l=recommended` | General content recommendation | Accepted as secondary signal. |
| `L=content` + `l=おすすめ` | General content recommendation (Japanese) | Accepted as secondary signal. |
| `L=birdwatch` | Context / correction labels | Existing support remains; not treated as recommendation. |

Implementation may accept additional aliases after Design Crit, but must not treat every arbitrary NIP-32 label as recommended.

## Candidate / ranking rules

A NIP-23 article may enter News candidate set when at least one of the following is true:

1. The article author is in the user's 1-hop follows.
2. The article author is in the user's 2-hop trust graph.
3. A labeler in the user's 1-hop follows applied a recognized recommended label to the article.
4. A labeler in the user's 2-hop trust graph applied a recognized recommended label to the article.

Recommended-label boosts:

| Signal | Suggested boost | Reason |
|---|---:|---|
| 1-hop author | Highest | User directly follows the author. |
| 1-hop recommended labeler | High | Directly trusted person recommended it. |
| 2-hop author | Medium | Socially nearby author. |
| 2-hop recommended labeler | Medium / low | Discovery signal, but weaker than direct follow. |
| Multiple independent recommended labels | Additive with cap | Avoid single-label dominance. |
| Official curated account label | Boost only | May raise rank, but cannot override safety filters. |

A recommended label must not override mute, block, report, NSFW, or other safety filters.

## User-facing copy

Do not expose NIP-23 / NIP-32 / labeler / trust graph language in the beginner UI.

| Internal concept | User-facing copy candidate |
|---|---|
| NIP-23 article | 記事 |
| recommended label | おすすめ |
| recommended by follow graph | フォロー周辺でおすすめ |
| recommended by followed user | フォロー中の人がおすすめ |
| 2-hop discovery | 近くの人たちのおすすめ |
| no candidates | まだ記事が少ないみたい。フォローが増えると、ここにおすすめが並ぶよ。 |

## Safety rules

- Do not fetch arbitrary relay-wide NIP-23 articles as a primary News surface.
- Do not show all kind 1985 labels as recommendations.
- A recommended label is a boost signal, not display permission.
- Mute / block / report labels always win over recommendation labels.
- Labelers outside the 2-hop trust graph do not boost content in Phase 1.
- Official curated labels may boost ranking but must not be the only discovery path.
- Surface copy must avoid Nostr terminology.

## Current behavior

Code-backed NIP-32 support currently includes Birdwatch/context labels using kind 1985 on Web / Android / iOS helper paths. News recommended-label discovery is a product/design decision documented here and should be implemented separately. Do not claim that recommended-label News ranking is already implemented until source code supports it.

## Consequences

### Positive

- Promotes content discovery without returning to unsafe relay-wide feeds.
- Lets trusted people curate News through Nostr-native labels.
- Fits Japanese UI by exposing the simple word おすすめ while keeping protocol complexity behind the scenes.
- Creates a path for official / community curation without hard central editorial control.

### Negative / risks

- Recommendation labels can become spam if not limited to trusted labelers.
- Label namespace fragmentation may reduce interoperability.
- Ranking may become opaque if boost explanation copy is weak.
- Official curated labels could be perceived as central editorial control if over-weighted.

## Platform notes

### Web

Web already has NIP-32 Birdwatch helpers in `lib/nostr.js`. News recommended-label fetching/ranking should be separate from Birdwatch context display to avoid mixing correction labels and recommendation labels.

### Android

Android defines kind 1985 and publishes Birdwatch labels. News recommended-label ranking should be added to News / repository paths when the News tab implementation begins, not to the old relay feed.

### iOS

iOS defines `NostrKind.label = 1985` and has Birdwatch label helpers. Recommended-label News discovery should preserve iOS guardrails and avoid exposing protocol terms in SwiftUI copy.

## Source references

- `docs/wiki/strategy/june-2026-roadmap.md`
- `docs/wiki/nips/nip-23.md`
- `docs/wiki/nips/nip-32.md`
- `docs/wiki/features/news.md`
- `android/app/src/main/kotlin/io/nurunuru/app/data/NostrRepositoryActions.kt`
- `android/app/src/main/kotlin/io/nurunuru/app/data/models/NostrModels.kt`
- `ios/NuruNuru/Data/NostrRepository+Reactions.swift`
- `ios/NuruNuru/Models/NostrKind.swift`
- `lib/nostr.js`
- User decision on 2026-05-31
- User decision on 2026-06-03: ニュースタブの NIP-23 / NIP-32 でおすすめラベルを活用してコンテンツ発見を促進する。

## Related pages

- [[../strategy/june-2026-roadmap]]
- [[../features/news]]
- [[../nips/nip-23]]
- [[../nips/nip-32]]

## Open questions

- Should the preferred namespace be `news`, `content`, or an app-specific namespace for recommended labels?
- Should Japanese `おすすめ` and English `recommended` both be emitted when the app creates recommendation labels?
- What exact score weights should be used for 1-hop labeler, 2-hop labeler, and official curated labels?
- Should users be able to create recommendation labels directly from the News UI in Phase 1, or should this start read-only?
