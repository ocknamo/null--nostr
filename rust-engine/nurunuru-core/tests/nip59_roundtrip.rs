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

async fn new_logged_in_engine(keys: &Keys, name: &str) -> std::sync::Arc<NuruNuruEngine> {
    let cfg = test_config(unique_db_path(name));
    let engine = NuruNuruEngine::new(keys.clone(), cfg).await.unwrap();
    engine.login(keys.public_key()).await.unwrap();
    engine
}

#[tokio::test]
async fn engine_signer_can_roundtrip_welcome_rumor_gift_wrap() {
    let alice_keys = Keys::generate();
    let bob_keys = Keys::generate();

    let alice = new_logged_in_engine(&alice_keys, "alice_welcome_engine_signer").await;
    let bob = new_logged_in_engine(&bob_keys, "bob_welcome_engine_signer").await;

    let bob_kp = bob.mls_create_key_package().await.unwrap();
    let bob_kp_event = {
        let tags = bob_kp
            .tags
            .iter()
            .map(|t| Tag::parse(t.clone()).unwrap())
            .collect::<Vec<_>>();
        EventBuilder::new(Kind::Custom(bob_kp.kind as u16), bob_kp.content.clone())
            .tags(tags)
            .build(bob_keys.public_key())
            .sign(&bob_keys)
            .await
            .unwrap()
    };

    let group = alice
        .mls_create_group(
            "Welcome Test".to_string(),
            vec![alice_keys.public_key().to_hex()],
            vec!["wss://example.com".to_string()],
        )
        .await
        .unwrap();

    let add_result = alice
        .mls_add_member(&group.group_id_hex, &bob_kp_event.as_json())
        .await
        .unwrap();

    let welcome_rumor: nostr::UnsignedEvent =
        serde_json::from_str(&add_result.welcome_event_data.inner_rumor_json).unwrap();

    let alice_engine_signer = alice.client_signer_for_tests().await.unwrap();
    let gw = EventBuilder::gift_wrap(
        &alice_engine_signer,
        &bob_keys.public_key(),
        welcome_rumor.clone(),
        [],
    )
    .await
    .unwrap();

    let unwrapped_with_raw = nostr::nips::nip59::extract_rumor(&bob_keys, &gw)
        .await
        .unwrap();
    assert_eq!(unwrapped_with_raw.rumor.kind, welcome_rumor.kind);
    assert_eq!(unwrapped_with_raw.rumor.pubkey, welcome_rumor.pubkey);

    let bob_engine_signer = bob.client_signer_for_tests().await.unwrap();
    let unwrapped_with_engine = nostr::nips::nip59::extract_rumor(&bob_engine_signer, &gw)
        .await
        .unwrap();
    assert_eq!(unwrapped_with_engine.rumor.kind, welcome_rumor.kind);
    assert_eq!(unwrapped_with_engine.rumor.pubkey, welcome_rumor.pubkey);
}

#[tokio::test]
async fn direct_nip59_giftwrap_roundtrip_works_between_two_engines() {
    let alice_keys = Keys::generate();
    let bob_keys = Keys::generate();

    let alice = new_logged_in_engine(&alice_keys, "alice_direct_giftwrap").await;
    let bob = new_logged_in_engine(&bob_keys, "bob_direct_giftwrap").await;

    let rumor = EventBuilder::new(Kind::Custom(444), "hello-welcome")
        .tags(vec![Tag::parse([
            "p",
            bob_keys.public_key().to_hex().as_str(),
        ])
        .unwrap()])
        .build(alice_keys.public_key());

    let gift = EventBuilder::gift_wrap(&alice_keys, &bob_keys.public_key(), rumor, [])
        .await
        .unwrap();

    let extracted = nostr::nips::nip59::extract_rumor(&bob_keys, &gift)
        .await
        .unwrap();
    assert_eq!(u16::from(extracted.rumor.kind), 444);
    assert_eq!(extracted.rumor.content, "hello-welcome");
}
