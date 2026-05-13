import SwiftUI
import PhotosUI
import Speech
import AVFoundation

/// 引用リポスト作成シート — NIP-18 準拠 (Kind 1 + "q" タグ + nostr:note1... 埋め込み)。
/// Android QuoteRepostModal.kt に対応。PostSheet と同じツールバーボタンを表示。
struct QuoteRepostSheet: View {

    let post:         ScoredPost
    let repository:   NostrRepository
    let myPubkeyHex:  String
    var myProfile:    UserProfile?    = nil
    var onDismiss:    () -> Void      = {}
    var onSuccess:    () -> Void      = {}

    @Environment(\.nuruTheme) private var theme
    @FocusState private var fieldFocused: Bool
    @State private var text:            String              = ""
    @State private var isPosting:       Bool                = false
    @State private var errorMessage:    String?             = nil
    @State private var contentWarning:  String              = ""
    @State private var showCWInput:     Bool                = false
    @State private var selectedItems:   [PhotosPickerItem]  = []
    @State private var selectedImages:  [UIImage]           = []
    @State private var uploadProgress:  String              = ""
    @State private var isUploading:     Bool                = false

    // Custom emoji — mirrors PostSheet
    @State private var showEmojiPicker:      Bool          = false
    @State private var selectedCustomEmojis: [CustomEmoji] = []

    // Relay selection + NIP-70 — mirrors PostSheet
    @State private var allRelays:       [String]      = []
    @State private var selectedRelays:  Set<String>   = []
    @State private var nip70Protected:  Bool          = false
    @State private var showRelayPanel:  Bool          = false

    // STT (Speech-to-Text) — mirrors PostSheet
    @State private var isSTTActive:    Bool          = false
    @State private var speechRecognizer: SFSpeechRecognizer? = nil
    @State private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest? = nil
    @State private var recognitionTask:   SFSpeechRecognitionTask? = nil
    @State private var audioEngine:       AVAudioEngine? = nil
    @State private var sttBaseText:       String        = ""

    private var remaining: Int { UI.postMaxLength - text.count }
    private var canPost: Bool {
        (!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !selectedImages.isEmpty)
        && remaining >= 0 && !isPosting && !isUploading
    }

    /// Whether relay config differs from defaults (show green dot indicator).
    private var hasRelayCustomization: Bool {
        selectedRelays.count != allRelays.count || nip70Protected
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── ヘッダー ─────────────────────────────────────────────────────
            HStack {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(theme.textPrimary)
                        .frame(width: 40, height: 40)
                }

                Spacer()

                Text("引用投稿")
                    .font(NuruFont.titleMedium())
                    .fontWeight(.bold)
                    .foregroundStyle(theme.textPrimary)

                Spacer()

                Button {
                    Task { await handlePost() }
                } label: {
                    if isPosting {
                        ProgressView()
                            .scaleEffect(0.8)
                            .frame(width: 64, height: 32)
                    } else {
                        Text("投稿")
                            .font(NuruFont.buttonMedium())
                            .foregroundStyle(.white)
                            .padding(.horizontal, NuruSpacing.space3)
                            .padding(.vertical, NuruSpacing.space1)
                            .background(canPost ? NuruColors.lineGreen : NuruColors.lineGreen.opacity(0.4))
                            .cornerRadius(NuruSpacing.radiusFull)
                    }
                }
                .disabled(!canPost)
            }
            .padding(.horizontal, NuruSpacing.space4)
            .padding(.top, NuruSpacing.space3)

            Divider().background(theme.borderColor)

