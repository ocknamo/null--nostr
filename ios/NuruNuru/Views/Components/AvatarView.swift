import SwiftUI
import CryptoKit
import ImageIO

// MARK: - Shared Image Cache (URLCache-backed, 50 MB memory / 200 MB disk)

/// アプリ全体で共有する画像キャッシュ。
/// Android の Coil キャッシュに相当。AsyncImage のデフォルトキャッシュは不十分なため、
/// 専用 URLSession + URLCache を使用して永続的なディスクキャッシュを実現する。
/// さらにインメモリ UIImage キャッシュを追加し、LazyVStack でのセル再利用時に
/// 即時表示を実現する（onDisappear → onAppear でネットワーク再取得しない）。
final class ImageCacheManager {
    static let shared = ImageCacheManager()

    let session: URLSession

    /// インメモリ UIImage キャッシュ — LazyVStack のセル再利用時に即時表示。
    /// NSCache は自動でメモリプレッシャー時にパージする。
    private let memoryCache = NSCache<NSURL, UIImage>()

    private init() {
        let cache = URLCache(
            memoryCapacity: 50 * 1024 * 1024,   // 50 MB メモリ
            diskCapacity:   200 * 1024 * 1024    // 200 MB ディスク
        )
        let config = URLSessionConfiguration.default
        config.urlCache = cache
        config.requestCachePolicy = .returnCacheDataElseLoad
        self.session = URLSession(configuration: config)
        memoryCache.countLimit = 300   // 最大300画像をインメモリに保持
    }

    func cachedUIImage(for url: URL) -> UIImage? {
        memoryCache.object(forKey: url as NSURL)
    }

    func storeUIImage(_ image: UIImage, for url: URL) {
        memoryCache.setObject(image, forKey: url as NSURL)
    }
}

enum CachedImageContentMode {
    case fill
    case fit
}

/// Cached image view — URLCache-backed image loading with placeholder.
/// `AsyncImage` のキャッシュ不足を解消し、ディスク永続キャッシュを実現する。
///
/// 改善点:
/// - インメモリ UIImage キャッシュ: LazyVStack でセルが再表示されたとき即時描画
/// - onDisappear でタスクをキャンセルしない: スクロール中の画像ロード失敗を防止
/// - リトライロジック: ネットワークエラー時に1回リトライ
struct CachedAsyncImage<Placeholder: View>: View {
    let url: URL?
    let authorPubkey: String?
    let contentMode: CachedImageContentMode
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var image: Image?
    @State private var loadTask: Task<Void, Never>?
    @State private var failedAt: Date? = nil

