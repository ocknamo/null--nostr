# Image Upload

## Summary

Image upload supports nostr.build, share.yabu.me/yabu.me, and Blossom-compatible servers. Upload authentication uses NIP-98 for HTTP upload endpoints and Blossom/BUD-03 kind 24242 auth for Blossom paths.

## Current behavior

- Composer image uploads are performed off the main thread.
- Android composer uploads multiple images in parallel using `async { }` inside `withContext(Dispatchers.IO)`.
- iOS routes uploads through `ImageUploadService` / repository helpers based on `prefs.uploadServer`.
- Upload server settings include Blossom defaults and compatibility with legacy NIP-96-style targets.
- iOS settings can publish/read Blossom user server lists (`kind:10063`) for BUD-03-style server discovery.
- Renderers handle media URLs from content and NIP-92 `imeta` tags.

## Platform notes

### Android

- `PostModal.kt` performs parallel upload before publishing.
- `ImageUploadUtils.kt` contains nostr.build / yabu.me / Blossom upload helpers.
- Blossom upload creates auth event kind 24242.
- nostr.build and yabu.me paths attempt NIP-98 auth.

### iOS

- `ImageUploadService.swift` supports `.nostrBuild`, `.yabuMe`, and `.blossom`.
- `uploadToBlossom()` uses PUT and kind 24242 auth.
- `NostrRepository+Backup.swift` has backup upload helpers with NIP-98 auth.
- `AvatarView.swift` has NIP-B7 / BUD-03 fallback resolution for hash-addressed Blossom URLs.

### Web

- `lib/nostr.js` implements upload helpers for nostr.build, Blossom, and yabu.me/NIP-96-like responses.

## Source references

- `android/app/src/main/kotlin/io/nurunuru/app/ui/components/PostModal.kt`
- `android/app/src/main/kotlin/io/nurunuru/app/data/ImageUploadUtils.kt`
- `ios/NuruNuru/Data/ImageUploadService.swift`
- `ios/NuruNuru/Data/NostrRepository+Backup.swift`
- `ios/NuruNuru/Views/Components/AvatarView.swift`
- `lib/nostr.js`

## Related pages

- [[features/post-composer]]
- [[nips/nip-98]]
- [[nips/README]]

## Open questions

- Android BUD-03 kind 10063 server-list publishing parity with iOS should be checked before claiming full parity.
