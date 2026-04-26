import Foundation
import UIKit
import CryptoKit

// MARK: - Upload Server

/// アップロード先サーバーの種別。
/// Android: `ImageUploadUtils.kt` の upload* 関数群に対応。
enum UploadServer: String, CaseIterable, Identifiable, Codable {
    case nostrBuild = "nostr.build"
    case yabuMe     = "share.yabu.me"
    case blossom    = "blossom"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .nostrBuild: return "nostr.build"
        case .yabuMe:     return "share.yabu.me"
        case .blossom:    return "Blossom"
        }
    }

    /// デフォルトの Blossom サーバー URL。
    static let defaultBlossomUrl = "https://blossom.nostr.build"

    init(rawValueOrDefault raw: String) {
        self = UploadServer(rawValue: raw) ?? .nostrBuild
    }
}

// MARK: - Upload Errors

enum ImageUploadError: LocalizedError {
    case compressionFailed
    case invalidUrl(String)
    case httpError(Int)
    case noUrl
    case timeout
    case signingFailed

    var errorDescription: String? {
        switch self {
        case .compressionFailed:    return "画像の圧縮に失敗しました"
        case .invalidUrl(let u):    return "不正なURL: \(u)"
        case .httpError(let code):  return "サーバーエラー (HTTP \(code))"
        case .noUrl:                return "アップロードURLを取得できませんでした"
        case .timeout:              return "アップロードがタイムアウトしました"
        case .signingFailed:        return "NIP-98 認証に失敗しました"
        }
    }
}

// MARK: - Image Upload Service

/// マルチサーバー画像アップロードサービス。
///
/// NIP-98 HTTP 認証（Kind 27235）付きで nostr.build / share.yabu.me / Blossom に対応。
/// Android: `ImageUploadUtils.kt` に対応。
struct ImageUploadService {

    private let signer: InternalSigner?

    /// タイムアウト（Android と同じ 30s）。
    private let timeoutInterval: TimeInterval = 30

    init(signer: InternalSigner?) {
        self.signer = signer
    }

    // MARK: - Compress

    /// JPEG 圧縮（最大幅 `maxSize`px、品質 `quality`）。
    /// Android: `ImageOptimizer.compress()` に対応。
    func compressImage(data: Data, maxSize: Int = 1920, quality: CGFloat = 0.85) -> Data {
        guard let image = UIImage(data: data) else { return data }

        // リサイズ
        let size = image.size
        let maxDim = CGFloat(maxSize)
        let resized: UIImage
        if size.width > maxDim || size.height > maxDim {
            let scale   = maxDim / max(size.width, size.height)
            let newSize = CGSize(width: (size.width * scale).rounded(),
                                 height: (size.height * scale).rounded())
            resized = UIGraphicsImageRenderer(size: newSize).image { _ in
                image.draw(in: CGRect(origin: .zero, size: newSize))
            }
        } else {
            resized = image
        }

        let compressed = resized.jpegData(compressionQuality: quality) ?? data
        // 圧縮結果が元データより大きい場合は元データをそのまま使用する
        // （既に最適化済みの JPEG を再圧縮すると逆にサイズが増えるケースがある）
        if compressed.count > data.count {
            AppLogger.log("Upload", "Compression produced larger output (\(data.count) → \(compressed.count)), using original")
            return data
        }
        return compressed
    }

    // MARK: - Upload (single image)

    /// 単一画像をアップロードして URL を返す。
    /// - Parameters:
    ///   - imageData: JPEG / PNG バイナリ
    ///   - server: アップロード先サーバー
    ///   - blossomBaseUrl: Blossom 選択時のベース URL（デフォルト: blossom.nostr.build）
    ///   - mimeType: MIME タイプ（デフォルト: image/jpeg）
    func uploadImage(
        imageData:      Data,
        server:         UploadServer,
        blossomBaseUrl: String = UploadServer.defaultBlossomUrl,
        mimeType:       String = "image/jpeg"
    ) async throws -> String {
        switch server {
        case .nostrBuild: return try await uploadToNostrBuild(data: imageData, mimeType: mimeType)
        case .yabuMe:     return try await uploadToYabuMe(data: imageData, mimeType: mimeType)
        case .blossom:    return try await uploadToBlossom(data: imageData, mimeType: mimeType,
                                                           baseUrl: blossomBaseUrl)
        }
    }

    // MARK: - nostr.build