    init(
        url: URL?,
        authorPubkey: String? = nil,
        contentMode: CachedImageContentMode = .fill,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.authorPubkey = authorPubkey
        self.contentMode = contentMode
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let image {
                switch contentMode {
                case .fill:
                    image.resizable().scaledToFill()
                case .fit:
                    image.resizable().scaledToFit()
                }
            } else {
                placeholder()
            }
        }
        .onAppear { loadIfNeeded(force: false) }
        .onChange(of: url) { _, _ in
            loadTask?.cancel()
            image = nil
            failedAt = nil
            loadIfNeeded(force: true)
        }
        .task(id: url) {
            // 一度失敗しても一定時間後に自動リトライして復旧させる
            while image == nil {
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                guard !Task.isCancelled else { break }
                if failedAt != nil {
                    loadIfNeeded(force: true)
                }
            }
        }
        // onDisappear: タスクをキャンセルしない。
        // LazyVStack ではセルがスクロールアウトすると onDisappear が呼ばれるが、
        // ロード中にキャンセルすると再表示時に画像が表示されない問題が発生していた。
    }

    private func loadIfNeeded(force: Bool) {
        guard image == nil, let url else { return }
        if !force, failedAt != nil { return }
        // 1. インメモリキャッシュから即時取得（ネットワーク不要）
        if let cached = ImageCacheManager.shared.cachedUIImage(for: url) {
            self.image = Image(uiImage: cached)
            self.failedAt = nil
            return
        }
        // 2. URLSession（URLCache ディスクキャッシュ → ネットワーク）
        loadTask = Task {
            await loadImage(url: url, retryCount: 2)
        }
    }

    private func loadImage(url: URL, retryCount: Int) async {
        do {
            try await loadPrimaryOrFallback(url: url)
            self.failedAt = nil
        } catch {
            if retryCount > 0 && !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(700))
                guard !Task.isCancelled else { return }
                await loadImage(url: url, retryCount: retryCount - 1)
                return
            }
            self.failedAt = Date()
        }
    }

    private func loadPrimaryOrFallback(url: URL) async throws {
        do {
            // Primary URL should behave like legacy loader (no hash enforcement),
            // so non-Blossom/CDN URLs keep working.
            let ui = try await fetchImageNoVerify(url: url)
            guard !Task.isCancelled else { return }
            ImageCacheManager.shared.storeUIImage(ui, for: url)
            self.image = Image(uiImage: ui)
            return
        } catch {
            // NIP-B7 / BUD-03 fallback: if source URL fails, try author's kind:10063 servers.
            guard let authorPubkey,
                  BlossomB7Resolver.extractLastSha256Hex(from: url.absoluteString) != nil else {
                throw error
            }
            let fallbackUrls = await BlossomB7Resolver.shared.fallbackUrls(for: url, authorPubkey: authorPubkey)
            guard !fallbackUrls.isEmpty else { throw error }

            let expectedHash = BlossomB7Resolver.extractLastSha256Hex(from: url.absoluteString)
            for fallback in fallbackUrls {
                do {
                    // Fallback blobs are hash-addressed; enforce SHA-256 integrity here.
                    let ui = try await fetchVerifiedImage(url: fallback, expectedHash: expectedHash)
                    guard !Task.isCancelled else { return }
                    ImageCacheManager.shared.storeUIImage(ui, for: fallback)
                    // also cache under original URL key to avoid repeating fallback work
                    ImageCacheManager.shared.storeUIImage(ui, for: url)
                    self.image = Image(uiImage: ui)
                    return
                } catch {
                    continue
                }
            }
            throw error
        }
    }

    private func fetchImageNoVerify(url: URL) async throws -> UIImage {
        let (data, resp) = try await fetchData(url: url, ignoreCache: false)
        if let http = resp as? HTTPURLResponse,
           !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        if let uiImage = decodeImage(data) {
            return uiImage
        }

        // キャッシュ破損/古いレスポンスを疑い、キャッシュ無視で1回だけ再取得
        let (freshData, freshResp) = try await fetchData(url: url, ignoreCache: true)
        if let http = freshResp as? HTTPURLResponse,
           !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        guard let uiImage = decodeImage(freshData) else {
            throw URLError(.cannotDecodeContentData)
        }
        return uiImage
    }

    private func fetchVerifiedImage(url: URL, expectedHash: String?) async throws -> UIImage {
        var (data, resp) = try await fetchData(url: url, ignoreCache: false)
        if let http = resp as? HTTPURLResponse,
           !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }

        // NIP-B7: fallback blob retrieval via hash-addressed URLs should verify integrity.
        if let expectedHash {
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            if digest.lowercased() != expectedHash.lowercased() {
                // キャッシュ不整合を疑って再取得して再検証
                (data, resp) = try await fetchData(url: url, ignoreCache: true)
                if let http = resp as? HTTPURLResponse,
                   !(200..<300).contains(http.statusCode) {
                    throw URLError(.badServerResponse)
                }
                let digest2 = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                guard digest2.lowercased() == expectedHash.lowercased() else {
                    throw URLError(.cannotDecodeRawData)
                }
            }
        }

        if let uiImage = decodeImage(data) {
            return uiImage
        }

        // デコード失敗時もキャッシュ無視で再試行
        let (freshData, freshResp) = try await fetchData(url: url, ignoreCache: true)
        if let http = freshResp as? HTTPURLResponse,
           !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        guard let uiImage = decodeImage(freshData) else {
            throw URLError(.cannotDecodeContentData)
        }
        return uiImage
    }

    private func fetchData(url: URL, ignoreCache: Bool) async throws -> (Data, URLResponse) {
        if ignoreCache {
            var req = URLRequest(url: url)
            req.cachePolicy = .reloadIgnoringLocalCacheData
            return try await ImageCacheManager.shared.session.data(for: req)
        }
        return try await ImageCacheManager.shared.session.data(from: url)
    }

    private func decodeImage(_ data: Data) -> UIImage? {
        if let ui = UIImage(data: data) { return ui }
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            return nil
        }
        return UIImage(cgImage: cg)
    }
}

/// Circular avatar — cached image when URL is available, initial-letter fallback otherwise.
/// Used across PostRow, PostSheet, HomeView, ZapSheet, etc.
struct AvatarView: View {
    let url:  String?
    let name: String
    let size: CGFloat

