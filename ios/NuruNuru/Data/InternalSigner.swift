import CommonCrypto
import CryptoKit
import Foundation
import P256K
import Security

/// nsec-based Nostr signer backed by SecureKeyManager.
/// Mirrors Android InternalSigner.
///
/// Phase 1: Schnorr event signing (NIP-01).
/// Phase 3: NIP-04 encrypt / decrypt for DMs and NIP-07 bridge.
final class InternalSigner {

    private let keyManager: SecureKeyManager

    init(keyManager: SecureKeyManager) {
        self.keyManager = keyManager
    }

    // MARK: - Public Key

    /// Returns the x-only public key as lowercase hex.
    func getPublicKeyHex() -> String? {
        keyManager.getStoredPublicKeyHex()
    }

    // MARK: - Event Signing (NIP-01 Schnorr)

    /// Build and sign a Nostr event.
    func signEvent(
        kind: Int,
        tags: [[String]],
        content: String,
        createdAt: Int64 = Int64(Date().timeIntervalSince1970)
    ) throws -> NostrEvent {
        guard let pubkeyHex = getPublicKeyHex() else {
            throw SignerError.keyNotUnlocked
        }
        guard var keyBytes = keyManager.getKeyBytesCopy() else {
            throw SignerError.keyNotUnlocked
        }
        defer {
            keyBytes.withUnsafeMutableBufferPointer { ptr in
                ptr.baseAddress?.initialize(repeating: 0, count: ptr.count)
            }
        }

        return try NostrKeyUtils.buildAndSign(
            privateKeyBytes: keyBytes,
            publicKeyHex:    pubkeyHex,
            kind:            kind,
            tags:            tags,
            content:         content,
            createdAt:       createdAt
        )
    }

    // MARK: - NIP-04 Encryption

    /// NIP-04: Encrypt plaintext for `receiverPubkeyHex` (x-only 32-byte hex).
    /// Returns `base64(ciphertext)?iv=base64(iv)` or nil on failure.
    /// The AES key is the 32-byte x-coordinate of the ECDH shared point (no hashing).
    func nip04Encrypt(receiverPubkeyHex: String, plaintext: String) -> String? {
        guard var keyBytes = keyManager.getKeyBytesCopy() else { return nil }
        defer { zeroize(&keyBytes) }

        guard let sharedKey = nip04SharedKey(privKeyBytes: keyBytes, peerPubkeyHex: receiverPubkeyHex)
        else { return nil }

        var iv = [UInt8](repeating: 0, count: 16)
        guard SecRandomCopyBytes(kSecRandomDefault, 16, &iv) == errSecSuccess else { return nil }

        guard let encrypted = aesCBCEncrypt(key: sharedKey, iv: iv, plaintext: plaintext) else { return nil }
        return Data(encrypted).base64EncodedString() + "?iv=" + Data(iv).base64EncodedString()
    }

    /// NIP-04: Decrypt a `base64(ct)?iv=base64(iv)` ciphertext from `senderPubkeyHex`.
    func nip04Decrypt(senderPubkeyHex: String, ciphertext: String) -> String? {
        guard var keyBytes = keyManager.getKeyBytesCopy() else { return nil }
        defer { zeroize(&keyBytes) }

        guard let sharedKey = nip04SharedKey(privKeyBytes: keyBytes, peerPubkeyHex: senderPubkeyHex)
        else { return nil }

        let parts = ciphertext.components(separatedBy: "?iv=")
        guard parts.count == 2,
              let ctData = Data(base64Encoded: parts[0]),
              let ivData = Data(base64Encoded: parts[1]),
              ivData.count == 16
        else { return nil }

        return aesCBCDecrypt(key: sharedKey, iv: [UInt8](ivData), ciphertext: [UInt8](ctData))
    }

    // MARK: - NIP-44 Encryption (v2)

