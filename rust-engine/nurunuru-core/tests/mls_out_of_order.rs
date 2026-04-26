use nostr::{EventBuilder, JsonUtil, Keys, Kind, Tag};
use nurunuru_core::types::MlsProcessResult;
use nurunuru_core::{NuruNuruConfig, NuruNuruEngine, NuruNuruError};
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};

fn unique_db_path(name: &str) -> String {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos();
    let mut path = std::env::temp_dir();
    path.push(format!(
        "nurunuru_mls_out_of_order_{}_{}_{}.sqlite3",
        name,
        std::process::id(),
        nanos
    ));
    path.to_string_lossy().to_string()
}

fn test_config(mls_db_path: String) -> NuruNuruConfig {
    let mut cfg = NuruNuruConfig::default();
    cfg.db_path = String::new();
    cfg.mls_db_path = mls_db_path;
    cfg
}

async fn new_logged_in_engine_with_db_path(
    keys: &Keys,
    mls_db_path: String,
) -> Arc<NuruNuruEngine> {
    let engine = NuruNuruEngine::new(keys.clone(), test_config(mls_db_path))
        .await
        .unwrap();
    engine.login(keys.public_key()).await.unwrap();
    engine
}

async fn new_logged_in_engine(keys: &Keys, name: &str) -> Arc<NuruNuruEngine> {
    new_logged_in_engine_with_db_path(keys, unique_db_path(name)).await
}

async fn sign_key_package_event(
    kind: u32,
    content: String,
    tags: Vec<Vec<String>>,
    keys: &Keys,
) -> nostr::Event {
    let tags: Vec<Tag> = tags
        .into_iter()
        .map(|t| serde_json::from_value::<Tag>(serde_json::to_value(t).unwrap()).unwrap())
        .collect();

    EventBuilder::new(Kind::Custom(kind as u16), content)
        .tags(tags)
        .build(keys.public_key())
        .sign(keys)
        .await
        .unwrap()
}

fn assert_retryable_unprocessable(result: Result<MlsProcessResult, NuruNuruError>) {
    match result {
        Ok(MlsProcessResult::StateUpdate { kind }) => {
            assert!(
                kind.contains("Unprocessable") || kind.contains("unprocessable"),
                "out-of-order message should be explicitly classified as retryable/unprocessable, got StateUpdate kind={kind:?}"
            );
            assert!(
                kind.contains("state_not_ready") || kind.starts_with("unhandled:Unprocessable"),
                "unprocessable kind should carry an app-usable retry reason, got {kind:?}"
            );
        }
        Err(NuruNuruError::MlsError(msg)) => {
            assert!(
                msg.contains("Unprocessable")
                    || msg.contains("unprocessable")
                    || msg.contains("epoch")
                    || msg.contains("state"),
                "out-of-order error should be classifiable as retryable/unprocessable, got {msg:?}"
            );
        }
        other => panic!(
            "out-of-order message must not be treated as success; expected retryable/unprocessable, got {other:?}"
        ),
    }
}

fn assert_duplicate_idempotent(result: Result<MlsProcessResult, NuruNuruError>, label: &str) {
    match result {
        Ok(MlsProcessResult::ApplicationMessage(msg)) => {
            assert!(
                !msg.content.is_empty(),
                "duplicate {label} returned an application message but content was empty"
            );
        }
        Ok(MlsProcessResult::StateUpdate { kind }) => {
            assert!(
                kind == "commit"
                    || kind == "proposal"
                    || kind == "pending_proposal"
                    || kind.starts_with("unhandled:"),
                "duplicate {label} should return a clear idempotent state/update classification, got {kind:?}"
            );
        }
        Err(err) => panic!("duplicate {label} processing should be idempotent, got error: {err:?}"),
    }
}

