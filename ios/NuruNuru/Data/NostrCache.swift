import Foundation

// MARK: - Cache Entry (persistence layer)

private struct CacheEntry: Codable {
    let value:  String  // JSON-encoded content
    let expiry: Int64   // milliseconds since epoch
}

// MARK: - LRU Cache (in-memory layer)

private final class LRUCache<K: Hashable, V> {
    private var dict:  [K: V] = [:]
    private var order: [K]    = []
    let capacity: Int

    init(capacity: Int) { self.capacity = capacity }

    func get(_ key: K) -> V? {
        guard let value = dict[key] else { return nil }
        order.removeAll { $0 == key }
        order.append(key)
        return value
    }

    func set(_ key: K, _ value: V) {
        if dict[key] != nil {
            order.removeAll { $0 == key }
        } else if order.count >= capacity, let lru = order.first {
            order.removeFirst()
            dict.removeValue(forKey: lru)
        }
        dict[key] = value
        order.append(key)
    }

    func remove(_ key: K) {
        dict.removeValue(forKey: key)
        order.removeAll { $0 == key }
    }

    func removeAll() { dict.removeAll(); order.removeAll() }
    var count: Int { dict.count }
}

// MARK: - NostrCache

/// Two-layer cache: in-memory LRU + UserDefaults persistence.
/// Mirrors Android NostrCache.
final class NostrCache {

    // MARK: - In-Memory LRU Layers

    private let profileLRU  = LRUCache<String, UserProfile>(capacity: CacheMaxEntries.profiles)
    private let timelineLRU = LRUCache<String, [NostrEvent]>(capacity: CacheMaxEntries.timeline)
    private let lock         = NSLock()

    // MARK: - Persistence

    private let defaults = UserDefaults.standard
    private let prefix   = "nuru_c_"
    private let encoder  = JSONEncoder()
    private let decoder  = JSONDecoder()

    // MARK: - TTL Settings (可変 — AppPreferences から上書き可)

    var profileTtl:    Int = CacheDuration.profile
    var profileEnabled: Bool = true

    var timelineTtl:   Int = CacheDuration.timeline
    var timelineEnabled: Bool = true

    var followListTtl: Int = CacheDuration.followList
    var followListEnabled: Bool = true

    var muteListTtl:   Int = CacheDuration.muteList
    var muteListEnabled: Bool = true

    var notificationTtl: Int = 86_400_000  // 1日
    var notificationEnabled: Bool = true

    var emojiTtl:      Int = CacheDuration.emoji
    var emojiEnabled: Bool = true

    var relayInfoTtl: Int = 86_400_000  // 1日
    var relayInfoEnabled: Bool = true

    var badgeTtl: Int = 86_400_000  // 1日
    var badgeEnabled: Bool = true

    var mlsGroupsTtl:   Int = 30 * 86_400_000  // 30日
    var mlsMessagesTtl: Int = 30 * 86_400_000  // 30日

    // MARK: - Profile Cache

    /// プロフィール編集後のグレース期間マップ (pubkey → 期限)。
    /// グレース期間中はリレーからの古いデータで上書きしない。
    private var profileGraceUntil: [String: Date] = [:]

    func getCachedProfile(_ pubkey: String) -> UserProfile? {
        lock.lock(); defer { lock.unlock() }
        // 1. LRU メモリキャッシュ（最速）
        if let cached = profileLRU.get(pubkey) { return cached }
        // 2. UserDefaults 永続化層へフォールバック（アプリ再起動後に必要）
        //    getCachedTimeline と同じパターン — LRU ミス時に UserDefaults から復元する。
        guard let raw  = readNoTTL(key: "profile_\(pubkey)"),
              let data = raw.data(using: .utf8),
              let profile = try? decoder.decode(UserProfile.self, from: data) else { return nil }
        // LRU に復元して次回は即時返却
        profileLRU.set(pubkey, profile)
        return profile
    }

    func setCachedProfile(_ pubkey: String, _ profile: UserProfile) {
        lock.lock(); defer { lock.unlock() }
        // グレース期間中の場合、キャッシュの方が新しい可能性があるため上書きしない
        // （ただし cacheProfile() からの直接呼び出しは setProfileGraceUntil の前なので問題なし）
        if let until = profileGraceUntil[pubkey], Date() < until {
            // グレース期間中: LRU または UserDefaults にすでにあるプロフィールを優先
            if profileLRU.get(pubkey) != nil { return }
            if readNoTTL(key: "profile_\(pubkey)") != nil { return }
        }
        profileLRU.set(pubkey, profile)
        guard profileEnabled else { return }
        guard let data = try? encoder.encode(profile),
              let json = String(data: data, encoding: .utf8) else { return }
        persist(key: "profile_\(pubkey)", value: json, ttl: profileTtl)
    }

