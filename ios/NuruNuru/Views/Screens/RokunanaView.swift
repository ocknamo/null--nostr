import SwiftUI
import PhotosUI
import AVKit
import AVFoundation

struct RokunanaView: View {
    @Bindable var viewModel: RokunanaViewModel
    var onProfileTap: (String) -> Void = { _ in }
    var onZap: (ScoredPost) -> Void = { _ in }

    @State private var showComposer = false
    @State private var isMuted = true

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if viewModel.isLoading && viewModel.posts.isEmpty {
                ProgressView("読み込み中…")
                    .tint(.white)
                    .foregroundStyle(.white)
            } else if viewModel.posts.isEmpty {
                emptyView
            } else {
                GeometryReader { geo in
                    TabView {
                        ForEach(viewModel.posts) { post in
                            RokunanaVideoPage(
                                post: post,
                                height: geo.size.height,
                                muted: $isMuted,
                                isOwnPost: post.event.pubkey == viewModel.myPubkeyHex,
                                onProfileTap: onProfileTap,
                                onLike: { await viewModel.toggleLike(post: post) },
                                onRepost: { await viewModel.toggleRepost(post: post) },
                                onZap: { onZap(post) },
                                onBookmark: { await viewModel.toggleBookmark(post: post) },
                                onNotInterested: { viewModel.notInterested(post: post) },
                                onDelete: { await viewModel.deletePost(post) },
                                onMute: { await viewModel.muteUser(post.event.pubkey) },
                                onReport: { type, content in await viewModel.reportEvent(post: post, type: type, content: content) },
                                onBirdwatch: { type, content, url in await viewModel.submitBirdwatch(post: post, type: type, content: content, url: url) }
                            )
                            .id(post.event.id)
                            .rotationEffect(.degrees(-90))
                            .frame(width: geo.size.width, height: geo.size.height)
                        }
                    }
                    .rotationEffect(.degrees(90))
                    .frame(width: geo.size.height, height: geo.size.width)
                    .offset(x: (geo.size.width - geo.size.height) / 2, y: (geo.size.height - geo.size.width) / 2)
                    .tabViewStyle(.page(indexDisplayMode: .never))
                }
            }

            topOverlay
        }
        .task { viewModel.startInitialLoadIfNeeded() }
        .sheet(isPresented: $showComposer) {
            RokunanaPostSheet(viewModel: viewModel, onDismiss: { showComposer = false })
        }
    }

    private var topOverlay: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                ForEach(RokunanaFeedMode.allCases) { mode in
                    Button {
                        viewModel.setMode(mode)
                    } label: {
                        Text(mode.label)
                            .font(.custom(NuruFont.bold, size: 16, relativeTo: .headline))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .layoutPriority(3)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 10)
                            .background(
                                Capsule().fill(viewModel.mode == mode ? Color.black.opacity(0.72) : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 4)

                Button {
                    showComposer = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Color.black.opacity(0.45)))
                }

                Text("LIVE")
                    .font(.custom(NuruFont.bold, size: 10, relativeTo: .caption2))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .overlay(Capsule().stroke(.white, lineWidth: 1.4))

                Image(systemName: "person.crop.circle")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(viewModel.categories, id: \.self) { category in
                        Button {
                            viewModel.selectedCategory = category
                        } label: {
                            Text(category)
                                .font(NuruFont.bodyMedium())
                                .fontWeight(.bold)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 12)
                                .background(
                                    Capsule().fill(viewModel.selectedCategory == category ? NuruColors.lineGreen : Color.black.opacity(0.45))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }

            Spacer()
        }
        .allowsHitTesting(true)
    }

    private var emptyView: some View {
        VStack(spacing: 14) {
            Text("67")
                .font(.custom(NuruFont.bold, size: 48, relativeTo: .largeTitle))
                .foregroundStyle(.white)
            Text("ろくなな")
                .font(NuruFont.titleLarge())
                .foregroundStyle(.white)
            Text("divine のショート動画がまだありません")
                .font(NuruFont.bodyMedium())
                .foregroundStyle(.white.opacity(0.7))
            Button("動画を投稿") { showComposer = true }
                .font(NuruFont.bodyMedium())
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(Capsule().fill(NuruColors.lineGreen))
        }
        .padding(.horizontal, 24)
    }
}

