# ADR-0004: Design tokens are source of truth

## Status

Accepted.

## Context

The project targets Web, Android, and iOS with shared visual identity. Manual drift between platforms is easy.

## Decision

`design-tokens/constants.json` is the source of truth for generated constants and tokenized design values. Generated Web/Android/iOS outputs must be synced with `npm run tokens` and checked with `npm run tokens:check`.

## Consequences

- Wiki pages may describe design behavior, but tokens and generated constants win on conflict.
- Meaningful token changes should update [[ui/design-tokens]] and [[platforms/parity-matrix]] if behavior changes.

## Source references

- `design-tokens/constants.json`
- `lib/constants.generated.js`
- `android/app/src/main/kotlin/io/nurunuru/app/data/Constants.kt`
- `ios/NuruNuru/Utilities/Constants.swift`
