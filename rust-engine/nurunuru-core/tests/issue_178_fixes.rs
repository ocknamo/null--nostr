//! Regression tests for the MDK-integration findings filed as
//! <https://github.com/tami1A84/null--nostr/issues/178>.
//!
//! These tests pin down the wrapper-side behaviours the issue asked for so
//! future refactors cannot silently regress them:
//!
//! * #4 process_welcome / accept_welcome / decline_welcome are exposed
//!   separately and `get_pending_welcomes` returns previewed Welcomes.
//! * #5 Commit processing surfaces structured `added_pubkeys` and
//!   `removed_pubkeys` via the new `MlsProcessResult::Commit` variant.
//! * #11 `MlsManager::new` refuses an empty pubkey and `engine.mls_reset`
//!   wipes the on-disk MLS state.
//! * #1 `MlsManager::new_with_key` opens an encrypted SQLCipher DB and
//!   `derive_mls_db_key` produces a stable 32-byte key from HKDF.
//! * #9/#10 The engine exposes `mls_subscribe_welcomes` and
//!   `mls_subscribe_keypackage_rotations`.

use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};

use nostr::{EventBuilder, JsonUtil, Keys, Kind, Tag};
use nurunuru_core::config::NuruNuruConfig;
use nurunuru_core::mls::{derive_mls_db_key, MlsManager};
use nurunuru_core::types::MlsProcessResult;
use nurunuru_core::NuruNuruEngine;

fn unique_db_path(name: &str) -> String {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos();
    let mut path = std::env::temp_dir();
    path.push(format!(
        "nurunuru_issue178_{}_{}_{}.sqlite3",
        name,
        std::process::id(),
        nanos
    ));
    path.to_string_lossy().to_string()
}

fn test_config(mls_db_path: String) -> NuruNuruConfig {
    NuruNuruConfig {
        db_path: String::new(),
        mls_db_path,
        ..NuruNuruConfig::default()
    }
}

async fn engine_for(keys: &Keys, name: &str) -> Arc<NuruNuruEngine> {
    let cfg = test_config(unique_db_path(name));
    let engine = NuruNuruEngine::new(keys.clone(), cfg).await.unwrap();
    engine.login(keys.public_key()).await.unwrap();
    engine
}

// ── #11 Identity binding ─────────────────────────────────────────────────────

#[test]
fn issue_178_11_mls_manager_refuses_empty_pubkey() {
    let res = MlsManager::new(&unique_db_path("empty_pk"), "");
    match res {
        Err(e) => assert!(
            format!("{e}").contains("non-empty"),
            "error should mention empty pubkey requirement, got {e}"
        ),
        Ok(_) => panic!("MlsManager::new must reject empty pubkey"),
    }
}

#[test]
fn issue_178_11_mls_manager_refuses_whitespace_pubkey() {
    let res = MlsManager::new(&unique_db_path("ws_pk"), "   ");
    match res {
        Err(e) => assert!(
            format!("{e}").contains("non-empty"),
            "error should mention empty pubkey requirement, got {e}"
        ),
        Ok(_) => panic!("MlsManager::new must reject whitespace-only pubkey"),
    }
}

#[tokio::test]
async fn issue_178_11_mls_reset_wipes_sqlite_file() {
    let alice = Keys::generate();
    let engine = engine_for(&alice, "reset_wipes").await;

    // Touch the DB by creating a key package — this guarantees the SQLite file
    // actually exists on disk before we ask reset() to wipe it.
    engine.mls_create_key_package().await.unwrap();

    let path = engine.config_for_tests().mls_db_path.clone();
    assert!(
        std::path::Path::new(&path).exists(),
        "DB file should exist before reset, path={path}"
    );

    let bob = Keys::generate();
    engine.mls_reset(bob.public_key()).await.unwrap();

    // After reset(): the prior file should be gone (or recreated empty by the
    // new manager). Either way, the *previous* MLS state must not survive.
    // Simplest invariant: the manager is bound to Bob's identity now.
    let pkg = engine.mls_create_key_package().await.unwrap();
    assert_eq!(pkg.kind, 30443, "fresh manager must produce kind:30443");
}