private struct RokunanaVideoPage: View {
    let post: ScoredPost
    let height: CGFloat
    @Binding var muted: Bool
    let isOwnPost: Bool
    var onProfileTap: (String) -> Void
    var onLike: () async -> Void
    var onRepost: () async -> Void
    var onZap: () -> Void
    var onBookmark: () async -> Void
    var onNotInterested: () -> Void
    var onDelete: () async -> Void
    var onMute: () async -> Void
    var onReport: (String, String) async -> Void
    var onBirdwatch: (String, String, String) async -> Void

    @State private var showReport = false
    @State private var showBirdwatch = false
    @State private var showCopyToast = false
    @State private var showMoreMenu = false

    private var video: RokunanaVideo? { RokunanaVideo(event: post.event) }

    var body: some View {
        ZStack {
            if let video {
                RokunanaPlayer(videoUrl: video.videoUrl, muted: $muted)
                    .ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
            }

            LinearGradient(colors: [.black.opacity(0.55), .clear, .black.opacity(0.82)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                // Important: this full-screen gradient was intercepting taps, so
                // the speaker button underneath could not toggle audio on device.
                .allowsHitTesting(false)

            HStack(alignment: .bottom) {
                bottomInfo
                Spacer(minLength: 12)
                rightActions
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    private var bottomInfo: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                AvatarView(url: post.profile?.picture, name: post.profile?.displayedName ?? "", size: 34)
                    .onTapGesture { onProfileTap(post.event.pubkey) }
                Text(post.profile?.displayedName ?? String(post.event.pubkey.prefix(12)) + "…")
                    .font(NuruFont.bodyMedium())
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("・フォロー")
                    .font(NuruFont.bodyMedium())
                    .fontWeight(.black)
                    .foregroundStyle(NuruColors.lineGreen)
            }

            if let video {
                Text(video.displaySummary)
                    .font(NuruFont.bodyMedium())
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .shadow(radius: 2)
                if !video.hashtags.isEmpty {
                    Text(video.hashtags.map { "#\($0)" }.joined(separator: " "))
                        .font(NuruFont.bodySmall())
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
            }
        }
    }

    private var rightActions: some View {
        VStack(spacing: 18) {
            iconButton(count: post.likeCount, active: post.isLiked) {
                LikeIcon(filled: post.isLiked)
                    .frame(width: 30, height: 30)
            } action: { Task { await onLike() } }
            iconButton(count: post.repostCount, active: post.isReposted) {
                RepostIcon()
                    .frame(width: 30, height: 30)
            } action: { Task { await onRepost() } }
            iconButton(count: post.zapAmount > 0 ? Int(post.zapAmount) : nil, active: false) {
                BitcoinIcon()
                    .frame(width: 30, height: 30)
            } action: { onZap() }
            iconButton(count: nil, active: post.isBookmarked) {
                BookmarkIcon(filled: post.isBookmarked)
                    .frame(width: 30, height: 30)
            } action: { Task { await onBookmark() } }
            moreButton
            audioMuteButton
        }
        .confirmationDialog("投稿メニュー", isPresented: $showMoreMenu, titleVisibility: .hidden) {
            Button("テキストをコピー") { copyText() }
            Button("Birdwatch") { showBirdwatch = true }
            Button("通報") { showReport = true }
            if !isOwnPost {
                Button("ミュート", role: .destructive) { Task { await onMute() } }
            }
            if isOwnPost {
                Button("削除", role: .destructive) { Task { await onDelete() } }
            }
            Button("キャンセル", role: .cancel) {}
        }
        .sheet(isPresented: $showReport) {
            ReportSheet(
                onReport: { type, content in
                    showReport = false
                    Task { await onReport(type, content) }
                },
                onDismiss: { showReport = false }
            )
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showBirdwatch) {
            BirdwatchModal(
                onDismiss: { showBirdwatch = false },
                onSubmit: { type, content, url in
                    showBirdwatch = false
                    Task { await onBirdwatch(type, content, url) }
                },
                existingNotes: post.birdwatchNotes
            )
            .presentationDetents([.large])
            .interactiveDismissDisabled(true)
        }
        .overlay(alignment: .bottom) {
            if showCopyToast {
                Text("コピーしました")
                    .font(.custom(NuruFont.bold, size: 12, relativeTo: .caption))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.black.opacity(0.65)))
                    .offset(y: 42)
            }
        }
    }

    private var moreButton: some View {
        Button { showMoreMenu = true } label: {
            MoreVertIcon()
                .frame(width: 24, height: 24)
                .foregroundStyle(.white)
                .frame(width: 48, height: 30)
        }
        .buttonStyle(.plain)
    }

    private var audioMuteButton: some View {
        Button { muted.toggle() } label: {
            Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white.opacity(0.92))
                .frame(width: 48, height: 30)
        }
        .buttonStyle(.plain)
    }

