# Marmot / MLS 実装プラン

> goose セッションごとに独立して進められるよう、タスクを小さく分割する。  
> 各セッションは原則 1 目的・限定ファイル・明確な完了条件で進める。  
> 更新日: 2026-04-24

---

## 0. 進め方の原則

1. Rust core を先に安定させる。
2. FFI contract を固定する。
3. Android / iOS は同じ contract に合わせる。
4. その後 WhiteNoise interop を詰める。
5. 同じファイルを複数 goose セッションで同時編集しない。
6. 各セッションは最後に必ず focused test を実行する。

---

## 1. フェーズ一覧

| Phase | 内容 | 目安 | 並列可否 |
|---|---|---:|---|
| P0 | 現状固定・回帰テスト追加 | 0.5〜1日 | 一部可 |
| P1 | Rust core MIP-00〜03 安定化 | 2〜4日 | 分割可 |
| P2 | FFI contract 整理 | 1〜2日 | Rust core 後 |
| P3 | iOS integration | 2〜4日 | Android と並列可 |
| P4 | Android integration | 2〜4日 | iOS と並列可 |
| P5 | Cross-platform interop | 2〜5日 | P3/P4 後 |
| P6 | WhiteNoise interop | 1〜3週間 | P5 後 |
| P7 | production hardening | 継続 | P5 後 |

---

## 2. セッション分割ルール

## 2.1 1 セッションのサイズ

1 goose セッションは以下のどれか 1 つに限定する。

- 1 integration test を追加して通す。
- 1 API の ID semantics を修正する。
- 1 platform flow を修正する。
- 1 document を更新する。
- 1 interop log を分析する。

## 2.2 同時編集禁止ファイル

以下は競合しやすいので、同時に複数セッションで触らない。

- `rust-engine/nurunuru-core/src/engine.rs`
- `rust-engine/nurunuru-core/src/mls.rs`
- `rust-engine/nurunuru-ffi/src/lib.rs`
- `rust-engine/nurunuru-ffi/bindgen/kotlin-out/uniffi/nurunuru/nurunuru.kt`
- `ios/NuruNuru/Data/NostrRepository+Talk.swift`
- `android/app/src/main/kotlin/io/nurunuru/app/data/NostrRepositoryTalk.kt`

## 2.3 セッション終了時の必須報告

各 goose セッションは最後に以下を報告する。

```text
変更ファイル:
実行テスト:
結果:
未解決:
次セッションへの引き継ぎ:
```

---

## 3. P0: 現状固定・回帰テスト追加

### P0-S1: Marmot happy path regression 固定

**目的**  
現在 pass している welcome + message flow を regression として固定する。

**対象ファイル**

- `rust-engine/nurunuru-core/tests/mls_marmot_flow.rs`

**作業**

- `marmot_welcome_giftwrap_and_message_flow_works` を整理。
- 不要な debug println を必要最小限にする。
- 以下を明示 assert:
  - Kind 1059 recipient `p` tag == Bob pubkey
  - extracted rumor kind == 444
  - extracted rumor JSON == inner rumor JSON or same id/kind/content/tags
  - `mls_process_welcome` returns Nostr group id 形式の 64 hex
  - post-join self-update commit kind == 445
  - final message decrypt == expected

**テスト**

```bash
cd rust-engine
cargo test -p nurunuru-core --test mls_marmot_flow -- --nocapture
```

**完了条件**

- test pass
- panic/debug noise が過剰でない

---

### P0-S2: group id semantics regression test

**目的**  
FFI/API 境界では groupIdHex が Nostr group id であることを固定する。

**対象ファイル**

- `rust-engine/nurunuru-core/tests/mls_marmot_flow.rs` または新規 `tests/mls_group_id_semantics.rs`

**作業**

- group 作成後 `group.group_id_hex` が Kind 445 `h` tag と一致することを assert。
- `groups_needing_self_update()` が返す ID を `mls_create_recovery_commit()` に渡せることを assert。
- internal MLS group id を誤って外へ返していないことを検証。

**テスト**

```bash
cd rust-engine
cargo test -p nurunuru-core --test mls_group_id_semantics -- --nocapture
```

**完了条件**

- groupIdHex = Nostr group id が test で保証される

---

### P0-S3: Welcome recipient regression test

**目的**  
Welcome 1059 の recipient が KeyPackage owner であることを固定する。

**対象ファイル**

- `rust-engine/nurunuru-core/tests/mls_marmot_flow.rs` または新規 `tests/mls_welcome_recipient.rs`

**作業**

- Bob KeyPackage で add_member。
- 返却された `welcome_event_data.recipient_pubkey == bob_pubkey` を assert。
- 1059 `p` tag == bob_pubkey を assert。
- Bob で unwrap success。
- Alice など wrong key で unwrap fail を assert。

**テスト**

```bash
cd rust-engine
cargo test -p nurunuru-core --test mls_welcome_recipient -- --nocapture
```

**完了条件**

- invalid HMAC regression が再発しない

---

## 4. P1: Rust core MIP-00〜03 安定化

### P1-S1: `mls_process_welcome()` semantics test

**目的**  
`mls_process_welcome()` が process + accept/join まで行うことを保証する。

**対象ファイル**

- `rust-engine/nurunuru-core/src/mls.rs`
- `rust-engine/nurunuru-core/tests/mls_marmot_flow.rs`

**作業**

- welcome process 後に `mls_list_groups()` に group が出ることを assert。
- group state が active 相当で後続 message を処理可能なことを assert。
- duplicate welcome process の挙動を確認。

**テスト**

```bash
cd rust-engine
cargo test -p nurunuru-core --test mls_marmot_flow -- --nocapture
```

**完了条件**

- process welcome 後に self-update / message 処理へ進める

---

### P1-S2: pending commit success/failure policy

**目的**  
publish 成功時 merge、失敗時 clear の policy を Rust API と test で安全にする。

**対象ファイル**

- `rust-engine/nurunuru-core/src/mls.rs`
- `rust-engine/nurunuru-core/src/engine.rs`
- `rust-engine/nurunuru-core/tests/mls_pending_commit.rs`

**作業**

- add_member 後 pending commit がある状態で次操作がどうなるか test。
- `mls_clear_pending_commit()` 後に再 add_member できることを test。
- `mls_merge_pending_commit()` 後に self-update を処理できることを test。

**テスト**

```bash
cd rust-engine
cargo test -p nurunuru-core --test mls_pending_commit -- --nocapture
```

**完了条件**

- pending commit による stuck state の復旧 path が test される

---

### P1-S3: post-join self-update full roundtrip

**目的**  
Bob join 後 self-update commit を Alice が process し、その後双方向 message が復号できること。

**対象ファイル**

- `rust-engine/nurunuru-core/tests/mls_marmot_flow.rs` または新規 `tests/mls_self_update_flow.rs`

**作業**

- Alice invites Bob。
- Bob processes welcome。
- Bob creates recovery/self-update commit。
- Bob merges after publish simulation。
- Alice processes Bob self-update。
- Alice sends message, Bob decrypts。
- Bob sends message, Alice decrypts。

**テスト**

```bash
cd rust-engine
cargo test -p nurunuru-core --test mls_self_update_flow -- --nocapture
```

**完了条件**

- self-update 後の双方向 message が pass

