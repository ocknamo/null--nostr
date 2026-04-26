# Marmot / MLS 実装設計書

> 対象: null--nostr / NuruNuru の Rust core + Android + iOS における Marmot MLS 実装。  
> 目的: WhiteNoise 互換を含む Marmot MIP-00〜03 の安定実装。  
> 更新日: 2026-04-24

---

## 1. ゴール

NuruNuru における Marmot 実装の第一ゴールは、以下を満たすこと。

1. NuruNuru 同士で MLS DM / group chat が安定して動作する。
2. WhiteNoise など外部 Marmot 実装と、少なくとも以下で相互運用できる。
   - KeyPackage publish / fetch
   - Welcome gift-wrap receive / process
   - Kind 445 group message send / receive
3. iOS / Android からは同一の FFI contract で MLS 機能を利用できる。
4. Nostr relay の out-of-order / duplicate / retry 前提で壊れない。
5. private key / MLS secret / KeyPackage lifecycle を安全に扱う。

---

## 2. 非ゴール / 後回し

初期 production-ready までの非ゴールは以下。

- Swift / Kotlin 側で MLS 暗号処理を再実装しない。
- Timeline / profile / follow / reaction など通常 Nostr 機能を Rust FFI に寄せない。
- MIP-04 encrypted media は MIP-00〜03 完走後に扱う。
- group data rotation / Nostr group id rotation は、まず受信・保存の互換性を確保し、UI exposed feature としては後段に回す。

---

## 3. レイヤ構成

```text
iOS / Android UI
  |
  | groupIdHex = Nostr group id hex
  v
Repository / ViewModel
  |
  | MLS only FFI
  v
nurunuru-ffi
  |
  v
nurunuru-core::NuruNuruEngine
  |
  | external API IDs are Nostr group IDs
  | internally resolve Nostr group ID -> MLS group ID
  v
MlsManager
  |
  | internal MDK API uses MLS group ID
  v
mdk-core / OpenMLS / mdk-sqlite-storage
```

---

## 4. ID 設計

Marmot/MDK には group id が 2 種類ある。

| ID | 意味 | 使用場所 | 外部 API |
|---|---|---|---|
| MLS group id | OpenMLS / MDK 内部 group key | `mdk.self_update`, `mdk.add_members`, `mdk.merge_pending_commit` | 原則非公開 |
| Nostr group id | Nostr routing 用 32-byte ID | Kind 445 `h` tag, relay filter, UI/API group id | 公開 |

## 4.1 NuruNuru の API contract

NuruNuru の外部 API / FFI / iOS / Android では:

```text
groupIdHex = Nostr group id hex
```

と定義する。

したがって `MlsGroupInfo.group_id_hex` も Nostr group id である。

```rust
MlsGroupInfo {
    group_id_hex: hex::encode(group.nostr_group_id),
    ...
}
```

## 4.2 内部操作時の変換

MDK API は MLS group id を要求するため、Rust wrapper 内で必ず変換する。

```rust
resolve_group_id(nostr_group_id_hex) -> mdk_storage_traits::GroupId // MLS group id
```

対象例:

- `mls_add_member(groupIdHex, ...)`
- `mls_create_message(groupIdHex, ...)`
- `mls_process_message_result(groupIdHex, ...)`
- `mls_merge_pending_commit(groupIdHex)`
- `mls_create_recovery_commit(groupIdHex)`
- `mls_clear_pending_commit(groupIdHex)`

## 4.3 `groups_needing_self_update()`

MDK の `groups_needing_self_update()` は internal MLS group id を返す。  
ただし NuruNuru の FFI contract では Nostr group id を返す必要がある。

正しい境界処理:

```text
MDK groups_needing_self_update()
  -> MLS group ids
NuruNuru wrapper
  -> get_group(mls_group_id)
  -> hex(group.nostr_group_id)
FFI / app
  -> Nostr group ids
```

---

## 5. Marmot event mapping

| Kind | 名称 | 役割 | NuruNuru 担当 |
|---:|---|---|---|
| 30443 | KeyPackage | MIP-00 canonical KeyPackage | Rust creates unsigned data, app signs/publishes if needed |
| 443 | legacy KeyPackage | 互換用 legacy KeyPackage | fetch/validation/normalization で受容 |
| 444 | Welcome rumor | MLS Welcome payload rumor | MDK generates, Rust validates |
| 1059 | NIP-59 Gift Wrap | Welcome rumor delivery | Rust gift-wraps using sender signer |
| 445 | Group Message / Commit | MLS app message / commit | MDK produces signed event JSON |

