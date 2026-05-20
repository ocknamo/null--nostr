# Design Tokens

## Summary

`design-tokens/constants.json` は Web / Android / iOS の色、重み、制限値などの単一の真実の源泉です。

## Generated files

`npm run tokens` により以下へ同期します。

| Platform | Generated file |
|---|---|
| Web | `lib/constants.generated.js` |
| Android | `android/app/src/main/kotlin/io/nurunuru/app/data/Constants.kt` |
| iOS | `ios/NuruNuru/Utilities/Constants.swift` |

## Rules

- デザイン値を変更したら `npm run tokens` を実行する。
- CI / review では `npm run tokens:check` で同期を確認する。
- 手書きで生成物だけを変更しない。

## Source references

- `design-tokens/constants.json`
- `design-tokens/generate.mjs`
- `lib/constants.generated.js`
- `android/app/src/main/kotlin/io/nurunuru/app/data/Constants.kt`
- `ios/NuruNuru/Utilities/Constants.swift`

## Related pages

- [[architecture]]
- [[ui/android-ios-sync]]
