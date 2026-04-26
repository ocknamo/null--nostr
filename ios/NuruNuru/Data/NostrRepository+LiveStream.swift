import Foundation

// MARK: - Live Stream Buffer Store
//
// `NostrRepository` は actor なので extension に stored property を追加できない。
// WebSocket フォールバック時のイベントバッファとタスクをここで管理する。

/// WebSocket ベースのフォールバックストリームの状態を保持する actor。
/// FFI が利用できない場合に `openRelayLiveStream` と組み合わせて使用する。
private actor LiveStreamStore {
    static let shared = LiveStreamStore()

    private var buffers: [String: [NostrEvent]]         = [:]
    private var seenIds: [String: Set<String>]           = [:]
    private var tasks:   [String: Task<Void, Never>]    = [:]

    /// `subId` に対してイベントを追記する（重複 ID は自動的にスキップ）。
    func append(_ subId: String, _ events: [NostrEvent]) {
        var seen = seenIds[subId] ?? Set()
        for event in events where seen.insert(event.id).inserted {
            buffers[subId, default: []].append(event)
        }
        seenIds[subId] = seen
    }

    /// `subId` のバッファを全件取り出してクリアする（drain）。
    /// seenIds は保持して、次回 append 時にも重複排除を継続する。
    func drain(_ subId: String) -> [NostrEvent] {
        let all = buffers[subId] ?? []
        buffers[subId] = []
        return all
    }

    /// `subId` に対応する受信タスクを登録する。
    func setTask(_ subId: String, _ task: Task<Void, Never>) {
        tasks[subId] = task
    }

    /// `subId` のタスクをキャンセルしてバッファを破棄する。
    func remove(_ subId: String) {
        tasks[subId]?.cancel()
        tasks.removeValue(forKey: subId)
        buffers.removeValue(forKey: subId)
        seenIds.removeValue(forKey: subId)
    }
}

// MARK: -

/// ライブストリーミング・単一リレーフェッチ・WebView NIP-07 ブリッジヘルパー。
/// Android の NostrRepositoryLiveStream.kt に相当。
///
/// ライブストリーミングには `URLSessionWebSocketTask` を使用する (Android 版 OkHttp 相当)。
/// WebSocket ベースでライブ更新を提供する。
extension NostrRepository {

    // MARK: - Convenience Fetch (ミニアプリ向け簡略版)

    /// 簡略パラメータで指定 kind のイベントを取得する（ミニアプリ・スケジューラー向け）。
    ///
    /// Android: `NostrRepository.fetchEvents(kinds:authors:limit:dTags:since:)` に対応。
    func fetchEventsByKind(
        kinds:   [Int],
        authors: [String]? = nil,
        limit:   Int       = 10,
        dTags:   [String]? = nil,
        since:   Int64?    = nil
    ) async -> [NostrEvent] {
        var filter = NostrFilter()
        filter.kinds   = kinds
        filter.authors = authors
        filter.limit   = limit
        filter.since   = since
        if let d = dTags, !d.isEmpty {
            filter.tags = ["#d": d]
        }
        return await fetchEvents(filters: [filter], timeoutSeconds: 5.0)
    }

    // MARK: - Relay Timeline (単一リレーからの一括取得)

    /// 指定リレーから Kind 1 を時系列で取得して `ScoredPost` として返す。
    ///
    /// EOSE 受信または 8 秒タイムアウトで終了。
    /// リプライ (e タグ付き) を除外し、ルート投稿のみを返す。
    /// Android: `fetchRelayTimeline()` に対応。
    ///
    /// - Parameters:
    ///   - relayUrl: 接続先リレーの WebSocket URL (例: "wss://yabu.me")。
    ///   - limit:    取得件数上限 (デフォルト 50)。
    /// - Returns: createdAt 降順の `ScoredPost` 配列。
    func fetchRelayTimeline(relayUrl: String, limit: Int = 50) async -> [ScoredPost] {
        let events: [NostrEvent] = await withTaskGroup(of: [NostrEvent].self) { group in
            group.addTask {
                await self.liveWebSocketFetch(
                    relayUrl:  relayUrl,
                    reqFilter: "{\"kinds\":[1],\"limit\":\(limit)}",
                    stopAfterEose: true
                )
            }
            // 8 秒タイムアウト
            group.addTask {
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                return []
            }
            let first = await group.next() ?? []
            group.cancelAll()
            return first
        }

        return events
            .filter { $0.getTagValues("e").isEmpty }   // ルート投稿のみ
            .sorted { $0.createdAt > $1.createdAt }
            .map    { ScoredPost(event: $0) }
    }

