import UIKit

/// 画像リサイズ・圧縮・プロキシURL生成。
/// Mirrors Android ImageOptimizer.
struct ImageOptimizer {

    // MARK: - Max Dimensions

    static let maxSizeNormal:       Int = 1024
    static let maxSizeLowBandwidth: Int = 480

    // MARK: - Resize & Compress

    /// アスペクト比を保ちつつ最大サイズに収める。
    static func resize(_ image: UIImage, lowBandwidth: Bool = false) -> UIImage {
        let maxDim = CGFloat(lowBandwidth ? maxSizeLowBandwidth : maxSizeNormal)
        let size   = image.size
        guard size.width > maxDim || size.height > maxDim else { return image }
        let scale   = maxDim / max(size.width, size.height)
        let newSize = CGSize(width: (size.width * scale).rounded(),
                             height: (size.height * scale).rounded())
        return UIGraphicsImageRenderer(size: newSize).image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    /// JPEG 圧縮（帯域幅に応じた品質）。
    static func compress(_ image: UIImage, lowBandwidth: Bool = false) -> Data? {
        let quality: CGFloat = lowBandwidth ? 0.6 : 0.85
        return resize(image, lowBandwidth: lowBandwidth).jpegData(compressionQuality: quality)
    }

    // MARK: - Image Proxy URL

    /// プロキシ必要なドメイン（Instagram・Twitter・Facebook）。
    private static let proxyRequired: Set<String> = [
        "cdninstagram.com", "scontent.cdninstagram.com",
        "twimg.com", "pbs.twimg.com", "fbcdn.net"
    ]

    /// プロキシ不要な信頼済みドメイン。
    private static let trusted: Set<String> = [
        "nostr.build", "image.nostr.build", "void.cat", "blossom.nostr.build",
        "yabu.me", "imgur.com", "gravatar.com", "githubusercontent.com",
        "robohash.org", "dicebear.com"
    ]

    /// wsrv.nl 経由で最適化した画像URLを返す。
    /// - Parameters:
    ///   - url: 元画像URL
    ///   - width: リサイズ幅（nil = 帯域幅依存のデフォルト値）
    ///   - lowBandwidth: 低帯域モード（cellular等）
    static func optimizedUrl(
        _ url: String,
        width: Int?    = nil,
        lowBandwidth: Bool = false
    ) -> String {
        guard let parsed = URL(string: url), let host = parsed.host else { return url }

        let isTrusted  = trusted.contains      { host.hasSuffix($0) }
        let needsProxy = proxyRequired.contains { host.hasSuffix($0) }
        guard isTrusted || needsProxy else { return url }

        let w = width ?? (lowBandwidth ? 320 : 640)
        let q = lowBandwidth ? 60 : 85
        let encoded = url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? url
        return "https://wsrv.nl/?url=\(encoded)&w=\(w)&q=\(q)&output=webp"
    }

    /// アバター用 — 2× の円形クロップ WebP URL を返す。
    static func avatarUrl(
        _ url: String?,
        displaySize: Int  = 48,
        lowBandwidth: Bool = false
    ) -> String? {
        guard let url else { return nil }
        let px = lowBandwidth ? min(displaySize, 64) * 2 : displaySize * 2
        let encoded = url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? url
        return "https://wsrv.nl/?url=\(encoded)&w=\(px)&h=\(px)&fit=cover&mask=circle&q=80&output=webp"
    }
}
