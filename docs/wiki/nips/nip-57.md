# NIP-57: Lightning Zaps

## Summary

NIP-57 is used for Zap requests and Zap receipts. null--nostr supports Zap invoice generation, Zap receipt fetching/parsing, notification display, settings, and aggregate Zap totals.

## Current behavior

- Zap requests use kind 9734.
- Zap receipts use kind 9735 and are fetched for notifications and engagement totals.
- Zap amounts are parsed from `bolt11` and/or `description` tags depending on platform helper.
- Post action rows include a Zap button and display Zap amount/count information.
- Zap settings let users configure default amounts.

## Platform notes

### Android

- `NostrRepository.fetchZaps()` fetches zap receipts and aggregates amounts.
- `parseZapAmount()` parses receipt amount data.
- `NotificationModal.kt` has Zap notification style and rendering.
- `ZapSettings` exists in settings mini-apps.

### iOS

- `NostrRepository.swift` builds zap requests and hits LNURL-pay endpoints for invoices.
- `NostrRepository+Reactions.swift` parses zap totals from receipt events.
- `ZapSheet.swift` handles Zap UI.
- `ZapSettingsView.swift` handles default amount settings.

### Web

- `lib/nostr.js` includes invoice fetch helpers, Zap parsing, and Zap total fetch helpers.

## Source references

- `android/app/src/main/kotlin/io/nurunuru/app/data/NostrRepository.kt`
- `android/app/src/main/kotlin/io/nurunuru/app/data/NostrRepositoryNotifications.kt`
- `android/app/src/main/kotlin/io/nurunuru/app/ui/components/PostActions.kt`
- `ios/NuruNuru/Data/NostrRepository.swift`
- `ios/NuruNuru/Data/NostrRepository+Reactions.swift`
- `ios/NuruNuru/Views/Sheets/ZapSheet.swift`
- `ios/NuruNuru/Views/MiniApps/ZapSettingsView.swift`
- `lib/nostr.js`

## Related pages

- [[features/timeline]]
- [[features/notifications]]
- [[nips/README]]
