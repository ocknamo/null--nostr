# ThemaDAY 2026-05-28 — Partnerships, External Collaboration, Developer Programs

## Summary

2026-05-28 の ThemaDAY では、ぬるぬるが **and other stuff の Nostr Compass #24** に取り上げられ、公開前レビューにも参加したことを、外部提携・開発者向け施策の重要なシグナルとして記録する。

この出来事は単なる露出ではなく、次の3点を示す。

1. ぬるぬるが Nostr ecosystem 内でレビュー対象になるだけの外部可視性を持ち始めた。
2. 記事公開前レビューにより、外部メディアとの信頼関係を壊さず、事実確認と文脈補正ができる運用が始まっている。
3. 今後の外部提携・開発者向け施策は、短期の流入獲得ではなく、Nostr ecosystem の相互運用性・品質・文化を高める形で設計する必要がある。

結論: パートナーシップ施策は「配信面を増やす」ではなく、**信頼できる外部文脈で、ぬるぬるの思想・実装・開発者接点を正しく伝える**ことを主目的にする。

## Current behavior

- ぬるぬるは Web / Android / iOS / Rust core を持つ Nostr client として開発されている。
- Nostr Compass #24 で取り上げられたこと、公開前レビューをしたことは、ユーザーから明示された外部メディア接点である。
- docs/wiki/ は ThemaDAY の判断・KPI・Open Questions を蓄積する company world model として使う方針になっている。

## Inputs reviewed

- User-provided ThemaDAY note on 2026-05-28:
  - “Thema DAY パートナーシップ　外部提携、開発者向け施策”
  - “今日はand other stuffのNostr Compass #24にぬるぬるが取り上げられ、記事の公開前にレビューもしました。”
- Nostr event link:
  - <https://njump.me/nevent1qqszz7ucm3jheef58vzvnrzddvvw4knus86pnjckp4rmf69ut90u3fczypm4j48hx9q3yjy6fg57c6ftwguxl4sten4sxzx5yvgpa2tec4agqrn55qa>
- GitHub PR:
  - <https://github.com/andotherstuff/nostr-compass/pull/95>

## Strategic interpretation

### 1. External coverage is a trust surface

Nostr Compass coverage should be treated as a **trust surface**, not only as marketing.

Good outcomes:

- readers understand what ぬるぬる is trying to protect: やわらかさ, privacy, distribution freedom, and Japanese community context;
- ecosystem contributors can verify the project through source code, NIP support notes, and platform docs;
- external writers can ask for fact checks without needing private project knowledge;
- review participation corrects factual errors while preserving editorial independence.

Risky outcomes:

- coverage is interpreted as a broad endorsement of every current implementation detail;
- ぬるぬる starts optimizing roadmap for external article attention rather than user signals;
- partnership language creates expectations of exclusive integrations or platform dependency;
- culture/copy is flattened into generic “Nostr app” positioning.

### 2. Pre-publication review is a lightweight partnership pattern

The Nostr Compass #24 review suggests a repeatable external collaboration pattern:

1. external party drafts coverage / integration / documentation;
2. ぬるぬる reviews for factual accuracy, safety, and cultural fit;
3. editorial or implementation ownership remains with the external party;
4. ぬるぬる records learnings and follow-up actions in docs/wiki/;
5. any product change still follows normal PR / Design Crit / release guardrails.

This pattern is compatible with the project culture because it avoids both control capture and passive misrepresentation.

### 3. Developer initiatives should reduce integration friction

Developer-facing work should prioritize clarity and interoperability over more features.

Near-term developer surfaces:

| Surface | Purpose | Next useful improvement |
|---|---|---|
| docs/wiki/nips/README.md | NIP support map | Keep implementation status precise and code-backed. |
| docs/wiki/architecture.md | Cross-platform mental model | Make Web / Android / iOS / Rust responsibilities easy to cite. |
| docs/wiki/platforms/rust-engine.md | Shared core + UniFFI context | Clarify which APIs are stable enough for external discussion. |
| docs/wiki/operations/feedback-loop.md | Feedback-to-Issue loop | Route external reports into triage without losing human review. |
| GitHub Issues / PRs | Contributor entry point | Label small, bounded tasks that do not require private context. |

