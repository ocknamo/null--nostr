use nostr::{EventBuilder, JsonUtil, Keys, Kind, Tag};
use nurunuru_core::{NuruNuruConfig, NuruNuruEngine};
use std::time::{SystemTime, UNIX_EPOCH};

fn unique_db_path(name: &str) -> String {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos();
    let mut path = std::env::temp_dir();
    path.push(format!(
        "nurunuru_mls_self_update_flow_{}_{}_{}.sqlite3",
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

async fn new_logged_in_engine(keys: &Keys, name: &str) -> std::sync::Arc<NuruNuruEngine> {
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

fn assert_32_byte_hex(label: &str, value: &str) {
    assert_eq!(
        value.len(),
        64,
        "{label} must be a 32-byte / 64-hex Nostr group id, got {value}"
    );
    assert!(
        value.chars().all(|c| c.is_ascii_hexdigit()),
        "{label} must be hex encoded, got {value}"
    );
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
        "{label} h tag must route to the public Nostr group id"
    );
}

#[tokio::test]
async fn post_join_self_update_full_roundtrip_allows_bidirectional_messages() {
    let alice_keys = Keys::generate();
    let bob_keys = Keys::generate();

    let alice = new_logged_in_engine(&alice_keys, "alice").await;
    let bob = new_logged_in_engine(&bob_keys, "bob").await;

    // Alice invites Bob using Bob's freshly published KeyPackage. The Welcome
    // gift-wrap recipient must be the KeyPackage event owner pubkey (Bob), not
    // the MDK-generated Welcome rumor pubkey.
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
            "Alice & Bob".to_string(),
            vec![alice_keys.public_key().to_hex()],
            vec![relay.clone()],
        )
        .await
        .unwrap();
    assert_32_byte_hex("Alice group_id_hex", &group.group_id_hex);

    let add_result = alice
        .mls_add_member(&group.group_id_hex, &bob_kp_json)
        .await
        .unwrap();
    assert_eq!(
        add_result.welcome_event_data.recipient_pubkey,
        bob_keys.public_key().to_hex(),
        "Welcome 1059 recipient must be the KeyPackage event owner pubkey"
    );
    assert_kind_445_with_group(
        &add_result.commit_event_data.content,
        &group.group_id_hex,
        "add-member commit",
    );

    // Simulate successful relay publication of Alice's add-member commit before
    // any later state updates are handled on Alice's side.
    alice
        .mls_merge_pending_commit(&group.group_id_hex)
        .await
        .unwrap();

    // Bob receives and processes the gift-wrapped Welcome, creating his local
    // group state. MIP-02 requires an immediate post-join self-update.
    let joined = bob
        .mls_process_welcome(&add_result.welcome_event_data.gift_wrapped_event_json)
        .await
        .unwrap();
    assert_eq!(
        joined.group_id_hex, group.group_id_hex,
        "mls_process_welcome() must return the public Nostr group id"
    );
    assert_32_byte_hex("Bob joined group_id_hex", &joined.group_id_hex);
    assert!(joined.relays.contains(&relay));

    let groups_needing_self_update = bob.mls_groups_needing_self_update(0).await.unwrap();
    assert!(
        groups_needing_self_update
            .iter()
            .any(|id| id == &group.group_id_hex),
        "Bob's joined group must require a post-join self-update"
    );

    // Bob publishes a recovery/self-update commit, then merges his pending
    // commit to simulate the successful publish path.
    let self_update = bob
        .mls_create_recovery_commit(&group.group_id_hex)
        .await
        .unwrap();
    assert_kind_445_with_group(
        &self_update.content,
        &group.group_id_hex,
        "post-join self-update commit",
    );

    bob.mls_merge_pending_commit(&group.group_id_hex)
        .await
        .unwrap();

    // Alice receives Bob's self-update and advances her local group state.
    let self_update_result = alice
        .mls_process_message_result(&group.group_id_hex, &self_update.content)
        .await
        .unwrap();
    match self_update_result {
        nurunuru_core::types::MlsProcessResult::StateUpdate { kind } => {
            assert_eq!(kind, "commit", "self-update must process as a commit");
        }
        other => panic!("expected self-update state update, got {other:?}"),
    }

    // Regression lock: after Bob's post-join self-update, both directions must
    // be decryptable. This catches epoch/state drift where only one side can read.
    let alice_to_bob = alice
        .mls_create_message(&group.group_id_hex, "Alice -> Bob after self-update")
        .await
        .unwrap();
    assert_kind_445_with_group(
        &alice_to_bob.content,
        &group.group_id_hex,
        "Alice application message",
    );
    let bob_decrypted = bob
        .mls_process_message_result(&group.group_id_hex, &alice_to_bob.content)
        .await
        .unwrap();
    match bob_decrypted {
        nurunuru_core::types::MlsProcessResult::ApplicationMessage(message) => {
            assert_eq!(message.content, "Alice -> Bob after self-update");
            assert_eq!(message.group_id_hex, group.group_id_hex);
            assert_eq!(message.sender_pubkey, alice_keys.public_key().to_hex());
        }
        other => panic!("Bob must decrypt Alice's application message, got {other:?}"),
    }

    let bob_to_alice = bob
        .mls_create_message(&group.group_id_hex, "Bob -> Alice after self-update")
        .await
        .unwrap();
    assert_kind_445_with_group(
        &bob_to_alice.content,
        &group.group_id_hex,
        "Bob application message",
    );
    let alice_decrypted = alice
        .mls_process_message_result(&group.group_id_hex, &bob_to_alice.content)
        .await
        .unwrap();
    match alice_decrypted {
        nurunuru_core::types::MlsProcessResult::ApplicationMessage(message) => {
            assert_eq!(message.content, "Bob -> Alice after self-update");
            assert_eq!(message.group_id_hex, group.group_id_hex);
            assert_eq!(message.sender_pubkey, bob_keys.public_key().to_hex());
        }
        other => panic!("Alice must decrypt Bob's application message, got {other:?}"),
    }

    bob.mls_delete_consumed_key_package_from_event_json(&bob_kp_json)
        .await
        .unwrap();
}