---

### P1-S4: KeyPackage consumed/rotation core logic

**目的**  
使用済み KeyPackage を local で追跡し、再利用を避ける。

**対象ファイル**

- `rust-engine/nurunuru-core/tests/mls_key_package_lifecycle.rs`
- 必要なら `docs/MARMOT_DESIGN.md`
- 必要なら `docs/MARMOT_IMPLEMENTATION_PLAN.md`

**作業**

- AddMemberResult に consumed KeyPackage event id を含めるか検討。
- 既存型で足りるなら platform 側で event id tracking。
- Rust test では同一 KeyPackage 再利用時の挙動を確認。
- 必要なら helper API 追加。

**確認結果**

- MDK 0.7.x は inviter-side `add_members` で同一 remote KeyPackage event の再利用を拒否しない。
- `rust-engine/nurunuru-core/tests/mls_key_package_lifecycle.rs` で現状挙動を regression として固定する。
- `AddMemberResult` への consumed KeyPackage event id 追加は現時点では不要。platform は `mls_add_member()` に渡した signed KeyPackage event JSON / event id を保持しており、その id を consumed set に記録できる。
- relay fetch 時の consumed id 除外、新 KeyPackage publish、NIP-09 delete best-effort は iOS / Android 側の rotation flow で実装する。

**テスト**

```bash
cd rust-engine
cargo test -p nurunuru-core --test mls_key_package_lifecycle -- --nocapture
```

**完了条件**

- consumed tracking の責務分担が明確
- 再利用事故が test で検出可能

---

### P1-S5: out-of-order / duplicate event handling test

**目的**  
relay out-of-order による unprocessable を retry できることを保証する。

**対象ファイル**

- `rust-engine/nurunuru-core/tests/mls_out_of_order.rs`

**作業**

- commit/message の順序を入れ替えて process。
- retryable result を確認。
- commit 後に retry して success することを確認。
- duplicate event を再 process して idempotent であることを確認。

**テスト**

```bash
cd rust-engine
cargo test -p nurunuru-core --test mls_out_of_order -- --nocapture
```

**完了条件**

- app 側 retry queue 設計を支える core behavior が確認される

---

## 5. P2: FFI contract 整理

### P2-S1: FFI API comment / naming 整理

**目的**  
`groupIdHex` が Nostr group id であることを FFI レベルで明文化する。

**対象ファイル**

- `rust-engine/nurunuru-ffi/src/lib.rs`
- `rust-engine/nurunuru-core/src/types.rs`

**作業**

- FFI exposed struct / method comments に `group_id_hex is Nostr group id` を明記。
- 必要なら debug-only `internal_mls_group_id_hex` は追加しない方針にする。
- API 互換を壊さない。

**テスト**

```bash
cd rust-engine
cargo test -p nurunuru-core --tests
```

**完了条件**

- contract がコードコメントで追える

---

### P2-S2: UniFFI/Kotlin binding regeneration

**目的**  
FFI API 変更があれば bindings を再生成する。

**対象ファイル**

- `rust-engine/nurunuru-ffi/src/lib.rs`
- `rust-engine/nurunuru-ffi/bindgen/kotlin-out/uniffi/nurunuru/nurunuru.kt`

**作業**

```bash
cd rust-engine/nurunuru-ffi
bash bindgen/gen_kotlin.sh
```

API 変更がない comment only なら不要。

**完了条件**

- Kotlin binding が compile 可能

---

### P2-S3: iOS MLS-only FFI contract sync

**目的**  
iOS の `MlsFFIBridge` と Rust FFI を一致させる。

**対象ファイル**

- `ios/NuruNuru/Data/NuruNuruFFIBridge.swift`
- `ios/NuruNuru/Data/NuruNuruFFILiveClient.swift`
- `ios/MLS_FFI_PLAN.md`

**作業**

- `mlsGroupsNeedingSelfUpdate` を bridge に含める。
- `mlsProcessMessageResult` が使えることを確認。
- groupIdHex comment を追加。

**テスト**

```bash
cd ios
xcodebuild -scheme NuruNuru -destination 'platform=iOS Simulator,name=iPhone 17' -skipPackagePluginValidation build
```

**完了条件**

- iOS build pass

---

## 6. P3: iOS integration

### P3-S1: iOS Welcome receive/process flow

**目的**  
iOS が Kind 1059 Welcome を受信し、unwrap/process/join できること。

**対象ファイル**

- `ios/NuruNuru/Data/NostrRepository+Talk.swift`

**作業**

- Welcome fetch filter を確認。
- 1059 unwrap は Rust FFI `mlsProcessWelcome` に渡す JSON shape を確認。
- process success 後 group list 更新。
- joined timestamp 保存。

**テスト**

```bash
cd ios
xcodebuild -scheme NuruNuru -destination 'platform=iOS Simulator,name=iPhone 17' -skipPackagePluginValidation build
```

**完了条件**

- simulator build pass
- logs で process welcome success を確認できる

---

### P3-S2: iOS post-join self-update retry loop

**目的**  
Welcome 後 self-update を自動 publish し、失敗時 retry する。

**対象ファイル**

- `ios/NuruNuru/Data/NostrRepository+Talk.swift`
- `ios/NuruNuru/Data/AppPreferences.swift` など prefs 定義がある場合

**作業**

- `mlsGroupsNeedingSelfUpdate` を使用。
- `mlsCreateRecoveryCommit` -> publish Kind 445 -> success なら merge。
- fail なら clear or retry policy に従う。
- `mlsSelfUpdateCompletedAtByGroupId` 保存。

**完了条件**

- self-update が best-effort ではなく retryable になる

---

### P3-S3: iOS KeyPackage consumed rotation/delete

**目的**  
Welcome process 後に自分の consumed KeyPackage を更新する。

**対象ファイル**

- `ios/NuruNuru/Data/NostrRepository+Talk.swift`
- `ios/NuruNuru/Data/NostrRepository+Actions.swift` if delete publish helper exists

**作業**

- consumed KeyPackage event id を prefs に記録。
- 新 KeyPackage publish。
- NIP-09 delete best-effort。
- fetch 時に consumed id を除外。

**完了条件**

- 同じ KeyPackage を再招待に使い回さない

---

### P3-S4: iOS message retry queue

**目的**  
out-of-order Kind 445 を retry する。

**対象ファイル**

- `ios/NuruNuru/Data/NostrRepository+Talk.swift`

**作業**

- retryable unprocessable は processedIds に入れない。
- state update 処理後 retry queue を再走査。
- invalid shape は dropped として processed に入れる。

**完了条件**

- relay 順序揺れで stuck しにくくなる

---

## 7. P4: Android integration

### P4-S1: Android Welcome receive/process flow

**対象ファイル**

- `android/app/src/main/kotlin/io/nurunuru/app/data/NostrRepositoryTalk.kt`

**作業**

- Kind 1059 Welcome fetch/process を確認。
- process success 後 group list 更新。
- groupIdHex = Nostr group id 前提で h-tag subscription。

**テスト**

```bash
cd android
./gradlew assembleDebug
```

**完了条件**

- Android build pass

---

### P4-S2: Android post-join self-update retry loop

**対象ファイル**

- `android/app/src/main/kotlin/io/nurunuru/app/data/NostrRepositoryTalk.kt`
- prefs 周辺

