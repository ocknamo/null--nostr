import Foundation
import Observation

/// Post enriched with engagement score and UI metadata.
/// Mirrors Android ScoredPost data class.
/// Uses @Observable class so SwiftUI views (PostRow, PostHeader) automatically
/// re-render when enrichProfiles() sets post.profile — fixes pubkey-display bug.
@Observable
final class ScoredPost: Identifiable {
    let event:        NostrEvent
    var id:           String { event.id }
    var score:        Double       = 0
    var profile:      UserProfile? = nil
    var likeCount:    Int          = 0
    var zapAmount:    Int64        = 0
    var repostCount:  Int          = 0
    var replyCount:   Int          = 0
    var isLiked:      Bool         = false
    var isReposted:   Bool         = false
    var isBookmarked: Bool         = false
    var isVerified:   Bool         = false
    var badges:       [String]     = []
    /// Birdwatch / context notes associated with this post.
    var birdwatchNotes: [NostrEvent] = []
    var quotedPost:   ScoredPost?  = nil  // safe: class reference type
    var repostedBy:   UserProfile? = nil
    var repostTime:   Int64?       = nil
    /// Event ID of own like — used for toggle (unlike via Kind 5).
    var myLikeEventId:   String?   = nil
    /// Event ID of own repost — used for toggle (unrepost via Kind 5).
    var myRepostEventId: String?   = nil

    init(event: NostrEvent, score: Double = 0, profile: UserProfile? = nil) {
        self.event   = event
        self.score   = score
        self.profile = profile
    }

    /// テキスト折り畳み用: content を指定文字数で切り詰めた仮の ScoredPost を返す。
    /// 元の投稿の参照型プロパティ（profile, badges 等）を共有する。
    func truncated(to maxLength: Int) -> ScoredPost {
        let truncatedContent = String(event.content.prefix(maxLength)) + "…"
        let truncatedEvent = NostrEvent(
            id:        event.id,
            pubkey:    event.pubkey,
            createdAt: event.createdAt,
            kind:      event.kind,
            tags:      event.tags,
            content:   truncatedContent,
            sig:       event.sig
        )
        let copy = ScoredPost(event: truncatedEvent, score: score, profile: profile)
        copy.likeCount    = likeCount
        copy.zapAmount    = zapAmount
        copy.repostCount  = repostCount
        copy.replyCount   = replyCount
        copy.isLiked      = isLiked
        copy.isReposted   = isReposted
        copy.isBookmarked = isBookmarked
        copy.badges       = badges
        copy.birdwatchNotes = birdwatchNotes
        copy.quotedPost   = quotedPost
        copy.repostedBy   = repostedBy
        return copy
    }
}

// MARK: - MLS / NIP-EE Types

/// NIP-EE MLS group — mirrors Android MlsGroup.
struct MlsGroup: Identifiable, Codable {
    let groupIdHex:    String
    var id:            String { groupIdHex }
    let name:          String
    let description:   String
    let adminPubkeys:  [String]
    let memberPubkeys: [String]
    let relays:        [String]
    let createdAt:     Int64
    let epoch:         Int64
    /// MIP-01 v3 disappearing message duration in seconds.
    /// nil => disabled.
    let disappearingMessageSecs: Int64?
    let isDm:          Bool
    var memberProfiles: [String: UserProfile] = [:]
    var lastMessage:   String = ""
    var lastMessageTime: Int64 = 0
    var unreadCount:   Int = 0
}

/// Decrypted MLS application message — mirrors Android MlsMessage.
struct MlsMessage: Identifiable, Codable {
    let id:            String
    let senderPubkey:  String
    let content:       String
    let timestamp:     Int64
    let groupIdHex:    String
    var senderProfile: UserProfile? = nil
}

/// NIP-30 custom emoji entry.
struct CustomEmoji: Identifiable {
    let shortcode: String
    let url:       String
    var id:        String { shortcode }
}

/// NIP-30 custom emoji set (kind 30030).
struct EmojiSet: Identifiable {
    let id:     String
    let name:   String
    var emojis: [CustomEmoji]
}

/// NIP-58 badge awarded to a user.
struct BadgeItem: Identifiable, Codable {
    let id:          String
    let name:        String
    let description: String?
    let imageUrl:    String?
}

/// Notification item — mirrors Android NotificationItem.
struct NotificationItem: Identifiable, Codable {
    let id:            String
    let pubkey:        String
    let type:          String  // "reaction", "zap", "repost", "reply", "mention"
    let createdAt:     Int64
    var amount:        Int64?  = nil
    var comment:       String? = nil
    var targetEventId: String? = nil
    var emojiUrl:      String? = nil
    var reactionEmoji: String? = nil
}

// MARK: - Calendar / Scheduler Types (Kind 31928)

/// Chronostr スケジュールイベント — Kind 31928 に対応。
/// Mirrors Android SchedulerApp.kt の CalendarEvent データ構造。
struct CalendarEvent: Identifiable {
    let id:         String
    let title:      String
    let candidates: [DateCandidate]
    let creator:    String   // pubkey hex
    let createdAt:  Int64
    let dTag:       String   // replaceable event d-tag
}

/// 候補日エントリ。`["start", "YYYY-MM-DD", "HH:MM?"]` タグから生成される。
struct DateCandidate {
    let date:  String    // YYYY-MM-DD
    let time:  String?   // HH:MM（任意）
    let votes: [String]  // 投票済み pubkeys のリスト
}