    /// プロフィールのグレース期間を設定する。
    func setProfileGraceUntil(_ pubkey: String, until: Date) {
        lock.lock(); defer { lock.unlock() }
        profileGraceUntil[pubkey] = until
    }

    /// プロフィールがグレース期間中かどうかを返す。
    func isProfileInGracePeriod(_ pubkey: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard let until = profileGraceUntil[pubkey] else { return false }
        return Date() < until
    }

    // MARK: - Timeline Cache

    /// タイムラインキャッシュ取得（TTLスキップ — 古いポストを見せても問題なし）。
    func getCachedTimeline(key: String = "global") -> [NostrEvent]? {
        lock.lock(); defer { lock.unlock() }
        if let events = timelineLRU.get(key) { return events }
        return readNoTTL(key: "timeline_\(key)").flatMap {
            guard let data = $0.data(using: .utf8) else { return nil }
            return try? decoder.decode([NostrEvent].self, from: data)
        }
    }

    func setCachedTimeline(_ events: [NostrEvent], key: String = "global") {
        lock.lock(); defer { lock.unlock() }
        timelineLRU.set(key, events)
        guard timelineEnabled else { return }
        guard let data = try? encoder.encode(events),
              let json = String(data: data, encoding: .utf8) else { return }
        persist(key: "timeline_\(key)", value: json, ttl: timelineTtl)
    }

    // MARK: - Follow List Cache

    func getCachedFollowList(pubkey: String) -> [String]? {
        readRaw(key: "follow_\(pubkey)").flatMap {
            guard let data = $0.data(using: .utf8) else { return nil }
            return try? decoder.decode([String].self, from: data)
        }
    }

    func setCachedFollowList(pubkey: String, list: [String]) {
        guard followListEnabled else { return }
        guard let data = try? encoder.encode(list),
              let json = String(data: data, encoding: .utf8) else { return }
        persist(key: "follow_\(pubkey)", value: json, ttl: followListTtl)
    }

    // MARK: - Mute List Cache

    func getCachedMuteList(pubkey: String) -> ([String], [String])? {
        guard let raw  = readRaw(key: "mute_\(pubkey)"),
              let data = raw.data(using: .utf8),
              let arr  = try? decoder.decode([[String]].self, from: data),
              arr.count == 2 else { return nil }
        return (arr[0], arr[1])
    }

    func setCachedMuteList(pubkey: String, pubkeys: [String], keywords: [String]) {
        guard muteListEnabled else { return }
        guard let data = try? encoder.encode([pubkeys, keywords]),
              let json = String(data: data, encoding: .utf8) else { return }
        persist(key: "mute_\(pubkey)", value: json, ttl: muteListTtl)
    }

    // MARK: - Notification Result Cache (Android NotificationResult 一括キャッシュに対応)

    /// 通知結果キャッシュ構造体
    struct CachedNotificationResult: Codable {
        let items:         [NotificationItem]
        let profileKeys:   [String]          // profiles の pubkey 一覧
        let originalKeys:  [String]          // originalPosts の event ID 一覧
        let cachedAt:      Int64
    }

    private let notificationCacheKey = "notification_result"

    /// 通知結果をキャッシュから取得。
    /// Android: `cache.getCachedNotifications()` に対応。
    func getCachedNotificationResult() -> CachedNotificationResult? {
        guard notificationEnabled else { return nil }
        guard let raw = readRaw(key: notificationCacheKey),
              let data = raw.data(using: .utf8),
              let result = try? decoder.decode(CachedNotificationResult.self, from: data) else { return nil }
        return result
    }

    /// 通知結果をキャッシュに保存。
    /// Android: `cache.setCachedNotifications(result)` に対応。
    func setCachedNotificationResult(_ items: [NotificationItem]) {
        guard notificationEnabled else { return }
        let result = CachedNotificationResult(
            items:        items,
            profileKeys:  Array(Set(items.map(\.pubkey))),
            originalKeys: items.compactMap(\.targetEventId),
            cachedAt:     Int64(Date().timeIntervalSince1970 * 1000)
        )
        guard let data = try? encoder.encode(result),
              let json = String(data: data, encoding: .utf8) else { return }
        persist(key: notificationCacheKey, value: json, ttl: notificationTtl)
    }

    // MARK: - Badge Cache (NIP-58)

    /// バッジ URL キャッシュ取得（pubkey → image URL 配列）。
    /// Android: cache.getCachedBadges() に対応。
    func getCachedBadges(pubkey: String) -> [String]? {
        guard badgeEnabled else { return nil }
        guard let raw  = readRaw(key: "badge_\(pubkey)"),
              let data = raw.data(using: .utf8),
              let urls = try? decoder.decode([String].self, from: data) else { return nil }
        return urls
    }

