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
| `lib/performance-metrics.js` | Local-only sanitized performance metrics helper; stores recent timings in memory and exposes `window.__NURU_PERF__` in development only. |
| `lib/publish-outbox.js` | Web durable publish outbox groundwork; stores fully signed event JSON locally in `localStorage` for retry diagnostics. |

## Constraints

- 投稿本文の折りたたみ閾値は 140 文字。リンクはカウントから除外。
- `dangerouslySetInnerHTML` の前には必ず `sanitizeContent()` を使う。
- production build では `console.log/warn/debug` を strip。重要な失敗のみ `console.error`。
- connection limit は max 4 global / 2 per-relay。
- 秘密鍵を `window.*` に出してはいけない。

- Web contains broad NIP utility support in `lib/nostr.js`, including NIP-17 DMs, NIP-46, NIP-65, NIP-70, upload auth, relay info/auth, and bookmarks.


## Performance behavior

- `lib/connection-manager.js` records sanitized local timings for managed relay fetches through `lib/performance-metrics.js`; metrics are not uploaded.
- `components/URLPreview.js` waits until a preview approaches the viewport before calling Microlink, reducing background network pressure on long timelines.
- `components/TimelineTab.js` keeps the visible following timeline when a refresh returns an empty relay result after posts are already displayed.

## Publish durability and diagnostics

- `lib/nostr.js` exposes `publishEventResult()` for Web publish paths with `eventId`, aggregate successful/failed relay lists, first-OK latency, retry queued state, and an error string. Existing `publishEvent()` remains a boolean compatibility wrapper.
- `lib/connection-manager.js` exposes `publishManagedResult()` and records per-relay publish success/failure into the existing Web relay health map.
- `lib/publish-outbox.js` persists fully signed event JSON only in browser `localStorage` before network publish. It never stores private keys, unsigned events, or signing material. This is a Web parity groundwork layer; IndexedDB migration remains an open improvement for larger queues.
- `retryPendingPublishOutbox()` retries pending/failed signed events, and `components/miniapps/RelaySettings.js` triggers best-effort retry when the browser comes back online.
- Relay Settings now shows a local diagnostics card for pending signed outbox count, recent event IDs, manual retry, and Web relay health. Raw signed event JSON/content is not displayed.

## Source references

- `lib/nostr.js`
- `lib/connection-manager.js`
- `lib/secure-key-store.js`
- `lib/security.js`
- `next.config.js`
- `lib/performance-metrics.js`
- `lib/publish-outbox.js`
- `components/TimelineTab.js`
- `components/URLPreview.js`
- `components/miniapps/RelaySettings.js`

## Related pages

- [[architecture]]
- [[features/timeline]]
- [[features/post-composer]]
