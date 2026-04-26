import Foundation

/// NIP-01 kind:0 metadata — mirrors Android UserProfile data class.
struct UserProfile: Codable {
    var pubkey:      String
    var name:        String?
    var displayName: String?
    var about:       String?
    var picture:     String?
    var nip05:       String?
    var banner:      String?
    var lud16:       String?
    var website:     String?
    var birthday:    String?
    var geohash:     String?

    enum CodingKeys: String, CodingKey {
        case pubkey, name
        case displayName = "display_name"
        case about, picture, nip05, banner, lud16, website, birthday, geohash
    }

    init(
        pubkey:      String = "",
        name:        String? = nil,
        displayName: String? = nil,
        about:       String? = nil,
        picture:     String? = nil,
        nip05:       String? = nil,
        banner:      String? = nil,
        lud16:       String? = nil,
        website:     String? = nil,
        birthday:    String? = nil,
        geohash:     String? = nil
    ) {
        self.pubkey      = pubkey
        self.name        = name
        self.displayName = displayName
        self.about       = about
        self.picture     = picture
        self.nip05       = nip05
        self.banner      = banner
        self.lud16       = lud16
        self.website     = website
        self.birthday    = birthday
        self.geohash     = geohash
    }

    /// Display name fallback chain: displayName → name → pubkey prefix.
    /// Mirrors Android UserProfile.displayedName.
    var displayedName: String {
        if let n = displayName, !n.isBlankOrEmpty { return n }
        if let n = name,        !n.isBlankOrEmpty { return n }
        return String(pubkey.prefix(12)) + "..."
    }
}

private extension String {
    var isBlankOrEmpty: Bool {
        trimmingCharacters(in: .whitespaces).isEmpty
    }
}
