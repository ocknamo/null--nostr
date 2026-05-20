# Notifications

## Summary

Notifications は repost、reply、mention などの通知表示を扱います。

## Current behavior

- Android の通知には reaction, zap receipt, repost, reply / mention, badges, follows などが含まれる。
- Kind 6 repost と Kind 1 `#p` reply / mention が明示的に扱われる。
- `NotificationModal.kt` は通知タイプごとに `NotifStyle` を持つ。
- Android では 30 秒の background polling がある。
- 新規 item pill は `Column > AnimatedVisibility` の構造で表示する。

## Implementation notes

- Compose の `AnimatedVisibility` は scope 解決に注意する。
- `AnimatedVisibility inside Box inside Column` では Kotlin が外側 receiver を優先する場合があるため、`Column { }` で scope を明確化するか standalone composable に切り出す。

## Source references

- `android/app/src/main/kotlin/io/nurunuru/app/ui/components/NotificationModal.kt`
- `android/app/src/main/kotlin/io/nurunuru/app/data/NostrRepositoryNotifications.kt`
- `android/app/src/main/kotlin/io/nurunuru/app/data/NostrRepository.kt`
- `ios/NuruNuru/Views/Sheets/NotificationSheet.swift`

## Related pages

- [[features/timeline]]
- [[platforms/android]]