Do not make developer-only tooling the center of the product week unless it directly improves user trust, contribution quality, or ecosystem interoperability.

## Partnership policy for now

External partnership is allowed when it satisfies all of the following:

1. **Non-exclusive** — no integration should make ぬるぬる dependent on one relay, store, media outlet, or vendor.
2. **Source-verifiable** — claims about protocol support, security, and platform behavior must be checkable in source or wiki references.
3. **Culture-preserving** — Japanese copy tone, やわらかさ, and “ぬるるは住人” doctrine are not overwritten by generic SaaS language.
4. **User-benefiting** — the collaboration improves onboarding, trust, interoperability, distribution freedom, or feedback quality.
5. **Human-reviewed** — final merge, release, signing, secrets, and cultural judgment remain human-approved.

## Follow-up actions

### External collaboration

- Keep a short external-review checklist for future article / podcast / integration reviews:
  - factual accuracy;
  - unsupported NIP claims;
  - security/privacy claims;
  - platform availability;
  - links to canonical source pages;
  - cultural/copy tone.
- After Nostr Compass #24 is public/final, extract concrete feedback or misunderstandings into Issues or Open Questions.
- Decide whether public “press / ecosystem references” should live in the wiki, README, or a separate website page.

### Developer initiatives

- Ensure contributor-facing docs point to:
  - architecture overview;
  - NIP support table;
  - platform guardrails;
  - culture principles and not-doing list;
  - safe feedback loop boundaries.
- Create or curate small external-contributor tasks only when they have:
  - clear source references;
  - no secret/signing/release access;
  - bounded scope;
  - test or verification path.
- Prefer PR review comments that teach project constraints over one-off correction.

### ThemaDAY operating cadence

- Treat external mentions as weekly learning inputs, not victory metrics by themselves.
- Record whether a mention produced:
  - installs;
  - first posts;
  - developer questions;
  - PRs / Issues;
  - NIP/interoperability feedback;
  - cultural misunderstanding to correct.

## Platform notes

### Web

External links should point to canonical Web surfaces where possible, including /p/<npub>, /e/<event-id>, docs/wiki pages, and README. Do not expose private keys or internal signer state while improving share/landing behavior.

### Android / iOS

Coverage may increase first-launch traffic. Production-quality onboarding, passkey/nsec fallback behavior, first post, image upload, and share routing remain the priority before adding new partnership-specific features.

### Rust Engine

If external developers ask about reusable core/FFI behavior, respond from source-backed docs only. Do not promise Rust API stability beyond what is currently implemented and documented.

## Source references

- AGENTS.md
- docs/wiki/strategy/themaday-2026-05-25.md
- docs/wiki/strategy/nuruh-ip-2026-05-28.md
- docs/wiki/operations/feedback-loop.md
- docs/wiki/nips/README.md
- Nostr Compass #24 Nostr event: <https://njump.me/nevent1qqszz7ucm3jheef58vzvnrzddvvw4knus86pnjckp4rmf69ut90u3fczypm4j48hx9q3yjy6fg57c6ftwguxl4sten4sxzx5yvgpa2tec4agqrn55qa>
- and other stuff / Nostr Compass PR #95: <https://github.com/andotherstuff/nostr-compass/pull/95>
- User-supplied ThemaDAY note on 2026-05-28

## Related pages

- [[themaday-2026-05-25]]
- [[nuruh-ip-2026-05-28]]
- [[../operations/feedback-loop]]
- [[../nips/README]]
- [[../culture/principles]]
- [[../culture/not-doing]]
- [[../culture/copy-style]]
- [[../decisions/adr-0011-nuruh-ip-doctrine]]

## Open Questions

- What exact claims about ぬるぬる were included in the final Nostr Compass #24 article after review?
- Did the Nostr Compass #24 mention create measurable installs, first posts, developer questions, Issues, or PRs?
- Should ぬるぬる maintain a public “external coverage / ecosystem references” page?
- Which developer-facing docs are currently most confusing to outside contributors?
