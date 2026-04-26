import Foundation

// MARK: - RelayMessage

enum RelayMessage {
    case event(subscriptionId: String, event: NostrEvent)
    case eose(subscriptionId: String)
    case notice(String)
    case closed(subscriptionId: String, message: String)
    case authChallenge(String)
}

// MARK: - NostrClient (multi-relay coordinator)

/// Multi-relay WebSocket coordinator.
/// Fans out fetches to all connected relays and deduplicates by event ID.
/// Mirrors Android: multiple relay connections managed in parallel.
actor NostrClient {

    // MARK: - Types

    enum ClientError: Error {
        case notConnected
        case sendFailed(Error)
        case rateLimited
        case invalidMessage
        case publishRejected(String)
        case publishAckTimeout
    }

    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
        case failed(String)

        static func == (lhs: ConnectionState, rhs: ConnectionState) -> Bool {
            switch (lhs, rhs) {
            case (.disconnected, .disconnected),
                 (.connecting, .connecting),
                 (.connected, .connected):
                return true
            case (.failed(let a), .failed(let b)):
                return a == b
            default:
                return false
            }
        }
    }

    // MARK: - Properties

    private var connections: [String: SingleRelayClient] = [:]

    var isEmpty: Bool { connections.isEmpty }

    // MARK: - Connection

    /// Connect (or reconnect) to all given relay URLs.
    /// Already-connected relays are skipped; failed/disconnected ones are reconnected.
    /// Connections are established in parallel for faster startup.
    func connect(relayUrls: [String]) async {
        AppLogger.log("Relay", "Connecting to \(relayUrls.count) relays: \(relayUrls.joined(separator: ", "))")

        // Prepare connections map first (actor-isolated)
        var toConnect: [SingleRelayClient] = []
        var toWait:    [SingleRelayClient] = []  // .connecting 状態のものは完了待ち
        for urlStr in relayUrls {
            if let existing = connections[urlStr] {
                let state = await existing.connectionState
                if state == .connected { continue }
                if state == .connecting { toWait.append(existing); continue }
                toConnect.append(existing)
                continue
            }
            guard let url = URL(string: urlStr) else { continue }
            let conn = SingleRelayClient(relayURL: url)
            connections[urlStr] = conn
            toConnect.append(conn)
        }

        // Connect all in parallel (each waits for handshake independently)
        await withTaskGroup(of: Void.self) { group in
            for conn in toConnect {
                group.addTask { await conn.connect() }
            }
            // .connecting 状態の接続はハンドシェイク完了を待機
            for conn in toWait {
                group.addTask {
                    for _ in 0..<30 { // max 15s
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        let s = await conn.connectionState
                        if s != .connecting { break }
                    }
                }
            }
        }

        // Log final connection state
        var connectedCount = 0
        for conn in connections.values {
            let state = await conn.connectionState
            if state == .connected { connectedCount += 1 }
        }
        AppLogger.log("Relay", "✅ \(connectedCount)/\(connections.count) relays connected")
    }

    /// Disconnect all relays and remove connections.
    func disconnect() async {
        for conn in connections.values { await conn.disconnect() }
        connections.removeAll()
    }

    /// Per-relay connection states — used by relay settings UI.
    func perRelayStates() async -> [String: ConnectionState] {
        var result: [String: ConnectionState] = [:]
        for (url, conn) in connections {
            result[url] = await conn.connectionState
        }
        return result
    }

    /// Aggregate connection state: connected if any relay is connected.
    var connectionState: ConnectionState {
        get async {
            var anyConnecting = false
            for conn in connections.values {
                let state = await conn.connectionState
                if state == .connected  { return .connected }
                if state == .connecting { anyConnecting = true }
            }
            if connections.isEmpty { return .disconnected }
            return anyConnecting ? .connecting : .failed(ErrorMessages.statusDisconnected)
        }
    }

    // MARK: - Fetch (fan-out + dedup)

    /// Fetch events from ALL connected relays in parallel; deduplicate by event ID.
    func fetchEvents(
        filters: [NostrFilter],
        timeoutSeconds: Double = 8.0
    ) async -> [NostrEvent] {
        guard !connections.isEmpty else { return [] }

        var allEvents: [NostrEvent] = []
        await withTaskGroup(of: [NostrEvent].self) { group in
            for conn in connections.values {
                group.addTask {
                    await conn.fetchEvents(filters: filters, timeoutSeconds: timeoutSeconds)
                }
            }
            for await events in group {
                allEvents += events
            }
        }

        // Deduplicate — fastest relay wins (first occurrence kept)
        var seen = Set<String>()
        return allEvents.filter { seen.insert($0.id).inserted }
    }

    /// Fetch from a specific relay URL (relay tab / targeted fetch).
    /// Re-uses existing connection if available; otherwise opens a temporary one.
    /// 切断済みの場合は再接続を試みてからフェッチする。
    func fetchEventsFromRelay(
        _ relayUrl: String,
        filters: [NostrFilter],
        timeoutSeconds: Double = 8.0
    ) async -> [NostrEvent] {
        if let conn = connections[relayUrl] {
            var state = await conn.connectionState

            // .connecting の場合: ハンドシェイク完了を最大 10 秒待機
            if state == .connecting {
                for _ in 0..<20 { // 0.5s × 20 = max 10s
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    state = await conn.connectionState
                    if state != .connecting { break }
                }
            }

            // 接続失敗中: 1回だけ再接続を試みる（cooldown があればスキップされる）
            if state != .connected {
                await conn.connect()
                state = await conn.connectionState
            }

            guard state == .connected else { return [] }

            return await conn.fetchEvents(filters: filters, timeoutSeconds: timeoutSeconds)
        }
        guard let url = URL(string: relayUrl) else { return [] }
        let conn = SingleRelayClient(relayURL: url)
        connections[relayUrl] = conn
        await conn.connect()
        let state = await conn.connectionState
        guard state == .connected else { return [] }
        return await conn.fetchEvents(filters: filters, timeoutSeconds: timeoutSeconds)
    }

    // MARK: - Publish (fan-out to all relays)

    /// Publish an event to all connected relays.
    /// Succeeds if at least one relay accepts the event.
    func publish(event: NostrEvent) async throws {
        guard !connections.isEmpty else { throw ClientError.notConnected }
        var lastError: Error?
        var succeeded = false
        var okRelays: [String] = []
        var ngRelays: [String] = []

        for (url, conn) in connections {
            do {
                try await conn.publish(event: event)
                succeeded = true
                okRelays.append(url)
            } catch {
                // Retry once after reconnect when relay is temporarily disconnected.
                let errStr = String(describing: error)
                if errStr.contains("notConnected") {
                    do {
                        try await conn.connect()
                        try await conn.publish(event: event)
                        succeeded = true
                        okRelays.append(url)
                        AppLogger.log("Relay", "publish retry ok relay=\(url) event=\(event.id)")
                        continue
                    } catch {
                        lastError = error
                        ngRelays.append(url)
                        AppLogger.log("Relay", "publish retry fail relay=\(url) event=\(event.id) err=\(error)")
                        continue
                    }
                }

                lastError = error
                ngRelays.append(url)
                AppLogger.log("Relay", "publish fail relay=\(url) event=\(event.id) err=\(error)")
            }
        }

        AppLogger.log("Relay", "publish summary event=\(event.id) ok=\(okRelays.count)/\(connections.count) okRelays=\(okRelays) ngRelays=\(ngRelays)")

        if !succeeded { throw lastError ?? ClientError.notConnected }
    }

    /// Publish a fully signed raw event JSON to a subset of relays.
    /// Used by MLS Kind-445 / Welcome events generated and signed by Rust MDK.
    /// If no relay subset is provided, falls back to publishing to all connected relays.
    func publishRawEventJSON(_ rawEventJSON: String, to relays: [String]) async throws {
        guard let data = rawEventJSON.data(using: .utf8) else {
            throw ClientError.invalidMessage
        }
        let event: NostrEvent
        do {
            event = try JSONDecoder().decode(NostrEvent.self, from: data)
        } catch {
            throw ClientError.invalidMessage
        }

        let targetRelays = relays.isEmpty ? Array(connections.keys) : relays
        guard !targetRelays.isEmpty else { throw ClientError.notConnected }

        let connectedTargets: [(String, SingleRelayClient)] = targetRelays.compactMap { relay in
            guard let conn = connections[relay] else { return nil }
            return (relay, conn)
        }

        var ngRelays: [String] = targetRelays.filter { relay in connections[relay] == nil }
        for relay in ngRelays {
            AppLogger.log("Relay", "publishRawEventJSON missing connection relay=\(relay) event=\(event.id)")
        }

        let results = await withTaskGroup(of: (relay: String, ok: Bool, err: String?).self) { group in
            for (relay, conn) in connectedTargets {
                group.addTask {
                    do {
                        try await conn.publish(event: event)
                        return (relay, true, nil)
                    } catch {
                        let errStr = String(describing: error)
                        if errStr.contains("notConnected") {
                            do {
                                await conn.connect()
                                try await conn.publish(event: event)
                                AppLogger.log("Relay", "publishRawEventJSON retry ok relay=\(relay) event=\(event.id)")
                                return (relay, true, nil)
                            } catch {
                                return (relay, false, String(describing: error))
                            }
                        }
                        return (relay, false, errStr)
                    }
                }
            }

            var collected: [(relay: String, ok: Bool, err: String?)] = []
            for await r in group {
                collected.append(r)
            }
            return collected
        }

        var okRelays: [String] = []
        var lastError: Error?
        for r in results {
            if r.ok {
                okRelays.append(r.relay)
            } else {
                ngRelays.append(r.relay)
                let err = r.err ?? "unknown"
                lastError = ClientError.publishRejected(err)
                AppLogger.log("Relay", "publishRawEventJSON fail relay=\(r.relay) event=\(event.id) err=\(err)")
            }
        }

        AppLogger.log("Relay", "publishRawEventJSON summary event=\(event.id) ok=\(okRelays.count)/\(targetRelays.count) okRelays=\(okRelays) ngRelays=\(ngRelays)")

        if okRelays.isEmpty { throw lastError ?? ClientError.notConnected }
    }

}

