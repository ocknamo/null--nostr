import CommonCrypto
import CryptoKit
import Foundation
import P256K
import Security

/// Passkey/PRF-direct backed Nostr signer.
///
/// Implements the same `EventSigner` protocol as `InternalSigner`, so it slots into
/// any call site that currently constructs an `InternalSigner` (NostrRepository,
/// SignUpSheet, etc.) without further refactoring.
///
/// The secret key is **never** stored on disk. Each `signEvent` / NIP-04 / NIP-44
/// call resolves the 32-byte PRF output via `NosskeyManager.deriveSecretKey`, which
/// prompts the user for a Face ID / Touch ID assertion. To avoid prompting on every
/// reactive UI tick we keep a short-lived in-memory cache (default 5 min).
///
/// The cache is opt-in: pass `cacheTTL: 0` to disable.
final class NosskeySigner: EventSigner {

    private let nosskeyManager: NosskeyManager
    private let keyInfo: NosskeyKeyInfo
    private let rpId: String
    private let cacheTTL: TimeInterval

    private var cachedSecret: [UInt8]?
    private var cachedAt: Date?

    init(
        nosskeyManager: NosskeyManager,
        keyInfo: NosskeyKeyInfo,
        rpId: String = NosskeyManager.defaultRpId,
        cacheTTL: TimeInterval = 5 * 60
    ) {
        self.nosskeyManager = nosskeyManager
        self.keyInfo = keyInfo
        self.rpId = rpId
        self.cacheTTL = cacheTTL
    }

    deinit {
        // Best-effort zeroize on dealloc.
        zeroizeCache()
    }

    // MARK: - Cache control

    /// Pre-warm the cache so subsequent synchronous calls (`signEvent`, NIP-04,
    /// NIP-44) succeed without throwing.
    ///
    /// Call this from a UI layer that can `await` (e.g. a Task in the sign-up
    /// composer) right before doing one or more synchronous publishes.
    @MainActor
    func warmCache() async throws {
        if isCacheFresh() { return }
        let secret = try await nosskeyManager.deriveSecretKey(for: keyInfo, rpId: rpId)
        cachedSecret = secret
        cachedAt = Date()
    }

    /// Force-clear the cached secret key.
    func zeroizeCache() {
        if cachedSecret != nil {
            cachedSecret?.withUnsafeMutableBufferPointer { ptr in
                ptr.baseAddress?.initialize(repeating: 0, count: ptr.count)
            }
        }
        cachedSecret = nil
        cachedAt = nil
    }

    private func isCacheFresh() -> Bool {
        guard cachedSecret != nil, let at = cachedAt else { return false }
        guard cacheTTL > 0 else { return false }
        return Date().timeIntervalSince(at) < cacheTTL
    }

    /// Returns a copy of the cached secret, or throws if the cache is cold.
    /// Callers must zeroize the returned buffer after use.
    private func requireCachedSecretCopy() throws -> [UInt8] {
        guard let secret = cachedSecret, isCacheFresh() else {
            // Cold cache — the caller should have awaited `warmCache()` first.
            throw NosskeyError.assertionFailed(
                "パスキーのキャッシュが切れています。再度認証してください"
            )
        }
        return Array(secret)
    }

    // MARK: - EventSigner

    func getPublicKeyHex() -> String? {
        keyInfo.pubkey
    }

    func signEvent(
        kind: Int,
        tags: [[String]],
        content: String,
        createdAt: Int64
    ) throws -> NostrEvent {
        var secret = try requireCachedSecretCopy()
        defer { zeroize(&secret) }

        return try NostrKeyUtils.buildAndSign(
            privateKeyBytes: secret,
            publicKeyHex:    keyInfo.pubkey,
            kind:            kind,
            tags:            tags,
            content:         content,
            createdAt:       createdAt
        )
    }

    // MARK: - NIP-04