---

## 6. KeyPackage lifecycle

## 6.1 Publish

1. user login 後に local KeyPackage の有無を確認。
2. 必要なら `mls_create_key_package()` を呼ぶ。
3. Kind 30443 event を platform signer で署名。
4. relay に publish。
5. local prefs に published event id / timestamp を保存。

## 6.2 Fetch

招待側は member pubkey から KeyPackage を取得する。

- canonical: kind 30443
- legacy fallback: kind 443
- 最新の valid event を選ぶ。
- relay tag は必要に応じて patch/補完する。

## 6.3 Consume

add member 成功後、招待された側の KeyPackage は消費済みとして扱う。

必要な処理:

- 招待側: 使用した KeyPackage event id を記録。
- 参加側: Welcome process 後、自分の consumed KeyPackage を削除または無効化。
- 参加側: 新しい KeyPackage を再 publish。
- relay 上の古い KeyPackage を参照しないよう、fetch 時に consumed list を見る。

責務分担:

- MDK 0.7.x の inviter-side `add_members` は、同一 remote KeyPackage event を別 group への `add_member` に再利用しても拒否しない。
- したがって relay fetch で「使用済み KeyPackage event id を除外する」責務は platform 側の local prefs / consumed set に置く。
- Rust core は参加側の local init-key material 削除用に `mls_delete_consumed_key_package_from_event_json()` を提供するが、remote relay event の global consumed 状態は保持しない。
- `AddMemberResult` に consumed KeyPackage event id を追加する API 変更は現時点では不要。呼び出し元は `mls_add_member(groupIdHex, keyPackageEventJson)` に渡した signed event JSON から event id を既に取得できるため、platform 側でその event id を記録する。

## 6.4 Delete event

NIP-09 delete を使う場合:

- Kind 5 delete event を publish。
- 対象は consumed KeyPackage event id。
- relay により delete 反映は best-effort なので、local consumed set も必須。

---

## 7. Add member / Welcome flow

## 7.1 招待側 Alice

```text
Alice creates group
  -> mls_create_group()
  -> returns groupIdHex = Nostr group id

Alice fetches Bob KeyPackage
  -> kind 30443 or 443
  -> validates owner = Bob pubkey

Alice add member
  -> mls_add_member(groupIdHex, bobKeyPackageEventJson)
  -> MDK add_members produces:
       - Kind 445 commit event JSON
       - Kind 444 welcome rumor
  -> Rust gift-wraps welcome rumor to Bob pubkey
       - Kind 1059

Alice publishes
  -> Kind 445 commit
  -> Kind 1059 welcome

Alice merges pending commit
  -> mls_merge_pending_commit(groupIdHex)
```

## 7.2 Welcome gift-wrap recipient

Welcome 1059 recipient は必ず **KeyPackage event owner** にする。

```rust
let recipient = key_package_event.pubkey;
```

してはいけない:

```rust
let recipient = welcome_rumor.pubkey;
```

理由:

- MDK generated welcome rumor の `pubkey` は、NIP-59 recipient identity とは限らない。
- recipient を誤ると受信者側で `invalid HMAC` になる。

## 7.3 参加側 Bob

```text
Bob fetches Kind 1059 addressed to Bob
  -> NIP-59 unwrap
  -> obtain Kind 444 welcome rumor

Bob process welcome
  -> mls_process_welcome(welcomeEventJson)
  -> MDK process_welcome + accept_welcome
  -> local group becomes active
  -> self-update required

Bob performs post-join self-update
  -> mls_create_recovery_commit(groupIdHex)
  -> publish Kind 445
  -> mls_merge_pending_commit(groupIdHex)

Alice fetches Bob self-update Kind 445
  -> mls_process_message_result(groupIdHex, eventJson)
```

---

## 8. Message flow

## 8.1 Send application message

```text
app calls mls_create_message(groupIdHex, content)
  -> Rust resolves Nostr group id -> MLS group id
  -> MDK creates Kind 445 signed event JSON
app publishes raw Kind 445 event
```

Kind 445 must contain exactly one valid `h` tag:

```text
["h", nostr_group_id_hex]
```

## 8.2 Receive message

```text
app subscribes/fetches Kind 445 with #h = groupIdHex
for each event:
  validate kind/content/h tag shape
  call mls_process_message_result(groupIdHex, eventJson)
```

Result handling:

| Result | App behavior |
|---|---|
| application | append visible message, mark processed |
| state update commit/proposal | mark processed, maybe merge pending commit |
| unprocessable retryable | do not mark processed; retry later |
| invalid shape | mark dropped/processed to avoid loop |

