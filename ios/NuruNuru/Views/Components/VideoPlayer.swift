import SwiftUI
import AVKit
import AVFoundation

/// Auto-looping video player with mute toggle and scroll-aware playback.
///
/// LazyVStack 内での使用を想定し、.onAppear/.onDisappear で再生/停止を管理。
/// プレイヤー生成は画面内に入ったときのみ行い、スクロールアウト時に解放してメモリを節約。
/// Mirrors Android VideoPlayer.kt (ExoPlayer → AVQueuePlayer + AVPlayerLooper).
struct VideoPlayer: View {

    let videoUrl: String

    @State private var muted:      Bool              = true
    @State private var player:     AVQueuePlayer?    = nil
    @State private var looper:     AVPlayerLooper?   = nil
    @State private var isReady:    Bool              = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // ─── Video Layer ──────────────────────────────────────────────
            if let player {
                VideoPlayerLayerView(player: player)
                    .clipped()
                    .transition(.opacity)
            } else {
                // ローディングプレースホルダー
                Color.black
                    .overlay(
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.8)
                    )
            }

            // ─── タップでミュート切替 ─────────────────────────────────────
            // Android: Box の clickable { } ミュートトグルに対応
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    muted.toggle()
                    player?.volume = muted ? 0 : 1
                }

            // ─── ミュートインジケーター（右下）────────────────────────────
            Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 12))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Color.black.opacity(0.5))
                .clipShape(Circle())
                .padding(8)
                .allowsHitTesting(false)
        }
        // ─── ライフサイクル管理 ─────────────────────────────────────────
        // LazyVStack: 画面内に入ったとき初めてプレイヤーを生成、出たとき解放
        .onAppear  { setupPlayer() }
        .onDisappear { teardownPlayer() }
        .onChange(of: videoUrl) { _, _ in
            teardownPlayer()
            setupPlayer()
        }
        .background(Color.black)
        .animation(.easeInOut(duration: 0.2), value: player != nil)
    }

    // MARK: - Player Lifecycle

    /// プレイヤーを初期化して再生開始。
    /// Android: ExoPlayer.Builder().build() + setMediaItem() + prepare() に対応。
    private func setupPlayer() {
        guard player == nil, let url = URL(string: videoUrl) else { return }

        let item        = AVPlayerItem(url: url)
        let queuePlayer = AVQueuePlayer(items: [item])
        queuePlayer.volume = 0              // ミュートで自動再生
        queuePlayer.actionAtItemEnd = .none // looper が管理

        let pl = AVPlayerLooper(player: queuePlayer, templateItem: item)

        // iOS のバックグラウンド再生を適切に無効化
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)

        looper = pl
        player = queuePlayer
        queuePlayer.play()
    }

    /// プレイヤーを停止して解放（スクロールアウト時）。
    /// Android: DisposableEffect { onDispose { exoPlayer.release() } } に対応。
    private func teardownPlayer() {
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        looper = nil
        player = nil
        isReady = false
    }
}

// MARK: - AVPlayerLayer Bridge (UIViewRepresentable)

/// AVPlayerLayer を使った軽量ビデオ表示。
/// AVPlayerViewController より軽量でスクロールパフォーマンスが向上する。
/// Android: PlayerView (ExoPlayer UI) に対応。
private struct VideoPlayerLayerView: UIViewRepresentable {

    let player: AVQueuePlayer

    func makeUIView(context: Context) -> PlayerLayerUIView {
        let view = PlayerLayerUIView()
        view.player = player
        return view
    }

    func updateUIView(_ uiView: PlayerLayerUIView, context: Context) {
        uiView.player = player
    }
}

// MARK: - PlayerLayerUIView

final class PlayerLayerUIView: UIView {

    private var playerLayer: AVPlayerLayer

    override init(frame: CGRect) {
        playerLayer = AVPlayerLayer()
        playerLayer.videoGravity = .resizeAspectFill
        super.init(frame: frame)
        layer.addSublayer(playerLayer)
        backgroundColor = .black
    }

    required init?(coder: NSCoder) { fatalError() }

    var player: AVQueuePlayer? {
        get { playerLayer.player as? AVQueuePlayer }
        set { playerLayer.player = newValue }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }
}
