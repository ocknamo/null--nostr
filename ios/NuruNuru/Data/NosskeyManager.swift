import AuthenticationServices
import CryptoKit
import Foundation
import P256K
import UIKit

// MARK: - Public Types

/// Persisted Passkey/Nosskey credential metadata.
///
/// The actual secp256k1 private key is **never** stored. On every signing call we
/// re-prompt the user for the Passkey assertion (Face ID / Touch ID) and recompute
/// the secret from the PRF output. Only this lightweight handle survives in
/// UserDefaults.
struct NosskeyKeyInfo: Codable, Equatable, Sendable {
    /// WebAuthn credential ID returned by the platform authenticator.
    let credentialId: Data
    /// secp256k1 x-only public key (lowercase hex, 64 chars) derived from the PRF output.
    let pubkey: String
    /// PRF salt input (fixed `"nostr-pwk"` UTF-8 bytes for Nosskey direct method).
    let salt: Data
    /// Optional display username supplied at registration time.
    var username: String?
}

/// Error vocabulary for Passkey/Nosskey flows.
enum NosskeyError: LocalizedError {
    case unsupported
    case prfUnsupported
    case userCancelled
    case prfMissing
    case invalidPrfOutput
    case registrationFailed(String)
    case assertionFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupported:
            return "この端末ではパスキーが利用できません（iOS 18以降が必要です）"
        case .prfUnsupported:
            return "このパスキーはPRF拡張に対応していません"
        case .userCancelled:
            return "パスキーの操作がキャンセルされました"
        case .prfMissing:
            return "パスキーからPRF出力を取得できませんでした"
        case .invalidPrfOutput:
            return "PRF出力のサイズが不正です（32バイト必要）"
        case .registrationFailed(let msg):
            return "パスキーの登録に失敗しました: \(msg)"
        case .assertionFailed(let msg):
            return "パスキーの認証に失敗しました: \(msg)"
        }
    }
}

// MARK: - NosskeyManager

/// Wraps `AuthenticationServices` Passkey APIs for the Nosskey "PRF direct method".
///
/// ## Production deployment note
/// `rpId` defaults to the Nostr-side canonical host `"www.nullnull.app"`.
/// For real Passkey registration on physical devices, an Associated Domains
/// entitlement (`webcredentials:www.nullnull.app`) **and** the AASA file at
/// `https://www.nullnull.app/.well-known/apple-app-site-association`
/// must be deployed:
///
/// ```json
/// {
///   "webcredentials": {
///     "apps": ["66G7S3P755.io.nurunuru.app"]
///   }
/// }
/// ```
///
/// Until that is set up, registration will fail on physical hardware. iOS Simulator
/// (iOS 18+) shows the system prompt regardless of AASA presence.
///
/// Sendable-safe: this class is intentionally `@MainActor`-isolated because the
/// underlying `ASAuthorizationController` API is `UIKit`-bound.
@MainActor
final class NosskeyManager: NSObject {

    // MARK: - Constants

    /// Default Relying Party identifier — see Production deployment note above.
    nonisolated static let defaultRpId = "www.nullnull.app"

    /// Fixed PRF salt for the Nosskey direct method.
    /// UTF-8 of `"nostr-pwk"` → `[0x6e, 0x6f, 0x73, 0x74, 0x72, 0x2d, 0x70, 0x77, 0x6b]`.
    nonisolated static let nosskeySalt: Data = Data("nostr-pwk".utf8)

    /// UserDefaults key for the persisted `NosskeyKeyInfo`.
    private static let storageKey = "nurunuru_nosskey_keyinfo"

    /// True when the platform supports the PRF extension (iOS 18+).
    static var isPlatformSupported: Bool {
        if #available(iOS 18.0, *) { return true }
        return false
    }

    // MARK: - Internal continuation bridge

    /// Output payload from the delegate during registration.
    fileprivate struct RegistrationResult {
        let credentialId: Data
        let prfOutput: Data?
    }

    /// Output payload from the delegate during assertion.
    fileprivate struct AssertionResult {
        let credentialId: Data
        let prfOutput: Data
    }

    private var registrationContinuation: CheckedContinuation<RegistrationResult, Error>?
    private var assertionContinuation: CheckedContinuation<AssertionResult, Error>?

    /// Strong-retain the controller during the async hop so the delegate fires.
    private var activeController: ASAuthorizationController?

    override init() {
        super.init()
    }

    // MARK: - Public API

    /// Create a new Passkey credential with PRF support and derive the corresponding
    /// secp256k1 x-only public key from the first PRF output.
    func createPasskey(
        username: String,
        displayName: String,
        rpId: String = NosskeyManager.defaultRpId
    ) async throws -> NosskeyKeyInfo {
        guard #available(iOS 18.0, *) else { throw NosskeyError.unsupported }

        // 32-byte random user handle — required by WebAuthn spec for new accounts.
        var userIdBytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, 32, &userIdBytes) == errSecSuccess else {
            throw NosskeyError.registrationFailed("ユーザーID生成に失敗しました")
        }
        let userId = Data(userIdBytes)