    private func copyText() {
        UIPasteboard.general.string = post.event.content
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        showCopyToast = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            showCopyToast = false
        }
    }

    private func iconButton<Icon: View>(count: Int?, active: Bool, @ViewBuilder icon: () -> Icon, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                icon()
                    .foregroundStyle(active ? NuruColors.lineGreen : .white)
                    .shadow(radius: 2)
                if let count, count > 0 {
                    Text(formatCount(count))
                        .font(.custom(NuruFont.bold, size: 12, relativeTo: .caption))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 48)
        }
        .buttonStyle(.plain)
    }

    private func formatCount(_ n: Int) -> String {
        n >= 1000 ? "\(n / 1000)K" : "\(n)"
    }
}

private struct RokunanaPlayer: View {
    let videoUrl: String
    @Binding var muted: Bool
    @State private var player: AVQueuePlayer? = nil
    @State private var looper: AVPlayerLooper? = nil

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let player {
                RokunanaPlayerLayer(player: player)
            } else {
                Color.black.overlay(ProgressView().tint(.white))
            }
        }
        .onAppear { setup() }
        .onDisappear { teardown() }
        .onChange(of: muted) { _, newValue in
            setMuted(newValue)
        }
    }

    private func setMuted(_ newValue: Bool) {
        muted = newValue
        configureAudioSessionForPlayback(shouldActivate: !newValue)
        player?.isMuted = newValue
        player?.volume = newValue ? 0 : 1
        player?.play()
        AppLogger.log("RokunanaAudio", "toggle muted=\(newValue) volume=\(player?.volume ?? -1) rate=\(player?.rate ?? -1)")
    }

    private func configureAudioSessionForPlayback(shouldActivate: Bool) {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback, options: [])
            try session.setActive(shouldActivate)
            AppLogger.log("RokunanaAudio", "audioSession active=\(shouldActivate) category=\(session.category.rawValue) outputVolume=\(session.outputVolume)")
        } catch {
            AppLogger.log("RokunanaAudio", "audioSession error=\(error.localizedDescription)", level: .error)
        }
    }

    private func setup() {
        guard player == nil, let url = URL(string: videoUrl) else { return }
        let item = AVPlayerItem(url: url)
        let queue = AVQueuePlayer(items: [item])
        queue.actionAtItemEnd = .none
        looper = AVPlayerLooper(player: queue, templateItem: item)
        player = queue
        setMuted(muted)
    }

    private func teardown() {
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        looper = nil
        player = nil
        if !muted {
            configureAudioSessionForPlayback(shouldActivate: false)
        }
    }
}

private struct RokunanaPlayerLayer: UIViewRepresentable {
    let player: AVQueuePlayer

    func makeUIView(context: Context) -> RokunanaPlayerUIView {
        let view = RokunanaPlayerUIView()
        view.player = player
        return view
    }

    func updateUIView(_ uiView: RokunanaPlayerUIView, context: Context) {
        uiView.player = player
    }
}

private final class RokunanaPlayerUIView: UIView {
    private let playerLayer = AVPlayerLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        playerLayer.videoGravity = .resizeAspectFill
        layer.addSublayer(playerLayer)
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

private struct RokunanaPostSheet: View {
    @Bindable var viewModel: RokunanaViewModel
    var onDismiss: () -> Void

    @State private var item: PhotosPickerItem? = nil
    @State private var capturedVideoData: Data? = nil
    @State private var showCamera = false
    @State private var title = ""
    @State private var summary = ""
    @State private var hashtags = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("動画") {
                    PhotosPicker(selection: $item, matching: .videos) {
                        HStack {
                            Image(systemName: "photo.on.rectangle")
                            Text(item == nil ? "ライブラリから選択" : "ライブラリ動画を選択済み")
                        }
                    }
                    Button {
                        showCamera = true
                    } label: {
                        HStack {
                            Image(systemName: "camera.fill")
                            Text(capturedVideoData == nil ? "カメラで6.7秒録画" : "録画済み動画を使用")
                        }
                    }
                }
                Section("説明") {
                    TextField("タイトル", text: $title)
                    TextField("本文", text: $summary, axis: .vertical)
                        .lineLimit(3...5)
                    TextField("#タグ（スペース区切り）", text: $hashtags)
                }
                if let error = viewModel.errorMessage {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("ろくなな投稿")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("閉じる", action: onDismiss)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(viewModel.isPublishing ? "投稿中…" : "投稿") {
                        Task {
                            let pickedData = try? await item?.loadTransferable(type: Data.self)
                            await viewModel.publishVideo(data: capturedVideoData ?? pickedData ?? nil, title: title, summary: summary, hashtagsText: hashtags)
                            if viewModel.errorMessage == nil { onDismiss() }
                        }
                    }
                    .disabled((item == nil && capturedVideoData == nil) || viewModel.isPublishing)
                }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            RokunanaCameraRecorderView { data in
                capturedVideoData = data
                item = nil
                showCamera = false
            } onCancel: {
                showCamera = false
            }
        }
    }
}

