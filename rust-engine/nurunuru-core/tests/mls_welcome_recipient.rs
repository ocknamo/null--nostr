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
        "nurunuru_mls_welcome_recipient_{}_{}_{}.sqlite3",
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
async fn welcome_1059_recipient_is_key_package_event_owner() {
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
    let bob_key_package_json = bob_key_package_event.as_json();

    alice
        .mls_validate_key_package_event(&bob_key_package_json)
        .await
        .unwrap();

    let group = alice
        .mls_create_group(
            "Welcome recipient regression".to_string(),
            vec![alice_pubkey.clone()],
            vec!["wss://relay.example.com".to_string()],
        )
        .await
        .unwrap();

    let add_result = alice
        .mls_add_member(&group.group_id_hex, &bob_key_package_json)
        .await
        .unwrap();

    assert_eq!(
        add_result.welcome_event_data.recipient_pubkey, bob_pubkey,
        "Welcome 1059 recipient_pubkey must be the KeyPackage event owner pubkey"
    );

    let gift_wrap: nostr::Event = serde_json::from_str(
        &add_result.welcome_event_data.gift_wrapped_event_json,
    )
    .unwrap();
    assert_eq!(
        u16::from(gift_wrap.kind),
        1059,
        "Welcome must be returned as a NIP-59 gift wrap (kind 1059)"
    );
    assert!(
        has_p_tag(&gift_wrap, &bob_pubkey),
        "Kind 1059 p tag must point at the KeyPackage event owner (Bob)"
    );

    let extracted_with_bob_raw_keys = nostr::nips::nip59::extract_rumor(&bob_keys, &gift_wrap)
        .await
        .expect("Bob raw keys must unwrap the Welcome gift wrap");
    assert_eq!(
        u16::from(extracted_with_bob_raw_keys.rumor.kind),
        444,
        "extracted Welcome rumor must be kind 444"
    );

    let bob_engine_signer = bob.client_signer_for_tests().await.unwrap();
    let extracted_with_bob_signer =
        nostr::nips::nip59::extract_rumor(&bob_engine_signer, &gift_wrap)
            .await
            .expect("Bob engine signer must unwrap the Welcome gift wrap");
    assert_eq!(
        u16::from(extracted_with_bob_signer.rumor.kind),
        444,
        "Bob signer must extract a kind 444 Welcome rumor"
    );

    let wrong_recipient_result = nostr::nips::nip59::extract_rumor(&alice_keys, &gift_wrap).await;
    assert!(
        wrong_recipient_result.is_err(),
        "Alice/wrong recipient keys must not unwrap Bob's Welcome gift wrap"
    );
}