        // 32-byte random challenge — server is not involved; this is local only.
        var challengeBytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, 32, &challengeBytes) == errSecSuccess else {
            throw NosskeyError.registrationFailed("チャレンジ生成に失敗しました")
        }
        let challenge = Data(challengeBytes)

        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(
            relyingPartyIdentifier: rpId
        )
        let request = provider.createCredentialRegistrationRequest(
            challenge: challenge,
            name: username.isEmpty ? "nurunuru-user" : username,
            userID: userId
        )
        // Ask the authenticator to advertise PRF support during registration.
        // `checkForSupport` returns only the support flag; we evaluate PRF via an
        // immediate assertion below to retrieve the 32-byte secret.
        request.prf = ASAuthorizationPublicKeyCredentialPRFRegistrationInput.checkForSupport

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        activeController = controller

        let result: RegistrationResult = try await withCheckedThrowingContinuation { continuation in
            self.registrationContinuation = continuation
            controller.performRequests()
        }
        activeController = nil

        // The registration ceremony rarely returns the PRF output directly on iOS
        // (the spec allows `enabled: true` only). To derive the Nostr pubkey we must
        // run an *assertion* immediately after registration so we always have a
        // 32-byte PRF output to work with. This keeps the Nosskey "direct method"
        // contract: pubkey == derive(PRF output).
        let prfBytes: Data
        if let output = result.prfOutput, output.count == 32 {
            prfBytes = output
        } else {
            // Fallback: immediately request an assertion to pull the PRF output.
            let assertion = try await runAssertion(
                credentialId: result.credentialId,
                rpId: rpId,
                salt: NosskeyManager.nosskeySalt
            )
            guard assertion.prfOutput.count == 32 else { throw NosskeyError.invalidPrfOutput }
            prfBytes = assertion.prfOutput
        }

        // Derive secp256k1 x-only public key from the 32-byte PRF output.
        let pubkeyHex = try derivePubkeyHex(fromPrfBytes: [UInt8](prfBytes))

        // Zero the PRF copy — caller never sees the secret.
        var prfCopy = [UInt8](prfBytes)
        zeroize(&prfCopy)

        let info = NosskeyKeyInfo(
            credentialId: result.credentialId,
            pubkey: pubkeyHex,
            salt: NosskeyManager.nosskeySalt,
            username: username.isEmpty ? nil : username
        )
        return info
    }

    /// Re-derive the 32-byte secp256k1 secret by prompting for a Passkey assertion.
    /// The caller is responsible for zeroing the returned array after use.
    func deriveSecretKey(
        for keyInfo: NosskeyKeyInfo,
        rpId: String = NosskeyManager.defaultRpId
    ) async throws -> [UInt8] {
        guard #available(iOS 18.0, *) else { throw NosskeyError.unsupported }
        let assertion = try await runAssertion(
            credentialId: keyInfo.credentialId,
            rpId: rpId,
            salt: keyInfo.salt
        )
        guard assertion.prfOutput.count == 32 else { throw NosskeyError.invalidPrfOutput }
        return [UInt8](assertion.prfOutput)
    }

    // MARK: - Persistence

    func loadStoredKeyInfo() -> NosskeyKeyInfo? {
        guard let data = UserDefaults.standard.data(forKey: NosskeyManager.storageKey) else { return nil }
        return try? JSONDecoder().decode(NosskeyKeyInfo.self, from: data)
    }

    func saveKeyInfo(_ info: NosskeyKeyInfo) {
        guard let data = try? JSONEncoder().encode(info) else { return }
        UserDefaults.standard.set(data, forKey: NosskeyManager.storageKey)
    }

    func clearStoredKeyInfo() {
        UserDefaults.standard.removeObject(forKey: NosskeyManager.storageKey)
    }

    // MARK: - Internal

    /// Run a single Passkey assertion with PRF eval for the given credential / salt.
    private func runAssertion(
        credentialId: Data,
        rpId: String,
        salt: Data
    ) async throws -> AssertionResult {
        guard #available(iOS 18.0, *) else { throw NosskeyError.unsupported }

        var challengeBytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, 32, &challengeBytes) == errSecSuccess else {
            throw NosskeyError.assertionFailed("チャレンジ生成に失敗しました")
        }
        let challenge = Data(challengeBytes)

        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(
            relyingPartyIdentifier: rpId
        )
        let request = provider.createCredentialAssertionRequest(challenge: challenge)
        request.allowedCredentials = [
            ASAuthorizationPlatformPublicKeyCredentialDescriptor(credentialID: credentialId)
        ]
        let prfInputValues = ASAuthorizationPublicKeyCredentialPRFAssertionInput.InputValues(
            saltInput1: salt
        )
        request.prf = ASAuthorizationPublicKeyCredentialPRFAssertionInput
            .inputValues(prfInputValues)

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        activeController = controller

        let result: AssertionResult = try await withCheckedThrowingContinuation { continuation in
            self.assertionContinuation = continuation
            controller.performRequests()
        }
        activeController = nil
        return result
    }

    /// Derive a secp256k1 x-only public key hex from a 32-byte PRF output.
    private func derivePubkeyHex(fromPrfBytes prfBytes: [UInt8]) throws -> String {
        guard prfBytes.count == 32 else { throw NosskeyError.invalidPrfOutput }
        do {
            let privKey = try P256K.Schnorr.PrivateKey(dataRepresentation: Data(prfBytes))
            // x-only pubkey == 32 bytes
            let xonly = privKey.xonly.bytes
            return xonly.map { String(format: "%02x", $0) }.joined()
        } catch {
            throw NosskeyError.registrationFailed("公開鍵導出に失敗しました: \(error.localizedDescription)")
        }
    }

    private func zeroize(_ bytes: inout [UInt8]) {
        bytes.withUnsafeMutableBufferPointer { ptr in
            ptr.baseAddress?.initialize(repeating: 0, count: ptr.count)
        }
    }
}