    /// POST https://nostr.build/api/v2/upload/files
    /// NIP-98 認証ヘッダー付き multipart/form-data。
    private func uploadToNostrBuild(data: Data, mimeType: String) async throws -> String {
        let endpoint = "https://nostr.build/api/v2/upload/files"
        var request  = try buildMultipartRequest(endpoint: endpoint, data: data, mimeType: mimeType)
        try addNip98Auth(to: &request, url: endpoint, method: "POST")

        let (resp, http) = try await urlSession.data(for: request)
        let code = (http as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw ImageUploadError.httpError(code) }

        // nostr.build V2 レスポンス: {"status":"success","data":[{"url":"..."}]}
        struct V2: Decodable {
            struct Item: Decodable { let url: String? }
            let status: String?
            let data:   [Item]?
            let url:    String?          // fallback
        }
        let decoded = try JSONDecoder().decode(V2.self, from: resp)
        if let u = decoded.data?.first?.url { return u }
        if let u = decoded.url { return u }
        throw ImageUploadError.noUrl
    }

    // MARK: - share.yabu.me

    /// POST https://share.yabu.me/api/v2/media
    /// multipart/form-data。NIP-98 認証ヘッダー付き。
    private func uploadToYabuMe(data: Data, mimeType: String) async throws -> String {
        let endpoint = "https://share.yabu.me/api/v2/media"
        var request  = try buildMultipartRequest(endpoint: endpoint, data: data, mimeType: mimeType)
        try addNip98Auth(to: &request, url: endpoint, method: "POST")

        let (resp, http) = try await urlSession.data(for: request)
        let code = (http as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw ImageUploadError.httpError(code) }

        // NIP-94 互換レスポンス
        struct R: Decodable {
            struct Nip94: Decodable { let tags: [[String]] }
            let status: String?; let nip94_event: Nip94?; let url: String?
        }
        let decoded = try JSONDecoder().decode(R.self, from: resp)
        if let u = decoded.url { return u }
        if let u = decoded.nip94_event?.tags
            .first(where: { $0.first == "url" })?[safe: 1] { return u }
        throw ImageUploadError.noUrl
    }

    // MARK: - Blossom (NIP-96)

    /// PUT https://{server}/upload
    /// NIP-98 認証ヘッダー付き（Kind 24242 相当）。
    /// Android: `ImageUploadUtils.uploadToBlossom()` に対応。
    private func uploadToBlossom(data: Data, mimeType: String, baseUrl: String) async throws -> String {
        let normalized = baseUrl.hasSuffix("/") ? String(baseUrl.dropLast()) : baseUrl
        let endpoint   = "\(normalized)/upload"
        guard URL(string: endpoint) != nil else { throw ImageUploadError.invalidUrl(endpoint) }

        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "PUT"
        request.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        request.httpBody   = data
        request.timeoutInterval = timeoutInterval
        try addNip98Auth(to: &request, url: endpoint, method: "PUT")

        let (resp, http) = try await urlSession.data(for: request)
        let code = (http as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw ImageUploadError.httpError(code) }

        struct R: Decodable { let url: String? }
        if let u = (try? JSONDecoder().decode(R.self, from: resp))?.url { return u }
        throw ImageUploadError.noUrl
    }

    // MARK: - NIP-98 HTTP Auth (Kind 27235)

    /// Authorization: Nostr <base64(Kind 27235 event JSON)>
    /// Android: `requestBuilder.addHeader("Authorization", "Nostr $authHeader")` に対応。
    private func addNip98Auth(to request: inout URLRequest, url: String, method: String) throws {
        guard let signer else { return }   // 認証なしの場合はスキップ
        guard let event = try? signer.signEvent(
            kind:    27235,
            tags:    [["u", url], ["method", method]],
            content: ""
        ) else { throw ImageUploadError.signingFailed }

        // NIP-98 サーバーは NIP-01 準拠の JSON フィールド順序を期待する。
        // JSONEncoder はキーをアルファベット順にするため、手動で正しい順序の JSON を構築する。
        // Android: Rust FFI の .asJson() が同じ順序を保証している。
        let tagsJson = "[" + event.tags.map { tag in
            "[" + tag.map { "\"\($0.nip98Escaped)\"" }.joined(separator: ",") + "]"
        }.joined(separator: ",") + "]"

        // 重要: 改行やインデントを含めないように1行で構築する
        let jsonString = "{\"id\":\"\(event.id)\",\"pubkey\":\"\(event.pubkey)\",\"created_at\":\(event.createdAt),\"kind\":\(event.kind),\"tags\":\(tagsJson),\"content\":\"\(event.content.nip98Escaped)\",\"sig\":\"\(event.sig)\"}"

        guard let jsonData = jsonString.data(using: .utf8) else { throw ImageUploadError.signingFailed }
        let b64 = jsonData.base64EncodedString()
        request.setValue("Nostr \(b64)", forHTTPHeaderField: "Authorization")
    }

