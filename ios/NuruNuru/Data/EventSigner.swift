import Foundation

/// Common signer abstraction used by `NostrRepository`, `ImageUploadService`, and other
/// call sites that previously coupled directly to `InternalSigner`.
///
/// Two production conformers exist:
///   - `InternalSigner` — nsec-backed signer using `SecureKeyManager` (Keychain).
///   - `NosskeySigner`  — Passkey/PRF-direct signer that re-derives the secret on demand.
///
/// All Schnorr / NIP-04 / NIP-44 operations are kept **synchronous** so existing call
/// sites do not need refactoring. Passkey-backed signing relies on a short-lived
/// in-memory cache; if the cache is cold the call throws and the UI layer is
/// expected to warm it explicitly (`NosskeySigner.warmCache()`).
protocol EventSigner: AnyObject {

    /// Returns the x-only public key as lowercase hex, or nil when unavailable.
    func getPublicKeyHex() -> String?

    /// NIP-01 Schnorr sign of a Nostr event.
    func signEvent(
        kind: Int,
        tags: [[String]],
        content: String,
        createdAt: Int64
    ) throws -> NostrEvent

    /// NIP-04 encrypt — returns `base64(ct)?iv=base64(iv)` or nil on failure.
    func nip04Encrypt(receiverPubkeyHex: String, plaintext: String) -> String?

    /// NIP-04 decrypt — returns plaintext or nil on failure.
    func nip04Decrypt(senderPubkeyHex: String, ciphertext: String) -> String?

    /// NIP-44 v2 encrypt.
    func nip44Encrypt(recipientPubkeyHex: String, plaintext: String) -> String?

    /// NIP-44 v2 decrypt.
    func nip44Decrypt(senderPubkeyHex: String, ciphertext: String) -> String?
}

extension EventSigner {
    /// Convenience overload that defaults `createdAt` to "now" — mirrors the
    /// original `InternalSigner.signEvent(kind:tags:content:)` signature so
    /// existing call sites compile unchanged.
    func signEvent(
        kind: Int,
        tags: [[String]],
        content: String
    ) throws -> NostrEvent {
        try signEvent(
            kind:      kind,
            tags:      tags,
            content:   content,
            createdAt: Int64(Date().timeIntervalSince1970)
        )
    }
}