// MARK: - ろくなな Camera Recorder

private struct RokunanaCameraRecorderView: View {
    @StateObject private var camera = RokunanaCameraController()
    var onComplete: (Data) -> Void
    var onCancel: () -> Void

    var body: some View {
        ZStack {
            Color(red: 0.0, green: 0.06, blue: 0.04).ignoresSafeArea()

            if let session = camera.session {
                RokunanaCameraPreview(session: session)
                    .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
                    .padding(.top, 54)
                    .padding(.bottom, 110)
                    .ignoresSafeArea(edges: .horizontal)
            } else {
                VStack(spacing: 14) {
                    ProgressView().tint(.white)
                    Text(camera.permissionMessage ?? "カメラを準備中…")
                        .font(NuruFont.bodyMedium())
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                }
                .padding(24)
            }

            VStack {
                HStack {
                    Button(action: onCancel) {
                        Image(systemName: "xmark")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(.white.opacity(0.85))
                            .frame(width: 54, height: 54)
                            .background(Circle().fill(Color.black.opacity(0.28)))
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding(.horizontal, 22)
                .padding(.top, 20)

                Spacer()

                if !camera.hasSeenSixSecondHint {
                    RokunanaSixSecondHint { camera.hasSeenSixSecondHint = true }
                        .padding(.bottom, 10)
                }

                HStack(spacing: 34) {
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(.white, lineWidth: 3)
                        .frame(width: 52, height: 52)
                        .opacity(0.9)

                    Button { camera.toggleRecording() } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 30, style: .continuous)
                                .stroke(.white, lineWidth: 5)
                                .frame(width: 92, height: 92)
                            RoundedRectangle(cornerRadius: camera.isRecording ? 12 : 22, style: .continuous)
                                .fill(Color.red)
                                .frame(width: camera.isRecording ? 42 : 58, height: camera.isRecording ? 42 : 58)
                        }
                    }
                    .buttonStyle(.plain)

                    VStack(spacing: 10) {
                        Text("Capture")
                            .font(.custom(NuruFont.bold, size: 13, relativeTo: .caption))
                            .foregroundStyle(NuruColors.lineGreen)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 9)
                            .background(Capsule().fill(NuruColors.lineGreen.opacity(0.14)))
                        Text("6.7s")
                            .font(.custom(NuruFont.bold, size: 13, relativeTo: .caption))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 72)
                }
                .padding(.bottom, 24)
            }

            VStack {
                Spacer()
                if camera.isRecording {
                    ProgressView(value: camera.progress)
                        .progressViewStyle(.linear)
                        .tint(NuruColors.lineGreen)
                        .padding(.horizontal, 54)
                        .padding(.bottom, 126)
                }
            }

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    VStack(spacing: 24) {
                        Button { camera.toggleTorch() } label: { Image(systemName: camera.isTorchOn ? "bolt.fill" : "bolt.slash") }
                        Button { } label: { Image(systemName: "timer") }
                        Button { camera.switchCamera() } label: { Image(systemName: "arrow.triangle.2.circlepath.camera") }
                    }
                    .font(.system(size: 25, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 64)
                    .padding(.vertical, 18)
                    .background(Capsule().fill(Color.black.opacity(0.35)))
                    .padding(.trailing, 20)
                    .padding(.bottom, 260)
                }
            }
        }
        .task { await camera.configure() }
        .onChange(of: camera.completedData) { _, data in
            if let data { onComplete(data) }
        }
    }
}

