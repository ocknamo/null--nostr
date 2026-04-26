import Foundation

/// Kind 31928 Chronostr スケジュール調整のリポジトリ操作。
/// Android SchedulerApp.kt の NostrRepository 呼び出しに対応。
extension NostrRepository {

    // MARK: - Fetch

    /// Kind 31928 スケジュールイベントを RSVP 票数付きで取得する。
    ///
    /// 処理フロー:
    /// 1. Kind 31928 イベントをフェッチ
    /// 2. 各イベントの `#a` タグで Kind 31925 RSVP を一括フェッチ
    /// 3. 候補日ごとに投票者 pubkey をカウントして `CalendarEvent` を構築
    func fetchCalendarEvents(pubkey: String) async -> [CalendarEvent] {
        var eventFilter = NostrFilter()
        eventFilter.authors = [pubkey]
        eventFilter.kinds   = [NostrKind.chronostrEvent]
        eventFilter.limit   = 50

        let rawEvents = await fetchEvents(filters: [eventFilter], timeoutSeconds: 5.0)
        guard !rawEvents.isEmpty else { return [] }

        // RSVP を #a タグで一括取得
        let aTags = rawEvents.map {
            "31928:\($0.pubkey):\($0.getTagValue("d") ?? $0.id)"
        }
        var rsvpFilter = NostrFilter()
        rsvpFilter.kinds = [NostrKind.calendarRsvp]
        rsvpFilter.tags  = ["#a": aTags]
        rsvpFilter.limit = 500

        let rsvps = await fetchEvents(filters: [rsvpFilter], timeoutSeconds: 5.0)

        // RSVP を a タグでグループ化
        var rsvpsByATag: [String: [NostrEvent]] = [:]
        for rsvp in rsvps {
            guard let aTag = rsvp.getTagValue("a") else { continue }
            rsvpsByATag[aTag, default: []].append(rsvp)
        }

        return rawEvents.map { ev in
            let dTag       = ev.getTagValue("d") ?? ev.id
            let aTag       = "31928:\(ev.pubkey):\(dTag)"
            let eventRsvps = rsvpsByATag[aTag] ?? []

            let candidates: [DateCandidate] = ev.tags
                .filter { $0.first == "start" || $0.first == "date" }
                .compactMap { tag -> DateCandidate? in
                    guard let date = tag[safe: 1] else { return nil }
                    let time = tag[safe: 2]
                    // この候補日を選択した RSVP の pubkeys
                    let votes = eventRsvps.compactMap { rsvp -> String? in
                        let rsvpDates = rsvp.tags
                            .filter { $0.first == "start" }
                            .compactMap { $0[safe: 1] }
                        return rsvpDates.contains(date) ? rsvp.pubkey : nil
                    }
                    return DateCandidate(date: date, time: time, votes: votes)
                }

            return CalendarEvent(
                id:         ev.id,
                title:      ev.getTagValue("title") ?? "無題",
                candidates: candidates,
                creator:    ev.pubkey,
                createdAt:  ev.createdAt,
                dTag:       dTag
            )
        }.sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Publish

    /// Kind 31928 スケジュールイベントを作成する。
    func createCalendarEvent(title: String, candidates: [DateCandidate]) async {
        var tags: [[String]] = [
            ["d", UUID().uuidString],
            ["title", title]
        ]
        for c in candidates {
            if let time = c.time, !time.isEmpty {
                tags.append(["start", c.date, time])
            } else {
                tags.append(["start", c.date])
            }
        }
        try? await publishEvent(kind: NostrKind.chronostrEvent, tags: tags, content: "")
    }

    /// Kind 31925 RSVP をパブリッシュする（参加可能な候補日を指定）。
    ///
    /// - Parameters:
    ///   - creatorPubkey: スケジュールイベントの作成者 pubkey
    ///   - dTag:          スケジュールイベントの d タグ値
    ///   - acceptedDates: 参加可能な候補日の配列（YYYY-MM-DD）
    func voteCalendarEvent(creatorPubkey: String, dTag: String, acceptedDates: [String]) async {
        let aTag = "31928:\(creatorPubkey):\(dTag)"
        var tags: [[String]] = [
            ["a", aTag],
            ["d", UUID().uuidString]
        ]
        for date in acceptedDates {
            tags.append(["start", date])
        }
        try? await publishEvent(kind: NostrKind.calendarRsvp, tags: tags, content: "参加可能")
    }
}