**作業**

- `mlsGroupsNeedingSelfUpdate` を使用。
- recovery commit publish success -> merge。
- fail -> clear/retry。

**完了条件**

- Android join 後 self-update が自動化される

---

### P4-S3: Android KeyPackage consumed rotation/delete

**対象ファイル**

- `android/app/src/main/kotlin/io/nurunuru/app/data/NostrRepositoryTalk.kt`

**作業**

- used KeyPackage tracking。
- publish new KeyPackage after consumed。
- NIP-09 delete best-effort。

**完了条件**

- Android で KeyPackage 再利用を避ける

---

### P4-S4: Android message retry queue

**対象ファイル**

- `android/app/src/main/kotlin/io/nurunuru/app/data/NostrRepositoryTalk.kt`

**作業**

- iOS と同等の retryable/dropped policy を実装。

**完了条件**

- relay out-of-order に耐える

---

## 8. P5: Cross-platform interop

### P5-S1: iOS invites Android

**目的**  
iOS Alice -> Android Bob の full flow。

**手順**

1. Android Bob publishes KeyPackage。
2. iOS Alice creates group and adds Bob。
3. Alice publishes Kind 445 + 1059。
4. Bob processes Welcome。
5. Bob self-updates。
6. Alice processes self-update。
7. 双方向 message。

**完了条件**

- 双方向 plaintext が一致
- logs に invalid HMAC / epoch mismatch が残らない

---

### P5-S2: Android invites iOS

P5-S1 の逆方向。

---

### P5-S3: relay outage / partial publish simulation

**目的**  
一部 relay publish failure で pending commit が stuck しない。

**作業**

- relay list に dead relay を混ぜる。
- 1 relay success なら merge。
- all fail なら clear。

---

## 9. P6: WhiteNoise interop

### P6-S1: WhiteNoise KeyPackage fetch compatibility

**目的**  
WhiteNoise の KeyPackage を NuruNuru が add_member できること。

**作業**

- WhiteNoise event samples を保存。
- 30443/443 shape を比較。
- relay tags / client tags / content base64 を検証。

**P6-S1 analysis status (2026-04-24)**

WhiteNoise の実 event JSON sample は、このセッションの入力および repository 内には見つからなかった。  
そのため、現時点では WhiteNoise actual shape は **未確認** であり、以下は NuruNuru/MDK 側の期待 shape と、sample 入手後に検証すべき互換性観点である。

#### NuruNuru expected KeyPackage shape

NuruNuru Rust core (`MlsManager::create_key_package_event`) は MDK の `create_key_package_for_event()` が返す KeyPackage を platform signer で署名して publish する前提。

Canonical current event:

- `kind`: `30443` (MIP-00 canonical, addressable)
- `pubkey`: KeyPackage owner の Nostr pubkey。MLS BasicCredential identity と一致必須。
- `content`: base64 encoded TLS-serialized MLS KeyPackage。
- required tags for current `30443`:
  - `['d', <64-hex random slot id>]`
  - `['mls_protocol_version', '1.0']`
  - `['mls_ciphersuite', '0x0001']`
  - `['mls_extensions', '0x000a', '0xf2ee']` (順序差は許容されるべき)
  - `['mls_proposals', '0x000a']`
  - `['relays', <wss relay>...]` (少なくとも 1 件、各値は valid RelayUrl)
  - `['i', <KeyPackageRef hex>]` (content から計算した KeyPackageRef と一致必須)
  - `['client', ...]` (例: `MDK/0.7.1`; validation 上は必須ではない)
  - `['encoding', 'base64']` (必須)
- optional tag:
  - `['-']` NIP-70 protected tag。NuruNuru/MDK default では付けない。

Legacy migration event:

- `kind`: `443`
- `content`: 30443 と同じ base64 KeyPackage。
- tags: `30443` tags から `d` を除いた shape。
- `mls_proposals` / `i` は legacy では backward compatibility のため MDK 側で optional だが、NuruNuru が生成する `legacy_tags` には含まれる。

#### `normalize_key_package_event_for_mdk` acceptance

NuruNuru の `normalize_key_package_event_for_mdk()` は incoming JSON の `kind == 30443` を `443` に rewrite してから `nostr::Event` として parse し、MDK `parse_key_package()` に渡す。

この wrapper 経由で受け入れ可能な条件:

- event JSON として parse できること。
- original `kind` が `30443` または `443` であることが望ましい。現実装は `30443` のみ rewrite し、それ以外は MDK に渡す。
- `content` が `['encoding','base64']` と整合する base64 TLS-serialized MLS KeyPackage であること。
- `pubkey` が KeyPackage credential identity と一致すること。
- `mls_protocol_version`, `mls_ciphersuite`, `mls_extensions`, `relays`, `encoding` が MDK validation を満たすこと。
- `i` tag が存在する場合は content から計算される KeyPackageRef と一致すること。

注意点:

- rewrite により current MDK の `kind:30443` 専用 validation (`d`, `mls_proposals`, `i` 必須) は wrapper 経由では bypass される。これは旧 MDK 互換目的の normalization だが、MDK 0.7.1 pinned git では `parse_key_package()` 自体が `30443` と `443` の両方を受け入れるため、将来は rewrite 不要になる可能性がある。
- Nostr event id/signature は kind rewrite 後の JSON と一致しなくなるが、現 MDK `parse_key_package()` は KeyPackage credential identity と event owner の一致を検証し、Nostr event signature verification は行わない。relay 取得時点では relay が署名検証済みとみなす運用になる。
- Welcome 1059 recipient は、この KeyPackage event の `pubkey` (owner) を使う。Welcome rumor の `pubkey` ではない。

#### WhiteNoise actual shape checklist

sample 入手後、以下を記録する。

- `kind`: `30443` か `443` か。
- `pubkey`: KeyPackage owner か。WhiteNoise UI/log の account pubkey と一致するか。
- `content`: base64 decode が成功するか。可能なら MDK/OpenMLS で TLS KeyPackage deserialize が成功するか。
- `tags`:
  - `d` の有無と形式 (`30443` なら 64 hex expected)。
  - `mls_protocol_version` value。
  - `mls_ciphersuite` value (`0x0001` expected)。
  - `mls_extensions` value list (`0x000a`, `0xf2ee` expected)。
  - `mls_proposals` の有無/value (`30443` なら `0x000a` expected)。
  - `relays` tag name/value 形式。NuruNuru/MDK は `['relays', 'wss://...']` を期待する。
  - `i` tag の有無、hex format、content-derived KeyPackageRef との一致。
  - `client` tag value (差分は原則許容)。
  - `encoding` tag (`base64` expected)。大文字小文字差分があれば要確認。
  - optional `['-']` protected tag の有無。

#### WhiteNoise sample acquisition procedure

WhiteNoise sample が無い場合は、次の手順で取得してこの section に結果を貼る。

1. WhiteNoise で test account を作成または既存 test key で login する。
2. WhiteNoise の MLS/Marmot KeyPackage publish 操作を実行する。
3. WhiteNoise account pubkey を控える。
4. publish 対象 relay を WhiteNoise logs/settings から控える。候補 relay が不明な場合は NuruNuru default relays と WhiteNoise configured relays の両方を検索する。
5. relay query:
   - canonical: `kinds: [30443]`, `authors: [<WhiteNoise pubkey>]`
   - legacy fallback: `kinds: [443]`, `authors: [<WhiteNoise pubkey>]`
   - 取得件数が多い場合は `limit: 5` で `created_at` 最新を優先する。
