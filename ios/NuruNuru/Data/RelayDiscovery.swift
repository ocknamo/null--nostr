import Foundation
import CoreLocation

// MARK: - Models

struct RelayInfo {
    let url:      String
    let lat:      Double
    let lon:      Double
    let name:     String
    let region:   String
    let priority: Int
}

struct RegionInfo: Identifiable {
    let id:     String
    let name:   String
    let nameEn: String
    let lat:    Double
    let lon:    Double
    let country: String
}

struct RelayInfoWithDistance: Identifiable {
    var id: String { info.url }
    let info:     RelayInfo
    let distance: Double
}

struct Nip65Config {
    let inbox:    [RelayInfoWithDistance]
    let outbox:   [RelayInfoWithDistance]
    let discover: [RelayInfo]
    let combined: [Nip65Relay]
}

// MARK: - RelayDiscovery

/// GPS-based relay discovery — mirrors Android `RelayDiscovery.kt`.
enum RelayDiscovery {

    static let gpsRelayDatabase: [RelayInfo] = [
        // Japan
        RelayInfo(url: "wss://yabu.me",                  lat: 35.6092,  lon: 139.73,    name: "やぶみ",         region: "JP", priority: 1),
        RelayInfo(url: "wss://relay.nostr.wirednet.jp",  lat: 34.706,   lon: 135.493,   name: "WiredNet JP",   region: "JP", priority: 1),
        RelayInfo(url: "wss://r.kojira.io",              lat: 35.6762,  lon: 139.6503,  name: "Kojira",        region: "JP", priority: 1),
        RelayInfo(url: "wss://relay.origin.land",        lat: 35.6673,  lon: 139.751,   name: "Origin Land",   region: "JP", priority: 2),
        RelayInfo(url: "wss://v-relay.d02.vrtmrz.net",   lat: 34.6937,  lon: 135.502,   name: "vrtmrz",        region: "JP", priority: 2),

        // Asia
        RelayInfo(url: "wss://relay.0xchat.com",         lat: 1.35208,  lon: 103.82,    name: "0xchat",        region: "SG", priority: 1),
        RelayInfo(url: "wss://nostr-01.yakihonne.com",   lat: 1.29524,  lon: 103.79,    name: "Yakihonne",     region: "SG", priority: 2),
        RelayInfo(url: "wss://nostr.dler.com",           lat: 25.0501,  lon: 121.565,   name: "dler",          region: "TW", priority: 2),
        RelayInfo(url: "wss://relay.islandbitcoin.com",  lat: 12.8498,  lon: 77.6545,   name: "Island Bitcoin", region: "IN", priority: 2),
        RelayInfo(url: "wss://nostr.jerrynya.fun",       lat: 31.2304,  lon: 121.474,   name: "jerrynya",      region: "CN", priority: 2),

        // North America
        RelayInfo(url: "wss://relay.damus.io",           lat: 43.6532,  lon: -79.3832,  name: "Damus",         region: "NA", priority: 1),
        RelayInfo(url: "wss://relay.primal.net",         lat: 43.6532,  lon: -79.3832,  name: "Primal",        region: "NA", priority: 1),
        RelayInfo(url: "wss://relay.wellorder.net",      lat: 45.5201,  lon: -122.99,   name: "Wellorder",     region: "NA", priority: 2),
        RelayInfo(url: "wss://relay.illuminodes.com",    lat: 47.6061,  lon: -122.333,  name: "Illuminodes",   region: "NA", priority: 2),
        RelayInfo(url: "wss://relay.fundstr.me",         lat: 42.3601,  lon: -71.0589,  name: "Fundstr",       region: "NA", priority: 2),
        RelayInfo(url: "wss://nostrelites.org",          lat: 41.8781,  lon: -87.6298,  name: "Nostrelites",   region: "NA", priority: 2),
        RelayInfo(url: "wss://relay.westernbtc.com",     lat: 44.5401,  lon: -123.368,  name: "Western BTC",   region: "NA", priority: 2),
        RelayInfo(url: "wss://cyberspace.nostr1.com",    lat: 40.7057,  lon: -74.0136,  name: "Cyberspace",    region: "NA", priority: 2),
        RelayInfo(url: "wss://fanfares.nostr1.com",      lat: 40.7128,  lon: -74.006,   name: "Fanfares",      region: "NA", priority: 2),

        // Europe
        RelayInfo(url: "wss://nos.lol",                  lat: 50.4754,  lon: 12.3683,   name: "nos.lol",       region: "EU", priority: 1),
        RelayInfo(url: "wss://relay.snort.social",       lat: 53.3498,  lon: -6.26031,  name: "Snort",         region: "EU", priority: 1),
        RelayInfo(url: "wss://nostr.wine",               lat: 48.8566,  lon: 2.35222,   name: "nostr.wine",    region: "EU", priority: 1),
        RelayInfo(url: "wss://relay.nostr.band",         lat: 52.52,    lon: 13.405,    name: "nostr.band",    region: "EU", priority: 1),
        RelayInfo(url: "wss://nostr.bond",               lat: 50.1109,  lon: 8.68213,   name: "nostr.bond",    region: "EU", priority: 2),
        RelayInfo(url: "wss://relay.thebluepulse.com",   lat: 49.4521,  lon: 11.0767,   name: "Blue Pulse",    region: "EU", priority: 2),
        RelayInfo(url: "wss://relay.lumina.rocks",       lat: 49.0291,  lon: 8.35695,   name: "Lumina",        region: "EU", priority: 2),
        RelayInfo(url: "wss://relay.angor.io",           lat: 48.1046,  lon: 11.6002,   name: "Angor",         region: "EU", priority: 2),
        RelayInfo(url: "wss://purplerelay.com",          lat: 50.1109,  lon: 8.68213,   name: "Purple Relay",  region: "EU", priority: 2),
        RelayInfo(url: "wss://nostr.mom",                lat: 50.4754,  lon: 12.3683,   name: "nostr.mom",     region: "EU", priority: 2),

        // Scandinavia
        RelayInfo(url: "wss://r.alphaama.com",           lat: 60.1699,  lon: 24.9384,   name: "Alphaama",      region: "EU", priority: 2),

        // Russia
        RelayInfo(url: "wss://adre.su",                  lat: 59.8845,  lon: 30.3184,   name: "adre.su",       region: "RU", priority: 2),

        // South America
        RelayInfo(url: "wss://relay.internationalright-wing.org", lat: -22.5022, lon: -48.7114, name: "IRW", region: "SA", priority: 2),

        // Global/CDN
        RelayInfo(url: "wss://nostr.mutinywallet.com",   lat: 37.7749,  lon: -122.4194, name: "Mutiny",        region: "Global", priority: 2),
    ]

