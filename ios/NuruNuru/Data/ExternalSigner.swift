import Foundation

/// NIP-46 Remote Signer Client for iOS.
/// Replaces NIP-55 (Amber) which is Android-only.
///
/// Flow:
///   1. Client generates a disposable keypair (`clientKeyPair`)
///   2. User provides a `bunker://` URI or scans a QR code
///   3. Client connects to the relay specified in the URI
///   4. Client sends `connect` request (Kind 24133, NIP-44 encrypted)
///   5. Remote signer responds with approval
///   6. Client calls `get_public_key` to learn the user's actual pubkey
///   7. For signing: `sign_event` request → signed event response
///
/// All NIP-46 messages are Kind 24133, encrypted with NIP-44.
actor ExternalSigner {

    // MARK: - State

    enum State: Equatable {
        case disconnected
        case connecting
        case waitingApproval
        case connected
        case error(String)

        static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.disconnected, .disconnected),
                 (.connecting, .connecting),
                 (.waitingApproval, .waitingApproval),
                 (.connected, .connected):
                return true
            case (.error(let a), .error(let b)):
                return a == b
            default:
                return false
            }
        }
    }

    private(set) var state: State = .disconnected

    // MARK: - Keypair (disposable client keypair for NIP-46 session)

    private var clientPrivateKeyBytes: [UInt8]?
    private var clientPublicKeyHex: String?

    /// Remote signer's pubkey (from bunker:// URI or connect response)
    private var remoteSignerPubkeyHex: String?

    /// The user's actual pubkey (learned via `get_public_key`)
    private(set) var userPubkeyHex: String?

    /// Relay URLs for communicating with the remote signer
    private var relayUrls: [String] = []

    /// Secret from the bunker URI (for authentication)
    private var secret: String?

    /// Dedicated relay client for NIP-46 communication
    private var nip46Client: NostrClient?

    /// Internal signer for NIP-44 encryption with client keypair
    private var clientSigner: InternalSigner?
    private var clientKeyManager: SecureKeyManager?

    /// Pending request continuations keyed by request ID
    private var pendingRequests: [String: CheckedContinuation<NIP46Response, Error>] = [:]

    /// Subscription task for listening to responses
    private var listenTask: Task<Void, Never>?

    // MARK: - Init

    init() {}

    // MARK: - Connect via bunker:// URI

    /// Parse a `bunker://<remote-signer-pubkey>?relay=<url>&secret=<s>` URI and connect.
    /// Returns the user's public key hex on success.
    func connect(uri: String) async throws -> String {
        state = .connecting

        // 1. Parse URI
        let parsed = try parseBunkerURI(uri)
        remoteSignerPubkeyHex = parsed.remotePubkey
        relayUrls = parsed.relays
        secret = parsed.secret

        // 2. Generate disposable client keypair
        let (privBytes, pubBytes) = try NostrKeyUtils.generateKeys()
        clientPrivateKeyBytes = privBytes
        clientPublicKeyHex = NostrKeyUtils.bytesToHex(pubBytes)

        // Set up client signer for NIP-44 encryption
        let km = SecureKeyManager()
        try km.storeKey(privateKeyBytes: privBytes, publicKeyHex: clientPublicKeyHex!)
        clientKeyManager = km
        clientSigner = InternalSigner(keyManager: km)

        // 3. Connect to relay
        let client = NostrClient()
        nip46Client = client
        await client.connect(relayUrls: relayUrls)

        let connState = await client.connectionState
        guard connState == .connected else {
            state = .error(ErrorMessages.connectionFailed)
            throw ExternalSignerError.connectionFailed
        }

        // 4. Start listening for responses
        startListening()

        // 5. Send connect request
        state = .waitingApproval
        let connectParams: [String] = if let s = secret {
            [parsed.remotePubkey, s]
        } else {
            [parsed.remotePubkey]
        }

        let connectResponse = try await sendRequest(method: "connect", params: connectParams)
        guard connectResponse.error == nil else {
            let errMsg = connectResponse.error ?? "接続が拒否されました"
            state = .error(errMsg)
            throw ExternalSignerError.connectionRejected(errMsg)
        }

        // 6. Get user's actual public key
        let pubkeyResponse = try await sendRequest(method: "get_public_key", params: [])
        guard let userPubkey = pubkeyResponse.result, !userPubkey.isEmpty, pubkeyResponse.error == nil else {
            state = .error("公開鍵の取得に失敗しました")
            throw ExternalSignerError.getPublicKeyFailed
        }

        userPubkeyHex = userPubkey
        state = .connected

        AppLogger.log("NIP46", "Connected to remote signer. User pubkey: \(userPubkey.prefix(16))...")
        return userPubkey
    }

    // MARK: - Sign Event

    /// Request the remote signer to sign an event.
    /// Returns the full signed event JSON string.
    /// タイムアウト時は最大2回リトライ（Android フォールバック戦略に対応）。
    func signEvent(kind: Int, content: String, tags: [[String]], createdAt: Int64 = Int64(Date().timeIntervalSince1970)) async throws -> NostrEvent {
        guard state == .connected else {
            throw ExternalSignerError.notConnected
        }

        // Build unsigned event JSON
        let unsignedEvent: [String: Any] = [
            "kind": kind,
            "content": content,
            "tags": tags,
            "created_at": createdAt
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: unsignedEvent),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw ExternalSignerError.serializationFailed
        }

        // リトライ付きリクエスト（最大3回試行）
        var lastError: Error?
        for attempt in 0..<3 {
            do {
                let response = try await sendRequest(method: "sign_event", params: [jsonString])

                guard let resultStr = response.result, response.error == nil else {
                    let errMsg = response.error ?? ErrorMessages.bunkerSigningFailed
                    throw ExternalSignerError.signingFailed(errMsg)
                }

                // Parse the signed event from the result
                guard let resultData = resultStr.data(using: .utf8),
                      let signedEvent = try? JSONDecoder().decode(NostrEvent.self, from: resultData) else {
                    throw ExternalSignerError.invalidResponse
                }

                return signedEvent
            } catch ExternalSignerError.timeout {
                lastError = ExternalSignerError.timeout
                AppLogger.log("NIP46", "sign_event timeout (attempt \(attempt + 1)/3)")
                if attempt < 2 {
                    // 指数バックオフ: 1s, 2s
                    try? await Task.sleep(nanoseconds: UInt64((attempt + 1)) * 1_000_000_000)
                }
            } catch {
                throw error
            }
        }

        throw lastError ?? ExternalSignerError.timeout
    }

    // MARK: - Disconnect

    func disconnect() async {
        listenTask?.cancel()
        listenTask = nil
        if let client = nip46Client {
            await client.disconnect()
        }
        nip46Client = nil

        // Cancel pending requests
        for (_, continuation) in pendingRequests {
            continuation.resume(throwing: ExternalSignerError.disconnected)
        }
        pendingRequests.removeAll()

        // Zero client key material
        clientKeyManager?.deleteAll()
        clientKeyManager = nil
        clientSigner = nil
        if var privBytes = clientPrivateKeyBytes {
            privBytes.withUnsafeMutableBufferPointer { ptr in
                ptr.baseAddress?.initialize(repeating: 0, count: ptr.count)
            }
        }
        clientPrivateKeyBytes = nil
        clientPublicKeyHex = nil
        remoteSignerPubkeyHex = nil
        userPubkeyHex = nil
        secret = nil

        state = .disconnected
        AppLogger.log("NIP46", "Disconnected from remote signer")
    }

    // MARK: - Private: URI Parsing

    private struct BunkerURIComponents {
        let remotePubkey: String
        let relays: [String]
        let secret: String?
    }

    private func parseBunkerURI(_ uri: String) throws -> BunkerURIComponents {
        // bunker://<remote-signer-pubkey>?relay=wss://...&secret=xxx
        let trimmed = uri.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmed.hasPrefix("bunker://") else {
            throw ExternalSignerError.invalidURI("bunker:// で始まるURIが必要です")
        }

        // Extract pubkey (host portion)
        let withoutScheme = String(trimmed.dropFirst("bunker://".count))
        let parts = withoutScheme.split(separator: "?", maxSplits: 1)
        let pubkey = String(parts[0])

        guard pubkey.count == 64, NostrKeyUtils.hexToBytes(pubkey) != nil else {
            throw ExternalSignerError.invalidURI("公開鍵の形式が正しくありません")
        }

        // Parse query parameters
        var relays: [String] = []
        var secret: String?

        if parts.count > 1 {
            let queryString = String(parts[1])
            let queryItems = queryString.split(separator: "&")
            for item in queryItems {
                let kv = item.split(separator: "=", maxSplits: 1)
                guard kv.count == 2 else { continue }
                let key = String(kv[0])
                let value = String(kv[1]).removingPercentEncoding ?? String(kv[1])
                switch key {
                case "relay":
                    relays.append(value)
                case "secret":
                    secret = value
                default:
                    break
                }
            }
        }

        guard !relays.isEmpty else {
            throw ExternalSignerError.invalidURI("リレーURLが指定されていません")
        }

        return BunkerURIComponents(remotePubkey: pubkey, relays: relays, secret: secret)
    }

    // MARK: - Private: NIP-46 Request/Response

    private func sendRequest(method: String, params: [String]) async throws -> NIP46Response {
        guard let signer = clientSigner,
              let clientPubHex = clientPublicKeyHex,
              let remotePubHex = remoteSignerPubkeyHex,
              let client = nip46Client else {
            throw ExternalSignerError.notConnected
        }

        let requestId = UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "").prefix(16)
        let requestIdStr = String(requestId)

        // Build JSON-RPC request
        let rpcRequest: [String: Any] = [
            "id": requestIdStr,
            "method": method,
            "params": params
        ]

        guard let rpcData = try? JSONSerialization.data(withJSONObject: rpcRequest),
              let rpcString = String(data: rpcData, encoding: .utf8) else {
            throw ExternalSignerError.serializationFailed
        }

        // NIP-44 encrypt to remote signer
        guard let encryptedContent = signer.nip44Encrypt(recipientPubkeyHex: remotePubHex, plaintext: rpcString) else {
            throw ExternalSignerError.encryptionFailed
        }

        // Build Kind 24133 event
        let requestEvent = try signer.signEvent(
            kind: 24133,
            tags: [["p", remotePubHex]],
            content: encryptedContent
        )

        // Publish to relay
        try await client.publish(event: requestEvent)

        AppLogger.log("NIP46", "Sent \(method) request (id: \(requestIdStr))")

        // Wait for response with timeout
        return try await withCheckedThrowingContinuation { continuation in
            pendingRequests[requestIdStr] = continuation

            // Timeout after 60 seconds
            Task {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                if let pending = pendingRequests.removeValue(forKey: requestIdStr) {
                    pending.resume(throwing: ExternalSignerError.timeout)
                }
            }
        }
    }

    // MARK: - Private: Listen for Responses

    private func startListening() {
        listenTask?.cancel()
        listenTask = Task { [weak self] in
            guard let self else { return }
            await self.listenLoop()
        }
    }

    private func listenLoop() async {
        guard let client = nip46Client,
              let clientPubHex = clientPublicKeyHex else { return }

        // Subscribe to Kind 24133 events p-tagged to our client pubkey
        let filter = NostrFilter(
            kinds: [24133],
            since: Int64(Date().timeIntervalSince1970) - 5,
            tags: ["#p": [clientPubHex]]
        )

        let events = await client.fetchEvents(filters: [filter], timeoutSeconds: 300)
        for event in events {
            await handleResponseEvent(event)
        }
    }

    private func handleResponseEvent(_ event: NostrEvent) {
        guard event.kind == 24133,
              let signer = clientSigner else { return }

        // Decrypt NIP-44 content
        guard let decrypted = signer.nip44Decrypt(senderPubkeyHex: event.pubkey, ciphertext: event.content) else {
            AppLogger.log("NIP46", "Failed to decrypt response from \(event.pubkey.prefix(16))...")
            return
        }

        // Parse JSON-RPC response
        guard let data = decrypted.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let responseId = json["id"] as? String else {
            AppLogger.log("NIP46", "Invalid response format")
            return
        }

        let response = NIP46Response(
            id: responseId,
            result: json["result"] as? String,
            error: json["error"] as? String
        )

        // If this is from the connect flow, update remote signer pubkey
        if remoteSignerPubkeyHex == nil || remoteSignerPubkeyHex?.isEmpty == true {
            remoteSignerPubkeyHex = event.pubkey
        }

        AppLogger.log("NIP46", "Received response for request \(responseId)")

        // Resume pending continuation
        if let continuation = pendingRequests.removeValue(forKey: responseId) {
            continuation.resume(returning: response)
        }
    }

    // MARK: - Types

    struct NIP46Response {
        let id: String
        let result: String?
        let error: String?
    }

    enum ExternalSignerError: LocalizedError {
        case invalidURI(String)
        case connectionFailed
        case connectionRejected(String)
        case getPublicKeyFailed
        case notConnected
        case disconnected
        case serializationFailed
        case encryptionFailed
        case signingFailed(String)
        case invalidResponse
        case timeout

        var errorDescription: String? {
            switch self {
            case .invalidURI(let msg):         return "無効なURI: \(msg)"
            case .connectionFailed:            return ErrorMessages.connectionFailed
            case .connectionRejected(let msg): return "接続が拒否されました: \(msg)"
            case .getPublicKeyFailed:          return "公開鍵の取得に失敗しました"
            case .notConnected:                return "リモートサイナーに接続されていません"
            case .disconnected:                return "リモートサイナーから切断されました"
            case .serializationFailed:         return "リクエストのシリアライズに失敗しました"
            case .encryptionFailed:            return "NIP-44暗号化に失敗しました"
            case .signingFailed(let msg):      return "署名に失敗しました: \(msg)"
            case .invalidResponse:             return "リモートサイナーからの応答を解析できません"
            case .timeout:                     return ErrorMessages.requestTimeout
            }
        }
    }
}