    func nip04Encrypt(receiverPubkeyHex: String, plaintext: String) -> String? {
        guard var secret = try? requireCachedSecretCopy() else { return nil }
        defer { zeroize(&secret) }

        guard let sharedKey = nip04SharedKey(privKeyBytes: secret, peerPubkeyHex: receiverPubkeyHex)
        else { return nil }

        var iv = [UInt8](repeating: 0, count: 16)
        guard SecRandomCopyBytes(kSecRandomDefault, 16, &iv) == errSecSuccess else { return nil }
        guard let encrypted = aesCBCEncrypt(key: sharedKey, iv: iv, plaintext: plaintext) else { return nil }
        return Data(encrypted).base64EncodedString() + "?iv=" + Data(iv).base64EncodedString()
    }

    func nip04Decrypt(senderPubkeyHex: String, ciphertext: String) -> String? {
        guard var secret = try? requireCachedSecretCopy() else { return nil }
        defer { zeroize(&secret) }

        guard let sharedKey = nip04SharedKey(privKeyBytes: secret, peerPubkeyHex: senderPubkeyHex)
        else { return nil }

        let parts = ciphertext.components(separatedBy: "?iv=")
        guard parts.count == 2,
              let ctData = Data(base64Encoded: parts[0]),
              let ivData = Data(base64Encoded: parts[1]),
              ivData.count == 16
        else { return nil }
        return aesCBCDecrypt(key: sharedKey, iv: [UInt8](ivData), ciphertext: [UInt8](ctData))
    }

    // MARK: - NIP-44 v2

    func nip44Encrypt(recipientPubkeyHex: String, plaintext: String) -> String? {
        guard var secret = try? requireCachedSecretCopy() else { return nil }
        defer { zeroize(&secret) }

        guard let sharedX = nip04SharedKey(privKeyBytes: secret, peerPubkeyHex: recipientPubkeyHex),
              let convKey = nip44ConversationKey(sharedX: sharedX)
        else { return nil }

        var nonce = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, 32, &nonce) == errSecSuccess else { return nil }
        guard let (cKey, cNonce, hKey) = nip44MessageKeys(conversationKey: convKey, nonce: nonce) else { return nil }

        guard let plainData = plaintext.data(using: .utf8) else { return nil }
        let padded     = Array(nip44Pad(plainData))
        let ciphertext = chacha20Stream(key: cKey, nonce: cNonce, data: padded)
        let mac = Array(HMAC<CryptoKit.SHA256>.authenticationCode(
            for: Data(nonce + ciphertext),
            using: SymmetricKey(data: Data(hKey))
        ))
        return Data([UInt8(2)] + nonce + ciphertext + mac).base64EncodedString()
    }

    func nip44Decrypt(senderPubkeyHex: String, ciphertext: String) -> String? {
        guard var secret = try? requireCachedSecretCopy() else { return nil }
        defer { zeroize(&secret) }

        guard let raw = Data(base64Encoded: ciphertext) else { return nil }
        let bytes = Array(raw)
        guard bytes.count > 66, bytes[0] == 2 else { return nil }
        let macStart = bytes.count - 32
        let nonce = Array(bytes[1..<33])
        let ct    = Array(bytes[33..<macStart])
        let mac   = Array(bytes.suffix(32))

        guard let sharedX = nip04SharedKey(privKeyBytes: secret, peerPubkeyHex: senderPubkeyHex),
              let convKey = nip44ConversationKey(sharedX: sharedX),
              let (cKey, cNonce, hKey) = nip44MessageKeys(conversationKey: convKey, nonce: nonce)
        else { return nil }

        let expectedMac = Array(HMAC<CryptoKit.SHA256>.authenticationCode(
            for: Data(nonce + ct),
            using: SymmetricKey(data: Data(hKey))
        ))
        guard mac == expectedMac else { return nil }

        let plainPadded = chacha20Stream(key: cKey, nonce: cNonce, data: ct)
        guard let unpadded = nip44Unpad(Data(plainPadded)) else { return nil }
        return String(data: unpadded, encoding: .utf8)
    }
}

