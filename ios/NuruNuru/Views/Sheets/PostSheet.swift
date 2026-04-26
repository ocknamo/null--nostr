import SwiftUI
import PhotosUI
import Speech

/// Compose a new post — 140-char limit, CW toggle, image attachment,
/// relay selection, NIP-70 protection, custom emoji insertion, and STT.
/// Mirrors Android PostModal.kt.
struct PostSheet: View {

    let repository:   NostrRepository
    let myPubkeyHex:  String
    var myProfile:    UserProfile?
    var replyToId:    String? = nil
    var onDismiss:    () -> Void = {}
    var onSuccess:    () -> Void = {}

    @Environment(\.nuruTheme) private var theme
    @FocusState  private var fieldFocused: Bool
    @State private var text:            String        = ""
    @State private var isPosting:       Bool          = false
    @State private var errorMessage:    String?       = nil
    @State private var contentWarning:  String        = ""
    @State private var showCWInput:     Bool          = false
    @State private var selectedItems:   [PhotosPickerItem] = []
    @State private var selectedImages:  [UIImage]     = []
    @State private var uploadProgress:  String        = ""
    @State private var isUploading:     Bool          = false

    // Relay selection + NIP-70
    @State private var allRelays:       [String]      = []
    @State private var selectedRelays:  Set<String>   = []
    @State private var nip70Protected:  Bool          = false
    @State private var showRelayPanel:  Bool          = false

    // Custom emoji
    @State private var showEmojiPicker:      Bool          = false
    @State private var selectedCustomEmojis: [CustomEmoji] = []

    // STT (Speech-to-Text)
    @State private var isSTTActive:    Bool          = false
    @State private var speechRecognizer: SFSpeechRecognizer? = nil
    @State private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest? = nil
    @State private var recognitionTask:   SFSpeechRecognitionTask? = nil
    @State private var audioEngine:       AVAudioEngine? = nil