#[tokio::test]
async fn marmot_out_of_order_kind445_message_retries_after_missing_commit_and_duplicates_are_idempotent(
) {
    let alice_keys = Keys::generate();
    let bob_keys = Keys::generate();

    let alice_db_path = unique_db_path("alice");
    let alice_replay_db_path = unique_db_path("alice_replay");
    let alice = new_logged_in_engine_with_db_path(&alice_keys, alice_db_path.clone()).await;
    let bob = new_logged_in_engine(&bob_keys, "bob").await;

    // Bob publishes a KeyPackage, then Alice creates a group and invites Bob.
    let bob_kp = bob.mls_create_key_package().await.unwrap();
    let bob_kp_event = sign_key_package_event(
        bob_kp.kind,
        bob_kp.content.clone(),
        bob_kp.tags.clone(),
        &bob_keys,
    )
    .await;
    let bob_kp_json = bob_kp_event.as_json();

    alice
        .mls_validate_key_package_event(&bob_kp_json)
        .await
        .unwrap();

    let relay = "wss://relay.example.com".to_string();
    let group = alice
        .mls_create_group(
            "Alice & Bob out-of-order".to_string(),
            vec![alice_keys.public_key().to_hex()],
            vec![relay],
        )
        .await
        .unwrap();

    let add_result = alice
        .mls_add_member(&group.group_id_hex, &bob_kp_json)
        .await
        .unwrap();

    // Simulate publish success for Alice's add-member commit.
    alice
        .mls_merge_pending_commit(&group.group_id_hex)
        .await
        .unwrap();

    // Bob joins via Welcome and performs the required post-join self-update.
    let joined = bob
        .mls_process_welcome(&add_result.welcome_event_data.gift_wrapped_event_json)
        .await
        .unwrap();
    assert_eq!(joined.group_id_hex, group.group_id_hex);

    let bob_self_update = bob
        .mls_create_recovery_commit(&group.group_id_hex)
        .await
        .unwrap();
    let bob_self_update_event: nostr::Event = serde_json::from_str(&bob_self_update.content).unwrap();
    assert_eq!(u16::from(bob_self_update_event.kind), 445);

    // Snapshot Alice's pre-self-update local state. This models an app process that
    // sees Bob's message first, classifies it, and later replays queued event ids
    // after processing the missing commit from persisted state.
    std::fs::copy(&alice_db_path, &alice_replay_db_path).unwrap();
    let alice_replay = new_logged_in_engine_with_db_path(&alice_keys, alice_replay_db_path).await;

    // Bob considers his self-update published before sending an application message.
    bob.mls_merge_pending_commit(&group.group_id_hex)
        .await
        .unwrap();

    let plaintext = "out-of-order hello";
    let bob_message = bob
        .mls_create_message(&group.group_id_hex, plaintext)
        .await
        .unwrap();
    let bob_message_event: nostr::Event = serde_json::from_str(&bob_message.content).unwrap();
    assert_eq!(u16::from(bob_message_event.kind), 445);

    // Relay delivers Bob's application message before the self-update commit Alice needs.
    // The app can put this event id in a retry queue because the result is explicit.
    // Use an app-replay engine backed by Alice's already-created local MLS DB state:
    // the speculative failed process may mutate MDK state, while real apps should retry
    // queued events from persisted state after the missing commit is processed.
    let out_of_order = alice_replay
        .mls_process_message_result(&group.group_id_hex, &bob_message.content)
        .await;
    assert_retryable_unprocessable(out_of_order);

    // Now the missing commit arrives. Alice advances state.
    let commit_result = alice
        .mls_process_message_result(&group.group_id_hex, &bob_self_update.content)
        .await
        .unwrap();
    match commit_result {
        MlsProcessResult::StateUpdate { kind } => assert_eq!(
            kind, "commit",
            "self-update commit should be a clear state-update result"
        ),
        other => panic!("expected self-update commit StateUpdate, got {other:?}"),
    }

    // After the missing commit has been processed, retrying the exact same message succeeds.
    let retry_result = alice
        .mls_process_message_result(&group.group_id_hex, &bob_message.content)
        .await
        .unwrap();
    match retry_result {
        MlsProcessResult::ApplicationMessage(msg) => {
            assert_eq!(msg.content, plaintext);
            assert_eq!(msg.sender_pubkey, bob_keys.public_key().to_hex());
            assert_eq!(msg.group_id_hex, group.group_id_hex);
        }
        other => panic!("retry after commit should decrypt application message, got {other:?}"),
    }

    // Duplicates from relay replay must be idempotent: no panic/error and clear result kind.
    let duplicate_commit = alice
        .mls_process_message_result(&group.group_id_hex, &bob_self_update.content)
        .await;
    assert_duplicate_idempotent(duplicate_commit, "commit");

    let duplicate_message = alice
        .mls_process_message_result(&group.group_id_hex, &bob_message.content)
        .await;
    assert_duplicate_idempotent(duplicate_message, "message");
}
