# Decisions

## Summary

This directory stores lightweight Architecture Decision Records (ADRs). Use ADRs for decisions that affect architecture, platform parity, security, protocols, or long-term maintenance.

## Decision index

| ADR | Decision |
|---|---|
| [[adr-0001-ios-observation]] | iOS ViewModels use iOS 17+ Observation. |
| [[adr-0002-native-talk-uses-marmot-mls]] | Native Talk is Marmot MLS-oriented; NIP-17 is legacy/compatibility. |
| [[adr-0003-ios-external-signing-uses-nip46]] | iOS external signing uses NIP-46, not NIP-55. |
| [[adr-0004-design-tokens-are-source-of-truth]] | Design tokens are source of truth for generated constants. |
| [[adr-0005-postactions-no-reply-button]] | PostActions has no reply button and may include optional bookmark. |
| [[adr-0006-web-rust-bridge-is-stub]] | Web Rust bridge is currently stubbed; Web Nostr operations use JS modules. |

## ADR convention

Each ADR should include:

- Status
- Context
- Decision
- Consequences
- Source references

## Related pages

- [[../index]]
- [[../architecture]]
## Source references

- `AGENTS.md`
- ADR files in `docs/wiki/decisions/`

