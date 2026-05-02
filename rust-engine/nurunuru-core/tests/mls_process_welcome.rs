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
        "nurunuru_mls_process_welcome_{}_{}_{}.sqlite3",
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
    assert_eq!(value.len(), 64, "{label} must be 32-byte hex");
    assert!(
        value.chars().all(|c| c.is_ascii_hexdigit()),
        "{label} must contain only hex characters: {value}"
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
        "{label} h tag must use the public Nostr group id"
    );
}

#[tokio::test]
async fn process_welcome_accepts_and_joins_group_before_returning() {
    let alice_keys = Keys::generate();
    let bob_keys = Keys::generate();

    let alice = new_logged_in_engine(&alice_keys, "alice").await;
    let bob = new_logged_in_engine(&bob_keys, "bob").await;

    // Alice invites Bob using Bob's KeyPackage event. The event owner pubkey is
    // the intended Welcome 1059 recipient; the inner Welcome rumor pubkey is not
    // an app/API group identifier and must not leak into these assertions.
    let bob_key_package = bob.mls_create_key_package().await.unwrap();
    let bob_key_package_event = sign_key_package_event(
        bob_key_package.kind,
        bob_key_package.content.clone(),
        bob_key_package.tags.clone(),
        &bob_keys,
    )
    .await;
    let bob_key_package_json = bob_key_package_event.as_json();

    alice
        .mls_validate_key_package_event(&bob_key_package_json)
        .await
        .unwrap();

    let relay = "wss://relay.example.com".to_string();
    let alice_group = alice
        .mls_create_group(
            "Alice & Bob".to_string(),
            vec![alice_keys.public_key().to_hex()],
            vec![relay.clone()],
        )
        .await
        .unwrap();
    assert_32_byte_hex("Alice group_id_hex", &alice_group.group_id_hex);

    let add_result = alice
        .mls_add_member(&alice_group.group_id_hex, &bob_key_package_json)
        .await
        .unwrap();
    assert_eq!(
        add_result.welcome_event_data.recipient_pubkey,
        bob_keys.public_key().to_hex(),
        "Welcome 1059 recipient must be the KeyPackage event owner pubkey"
    );
    assert_kind_445_with_group(
        &add_result.commit_event_data.content,
        &alice_group.group_id_hex,
        "add-member commit",
    );

    // Simulate successful publication of Alice's add-member commit before Bob's
    // post-join self-update is later processed by Alice.
    alice
        .mls_merge_pending_commit(&alice_group.group_id_hex)
        .await
        .unwrap();

    let gift_wrapped_welcome = &add_result.welcome_event_data.gift_wrapped_event_json;
    assert!(
        !gift_wrapped_welcome.is_empty(),
        "gift-wrapped Welcome must be returned"
    );

    let joined = bob.mls_process_welcome(gift_wrapped_welcome).await.unwrap();

    // App/FFI boundary contract: group_id_hex is the Nostr group id used in
    // Kind-445 h tags, not MDK/OpenMLS' internal group id.
    assert_eq!(
        joined.group_id_hex, alice_group.group_id_hex,
        "mls_process_welcome() must return the public Nostr group id from the Welcome"
    );
    assert_32_byte_hex("joined.group_id_hex", &joined.group_id_hex);
    assert!(joined.relays.contains(&relay));

    // P1-S1 regression lock: process_welcome() is not just a preview step. It
    // must accept/join before returning so the group is immediately listed and
    // usable by later APIs.
    let bob_groups = bob.mls_list_groups().await.unwrap();
    let listed_group = bob_groups
        .iter()
        .find(|group| group.group_id_hex == joined.group_id_hex)
        .unwrap_or_else(|| {
            panic!(
                "Bob's mls_list_groups() must include joined group {}; groups={bob_groups:?}",
                joined.group_id_hex
            )
        });
    assert_eq!(
        listed_group.group_id_hex, joined.group_id_hex,
        "listed group id must remain the public Nostr group id"
    );
    assert!(listed_group.relays.contains(&relay));

    let self_update = bob
        .mls_create_recovery_commit(&joined.group_id_hex)
        .await
        .unwrap();
    assert_kind_445_with_group(
        &self_update.content,
        &joined.group_id_hex,
        "post-join recovery/self-update commit",
    );

    // Marmot/Nostr relays can redeliver duplicate Welcomes. The design requires
    // duplicate/retry tolerance; current core behavior is naturally idempotent:
    // a duplicate process returns Ok for the same already-joined Nostr group id.
    let duplicate = bob.mls_process_welcome(gift_wrapped_welcome).await;
    match duplicate {
        Ok(group) => {
            assert_eq!(
                group.group_id_hex, joined.group_id_hex,
                "idempotent duplicate Welcome processing must return the same public Nostr group id"
            );
            assert!(group.relays.contains(&relay));
        }
        Err(NuruNuruError::MlsError(message)) => {
            assert!(
                message.starts_with("process_welcome:") || message.starts_with("accept_welcome:"),
                "if duplicate Welcome processing fails, it must fail in process/accept_welcome; got: {message}"
            );
        }
        Err(other) => {
            panic!("duplicate Welcome must either be idempotent Ok or an MLS error, got {other:?}")
        }
    }

    let bob_groups_after_duplicate = bob.mls_list_groups().await.unwrap();
    assert!(
        bob_groups_after_duplicate
            .iter()
            .any(|group| group.group_id_hex == joined.group_id_hex),
        "duplicate processing failure must not remove the already joined group"
    );
}