6. 取得した full signed event JSON を保存する。最低限 `id`, `pubkey`, `created_at`, `kind`, `tags`, `content`, `sig` を含める。
7. private key / nsec / local MLS secret は絶対に保存しない。KeyPackage content は公開 event payload なので保存可。
8. NuruNuru Rust focused validation を実行するか、新規 regression test fixture に貼って `mls_validate_key_package_event()` と `mls_add_member()` まで確認する。

#### Known compatibility risks to test once sample is available

- WhiteNoise が `kind:30443` を publish しているが `d` / `mls_proposals` / `i` のいずれかを省略している場合: 現 NuruNuru wrapper は `443` rewrite により受け入れる可能性があるが、current MIP-00 strict 30443 としては不完全。Regression test で「現状受容する/拒否する」を固定し、strict に寄せるか互換重視にするか決める。
- WhiteNoise が `kind:443` only の場合: NuruNuru は legacy として受け入れる設計。`i` / `mls_proposals` が無い legacy sample も regression test 化する。
- `encoding` tag が無い、または `content` が hex/base64url/no-padding の場合: 現 MDK は `['encoding','base64']` を必須とするため受け入れ不可。修正するなら normalization ではなく MDK compatibility policy と security review が必要。
- `relays` tag が `relay` 単数、複数 `['relay', ...]`、または marker 付き `r` tag の場合: 現 MDK は `relays` tag を必須とするため受け入れ不可。必要なら Rust regression test と normalization/policy を追加する。
- `pubkey` と KeyPackage credential identity が不一致の場合: security 上拒否が正しい。修正してはいけない。

#### Proposed Rust regression tests after sample acquisition

追加先候補: `rust-engine/nurunuru-core/tests/mls_marmot_flow.rs` または新規 `tests/mls_whitenoise_key_package.rs`。

- `whitenoise_key_package_sample_validates`: WhiteNoise signed event JSON fixture を `mls_validate_key_package_event()` に渡して pass/fail expectation を固定する。
- `whitenoise_key_package_can_be_added_as_member`: Alice NuruNuru engine が sample を `mls_add_member(groupIdHex, sample_json)` に使い、Kind 445 commit と Kind 1059 Welcome を生成できることを確認する。`welcome_event_data.recipient_pubkey == sample.pubkey` を assert する。
- `whitenoise_key_package_shape_documents_kind`: sample の `kind` が `30443` または `443` のどちらかを assert し、migration 変更を検知する。
- 必要なら negative tests:
  - missing/invalid `encoding` rejects。
  - `pubkey` と credential identity mismatch rejects。
  - malformed `relays` tag rejects or normalized according to chosen policy。

#### Fix candidates if WhiteNoise sample is rejected

- Rejection reason が tag alias/shape 差分のみの場合: `normalize_key_package_event_for_mdk()` に限定的 normalization を追加する。ただし `pubkey`/credential identity mismatch と invalid MLS content は絶対に許容しない。
- MDK 0.7.1 が `30443` を直接 parse できる前提が安定したら、kind rewrite を削除または feature-gated にし、strict 30443 validation (`d`, `mls_proposals`, `i`) を活かす。
- Platform fetch 側は `30443` と `443` の両方を query し、同一 owner の最新 valid KeyPackage を選ぶ。Welcome 1059 recipient は常に selected KeyPackage event owner (`event.pubkey`) にする。

---

### P6-S2: NuruNuru invites WhiteNoise

**目的**  
NuruNuru generated 1059 Welcome を WhiteNoise が process できること。

**必要ログ**

- Kind 445 commit JSON
- Kind 1059 welcome outer metadata
- recipient p tag
- relay list
- WhiteNoise error if fail

**2026-04-24 P6-S2 analysis / current status**

このセッションではコード変更なしで確認を試みた。repo 内に WhiteNoise CLI / fixture / sample event が無く、WhiteNoise 側での実 process までは実行できなかった。そのため interop 実測は **blocked: no WhiteNoise runtime/sample provided** として扱う。

確認できた範囲:

1. WhiteNoise 側で KeyPackage publish: 未実行。WhiteNoise KeyPackage event JSON は未取得。
2. NuruNuru が KeyPackage fetch: 未実行。実 relay sample が無いため未確認。
3. NuruNuru `add_member`: NuruNuru generated KeyPackage では `mls_marmot_flow` で pass。
4. NuruNuru Kind 445 commit + Kind 1059 Welcome publish shape: local regression で以下を確認済み。
   - add-member commit は signed Kind 445 event JSON。
   - Kind 445 `h` tag / `groupIdHex` は Nostr group id。
   - Welcome は Kind 444 rumor を Kind 1059 gift-wrap した event JSON。
   - Kind 1059 outer `p` tag は KeyPackage event owner pubkey。
   - `WelcomeEventData.recipient_pubkey == key_package_event.pubkey`。
5. WhiteNoise process Welcome: 未実行。WhiteNoise error message は未取得。

WhiteNoise error 分類:

- 今回は WhiteNoise error が無いため分類不可。
- 次回取得時は少なくとも以下に分類する。
  - `unwrap_invalid_hmac_or_recipient`: 1059 `p` tag / NIP-59 recipient mismatch。NuruNuru 側は KeyPackage owner を recipient にする実装・regression があるため、実 sample で `p == WhiteNoise pubkey` を再確認する。
  - `welcome_rumor_shape`: unwrap は成功したが Kind 444 rumor の kind/tags/content が WhiteNoise expected shape と不一致。
  - `mls_process_welcome`: Kind 444 は読めたが MLS Welcome / credential / KeyPackage lifecycle の不一致で失敗。
  - `post_join_state`: Welcome process は成功したが self-update / epoch / commit ordering で後続が失敗。

NuruNuru event shape の現時点評価:

- 既存 Rust regression (`marmot_welcome_giftwrap_and_message_flow_works`) 上は問題なし。
- 重要な interop guard は満たしている。
  - FFI / App 境界の `groupIdHex` は Nostr group id で、internal MLS group id は外へ出さない。
  - Welcome 1059 recipient は Welcome rumor pubkey ではなく KeyPackage event owner pubkey。
- 未確認なのは WhiteNoise generated KeyPackage を `normalize_key_package_event_for_mdk()` + `mdk.parse_key_package()` が受理し、その KeyPackage に対する MDK generated Welcome を WhiteNoise が受理できるか、という実装間差分。

追加すべき Rust regression test:

- `whitenoise_key_package_can_receive_nurunuru_welcome`（fixture 取得後）
  - WhiteNoise signed KeyPackage event JSON fixture を読み込む。
  - `event.pubkey == expected_whitenoise_pubkey` を assert。
  - NuruNuru Alice が `mls_validate_key_package_event()` で validation。
  - Alice が `mls_create_group()` → `mls_add_member(groupIdHex, fixture_json)`。
  - add result の commit event が kind 445、`h` tag が `groupIdHex` と一致することを assert。
  - 1059 outer event が kind 1059、`p` tag が WhiteNoise pubkey、content length > 0 であることを assert。
  - WhiteNoise 側 unwrap/process までは Rust unit test 単独では不可なので、fixture-driven integration test または external harness で process result/error を保存する。
