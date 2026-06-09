# NIP-71: Video Events / ろくなな

## Summary

The project has a short-video area called ろくなな. Current code uses OpenVine/diVine-compatible short video events, primarily kind 34236, with related NIP-71-style metadata.

## Current behavior

- iOS `RokunanaVideo` describes diVine/OpenVine-compatible NIP-71 short video events.
- Primary discovery/publish kind is 34236, which upstream names “Addressable Short Video Event”.
- Upstream NIP-71 also defines regular video kind 21, portrait short video kind 22, and addressable video kind 34235.
- Acceptable video kinds in iOS parsing include 22, 21, 34235, 34236, and 34237.
- Publishing uses tags such as `d`, `imeta`, `title`, `summary`, `language`, and `client`.
- Android timeline paths include `NostrKind.VIDEO_LOOP` kind 34236 alongside text notes, long-form posts, and reposts.

## Platform notes

### Android

- `NostrKind.ADDRESSABLE_SHORT_VIDEO = 34236`.
- Timeline fetch paths include `VIDEO_LOOP`.
- Video playback uses `VideoPlayer.kt` / ExoPlayer elsewhere in UI.

### iOS

- `NostrRepository+Rokunana.swift` publishes kind 34236 short video events.
- Uploaded media uses existing Blossom/NIP-98 upload paths.
- `RokunanaVideo.swift` parses video metadata and acceptable kinds.

### Web

- `lib/nostr-kinds.js` includes `SHORT_VIDEO: 34236`.

## Source references

- `ios/NuruNuru/Models/RokunanaVideo.swift`
- `ios/NuruNuru/Data/NostrRepository+Rokunana.swift`
- `ios/NuruNuru/Views/Screens/RokunanaView.swift`
- `android/app/src/main/kotlin/io/nurunuru/app/data/models/NostrModels.kt`
- `android/app/src/main/kotlin/io/nurunuru/app/data/NostrRepositoryTimeline.kt`
- `android/app/src/main/kotlin/io/nurunuru/app/ui/components/VideoPlayer.kt`
- `lib/nostr-kinds.js`

## Related pages

- [[features/timeline]]
- [[features/image-upload]]
- [[nips/README]]