// MARK: - ASAuthorizationControllerDelegate

extension NosskeyManager: ASAuthorizationControllerDelegate {

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            // Registration?
            if #available(iOS 18.0, *),
               let reg = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialRegistration {
                let credId = reg.credentialID
                // `prf` is iOS 18+ only — the #available guards the property access.
                // Registration with `checkForSupport` returns a non-nil `prf` object
                // when the authenticator advertises PRF; the output's `first` may be
                // nil because actual evaluation happens in the assertion phase.
                if reg.prf == nil {
                    self.registrationContinuation?.resume(throwing: NosskeyError.prfUnsupported)
                    self.registrationContinuation = nil
                    return
                }
                let prfOutput: Data? = reg.prf?.first?.withUnsafeBytes { Data($0) }
                self.registrationContinuation?.resume(
                    returning: RegistrationResult(credentialId: credId, prfOutput: prfOutput)
                )
                self.registrationContinuation = nil
                return
            }

            // Assertion?
            if #available(iOS 18.0, *),
               let asr = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialAssertion {
                let credId = asr.credentialID
                guard let prfResult = asr.prf else {
                    self.assertionContinuation?.resume(throwing: NosskeyError.prfMissing)
                    self.assertionContinuation = nil
                    return
                }
                let out = prfResult.first
                let outData = out.withUnsafeBytes { Data($0) }
                self.assertionContinuation?.resume(
                    returning: AssertionResult(credentialId: credId, prfOutput: outData)
                )
                self.assertionContinuation = nil
                return
            }

            // Unknown credential type → fail both pending continuations defensively.
            let err = NosskeyError.registrationFailed("不明な認証情報の種類です")
            self.registrationContinuation?.resume(throwing: err)
            self.registrationContinuation = nil
            self.assertionContinuation?.resume(throwing: err)
            self.assertionContinuation = nil
        }
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let mapped: NosskeyError = {
                if let asErr = error as? ASAuthorizationError {
                    switch asErr.code {
                    case .canceled: return .userCancelled
                    case .failed:   return .registrationFailed(error.localizedDescription)
                    default:        return .registrationFailed(error.localizedDescription)
                    }
                }
                return .registrationFailed(error.localizedDescription)
            }()
            self.registrationContinuation?.resume(throwing: mapped)
            self.registrationContinuation = nil
            let assertionError: NosskeyError
            if case .userCancelled = mapped {
                assertionError = .userCancelled
            } else {
                assertionError = .assertionFailed(error.localizedDescription)
            }
            self.assertionContinuation?.resume(throwing: assertionError)
            self.assertionContinuation = nil
        }
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding

extension NosskeyManager: ASAuthorizationControllerPresentationContextProviding {

    nonisolated func presentationAnchor(
        for controller: ASAuthorizationController
    ) -> ASPresentationAnchor {
        // The system calls this on the main thread. Hop to MainActor explicitly to
        // walk the connected-scenes graph safely.
        MainActor.assumeIsolated {
            for scene in UIApplication.shared.connectedScenes {
                guard let windowScene = scene as? UIWindowScene,
                      scene.activationState == .foregroundActive else { continue }
                if let keyWindow = windowScene.windows.first(where: { $0.isKeyWindow }) {
                    return keyWindow
                }
                if let firstWindow = windowScene.windows.first {
                    return firstWindow
                }
            }
            // Fallback — empty anchor. iOS will display modally over whatever is current.
            return ASPresentationAnchor()
        }
    }
}