---

## 9. Pending commit policy

Pending commit は失敗時の最大の事故要因なので、操作ごとにルールを固定する。

## 9.1 Local commit publish success

以下の順にする。

```text
create commit
publish Kind 445
if publish success:
    merge_pending_commit
else:
    clear_pending_commit
```

対象:

- add member
- remove member
- self-update / recovery commit
- leave group if commit/proposal path uses pending state

## 9.2 Partial relay publish

複数 relay publish の一部成功時は、以下の暫定ルールにする。

- 1 relay 以上成功なら success とみなし merge。
- 全 relay 失敗なら clear。
- publish result を log に残す。

将来的には relay quorum policy を導入できる。

## 9.3 Stale pending commit recovery

Pending commit は MLS state を fork させ得るため、migration で無条件に破棄しない。

原則:

1. app 起動 / foreground / send 前に mls_merge_pending_commit(groupIdHex) を 1 回だけ best-effort で試す。
2. groupIdHex は必ず Nostr group id。旧実装由来の internal MLS group id らしき値を FFI に渡して recovery しない。
3. pending commit の publish metadata がある場合だけ自動判断する。
   - ack_count >= 1: publish success 扱い。relay catch-up 後に merge を再試行し、失敗しても自動 clear しない。
   - ack_count == 0 かつ全 relay publish failure が確定: mls_clear_pending_commit(groupIdHex) して再試行可能にする。
   - partial success: success 扱いで merge。
4. metadata がない legacy stale pending commit は destructive migration しない。send を止めて catch-up / user visible repair flow / diagnostic log へ回す。
5. clear は「commit が relay に一切出ていない」ことを app が知っている場合、または明示的 repair 操作の場合に限定する。

将来追加する platform metadata は少なくとも以下を持つ。

- nostr_group_id_hex
- operation = add_member | remove_member | self_update | leave
- commit_event_id
- created_at
- target_relays
- ack_count
- last_error_class

この metadata 自体も Nostr group id で keying し、internal MLS group id は保存しない。

---

## 10. Self-update policy

MIP-02 post-join self-update は必須扱い。

## 10.1 Trigger

- `mls_process_welcome()` 成功直後。
- `groups_needing_self_update(threshold_secs)` に出た group。
- app 起動時 / foreground 復帰時 / 定期 polling 時。

## 10.2 Deadline

- join 後 24h 以内に self-update を publish する。
- 失敗した場合は retry queue に残す。

## 10.3 API

```text
mlsGroupsNeedingSelfUpdate(thresholdSecs) -> [nostr_group_id_hex]
mlsCreateRecoveryCommit(groupIdHex) -> Kind 445 commit data
mlsMergePendingCommit(groupIdHex)
mlsClearPendingCommit(groupIdHex)
```

## 10.4 Background retry / battery policy

Marmot の retry は platform 境界では常に Nostr group id を `groupIdHex` として扱う。internal MLS group id は FFI / App 境界・永続 key・ログへ出さない。Welcome 1059 の recipient は KeyPackage event owner pubkey であり、Welcome rumor pubkey ではないため、retry metadata も KeyPackage event id と owner pubkey を保持する。

Retry は次の 3 種類を分離して設計する。

| queue | 対象 | 成功条件 | 失敗時の扱い |
|---|---|---|---|
| self-update retry | MIP-02 post-join self-update / recovery commit | Kind 445 commit を少なくとも 1 relay に publish し、必要な pending commit を merge できた | group ごとに pending を保持し、同 epoch で commit を多重生成しない |
| message retry | application message Kind 445 publish | group relay / inbox relay のいずれかに publish 成功 | signed outer event JSON を再送。MLS state は再生成しない |
| KeyPackage rotation retry | consumed / stale / missing KeyPackage の再発行 | current KeyPackage event id を記録し、必要 relay に publish 成功 | stale package を使い続けないよう retry を維持。ただし battery 制約で頻度制限 |

### 10.4.1 iOS policy

iOS は任意タイミングの background execution を保証しないため、MLS retry は foreground-first とする。

- primary trigger:
  - app 起動時。
  - foreground 復帰時。
  - Talk 画面表示時 / group 詳細表示時。
  - 通常の foreground polling tick。
- optional background trigger:
  - `BGAppRefreshTask` を利用する場合も best-effort のみ。実行されない前提で UX を設計する。
  - `BGProcessingTask` は長時間 crypto / network を常用する目的では使わない。ユーザー操作直後の短い follow-up に限定する。