    // MARK: - Open Relay Live Stream (連続受信)

    /// 指定リレーに接続し、EOSE 後も接続を維持して新着 Kind 1 を emit し続ける。
    ///
    /// 呼び出し元は返却された `AsyncStream` を `for await` でイテレートし、
    /// 購読を終了するには Task をキャンセルする。
    /// Android: `openRelayLiveStream()` の Flow に相当。
    ///
    /// - Parameter relayUrl: 接続先リレーの WebSocket URL。
    /// - Returns: 新着 `NostrEvent` を emit する `AsyncStream`。
    func openRelayLiveStream(relayUrl: String) -> AsyncStream<NostrEvent> {
        let since = Int64(Date().timeIntervalSince1970)
        return AsyncStream { continuation in
            guard let url = URL(string: relayUrl) else {
                continuation.finish()
                return
            }

            let subId  = "live-\(UUID().uuidString.prefix(8))"
            let reqMsg = "[\"REQ\",\"\(subId)\",{\"kinds\":[1],\"since\":\(since)}]"
            let closeMsg = "[\"CLOSE\",\"\(subId)\"]"

            let wsTask = URLSession.shared.webSocketTask(with: url)
            wsTask.resume()

            // バックグラウンドタスクで受信ループ
            let receiveTask = Task {
                do {
                    try await wsTask.send(.string(reqMsg))
                    while !Task.isCancelled {
                        let msg = try await wsTask.receive()
                        guard case .string(let text) = msg,
                              let event = parseNostrEventMessage(text) else { continue }
                        continuation.yield(event)
                    }
                } catch {
                    // キャンセルまたはネットワークエラー
                    continuation.finish()
                }
            }

            // ストリーム終了時に WebSocket をクリーンアップ
            continuation.onTermination = { _ in
                receiveTask.cancel()
                wsTask.send(.string(closeMsg)) { _ in }
                wsTask.cancel(with: .normalClosure, reason: nil)
            }
        }
    }
    // MARK: - High-level Live Timeline API（TimelineViewModel 向け）

    /// ライブタイムライン購読を開始してサブスクリプション ID を返す。
    ///
    /// FFI が利用可能な場合は Rust エンジン経由。利用不可の場合は
    /// `openRelayLiveStream` を使った WebSocket フォールバックに切り替える。
    ///
    /// - Parameter authors: フォローフィードの場合は pubkey 配列。グローバルは空配列。
    /// - Returns: サブスクリプション ID。取得できない場合は `nil`。
    func startLiveTimeline(authors: [String] = [], relayUrl: String? = nil) async -> String? {
        // WebSocket フォールバック: 指定リレーまたはプライマリリレーへ接続してバッファリング。
        // following フィードでは follow authors のみを通すことで、リレーフィード新着が混入しないようにする。
        let targetRelay = relayUrl ?? getSavedRelayUrls().first
        guard let targetRelay else { return nil }
        let authorSet = Set(authors)
        let shouldFilterByAuthor = !authorSet.isEmpty
        let subId = "ws-\(UUID().uuidString.prefix(8))"
        let stream = openRelayLiveStream(relayUrl: targetRelay)
        let task: Task<Void, Never> = Task { [stream] in
            for await event in stream {
                guard !Task.isCancelled else { break }
                if shouldFilterByAuthor && !authorSet.contains(event.pubkey) {
                    continue
                }
                await LiveStreamStore.shared.append(subId, [event])
            }
        }
        await LiveStreamStore.shared.setTask(subId, task)
        return subId
    }