- `whitenoise_key_package_fixture_shape_documents_tags`
  - kind 30443/443、`encoding`, `i`, `relays`, `mls_*` tags の実 shape を snapshot 的に固定し、NuruNuru の normalization 必要有無を明示する。

修正候補（実 WhiteNoise error 取得後に選択）:

- `unwrap_invalid_hmac_or_recipient` の場合:
  - まず outer 1059 `tags` の `p` が WhiteNoise KeyPackage event `pubkey` と一致するか確認する。
  - 一致しないなら Rust core の recipient regression を拡張。ただし現実装は `key_package_owner_pubkey` を使っているため、platform fetch/selection で別 pubkey の KeyPackage を渡していないかを優先調査する。
- `welcome_rumor_shape` の場合:
  - Kind 444 rumor JSON（content は必要最小限の metadata）を WhiteNoise expected shape と比較する。
  - MDK generated rumor の kind/tags/content encoding 差分なら mdk-core compatibility issue として切り分ける。
- `mls_process_welcome` の場合:
  - WhiteNoise KeyPackage fixture の credential identity、`i` tag KeyPackageRef、MLS protocol/ciphersuite/extensions/proposals を確認する。
  - tag alias/shape 差分のみなら KeyPackage normalization を限定追加する。credential/event signer mismatch や invalid MLS content は許容しない。
- `post_join_state` の場合:
  - WhiteNoise 側が Welcome 後 self-update を要求するか、NuruNuru commit publish/merge timing と epoch ordering を確認する。

次回 P6-S2 実測に必要な入力:

- WhiteNoise KeyPackage event JSON（signed full event）。
- NuruNuru が publish した Kind 445 commit full event JSON。
- NuruNuru Kind 1059 outer event metadata: `id`, `pubkey`, `kind`, `tags` 内 `p`, `content.length`。
- WhiteNoise process error full message（secret/content は除外）。
- WhiteNoise pubkey と 1059 recipient `p` tag の一致結果。

---

### P6-S3: WhiteNoise invites NuruNuru

**目的**  
WhiteNoise generated 1059 Welcome を NuruNuru が process できること。

**作業**

- NIP-59 unwrap error の分類。
- Kind 444 validation error の分類。
- MDK process_welcome error の分類。

**2026-04-24 P6-S3 analysis / current status**

このセッションではコード変更なしで確認を試みた。repository 内、過去セッション記録内に WhiteNoise が NuruNuru を invite した実 event sample、log、WhiteNoise runtime は見つからなかった。そのため interop 実測は blocked: no WhiteNoise-generated 445/1059 sample provided として扱う。

確認できた範囲:

1. NuruNuru KeyPackage publish は実 relay では未実行。iOS と Android は login 後に KeyPackage publish path を持ち、published event id を prefs に保存する。実測の KeyPackage id/kind/pubkey は未取得。
2. WhiteNoise invite、WhiteNoise Kind 445 commit、Kind 1059 Welcome publish は未実行。実測の 1059 id/pubkey/p tag/kind/content length は未取得。
3. NuruNuru fetch path は確認済み。iOS は kind 1059 #p が自分の pubkey の filter を primary とし、必要なら broad fetch から自分宛 p tag のみ抽出する。Android は kind 1059 #p と legacy kind 444 #p を fetch し、1059 は自分宛 p tag が無いものを unwrap 前に skip する。
4. Rust mls_process_welcome は signed kind 1059 を NIP-59 unwrap し、inner rumor JSON を MlsManager process_welcome に渡す。legacy kind 444 は直接渡す。
5. MlsManager process_welcome は inner JSON を UnsignedEvent として parse し、kind 444 を要求し、MDK process_welcome と accept_welcome を実行する。成功時に外へ返す group_id_hex は Nostr group id。
6. post-join self-update path は iOS/Android とも存在する。Welcome process 成功後に mlsCreateRecoveryCommit groupIdHex、Kind 445 publish、publish success なら mlsMergePendingCommit groupIdHex を実行する。groupIdHex は FFI/App 境界 contract 通り Nostr group id。

現時点の成功/失敗 step:

- Step 1 NuruNuru KeyPackage publish: 実測未実行、実装 path のみ確認。
- Step 2 WhiteNoise invite: 未実行。
- Step 3 WhiteNoise Kind 445 + Kind 1059 publish: 未実行。
- Step 4 NuruNuru Kind 1059 fetch: 実 relay sample が無いため未実行、実装 path のみ確認。
- Step 5 NuruNuru mlsProcessWelcome: WhiteNoise sample が無いため未実行。NuruNuru generated fixture では既存 Rust regression が pass。
- Step 6 post-join self-update: WhiteNoise sample 後の実測は未実行。NuruNuru generated flow では mls_self_update_flow regression が pass。

Error classification status:

- NIP-59 unwrap error: 未取得。WhiteNoise 1059 sample が無いため有無不明。
- Kind 444 validation error: 未取得。unwrap 後 rumor sample が無いため有無不明。
- MDK process_welcome error: 未取得。WhiteNoise Welcome payload sample が無いため有無不明。

取得すべき実測ログ:

- NuruNuru KeyPackage event: id, kind, pubkey, created_at, public tags。
- WhiteNoise Kind 445 commit: id, kind, pubkey, h tag, created_at、可能なら full event JSON。
- WhiteNoise Kind 1059 outer metadata: id, pubkey, p tag, kind, content length, created_at, publish relay。
- NuruNuru error log: gift-wrap unwrap failed の有無、Welcome event must be kind 444 または unsigned event parse error の有無、process_welcome または accept_welcome error の有無、self-update publish/merge の成否。

修正候補:

- invalid HMAC など unwrap 失敗なら、WhiteNoise 1059 outer p tag が NuruNuru KeyPackage owner pubkey と一致するかを最初に確認する。一致しない場合は WhiteNoise recipient selection または NuruNuru KeyPackage publish/fetch 対象 pubkey の問題。
- unwrap 成功後の Kind 444 validation error なら、inner rumor が unsigned kind 444 event JSON か、WhiteNoise が signed event JSON や content-only payload を wrap していないかを確認する。
- MDK process_welcome error なら、WhiteNoise Welcome が消費した KeyPackageRef と NuruNuru published KeyPackage/local init-key material の一致、protocol version、ciphersuite、extensions、proposals、commit/welcome ordering を確認する。
- post-join self-update 失敗なら、mlsProcessWelcome が返した groupIdHex が Nostr group id で Kind 445 h tag と一致するか、および publish success 時 merge / all-fail 時 clear の policy を確認する。

追加すべき regression / interop test:

- whitenoise_welcome_1059_can_be_processed_by_nurunuru: WhiteNoise 1059 fixture を matching NuruNuru key and MLS DB/init-key material で mls_process_welcome に渡し、kind 1059、p tag、content length、returned Nostr group id と WhiteNoise 445 h tag の一致を assert。
- whitenoise_welcome_unwrap_error_is_classified: wrong recipient key で gift-wrap unwrap failed 系 error になることを assert。
- whitenoise_welcome_inner_kind_validation: unwrap 後 inner rumor が kind 444 であること、kind mismatch を reject することを assert。
- whitenoise_welcome_post_join_self_update_roundtrip: Welcome process 後 groups_needing_self_update に Nostr group id が出て、create_recovery_commit が Kind 445 を返し、merge_pending_commit できることを assert。