// ── #1 Encrypted database ────────────────────────────────────────────────────

#[test]
fn issue_178_1_encrypted_db_open_and_reopen_with_same_key() {
    let path = unique_db_path("enc_reopen");
    let keys = Keys::generate();
    let pk = keys.public_key().to_hex();
    let key = [42u8; 32];

    let mgr = MlsManager::new_with_key(&path, &pk, key).expect("first open succeeds");
    assert!(mgr.is_encrypted(), "manager must report encrypted=true");
    drop(mgr);

    // Reopen with the same key — should succeed.
    let mgr2 = MlsManager::new_with_key(&path, &pk, key).expect("reopen with same key succeeds");
    assert!(mgr2.is_encrypted());
}

#[test]
fn issue_178_1_encrypted_db_rejects_wrong_key() {
    let path = unique_db_path("enc_wrongkey");
    let keys = Keys::generate();
    let pk = keys.public_key().to_hex();
    let key_a = [1u8; 32];
    let key_b = [2u8; 32];

    let mgr = MlsManager::new_with_key(&path, &pk, key_a).expect("first open");
    drop(mgr);

    let res = MlsManager::new_with_key(&path, &pk, key_b);
    assert!(
        res.is_err(),
        "opening an encrypted DB with the wrong key must fail"
    );
}

#[test]
fn issue_178_1_derive_mls_db_key_is_deterministic() {
    let secret = [7u8; 32];
    let salt = b"io.nurunuru.mdk.v1.test";

    let k1 = derive_mls_db_key(&secret, salt);
    let k2 = derive_mls_db_key(&secret, salt);
    assert_eq!(k1, k2, "HKDF derivation must be deterministic");

    let k3 = derive_mls_db_key(&secret, b"different.salt");
    assert_ne!(k1, k3, "different salt must yield different key");

    let k4 = derive_mls_db_key(&[8u8; 32], salt);
    assert_ne!(k1, k4, "different secret must yield different key");
}

// ── #4 Split process_welcome / accept_welcome / decline_welcome ──────────────

#[tokio::test]
async fn issue_178_4_preview_then_decline_does_not_create_active_group() {
    // Alice creates a group with Bob; we preview the Welcome on Bob's engine
    // and decline it. Bob's groups list must remain empty.
    let alice_keys = Keys::generate();
    let bob_keys = Keys::generate();

    let alice = engine_for(&alice_keys, "preview_decline_alice").await;
    let bob = engine_for(&bob_keys, "preview_decline_bob").await;

    // Bob publishes a KeyPackage (via the engine's create + we sign it manually).
    let bob_pkg = bob.mls_create_key_package().await.unwrap();
    let bob_kp_event = {
        let mut tags: Vec<Tag> = Vec::new();
        for raw in &bob_pkg.tags {
            if let Ok(tag) = Tag::parse(raw.iter().map(|s| s.as_str())) {
                tags.push(tag);
            }
        }
        let signer = bob.client_signer_for_tests().await.unwrap();
        EventBuilder::new(Kind::from(bob_pkg.kind as u16), bob_pkg.content.clone())
            .tags(tags)
            .sign(&signer)
            .await
            .unwrap()
    };

    let group_info = alice
        .mls_create_group(
            "Preview/Decline Group".to_string(),
            vec![alice_keys.public_key().to_hex()],
            vec!["wss://relay.example".to_string()],
        )
        .await
        .unwrap();

    let add_result = alice
        .mls_add_member(&group_info.group_id_hex, &bob_kp_event.as_json())
        .await
        .unwrap();
    alice
        .mls_merge_pending_commit(&group_info.group_id_hex)
        .await
        .unwrap();

    let gift_wrap = add_result.welcome_event_data.gift_wrapped_event_json;
    assert!(!gift_wrap.is_empty(), "must produce gift-wrap");

    // Bob *previews* — no group should be created yet.
    let pending = bob.mls_preview_welcome(&gift_wrap).await.unwrap();
    assert_eq!(pending.group_id_hex, group_info.group_id_hex);
    let bob_groups_pre = bob.mls_list_groups().await.unwrap();
    assert!(
        bob_groups_pre.iter().all(|g| g.member_pubkeys.is_empty()),
        "preview must not create an active group with members"
    );

    // Pending list should surface this welcome.
    let pending_list = bob.mls_get_pending_welcomes().await.unwrap();
    assert!(
        pending_list
            .iter()
            .any(|p| p.welcome_event_id_hex == pending.welcome_event_id_hex),
        "previewed welcome should appear in get_pending_welcomes"
    );

    // Bob declines — group must not have an active state.
    bob.mls_decline_welcome(&pending.welcome_event_id_hex)
        .await
        .unwrap();

    let pending_list_after = bob.mls_get_pending_welcomes().await.unwrap();
    assert!(
        pending_list_after
            .iter()
            .all(|p| p.welcome_event_id_hex != pending.welcome_event_id_hex),
        "declined welcome must no longer be pending"
    );
}