- battery/network:
  - Low Power Mode では message retry 以外の proactive retry を抑制する。
  - cellular では KeyPackage rotation の定期 retry を抑制し、foreground 復帰時のみ試行する。
  - 1 wake で処理する queue 数と relay 数に上限を置く。
- state:
  - private key は Keychain のみ。retry queue には signed event JSON / event id / Nostr group id / relay URL / nextAttemptAt / attempt count のみを保存する。
  - self-update の pending commit は Rust/MDK state を authoritative とし、platform prefs は scheduling metadata のみを持つ。

### 10.4.2 Android policy

Android は WorkManager と foreground polling を併用する。

- WorkManager:
  - unique work 名を `marmot_retry_<account_pubkey>` とし、既存 work を多重起動しない。
  - network connected constraint を必須にする。
  - battery not low constraint を self-update / KeyPackage rotation に適用する。message retry はユーザー送信直後の short retry を許可する。
  - expedited work はユーザーが送信した message retry の直後のみ。self-update / KeyPackage rotation は通常 work。
- foreground:
  - app foreground 中は既存 polling に piggyback し、WorkManager より短い interval で retry を drain する。
  - foreground 復帰時に self-update -> KeyPackage rotation -> message retry の順で軽量 scan し、未処理があれば drain する。
- lifecycle:
  - Doze / App Standby で遅延することを許容する。
  - failed work は WorkManager の backoff に加え、queue item の `nextAttemptAt` で二重に rate limit する。

### 10.4.3 Relay retry backoff

Relay ごと・queue item ごとに指数 backoff を持つ。

- base: 30s。
- multiplier: 2.0。
- jitter: ±20%。
- max: foreground 15m / background 6h。
- relay-level cooldown: connection failure / AUTH / rate limit は relay URL 単位で共有する。
- terminal failure:
  - invalid event shape / wrong `h` tag / malformed payload は retry しない。
  - relay policy reject は relay 単位で cooldown し、他 relay への retry は継続する。
  - all relay fail が続いても signed event JSON は TTL まで保持する。
- TTL:
  - message retry: 7 days またはユーザー削除まで。
  - self-update retry: group が存在する限り維持。24h deadline 超過時は警告ログ/UX 表示対象。
  - KeyPackage rotation retry: 新しい KeyPackage publish 成功まで維持。古い consumed package の retry metadata は成功後に cleanup。

---

## 11. Out-of-order / duplicate handling

Relay では順序保証がないため、以下を前提とする。

1. event id processed set を group ごとに持つ。
2. retryable unprocessable は processed に入れない。
3. invalid shape / wrong h-tag は processed/dropped に入れる。
4. epoch gap は retry queue に残す。
5. 新しい commit を処理した後、retry queue を再走査する。

---

## 12. Storage

## 12.1 Rust / MDK storage

- mdk sqlite path: platform-provided app files dir 配下。
- iOS / Android とも private app storage に置く。
- backup 対象にするかは platform policy で検討。

## 12.2 Platform prefs

Platform 側で持つもの:

- published KeyPackage event id
- consumed KeyPackage event ids
- `mlsJoinedAtByGroupId`
- `mlsSelfUpdateCompletedAtByGroupId`
- processed Kind 445 ids per group
- retryable Kind 445 ids per group

private key は絶対に prefs に置かない。

## 12.3 Migration / cleanup policy

P7-S2 時点の調査結果:

- iOS prefs は mlsJoinedAtByGroupId, mlsSelfUpdateCompletedAtByGroupId, hiddenMlsGroupIds, mlsKeyPackageEventJsonById, mlsConsumedKeyPackageEventIds を持つ。
- Android prefs は mls_self_update_success_at_<groupIdHex>, mlsPublishedKeyPackageEventId, mlsPublishedKeyPackageAt, mlsConsumedKeyPackageEventIds を持つ。Android cache には left group ids / cached MLS groups/messages がある。
- processed Kind 445 ids / retryable queue / Welcome processed ids は両 platform とも主にセッション内 state で、永続 migration 対象ではない。
- old group id semantics が混入し得る永続 key は「group id で keying された self-update / joined / hidden / left / cached group state」。consumed KeyPackage set は event id set なので group id semantics 変更の直接対象ではない。

Migration は non-destructive に行う。

