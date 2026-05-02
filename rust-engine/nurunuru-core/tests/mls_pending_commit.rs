use nostr::{EventBuilder, JsonUtil, Keys, Kind, Tag};
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
        "nurunuru_mls_pending_commit_{}_{}_{}.sqlite3",
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

async fn new_logged_in_engine(keys: &Keys, name: &str) -> Arc<NuruNuruEngine> {
    let engine = NuruNuruEngine::new(keys.clone(), test_config(unique_db_path(name)))
        .await
        .unwrap();
    engine.login(keys.public_key()).await.unwrap();
    engine
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

async fn signed_key_package_json(engine: &NuruNuruEngine, keys: &Keys) -> String {
    let kp = engine.mls_create_key_package().await.unwrap();
    sign_key_package_event(kp.kind, kp.content, kp.tags, keys)
        .await
        .as_json()
}

async fn create_group_for_alice(alice: &NuruNuruEngine, alice_keys: &Keys, name: &str) -> String {
    alice
        .mls_create_group(
            name.to_string(),
            vec![alice_keys.public_key().to_hex()],
            vec!["wss://relay.example.com".to_string()],
        )
        .await
        .unwrap()
        .group_id_hex
}

fn assert_kind_445_with_group(event_json: &str, group_id_hex: &str, label: &str) {
    let event: nostr::Event = serde_json::from_str(event_json)
        .unwrap_or_else(|e| panic!("{label} must be valid signed event JSON: {e}"));
    assert_eq!(u16::from(event.kind), 445, "{label} must be kind 445");

    let h_tag = event
        .tags
        .iter()
        .find(|tag| tag.kind() == nostr::TagKind::h())
        .and_then(|tag| tag.content());
    assert_eq!(
        h_tag,
        Some(group_id_hex),
        "{label} h tag must use the public Nostr group id"
    );
}

fn assert_pending_commit_error<T>(result: Result<T, NuruNuruError>, context: &str) {
    match result {
        Err(NuruNuruError::MlsError(message)) => {
            assert!(
                message.contains("pending commit") || message.contains("pending proposal"),
                "{context} must fail because a pending commit/proposal exists, got: {message}"
            );
        }
        Err(other) => panic!("{context} must fail with an MLS pending-commit error, got {other:?}"),
        Ok(_) => panic!("{context} must be blocked while the previous commit is pending"),
    }
}

#[tokio::test]
async fn pending_commit_blocks_next_commit_until_cleared_or_merged() {
    let alice_keys = Keys::generate();
    let bob_keys = Keys::generate();
    let charlie_keys = Keys::generate();
    let dave_keys = Keys::generate();
    let erin_keys = Keys::generate();

    let alice = new_logged_in_engine(&alice_keys, "alice_blocks").await;
    let bob = new_logged_in_engine(&bob_keys, "bob_blocks").await;
    let charlie = new_logged_in_engine(&charlie_keys, "charlie_blocks").await;
    let dave = new_logged_in_engine(&dave_keys, "dave_blocks").await;
    let erin = new_logged_in_engine(&erin_keys, "erin_blocks").await;

    let bob_kp_json = signed_key_package_json(&bob, &bob_keys).await;
    let charlie_kp_json = signed_key_package_json(&charlie, &charlie_keys).await;
    let dave_kp_json = signed_key_package_json(&dave, &dave_keys).await;
    let erin_kp_json = signed_key_package_json(&erin, &erin_keys).await;

    let clear_group_id = create_group_for_alice(&alice, &alice_keys, "clear branch").await;
    let add_bob = alice
        .mls_add_member(&clear_group_id, &bob_kp_json)
        .await
        .unwrap();
    assert_kind_445_with_group(
        &add_bob.commit_event_data.content,
        &clear_group_id,
        "first add-member commit",
    );

    assert_pending_commit_error(
        alice
            .mls_add_member(&clear_group_id, &charlie_kp_json)
            .await,
        "second add_member before clear/merge",
    );

    alice
        .mls_clear_pending_commit(&clear_group_id)
        .await
        .unwrap();
    let retry_after_clear = alice
        .mls_add_member(&clear_group_id, &charlie_kp_json)
        .await
        .unwrap();
    assert_kind_445_with_group(
        &retry_after_clear.commit_event_data.content,
        &clear_group_id,
        "add-member commit after clear_pending_commit",
    );

    let merge_group_id = create_group_for_alice(&alice, &alice_keys, "merge branch").await;
    let add_dave = alice
        .mls_add_member(&merge_group_id, &dave_kp_json)
        .await
        .unwrap();
    assert_kind_445_with_group(
        &add_dave.commit_event_data.content,
        &merge_group_id,
        "first add-member commit on merge branch",
    );

    alice
        .mls_merge_pending_commit(&merge_group_id)
        .await
        .unwrap();
    let followup_after_merge = alice
        .mls_add_member(&merge_group_id, &erin_kp_json)
        .await
        .unwrap();
    assert_kind_445_with_group(
        &followup_after_merge.commit_event_data.content,
        &merge_group_id,
        "follow-up add-member commit after merge_pending_commit",
    );
}

#[tokio::test]
async fn clear_pending_commit_allows_retry() {
    let alice_keys = Keys::generate();
    let bob_keys = Keys::generate();

    let alice = new_logged_in_engine(&alice_keys, "alice_clear_retry").await;
    let bob = new_logged_in_engine(&bob_keys, "bob_clear_retry").await;

    let bob_kp_json = signed_key_package_json(&bob, &bob_keys).await;
    let group_id = create_group_for_alice(&alice, &alice_keys, "clear allows retry").await;

    let original_add = alice.mls_add_member(&group_id, &bob_kp_json).await.unwrap();
    assert_kind_445_with_group(
        &original_add.commit_event_data.content,
        &group_id,
        "original add-member commit",
    );

    alice.mls_clear_pending_commit(&group_id).await.unwrap();

    let retried_add = alice.mls_add_member(&group_id, &bob_kp_json).await.unwrap();
    assert_kind_445_with_group(
        &retried_add.commit_event_data.content,
        &group_id,
        "retried add-member commit after clear_pending_commit",
    );
    assert_eq!(
        retried_add.welcome_event_data.recipient_pubkey,
        bob_keys.public_key().to_hex(),
        "retry must still target the KeyPackage event owner pubkey"
    );
}

#[tokio::test]
async fn merge_pending_commit_allows_followup_state_update() {
    let alice_keys = Keys::generate();
    let bob_keys = Keys::generate();

    let alice = new_logged_in_engine(&alice_keys, "alice_merge_followup").await;
    let bob = new_logged_in_engine(&bob_keys, "bob_merge_followup").await;

    let bob_kp_json = signed_key_package_json(&bob, &bob_keys).await;
    let group_id = create_group_for_alice(&alice, &alice_keys, "merge allows followup").await;

    let add_result = alice.mls_add_member(&group_id, &bob_kp_json).await.unwrap();
    assert_kind_445_with_group(
        &add_result.commit_event_data.content,
        &group_id,
        "add-member commit",
    );

    // Publish success policy: after the add-member Kind-445 is accepted by relays,
    // merge the local pending commit before handling later state updates.
    alice.mls_merge_pending_commit(&group_id).await.unwrap();

    let joined = bob
        .mls_process_welcome(&add_result.welcome_event_data.gift_wrapped_event_json)
        .await
        .unwrap();
    assert_eq!(joined.group_id_hex, group_id);

    let self_update = bob.mls_create_recovery_commit(&group_id).await.unwrap();
    assert_kind_445_with_group(&self_update.content, &group_id, "Bob self-update commit");
    bob.mls_merge_pending_commit(&group_id).await.unwrap();

    let processed = alice
        .mls_process_message_result(&group_id, &self_update.content)
        .await
        .unwrap();
    match processed {
        nurunuru_core::types::MlsProcessResult::StateUpdate { kind } => {
            assert_eq!(kind, "commit", "Bob self-update must process as a commit");
        }
        other => panic!("expected Bob self-update to be a state update, got {other:?}"),
    }

    let expected = "message after pending add-member commit was merged";
    let message = alice.mls_create_message(&group_id, expected).await.unwrap();
    assert_kind_445_with_group(&message.content, &group_id, "Alice follow-up message");

    let decrypted = bob
        .mls_process_message_result(&group_id, &message.content)
        .await
        .unwrap();
    match decrypted {
        nurunuru_core::types::MlsProcessResult::ApplicationMessage(message) => {
            assert_eq!(message.content, expected);
            assert_eq!(message.sender_pubkey, alice_keys.public_key().to_hex());
            assert_eq!(message.group_id_hex, group_id);
        }
        other => panic!("Bob must decrypt Alice's follow-up message, got {other:?}"),
    }
}