    @Environment(\.nuruTheme) private var theme

    var body: some View {
        Group {
            if let imageURL = normalizedImageURL(from: url) {
                CachedAsyncImage(url: imageURL) {
                    fallbackView
                }
            } else {
                fallbackView
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var fallbackView: some View {
        ZStack {
            Circle().fill(theme.bgTertiary)
            Image(systemName: "person.fill")
                .font(.system(size: size * 0.55))
                .foregroundStyle(theme.textTertiary)
        }
    }

    private func normalizedImageURL(from raw: String?) -> URL? {
        guard var s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else {
            return nil
        }
        if s.hasPrefix("//") {
            s = "https:" + s
        }
        if !(s.hasPrefix("http://") || s.hasPrefix("https://")) {
            return nil
        }
        if let encoded = s.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed),
           let u = URL(string: encoded),
           let scheme = u.scheme?.lowercased(),
           (scheme == "http" || scheme == "https") {
            return u
        }
        return nil
    }
}


// MARK: - NIP-B7 / BUD-03 fallback resolver (local)

actor BlossomB7Resolver {
    static let shared = BlossomB7Resolver()

    private let client = NostrClient()
    private var connected = false
    private var serverCache: [String: [String]] = [:]

    private init() {}

    func fallbackUrls(for originalURL: URL, authorPubkey: String) async -> [URL] {
        let source = originalURL.absoluteString
        guard let hash = Self.extractLastSha256Hex(from: source) else { return [] }
        let ext = Self.extractExtensionAfterHash(from: source, hash: hash)

        let servers = await userServers(pubkey: authorPubkey)
        guard !servers.isEmpty else { return [] }

        var out: [URL] = []
        for base in servers {
            let trimmed = base.hasSuffix("/") ? String(base.dropLast()) : base
            if let u = URL(string: "\(trimmed)/\(hash)") { out.append(u) }
            if let ext, !ext.isEmpty,
               let u = URL(string: "\(trimmed)/\(hash).\(ext)") { out.append(u) }
        }

        var seen = Set<String>()
        return out.filter { seen.insert($0.absoluteString).inserted }
    }

    func userServers(pubkey: String) async -> [String] {
        if let cached = serverCache[pubkey], !cached.isEmpty { return cached }
        await ensureConnected()

        let filter = NostrFilter(ids: nil, authors: [pubkey], kinds: [NostrKind.blossomUserServerList], since: nil, until: nil, limit: 1, tags: nil, search: nil)
        let events = await client.fetchEvents(filters: [filter], timeoutSeconds: 6.0).sorted { $0.createdAt > $1.createdAt }
        guard let latest = events.first else { return [] }

        var out: [String] = []
        var seen = Set<String>()
        for tag in latest.tags where tag.first == "server" {
            guard tag.count > 1 else { continue }
            guard let n = Self.normalizedServerUrl(tag[1]) else { continue }
            let k = n.lowercased()
            if seen.insert(k).inserted { out.append(n) }
        }
        serverCache[pubkey] = out
        return out
    }

    private func ensureConnected() async {
        if connected { return }
        await client.connect(relayUrls: defaultRelays)
        connected = true
    }

    static func extractLastSha256Hex(from text: String) -> String? {
        let pattern = "[0-9a-fA-F]{64}"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard let last = matches.last else { return nil }
        return ns.substring(with: last.range).lowercased()
    }

    private static func extractExtensionAfterHash(from text: String, hash: String) -> String? {
        let lower = text.lowercased()
        guard let r = lower.range(of: hash.lowercased(), options: .backwards) else { return nil }
        let suffix = lower[r.upperBound...]
        guard suffix.hasPrefix(".") else { return nil }
        let ext = suffix.dropFirst().prefix { $0.isLetter || $0.isNumber }
        let e = String(ext)
        return e.isEmpty ? nil : e
    }

    static func normalizedServerUrl(_ raw: String) -> String? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        let withScheme = (t.hasPrefix("http://") || t.hasPrefix("https://")) ? t : "https://\(t)"
        guard var c = URLComponents(string: withScheme),
              let scheme = c.scheme?.lowercased(), ["http", "https"].contains(scheme), c.host != nil else { return nil }
        c.scheme = scheme
        c.query = nil
        c.fragment = nil
        let path = c.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        c.path = path.isEmpty ? "" : "/\(path)"
        return c.string
    }
}
