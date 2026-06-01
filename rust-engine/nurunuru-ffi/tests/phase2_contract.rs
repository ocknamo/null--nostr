use serde_json::Value;
use uniffi_nurunuru::{derive_public_key_from_secret, generate_keypair, sign_event_json};

#[test]
fn keygen_derive_and_sign_event_json_contract() {
    let kp = generate_keypair().expect("generate keypair");
    assert_eq!(kp.private_key_hex.len(), 64);
    assert!(kp.nsec.starts_with("nsec1"));
    assert_eq!(kp.public_key_hex.len(), 64);
    assert!(kp.npub.starts_with("npub1"));

    let derived = derive_public_key_from_secret(kp.private_key_hex.clone()).expect("derive pubkey");
    assert_eq!(derived, kp.public_key_hex);
    let derived_from_nsec =
        derive_public_key_from_secret(kp.nsec.clone()).expect("derive pubkey from nsec");
    assert_eq!(derived_from_nsec, kp.public_key_hex);

    let signed = sign_event_json(
        kp.private_key_hex,
        1,
        "hello from iOS FFI contract".to_string(),
        vec![vec!["client".to_string(), "nullnull iOS".to_string()]],
        Some(1_700_000_000),
    )
    .expect("sign event");
    let value: Value = serde_json::from_str(&signed).expect("valid json");
    assert_eq!(value["pubkey"].as_str(), Some(kp.public_key_hex.as_str()));
    assert_eq!(value["created_at"].as_u64(), Some(1_700_000_000));
    assert_eq!(value["kind"].as_u64(), Some(1));
    assert_eq!(
        value["content"].as_str(),
        Some("hello from iOS FFI contract")
    );
    assert!(value["id"].as_str().is_some());
    assert!(value["sig"].as_str().is_some());
}
