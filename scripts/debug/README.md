# Debug Scripts

Ad-hoc diagnostic scripts for investigating native Talk / MLS / relay behavior.
Not shipped with the app; intentionally minimal dependencies (`ws` only).

## probe-relays.mjs

Probe all default JP + global relays for Kind-445 (MLS application message) events
on a specific MLS group id. Used to diagnose iOS↔Android delivery gaps where one
peer's encrypted message does not reach the other peer's MDK instance.

```bash
# Requires: npm i -g ws  (or: cd to a dir that has ws available)
GID=<group_id_hex_64chars> SINCE=<unix_ts> node scripts/debug/probe-relays.mjs
```

Output is per-relay: ✅OK / ⏱TO / ❌ERR with event count and the first 12 hex
chars of each event id, timestamp, and the first 8 hex chars of the publisher
pubkey. Lets you see which relays actually carry a given group's traffic.

Do NOT hardcode a live group_id into a committed version of this script —
group_ids in the public repo history identify specific users as participants
in a Talk even though the MLS payload itself is encrypted.