1. 起動後、FFI mlsListGroups() から現在の Nostr group id set を得る。
2. prefs/cache 内の group id key を検査する。
   - 64 hex かつ current Nostr group id set に存在する: current として使用。
   - 64 hex だが current set に存在しない: orphan として保持するが FFI には渡さない。
   - 64 hex でない、または旧 internal MLS group id 長（例: 16 bytes = 32 hex）に見える: legacy id として隔離し、FFI には渡さない。
3. 安全に mapping できない legacy id は Nostr group id へ推測変換しない。Rust/MDK storage は Nostr group id を返す mlsListGroups() を source of truth にする。
4. legacy/orphan prefs は即削除せず、diagnostic log と optional backup key（例: *_legacy_group_id_v1）へ退避してから一定バージョン後に削除する。
5. UI/filter/cache は current Nostr group id のみを参照する。legacy hidden/left id で current group を隠さない。

Consumed KeyPackage cleanup:

- mlsConsumedKeyPackageEventIds は event id（64 hex lowercase）だけを保持し、fetch 時に除外する。
- cleanup は invalid hex / empty / duplicate の除去、lowercase 正規化、上限件数または TTL による pruning に限定する。
- relay delete は best-effort なので、古い consumed id を短期間で消す destructive cleanup はしない。
- 将来は event_id -> {kind, pubkey, created_at, consumed_at} の metadata 化を行い、90 日以上古い legacy 443 / relay delete 済み event JSON から順に削除する。
- mlsKeyPackageEventJsonById は local init-key material cleanup の fallback なので、対応する consumed id の処理が完了するまでは保持する。

---

## 13. FFI contract

MLS FFI は MLS のみに限定する。

必須 API:

```text
mlsCreateKeyPackage
mlsCreateGroup
mlsAddMember
mlsRemoveMember
mlsLeaveGroup
mlsListGroups
mlsGetGroupInfo
mlsCreateMessage
mlsProcessMessageResult
mlsProcessWelcome
mlsGetMessageHistory
mlsMergePendingCommit
mlsCreateRecoveryCommit
mlsClearPendingCommit
mlsGroupsNeedingSelfUpdate
```

すべての `groupIdHex` は Nostr group id。

---

## 14. Security requirements

- private key は Keychain / Android secure storage / Rust memory 内のみ。
- logs に secret / MLS payload plaintext / private key を出さない。
- Welcome unwrap error は event id / kind / recipient まで。content は出さない。
- KeyPackage は公開情報だが、消費済み管理は local で厳密にする。
- publish failure 時の pending commit cleanup を必ず行う。

---

## 15. Interop test matrix

## 15.1 Rust integration tests

必須:

- KeyPackage 30443 validation passes
- legacy 443 validation passes
- invalid KeyPackage content rejects
- add member returns valid Kind 445 / 444 / 1059
- 1059 unwrap by recipient succeeds
- wrong recipient unwrap fails
- process welcome joins group
- process welcome marks self-update required
- post-join self-update roundtrip
- application message after self-update decrypts
- out-of-order commit/message retry behavior
- duplicate event idempotency

## 15.2 Platform tests

- iOS: create group -> add member -> welcome -> self-update -> send message
- Android: same
- cross-platform: iOS invites Android, Android invites iOS

## 15.3 External interop

- NuruNuru invites WhiteNoise
- WhiteNoise invites NuruNuru
- KeyPackage fetch both ways
- Kind 445 message both ways
- duplicate/replayed Welcome behavior

---

## 16. Current known status

As of 2026-04-24:

- direct NIP-59 gift-wrap roundtrip: pass
- engine signer welcome rumor gift-wrap: pass
- Marmot welcome gift-wrap and message flow: pass after recipient fix
- KeyPackage 30443 / 443 validation: pass
- invalid MLS outer payload rejection: pass

Known important fixes already applied:

- Welcome 1059 recipient uses KeyPackage event owner, not welcome rumor pubkey.
- `mls_process_welcome()` accepts the welcome after processing.
- `groups_needing_self_update()` converts internal MLS group id to Nostr group id at FFI boundary.

---

## 17. Completion definition

## 17.1 Core complete

- Rust integration tests for MIP-00〜03 pass.
- ID boundary is tested.
- pending commit success/failure paths are tested.
- out-of-order basic retry is tested.

## 17.2 App complete

- iOS and Android can both create/join/send/decrypt.
- post-join self-update is automatic and retryable.
- consumed KeyPackage rotation/delete works.
- relay fetch/subscribe uses Nostr group id `h` tag.

## 17.3 Interop complete

- WhiteNoise invite both directions works.
- WhiteNoise message both directions works.
- known relay delays / duplicates do not break state.