    /// BadgeItem 配列をキャッシュから取得（名前・説明付き）。
    func getCachedBadgeItems(pubkey: String) -> [BadgeItem]? {
        guard badgeEnabled else { return nil }
        guard let raw  = readRaw(key: "badge_items_\(pubkey)"),
              let data = raw.data(using: .utf8),
              let items = try? decoder.decode([BadgeItem].self, from: data) else { return nil }
        return items
    }

    /// バッジ URL キャッシュ保存。
    /// Android: cache.setCachedBadges() に対応。
    func setCachedBadges(pubkey: String, urls: [String]) {
        guard badgeEnabled else { return }
        guard let data = try? encoder.encode(urls),
              let json = String(data: data, encoding: .utf8) else { return }
        persist(key: "badge_\(pubkey)", value: json, ttl: badgeTtl)
    }

    /// BadgeItem 配列をキャッシュに保存（名前・説明付き）。
    func setCachedBadgeItems(pubkey: String, items: [BadgeItem]) {
        guard badgeEnabled else { return }
        guard let data = try? encoder.encode(items),
              let json = String(data: data, encoding: .utf8) else { return }
        persist(key: "badge_items_\(pubkey)", value: json, ttl: badgeTtl)
    }

    // MARK: - Deleted Event IDs (NIP-09)

    private let deletedIdsKey = "nuru_deleted_event_ids"
    private let maxDeletedIds = 500

    func addDeletedEventId(_ id: String) {
        var ids = getDeletedEventIds()
        ids.insert(id)
        if ids.count > maxDeletedIds {
            ids = Set(ids.sorted().dropFirst(ids.count - maxDeletedIds))
        }
        defaults.set(Array(ids), forKey: deletedIdsKey)
    }

    func getDeletedEventIds() -> Set<String> {
        Set(defaults.stringArray(forKey: deletedIdsKey) ?? [])
    }

    // MARK: - Left Groups (MLS)

    private let leftGroupsKey = "nuru_left_groups"

    func markGroupAsLeft(_ groupIdHex: String) {
        var ids = getLeftGroupIds()
        ids.insert(groupIdHex)
        defaults.set(Array(ids), forKey: leftGroupsKey)
    }

    func getLeftGroupIds() -> Set<String> {
        Set(defaults.stringArray(forKey: leftGroupsKey) ?? [])
    }

    // MARK: - Apply Settings from AppPreferences (mirrors Android NostrCache.applySettings)

    func applySettings(_ appPrefs: AppPreferences) {
        let day = 86_400_000 // 1日 = 86,400,000 ms

        profileTtl      = appPrefs.getCacheTtlMs("profile", day)
        profileEnabled   = appPrefs.isCacheEnabled("profile")

        timelineTtl      = appPrefs.getCacheTtlMs("timeline", day)
        timelineEnabled  = appPrefs.isCacheEnabled("timeline")

        followListTtl     = appPrefs.getCacheTtlMs("followlist", day)
        followListEnabled = appPrefs.isCacheEnabled("followlist")

        muteListTtl      = appPrefs.getCacheTtlMs("mutelist", day)
        muteListEnabled  = appPrefs.isCacheEnabled("mutelist")

        notificationTtl     = appPrefs.getCacheTtlMs("notification", day)
        notificationEnabled = appPrefs.isCacheEnabled("notification")

        emojiTtl      = appPrefs.getCacheTtlMs("emoji", day)
        emojiEnabled  = appPrefs.isCacheEnabled("emoji")

        relayInfoTtl     = appPrefs.getCacheTtlMs("relay", day)
        relayInfoEnabled = appPrefs.isCacheEnabled("relay")

        badgeTtl      = appPrefs.getCacheTtlMs("badge", day)
        badgeEnabled  = appPrefs.isCacheEnabled("badge")

        mlsGroupsTtl   = appPrefs.getCacheTtlMs("mls_groups", 30 * day)
        mlsMessagesTtl = appPrefs.getCacheTtlMs("mls_messages", 30 * day)
    }

    // MARK: - Cache Statistics (mirrors Android NostrCache.CacheStats)

    struct CacheStats {
        let entryCount: Int
        let memoryProfileCount: Int
        let memoryTimelineCount: Int
    }