---

### P6-S4: WhiteNoise message interop

**目的**  
Kind 445 application message 双方向復号。

**作業**

- self-update 後の epoch 確認。
- h tag = Nostr group id 確認。
- duplicate/out-of-order 再送確認。

**2026-04-24 P6-S4 analysis / current status**

このセッションではコード変更なしで確認を試みた。repository 内に WhiteNoise runtime、WhiteNoise generated Kind 445 application message fixture、WhiteNoise 側 decrypt log、または P6-S2/P6-S3 実測成功ログは見つからなかった。そのため WhiteNoise と NuruNuru の実双方向復号は **blocked: no WhiteNoise runtime/sample/log provided** として扱う。

前提確認:

- P6-S2 NuruNuru invites WhiteNoise: repository/docs 上は実測未完了。NuruNuru generated add-member commit / 1059 Welcome shape は local Rust regression で確認済みだが、WhiteNoise が Welcome を process した証跡は未取得。
- P6-S3 WhiteNoise invites NuruNuru: repository/docs 上は実測未完了。WhiteNoise generated 445/1059 sample が無く、NuruNuru の WhiteNoise Welcome process 実測は未取得。
- P6-S4 の前提である join 後 self-update 完了は、WhiteNoise interop 実測としては未確認。local NuruNuru⇄NuruNuru regression では Welcome 後に groups_needing_self_update が Nostr group id を返し、post-join self-update commit publish/merge simulation 後に Alice 側が commit として process できることを確認済み。

確認できた NuruNuru local behavior:

- `mls_create_message(groupIdHex, content)` は FFI/App 境界の `groupIdHex` を Nostr group id として受け取り、内部で MLS group id に resolve して MDK `create_message` を呼ぶ。internal MLS group id は外へ出さない。
- 生成される Kind 445 event JSON は `h` tag に Nostr group id を入れる想定で、`mls_self_update_flow` / `mls_group_id_semantics` regression が `h == group.group_id_hex` を assert している。
- `mls_process_message_result(groupIdHex, eventJson)` は kind 445、base64 content、minimum encrypted payload length、`h` tag presence、`h == groupIdHex` を MDK 処理前に確認する。missing/wrong `h` は unprocessable state update として分類され、wrong group の復号を試みない。
- post-join self-update 後の NuruNuru⇄NuruNuru application message は双方向に復号できる regression がある。
- out-of-order delivery は、self-update commit より先に後続 application message が届いた場合に retryable/unprocessable として扱い、commit 処理後に同一 message を retry して復号できる regression がある。duplicate commit/message は panic/error ではなく idempotent な分類になる regression がある。

P6-S4 実測結果:

| Direction | Result | Error classification | Notes |
|---|---|---|---|
| NuruNuru -> WhiteNoise | 未確認 / blocked | WhiteNoise error 未取得 | WhiteNoise が NuruNuru generated Kind 445 application message を受信・復号した log が無い。 |
| WhiteNoise -> NuruNuru | 未確認 / blocked | NuruNuru error 未取得 | WhiteNoise generated Kind 445 application message fixture/event id/log が無い。 |

現時点で怪しい箇所の切り分け状況:

- group id: NuruNuru local regression では `groupIdHex` と Kind 445 `h` tag は Nostr group id で一致。WhiteNoise event の `h` が同じ Nostr group id かは sample 未取得のため未確認。
- epoch: NuruNuru local regression では self-update commit 後に双方向 message が復号でき、out-of-order 時は retryable/unprocessable になる。WhiteNoise と epoch が一致しているか、WhiteNoise が NuruNuru self-update commit を process 済みかは未確認。
- relay: 実 relay publish/subscribe 経路未確認。Kind 445 が両者の共通 relay に publish され、`#h` filter で取得できているか未確認。
- content shape: NuruNuru generated Kind 445 は signed event JSON / base64 content / encrypted payload length guard を満たす。WhiteNoise generated content encoding、h tag shape、kind は sample 未取得のため未確認。
- duplicate: NuruNuru local regression では duplicate commit/message は idempotent に扱える。WhiteNoise 側の duplicate handling は未確認。

次回 P6-S4 実測で取得すべき最小ログ（secret / plaintext payload は出さない）:

- group id: Nostr group id hex、WhiteNoise 表示/内部 group id と Kind 445 `h` tag の対応。internal MLS group id はログに出さない。
- join/self-update state: Welcome process success、post-join self-update Kind 445 event id、publisher、publish relay、merge/accepted status、local epoch before/after（可能なら数値のみ）。
- NuruNuru -> WhiteNoise message: NuruNuru generated Kind 445 event id、kind、pubkey、created_at、`h` tag、content length、publish relay、WhiteNoise decrypt result/error class。plaintext は `p6s4-n2w` など最小テスト文字列のみ、secret はログ禁止。
- WhiteNoise -> NuruNuru message: WhiteNoise generated Kind 445 event id、kind、pubkey、created_at、`h` tag、content length、publish relay、NuruNuru `mls_process_message_result` result/error class。plaintext は `p6s4-w2n` など最小テスト文字列のみ、secret はログ禁止。
- retry/duplicate: 同一 event id 再処理時の分類、out-of-order delivery があれば retry queue に残ったか、commit 後 retry で復号できたか。

失敗時の error 分類:

- `wrong_group_id_or_h_tag`: Kind 445 `h` tag が Nostr group id と一致しない、missing h tag、または app が internal MLS group id を渡している。修正候補は FFI/App 境界で groupIdHex=Nostr group id を再固定し、relay filter `#h` と process 引数を同じ値にする。
- `epoch_or_state_not_ready`: self-update commit 未処理、commit/message out-of-order、local epoch gap。修正候補は missing commit を retry queue 優先で process し、application message は retryable/unprocessable として processed set に入れない。
- `content_shape_invalid`: kind != 445、content が standard base64 でない、decoded payload が短すぎる、signed event JSON ではない。修正候補は WhiteNoise/NuruNuru generated event shape を MIP-03 に合わせ、normalization は security review 後に限定追加する。
- `relay_visibility`: publish relay と subscribe relay が重ならない、`#h` filter 不一致、relay duplicate/drop。修正候補は group relays と fetch relaysをログで比較し、少なくとも共通 relay 1 件で publish/fetch する。
- `duplicate_policy`: duplicate event を fatal error として扱う、または visible message が二重 append される。修正候補は processed Kind 445 ids per group と retryable queue policy を platform 側に固定する。

追加すべき regression / interop test:

