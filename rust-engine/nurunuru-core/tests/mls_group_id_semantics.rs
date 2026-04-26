use nostr::{EventBuilder, JsonUtil, Keys, Kind, Tag, TagKind};
use nurunuru_core::{NuruNuruConfig, NuruNuruEngine};
use std::time::{SystemTime, UNIX_EPOCH};

fn unique_db_path(name: &str) -> String {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos();
    let mut path = std::env::temp_dir();
    path.push(format!(
        "nurunuru_mls_group_id_semantics_{}_{}_{}.sqlite3",
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
    let cfg = test_config(unique_db_path(name));
    let engine = NuruNuruEngine::new(keys.clone(), cfg).await.unwrap();
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

fn h_tag(event: &nostr::Event) -> String {
    event
        .tags
        .iter()
        .find(|tag| tag.kind() == TagKind::h())
        .and_then(|tag| tag.content())
        .expect("Kind 445 event must have an h tag")
        .to_string()
}

#[tokio::test]
async fn ffi_group_id_hex_is_nostr_group_id_not_internal_mls_id() {
    let alice_keys = Keys::generate();
    let bob_keys = Keys::generate();

    let alice = new_logged_in_engine(&alice_keys, "alice_semantics").await;
    let bob = new_logged_in_engine(&bob_keys, "bob_semantics").await;

    let relay = "wss://relay.example.com".to_string();
    let group = alice
        .mls_create_group(
            "Group ID semantics".to_string(),
            vec![alice_keys.public_key().to_hex()],
            vec![relay.clone()],
        )
        .await
        .unwrap();

    // FFI/API boundary contract: groupIdHex is the public Nostr group id
    // (32 bytes / 64 hex), not MDK/OpenMLS' internal group id.
    assert_32_byte_hex("mls_create_group().group_id_hex", &group.group_id_hex);

    // The public group id returned by create_group must be exactly the value used
    // for Kind 445 routing in the h tag.
    let initial_message = alice
        .mls_create_message(&group.group_id_hex, "hello from the creator")
        .await
        .unwrap();
    let initial_event: nostr::Event = serde_json::from_str(&initial_message.content).unwrap();
    assert_eq!(u16::from(initial_event.kind), 445);
    assert_eq!(
        h_tag(&initial_event),
        group.group_id_hex,
        "MlsGroupInfo.group_id_hex must match Kind 445 h tag (Nostr group id)"
    );

    let listed = alice.mls_list_groups().await.unwrap();
    assert!(
        listed.iter().any(|g| g.group_id_hex == group.group_id_hex),
        "mls_list_groups() must expose the same Nostr group id as create_group()"
    );

    let looked_up = alice
        .mls_get_group_info(&group.group_id_hex)
        .await
        .unwrap();
    assert_eq!(
        looked_up.group_id_hex, group.group_id_hex,
        "mls_get_group_info() must not translate back to an internal MLS group id"
    );
    assert_32_byte_hex("mls_get_group_info().group_id_hex", &looked_up.group_id_hex);

    // Invite Bob so that Bob's local MDK state requires the MIP-02 post-join
    // self-update. groups_needing_self_update() is a critical boundary because
    // MDK returns internal MLS group IDs and NuruNuru must translate them back
    // to Nostr group IDs before returning to apps/FFI.
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

    let add_result = alice
        .mls_add_member(&group.group_id_hex, &bob_kp_json)
        .await
        .unwrap();

    let add_commit: nostr::Event =
        serde_json::from_str(&add_result.commit_event_data.content).unwrap();
    assert_eq!(u16::from(add_commit.kind), 445);
    assert_eq!(
        h_tag(&add_commit),
        group.group_id_hex,
        "add-member commit h tag must keep using the Nostr group id"
    );

    alice
        .mls_merge_pending_commit(&group.group_id_hex)
        .await
        .unwrap();

    let joined = bob
        .mls_process_welcome(&add_result.welcome_event_data.gift_wrapped_event_json)
        .await
        .unwrap();
    assert_eq!(
        joined.group_id_hex, group.group_id_hex,
        "mls_process_welcome() must return the same Nostr group id used by Alice"
    );
    assert_32_byte_hex("mls_process_welcome().group_id_hex", &joined.group_id_hex);

    let bob_listed = bob.mls_list_groups().await.unwrap();
    assert!(
        bob_listed.iter().any(|g| g.group_id_hex == group.group_id_hex),
        "Bob's mls_list_groups() must expose the Nostr group id, not an internal MLS id"
    );

    let self_update_ids = bob.mls_groups_needing_self_update(0).await.unwrap();
    assert!(
        !self_update_ids.is_empty(),
        "Bob should need a post-join self-update after accepting Welcome"
    );
    assert!(
        self_update_ids.iter().all(|id| id.len() == 64),
        "groups_needing_self_update() must not leak shorter internal MLS group IDs: {self_update_ids:?}"
    );
    assert!(
        self_update_ids.iter().all(|id| id.chars().all(|c| c.is_ascii_hexdigit())),
        "groups_needing_self_update() IDs must be hex encoded Nostr group IDs: {self_update_ids:?}"
    );
    assert!(
        self_update_ids.iter().any(|id| id == &group.group_id_hex),
        "groups_needing_self_update() must return the Nostr group id from Kind 445 h tags"
    );

    let id_from_boundary = self_update_ids
        .iter()
        .find(|id| *id == &group.group_id_hex)
        .unwrap();

    // Regression guard: the ID returned by groups_needing_self_update() must be
    // directly usable as the public groupIdHex input to mls_create_recovery_commit().
    // If an internal MLS group id leaks here, resolve_group_id() will fail or the
    // resulting Kind 445 h tag will not match the public Nostr group id.
    let recovery = bob
        .mls_create_recovery_commit(id_from_boundary)
        .await
        .unwrap();
    let recovery_event: nostr::Event = serde_json::from_str(&recovery.content).unwrap();
    assert_eq!(u16::from(recovery_event.kind), 445);
    assert_eq!(
        h_tag(&recovery_event),
        group.group_id_hex,
        "recovery commit h tag must be the public Nostr group id returned across the API boundary"
    );
    assert_eq!(
        h_tag(&recovery_event),
        *id_from_boundary,
        "groups_needing_self_update() output must be directly usable by mls_create_recovery_commit()"
    );

    // A second explicit anti-leak check across the boundary-visible IDs: every
    // exposed group id in this flow is identical to the Kind 445 h tag and is a
    // 32-byte Nostr group id. An internal MLS group id would diverge here.
    let boundary_ids = [
        group.group_id_hex.as_str(),
        looked_up.group_id_hex.as_str(),
        joined.group_id_hex.as_str(),
        id_from_boundary.as_str(),
    ];
    for id in boundary_ids {
        assert_eq!(
            id,
            h_tag(&initial_event),
            "internal MLS group id leaked across an FFI/API boundary: {id} != Kind 445 h tag"
        );
        assert_32_byte_hex("boundary groupIdHex", id);
    }
}