// MARK: - Shared crypto helpers (mirrored from InternalSigner)

private extension NosskeySigner {

    func nip04SharedKey(privKeyBytes: [UInt8], peerPubkeyHex: String) -> [UInt8]? {
        guard let peerPubBytes = NostrKeyUtils.hexToBytes(peerPubkeyHex),
              peerPubBytes.count == 32
        else { return nil }
        let compressedPubData = Data([0x02] + peerPubBytes)

        guard let privKey = try? P256K.KeyAgreement.PrivateKey(dataRepresentation: Data(privKeyBytes)),
              let pubKey  = try? P256K.KeyAgreement.PublicKey(dataRepresentation: compressedPubData),
              let shared  = try? privKey.sharedSecretFromKeyAgreement(with: pubKey, format: .compressed)
        else { return nil }

        return shared.withUnsafeBytes { buf -> [UInt8]? in
            let bytes = Array(buf)
            guard bytes.count >= 33 else { return nil }
            return Array(bytes[1 ..< 33])
        }
    }

    func aesCBCEncrypt(key: [UInt8], iv: [UInt8], plaintext: String) -> [UInt8]? {
        guard let data = plaintext.data(using: .utf8) else { return nil }
        let inBytes = [UInt8](data)
        var outBuffer = [UInt8](repeating: 0, count: inBytes.count + kCCBlockSizeAES128)
        var numOut = 0
        let status = CCCrypt(
            CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES),
            CCOptions(kCCOptionPKCS7Padding),
            key, kCCKeySizeAES256, iv,
            inBytes, inBytes.count,
            &outBuffer, outBuffer.count, &numOut
        )
        guard status == kCCSuccess else { return nil }
        return Array(outBuffer[..<numOut])
    }

    func aesCBCDecrypt(key: [UInt8], iv: [UInt8], ciphertext: [UInt8]) -> String? {
        var outBuffer = [UInt8](repeating: 0, count: ciphertext.count + kCCBlockSizeAES128)
        var numOut = 0
        let status = CCCrypt(
            CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES),
            CCOptions(kCCOptionPKCS7Padding),
            key, kCCKeySizeAES256, iv,
            ciphertext, ciphertext.count,
            &outBuffer, outBuffer.count, &numOut
        )
        guard status == kCCSuccess else { return nil }
        return String(bytes: Array(outBuffer[..<numOut]), encoding: .utf8)
    }

    func zeroize(_ bytes: inout [UInt8]) {
        bytes.withUnsafeMutableBufferPointer { ptr in
            ptr.baseAddress?.initialize(repeating: 0, count: ptr.count)
        }
    }

    // NIP-44 v2 — same as InternalSigner private helpers (kept local for symmetry).
    func nip44ConversationKey(sharedX: [UInt8]) -> [UInt8]? {
        let info = Data("nip44-v2".utf8)
        return HKDF<CryptoKit.SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: Data(sharedX)),
            info: info,
            outputByteCount: 32
        ).withUnsafeBytes { Array($0) }
    }

    func nip44MessageKeys(conversationKey: [UInt8], nonce: [UInt8]) -> ([UInt8], [UInt8], [UInt8])? {
        let info = Data("nip44-v2".utf8)
        let raw  = HKDF<CryptoKit.SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: Data(conversationKey)),
            salt: Data(nonce),
            info: info,
            outputByteCount: 76
        ).withUnsafeBytes { Array($0) }
        guard raw.count == 76 else { return nil }
        return (Array(raw[0..<32]), Array(raw[32..<44]), Array(raw[44..<76]))
    }

    func nip44Pad(_ data: Data) -> Data {
        let len    = data.count
        let padded = nip44CalcPaddedLen(len)
        var result = Data(repeating: 0, count: padded + 2)
        result[0]  = UInt8((len >> 8) & 0xff)
        result[1]  = UInt8(len & 0xff)
        result.replaceSubrange(2..<(2 + len), with: data)
        return result
    }

    func nip44Unpad(_ data: Data) -> Data? {
        guard data.count >= 2 else { return nil }
        let len = (Int(data[0]) << 8) | Int(data[1])
        guard len > 0, data.count >= len + 2 else { return nil }
        return data.subdata(in: 2..<(2 + len))
    }

    func nip44CalcPaddedLen(_ len: Int) -> Int {
        guard len > 0 else { return 32 }
        if len <= 32 { return 32 }
        let v        = len - 1
        let nextPow  = 1 << (Int.bitWidth - v.leadingZeroBitCount)
        let chunk    = max(32, nextPow / 8)
        return chunk * ((len - 1) / chunk + 1)
    }

    func chacha20Stream(key: [UInt8], nonce: [UInt8], data: [UInt8]) -> [UInt8] {
        var result:  [UInt8] = [UInt8](repeating: 0, count: data.count)
        var counter: UInt32  = 0
        var offset           = 0
        while offset < data.count {
            let block = chacha20Block(key: key, counter: counter, nonce: nonce)
            let take  = min(64, data.count - offset)
            for i in 0..<take { result[offset + i] = data[offset + i] ^ block[i] }
            offset  += take
            counter += 1
        }
        return result
    }

    func chacha20Block(key: [UInt8], counter: UInt32, nonce: [UInt8]) -> [UInt8] {
        var s = [UInt32](repeating: 0, count: 16)
        s[0] = 0x61707865; s[1] = 0x3320646e; s[2] = 0x79622d32; s[3] = 0x6b206574
        for i in 0..<8 { s[4 + i] = cc20LE32(key, i * 4) }
        s[12] = counter
        s[13] = cc20LE32(nonce, 0)
        s[14] = cc20LE32(nonce, 4)
        s[15] = cc20LE32(nonce, 8)

        var w = s
        for _ in 0..<10 {
            cc20QR(&w, 0, 4,  8, 12); cc20QR(&w, 1, 5,  9, 13)
            cc20QR(&w, 2, 6, 10, 14); cc20QR(&w, 3, 7, 11, 15)
            cc20QR(&w, 0, 5, 10, 15); cc20QR(&w, 1, 6, 11, 12)
            cc20QR(&w, 2, 7,  8, 13); cc20QR(&w, 3, 4,  9, 14)
        }
        for i in 0..<16 { w[i] = w[i] &+ s[i] }

        var out = [UInt8](repeating: 0, count: 64)
        for i in 0..<16 {
            out[i*4]   = UInt8( w[i]        & 0xff)
            out[i*4+1] = UInt8((w[i] >>  8) & 0xff)
            out[i*4+2] = UInt8((w[i] >> 16) & 0xff)
            out[i*4+3] = UInt8((w[i] >> 24) & 0xff)
        }
        return out
    }

    func cc20QR(_ s: inout [UInt32], _ a: Int, _ b: Int, _ c: Int, _ d: Int) {
        s[a] = s[a] &+ s[b]; s[d] ^= s[a]; s[d] = (s[d] << 16) | (s[d] >> 16)
        s[c] = s[c] &+ s[d]; s[b] ^= s[c]; s[b] = (s[b] << 12) | (s[b] >> 20)
        s[a] = s[a] &+ s[b]; s[d] ^= s[a]; s[d] = (s[d] <<  8) | (s[d] >> 24)
        s[c] = s[c] &+ s[d]; s[b] ^= s[c]; s[b] = (s[b] <<  7) | (s[b] >> 25)
    }

    func cc20LE32(_ b: [UInt8], _ off: Int) -> UInt32 {
        UInt32(b[off]) | (UInt32(b[off+1]) << 8) | (UInt32(b[off+2]) << 16) | (UInt32(b[off+3]) << 24)
    }
}
