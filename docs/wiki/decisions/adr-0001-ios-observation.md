# ADR-0001: iOS ViewModel は Observation を使う

## Status

Accepted

## Context

null--nostr の iOS app は iOS 17.0 以上を minimum deployment target とします。SwiftUI の新しい Observation framework を利用できます。

## Decision

iOS ViewModel は `@Observable` を使います。Combine / `ObservableObject` は原則使いません。

## Consequences

- ViewModel は iOS 17+ Observation framework 前提で実装する。
- `ObservableObject` や Combine dependency を追加しない。
- Android の ViewModel / Repository 構造と責務の対応を保ちやすくする。

## Source references

- `AGENTS.md`
- `ios/NuruNuru/ViewModels/`
- `ios/project.yml`

## Related pages

- [[platforms/ios]]