    func getCacheStats() -> CacheStats {
        CacheStats(
            entryCount: defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix(prefix) }.count,
            memoryProfileCount: profileLRU.count,
            memoryTimelineCount: timelineLRU.count
        )
    }

    /// nostrdb ディレクトリの合計ファイルサイズを返す（バイト）。
    /// iOS では `Application Support/nostrdb_ndb` を使用。
    /// Rust FFI (Phase 1) 未統合の場合は 0 を返す。
    static func nostrdbFileSize() -> Int64 {
        let dbPath = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("nostrdb_ndb").path ?? ""
        guard !dbPath.isEmpty else { return 0 }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dbPath, isDirectory: &isDir) else { return 0 }
        if isDir.boolValue {
            guard let enumerator = FileManager.default.enumerator(atPath: dbPath) else { return 0 }
            var total: Int64 = 0
            while let file = enumerator.nextObject() as? String {
                let fullPath = (dbPath as NSString).appendingPathComponent(file)
                if let attrs = try? FileManager.default.attributesOfItem(atPath: fullPath),
                   let size = attrs[.size] as? Int64 {
                    total += size
                }
            }
            return total
        } else {
            return (try? FileManager.default.attributesOfItem(atPath: dbPath))?[.size] as? Int64 ?? 0
        }
    }

    /// UserDefaults に保存されたキャッシュの合計サイズ（バイト概算）を返す。
    /// Android の nostrdb サイズ表示に対応するキャッシュサイズ代替指標。
    static func appCacheTotalSize() -> Int64 {
        var total: Int64 = 0
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("nuru_c_") {
            if let data = defaults.data(forKey: key) {
                total += Int64(data.count)
            }
        }
        return total
    }

    // MARK: - Cache Management

    @discardableResult
    func clearExpiredCache() -> Int {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        var count = 0
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            guard let data  = defaults.data(forKey: key),
                  let entry = try? decoder.decode(CacheEntry.self, from: data) else { continue }
            if now > entry.expiry {
                defaults.removeObject(forKey: key)
                count += 1
            }
        }
        return count
    }

    func clearAll() {
        lock.lock(); defer { lock.unlock() }
        profileLRU.removeAll()
        timelineLRU.removeAll()
        defaults.dictionaryRepresentation().keys
            .filter { $0.hasPrefix(prefix) }
            .forEach { defaults.removeObject(forKey: $0) }
    }

    func clearByType(_ typeId: String) {
        lock.lock(); defer { lock.unlock() }
        switch typeId {
        case "profile":
            profileLRU.removeAll()
            clearByPrefix("profile_")
        case "timeline":
            timelineLRU.removeAll()
            clearByPrefix("timeline_")
        case "followlist":  clearByPrefix("follow_")
        case "mutelist":    clearByPrefix("mute_")
        case "notification": clearByPrefix("notification_")
        case "emoji":       clearByPrefix("emoji_")
        case "relay":       clearByPrefix("relay_")
        case "badge":       clearByPrefix("badge_")
        case "mls_groups":  clearByPrefix("mls_groups_")
        case "mls_messages": clearByPrefix("mls_msgs_")
        default:            clearByPrefix("\(typeId)_")
        }
    }

    func getEntriesCount(_ typeId: String) -> Int {
        let sub: String
        switch typeId {
        case "profile":      sub = "profile_"
        case "timeline":     sub = "timeline_"
        case "followlist":   sub = "follow_"
        case "mutelist":     sub = "mute_"
        case "notification": sub = "notification_"
        case "emoji":        sub = "emoji_"
        case "relay":        sub = "relay_"
        case "badge":        sub = "badge_"
        case "mls_groups":   sub = "mls_groups_"
        case "mls_messages": sub = "mls_msgs_"
        default:             return 0
        }
        return defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix(prefix + sub) }.count
    }

    // MARK: - Private Helpers

    private func persist(key: String, value: String, ttl: Int) {
        let expiry = Int64(Date().timeIntervalSince1970 * 1000) + Int64(ttl)
        guard let data = try? encoder.encode(CacheEntry(value: value, expiry: expiry)) else { return }
        defaults.set(data, forKey: prefix + key)
    }

    private func readRaw(key: String) -> String? {
        guard let data  = defaults.data(forKey: prefix + key),
              let entry = try? decoder.decode(CacheEntry.self, from: data) else { return nil }
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        guard now <= entry.expiry else {
            defaults.removeObject(forKey: prefix + key)
            return nil
        }
        return entry.value
    }

    private func readNoTTL(key: String) -> String? {
        guard let data  = defaults.data(forKey: prefix + key),
              let entry = try? decoder.decode(CacheEntry.self, from: data) else { return nil }
        return entry.value
    }

    private func clearByPrefix(_ typePrefix: String) {
        defaults.dictionaryRepresentation().keys
            .filter { $0.hasPrefix(prefix + typePrefix) }
            .forEach { defaults.removeObject(forKey: $0) }
    }
}
