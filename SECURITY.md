# Security Policy

ぬるぬるは、かわいさと秘密鍵への厳格さを同時に持つことを大切にしています。

## Do not post secrets in public

以下に関する脆弱性・再現手順・秘密情報を、公開 GitHub Issue / public Nostr post / public chat に書かないでください。

- private key / nsec / seed / mnemonic
- signature bypass / signing oracle
- key derivation / passkey / PRF
- Keychain / secure storage / Android Keystore
- NIP-04 / NIP-44 / NIP-46 / MLS encryption
- exploit details that allow account takeover or key exposure

## Reporting a vulnerability

Preferred:

1. Use GitHub Security Advisory / private vulnerability reporting if available for this repository.
2. If private reporting is unavailable, open a public Issue with **only** this kind of minimal text:

```text
Security contact request: I found a possible issue related to [area only: key storage/signing/passkey/etc.].
No details are included publicly.
```

Do not include exploit details until a private channel is confirmed.

Project contact npub:

```text
npub194dkgpxl2vk7pqkeualh7sjh5m6rldumh80gm5av0h67d494qzcqum2u20
```

## Response expectation

Security response is best-effort. The project currently operates with limited maintainer capacity, so this is not a contractual SLA.

High-priority areas:

- private key exposure
- signing without user intent
- account takeover
- encrypted message disclosure
- data loss in secure storage

## Public disclosure

Please avoid public disclosure until the project has had time to investigate and prepare a fix or mitigation.
