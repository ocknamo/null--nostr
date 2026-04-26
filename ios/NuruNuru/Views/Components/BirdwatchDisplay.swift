import SwiftUI

// MARK: - Context type labels

private let contextTypeLabels: [String: String] = [
    "misleading":       "誤解を招く情報",
    "missing_context":  "背景情報が不足",
    "factual_error":    "事実誤認",
    "outdated":         "古い情報",
    "satire":           "風刺・ジョーク"
]

// MARK: - BirdwatchDisplay

/// Birdwatch (context notes) display component.
/// Mirrors Android BirdwatchDisplay composable.
///
/// 使い方:
/// - `notes` を直接渡すか、`repository` + `eventId` を渡して自己ロードさせる。
struct BirdwatchDisplay: View {

    var notes:          [NostrEvent]              = []
    var repository:     NostrRepository?           = nil
    var eventId:        String?                    = nil
    var onRate:         (String, String) -> Void   = { _, _ in }
    var onAuthorClick:  (String) -> Void           = { _ in }

    @State private var fetchedNotes: [NostrEvent] = []
    @State private var isExpanded = false
    @Environment(\.nuruTheme) private var theme

    private var displayNotes: [NostrEvent] {
        notes.isEmpty ? fetchedNotes : notes
    }

    private static let blue = Color(red: 0.13, green: 0.59, blue: 0.95)

    var body: some View {
        Group {
            if displayNotes.isEmpty { EmptyView() }
            else { content }
        }
        .task(id: eventId) {
            guard let repo = repository, let eid = eventId, notes.isEmpty else { return }
            let result = await repo.fetchBirdwatchNotes(eventIds: [eid])
            fetchedNotes = result[eid] ?? []
        }
    }

    private var content: some View {
        let sorted = displayNotes.sorted { $0.createdAt > $1.createdAt }
        let display = isExpanded ? sorted : Array(sorted.prefix(1))
        let hasMore = sorted.count > 1

        return VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Self.blue)
                Text("読者からの追加情報")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Self.blue)
                Spacer()
                if hasMore && !isExpanded {
                    Text("+\(sorted.count - 1)件")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textTertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Self.blue.opacity(0.05))

            // Notes
            VStack(spacing: 0) {
                ForEach(Array(display.enumerated()), id: \.element.id) { idx, note in
                    BirdwatchNoteItem(note: note, onRate: onRate, onAuthorClick: onAuthorClick)
                        .padding(.horizontal, 12)
                    if idx < display.count - 1 {
                        Divider().background(theme.borderColor)
                            .padding(.horizontal, 12)
                    }
                }
            }

            // Toggle footer
            if hasMore {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Text(isExpanded ? "折りたたむ" : "他 \(sorted.count - 1)件のコンテキストを表示")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Self.blue)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11))
                            .foregroundStyle(Self.blue)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
            }
        }
        .background(Self.blue.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Self.blue.opacity(0.2), lineWidth: 0.5)
        )
        .padding(.vertical, 4)
    }
}

// MARK: - BirdwatchNoteItem

private struct BirdwatchNoteItem: View {

    let note:          NostrEvent
    let onRate:        (String, String) -> Void
    let onAuthorClick: (String) -> Void

    @State private var ratedByMe: String? = nil
    @Environment(\.nuruTheme) private var theme

    private static let blue = Color(red: 0.13, green: 0.59, blue: 0.95)

    var body: some View {
        let contextType = note.getTagValue("l") ?? "missing_context"
        let label = contextTypeLabels[contextType]
        let sourceUrl = extractSourceUrl(note.content)
        let cleanContent = note.content
            .replacingOccurrences(of: #"https?://[^\s]+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)

        VStack(alignment: .leading, spacing: 8) {
            // Label badge
            if let label {
                Text(label)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Self.blue)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Self.blue.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            // Content
            if !cleanContent.isEmpty {
                Text(cleanContent)
                    .font(NuruFont.bodySmall())
                    .foregroundStyle(theme.textPrimary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Source URL
            if let sourceUrl {
                Button {
                    if let url = URL(string: sourceUrl) { UIApplication.shared.open(url) }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 10))
                        Text("ソースを表示")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(Self.blue)
                }
                .buttonStyle(.plain)
            }

            // Footer: author + rating
            HStack {
                Button { onAuthorClick(note.pubkey) } label: {
                    HStack(spacing: 6) {
                        Text(note.pubkey.shortenedPubkey)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(theme.textSecondary)
                        Text("·")
                            .foregroundStyle(theme.textTertiary)
                        Text(formatBirdwatchTimestamp(note.createdAt))
                            .font(.system(size: 11))
                            .foregroundStyle(theme.textSecondary)
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                if let rated = ratedByMe {
                    Text(rated == "helpful" ? "評価済み ✓" : "評価済み")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(NuruColors.lineGreen)
                } else {
                    HStack(spacing: 8) {
                        Text("役に立ちましたか？")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.textTertiary)
                        HStack(spacing: 4) {
                            rateButton("はい") {
                                ratedByMe = "helpful"
                                onRate(note.id, "helpful")
                            }
                            rateButton("いいえ") {
                                ratedByMe = "not_helpful"
                                onRate(note.id, "not_helpful")
                            }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 12)
    }

    private func rateButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(theme.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(theme.borderColor, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Helpers

private func extractSourceUrl(_ content: String) -> String? {
    let pattern = #"https?://[^\s]+"#
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
          let range = Range(match.range, in: content) else { return nil }
    return String(content[range])
}

private func formatBirdwatchTimestamp(_ unixSec: Int64) -> String {
    let diff = Int64(Date().timeIntervalSince1970) - unixSec
    switch diff {
    case ..<60:    return "たった今"
    case ..<3600:  return "\(diff / 60)分前"
    case ..<86400: return "\(diff / 3600)時間前"
    default:       return "\(diff / 86400)日前"
    }
}