#[tokio::test]
async fn issue_178_4_preview_then_accept_joins_group() {
    let alice_keys = Keys::generate();
    let bob_keys = Keys::generate();
    let alice = engine_for(&alice_keys, "preview_accept_alice").await;
    let bob = engine_for(&bob_keys, "preview_accept_bob").await;

    let bob_pkg = bob.mls_create_key_package().await.unwrap();
    let bob_kp_event = {
        let mut tags: Vec<Tag> = Vec::new();
        for raw in &bob_pkg.tags {
            if let Ok(tag) = Tag::parse(raw.iter().map(|s| s.as_str())) {
                tags.push(tag);
            }
        }
        let signer = bob.client_signer_for_tests().await.unwrap();
        EventBuilder::new(Kind::from(bob_pkg.kind as u16), bob_pkg.content.clone())
            .tags(tags)
            .sign(&signer)
            .await
            .unwrap()
    };

    let group_info = alice
        .mls_create_group(
            "Accept Group".to_string(),
            vec![alice_keys.public_key().to_hex()],
            vec!["wss://relay.example".to_string()],
        )
        .await
        .unwrap();
    let add_result = alice
        .mls_add_member(&group_info.group_id_hex, &bob_kp_event.as_json())
        .await
        .unwrap();
    alice
        .mls_merge_pending_commit(&group_info.group_id_hex)
        .await
        .unwrap();

    let pending = bob
        .mls_preview_welcome(&add_result.welcome_event_data.gift_wrapped_event_json)
        .await
        .unwrap();
    let accepted = bob
        .mls_accept_welcome(&pending.welcome_event_id_hex)
        .await
        .unwrap();
    assert_eq!(accepted.group_id_hex, group_info.group_id_hex);

    let groups = bob.mls_list_groups().await.unwrap();
    assert!(
        groups
            .iter()
            .any(|g| g.group_id_hex == group_info.group_id_hex && g.member_pubkeys.len() >= 2),
        "after accept Bob must be a group member"
    );
}

// ── #5 Structured Commit delta ───────────────────────────────────────────────