- `whitenoise_to_nurunuru_kind445_application_message_fixture_decrypts`: WhiteNoise generated Kind 445 fixture と matching NuruNuru MLS DB state fixtureを使い、`h == Nostr group id`、`mls_process_message_result` が `ApplicationMessage` を返すことを assert。
- `nurunuru_to_whitenoise_kind445_application_message_fixture_decrypts`: NuruNuru generated Kind 445 fixture を WhiteNoise external harness で decrypt し、result/error class を保存する。Rust unit test 単独ではなく fixture-driven interop harness が必要。
- `whitenoise_kind445_h_tag_mismatch_is_non_retryable`: WhiteNoise-like fixture の `h` mismatch/missing を NuruNuru が unprocessable/drop 分類し、wrong group decrypt を試みないことを assert。
- `whitenoise_kind445_epoch_gap_is_retryable`: self-update commit より先に WhiteNoise application message が届く fixture で retryable/unprocessable になり、commit 処理後 retry で復号できることを assert。
- `kind445_duplicate_replay_does_not_double_append`: 同一 WhiteNoise message event id を二度処理して fatal error や二重 visible append にならないことを platform processed-id policy と合わせて assert。

---

## 10. P7: production hardening

### P7-S1: log redaction

**対象**

- Rust logs
- iOS AppLogger
- Android Log

**方針**

- private key, MLS plaintext payload, decrypted secret は出さない。
- event id / kind / pubkey prefix / group id は可。

---

### P7-S2: migration / storage cleanup

**目的**

groupIdHex=Nostr group id へ contract を固定した後も、旧 build の prefs/cache や pending commit が残っている端末を壊さず復旧できる方針を定義する。P7-S2 では destructive migration は実装しない。

**調査結果**

- Rust core は resolve_group_id(nostr_group_id_hex) で Nostr group id から internal MLS group id を引き直し、MlsGroupInfo.group_id_hex / process_welcome return / message history は Nostr group id を返す。
- iOS の永続 MLS prefs: mlsJoinedAtByGroupId, mlsSelfUpdateCompletedAtByGroupId, hiddenMlsGroupIds, mlsKeyPackageEventJsonById, mlsConsumedKeyPackageEventIds。mlsProcessedIds / retryable state / processedWelcomeIds はセッション内 state。
- Android の永続 MLS prefs: mls_self_update_success_at_<groupIdHex>, mlsPublishedKeyPackageEventId, mlsPublishedKeyPackageAt, mlsConsumedKeyPackageEventIds。Android cache には cached MLS groups/messages と left group ids がある。mlsProcessedIds / retry queue / processedWelcomeIds はセッション内 state。
- old group id semantics の影響を受ける可能性があるのは group id keyed prefs/cache（joined/self-update/hidden/left/cached messages）。consumed KeyPackage set は Nostr event id keyed なので semantics migration 対象ではない。

**Migration 方針**

1. mlsListGroups() を source of truth として current Nostr group id set を作る。
2. group id keyed prefs/cache は以下に分類する。
   - current: 64 hex かつ current set に存在。通常使用。
   - orphan: 64 hex だが current set に存在しない。保持するが FFI に渡さない。
   - legacy: 64 hex でない、または internal MLS group id 長（例: 32 hex）に見える。保持/退避するが FFI に渡さない。
3. legacy id を Nostr group id に推測変換しない。安全な mapping が必要なら Rust 側に明示 API / diagnostic export を追加する別セッションで扱う。
4. UI/cache filtering は current Nostr group id のみを使い、legacy hidden/left id で current group を誤って隠さない。
5. 実装時は backup key（例: *_legacy_group_id_v1）へ退避してから pruning する。即削除しない。

**Stale pending commit recovery 方針**

- 起動 / foreground / send 前に Nostr group id で mlsMergePendingCommit(groupIdHex) を 1 回 best-effort する。
- pending publish metadata がある場合のみ自動 clear 判定する。
  - 1 relay 以上 ACK: publish success とみなし merge retry。自動 clear しない。
  - 0 ACK かつ all relay failure 確定: mlsClearPendingCommit(groupIdHex) 可。
  - metadata なしの legacy stale pending: destructive clear しない。catch-up 後も詰まる場合は repair UI / diagnostic flow へ回す。
- 今後 platform 側で nostr_group_id_hex, operation, commit_event_id, created_at, target_relays, ack_count, last_error_class を保存する。

**Consumed KeyPackage cleanup 方針**

- consumed set は event id（64 hex lowercase）として正規化し、fetch 時に除外する。
- cleanup は empty / invalid hex / duplicate 除去、上限件数または TTL pruning に限定する。relay delete は best-effort のため、古い id を短期間で消さない。
- iOS の mlsKeyPackageEventJsonById は mlsDeleteConsumedKeyPackageFromEventJson() fallback 用。対応 consumed id の local cleanup / rotation が終わるまでは保持する。
- 将来は event_id -> metadata(consumed_at, kind, pubkey, created_at) に移行し、90 日超の legacy 443 / delete 済み JSON から順に削除する。

**必要最小実装（本セッション）**

- docs/MARMOT_DESIGN.md に migration / stale pending / consumed cleanup policy を追記。
- docs/MARMOT_IMPLEMENTATION_PLAN.md の P7-S2 を詳細化。
- iOS / Android prefs の destructive migration は未実装。

**次の実装候補**

- iOS AppPreferences に group id keyed map sanitizer（current/orphan/legacy 分類、backup key 保存）を追加。
- Android AppPreferences / NostrCache に同等 sanitizer を追加。
- platform pending publish metadata を追加し、all-fail のみ自動 clear する。

---

### P7-S3: background retry / battery policy

**目的**

Marmot の self-update / message publish / KeyPackage rotation を同一 retry として混ぜず、iOS / Android の background execution 制約と battery policy に合わせて drain できる設計にする。`groupIdHex` は FFI / App 境界では Nostr group id のみを指し、internal MLS group id は外へ出さない。

**共通設計**

- retry queue を 3 種類に分ける。
  1. self-update retry: MIP-02 post-join self-update / recovery commit。
  2. message retry: application message Kind 445 の signed outer event 再送。
  3. KeyPackage rotation retry: consumed / stale / missing KeyPackage の再発行。
- retry item の最小 metadata:
  - `queueType`, `accountPubkey`, `groupIdHex` (Nostr group id), `eventId`, `relayUrls`, `attemptCount`, `nextAttemptAt`, `lastErrorKind`。
  - message retry は signed outer event JSON を保持し、再送時に MLS state を再生成しない。
  - self-update retry は pending commit の authoritative state を Rust/MDK に置き、platform は scheduling metadata のみ保持する。
  - KeyPackage rotation retry は KeyPackage event owner pubkey と KeyPackage event id を保持する。Welcome 1059 の recipient は KeyPackage event owner pubkey であり、Welcome rumor pubkey ではない。
- 成功条件:
  - self-update: Kind 445 commit が 1 relay 以上に publish 成功し、pending commit merge が成功する。
  - message: 1 relay 以上に publish 成功したら sent とみなす。partial fail relay は relay cooldown のみ更新する。
  - KeyPackage rotation: latest KeyPackage event id が保存され、必要 relay に 1 件以上 publish 成功する。
- retry 対象外:
  - invalid payload / wrong `h` tag / malformed base64 / group id mismatch。
  - local signing key missing / user logout。
  - group deleted / left group。

**iOS 方針**

- iOS は background fetch / BGTask が必ず実行される保証がないため、foreground-first にする。
- trigger:
  - app 起動時、foreground 復帰時、Talk 画面表示時、group 詳細表示時。
  - foreground polling tick に piggyback して小さく drain。
  - `BGAppRefreshTask` を入れる場合も best-effort 扱い。実行されない前提で期限超過 UX を用意する。
