# Talk Relay Strategy

## Summary

Talk relay strategy is separate from normal timeline relay use because Marmot MLS relies on KeyPackage discovery, Welcome delivery, and group message fanout across several relay sets.

## Current behavior

- KeyPackage discovery uses Marmot kind `10051` relay lists where available.
- NIP-17/MLS inbox relay list kind `10050` is used as an inbox relay signal for Welcome/MLS wrapper delivery.
- NIP-65 write relays are used as fallback when Marmot-specific relay lists are absent.
- Native repositories merge default relays, group relays, peer inbox relays, and Marmot interop fallback relays.
- Relay hit/ACK scoring exists on iOS to prefer relays that actually carry Marmot traffic.
- Some public relays are avoided or deprioritized for Marmot if logs/code identify them as rejecting or hanging on MLS kinds.

## Platform notes

### Android

- `AppPreferences.kt` stores MLS key package discovery relays and inbox relays.
- `NostrRepositoryTalk.kt` resolves key package relays, Welcome inbox relays, group message relays, and interop fallback relays.

### iOS

- `AppPreferences.swift` stores Marmot/WhiteNoise relay preferences and per-group retry/lifecycle metadata.
- `NostrRepository+Talk.swift` resolves member KeyPackage relays, Welcome/MLS inbox relays, and per-group message relays.
- `NostrRepository.swift` stores relay hit/ACK scores for Marmot traffic.

## Source references

- `android/app/src/main/kotlin/io/nurunuru/app/data/prefs/AppPreferences.kt`
  - MLS relay preferences
- `android/app/src/main/kotlin/io/nurunuru/app/data/NostrRepositoryTalk.kt`
  - relay merge, KeyPackage relay resolution, Welcome inbox resolution
- `ios/NuruNuru/Data/AppPreferences.swift`
  - Marmot relay settings and retry metadata
- `ios/NuruNuru/Data/NostrRepository.swift`
  - Marmot relay hit/ACK score state
- `ios/NuruNuru/Data/NostrRepository+Talk.swift`
  - `resolveKeyPackageRelays`, Welcome/MLS inbox relay resolution, fanout logic
- `docs/wiki/nips/nip-65.md`

## Related pages

- [[features/talk]]
- [[features/talk-marmot-mls]]
- [[features/relay-management]]
- [[nips/nip-65]]
- [[nips/nip-17]]

## Open questions

- Exact default/fallback Marmot relay pool should be rechecked whenever relay policy changes in code.
