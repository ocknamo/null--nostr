import Foundation

extension Collection {
    /// Safe index subscript — returns nil if out of bounds.
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

extension String {
    /// Convert an NSRange to a Range<String.Index> in this string.
    func range(from nsRange: NSRange) -> Range<String.Index>? {
        Range(nsRange, in: self)
    }
}

extension Int64 {
    /// Human-readable relative time — 今 / Xm / Xh / Xd / M/d.
    var relativeTimeString: String {
        let diff = Int64(Date().timeIntervalSince1970) - self
        if diff < 60      { return "今" }
        if diff < 3600    { return "\(diff / 60)m" }
        if diff < 86400   { return "\(diff / 3600)h" }
        if diff < 604800  { return "\(diff / 86400)d" }
        let fmt = DateFormatter()
        fmt.dateFormat = "M/d"
        return fmt.string(from: Date(timeIntervalSince1970: TimeInterval(self)))
    }
}

extension String {
    /// Abbreviates a hex pubkey to "prefix6…suffix4".
    var shortenedPubkey: String {
        guard count >= 12 else { return self }
        return String(prefix(6)) + "…" + String(suffix(4))
    }
}