- battery/network:
  - Low Power Mode では self-update / KeyPackage rotation の proactive retry を抑制し、foreground 復帰時の短い scan のみにする。
  - cellular では KeyPackage rotation の定期 retry を抑制し、ユーザー操作・foreground 復帰時のみ行う。
  - 1 回の wake で処理する item 数・relay 数・実行時間を制限する。
- 実装セッション分割:
  1. iOS retry metadata store 設計: private storage に queue item を保存し、private key は保存しない。`NostrRepository` actor からのみ操作。
  2. iOS foreground drain: app 起動/foreground/Talk 表示から self-update -> KeyPackage rotation -> message retry を drain。
  3. iOS optional BGAppRefreshTask: best-effort scan のみ。長時間 crypto/network を前提にしない。

**Android 方針**

- WorkManager + foreground polling + app foreground 復帰時処理を併用する。
- WorkManager:
  - unique work 名: `marmot_retry_<account_pubkey>`。多重起動を避ける。
  - `NetworkType.CONNECTED` を必須 constraint にする。
  - self-update / KeyPackage rotation は battery-not-low constraint を付ける。
  - message retry はユーザー送信直後のみ short/expedited work を許可し、それ以外は通常 work。
  - WorkManager backoff に加えて item の `nextAttemptAt` を見て二重 rate limit する。
- foreground polling:
  - app foreground 中は既存 Talk / relay polling に piggyback し、WorkManager より短い interval で drain。
  - foreground 復帰時に軽量 scan して queue があれば drain。
- 実装セッション分割:
  1. Android retry metadata store: DataStore/Room/既存 prefs のどれに置くかを確定し、signed event JSON と scheduling metadata を保存。
  2. Android WorkManager worker: 3 queue を順に drain し、constraints/backoff を適用。
  3. Android foreground integration: `NostrRepositoryTalk` / ViewModel の foreground polling と復帰時 hook から drain。

**Relay retry backoff proposal**

- per relay URL と per queue item の両方に backoff を持つ。
- base 30s、multiplier 2.0、jitter ±20%。
- max delay:
  - foreground drain: 15m。
  - background / WorkManager / BGTask: 6h。
- relay-level cooldown:
  - connection failure / timeout / rate limit / relay policy reject は relay URL 単位で共有。
  - AUTH required は signer/session state を確認するまで同 relay を cooldown。
- TTL:
  - message retry: 7 days またはユーザーが送信失敗を削除するまで。
  - self-update retry: group が存在する限り維持。join 後 24h deadline 超過は warning + UI 表示対象。
  - KeyPackage rotation retry: 新しい KeyPackage publish 成功まで維持。成功後に consumed package metadata を cleanup。

**完了条件**

- [ ] self-update / message / KeyPackage rotation の retry store と drain API が別々に定義されている。
- [ ] iOS は foreground-first で、BGTask は best-effort として扱われている。
- [ ] Android は WorkManager constraints と foreground polling の責務分担が明確。
- [ ] relay retry backoff と terminal failure の分類が実装に落とせる。
- [ ] `groupIdHex` は Nostr group id としてのみ永続化・ログ出力される。

---

## 11. 推奨 goose セッション指示テンプレート

## 11.1 Rust test session

```text
目的: Marmot の [対象] regression test を追加して pass させてください。

必ず読む:
- docs/MARMOT_DESIGN.md
- docs/MARMOT_IMPLEMENTATION_PLAN.md
- rust-engine/nurunuru-core/src/mls.rs
- rust-engine/nurunuru-core/src/engine.rs
- rust-engine/nurunuru-core/tests/mls_marmot_flow.rs

編集してよいファイル:
- [限定ファイル]

編集してはいけないファイル:
- iOS/Android files
- FFI bindings

実行テスト:
cd rust-engine && cargo test -p nurunuru-core --test [test_name] -- --nocapture

完了報告:
変更ファイル、実行テスト、結果、未解決、次への引き継ぎを報告してください。
```

## 11.2 iOS session

```text
目的: iOS の Marmot [対象 flow] を修正してください。

必ず読む:
- docs/MARMOT_DESIGN.md
- docs/MARMOT_IMPLEMENTATION_PLAN.md
- ios/MLS_FFI_PLAN.md
- ios/NuruNuru/Data/NostrRepository+Talk.swift

編集してよいファイル:
- ios/NuruNuru/Data/NostrRepository+Talk.swift
- 必要なら prefs 定義ファイル 1 個まで

編集してはいけないファイル:
- Rust core
- Android

ビルド:
cd ios && xcodebuild -scheme NuruNuru -destination 'platform=iOS Simulator,name=iPhone 17' -skipPackagePluginValidation build

完了報告:
変更ファイル、実行テスト、結果、未解決、次への引き継ぎを報告してください。
```

## 11.3 Android session

```text
目的: Android の Marmot [対象 flow] を修正してください。

必ず読む:
- docs/MARMOT_DESIGN.md
- docs/MARMOT_IMPLEMENTATION_PLAN.md
- android/app/src/main/kotlin/io/nurunuru/app/data/NostrRepositoryTalk.kt

編集してよいファイル:
- android/app/src/main/kotlin/io/nurunuru/app/data/NostrRepositoryTalk.kt
- 必要なら prefs 定義ファイル 1 個まで

編集してはいけないファイル:
- Rust core
- iOS

ビルド:
cd android && ./gradlew assembleDebug

完了報告:
変更ファイル、実行テスト、結果、未解決、次への引き継ぎを報告してください。
```

## 11.4 WhiteNoise interop analysis session

```text
目的: WhiteNoise interop の [対象 event] を分析してください。コード変更はしないでください。

入力:
- event JSON samples
- NuruNuru logs
- WhiteNoise logs if available

必ず読む:
- docs/MARMOT_DESIGN.md

出力:
- NuruNuru expected shape
- WhiteNoise actual shape
- 差分
- 修正候補
- 追加すべき regression test
```

---

## 12. 優先順位つき次タスク

次に進めるならこの順番を推奨する。

1. P0-S2: group id semantics regression test
2. P0-S3: Welcome recipient regression test
3. P1-S3: post-join self-update full roundtrip
4. P1-S2: pending commit success/failure policy
5. P1-S4: KeyPackage consumed/rotation core logic
6. P2-S1: FFI API comment / naming 整理
7. P3-S2 / P4-S2: platform self-update retry loop
8. P5-S1/P5-S2: iOS Android cross interop
9. P6: WhiteNoise interop

---

## 13. 完了見積もり

| 到達点 | 目安 |
|---|---:|
| Rust core tests green | 1〜3日 |
| iOS/Android NuruNuru 同士で実用 | 1〜2週間 |
| WhiteNoise interop 実用 | 2〜4週間 |
| production quality | 4〜8週間 |

---

## 14. リスク

| リスク | 対策 |
|---|---|
| ID semantics 混乱 | groupIdHex=Nostr group id をテストとコメントで固定 |
| pending commit stuck | publish fail 時 clear policy を徹底 |
| relay out-of-order | retry queue / duplicate processed set |
| KeyPackage reuse | consumed tracking + re-publish |
| WhiteNoise shape 差分 | sample-driven regression tests |
| goose セッション競合 | 編集ファイルを限定し、同時編集禁止ファイルを守る |
