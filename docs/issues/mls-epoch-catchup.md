# Android MLS: implement peer-epoch catch-up when state_not_ready persists across repair

**Type:** bug / enhancement (Talk parity)
**Area:** rust-engine/nurunuru-core/src/mls.rs
**Related PR:** #180 (upstream MDK receive-path fix, merged)
**Related work:** fix/android-talk-ux-pull-to-refresh (UX layer; user-confirmed workaround A)

## Summary

iOS→Android Talk MLS messages can become permanently undecryptable on Android
even after explicit user-initiated strong repair (`mlsClearPendingCommit` +
`fetchMlsMessages(repairFull=true)`). Recreating the DM from scratch
("workaround A") restores delivery, indicating that the Android MDK instance
is stranded at an older MLS epoch than the iOS peer.

Tracked separately from the Talk UX PR because this is a Rust/MDK layer
problem, not a UI gesture problem.

## Observed behavior (2026-05-23, on a physical Android device)

Group: (32-byte MLS group_id, redacted)

After iOS sent multiple new application messages, Android logcat (02:45:49) shows:

```
NostrRepository fetched 30 Kind-445 events
NostrRepository applied=0  stateOnly=1  dropped=0  retryable=58  retryQueued=29
NostrRepository stateUpdate id=21c7594d... kind=unhandled:Unprocessable:state_not_ready
... (58 retryable entries — iOS's new application messages cannot be decrypted)
NostrRepository fetchMlsMessages($groupId): history count=17  ← Android's MDK epoch is frozen
TalkVM repair source=pull repaired=17 merged=17 relayFetched=30
TalkVM poll ... shown=17 gap=0
```

User-initiated strong repair (`clearPendingCommit = true`) completes successfully
but does not change `history count`. The retryable queue continues to grow as
iOS sends additional messages. **Workaround A** (leave the DM on both ends and
recreate from scratch) immediately restores bidirectional delivery — the new
group starts at `epoch=0` with both ends aligned.

## Root cause hypothesis

Per `rust-engine/nurunuru-core/src/mls.rs:892`, `state_not_ready` is the
catch-all branch when MDK has no key for the requested epoch. Once an Android
client misses a Commit (e.g. relay outage, app killed during MLS apply, or a
self-update Commit that never round-tripped), its local epoch falls behind iOS.
There is currently no recovery path other than recreating the group:

- `mlsMergePendingCommit` / `mlsClearPendingCommit` only manipulate **local**
  pending state. They cannot fast-forward MDK to a peer's epoch.
- `fetchMlsMessages(repairFull=true)` re-fetches Kind-445 events but cannot
  decrypt them without the missing epoch key.
- The relay does not retain a fetchable "current GroupState" object; MLS by
  design distributes state via Commits, not snapshots.

## Proposed approach (sketch — needs design review)

Three candidates, ordered by invasiveness:

1. **Commit replay window.** Persist all incoming Kind-445 Commit wrappers
   (not just application messages) in nostrdb for N days. On `state_not_ready`,
   walk back through unapplied Commits in createdAt order and try `mdk.process`
   until the epoch catches up.
2. **External state request (MIP-extension).** Ask a trusted peer (a group
   member we already have a key with, e.g. ourselves on iOS) for the current
   exporter secret via a Welcome-style kind:1059 sealed envelope.
3. **Auto-recreate.** Detect persistent `state_not_ready` (>N occurrences over
   M minutes) and prompt the user to recreate the conversation. Preserves the
   message history surface but accepts that past undecryptable messages are
   gone.

Candidate 1 is the most spec-aligned (MLS Commits are designed to be replayable
in order). Candidate 3 is what the user already does manually and could be
automated as a fallback. Candidate 2 needs MIP authoring — out of scope for an
incremental fix.

## Acceptance criteria

- [ ] Android can recover from a missed-Commit gap of at least 1 epoch without
      user intervention, when the missing Commit is still retrievable from
      configured relays.
- [ ] If recovery is impossible (Commit aged out of relays), surface an actionable
      UI prompt instead of silently retry-queueing forever.
- [ ] No regression to PR #180 receive-path semantics (no unconditional
      `mlsClearPendingCommit` on receive path).
- [ ] iOS parity tracked in a sibling Issue once the Android approach is chosen.

## Out of scope (handled elsewhere)

- Talk UX (pull-to-refresh, smart auto-scroll, strong repair on pull) —
  shipped in PR #182 (`fix/android-talk-ux-pull-to-refresh`).
- MLS DB encryption — Issue #181 (separate 3-chunk PR plan).

## References

- `rust-engine/nurunuru-core/src/mls.rs` (state_not_ready branch ~line 892)
- `android/app/src/main/kotlin/io/nurunuru/app/data/NostrRepositoryTalk.kt` (`fetchMlsMessages`, `mlsStateGapCount`)
- PR #180 — preserves MDK receive logic; must not be regressed
- Workaround A user confirmation: 2026-05-23