    static let directoryRelays: [RelayInfo] = [
        RelayInfo(url: "wss://directory.yabu.me", lat: 0, lon: 0, name: "Directory yabu.me", region: "JP", priority: 0),
        RelayInfo(url: "wss://purplepag.es",      lat: 0, lon: 0, name: "Purple Pages",      region: "Global", priority: 0),
    ]

    static let regionCoordinates: [RegionInfo] = [
        // Japan
        RegionInfo(id: "jp-tokyo",   name: "東京",           nameEn: "Tokyo",            lat: 35.6762,  lon: 139.6503, country: "JP"),
        RegionInfo(id: "jp-osaka",   name: "大阪",           nameEn: "Osaka",            lat: 34.6937,  lon: 135.5023, country: "JP"),
        RegionInfo(id: "jp-nagoya",  name: "名古屋",          nameEn: "Nagoya",           lat: 35.1815,  lon: 136.9066, country: "JP"),
        RegionInfo(id: "jp-fukuoka", name: "福岡",           nameEn: "Fukuoka",          lat: 33.5904,  lon: 130.4017, country: "JP"),
        RegionInfo(id: "jp-sapporo", name: "札幌",           nameEn: "Sapporo",          lat: 43.0618,  lon: 141.3545, country: "JP"),
        // Asia
        RegionInfo(id: "sg",         name: "シンガポール",     nameEn: "Singapore",        lat: 1.3521,   lon: 103.8198, country: "SG"),
        RegionInfo(id: "tw",         name: "台湾",           nameEn: "Taiwan",           lat: 25.0330,  lon: 121.5654, country: "TW"),
        RegionInfo(id: "kr",         name: "韓国",           nameEn: "South Korea",      lat: 37.5665,  lon: 126.9780, country: "KR"),
        RegionInfo(id: "cn-shanghai", name: "上海",          nameEn: "Shanghai",         lat: 31.2304,  lon: 121.4737, country: "CN"),
        RegionInfo(id: "in",         name: "インド",          nameEn: "India",            lat: 28.6139,  lon: 77.2090,  country: "IN"),
        // North America
        RegionInfo(id: "us-west",    name: "北米西部",        nameEn: "US West",          lat: 37.7749,  lon: -122.4194, country: "US"),
        RegionInfo(id: "us-east",    name: "北米東部",        nameEn: "US East",          lat: 40.7128,  lon: -74.0060,  country: "US"),
        RegionInfo(id: "ca",         name: "カナダ",          nameEn: "Canada",           lat: 43.6532,  lon: -79.3832,  country: "CA"),
        // Europe
        RegionInfo(id: "eu-west",    name: "西ヨーロッパ",    nameEn: "Western Europe",   lat: 48.8566,  lon: 2.3522,    country: "EU"),
        RegionInfo(id: "eu-central", name: "中央ヨーロッパ",  nameEn: "Central Europe",   lat: 52.5200,  lon: 13.4050,   country: "EU"),
        RegionInfo(id: "eu-north",   name: "北ヨーロッパ",    nameEn: "Northern Europe",  lat: 59.3293,  lon: 18.0686,   country: "EU"),
        RegionInfo(id: "uk",         name: "イギリス",        nameEn: "UK",               lat: 51.5074,  lon: -0.1278,   country: "UK"),
        // Others
        RegionInfo(id: "au",         name: "オーストラリア",   nameEn: "Australia",        lat: -33.8688, lon: 151.2093,  country: "AU"),
        RegionInfo(id: "br",         name: "ブラジル",        nameEn: "Brazil",           lat: -23.5505, lon: -46.6333,  country: "BR"),
        RegionInfo(id: "global",     name: "グローバル",       nameEn: "Global",           lat: 0.0,      lon: 0.0,       country: "Global"),
    ]

