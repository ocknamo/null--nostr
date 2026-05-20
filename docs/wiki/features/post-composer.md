# Post Composer

## Summary

Post Composer は投稿作成 UI です。テキスト、画像、リレー指定投稿、NIP-70 保護などを扱います。

## Current behavior

- 投稿文字数は 140 文字。
- Android は `PostModal.kt` で厳密に enforced。
- iOS は `PostSheet.swift` で厳密に enforced。
- Android では relay selection panel があり、`targetRelays` により targeted publish を行う。
- iOS も `publishNote(..., targetRelays:)` を持ち、初回 publish 後に explicit target relays と返信先作者の NIP-65 read relays へ fan out する。
- NIP-70 protection が有効な場合、署名前に `['-']` tag を追加する。
- 返信は NIP-10 形式の `e` tag marker `reply` と `p` tag を使う。
- content warning は `content-warning` tag。
- custom tags は NIP-71 `imeta` などの追加タグ用途にも使われる。
- Android の画像アップロードは `withContext(Dispatchers.IO)` 内で `async {}` を使い並列化する。

## Platform notes

### Android

- `targetRelays: List<String>?` が non-null の場合、`publishNoteWithTagsToRelays()` / FFI `publish_note_with_tags_to_relays` 経由。
- null の場合は全 relay へ broadcast。
- `nip70Protected = true` で `['-']` tag を追加。

### iOS

- `PostSheet.swift` が 140 文字制限を守る。
- modal 表示は `.sheet`。
- LINE Seed JP font を使う。
- `NostrRepository+Actions.swift` は `replyToId` / `replyToPubkey` / `contentWarning` / `customTags` / `targetRelays` / `nip70Protected` を受け取る。

## Source references

- `android/app/src/main/kotlin/io/nurunuru/app/ui/components/PostModal.kt`
- `android/app/src/main/kotlin/io/nurunuru/app/data/NostrRepository.kt`
- `ios/NuruNuru/Views/Sheets/PostSheet.swift`
- `rust-engine/nurunuru-ffi/src/lib.rs`

## Related pages

- [[nips/README]]
- [[nips/nip-70]]
- [[features/image-upload]]
- [[features/relay-management]]
- [[platforms/rust-engine]]
- [[ui/android-ios-sync]]