    /// NIP-44 v2: `recipientPubkeyHex` 向けに `plaintext` を暗号化する。
    /// 出力は base64 エンコード済みの "version(1) || nonce(32) || ciphertext || mac(32)" 形式。
    /// - Returns: 暗号化済み文字列。失敗時は `nil`。
    func nip44Encrypt(recipientPubkeyHex: String, plaintext: String) -> String? {
        guard var keyBytes = keyManager.getKeyBytesCopy() else { return nil }
        defer { zeroize(&keyBytes) }

        guard let sharedX = nip04SharedKey(privKeyBytes: keyBytes, peerPubkeyHex: recipientPubkeyHex),
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

    /// NIP-44 v2: `senderPubkeyHex` からの `ciphertext` を復号する。
    /// - Returns: 復号済みプレーンテキスト。検証失敗・フォーマットエラー時は `nil`。
    func nip44Decrypt(senderPubkeyHex: String, ciphertext: String) -> String? {
        guard var keyBytes = keyManager.getKeyBytesCopy() else { return nil }
        defer { zeroize(&keyBytes) }

        guard let raw = Data(base64Encoded: ciphertext) else { return nil }
        let bytes = Array(raw)
        // version(1) + nonce(32) + ct(≥1) + mac(32) = 最低 66 バイト
        guard bytes.count > 66, bytes[0] == 2 else { return nil }
        let macStart = bytes.count - 32
        let nonce = Array(bytes[1..<33])
        let ct    = Array(bytes[33..<macStart])
        let mac   = Array(bytes.suffix(32))

        guard let sharedX = nip04SharedKey(privKeyBytes: keyBytes, peerPubkeyHex: senderPubkeyHex),
              let convKey = nip44ConversationKey(sharedX: sharedX),
              let (cKey, cNonce, hKey) = nip44MessageKeys(conversationKey: convKey, nonce: nonce)
        else { return nil }

        // HMAC 検証
        let expectedMac = Array(HMAC<CryptoKit.SHA256>.authenticationCode(
            for: Data(nonce + ct),
            using: SymmetricKey(data: Data(hKey))
        ))
        guard mac == expectedMac else { return nil }

        let plainPadded = chacha20Stream(key: cKey, nonce: cNonce, data: ct)
        guard let unpadded = nip44Unpad(Data(plainPadded)) else { return nil }
        return String(data: unpadded, encoding: .utf8)
    }

    // MARK: - Errors

    enum SignerError: LocalizedError {
        case keyNotUnlocked
        case invalidPublicKey

        var errorDescription: String? {
            switch self {
            case .keyNotUnlocked:   return ErrorMessages.noSigningMethod
            case .invalidPublicKey: return "公開鍵の形式が正しくありません"
            }
        }
    }
}

// MARK: - Private NIP-04 Helpers

private extension InternalSigner {

    /// Compute the 32-byte NIP-04 shared key via secp256k1 ECDH.
    /// Result = x-coordinate of (privKey × peerPubKey).
    /// Using 0x02 prefix for x-only pubkey is correct: negation in secp256k1 preserves x.
    func nip04SharedKey(privKeyBytes: [UInt8], peerPubkeyHex: String) -> [UInt8]? {
        guard let peerPubBytes = NostrKeyUtils.hexToBytes(peerPubkeyHex),
              peerPubBytes.count == 32
        else { return nil }

        // x-only (32 B) → compressed (33 B) with even-parity assumption (0x02)
        let compressedPubData = Data([0x02] + peerPubBytes)

        guard let privKey = try? P256K.KeyAgreement.PrivateKey(dataRepresentation: Data(privKeyBytes)),
              let pubKey  = try? P256K.KeyAgreement.PublicKey(dataRepresentation: compressedPubData),
              let shared  = try? privKey.sharedSecretFromKeyAgreement(with: pubKey, format: .compressed)
        else { return nil }

        // compressed = [prefix(1), x(32)] — take the x-coordinate only
        return shared.withUnsafeBytes { buf -> [UInt8]? in
            let bytes = Array(buf)
            guard bytes.count >= 33 else { return nil }
            return Array(bytes[1 ..< 33])
        }
    }

    /// AES-256-CBC encrypt with PKCS7 padding (CommonCrypto).
    func aesCBCEncrypt(key: [UInt8], iv: [UInt8], plaintext: String) -> [UInt8]? {
        guard let data = plaintext.data(using: .utf8) else { return nil }
        let inBytes = [UInt8](data)
        var outBuffer = [UInt8](repeating: 0, count: inBytes.count + kCCBlockSizeAES128)
        var numOut = 0
        let status = CCCrypt(
            CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES),
            CCOptions(kCCOptionPKCS7Padding),
            key, kCCKeySizeAES256,
            iv,
            inBytes, inBytes.count,
            &outBuffer, outBuffer.count,
            &numOut
        )
        guard status == kCCSuccess else { return nil }
        return Array(outBuffer[..<numOut])
    }