    /// Region grouping for dropdown display.
    static var groupedRegions: [(String, [RegionInfo])] {
        let grouped = Dictionary(grouping: regionCoordinates) { region -> String in
            switch region.country {
            case "JP":                     return "日本"
            case "SG", "TW", "KR", "CN", "IN": return "アジア"
            case "US", "CA":               return "北米"
            case "EU", "UK":               return "ヨーロッパ"
            default:                       return "その他"
            }
        }
        let order = ["日本", "アジア", "北米", "ヨーロッパ", "その他"]
        return order.compactMap { key in
            guard let regions = grouped[key] else { return nil }
            return (key, regions)
        }
    }

    // MARK: - Distance / Geohash

    /// Haversine distance in km.
    static func calculateDistance(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let R = 6371.0
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2) +
                cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) *
                sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return R * c
    }

    /// Encode lat/lon to a geohash string (precision 6).
    static func encodeGeohash(lat: Double, lon: Double, precision: Int = 6) -> String {
        let base32 = Array("0123456789bcdefghjkmnpqrstuvwxyz")
        var latRange = (-90.0, 90.0)
        var lonRange = (-180.0, 180.0)
        var isEven = true
        var bit = 0
        var ch = 0
        var result = ""

        while result.count < precision {
            if isEven {
                let mid = (lonRange.0 + lonRange.1) / 2
                if lon >= mid {
                    ch |= (1 << (4 - bit))
                    lonRange.0 = mid
                } else {
                    lonRange.1 = mid
                }
            } else {
                let mid = (latRange.0 + latRange.1) / 2
                if lat >= mid {
                    ch |= (1 << (4 - bit))
                    latRange.0 = mid
                } else {
                    latRange.1 = mid
                }
            }
            isEven.toggle()
            if bit < 4 {
                bit += 1
            } else {
                result.append(base32[ch])
                bit = 0
                ch = 0
            }
        }
        return result
    }

    // MARK: - Relay Selection

    static func findNearestRelays(userLat: Double, userLon: Double, count: Int = 5) -> [RelayInfoWithDistance] {
        gpsRelayDatabase
            .map { relay in
                RelayInfoWithDistance(
                    info: relay,
                    distance: calculateDistance(lat1: userLat, lon1: userLon, lat2: relay.lat, lon2: relay.lon)
                )
            }
            .sorted { lhs, rhs in
                if lhs.info.priority != rhs.info.priority { return lhs.info.priority < rhs.info.priority }
                return lhs.distance < rhs.distance
            }
            .prefix(count)
            .map { $0 }
    }

    static func generateRelayListByLocation(userLat: Double, userLon: Double) -> Nip65Config {
        let nearestRelays = findNearestRelays(userLat: userLat, userLon: userLon, count: 15)

        // Outbox (3-5): prefer nearest priority-1
        var outbox = nearestRelays.filter { $0.info.priority == 1 }.prefix(3).map { $0 }
        if outbox.count < 3 {
            let additional = nearestRelays
                .filter { r in !outbox.contains(where: { $0.info.url == r.info.url }) }
                .prefix(3 - outbox.count)
            outbox.append(contentsOf: additional)
        }

        // Inbox (3-4)
        var inbox = nearestRelays.filter { $0.info.priority == 1 }.prefix(3).map { $0 }
        let inboxUrls = Set(inbox.map(\.info.url))
        let globalRelay = gpsRelayDatabase
            .filter { relay in relay.priority == 1 && relay.region == "Global" && !inboxUrls.contains(relay.url) }
            .prefix(1)
            .map { relay in RelayInfoWithDistance(info: relay, distance: calculateDistance(lat1: userLat, lon1: userLon, lat2: relay.lat, lon2: relay.lon)) }
        inbox.append(contentsOf: globalRelay)

        // Combined NIP-65 list
        var combined: [Nip65Relay] = []
        var addedUrls = Set<String>()

        // Nearest 2 as read+write
        for r in nearestRelays.prefix(2) {
            if !addedUrls.contains(r.info.url) {
                combined.append(Nip65Relay(url: r.info.url, permission: .readWrite))
                addedUrls.insert(r.info.url)
            }
        }
        // Remaining outbox (write)
        for r in outbox {
            if !addedUrls.contains(r.info.url) {
                combined.append(Nip65Relay(url: r.info.url, permission: .write))
                addedUrls.insert(r.info.url)
            }
        }
        // Remaining inbox (read)
        for r in inbox {
            if !addedUrls.contains(r.info.url) {
                combined.append(Nip65Relay(url: r.info.url, permission: .read))
                addedUrls.insert(r.info.url)
            } else if let idx = combined.firstIndex(where: { $0.url == r.info.url }),
                      combined[idx].permission == .write {
                combined[idx] = Nip65Relay(url: r.info.url, permission: .readWrite)
            }
        }

        return Nip65Config(
            inbox: Array(inbox.prefix(4)),
            outbox: Array(outbox.prefix(5)),
            discover: directoryRelays,
            combined: combined
        )
    }

    static func formatDistance(_ km: Double) -> String {
        if km < 1.0 { return "\(Int(km * 1000))m" }
        if km < 100 { return String(format: "%.1fkm", km) }
        return "\(Int(km))km"
    }
}
