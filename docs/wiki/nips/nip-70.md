# NIP-70: Protected Events

## Summary

NIP-70 protected events are represented by a `['-']` tag. null--nostr exposes this mainly through the post composer and event backup/import tooling.

## Current behavior

- Android composer has a `Protected (NIP-70)` toggle.
- When enabled, publish logic adds `['-']` before signing if absent.
- iOS `publishNote(..., nip70Protected: true)` also adds `['-']` before signing.
- Web has helpers for checking and creating protected event templates.
- Backup/import UI recognizes protected events and skips protected/non-owned events where appropriate.

## Platform notes

### Android

- `PostModal.kt` stores `nip70Protected` state and passes it to `NostrRepository.publishNote()`.
- `NostrRepositoryActions.kt` appends `listOf("-")` before signing.
- External signer path signs the unsigned event with the protected tag already included.

### iOS

- `NostrRepository+Actions.swift` appends `["-"]` in `publishNote()` when `nip70Protected` is true.
- `PostSheet.swift` owns the composer-side controls and constraints.

### Web

- `lib/nostr.js` implements `isProtectedEvent()`, `addProtectedTag()`, and `createProtectedEventTemplate()`.

## Source references

- `android/app/src/main/kotlin/io/nurunuru/app/ui/components/PostModal.kt`
- `android/app/src/main/kotlin/io/nurunuru/app/data/NostrRepositoryActions.kt`
- `android/app/src/main/kotlin/io/nurunuru/app/ui/miniapps/EventBackupSettings.kt`
- `ios/NuruNuru/Data/NostrRepository+Actions.swift`
- `ios/NuruNuru/Views/Sheets/PostSheet.swift`
- `lib/nostr.js`

## Related pages

- [[features/post-composer]]
- [[nips/README]]
