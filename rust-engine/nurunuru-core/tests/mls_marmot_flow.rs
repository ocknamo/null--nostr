use nostr::{EventBuilder, JsonUtil, Keys, Kind, Tag};
use nurunuru_core::{NuruNuruConfig, NuruNuruEngine, NuruNuruError};
use std::time::{SystemTime, UNIX_EPOCH};

fn unique_db_path(name: &str) -> String {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos();
    let mut path = std::env::temp_dir();
    path.push(format!(
        "nurunuru_mls_test_{}_{}_{}.sqlite3",
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

async fn new_logged_in_engine(keys: &Keys, name: &str) -> NuruNuruEngineHandle {
    let cfg = test_config(unique_db_path(name));
    let engine = NuruNuruEngine::new(keys.clone(), cfg).await.unwrap();
    engine.login(keys.public_key()).await.unwrap();
    NuruNuruEngineHandle { engine }
}

struct NuruNuruEngineHandle {
    engine: std::sync::Arc<NuruNuruEngine>,
}

impl Drop for NuruNuruEngineHandle {
    fn drop(&mut self) {
        // Best-effort cleanup; file may still be open on some platforms.
    }
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

#[tokio::test]
async fn marmot_welcome_giftwrap_and_message_flow_works() {
    let alice_keys = Keys::generate();
    let bob_keys = Keys::generate();
    let bob_pubkey = bob_keys.public_key().to_hex();

    let alice = new_logged_in_engine(&alice_keys, "alice_flow").await;
    let bob = new_logged_in_engine(&bob_keys, "bob_flow").await;

    let bob_kp = bob.engine.mls_create_key_package().await.unwrap();
    let bob_kp_event = sign_key_package_event(
        bob_kp.kind,
        bob_kp.content.clone(),
        bob_kp.tags.clone(),
        &bob_keys,
    )
    .await;
    let bob_kp_json = bob_kp_event.as_json();

    alice
        .engine
        .mls_validate_key_package_event(&bob_kp_json)
        .await
        .unwrap();

    let relay = "wss://relay.example.com".to_string();
    let group = alice
        .engine
        .mls_create_group(
            "Alice & Bob".to_string(),
            vec![alice_keys.public_key().to_hex()],
            vec![relay.clone()],
        )
        .await
        .unwrap();

    let add_result = alice
        .engine
        .mls_add_member(&group.group_id_hex, &bob_kp_json)
        .await
        .unwrap();

    assert!(
        !add_result.commit_event_data.content.is_empty(),
        "commit event JSON should be present"
    );
    assert!(
        !add_result.welcome_event_data.inner_rumor_json.is_empty(),
        "welcome rumor should be present"
    );
    assert!(
        !add_result
            .welcome_event_data
            .gift_wrapped_event_json
            .is_empty(),
        "gift wrap JSON should be present"
    );
    assert_eq!(
        add_result.welcome_event_data.recipient_pubkey, bob_pubkey,
        "Welcome recipient must be the KeyPackage event owner pubkey"
    );

    let add_commit: nostr::Event =
        serde_json::from_str(&add_result.commit_event_data.content).unwrap();
    assert_eq!(
        u16::from(add_commit.kind),
        445,
        "add-member commit must be kind 445"
    );

    // In the real publish flow the inviter merges the pending add-member commit
    // after publishing it. Do the same here before processing Bob's self-update.
    alice
        .engine
        .mls_merge_pending_commit(&group.group_id_hex)
        .await
        .unwrap();

    let gift_wrap: nostr::Event =
        serde_json::from_str(&add_result.welcome_event_data.gift_wrapped_event_json).unwrap();
    assert_eq!(
        u16::from(gift_wrap.kind),
        1059,
        "welcome must be gift-wrapped as kind 1059"
    );
    assert!(
        gift_wrap.tags.clone().to_vec().iter().any(|tag| {
            let parts = tag.as_slice();
            parts.len() >= 2 && parts[0] == "p" && parts[1] == bob_pubkey
        }),
        "Kind 1059 recipient p tag must be Bob's pubkey"
    );

    let mut inner_rumor: nostr::UnsignedEvent =
        serde_json::from_str(&add_result.welcome_event_data.inner_rumor_json).unwrap();
    let inner_rumor_id = inner_rumor.id();
    assert_eq!(
        u16::from(inner_rumor.kind),
        444,
        "welcome inner rumor should be kind 444"
    );

    let extracted = nostr::nips::nip59::extract_rumor(&bob_keys, &gift_wrap)
        .await
        .unwrap();
    let mut extracted_rumor = extracted.rumor;
    let extracted_rumor_id = extracted_rumor.id();
    assert_eq!(
        u16::from(extracted_rumor.kind),
        444,
        "extracted welcome rumor should be kind 444"
    );
    assert_eq!(
        extracted_rumor_id, inner_rumor_id,
        "extracted rumor id must match inner_rumor_json"
    );
    assert_eq!(
        u16::from(extracted_rumor.kind),
        u16::from(inner_rumor.kind),
        "extracted rumor kind must match inner_rumor_json"
    );
    assert_eq!(
        extracted_rumor.content, inner_rumor.content,
        "extracted rumor content must match inner_rumor_json"
    );
    assert_eq!(
        extracted_rumor.tags.clone().to_vec(),
        inner_rumor.tags.clone().to_vec(),
        "extracted rumor tags must match inner_rumor_json"
    );

    let joined = bob
        .engine
        .mls_process_welcome(&add_result.welcome_event_data.gift_wrapped_event_json)
        .await
        .unwrap();
    assert_eq!(joined.group_id_hex, group.group_id_hex);
    assert_eq!(
        joined.group_id_hex.len(),
        64,
        "group_id_hex must be a 32-byte Nostr group id hex"
    );
    assert!(
        joined.group_id_hex.chars().all(|c| c.is_ascii_hexdigit()),
        "group_id_hex must be hex encoded"
    );
    assert!(joined.relays.contains(&relay));

    let pending_self_update = bob.engine.mls_groups_needing_self_update(0).await.unwrap();
    assert!(
        pending_self_update
            .iter()
            .any(|id| id == &group.group_id_hex),
        "joined group should need self-update immediately"
    );

    let self_update = bob
        .engine
        .mls_create_recovery_commit(&group.group_id_hex)
        .await
        .unwrap();
    let self_update_commit: nostr::Event = serde_json::from_str(&self_update.content).unwrap();
    assert_eq!(
        u16::from(self_update_commit.kind),
        445,
        "post-join self-update commit must be kind 445"
    );

    let self_update_result = alice
        .engine
        .mls_process_message_result(&group.group_id_hex, &self_update.content)
        .await
        .unwrap();
    match self_update_result {
        nurunuru_core::types::MlsProcessResult::StateUpdate { .. } => {}
        other => panic!(
            "expected state update for self-update commit, got {:?}",
            other
        ),
    }
    bob.engine
        .mls_merge_pending_commit(&group.group_id_hex)
        .await
        .unwrap();

    let expected_plaintext = "Hello Bob!";
    let msg = alice
        .engine
        .mls_create_message(&group.group_id_hex, expected_plaintext)
        .await
        .unwrap();
    let msg_result = bob
        .engine
        .mls_process_message_result(&group.group_id_hex, &msg.content)
        .await
        .unwrap();
    match msg_result {
        nurunuru_core::types::MlsProcessResult::ApplicationMessage(m) => {
            assert_eq!(
                m.content, expected_plaintext,
                "final decrypted message must match expected plaintext"
            );
            assert_eq!(m.group_id_hex, group.group_id_hex);
            assert_eq!(m.sender_pubkey, alice_keys.public_key().to_hex());
        }
        other => panic!("expected application message, got {:?}", other),
    }

    bob.engine
        .mls_delete_consumed_key_package_from_event_json(&bob_kp_json)
        .await
        .unwrap();
}

#[tokio::test]
async fn marmot_key_package_validation_accepts_30443_and_443() {
    let alice_keys = Keys::generate();
    let bob_keys = Keys::generate();

    let alice = new_logged_in_engine(&alice_keys, "alice_validate").await;
    let bob = new_logged_in_engine(&bob_keys, "bob_validate").await;

    let kp = bob.engine.mls_create_key_package().await.unwrap();

    let canonical =
        sign_key_package_event(kp.kind, kp.content.clone(), kp.tags.clone(), &bob_keys).await;
    alice
        .engine
        .mls_validate_key_package_event(&canonical.as_json())
        .await
        .unwrap();

    let legacy = sign_key_package_event(443, kp.content, kp.legacy_tags, &bob_keys).await;
    alice
        .engine
        .mls_validate_key_package_event(&legacy.as_json())
        .await
        .unwrap();
}

#[tokio::test]
async fn marmot_process_message_rejects_invalid_outer_shape() {
    let alice_keys = Keys::generate();
    let alice = new_logged_in_engine(&alice_keys, "alice_invalid_outer").await;

    let bad_event = serde_json::json!({
        "id": "0000000000000000000000000000000000000000000000000000000000000000",
        "pubkey": alice_keys.public_key().to_hex(),
        "created_at": 0,
        "kind": 445,
        "tags": [["h", "0000000000000000000000000000000000000000000000000000000000000000"]],
        "content": "not-base64",
        "sig": "00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"
    });

    let err = alice
        .engine
        .mls_process_message_result(
            "0000000000000000000000000000000000000000000000000000000000000000",
            &bad_event.to_string(),
        )
        .await
        .unwrap_err();

    match err {
        NuruNuruError::MlsError(msg) => assert!(
            msg.contains("invalid_base64_content"),
            "unexpected error: {msg}"
        ),
        other => panic!("unexpected error variant: {other:?}"),
    }
}
