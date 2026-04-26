import Foundation

/// UserDefaults-backed application preferences.
/// Private keys are NEVER stored here — use SecureKeyManager.
/// Mirrors Android AppPreferences (non-sensitive fields only).
final class AppPreferences {

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let publicKeyHex       = "nurunuru_pubkey_hex"
        static let isExternalSigner   = "nurunuru_is_external_signer"
        static let selectedRelays     = "nurunuru_relays"
        static let biometricEnabled   = "nurunuru_biometric_enabled"
        static let mainRelay          = "nurunuru_main_relay"
        static let defaultZapAmount   = "nurunuru_default_zap_amount"
        static let autoSignEnabled    = "nurunuru_auto_sign_enabled"
        static let uploadServer       = "nurunuru_upload_server"
        static let customUploadServers = "nurunuru_custom_upload_servers"
        static let elevenLabsApiKey   = "nurunuru_elevenlabs_api_key"
        static let elevenLabsLanguage = "nurunuru_elevenlabs_language"
        static let favoriteApps       = "nurunuru_favorite_apps"
        static let externalApps       = "nurunuru_external_apps"
        static let userLat            = "nurunuru_user_lat"
        static let userLon            = "nurunuru_user_lon"
        static let userGeohash        = "nurunuru_user_geohash"
        static let selectedRegionId   = "nurunuru_selected_region_id"
        static let nip65Relays                    = "nurunuru_nip65_relays"
        static let notificationEnabledKinds       = "nurunuru_notification_enabled_kinds"
        static let notificationEmojiReactionEnabled = "nurunuru_notification_emoji_reaction_enabled"
        static let hiddenMlsGroupIds = "nurunuru_hidden_mls_group_ids"
        static let mlsJoinedAtByGroupId = "nurunuru_mls_joined_at_by_group_id"
        static let mlsSelfUpdateCompletedAtByGroupId = "nurunuru_mls_self_update_completed_at_by_group_id"
        static let mlsKeyPackageEventJsonById = "nurunuru_mls_keypackage_event_json_by_id"
        static let mlsConsumedKeyPackageEventIds = "nurunuru_mls_consumed_keypackage_event_ids"
        static let mlsRejectedWelcomeRetryAfterById = "nurunuru_mls_rejected_welcome_retry_after_by_id"
    }

    var publicKeyHex: String? {
        get { defaults.string(forKey: Keys.publicKeyHex) }
        set { defaults.set(newValue, forKey: Keys.publicKeyHex) }
    }

    var isExternalSigner: Bool {
        get { defaults.bool(forKey: Keys.isExternalSigner) }
        set { defaults.set(newValue, forKey: Keys.isExternalSigner) }
    }

    var selectedRelays: [String] {
        get { defaults.stringArray(forKey: Keys.selectedRelays) ?? defaultRelays }
        set { defaults.set(newValue, forKey: Keys.selectedRelays) }
    }

    var mainRelay: String {
        get { defaults.string(forKey: Keys.mainRelay) ?? defaultRelays[0] }
        set { defaults.set(newValue, forKey: Keys.mainRelay) }
    }

    var biometricEnabled: Bool {
        get { defaults.bool(forKey: Keys.biometricEnabled) }
        set { defaults.set(newValue, forKey: Keys.biometricEnabled) }
    }

    var defaultZapAmount: Int {
        get { defaults.integer(forKey: Keys.defaultZapAmount).nonZero ?? 21 }
        set { defaults.set(newValue, forKey: Keys.defaultZapAmount) }
    }

    var autoSignEnabled: Bool {
        get { defaults.object(forKey: Keys.autoSignEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.autoSignEnabled) }
    }

    /// Raw string（UserDefaults 保存用）。型安全な操作には `uploadServerEnum` を推奨。
    var uploadServer: String {
        // Default to Blossom (nostr.build) per BUD-03-oriented upload settings.
        get { defaults.string(forKey: Keys.uploadServer) ?? UploadServer.defaultBlossomUrl }
        set { defaults.set(newValue, forKey: Keys.uploadServer) }
    }

    /// `UploadServer` enum として取得・設定する型安全なアクセサ。
    var uploadServerEnum: UploadServer {
        get { UploadServer(rawValue: uploadServer) ?? .nostrBuild }
        set { uploadServer = newValue.rawValue }
    }

    // User-defined upload destination base URLs.
    var customUploadServers: [String] {
        get {
            guard let data = defaults.data(forKey: Keys.customUploadServers),
                  let list = try? JSONDecoder().decode([String].self, from: data) else { return [] }
            return list
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Keys.customUploadServers)
            }
        }
    }

    var elevenLabsApiKey: String {
        get { defaults.string(forKey: Keys.elevenLabsApiKey) ?? "" }
        set { defaults.set(newValue, forKey: Keys.elevenLabsApiKey) }
    }

    var elevenLabsLanguage: String {
        get { defaults.string(forKey: Keys.elevenLabsLanguage) ?? "jpn" }
        set { defaults.set(newValue, forKey: Keys.elevenLabsLanguage) }
    }

    /// IDs of favourite mini-apps (shown in マイミニアプリ horizontal row).
    var favoriteApps: [String] {
        get {
            guard let data = defaults.data(forKey: Keys.favoriteApps),
                  let list = try? JSONDecoder().decode([String].self, from: data) else { return [] }
            return list
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) { defaults.set(data, forKey: Keys.favoriteApps) }
        }
    }

    /// JSON-encoded external mini-app list.
    var externalApps: String {
        get { defaults.string(forKey: Keys.externalApps) ?? "[]" }
        set { defaults.set(newValue, forKey: Keys.externalApps) }
    }

    var userLat: Double {
        get { defaults.double(forKey: Keys.userLat) }
        set { defaults.set(newValue, forKey: Keys.userLat) }
    }

    var userLon: Double {
        get { defaults.double(forKey: Keys.userLon) }
        set { defaults.set(newValue, forKey: Keys.userLon) }
    }

    var userGeohash: String? {
        get { defaults.string(forKey: Keys.userGeohash) }
        set { defaults.set(newValue, forKey: Keys.userGeohash) }
    }

    var selectedRegionId: String? {
        get { defaults.string(forKey: Keys.selectedRegionId) }
        set { defaults.set(newValue, forKey: Keys.selectedRegionId) }
    }

    /// NIP-65 relay list stored as JSON array of `{url, read, write}`.
    var nip65Relays: [Nip65Relay] {
        get {
            guard let data = defaults.data(forKey: Keys.nip65Relays),
                  let list = try? JSONDecoder().decode([Nip65Relay].self, from: data) else { return [] }
            return list
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) { defaults.set(data, forKey: Keys.nip65Relays) }
        }
    }

    /// 通知で有効な Kind のセット (Android: notificationEnabledKinds)
    /// デフォルト: reaction(7), zapReceipt(9735), repost(6), textNote(1), badgeAward(8)
    var notificationEnabledKinds: Set<Int> {
        get {
            guard let data = defaults.data(forKey: Keys.notificationEnabledKinds),
                  let arr = try? JSONDecoder().decode([Int].self, from: data) else {
                return [NostrKind.reaction, NostrKind.zapReceipt, NostrKind.repost,
                        NostrKind.textNote, NostrKind.badgeAward]
            }
            return Set(arr)
        }
        set {
            if let data = try? JSONEncoder().encode(Array(newValue)) {
                defaults.set(data, forKey: Keys.notificationEnabledKinds)
            }
        }
    }

    /// 絵文字リアクション通知の有効/無効 (Android: notificationEmojiReactionEnabled)
    var notificationEmojiReactionEnabled: Bool {
        get { defaults.object(forKey: Keys.notificationEmojiReactionEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.notificationEmojiReactionEnabled) }
    }

    /// Hidden/stale MLS group IDs (persisted across app relaunch).
    var hiddenMlsGroupIds: Set<String> {
        get {
            guard let arr = defaults.stringArray(forKey: Keys.hiddenMlsGroupIds) else { return [] }
            return Set(arr)
        }
        set {
            defaults.set(Array(newValue), forKey: Keys.hiddenMlsGroupIds)
        }
    }

    /// Per-group join timestamp (unix seconds) used for MIP-02 self-update 24h requirement.
    var mlsJoinedAtByGroupId: [String: Int64] {
        get {
            guard let data = defaults.data(forKey: Keys.mlsJoinedAtByGroupId),
                  let map = try? JSONDecoder().decode([String: Int64].self, from: data) else { return [:] }
            return map
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Keys.mlsJoinedAtByGroupId)
            }
        }
    }

    /// Per-group self-update completion timestamp (unix seconds).
    var mlsSelfUpdateCompletedAtByGroupId: [String: Int64] {
        get {
            guard let data = defaults.data(forKey: Keys.mlsSelfUpdateCompletedAtByGroupId),
                  let map = try? JSONDecoder().decode([String: Int64].self, from: data) else { return [:] }
            return map
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Keys.mlsSelfUpdateCompletedAtByGroupId)
            }
        }
    }

    /// Locally published KeyPackage event JSONs keyed by event id (hex).
    /// Used to ensure MIP-02 consumed-keypackage deletion/rotation even when relay fetch misses.
    var mlsKeyPackageEventJsonById: [String: String] {
        get {
            guard let data = defaults.data(forKey: Keys.mlsKeyPackageEventJsonById),
                  let map = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
            return map
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Keys.mlsKeyPackageEventJsonById)
            }
        }
    }

    /// KeyPackage event ids already consumed by MLS Welcome processing.
    /// Relay deletion is best-effort, so this local set is the source of truth
    /// for avoiding KeyPackage reuse after app relaunch.
    var mlsConsumedKeyPackageEventIds: Set<String> {
        get {
            guard let arr = defaults.stringArray(forKey: Keys.mlsConsumedKeyPackageEventIds) else { return [] }
            return Set(arr)
        }
        set {
            defaults.set(Array(newValue), forKey: Keys.mlsConsumedKeyPackageEventIds)
        }
    }

    /// Rejected Welcome event retry gate (event id -> next retry unix seconds).
    /// Persisted so concurrent repository instances / app lifecycle churn do not
    /// repeatedly unwrap/process the same invalid or non-matching kind:1059 event.
    var mlsRejectedWelcomeRetryAfterById: [String: Int64] {
        get {
            guard let data = defaults.data(forKey: Keys.mlsRejectedWelcomeRetryAfterById),
                  let map = try? JSONDecoder().decode([String: Int64].self, from: data) else { return [:] }
            return map
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Keys.mlsRejectedWelcomeRetryAfterById)
            }
        }
    }

    // MARK: - Cache Settings (per-type enable/TTL — mirrors Android AppPreferences)

    /// キャッシュ種別ごとの有効/無効フラグ。デフォルト: true（有効）。
    func isCacheEnabled(_ typeId: String) -> Bool {
        defaults.object(forKey: "nurunuru_cache_\(typeId)_enabled") as? Bool ?? true
    }

    func setCacheEnabled(_ typeId: String, _ enabled: Bool) {
        defaults.set(enabled, forKey: "nurunuru_cache_\(typeId)_enabled")
    }

    /// キャッシュ種別ごとの TTL（ミリ秒）。未設定時は `defaultMs` を返す。
    func getCacheTtlMs(_ typeId: String, _ defaultMs: Int) -> Int {
        let v = defaults.integer(forKey: "nurunuru_cache_\(typeId)_ttl")
        return v > 0 ? v : defaultMs
    }

    func setCacheTtlMs(_ typeId: String, _ ttlMs: Int) {
        defaults.set(ttlMs, forKey: "nurunuru_cache_\(typeId)_ttl")
    }

    func clear() {
        [Keys.publicKeyHex,
         Keys.isExternalSigner,
         Keys.selectedRelays,
         Keys.biometricEnabled,
         Keys.mainRelay,
         Keys.defaultZapAmount,
         Keys.autoSignEnabled,
         Keys.uploadServer,
         Keys.customUploadServers,
         Keys.favoriteApps,
         Keys.externalApps,
         Keys.hiddenMlsGroupIds,
         Keys.mlsJoinedAtByGroupId,
         Keys.mlsSelfUpdateCompletedAtByGroupId,
         Keys.mlsKeyPackageEventJsonById,
         Keys.mlsConsumedKeyPackageEventIds,
         Keys.mlsRejectedWelcomeRetryAfterById].forEach { defaults.removeObject(forKey: $0) }
    }
}

private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}
