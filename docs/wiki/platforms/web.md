# Web Platform

## Summary

Web は Next.js 14 PWA として実装されています。現状、Web の Rust bridge は stub であり、Nostr 操作は主に `lib/nostr.js` が直接担当します。

## Key modules

| File | Role |
|---|---|
| `lib/nostr.js` | publish、DM、Zap、sign などの Nostr 操作。 |
| `lib/connection-manager.js` | WebSocket pool、rate limit、relay cooldown。 |
| `lib/cache.js` | memory LRU + localStorage の二層キャッシュ。 |
| `lib/secure-key-store.js` | 秘密鍵を module-level closure に保持。 |
| `lib/security.js` | CSRF、AES-GCM storage、content sanitization。 |
| `lib/validation.js` | URL、pubkey、NIP-05 の入力検証。 |

## Constraints

- 投稿本文の折りたたみ閾値は 140 文字。リンクはカウントから除外。
- `dangerouslySetInnerHTML` の前には必ず `sanitizeContent()` を使う。
- production build では `console.log/warn/debug` を strip。重要な失敗のみ `console.error`。
- connection limit は max 4 global / 2 per-relay。
- 秘密鍵を `window.*` に出してはいけない。

- Web contains broad NIP utility support in `lib/nostr.js`, including NIP-17 DMs, NIP-46, NIP-65, NIP-70, upload auth, relay info/auth, and bookmarks.

## Source references

- `lib/nostr.js`
- `lib/connection-manager.js`
- `lib/secure-key-store.js`
- `lib/security.js`
- `next.config.js`

## Related pages

- [[architecture]]
- [[features/timeline]]
- [[features/post-composer]]