            // ── CW 入力フィールド ─────────────────────────────────────────────
            if showCWInput {
                HStack(spacing: NuruSpacing.space2) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color(red: 0.98, green: 0.67, blue: 0.0))
                    TextField("警告の理由（ネタバレ・センシティブ等）", text: $contentWarning)
                        .font(NuruFont.bodySmall())
                        .foregroundStyle(theme.textPrimary)
                }
                .padding(.horizontal, NuruSpacing.space4)
                .padding(.vertical, NuruSpacing.space2)
                .background(Color(red: 0.98, green: 0.67, blue: 0.0).opacity(0.08))
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // ── コンポーザー本体 ──────────────────────────────────────────────
            ScrollView {
                VStack(alignment: .leading, spacing: NuruSpacing.space3) {
                    // テキスト入力エリア
                    HStack(alignment: .top, spacing: NuruSpacing.space3) {
                        AvatarView(
                            url:  myProfile?.picture,
                            name: myProfile?.displayedName ?? "?",
                            size: NuruSpacing.avatarMd
                        )

                        VStack(alignment: .leading, spacing: NuruSpacing.space1) {
                            if let name = myProfile?.displayedName {
                                Text(name)
                                    .font(NuruFont.titleMedium())
                                    .foregroundStyle(theme.textPrimary)
                            }

                            TextEditor(text: $text)
                                .font(NuruFont.bodyLarge())
                                .foregroundStyle(theme.textPrimary)
                                .scrollContentBackground(.hidden)
                                .background(Color.clear)
                                .focused($fieldFocused)
                                .frame(minHeight: 80, maxHeight: 200)
                                .overlay(alignment: .topLeading) {
                                    if text.isEmpty {
                                        Text("コメントを追加...")
                                            .font(NuruFont.bodyLarge())
                                            .foregroundStyle(theme.textTertiary)
                                            .allowsHitTesting(false)
                                            .padding(.top, 8)
                                            .padding(.leading, 4)
                                    }
                                }
                        }
                    }

                    // 画像プレビュー
                    if !selectedImages.isEmpty {
                        imagePreviewRow
                    }

                    // カスタム絵文字プレビュー — mirrors Android QuoteRepostModal.kt
                    if !selectedCustomEmojis.isEmpty {
                        customEmojiPreviewRow
                    }

                    // アップロード進捗
                    if !uploadProgress.isEmpty {
                        Text(uploadProgress)
                            .font(NuruFont.bodySmall())
                            .foregroundStyle(theme.textSecondary)
                    }

                    // 引用元プレビューカード
                    quotedPostCard
                }
                .padding(NuruSpacing.space4)
            }

            // エラー表示
            if let msg = errorMessage {
                Text(msg)
                    .font(NuruFont.bodySmall())
                    .foregroundStyle(NuruColors.colorError)
                    .padding(.horizontal, NuruSpacing.space4)
                    .padding(.bottom, NuruSpacing.space2)
            }

            Divider().background(theme.borderColor)

            // ── ボトムツールバー — Android PostToolbar と同じ順序/アイコン ─────────
            HStack(spacing: 4) {
                PhotosPicker(
                    selection: $selectedItems,
                    maxSelectionCount: 3,
                    matching: .images
                ) {
                    toolbarIcon(tint: selectedImages.isEmpty ? theme.textTertiary : NuruColors.lineGreen) {
                        PhotoIcon()
                    }
                }
                .disabled(selectedImages.count >= 3)
                .opacity(selectedImages.count >= 3 ? 0.35 : 1.0)
                .onChange(of: selectedItems) { _, newItems in
                    Task { await loadSelectedImages(from: newItems) }
                }

                toolbarButton {
                    withAnimation(.easeInOut(duration: 0.2)) { showCWInput.toggle() }
                    if !showCWInput { contentWarning = "" }
                } icon: {
                    toolbarIcon(tint: showCWInput ? Color(red: 1.0, green: 0.60, blue: 0.0) : theme.textTertiary) {
                        WarningIcon()
                    }
                }

                toolbarButton {
                    showEmojiPicker.toggle()
                    if showEmojiPicker { showRelayPanel = false }
                } icon: {
                    toolbarIcon(tint: theme.textTertiary) {
                        EmojiIcon()
                    }
                }

                toolbarButton {
                    if isSTTActive { stopSTT() } else { startSTT() }
                } icon: {
                    toolbarIcon(tint: isSTTActive ? Color.red : theme.textTertiary) {
                        MicIcon()
                    }
                }

                toolbarButton {
                    withAnimation(.easeInOut(duration: 0.2)) { showRelayPanel.toggle() }
                    if showRelayPanel { showEmojiPicker = false }
                } icon: {
                    toolbarIcon(tint: (showRelayPanel || hasRelayCustomization) ? NuruColors.lineGreen : theme.textTertiary) {
                        Image(systemName: "wifi.router")
                            .font(.system(size: 22, weight: .regular))
                    }
                }

                Spacer()

                Text("\(remaining)")
                    .font(.system(size: 12))
                    .foregroundStyle(remaining < 0 ? NuruColors.colorError
                        : remaining < 20 ? Color(red: 1.0, green: 0.60, blue: 0.0)
                        : theme.textTertiary)
                    .padding(.trailing, 8)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)

            if showRelayPanel {
                RelaySelectPanel(
                    relays: allRelays,
                    selectedRelays: $selectedRelays,
                    nip70Protected: $nip70Protected
                )
            }
        }
        .background(theme.bgPrimary.ignoresSafeArea())
        .onAppear {
            fieldFocused = true
            Task {
                let relays = await repository.getSavedRelayUrls()
                allRelays = relays
                selectedRelays = Set(relays)
            }
        }
        .onDisappear { stopSTT() }
        .animation(.easeInOut(duration: 0.2), value: showCWInput)
        .animation(.easeInOut(duration: 0.2), value: showRelayPanel)
        .sheet(isPresented: $showEmojiPicker) {
            EmojiPickerSheet(
                repository: repository,
                pubkeyHex: myPubkeyHex,
                individualOnly: true,
                onSelect: { emoji in
                    insertCustomEmoji(emoji)
                }
            )
            .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Android-style Toolbar Helpers

    private func toolbarButton<Icon: View>(
        action: @escaping () -> Void,
        @ViewBuilder icon: () -> Icon
    ) -> some View {
        Button(action: action) { icon() }
            .buttonStyle(.plain)
    }

    private func toolbarIcon<Icon: View>(
        tint: Color,
        @ViewBuilder icon: () -> Icon
    ) -> some View {
        icon()
            .frame(width: 24, height: 24)
            .foregroundStyle(tint)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }

    // MARK: - 引用元プレビューカード

    private var quotedPostCard: some View {
        VStack(alignment: .leading, spacing: NuruSpacing.space2) {
            // 著者行
            HStack(spacing: 6) {
                AvatarView(
                    url:  post.profile?.picture,
                    name: post.profile?.displayedName ?? "?",
                    size: 20
                )
                Text(post.profile?.displayedName ?? post.event.pubkey.shortenedPubkey)
                    .font(NuruFont.bodySmall())
                    .fontWeight(.semibold)
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
            }

            // 投稿本文（最大5行）
            Text(removeImageUrls(post.event.content))
                .font(NuruFont.bodySmall())
                .foregroundStyle(theme.textSecondary)
                .lineLimit(5)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(NuruSpacing.space3)
        .background(theme.bgTertiary)
        .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusMd))
        .overlay(
            RoundedRectangle(cornerRadius: NuruSpacing.radiusMd)
                .stroke(theme.borderColor.opacity(0.5), lineWidth: 0.5)
        )
    }

    // MARK: - 画像プレビュー

    private var imagePreviewRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: NuruSpacing.space2) {
                ForEach(Array(selectedImages.enumerated()), id: \.offset) { idx, img in
                    ZStack(alignment: .topTrailing) {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 80, height: 80)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusSm))

                        Button {
                            selectedImages.remove(at: idx)
                            if idx < selectedItems.count { selectedItems.remove(at: idx) }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(.white)
                                .background(Color.black.opacity(0.5))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .padding(4)
                    }
                }
            }
        }
    }

    // MARK: - Custom Emoji Preview

    private var customEmojiPreviewRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(selectedCustomEmojis) { emoji in
                    HStack(spacing: 4) {
                        if let url = URL(string: emoji.url) {
                            AsyncImage(url: url) { phase in
                                if case .success(let img) = phase {
                                    img.resizable().scaledToFit()
                                } else {
                                    Color.clear
                                }
                            }
                            .frame(width: 18, height: 18)
                        }
                        Text(":\(emoji.shortcode):")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.textTertiary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(theme.bgSecondary)
                    .clipShape(Capsule())
                }
            }
        }
    }

    // MARK: - 画像読み込み

    private func loadSelectedImages(from items: [PhotosPickerItem]) async {
        var images: [UIImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let img  = UIImage(data: data) {
                images.append(img)
            }
        }
        await MainActor.run { selectedImages = images }
    }

    // MARK: - カスタム絵文字挿入 — mirrors PostSheet

    private func insertCustomEmoji(_ emoji: CustomEmoji) {
        let insert = ":\(emoji.shortcode):"
        guard (text + insert).count <= UI.postMaxLength else { return }
        text += insert
        if !selectedCustomEmojis.contains(where: { $0.shortcode == emoji.shortcode }) {
            selectedCustomEmojis.append(emoji)
        }
    }

    // MARK: - STT (Speech-to-Text) — mirrors PostSheet

    private func startSTT() {
        guard !isSTTActive else { return }
        errorMessage = nil

        SFSpeechRecognizer.requestAuthorization { speechStatus in
            guard speechStatus == .authorized else {
                DispatchQueue.main.async {
                    errorMessage = "音声認識の許可が必要です"
                }
                return
            }

            AVAudioApplication.requestRecordPermission { granted in
                DispatchQueue.main.async {
                    guard granted else {
                        errorMessage = "マイクの許可が必要です"
                        return
                    }
                    beginRecording()
                }
            }
        }
    }

    private func beginRecording() {
        stopSTT(resetBaseText: false)

        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja-JP"))
        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "音声認識が利用できません"
            return
        }
        speechRecognizer = recognizer
        sttBaseText = text

        let engine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            let inputNode = engine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }

            recognitionTask = recognizer.recognitionTask(with: request) { result, error in
                if let result {
                    let transcribed = result.bestTranscription.formattedString
                    DispatchQueue.main.async {
                        let separator = self.sttBaseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : " "
                        let combined = self.sttBaseText + separator + transcribed
                        if combined.count <= UI.postMaxLength {
                            self.text = combined
                        }
                    }
                }
                if error != nil || (result?.isFinal ?? false) {
                    DispatchQueue.main.async { self.stopSTT() }
                }
            }

            engine.prepare()
            try engine.start()

            self.audioEngine = engine
            self.recognitionRequest = request
            isSTTActive = true
        } catch {
            inputNodeRemoveTapSafely(engine: engine)
            recognitionTask?.cancel()
            recognitionTask = nil
            recognitionRequest = nil
            audioEngine = nil
            isSTTActive = false
            errorMessage = "録音を開始できませんでした: \(error.localizedDescription)"
        }
    }

    private func stopSTT(resetBaseText: Bool = true) {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        audioEngine = nil
        recognitionRequest = nil
        recognitionTask = nil
        isSTTActive = false
        if resetBaseText { sttBaseText = "" }

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func inputNodeRemoveTapSafely(engine: AVAudioEngine) {
        engine.inputNode.removeTap(onBus: 0)
    }

    // MARK: - 投稿処理 (NIP-18: Kind 1 + "q" タグ + nostr:note1... 埋め込み)

    private func handlePost() async {
        guard canPost else { return }
        isPosting    = true
        errorMessage = nil

        // Stop STT if active
        if isSTTActive { stopSTT() }

        var content    = text
        var customTags: [[String]] = []

        // 画像アップロード（並列 — Android PostModal.kt の async { } / awaitAll() パターンに対応）
        if !selectedImages.isEmpty {
            isUploading    = true
            uploadProgress = "画像をアップロード中..."

            let server        = repository.prefs.uploadServerEnum
            let uploadService = ImageUploadService(signer: repository.signer)
            let total         = selectedImages.count

            let urls = await uploadService.uploadImages(
                selectedImages,
                server: server,
                blossomBaseUrl: repository.prefs.blossomUploadBaseUrl,
                onProgress: { current, _ in
                    Task { @MainActor in
                        self.uploadProgress = "画像をアップロード中 (\(current)/\(total))..."
                    }
                }
            )

            if !urls.isEmpty {
                content += "\n" + urls.joined(separator: "\n")
            } else {
                isUploading = false
                uploadProgress = ""
                errorMessage = "画像のアップロードに失敗しました。ネットワークを確認してください。"
                isPosting = false
                return
            }
            isUploading    = false
            uploadProgress = ""
        }

        // NIP-18: "q" タグ — 引用元イベント ID を参照 (relay URL と pubkey は空文字)
        customTags.append(["q", post.event.id, "", ""])

        // NIP-19: content 末尾に nostr:note1... を追加
        if let note1 = encodeNote1(eventIdHex: post.event.id) {
            let suffix = "nostr:\(note1)"
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            content = trimmed.isEmpty ? suffix : trimmed + "\n" + suffix
        }

        // ハッシュタグ抽出 → "t" タグ (Unicode 対応)
        let hashtagPattern = #"#([\w\u{3040}-\u{309F}\u{30A0}-\u{30FF}\u{4E00}-\u{9FFF}\u{FF00}-\u{FFEF}]+)"#
        if let regex = try? NSRegularExpression(pattern: hashtagPattern) {
            let ns = content as NSString
            var seen = Set<String>()
            regex.matches(in: content, range: NSRange(location: 0, length: ns.length)).forEach { m in
                let tag = ns.substring(with: m.range(at: 1)).lowercased()
                if seen.insert(tag).inserted { customTags.append(["t", tag]) }
            }
        }

        // カスタム絵文字タグ — mirrors PostSheet
        for emoji in selectedCustomEmojis {
            customTags.append(["emoji", emoji.shortcode, emoji.url])
        }

        // targetRelays: nil = broadcast to all, non-nil = specific relays only
        let targetRelayList: [String]? = selectedRelays.count != allRelays.count
            ? Array(selectedRelays) : nil

        do {
            try await repository.publishNote(
                content:        content,
                contentWarning: showCWInput && !contentWarning.isEmpty ? contentWarning : nil,
                customTags:     customTags,
                targetRelays:   targetRelayList,
                nip70Protected: nip70Protected
            )
            onSuccess()
        } catch {
            errorMessage = "投稿に失敗しました: \(error.localizedDescription)"
        }
        isPosting = false
    }
}

// MARK: - NIP-19 note1 エンコード (private helper)

/// イベント ID (hex) を NIP-19 note1 形式の bech32 文字列にエンコードする。
private func encodeNote1(eventIdHex: String) -> String? {
    NIP19.encodeNote1(eventIdHex)
}
