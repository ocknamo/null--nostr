# ADR-0002: Native Talk uses Marmot MLS

## Status

Accepted.

## Context

The repository contains NIP-17 DM helpers and models, but native Talk code has moved toward Marmot MLS / WhiteNoise-compatible group messaging.

## Decision

Android and iOS native Talk should be documented and implemented as Marmot MLS-oriented. NIP-17 remains legacy/compatibility support unless code explicitly reintroduces native NIP-17 display.

## Consequences

- Do not treat Web NIP-17 helpers as native Talk parity.
- Kind 1059 in native Talk is often Marmot Welcome delivery, not a user-visible NIP-17 DM.
- Talk changes should update [[features/talk]], [[nips/nip-17]], and [[nips/nip-59]].

## Source references

- `android/app/src/main/kotlin/io/nurunuru/app/data/NostrRepositoryTalk.kt`
- `ios/NuruNuru/Data/NostrRepository+Talk.swift`
- `rust-engine/nurunuru-core/src/mls.rs`
