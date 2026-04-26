import Foundation
import Security

/// iOS Keychain-based Nostr private key storage.
/// Mirrors Android SecureKeyManager.
///
/// ## Security contract
/// - Private key bytes stored in Keychain with kSecAttrAccessibleWhenUnlockedThisDeviceOnly
/// - In-memory copy zeroed on logout, deinit, and after each use
/// - Never log, print, or paste key material
/// - Never store in UserDefaults or files
final class SecureKeyManager {

    private enum KeychainAccount {
        static let privateKey    = "nostr.private_key"
        static let publicKeyHex  = "nostr.public_key_hex"
    }

    private let service = "io.nurunuru.app"

    // In-memory key — zeroed out when not needed
    private var _keyBytes: [UInt8]?

    // MARK: - Store

    /// Encrypt and persist the private key in Keychain.
    /// - Parameters:
    ///   - privateKeyBytes: Raw 32-byte secp256k1 private key
    ///   - publicKeyHex:    Corresponding x-only public key as lowercase hex
    func storeKey(privateKeyBytes: [UInt8], publicKeyHex: String) throws {
        guard privateKeyBytes.count == 32 else {
            throw KeyError.invalidKeySize
        }

        try saveToKeychain(data: Data(privateKeyBytes), account: KeychainAccount.privateKey)
        try saveToKeychain(data: Data(publicKeyHex.utf8), account: KeychainAccount.publicKeyHex)

        zeroize()
        _keyBytes = privateKeyBytes
    }

    // MARK: - Unlock

    /// Load the private key from Keychain into memory.
    /// Call this on app start after confirming stored key exists.
    @discardableResult
    func unlockKey() -> Bool {
        guard let data = loadFromKeychain(account: KeychainAccount.privateKey) else { return false }
        let bytes = [UInt8](data)
        zeroize()
        _keyBytes = bytes
        return true
    }

    // MARK: - Access

    var isUnlocked: Bool { _keyBytes != nil }

    func hasStoredKey() -> Bool {
        loadFromKeychain(account: KeychainAccount.privateKey) != nil
    }

    func getStoredPublicKeyHex() -> String? {
        guard let data = loadFromKeychain(account: KeychainAccount.publicKeyHex) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Returns a copy of key bytes. Caller MUST zero the returned array after use.
    func getKeyBytesCopy() -> [UInt8]? {
        _keyBytes.map { Array($0) }
    }

    /// Returns key as hex string for temporary use (e.g. signing).
    /// Do not store the returned string.
    func getKeyHexTemporary() -> String? {
        _keyBytes.map { bytes in
            bytes.map { String(format: "%02x", $0) }.joined()
        }
    }

    // MARK: - Zeroize

    /// Zero in-memory key material. Call on logout and background transitions.
    func zeroize() {
        _keyBytes?.withUnsafeMutableBufferPointer { ptr in
            ptr.baseAddress?.initialize(repeating: 0, count: ptr.count)
        }
        _keyBytes = nil
    }

    // MARK: - Delete

    func deleteAll() {
        zeroize()
        deleteFromKeychain(account: KeychainAccount.privateKey)
        deleteFromKeychain(account: KeychainAccount.publicKeyHex)
    }

    // MARK: - Keychain Internals

    private func saveToKeychain(data: Data, account: String) throws {
        // Delete existing entry first to avoid errSecDuplicateItem
        deleteFromKeychain(account: account)

        let query: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrService as String:      service,
            kSecAttrAccount as String:      account,
            kSecValueData as String:        data,
            kSecAttrAccessible as String:   kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeyError.keychainWriteFailed(status)
        }
    }

    private func loadFromKeychain(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    private func deleteFromKeychain(account: String) {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Errors

    enum KeyError: LocalizedError {
        case invalidKeySize
        case keychainWriteFailed(OSStatus)

        var errorDescription: String? {
            switch self {
            case .invalidKeySize:
                return "秘密鍵のサイズが正しくありません（32バイト必要）"
            case .keychainWriteFailed(let status):
                return "Keychainへの書き込みに失敗しました (status: \(status))"
            }
        }
    }

    deinit { zeroize() }
}