    // MARK: - Multipart Builder

    private func buildMultipartRequest(endpoint: String, data: Data, mimeType: String) throws -> URLRequest {
        guard let url = URL(string: endpoint) else { throw ImageUploadError.invalidUrl(endpoint) }
        var request  = URLRequest(url: url)
        request.httpMethod      = "POST"
        request.timeoutInterval = timeoutInterval

        let boundary = "NuruNuru-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)",
                         forHTTPHeaderField: "Content-Type")

        let ext = mimeType == "image/png" ? "png" : "jpg"
        var body = Data()
        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"file\"; filename=\"upload.\(ext)\"\r\n")
        body.appendString("Content-Type: \(mimeType)\r\n\r\n")
        body.append(data)
        body.appendString("\r\n--\(boundary)--\r\n")
        request.httpBody = body
        return request
    }

    // MARK: - URLSession

    private var urlSession: URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest  = timeoutInterval
        config.timeoutIntervalForResource = timeoutInterval
        return URLSession(configuration: config)
    }
}

// MARK: - Parallel Upload Helper

extension ImageUploadService {

    /// 複数画像を並列アップロード（最大3枚同時）。
    /// Android: `PostModal.kt` の `async { } / awaitAll()` パターンに対応。
    ///
    /// - Returns: 成功した URL のリスト（失敗したものはスキップ）。
    func uploadImages(
        _ images:       [UIImage],
        server:         UploadServer,
        blossomBaseUrl: String = UploadServer.defaultBlossomUrl,
        onProgress:     @escaping @Sendable (Int, Int) -> Void = { _, _ in }
    ) async -> [String] {
        var urls: [String?] = Array(repeating: nil, count: images.count)
        let total = images.count

        await withTaskGroup(of: (Int, String?).self) { group in
            for (i, image) in images.enumerated() {
                group.addTask {
                    await onProgress(i + 1, total)
                    // iOS カメラの HEIC/HEIF 画像は jpegData() で nil を返す場合がある。
                    // UIImage を再描画して確実に JPEG に変換する。
                    let rawData: Data
                    if let jpeg = image.jpegData(compressionQuality: 0.92), !jpeg.isEmpty {
                        rawData = jpeg
                    } else {
                        // HEIC→JPEG フォールバック: UIGraphicsImageRenderer で再描画
                        let renderer = UIGraphicsImageRenderer(size: image.size, format: {
                            let fmt = UIGraphicsImageRendererFormat()
                            fmt.preferredRange = .standard  // sRGB (ICC プロフィール互換)
                            return fmt
                        }())
                        rawData = renderer.jpegData(withCompressionQuality: 0.92) { ctx in
                            image.draw(in: CGRect(origin: .zero, size: image.size))
                        }
                        AppLogger.log("Upload", "Image \(i+1): HEIC→JPEG fallback conversion (\(rawData.count) bytes)")
                    }
                    guard !rawData.isEmpty else {
                        AppLogger.log("Upload", "Image \(i+1): compression produced empty data, skipping")
                        return (i, nil)
                    }
                    let data = self.compressImage(
                        data:     rawData,
                        maxSize:  1920,
                        quality:  0.85
                    )
                    AppLogger.log("Upload", "Image \(i+1)/\(total): \(rawData.count) bytes → \(data.count) bytes compressed")
                    do {
                        let url = try await self.uploadImage(
                            imageData: data,
                            server:    server,
                            blossomBaseUrl: blossomBaseUrl
                        )
                        AppLogger.log("Upload", "Image \(i+1) uploaded: \(url)")
                        return (i, url)
                    } catch {
                        AppLogger.log("Upload", "Image \(i+1) upload failed: \(error.localizedDescription)")
                        return (i, nil)
                    }
                }
            }
            for await (i, url) in group {
                urls[i] = url
            }
        }
        return urls.compactMap { $0 }
    }
}

// MARK: - Data Helper

private extension Data {
    mutating func appendString(_ s: String) {
        if let d = s.data(using: .utf8) { append(d) }
    }
}

// MARK: - NIP-98 JSON Escape

private extension String {
    /// NIP-01 準拠の JSON エスケープ（NIP-98 認証ヘッダー用）。
    var nip98Escaped: String {
        var result = ""
        for ch in self {
            switch ch {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            default:
                let scalar = ch.unicodeScalars.first!.value
                if scalar < 0x20 {
                    result += String(format: "\\u%04x", scalar)
                } else {
                    result.append(ch)
                }
            }
        }
        return result
    }
}