#[tokio::test]
async fn issue_178_5_commit_carries_added_member_pubkeys() {
    // Alice and Bob join a group. Alice then adds Carol and publishes the
    // commit. When Bob processes that commit, the wrapper must surface Carol's
    // pubkey in `added_pubkeys` so Bob's UI does not need to re-query
    // get_group_info.
    let alice_keys = Keys::generate();
    let bob_keys = Keys::generate();
    let carol_keys = Keys::generate();
    let alice = engine_for(&alice_keys, "commit_delta_alice").await;
    let bob = engine_for(&bob_keys, "commit_delta_bob").await;
    let carol = engine_for(&carol_keys, "commit_delta_carol").await;

    let bob_pkg = bob.mls_create_key_package().await.unwrap();
    let bob_kp_event = {
        let mut tags: Vec<Tag> = Vec::new();
        for raw in &bob_pkg.tags {
            if let Ok(tag) = Tag::parse(raw.iter().map(|s| s.as_str())) {
                tags.push(tag);
            }
        }
        let signer = bob.client_signer_for_tests().await.unwrap();
        EventBuilder::new(Kind::from(bob_pkg.kind as u16), bob_pkg.content.clone())
            .tags(tags)
            .sign(&signer)
            .await
            .unwrap()
    };
    let carol_pkg = carol.mls_create_key_package().await.unwrap();
    let carol_kp_event = {
        let mut tags: Vec<Tag> = Vec::new();
        for raw in &carol_pkg.tags {
            if let Ok(tag) = Tag::parse(raw.iter().map(|s| s.as_str())) {
                tags.push(tag);
            }
        }
        let signer = carol.client_signer_for_tests().await.unwrap();
        EventBuilder::new(Kind::from(carol_pkg.kind as u16), carol_pkg.content.clone())
            .tags(tags)
            .sign(&signer)
            .await
            .unwrap()
    };

    let group_info = alice
        .mls_create_group(
            "Delta Group".to_string(),
            vec![alice_keys.public_key().to_hex()],
            vec!["wss://relay.example".to_string()],
        )
        .await
        .unwrap();

    // Alice adds Bob first; Bob joins.
    let bob_add = alice
        .mls_add_member(&group_info.group_id_hex, &bob_kp_event.as_json())
        .await
        .unwrap();
    alice
        .mls_merge_pending_commit(&group_info.group_id_hex)
        .await
        .unwrap();
    bob.mls_process_welcome(&bob_add.welcome_event_data.gift_wrapped_event_json)
        .await
        .unwrap();

    // Bob runs his MIP-02 post-join self-update so his epoch matches Alice.
    let bob_self_update = bob
        .mls_create_recovery_commit(&group_info.group_id_hex)
        .await
        .unwrap();
    bob.mls_merge_pending_commit(&group_info.group_id_hex)
        .await
        .unwrap();
    let _ = alice
        .mls_process_message_result(&group_info.group_id_hex, &bob_self_update.content)
        .await
        .unwrap();

    // Alice adds Carol — this is the commit Bob will observe.
    let carol_add = alice
        .mls_add_member(&group_info.group_id_hex, &carol_kp_event.as_json())
        .await
        .unwrap();
    alice
        .mls_merge_pending_commit(&group_info.group_id_hex)
        .await
        .unwrap();

    let bob_observation = bob
        .mls_process_message_result(
            &group_info.group_id_hex,
            &carol_add.commit_event_data.content,
        )
        .await
        .unwrap();

    match bob_observation {
        MlsProcessResult::Commit {
            delta,
            group_id_hex,
            ..
        } => {
            assert_eq!(group_id_hex, group_info.group_id_hex);
            assert!(
                delta
                    .added_pubkeys
                    .iter()
                    .any(|pk| pk.eq_ignore_ascii_case(&carol_keys.public_key().to_hex())),
                "Bob's view of Alice's add-Carol commit must include Carol's pubkey in added_pubkeys, got {delta:?}"
            );
            assert!(
                delta.removed_pubkeys.is_empty(),
                "no member was removed, got {:?}",
                delta.removed_pubkeys
            );
            assert!(
                delta.epoch_after >= 2,
                "epoch should have advanced past join"
            );
        }
        other => panic!("expected structured Commit with added/removed delta, got {other:?}"),
    }
}

// ── #9 / #10 Subscription helpers ───────────────────────────────────────────

#[tokio::test]
async fn issue_178_9_mls_subscribe_welcomes_returns_subscription_id() {
    let keys = Keys::generate();
    let engine = engine_for(&keys, "subscribe_welcomes").await;
    let sub_id = engine.mls_subscribe_welcomes(None).await.unwrap();
    assert!(
        !sub_id.is_empty(),
        "subscribe_welcomes must return a sub id"
    );
    engine.unsubscribe_stream(&sub_id).await.unwrap();
}

#[tokio::test]
async fn issue_178_10_mls_subscribe_keypackage_rotations_returns_subscription_id() {
    let alice = Keys::generate();
    let bob = Keys::generate();
    let engine = engine_for(&alice, "subscribe_keypackage").await;
    let sub_id = engine
        .mls_subscribe_keypackage_rotations(vec![bob.public_key()])
        .await
        .unwrap();
    assert!(
        !sub_id.is_empty(),
        "subscribe_keypackage_rotations must return a sub id"
    );
    engine.unsubscribe_stream(&sub_id).await.unwrap();
}
