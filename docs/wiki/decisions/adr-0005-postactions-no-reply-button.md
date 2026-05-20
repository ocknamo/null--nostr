# ADR-0005: PostActions has no reply button

## Status

Accepted as current behavior.

## Context

Older docs described PostActions as exactly three buttons. Current Android and iOS code can show bookmark in addition to like/repost/zap, but does not include a reply button in the PostActions row.

## Decision

Document PostActions as like/repost/zap plus optional bookmark, with no reply button. Reply entry points live elsewhere, such as post detail or composer reply flows.

## Consequences

- Do not reintroduce stale “3 buttons only” docs.
- UI parity checks should verify optional bookmark handling and no reply icon in PostActions.

## Source references

- `android/app/src/main/kotlin/io/nurunuru/app/ui/components/PostActions.kt`
- `ios/NuruNuru/Views/Components/PostActions.swift`
- `docs/wiki/ui/android-ios-sync.md`
