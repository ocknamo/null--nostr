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
        "nurunuru_mls_key_package_lifecycle_{}_{}_{}.sqlite3",
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
    let tags = tags
        .into_iter()
        .map(|tag| Tag::parse(tag).unwrap())
        .collect::<Vec<_>>();

    EventBuilder::new(Kind::Custom(kind as u16), content)
        .tags(tags)
        .build(keys.public_key())
        .sign(keys)
        .await
        .unwrap()
}

fn has_p_tag(event: &nostr::Event, pubkey_hex: &str) -> bool {
    event.tags.clone().to_vec().iter().any(|tag| {
        let parts = tag.as_slice();
        parts.len() >= 2 && parts[0] == "p" && parts[1] == pubkey_hex
    })
}

#[tokio::test]
async fn reusing_same_key_package_for_add_member_is_currently_accepted_by_mdk() {
    let alice_keys = Keys::generate();
    let bob_keys = Keys::generate();
    let alice_pubkey = alice_keys.public_key().to_hex();
    let bob_pubkey = bob_keys.public_key().to_hex();

    let alice = new_logged_in_engine(&alice_keys, "alice").await;
    let bob = new_logged_in_engine(&bob_keys, "bob").await;

    let bob_key_package = bob.mls_create_key_package().await.unwrap();
    let bob_key_package_event = sign_key_package_event(
        bob_key_package.kind,
        bob_key_package.content.clone(),
        bob_key_package.tags.clone(),
        &bob_keys,
    )
    .await;
    assert_eq!(
        bob_key_package_event.pubkey.to_hex(),
        bob_pubkey,
        "test KeyPackage event must be owned/signed by Bob"
    );
    let bob_key_package_event_id = bob_key_package_event.id.to_hex();
    let bob_key_package_json = bob_key_package_event.as_json();

    alice
        .mls_validate_key_package_event(&bob_key_package_json)
        .await
        .unwrap();

    let first_group = alice
        .mls_create_group(
            "First group".to_string(),
            vec![alice_pubkey.clone()],
            vec!["wss://relay.example.com".to_string()],
        )
        .await
        .unwrap();

    let first_add = alice
        .mls_add_member(&first_group.group_id_hex, &bob_key_package_json)
        .await
        .unwrap();
    assert_eq!(
        first_add.welcome_event_data.recipient_pubkey, bob_pubkey,
        "Welcome recipient must remain the KeyPackage event owner"
    );
    let first_gift_wrap: nostr::Event =
        serde_json::from_str(&first_add.welcome_event_data.gift_wrapped_event_json).unwrap();
    assert!(
        has_p_tag(&first_gift_wrap, &bob_pubkey),
        "first Welcome gift wrap must target Bob"
    );
    alice
        .mls_merge_pending_commit(&first_group.group_id_hex)
        .await
        .unwrap();

    let second_group = alice
        .mls_create_group(
            "Second group".to_string(),
            vec![alice_pubkey],
            vec!["wss://relay.example.com".to_string()],
        )
        .await
        .unwrap();

    // This is the current MDK 0.7.x behavior: inviter-side add_members does not
    // reject reusing the exact same remote KeyPackage event in another group.
    // Therefore consumed KeyPackage event-id tracking must happen in platform
    // relay-fetch/prefs logic until/unless the core API grows an explicit helper.
    let second_add = alice
        .mls_add_member(&second_group.group_id_hex, &bob_key_package_json)
        .await
        .expect("MDK currently accepts reusing the same remote KeyPackage for add_member");

    assert_eq!(
        second_add.welcome_event_data.recipient_pubkey, bob_pubkey,
        "reused KeyPackage still routes Welcome to the KeyPackage owner"
    );
    assert!(
        !second_add.commit_event_data.content.is_empty(),
        "second add_member should produce a commit event"
    );
    assert!(
        !second_add
            .welcome_event_data
            .gift_wrapped_event_json
            .is_empty(),
        "second add_member should produce a gift-wrapped Welcome"
    );
    let second_gift_wrap: nostr::Event =
        serde_json::from_str(&second_add.welcome_event_data.gift_wrapped_event_json).unwrap();
    assert!(
        has_p_tag(&second_gift_wrap, &bob_pubkey),
        "second Welcome gift wrap must still target Bob"
    );

    println!(
        "MDK accepted reused KeyPackage event id {}; platform consumed tracking is required",
        bob_key_package_event_id
    );
}
