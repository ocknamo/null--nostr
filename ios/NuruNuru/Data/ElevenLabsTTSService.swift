import AVFoundation
import Foundation

/// ElevenLabs Text-to-Speech サービス。
/// 投稿テキストを音声合成し AVAudioPlayer で再生する。
/// Mirrors Android ElevenLabsSettings.kt の TTS 機能。
///
/// 使用法:
///   try await ElevenLabsTTSService.shared.speak(text: content, apiKey: key)
///   ElevenLabsTTSService.shared.stop()
final class ElevenLabsTTSService: NSObject {

    static let shared = ElevenLabsTTSService()

    /// ElevenLabs デフォルト音声 ID (Rachel — multilingual 対応)
    private let defaultVoiceId = "21m00Tcm4TlvDq8ikWAM"

    private var player: AVAudioPlayer?
    private(set) var isPlaying: Bool = false

    private override init() { super.init() }

    // MARK: - Public API

    /// テキストを音声合成して再生する。
    ///
    /// - Parameters:
    ///   - text:   読み上げるテキスト
    ///   - apiKey: ElevenLabs xi-api-key
    /// - Throws: `TTSError`
    func speak(text: String, apiKey: String) async throws {
        guard !apiKey.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw TTSError.noApiKey
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        stop()  // 再生中なら停止

        let urlStr = "https://api.elevenlabs.io/v1/text-to-speech/\(defaultVoiceId)"
        guard let url = URL(string: urlStr) else { throw TTSError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey,             forHTTPHeaderField: "xi-api-key")
        request.timeoutInterval = 15

        let body: [String: Any] = [
            "text":     trimmed,
            "model_id": "eleven_multilingual_v2"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else { throw TTSError.invalidResponse }
        guard http.statusCode == 200 else { throw TTSError.apiError(http.statusCode) }

        await MainActor.run {
            do {
                #if os(iOS) || os(tvOS) || os(watchOS)
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
                try AVAudioSession.sharedInstance().setActive(true)
                #endif
                player = try AVAudioPlayer(data: data)
                player?.delegate = self
                player?.play()
                isPlaying = true
            } catch {
                isPlaying = false
            }
        }
    }

    /// 再生を停止する。
    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
    }

    // MARK: - Errors

    enum TTSError: Error, LocalizedError {
        case noApiKey
        case invalidURL
        case invalidResponse
        case apiError(Int)

        var errorDescription: String? {
            switch self {
            case .noApiKey:         return "APIキーが設定されていません"
            case .invalidURL:       return "URLエラー"
            case .invalidResponse:  return "レスポンスエラー"
            case .apiError(let c):  return "APIエラー (HTTP \(c))"
            }
        }
    }
}

// MARK: - AVAudioPlayerDelegate

extension ElevenLabsTTSService: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isPlaying = false
        self.player = nil
    }
}
