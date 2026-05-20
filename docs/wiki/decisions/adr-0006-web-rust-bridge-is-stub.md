# ADR-0006: Web Rust bridge is currently stubbed

## Status

Accepted as current behavior.

## Context

The repository includes a Rust core and bridge layers, but Web Nostr operations currently run through JavaScript modules rather than a live Rust bridge.

## Decision

Document Web Rust bridge / engine manager as stubs unless source code changes prove otherwise. Web protocol operations should be understood through `lib/nostr.js` and related JS modules.

## Consequences

- Do not assume Web gets native Rust MLS/FFI behavior.
- Web/native parity must be checked per feature.

## Source references

- `lib/rust-bridge.js`
- `lib/rust-engine-manager.js`
- `lib/nostr.js`
- `docs/wiki/platforms/web.md`