    /// バッファ済みの新着イベントを取得してクリアする（async・メインループから呼び出し可）。
    ///
    /// - Parameter subId: `startLiveTimeline(authors:)` が返したサブスクリプション ID。
    /// - Returns: 新着 `NostrEvent` 配列。
    func pollNewPosts(subId: String) async -> [NostrEvent] {
        return await LiveStreamStore.shared.drain(subId)
    }

    /// ライブタイムライン購読を停止してリソースを解放する。
    ///
    /// - Parameter subId: `startLiveTimeline(authors:)` が返したサブスクリプション ID。
    func stopLiveTimeline(subId: String) async {
        await LiveStreamStore.shared.remove(subId)
    }
}

// MARK: - Private WebSocket Helpers

extension NostrRepository {

    /// WebSocket に接続して NIP-01 REQ を送信し、イベントを収集して返す。
    ///
    /// `stopAfterEose = true` のとき EOSE 受信後すぐに接続を閉じる。
    /// Task がキャンセルされると接続をクリーンアップして終了する。
    ///
    /// - Parameters:
    ///   - relayUrl:      接続先 WebSocket URL 文字列。
    ///   - reqFilter:     REQ メッセージに埋め込む JSON フィルタ文字列。
    ///   - stopAfterEose: EOSE 受信後に接続を閉じるか。
    /// - Returns: 受信したイベント配列。
    private func liveWebSocketFetch(
        relayUrl:      String,
        reqFilter:     String,
        stopAfterEose: Bool = true
    ) async -> [NostrEvent] {
        guard let url = URL(string: relayUrl) else { return [] }

        let subId    = "rlt-\(UUID().uuidString.prefix(8))"
        let reqMsg   = "[\"REQ\",\"\(subId)\",\(reqFilter)]"
        let closeMsg = "[\"CLOSE\",\"\(subId)\"]"

        let wsTask = URLSession.shared.webSocketTask(with: url)
        wsTask.resume()

        var collected: [NostrEvent] = []

        do {
            try await wsTask.send(.string(reqMsg))

            loop: while !Task.isCancelled {
                let msg = try await wsTask.receive()
                guard case .string(let text) = msg else { continue }

                guard let data  = text.data(using: .utf8),
                      let arr   = try? JSONSerialization.jsonObject(with: data) as? [Any],
                      let msgType = arr.first as? String else { continue }

                switch msgType {
                case "EVENT":
                    guard arr.count >= 3,
                          let obj   = arr[2] as? [String: Any],
                          let eData = try? JSONSerialization.data(withJSONObject: obj),
                          let event = try? JSONDecoder().decode(NostrEvent.self, from: eData)
                    else { continue }
                    collected.append(event)

                case "EOSE":
                    if stopAfterEose { break loop }

                default:
                    break
                }
            }
        } catch {
            // CancellationError または WebSocket エラー — サイレントに終了
        }

        wsTask.send(.string(closeMsg)) { _ in }
        wsTask.cancel(with: .normalClosure, reason: nil)
        return collected
    }

    /// WebSocket メッセージテキストから `NostrEvent` をパースする。
    ///
    /// `["EVENT", <subId>, <eventObject>]` 形式のみ受け付ける。
    private func parseNostrEventMessage(_ text: String) -> NostrEvent? {
        guard let data = text.data(using: .utf8),
              let arr  = try? JSONSerialization.jsonObject(with: data) as? [Any],
              (arr.first as? String) == "EVENT",
              arr.count >= 3,
              let obj    = arr[2] as? [String: Any],
              let eData  = try? JSONSerialization.data(withJSONObject: obj),
              let event  = try? JSONDecoder().decode(NostrEvent.self, from: eData)
        else { return nil }
        return event
    }
}