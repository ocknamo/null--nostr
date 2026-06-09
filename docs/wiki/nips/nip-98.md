# NIP-98: HTTP Auth for Uploads

## Summary

NIP-98 HTTP authentication is used for upload targets that require signed HTTP auth events. The code also supports Blossom/BUD-03 auth using kind 24242, which is adjacent but not the same event kind as NIP-98 kind 27235.

## Current behavior

- Uploads to nostr.build / share.yabu.me style endpoints add NIP-98 auth where possible.
- Upstream marks NIP-96 HTTP File Storage Integration as unrecommended/replaced by Blossom, so NIP-96-style response handling should be documented as compatibility rather than the preferred upload standard.
- iOS `ImageUploadService` creates kind 27235 auth for NIP-98 paths.
- Blossom upload paths use PUT plus Blossom auth kind 24242 in current code.
- Backup upload paths also add auth headers.

## Platform notes

### Android

- `ImageUploadUtils.uploadToBlossom()` creates kind 24242 auth for Blossom.
- nostr.build / yabu.me upload helpers attempt NIP-98 auth.
- Signup image upload also uses authenticated upload paths.

### iOS

- `ImageUploadService` supports nostr.build, share.yabu.me, and Blossom.
- Comments note that Blossom may reject kind 27235 and therefore uses Android-compatible Blossom auth kind 24242.
- `NostrRepository+Backup.swift` uses NIP-98 auth for backup uploads.

### Web

- `lib/nostr.js` adds NIP-98 auth for upload paths and creates Blossom auth events with kind 24242.

## Source references

- `android/app/src/main/kotlin/io/nurunuru/app/data/ImageUploadUtils.kt`
- `android/app/src/main/kotlin/io/nurunuru/app/ui/components/SignUpModal.kt`
- `ios/NuruNuru/Data/ImageUploadService.swift`
- `ios/NuruNuru/Data/NostrRepository+Backup.swift`
- `lib/nostr.js`

## Related pages

- [[features/image-upload]]
- [[nips/README]]
