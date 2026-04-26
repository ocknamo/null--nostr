import SwiftUI

/// Centralized icon definitions — mirrors Android NuruIcons.kt.
/// Maps all custom vector icons to equivalent SF Symbols.
/// Usage: Image(systemName: NuruIcons.like(filled: true))
enum NuruIcons {

    // MARK: - Static Icons

    /// xmark  (Android: Close)
    static let close         = "xmark"
    /// video  (Android: Video)
    static let video         = "video"
    /// photo  (Android: Image)
    static let photo         = "photo"
    /// exclamationmark.triangle  (Android: Warning)
    static let warning       = "exclamationmark.triangle"
    /// face.smiling  (Android: Emoji)
    static let emoji         = "face.smiling"
    /// mic  (Android: Mic)
    static let mic           = "mic"
    /// globe  (Android: Website)
    static let website       = "globe"
    /// birthday.cake  (Android: Cake)
    static let cake          = "birthday.cake"
    /// magnifyingglass  (Android: Search)
    static let search        = "magnifyingglass"
    /// lock  (Android: Lock outline)
    static let lock          = "lock"
    /// lock.fill  (Android: Lock filled)
    static let lockFill      = "lock.fill"
    /// rosette  (Android: Badge)
    static let badge         = "rosette"
    /// calendar  (Android: Scheduler)
    static let scheduler     = "calendar"
    /// network  (Android: Relay)
    static let relay         = "network"
    /// square.and.arrow.up  (Android: Backup)
    static let backup        = "square.and.arrow.up"
    /// square.and.arrow.down  (Android: Download)
    static let download      = "square.and.arrow.down"
    /// bell  (Android: Notifications outline)
    static let bell          = "bell"
    /// bell.fill  (Android: Notifications filled)
    static let bellFill      = "bell.fill"
    /// arrow.2.squarepath  (Android: Repost)
    static let repost        = "arrow.2.squarepath"
    /// bubble.left  (Android: Reply / comment)
    static let reply         = "bubble.left"
    /// paperplane  (Android: Send)
    static let send          = "paperplane"
    /// checkmark  (Android: Check)
    static let check         = "checkmark"
    /// ellipsis  (Android: MoreVert)
    static let moreVert      = "ellipsis"
    /// hand.thumbsdown  (Android: NotInterested)
    static let notInterested = "hand.thumbsdown"
    /// flag  (Android: Flag outline)
    static let flag          = "flag"
    /// flag.fill  (Android: Flag filled)
    static let flagFill      = "flag.fill"
    /// checkmark.circle.fill  (Android: BirdwatchCheck)
    static let birdwatchCheck = "checkmark.circle.fill"
    /// circle.slash  (Android: Block)
    static let block         = "circle.slash"
    /// trash  (Android: Trash)
    static let trash         = "trash"
    /// square.and.pencil  (Android: Edit — document + pencil custom SVG)
    static let edit          = "square.and.pencil"
    /// qrcode  (Android: NuruIcons.QRCode)
    static let qrCode        = "qrcode"
    /// checkmark.circle.fill green  (Android: NuruIcons.Verified — filled green circle + white checkmark)
    static let verifiedBadge = "checkmark.circle.fill"
    /// bitcoinsign.circle  (Android: NuruIcons.Bitcoin — ₿ icon for lud16 field)
    static let bitcoin       = "bitcoinsign.circle"
    /// plus  (FAB / compose)
    static let compose       = "plus"
    /// chevron.left  (back navigation)
    static let back          = "chevron.left"
    /// chevron.down  (dropdown)
    static let chevronDown   = "chevron.down"
    /// info.circle  (Android: info)
    static let info          = "info.circle"
    /// person.fill  (avatar fallback)
    static let person        = "person.fill"
    /// person.crop.circle  (profile / logout)
    static let profileIcon   = "person.crop.circle"
    /// rectangle.portrait.and.arrow.right  (logout)
    static let logout        = "rectangle.portrait.and.arrow.right"
    /// speaker.slash.fill  (mute)
    static let mute          = "speaker.slash.fill"
    /// internaldrive  (cache)
    static let cache         = "internaldrive"

    // MARK: - State-dependent Icons

    /// Thumbs-up like — mirrors Android NuruIcons.Like(filled).
    /// NOTE: Android uses thumbs-up (not heart). iOS matches this.
    static func like(filled: Bool) -> String {
        filled ? "hand.thumbsup.fill" : "hand.thumbsup"
    }

    /// Zap / lightning bolt — mirrors Android NuruIcons.Zap(filled).
    static func zap(filled: Bool) -> String {
        filled ? "bolt.fill" : "bolt"
    }

    /// Star — mirrors Android NuruIcons.Star(filled).
    static func star(filled: Bool) -> String {
        filled ? "star.fill" : "star"
    }

    /// Bookmark — mirrors Android NuruIcons.Bookmark(filled).
    static func bookmark(filled: Bool) -> String {
        filled ? "bookmark.fill" : "bookmark"
    }

    // MARK: - Bottom Navigation Icons
    // Mirrors Android BottomTab icon assignments.

    /// Home tab — mirrors Android NuruIcons.Home(filled) which draws a house shape.
    static func home(filled: Bool) -> String {
        filled ? "house.fill" : "house"
    }

    /// Talk tab — mirrors Android NuruIcons.Talk(filled) which draws a speech bubble.
    static func talk(filled: Bool) -> String {
        filled ? "message.fill" : "message"
    }

    /// Timeline tab — mirrors Android NuruIcons.Timeline(filled).
    /// SF Symbol equivalent: "newspaper"
    static func timeline(filled: Bool) -> String {
        filled ? "newspaper.fill" : "newspaper"
    }

    /// Mini-apps grid tab — mirrors Android NuruIcons.Grid(filled).
    static func grid(filled: Bool) -> String {
        filled ? "square.grid.2x2.fill" : "square.grid.2x2"
    }
}