// MARK: - SingleRelayClient (internal)

/// Single WebSocket relay connection with subscription management and rate limiting.
/// Internal to NostrClient — use NostrClient for all external access.
private actor SingleRelayClient {

    // MARK: - Subscription

    private struct Subscription {
        let id:           String
        let filters:      [NostrFilter]
        let continuation: AsyncStream<RelayMessage>.Continuation
    }

    private struct PublishWaiterKey: Hashable {
        let eventId: String
    }

    // MARK: - Properties

    let relayURL: URL
    private var webSocketTask:    URLSessionWebSocketTask?
    private var wsDelegate:       WebSocketDelegate?
    private var urlSession:       URLSession?
    private var subscriptions:    [String: Subscription] = [:]
    private var publishWaiters: [PublishWaiterKey: [CheckedContinuation<(Bool, String), Never>]] = [:]
    private(set) var connectionState: NostrClient.ConnectionState = .disconnected

    // Token bucket rate limiting
    private var requestTokens:    Double = Double(RateLimit.burstSize)
    private var lastTokenRefill:  Date   = Date()

    // Failure tracking
    private var consecutiveFailures = 0
    private var cooldownUntil: Date?

    // Auto-reconnect
    private var reconnectAttempts = 0
    private var reconnectTask: Task<Void, Never>?

    private let decoder = JSONDecoder()
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()

    // MARK: - Init

    init(relayURL: URL) {
        self.relayURL = relayURL
    }

    // MARK: - Connection

    func connect() async {
        guard connectionState != .connected, connectionState != .connecting else { return }
        if let until = cooldownUntil, Date() < until {
            connectionState = .failed(ErrorMessages.statusReconnecting)
            return
        }
        reconnectTask?.cancel()
        reconnectTask = nil
        connectionState = .connecting

        AppLogger.log("Relay", "Connecting to \(relayURL.absoluteString)…")

        // Create delegate to detect WebSocket open/close events
        let delegate = WebSocketDelegate(relayHost: relayURL.host ?? relayURL.absoluteString)
        wsDelegate = delegate

        // URLSession with WebSocket-optimized configuration
        // IMPORTANT: Do NOT set timeoutIntervalForResource — its default is 7 days.
        // Setting it to a short value (e.g. 30s) kills long-lived WebSocket connections.
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest  = 15
        config.waitsForConnectivity = true
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        urlSession = session
        let task = session.webSocketTask(with: relayURL)
        webSocketTask = task
        task.resume()

        // Wait for actual WebSocket handshake (up to 15s)
        let opened = await delegate.waitForOpen(timeout: 15.0)
        if opened {
            connectionState = .connected
            consecutiveFailures = 0
            reconnectAttempts   = 0
            AppLogger.log("Relay", "✅ Connected to \(relayURL.host ?? relayURL.absoluteString)")
            Task { await receiveLoop() }
        } else {
            let errorDesc = await delegate.lastError ?? "handshake timeout"
            connectionState = .failed(errorDesc)
            AppLogger.log("Relay", "❌ Failed to connect to \(relayURL.absoluteString) — \(errorDesc)")
            scheduleReconnect()
        }
    }

    func disconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        wsDelegate = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        connectionState = .disconnected
        for sub in subscriptions.values { sub.continuation.finish() }
        subscriptions.removeAll()
        AppLogger.log("Relay", "Disconnected from \(relayURL.host ?? relayURL.absoluteString)")
    }

    // MARK: - Fetch (convenience)

    /// Subscribe, collect events until EOSE or timeout, then unsubscribe.
    /// Uses a concurrent timeout task to force-close the stream if the relay hangs.
    func fetchEvents(filters: [NostrFilter], timeoutSeconds: Double) async -> [NostrEvent] {
        var state = connectionState

        // connecting 中は少し待ってから取得（起動直後 0 件化を防ぐ）
        if state == .connecting {
            for _ in 0..<20 { // up to 10s
                try? await Task.sleep(nanoseconds: 500_000_000)
                state = connectionState
                if state != .connecting { break }
            }
        }

        // 切断/失敗時は1回だけ再接続を試みる
        if state != .connected {
            await connect()
            state = connectionState
        }

        guard state == .connected else {
            AppLogger.log("Relay", "[\(relayURL.host ?? "?")] fetchEvents SKIPPED — state: \(state)")
            return []
        }
        var events: [NostrEvent] = []
        let subId = "f" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(15).lowercased()
        guard let stream = try? await subscribe(filters: filters, id: subId) else {
            AppLogger.log("Relay", "[\(relayURL.host ?? "?")] fetchEvents subscribe FAILED for \(subId)")
            return []
        }

        defer { Task { try? await unsubscribe(id: subId) } }

        // Concurrent timeout: force-close the stream if relay hangs (no EOSE, no error)
        let timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.forceCloseSubscription(id: subId)
        }
        defer { timeoutTask.cancel() }

        for await message in stream {
            switch message {
            case .event(_, let event): events.append(event)
            case .eose:                return events
            default:                   break
            }
        }
        return events
    }

    /// Force-finish a subscription's continuation (called by timeout task).
    private func forceCloseSubscription(id: String) {
        subscriptions[id]?.continuation.finish()
        subscriptions.removeValue(forKey: id)
    }

    // MARK: - Subscribe / Unsubscribe

    func subscribe(filters: [NostrFilter], id: String) async throws -> AsyncStream<RelayMessage> {
        guard connectionState == .connected else { throw NostrClient.ClientError.notConnected }
        var continuation: AsyncStream<RelayMessage>.Continuation!
        let stream = AsyncStream<RelayMessage> { cont in continuation = cont }
        subscriptions[id] = Subscription(id: id, filters: filters, continuation: continuation)
        try await sendREQ(id: id, filters: filters)
        return stream
    }

    func unsubscribe(id: String) async throws {
        subscriptions[id]?.continuation.finish()
        subscriptions.removeValue(forKey: id)
        try await sendCLOSE(id: id)
    }


    // ---- Recovered minimal methods ----
    func publish(event: NostrEvent) async throws {
        guard connectionState == .connected else { throw NostrClient.ClientError.notConnected }
        let encoder = JSONEncoder()
        let eventData = try encoder.encode(event)
        let eventAny = try JSONSerialization.jsonObject(with: eventData)
        let msgData = try JSONSerialization.data(withJSONObject: ["EVENT", eventAny])
        guard let text = String(data: msgData, encoding: .utf8) else {
            throw NostrClient.ClientError.invalidMessage
        }
        try await webSocketTask?.send(.string(text))

        // MIP-02 timing safety: caller can treat publish completion as relay-level acknowledgement.
        let (ok, message) = await waitForPublishAck(eventId: event.id, timeoutSeconds: 8.0)
        if !ok && message == "timeout:publish_ack" {
            throw NostrClient.ClientError.publishAckTimeout
        }
        guard ok else {
            throw NostrClient.ClientError.publishRejected(message)
        }
    }

    private func waitForPublishAck(eventId: String, timeoutSeconds: Double) async -> (Bool, String) {
        let key = PublishWaiterKey(eventId: eventId)
        return await withCheckedContinuation { continuation in
            publishWaiters[key, default: []].append(continuation)

            Task { [weak self] in
                guard let self else { return }
                try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                await self.timeoutPublishWaiter(key: key)
            }
        }
    }

    private func timeoutPublishWaiter(key: PublishWaiterKey) {
        guard let waiters = publishWaiters.removeValue(forKey: key), !waiters.isEmpty else { return }
        for w in waiters {
            w.resume(returning: (false, "timeout:publish_ack"))
        }
    }

    private func sendREQ(id: String, filters: [NostrFilter]) async throws {
        let enc = JSONEncoder()
        let filterAny: [Any] = try filters.map { f in
            let d = try enc.encode(f)
            return try JSONSerialization.jsonObject(with: d)
        }
        let payload: [Any] = ["REQ", id] + filterAny
        let data = try JSONSerialization.data(withJSONObject: payload)
        guard let text = String(data: data, encoding: .utf8) else { throw NostrClient.ClientError.invalidMessage }
        try await webSocketTask?.send(.string(text))
    }

    private func sendCLOSE(id: String) async throws {
        let data = try JSONSerialization.data(withJSONObject: ["CLOSE", id])
        guard let text = String(data: data, encoding: .utf8) else { throw NostrClient.ClientError.invalidMessage }
        try await webSocketTask?.send(.string(text))
    }

    private func receiveLoop() async {
        guard let task = webSocketTask else { return }
        while connectionState == .connected {
            do {
                let msg = try await task.receive()
                switch msg {
                case .string(let text):
                    guard let data = text.data(using: .utf8),
                          let arr = try JSONSerialization.jsonObject(with: data) as? [Any],
                          let type = arr.first as? String else { continue }

                    switch type {
                    case "EVENT":
                        guard arr.count >= 3,
                              let subId = arr[1] as? String else { continue }
                        let eventObj = arr[2]
                        let eventData = try JSONSerialization.data(withJSONObject: eventObj)
                        if let event = try? JSONDecoder().decode(NostrEvent.self, from: eventData) {
                            subscriptions[subId]?.continuation.yield(.event(subscriptionId: subId, event: event))
                        }
                    case "EOSE":
                        guard arr.count >= 2, let subId = arr[1] as? String else { continue }
                        subscriptions[subId]?.continuation.yield(.eose(subscriptionId: subId))
                    case "OK":
                        guard arr.count >= 4,
                              let eventId = arr[1] as? String,
                              let ok = arr[2] as? Bool,
                              let message = arr[3] as? String else { continue }
                        for key in publishWaiters.keys {
                            if key.eventId == eventId {
                                let waiters = publishWaiters.removeValue(forKey: key) ?? []
                                for w in waiters { w.resume(returning: (ok, message)) }
                            }
                        }
                    case "NOTICE":
                        break
                    default:
                        break
                    }
                default:
                    break
                }
            } catch {
                connectionState = .failed(String(describing: error))
                scheduleReconnect()
                break
            }
        }
    }

    private func scheduleReconnect() {
        consecutiveFailures += 1
        reconnectTask?.cancel()

        // Exponential backoff: 2s → 4s → 8s → 16s → 30s(cap)
        let delaySecs = min(Double(2 << min(consecutiveFailures, 4)), 30.0)

        // Cooldown: skip all connect() attempts during the backoff period
        cooldownUntil = Date().addingTimeInterval(delaySecs)

        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delaySecs * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            await self.connect()
        }
    }
}

private final class WebSocketDelegate: NSObject, URLSessionWebSocketDelegate {
    let relayHost: String
    private(set) var didOpen = false
    private(set) var lastError: String?
    private var openContinuation: CheckedContinuation<Bool, Never>?

    init(relayHost: String) {
        self.relayHost = relayHost
    }

    func waitForOpen(timeout: TimeInterval) async -> Bool {
        if didOpen { return true }
        return await withCheckedContinuation { cont in
            openContinuation = cont
            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                if !self.didOpen {
                    self.lastError = self.lastError ?? "handshake timeout"
                    self.openContinuation?.resume(returning: false)
                    self.openContinuation = nil
                }
            }
        }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        didOpen = true
        openContinuation?.resume(returning: true)
        openContinuation = nil
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        didOpen = false
        lastError = "closed: (closeCode.rawValue)"
    }
}
