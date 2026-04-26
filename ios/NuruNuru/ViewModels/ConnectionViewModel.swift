import Foundation
import Network
import Observation

/// リレー接続とネットワーク到達可能性の監視ViewModel。
/// Mirrors Android ConnectionViewModel.
@Observable
@MainActor
final class ConnectionViewModel {

    // MARK: - State

    var isOnline:         Bool                       = true
    var connectionState:  NostrClient.ConnectionState = .connecting
    var statusMessage:    String                     = "接続中"
    /// Android: 初期値 isFullyConnected = true（楽観的）。
    /// 起動直後のリレー接続完了前に「切断中」バナーが出るのを防止する。
    var isFullyConnected: Bool                       = true
    var wasOffline:       Bool                       = false
    var activeRelayUrl:   String                     = ""
    /// 初回接続が完了したかどうか。完了前は「切断中」バナーを表示しない。
    private var hasConnectedOnce: Bool               = false

    // MARK: - Dependencies

    let repository: NostrRepository

    // @Observable マクロの観測対象から除外する（UI に反映不要な内部実装）。
    // @ObservationIgnored により macro 展開されないため、nonisolated(unsafe) の
    // 「has no effect」警告も出なくなる。クラスは @MainActor なので MainActor 上で
    // 安全にアクセスされる。
    @ObservationIgnored private var monitor:  NWPathMonitor?
    @ObservationIgnored private var pollTask: Task<Void, Never>?

    // MARK: - Init

    init(repository: NostrRepository) {
        self.repository = repository
        Task { await startMonitoring() }
    }

    deinit {
        pollTask?.cancel()
        monitor?.cancel()
    }

    // MARK: - Monitoring

    func startMonitoring() async {
        activeRelayUrl = await repository.getSavedRelayUrls().first ?? "wss://yabu.me"

        let monitor = NWPathMonitor()
        self.monitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let nowOnline = path.status == .satisfied
                if !self.isOnline && nowOnline {
                    self.wasOffline = true
                    Task { await self.reconnect() }
                }
                self.isOnline = nowOnline
                self.updateStatus()
            }
        }
        monitor.start(queue: DispatchQueue(label: "io.nurunuru.netmon", qos: .utility))

        await refreshHealth()

        // 60秒ごとに定期チェック
        pollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(
                    Double(Connection.healthCheckIntervalMs) / 1000.0
                ))
                await refreshHealth()
            }
        }
    }

    // MARK: - Actions

    func refreshHealth() async {
        let state = await repository.connectionState
        connectionState = state

        if state == .connected {
            hasConnectedOnce = true
        }

        // Android 同様: 初回接続前は楽観的に true を維持してバナーを出さない。
        // 初回接続完了後は実際の接続状態を反映する。
        if hasConnectedOnce {
            isFullyConnected = (state == .connected) && isOnline
        } else {
            // 初回接続完了前: isOnline ならバナーを出さない（Android と同じ挙動）
            isFullyConnected = isOnline
        }
        wasOffline = false
        updateStatus()
    }

    func reconnect() async {
        connectionState = .connecting
        updateStatus()
        await repository.connect()
        hasConnectedOnce = true
        await refreshHealth()
    }

    // MARK: - Private

    private func updateStatus() {
        guard isOnline else { statusMessage = "オフライン"; return }
        switch connectionState {
        case .connected:    statusMessage = "接続中"
        case .connecting:   statusMessage = "再接続中..."
        case .disconnected: statusMessage = "切断中"
        case .failed:       statusMessage = "接続に問題があります"
        }
    }
}
