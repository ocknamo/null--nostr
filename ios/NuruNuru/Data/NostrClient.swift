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

    fileprivate static let noisyRelays: Set<String> = ["relay.nostr.band", "relay.nostr.wirednet.jp"]
    /// Relays that are reachable only opportunistically. They are not auto-reconnected
    /// after failures, and failures place them in a long local cooldown to avoid
    /// creating load for relay operators. Users can still explicitly select them later.
    fileprivate static let operatorFriendlyCooldownRelays: Set<String> = ["relay.nostr.wirednet.jp"]
    fileprivate static let excludedRelays: Set<String> = ["wss://relay.nostr.band"]

    var isEmpty: Bool { connections.isEmpty }

    // MARK: - Connection

    /// Connect (or reconnect) to all given relay URLs.
    /// Already-connected relays are skipped; failed/disconnected ones are reconnected.
    /// Connections are established in parallel for faster startup.
    func connect(relayUrls: [String]) async {
        let relayUrls = relayUrls.filter { !Self.excludedRelays.contains($0) }
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
        guard !Self.excludedRelays.contains(relayUrl) else { return [] }
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
    /// Succeeds as soon as the first relay accepts the event; remaining relays continue in background.
    func publish(event: NostrEvent) async throws {
        try await publish(event: event, waitForAllRelays: false)
    }

    /// Publish with selectable wait policy.
    /// - waitForAllRelays=false: fastest UI path. Return after first relay OK, fan-out keeps running.
    /// - waitForAllRelays=true: legacy behaviour for callers that need full relay completion.
    func publish(event: NostrEvent, waitForAllRelays: Bool) async throws {
        guard !connections.isEmpty else { throw ClientError.notConnected }
        let targets = Array(connections)

        if waitForAllRelays {
            _ = try await publishToRelays(event: event, targets: targets)
            return
        }

        var lastError: Error?
        var failures = 0
        let firstOkRelay = await withTaskGroup(of: (String, Error?).self, returning: String?.self) { group in
            for (url, conn) in targets {
                group.addTask {
                    do {
                        try await self.publishToSingleRelay(event: event, relayUrl: url, conn: conn)
                        return (url, nil)
                    } catch {
                        return (url, error)
                    }
                }
            }

            while let result = await group.next() {
                if let error = result.1 {
                    failures += 1
                    lastError = error
                    continue
                }

                // Important: returning here returns from the task-group closure only.
                // Return the relay URL to the outer function and then return success below.
                group.cancelAll()
                return result.0
            }
            return nil
        }

        if let firstOkRelay {
            AppLogger.log("Relay", "publish first-ok event=\(event.id) relay=\(firstOkRelay) fanout=\(targets.count)")
            Task { await self.publishFanoutBestEffort(event: event, targets: targets, skipRelay: firstOkRelay) }
            return
        }

        AppLogger.log("Relay", "publish failed event=\(event.id) failures=\(failures)/\(targets.count)")
        throw lastError ?? ClientError.notConnected
    }

    private func publishToRelays(event: NostrEvent, targets: [(String, SingleRelayClient)]) async throws -> [String] {
        var lastError: Error?
        var okRelays: [String] = []
        var ngRelays: [String] = []
        await withTaskGroup(of: (String, Bool, Error?).self) { group in
            for (url, conn) in targets {
                group.addTask {
                    do {
                        try await self.publishToSingleRelay(event: event, relayUrl: url, conn: conn)
                        return (url, true, nil)
                    } catch {
                        return (url, false, error)
                    }
                }
            }
            for await r in group {
                if r.1 { okRelays.append(r.0) } else { ngRelays.append(r.0); lastError = r.2 }
            }
        }
        AppLogger.log("Relay", "publish summary event=\(event.id) ok=\(okRelays.count)/\(targets.count) okRelays=\(okRelays) ngRelays=\(ngRelays)")
        if okRelays.isEmpty { throw lastError ?? ClientError.notConnected }
        return okRelays
    }

    private func publishFanoutBestEffort(event: NostrEvent, targets: [(String, SingleRelayClient)], skipRelay: String) async {
        for (url, conn) in targets where url != skipRelay {
            do { try await publishToSingleRelay(event: event, relayUrl: url, conn: conn) }
            catch { AppLogger.log("Relay", "publish background fail relay=\(url) event=\(event.id) err=\(error)") }
        }
    }

    private func publishToSingleRelay(event: NostrEvent, relayUrl: String, conn: SingleRelayClient) async throws {
        do {
            try await conn.publish(event: event)
        } catch {
            let errStr = String(describing: error)
            if errStr.contains("notConnected") {
                try await conn.connect()
                try await conn.publish(event: event)
                AppLogger.log("Relay", "publish retry ok relay=\(relayUrl) event=\(event.id)")
            } else {
                throw error
            }
        }
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

        let isNoisyRelay = NostrClient.noisyRelays.contains(relayURL.host ?? "")
        if !isNoisyRelay {
            AppLogger.log("Relay", "Connecting to \(relayURL.absoluteString)…")
        }

        // Create delegate to detect WebSocket open/close events
        let delegate = WebSocketDelegate(relayHost: relayURL.host ?? relayURL.absoluteString)
        wsDelegate = delegate

        // URLSession with WebSocket-optimized configuration
        // IMPORTANT: Do NOT set timeoutIntervalForResource — its default is 7 days.
        // Setting it to a short value (e.g. 30s) kills long-lived WebSocket connections.
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest  = isNoisyRelay ? 6 : 15
        config.waitsForConnectivity = true
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        urlSession = session
        let task = session.webSocketTask(with: relayURL)
        webSocketTask = task
        task.resume()

        // Wait for actual WebSocket handshake (up to 15s)
        let opened = await delegate.waitForOpen(timeout: isNoisyRelay ? 6.0 : 15.0)
        if opened {
            connectionState = .connected
            consecutiveFailures = 0
            reconnectAttempts   = 0
            AppLogger.log("Relay", "✅ Connected to \(relayURL.host ?? relayURL.absoluteString)")
            Task { await receiveLoop() }
        } else {
            let errorDesc = await delegate.lastError ?? "handshake timeout"
            connectionState = .failed(errorDesc)
            if !isNoisyRelay {
                AppLogger.log("Relay", "❌ Failed to connect to \(relayURL.absoluteString) — \(errorDesc)")
            }
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
            if !NostrClient.noisyRelays.contains(relayURL.host ?? "") {
                AppLogger.log("Relay", "[\(relayURL.host ?? "?")] fetchEvents SKIPPED — state: \(state)")
            }
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

        let host = relayURL.host ?? ""
        let isNoisyRelay = NostrClient.noisyRelays.contains(host)
        let isOperatorFriendlyCooldownRelay = NostrClient.operatorFriendlyCooldownRelays.contains(host)

        let delaySecs: Double
        if isOperatorFriendlyCooldownRelay {
            // Operator-friendly temporary exclusion: after a failure, do not schedule
            // automatic reconnects. Keep the relay locally cooled down for a long window
            // so fan-out fetches do not repeatedly hit an unhealthy relay.
            // 5m → 10m → 20m → 40m → 60m(cap)
            delaySecs = min(300.0 * pow(2.0, Double(max(consecutiveFailures - 1, 0))), 3600.0)
        } else if isNoisyRelay {
            delaySecs = min(Double(30 << min(consecutiveFailures, 3)), 300.0)
        } else {
            // Exponential backoff: 2s → 4s → 8s → 16s → 30s(cap)
            delaySecs = min(Double(2 << min(consecutiveFailures, 4)), 30.0)
        }

        // Cooldown: skip all connect() attempts during the backoff period.
        cooldownUntil = Date().addingTimeInterval(delaySecs)

        guard !isOperatorFriendlyCooldownRelay else {
            // No automatic reconnect for overloaded/flaky community relays. A later
            // explicit user action or future fetch after cooldown may try once again.
            return
        }

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
