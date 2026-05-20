# Talk Debugging

## Summary

Talk debugging usually involves comparing Android logcat, iOS unified logs, Rust/MDK traces, and relay event availability for Marmot MLS kinds. Raw logs should remain local and ignored by Git; only sanitized findings belong in the Wiki.

## Current behavior / guidance

- `logs/` was identified as local Android/iOS Talk/Marmot diagnostic output and is ignored by Git.
- Raw logs may contain device IDs, local paths, relay URLs, event IDs, group IDs, pubkeys, and app internals. Do not commit them.
- Prefer summaries under this page or future dated debugging notes rather than storing raw log files.
- Debugging often checks:
  - KeyPackage publish/discovery: kind `30443`, legacy kind `443`, relay list kind `10051`.
  - Welcome delivery: outer kind `1059`, inner kind `444`/`10444`, recipient `p` tags.
  - Group messages: kind `445`, `h` tag, message decrypt/apply results.
  - Self-update / key package rotation markers and retry drains.
  - Android/iOS parity for group ID, relay fanout, and canonical DM/group selection.

## Useful commands

```bash
# Android logcat filtered after reproducing an issue
adb logcat | grep -E 'NostrRepository|TalkVM|MLS|Marmot|MDK'

# iOS unified logs filtered for Talk/Marmot areas
log show --style compact --last 30m --predicate 'process CONTAINS[c] "Nuru" OR eventMessage CONTAINS[c] "TalkVM" OR eventMessage CONTAINS[c] "MLS" OR eventMessage CONTAINS[c] "Marmot"'
```

## Source references

- `android/app/src/main/kotlin/io/nurunuru/app/data/NostrRepositoryTalk.kt`
  - logging around fetch/send/apply/retry flows
- `android/app/src/main/kotlin/io/nurunuru/app/viewmodel/TalkViewModel.kt`
  - Talk state/poll logging
- `ios/NuruNuru/Data/NostrRepository+Talk.swift`
  - AppLogger Talk/Marmot diagnostics
- `ios/NuruNuru/ViewModels/TalkViewModel.swift`
  - Talk state/poll logging
- `rust-engine/nurunuru-core/src/mls.rs`
  - MLS validation/decrypt/apply behavior
- `.gitignore`
  - `logs/` ignored

## Related pages

- [[features/talk]]
- [[features/talk-marmot-mls]]
- [[features/talk-relays]]
- [[features/talk-ios-android-parity]]

## Open questions

- If recurring Talk bugs appear, add dated sanitized case studies here instead of committing raw logs.