private struct RokunanaSixSecondHint: View {
    var onOK: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Capsule()
                .fill(Color.white.opacity(0.25))
                .frame(width: 64, height: 5)
                .padding(.top, 10)
            Text("🐶")
                .font(.system(size: 62))
            Text("なぜ6.7秒なの？")
                .font(NuruFont.titleLarge())
                .fontWeight(.black)
                .foregroundStyle(.white)
            Text("短いクリップは目を引く余白を作ります。6.7秒に整えると、ろくななのテンポで見やすく投稿できます。")
                .font(NuruFont.bodyMedium())
                .foregroundStyle(.white.opacity(0.74))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
            Button(action: onOK) {
                Text("わかりました！")
                    .font(NuruFont.bodyMedium())
                    .fontWeight(.black)
                    .foregroundStyle(NuruColors.lineGreen)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Capsule().stroke(NuruColors.lineGreen.opacity(0.35), lineWidth: 1.5))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(Color(red: 0.0, green: 0.09, blue: 0.06))
        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
    }
}

private struct RokunanaCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.videoPreviewLayer.session = session
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

@MainActor
private final class RokunanaCameraController: NSObject, ObservableObject, AVCaptureFileOutputRecordingDelegate {
    @Published var session: AVCaptureSession? = nil
    @Published var isRecording = false
    @Published var progress: Double = 0
    @Published var completedData: Data? = nil
    @Published var permissionMessage: String? = nil
    @Published var isTorchOn = false
    @Published var hasSeenSixSecondHint = false

    private let maxDuration: TimeInterval = 6.7
    private var movieOutput: AVCaptureMovieFileOutput?
    private var currentDevice: AVCaptureDevice?
    private var timerTask: Task<Void, Never>?

    func configure() async {
        guard await requestPermissions() else { return }

        let session = AVCaptureSession()
        session.beginConfiguration()
        session.sessionPreset = .high

        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let videoInput = try? AVCaptureDeviceInput(device: videoDevice),
              session.canAddInput(videoInput) else {
            permissionMessage = "カメラを開始できませんでした"
            return
        }
        session.addInput(videoInput)
        currentDevice = videoDevice

        if let audioDevice = AVCaptureDevice.default(for: .audio),
           let audioInput = try? AVCaptureDeviceInput(device: audioDevice),
           session.canAddInput(audioInput) {
            session.addInput(audioInput)
        }

        let output = AVCaptureMovieFileOutput()
        if session.canAddOutput(output) {
            session.addOutput(output)
            movieOutput = output
        }
        session.commitConfiguration()
        self.session = session

        Task.detached { session.startRunning() }
    }

    private func requestPermissions() async -> Bool {
        let camera = await AVCaptureDevice.requestAccess(for: .video)
        let mic = await AVCaptureDevice.requestAccess(for: .audio)
        if !camera || !mic {
            permissionMessage = "カメラとマイクへのアクセスを許可してください"
            return false
        }
        return true
    }

    func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        guard let movieOutput, !movieOutput.isRecording else { return }
        completedData = nil
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rokunana-record-\(UUID().uuidString).mov")
        movieOutput.startRecording(to: url, recordingDelegate: self)
        isRecording = true
        progress = 0
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            guard let self else { return }
            let start = Date()
            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(start)
                await MainActor.run { self.progress = min(1, elapsed / self.maxDuration) }
                if elapsed >= self.maxDuration {
                    await MainActor.run { self.stopRecording() }
                    break
                }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
    }

    private func stopRecording() {
        movieOutput?.stopRecording()
        timerTask?.cancel()
        isRecording = false
    }

    func switchCamera() {
        guard let session else { return }
        session.beginConfiguration()
        let currentInput = session.inputs.compactMap { $0 as? AVCaptureDeviceInput }.first { $0.device.hasMediaType(.video) }
        if let currentInput { session.removeInput(currentInput) }
        let newPosition: AVCaptureDevice.Position = currentDevice?.position == .back ? .front : .back
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition),
           let input = try? AVCaptureDeviceInput(device: device),
           session.canAddInput(input) {
            session.addInput(input)
            currentDevice = device
        } else if let currentInput, session.canAddInput(currentInput) {
            session.addInput(currentInput)
        }
        session.commitConfiguration()
    }

    func toggleTorch() {
        guard let device = currentDevice, device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = device.torchMode == .on ? .off : .on
            isTorchOn = device.torchMode == .on
            device.unlockForConfiguration()
        } catch { }
    }

    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        guard error == nil, let data = try? Data(contentsOf: outputFileURL) else { return }
        try? FileManager.default.removeItem(at: outputFileURL)
        Task { @MainActor in
            self.isRecording = false
            self.completedData = data
        }
    }
}
