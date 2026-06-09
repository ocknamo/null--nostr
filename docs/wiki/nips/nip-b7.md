# NIP-B7: Blossom

## Summary

NIP-B7 covers Blossom-related blob storage behavior. In null--nostr, Blossom is the preferred modern upload ecosystem alongside NIP-98 HTTP auth compatibility paths and legacy NIP-96-style endpoints.

## Current behavior

- Android and iOS upload helpers can upload to Blossom-compatible servers.
- Blossom upload auth uses kind 24242 in current code paths.
- iOS settings and avatar fallback paths reference Blossom user server discovery, including kind 10063.
- Web `lib/nostr.js` includes Blossom upload/auth helper paths.

## Kind notes

| kind | Meaning | null--nostr status |
|---:|---|---|
| 10063 | User server list | iOS/settings + upload ecosystem support; Android parity open. |
| 24242 | Blossom mediaserver blob/auth ecosystem | Used by Blossom upload auth paths. |

## Platform notes

### Android

- `ImageUploadUtils.uploadToBlossom()` creates kind 24242 auth.
- Full kind 10063 server-list publishing parity should be checked before claiming Android support.

### iOS

- `ImageUploadService.swift` supports `.blossom` upload targets.
- `AvatarView.swift` resolves hash-addressed Blossom URLs with fallback server behavior.
- Settings can publish/read Blossom user server lists.

### Web

- `lib/nostr.js` supports Blossom upload/auth helper behavior.

## Source references

- `android/app/src/main/kotlin/io/nurunuru/app/data/ImageUploadUtils.kt`
- `ios/NuruNuru/Data/ImageUploadService.swift`
- `ios/NuruNuru/Views/Components/AvatarView.swift`
- `ios/NuruNuru/Views/Screens/MiniAppsView.swift`
- `lib/nostr.js`

## Related pages

- [[README]]
- [[kind-registry]]
- [[nip-98]]
- [[../features/image-upload]]

## Open questions

- Should Android expose Blossom user server list kind 10063 settings to match iOS?
- Should upload settings copy explicitly say Blossom is preferred over legacy NIP-96-style endpoints?