    private var remaining: Int { UI.postMaxLength - text.count }
    private var canPost:   Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && remaining >= 0 && !isPosting && !isUploading
    }

    /// Whether relay config differs from defaults (show green dot indicator).
    private var hasRelayCustomization: Bool {
        selectedRelays.count != allRelays.count || nip70Protected
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header — Android style: キャンセル(左) + タイトル(中) + 投稿(右)
            HStack {
                Button("キャンセル", action: onDismiss)
                    .font(NuruFont.bodyMedium())
                    .foregroundStyle(theme.textSecondary)

                Spacer()

                Text(replyToId != nil ? "返信" : "新規投稿")
                    .font(NuruFont.titleMedium())
                    .fontWeight(.bold)
                    .foregroundStyle(theme.textPrimary)

                Spacer()

                Button("投稿") {
                    Task { await handlePost() }
                }
                .font(NuruFont.buttonMedium())
                .foregroundStyle(.white)
                .padding(.horizontal, NuruSpacing.space3)
                .padding(.vertical, NuruSpacing.space1)
                .background(canPost ? NuruColors.lineGreen : NuruColors.lineGreen.opacity(0.4))
                .cornerRadius(NuruSpacing.radiusFull)
                .disabled(!canPost)
            }
            .padding(.horizontal, NuruSpacing.space4)
            .padding(.top, NuruSpacing.space3)

            Divider().background(theme.borderColor)

            // CW input field
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

            // Composer
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top, spacing: NuruSpacing.space3) {
                        AvatarView(
                            url:  myProfile?.picture,
                            name: myProfile?.displayedName ?? "?",
                            size: NuruSpacing.avatarMd
                        )

                        VStack(alignment: .leading, spacing: NuruSpacing.space2) {
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
                                .frame(minHeight: 120, maxHeight: 280)
                                .overlay(alignment: .topLeading) {
                                    if text.isEmpty {
                                        Text("いまどうしてる？")
                                            .font(NuruFont.bodyLarge())
                                            .foregroundStyle(theme.textTertiary)
                                            .allowsHitTesting(false)
                                            .padding(.top, 8)
                                            .padding(.leading, 4)
                                    }
                                }
                        }
                    }
                    .padding(.horizontal, NuruSpacing.space4)
                    .padding(.vertical, NuruSpacing.space3)

                    // Hashtag-highlighted preview
                    if !text.isEmpty && text.contains("#") {
                        hashtagPreview
                            .padding(.horizontal, NuruSpacing.space4)
                            .padding(.bottom, NuruSpacing.space2)
                    }

                    // Image previews
                    if !selectedImages.isEmpty {
                        imagePreviewRow
                            .padding(.horizontal, NuruSpacing.space4)
                            .padding(.bottom, NuruSpacing.space2)
                    }

                    // Upload progress
                    if !uploadProgress.isEmpty {
                        Text(uploadProgress)
                            .font(NuruFont.bodySmall())
                            .foregroundStyle(theme.textSecondary)
                            .padding(.horizontal, NuruSpacing.space4)
                    }

                    // Relay selection panel (collapsible)
                    if showRelayPanel {
                        relayPanelSection
                    }
                }
            }

            // Error
            if let msg = errorMessage {
                Text(msg)
                    .font(NuruFont.bodySmall())
                    .foregroundStyle(NuruColors.colorError)
                    .padding(.horizontal, NuruSpacing.space4)
                    .padding(.bottom, NuruSpacing.space2)
            }

            Divider().background(theme.borderColor)

            // Bottom toolbar
            HStack(spacing: NuruSpacing.space3) {
                // Image picker
                PhotosPicker(
                    selection: $selectedItems,
                    maxSelectionCount: 4,
                    matching: .images
                ) {
                    Image(systemName: "photo")
                        .font(.system(size: NuruSpacing.iconMd))
                        .foregroundStyle(selectedImages.isEmpty ? theme.textTertiary : NuruColors.lineGreen)
                }
                .onChange(of: selectedItems) { _, newItems in
                    Task { await loadSelectedImages(from: newItems) }
                }

                // CW toggle
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showCWInput.toggle() }
                    if !showCWInput { contentWarning = "" }
                } label: {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: NuruSpacing.iconMd))
                        .foregroundStyle(showCWInput
                            ? Color(red: 0.98, green: 0.67, blue: 0.0)
                            : theme.textTertiary)
                }
                .buttonStyle(.plain)

                // Custom emoji picker
                Button { showEmojiPicker.toggle() } label: {
                    Image(systemName: "face.smiling")
                        .font(.system(size: NuruSpacing.iconMd))
                        .foregroundStyle(selectedCustomEmojis.isEmpty
                            ? theme.textTertiary : NuruColors.lineGreen)
                }
                .buttonStyle(.plain)

                // Relay selection
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showRelayPanel.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: NuruSpacing.iconMd))
                        if hasRelayCustomization {
                            Circle().fill(NuruColors.lineGreen).frame(width: 6, height: 6)
                        }
                    }
                    .foregroundStyle(hasRelayCustomization
                        ? NuruColors.lineGreen : theme.textTertiary)
                }
                .buttonStyle(.plain)

                // STT (Speech-to-Text)
                Button {
                    if isSTTActive { stopSTT() } else { startSTT() }
                } label: {
                    Image(systemName: isSTTActive ? "mic.fill" : "mic")
                        .font(.system(size: NuruSpacing.iconMd))
                        .foregroundStyle(isSTTActive ? NuruColors.lineGreen : theme.textTertiary)
                }
                .buttonStyle(.plain)

                Spacer()

                // Character counter — always visible
                HStack(spacing: 4) {
                    Text("\(remaining)")
                        .font(NuruFont.bodySmall())
                        .foregroundStyle(remaining < 0 ? NuruColors.colorError
                            : remaining <= 20 ? Color(red: 0.98, green: 0.67, blue: 0.0)
                            : theme.textTertiary)

                    ZStack {
                        Circle()
                            .stroke(theme.bgTertiary, lineWidth: 2)
                        Circle()
                            .trim(from: 0, to: max(0, CGFloat(text.count) / CGFloat(UI.postMaxLength)))
                            .stroke(remaining < 0 ? NuruColors.colorError : NuruColors.lineGreen, lineWidth: 2)
                            .rotationEffect(.degrees(-90))
                    }
                    .frame(width: 20, height: 20)
                    .animation(.easeInOut(duration: 0.1), value: text.count)
                }
            }
            .padding(.horizontal, NuruSpacing.space4)
            .padding(.vertical, NuruSpacing.space3)
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
                onSelect: { emoji in
                    insertCustomEmoji(emoji)
                }
            )
            .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Hashtag Preview

    /// Shows a preview of the text with hashtags highlighted in LineGreen.
    /// iOS TextEditor does not support AttributedString inline, so we use
    /// a read-only overlay preview (matches Android AnnotatedString behavior).
    private var hashtagPreview: some View {
        let attributed = hashtagAttributedText(text)
        return VStack(alignment: .leading, spacing: NuruSpacing.space1) {
            HStack(spacing: NuruSpacing.space1) {
                Image(systemName: "eye")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textTertiary)
                Text("プレビュー")
                    .font(NuruFont.labelSmall())
                    .foregroundStyle(theme.textTertiary)
            }
            Text(attributed)
                .font(NuruFont.bodyMedium())
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(NuruSpacing.space2)
        .background(theme.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusSm))
    }

    /// Creates an AttributedString with hashtags colored in LineGreen.
    private func hashtagAttributedText(_ input: String) -> AttributedString {
        var result = AttributedString(input)
        result.foregroundColor = UIColor(theme.textPrimary)

        // Match #hashtag patterns (supports Japanese/unicode characters)
        let pattern = #"#[\p{L}\p{N}_]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return result }
        let nsString = input as NSString
        let matches = regex.matches(in: input, range: NSRange(location: 0, length: nsString.length))

        for match in matches {
            guard let swiftRange = Range(match.range, in: input) else { continue }
            let attrRange = result.range(of: String(input[swiftRange]))
            if let attrRange {
                result[attrRange].foregroundColor = UIColor(NuruColors.lineGreen)
            }
        }
        return result
    }

    // MARK: - Relay Panel Section

    @ViewBuilder
    private var relayPanelSection: some View {
        let panel = RelaySelectPanel(
            relays: allRelays,
            selectedRelays: $selectedRelays,
            nip70Protected: $nip70Protected
        )
        panel
            .padding(EdgeInsets(top: NuruSpacing.space2, leading: NuruSpacing.space4, bottom: NuruSpacing.space2, trailing: NuruSpacing.space4))
            .transition(AnyTransition.move(edge: .bottom).combined(with: AnyTransition.opacity))
    }

    // MARK: - Image Previews

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
                            if idx < selectedItems.count {
                                selectedItems.remove(at: idx)
                            }
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

    // MARK: - Image Loading

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

    // MARK: - Custom Emoji Insertion

    private func insertCustomEmoji(_ emoji: CustomEmoji) {
        let insert = ":\(emoji.shortcode):"
        guard (text + insert).count <= UI.postMaxLength else { return }
        text += insert
        if !selectedCustomEmojis.contains(where: { $0.shortcode == emoji.shortcode }) {
            selectedCustomEmojis.append(emoji)
        }
    }

    // MARK: - STT (Speech-to-Text)

    private func startSTT() {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                guard status == .authorized else {
                    errorMessage = "音声認識の許可が必要です"
                    return
                }
                beginRecording()
            }
        }
    }

    private func beginRecording() {
        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja-JP"))
        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "音声認識が利用できません"
            return
        }
        speechRecognizer = recognizer

        let engine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            let inputNode = engine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }

            engine.prepare()
            try engine.start()

            recognitionTask = recognizer.recognitionTask(with: request) { result, error in
                if let result {
                    let transcribed = result.bestTranscription.formattedString
                    DispatchQueue.main.async {
                        // Only update if within character limit
                        if transcribed.count <= UI.postMaxLength {
                            self.text = transcribed
                        }
                    }
                }
                if error != nil || (result?.isFinal ?? false) {
                    DispatchQueue.main.async { self.stopSTT() }
                }
            }

            self.audioEngine = engine
            self.recognitionRequest = request
            isSTTActive = true
        } catch {
            errorMessage = "録音を開始できませんでした"
        }
    }

    private func stopSTT() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        audioEngine = nil
        recognitionRequest = nil
        recognitionTask = nil
        isSTTActive = false
    }

    // MARK: - Posting

    private func handlePost() async {
        guard canPost else { return }
        isPosting    = true
        errorMessage = nil

        // Stop STT if active
        if isSTTActive { stopSTT() }

        // 並列画像アップロード（最大3枚同時）
        // Android: PostModal.kt の async { } / awaitAll() パターンに対応
        var content = text
        if !selectedImages.isEmpty {
            isUploading    = true
            uploadProgress = "画像をアップロード中..."

            let server        = repository.prefs.uploadServerEnum
            let uploadService = ImageUploadService(signer: repository.signer)
            let total         = selectedImages.count

            let urls = await uploadService.uploadImages(
                selectedImages,
                server: server,
                onProgress: { current, _ in
                    Task { @MainActor in
                        self.uploadProgress = "画像をアップロード中 (\(current)/\(total))..."
                    }
                }
            )

            if !urls.isEmpty {
                content += "\n" + urls.joined(separator: "\n")
            } else {
                // 全画像のアップロードが失敗
                isUploading = false
                uploadProgress = ""
                errorMessage = "画像のアップロードに失敗しました。ネットワークを確認してください。"
                isPosting = false
                return
            }
            isUploading    = false
            uploadProgress = ""
        }

        // Build custom emoji tags
        var emojiTags: [[String]] = []
        for emoji in selectedCustomEmojis {
            emojiTags.append(["emoji", emoji.shortcode, emoji.url])
        }

        // targetRelays: nil = broadcast to all, non-nil = specific relays only
        let targetRelayList: [String]? = selectedRelays.count != allRelays.count
            ? Array(selectedRelays) : nil

        do {
            try await repository.publishNote(
                content:        content,
                replyToId:      replyToId,
                contentWarning: showCWInput && !contentWarning.isEmpty ? contentWarning : nil,
                customTags:     emojiTags,
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