    /// AES-256-CBC decrypt with PKCS7 padding (CommonCrypto).
    func aesCBCDecrypt(key: [UInt8], iv: [UInt8], ciphertext: [UInt8]) -> String? {
        var outBuffer = [UInt8](repeating: 0, count: ciphertext.count + kCCBlockSizeAES128)
        var numOut = 0
        let status = CCCrypt(
            CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES),
            CCOptions(kCCOptionPKCS7Padding),
            key, kCCKeySizeAES256,
            iv,
            ciphertext, ciphertext.count,
            &outBuffer, outBuffer.count,
            &numOut
        )
        guard status == kCCSuccess else { return nil }
        return String(bytes: Array(outBuffer[..<numOut]), encoding: .utf8)
    }

    /// Zero-fill a byte array to prevent key material from lingering in memory.
    func zeroize(_ bytes: inout [UInt8]) {
        bytes.withUnsafeMutableBufferPointer { ptr in
            ptr.baseAddress?.initialize(repeating: 0, count: ptr.count)
        }
    }

    // MARK: - NIP-44 Private Helpers

    /// HKDF-SHA256 で NIP-44 v2 conversation key を導出する。
    /// IKM = ECDH x-coordinate, salt = empty, info = "nip44-v2", len = 32
    private func nip44ConversationKey(sharedX: [UInt8]) -> [UInt8]? {
        let info = Data("nip44-v2".utf8)
        return HKDF<CryptoKit.SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: Data(sharedX)),
            info: info,
            outputByteCount: 32
        ).withUnsafeBytes { Array($0) }
    }

    /// HKDF-SHA256 で 76 バイトの message keys を導出し、
    /// (chacha_key[32], chacha_nonce[12], hmac_key[32]) を返す。
    private func nip44MessageKeys(
        conversationKey: [UInt8],
        nonce: [UInt8]
    ) -> ([UInt8], [UInt8], [UInt8])? {
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

    /// NIP-44 v2 padding: 2-byte BE length prefix + zero-padded to `calcPaddedLen`.
    private func nip44Pad(_ data: Data) -> Data {
        let len       = data.count
        let padded    = nip44CalcPaddedLen(len)
        var result    = Data(repeating: 0, count: padded + 2)
        result[0]     = UInt8((len >> 8) & 0xff)
        result[1]     = UInt8(len & 0xff)
        result.replaceSubrange(2..<(2 + len), with: data)
        return result
    }

    /// NIP-44 v2 unpad: reads 2-byte BE length and extracts the actual content.
    private func nip44Unpad(_ data: Data) -> Data? {
        guard data.count >= 2 else { return nil }
        let len = (Int(data[0]) << 8) | Int(data[1])
        guard len > 0, data.count >= len + 2 else { return nil }
        return data.subdata(in: 2..<(2 + len))
    }

    /// NIP-44 v2 padded length formula (matches the reference TypeScript spec).
    private func nip44CalcPaddedLen(_ len: Int) -> Int {
        guard len > 0 else { return 32 }
        if len <= 32 { return 32 }
        let v        = len - 1
        let nextPow  = 1 << (Int.bitWidth - v.leadingZeroBitCount)
        let chunk    = max(32, nextPow / 8)
        return chunk * ((len - 1) / chunk + 1)
    }

    // MARK: - ChaCha20 Stream Cipher (RFC 7539)

    /// XOR `data` with the ChaCha20 keystream (key=32B, nonce=12B, counter starts at 0).
    private func chacha20Stream(key: [UInt8], nonce: [UInt8], data: [UInt8]) -> [UInt8] {
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

    /// Produce one 64-byte ChaCha20 keystream block (RFC 7539, 20 rounds).
    private func chacha20Block(key: [UInt8], counter: UInt32, nonce: [UInt8]) -> [UInt8] {
        var s = [UInt32](repeating: 0, count: 16)
        s[0] = 0x61707865; s[1] = 0x3320646e; s[2] = 0x79622d32; s[3] = 0x6b206574
        for i in 0..<8 { s[4 + i] = cc20LE32(key,   i * 4) }
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

    private func cc20QR(_ s: inout [UInt32], _ a: Int, _ b: Int, _ c: Int, _ d: Int) {
        s[a] = s[a] &+ s[b]; s[d] ^= s[a]; s[d] = (s[d] << 16) | (s[d] >> 16)
        s[c] = s[c] &+ s[d]; s[b] ^= s[c]; s[b] = (s[b] << 12) | (s[b] >> 20)
        s[a] = s[a] &+ s[b]; s[d] ^= s[a]; s[d] = (s[d] <<  8) | (s[d] >> 24)
        s[c] = s[c] &+ s[d]; s[b] ^= s[c]; s[b] = (s[b] <<  7) | (s[b] >> 25)
    }

    private func cc20LE32(_ b: [UInt8], _ off: Int) -> UInt32 {
        UInt32(b[off]) | (UInt32(b[off+1]) << 8) | (UInt32(b[off+2]) << 16) | (UInt32(b[off+3]) << 24)
    }
}
