# iOS Platform

## Summary

iOS は Swift / SwiftUI / iOS 17+ Observation による native app です。Android との pixel-perfect sync を重視します。

## Main structure

```text
ios/NuruNuru/
  Theme/
  Models/
  Data/
  ViewModels/
  Views/Screens/
  Views/Components/
  Views/Sheets/
  Views/MiniApps/
```

## Important rules

- `NostrRepository` は `actor`。
- ViewModel は `@Observable`。Combine / `ObservableObject` は使わない。
- NIP-46 を外部署名に使う。iOS では NIP-55 を使わない。
- 秘密鍵は Keychain のみ。`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`。
- body text は LINE Seed JP のみ。system font fallback を避ける。
- timeline は `.id(post.event.id)` を使い、entrance animation を避ける。
- image viewer は `.fullScreenCover`。その他は原則 `.sheet`。
- tab bar は `.safeAreaInset(edge: .bottom, spacing: 0)`。

- Uploads support NIP-98 and Blossom auth kind 24242 paths.
- Talk is Marmot MLS oriented; NIP-17 is not the native iOS external signer path and legacy messaging boundaries must be checked in code.
- PostActions includes bookmark when handler is supplied; do not describe it as strictly 3 buttons.

## Source references

- `ios/NuruNuru/`
- `ios/GUARDRAILS.md`
- `ios/project.yml`
- `ios/NuruNuru/Data/`
- `ios/NuruNuru/ViewModels/`

## Related pages

- [[ui/android-ios-sync]]
- [[decisions/adr-0001-ios-observation]]
- [[features/post-composer]]
