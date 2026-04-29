import SwiftUI
import PhotosUI
import Speech
import AVFoundation

/// Compose a new post — 140-char limit, CW toggle, image attachment,
/// relay selection, NIP-70 protection, custom emoji insertion, and STT.
/// Mirrors Android PostModal.kt.
struct PostSheet: View {

    let repository:   NostrRepository
    let myPubkeyHex:  String
    var myProfile:    UserProfile?
    var initialText:  String = ""
    var initialMentionProfile: UserProfile? = nil
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

    // Mentions (NIP-27): @username suggestions are limited to followed users.
    // NIP-05 (name@domain) and npub/nprofile can also be converted to nostr:npub... mentions.
    @State private var followedMentionUsers: [MentionCandidate] = []
    @State private var mentionSuggestions:   [MentionCandidate] = []
    @State private var mentionAliases:       [String: String] = [:]  // lowercased display token -> pubkey
    @State private var isLoadingMentions:    Bool = false

    // STT (Speech-to-Text)
    @State private var isSTTActive:    Bool          = false
    @State private var speechRecognizer: SFSpeechRecognizer? = nil
    @State private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest? = nil
    @State private var recognitionTask:   SFSpeechRecognitionTask? = nil
    @State private var audioEngine:       AVAudioEngine? = nil
    @State private var sttBaseText:       String        = ""

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
                                .onChange(of: text) { _, newValue in
                                    updateMentionSuggestions(for: newValue)
                                }
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

                    mentionSuggestionSection
                        .padding(.horizontal, NuruSpacing.space4)
                        .padding(.bottom, mentionSuggestions.isEmpty ? 0 : NuruSpacing.space2)

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

                    // Custom emoji preview row — mirrors Android PostModal.kt
                    if !selectedCustomEmojis.isEmpty {
                        customEmojiPreviewRow
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

            // Bottom toolbar — mirrors Android PostToolbar order/icons:
            // Image / CW / Emoji / Mic / Router / spacer / remaining count
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
                relayPanelSection
            }
        }
        .background(theme.bgPrimary.ignoresSafeArea())
        .onAppear {
            if let target = initialMentionProfile {
                mentionAliases[target.displayedName.lowercased()] = target.pubkey
                if let name = target.name, !name.isEmpty { mentionAliases[name.lowercased()] = target.pubkey }
                if text.isEmpty {
                    text = "@\(target.displayedName) "
                }
            } else if text.isEmpty && !initialText.isEmpty {
                text = initialText
            }
            fieldFocused = true
            Task {
                let relays = await repository.getSavedRelayUrls()
                allRelays = relays
                selectedRelays = Set(relays)
                await loadMentionCandidates()
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


    // MARK: - Mentions

    @ViewBuilder
    private var mentionSuggestionSection: some View {
        if !mentionSuggestions.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(mentionSuggestions) { candidate in
                        Button {
                            insertMention(candidate)
                        } label: {
                            HStack(spacing: 6) {
                                AvatarView(
                                    url: candidate.profile.picture,
                                    name: candidate.displayName,
                                    size: 24
                                )
                                VStack(alignment: .leading, spacing: 0) {
                                    Text("@\(candidate.displayName)")
                                        .font(NuruFont.labelSmall())
                                        .foregroundStyle(theme.textPrimary)
                                        .lineLimit(1)
                                    if let nip05 = candidate.profile.nip05, !nip05.isEmpty {
                                        Text(formatPostSheetNip05(nip05))
                                            .font(.system(size: 10))
                                            .foregroundStyle(theme.textTertiary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(theme.bgSecondary)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func loadMentionCandidates() async {
        guard followedMentionUsers.isEmpty else { return }
        let follows = await repository.fetchFollowList(pubkey: myPubkeyHex)
        let profiles = await repository.fetchProfiles(pubkeys: follows)
        let profileMap = Dictionary(uniqueKeysWithValues: profiles.map { ($0.pubkey, $0) })
        let candidates = follows.map { pubkey -> MentionCandidate in
            MentionCandidate(profile: profileMap[pubkey] ?? UserProfile(pubkey: pubkey))
        }
        await MainActor.run {
            followedMentionUsers = candidates.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            updateMentionSuggestions(for: text)
        }
    }

    private func currentMentionToken(in input: String) -> String? {
        guard let atIndex = input.lastIndex(of: "@") else { return nil }
        let token = String(input[atIndex...])
        guard !token.dropFirst().isEmpty,
              token.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return nil }
        return token
    }

    private func updateMentionSuggestions(for input: String) {
        guard let token = currentMentionToken(in: input) else {
            mentionSuggestions = []
            return
        }
        let query = String(token.dropFirst()).lowercased()
        guard !query.contains("@"), !query.hasPrefix("npub1"), !query.hasPrefix("nprofile1") else {
            mentionSuggestions = []
            return
        }
        // Username search is intentionally restricted to followed users only.
        mentionSuggestions = followedMentionUsers.filter { candidate in
            candidate.searchKeys.contains { $0.contains(query) }
        }.prefix(8).map { $0 }
    }

    private func insertMention(_ candidate: MentionCandidate) {
        mentionAliases[candidate.displayName.lowercased()] = candidate.profile.pubkey
        if let name = candidate.profile.name, !name.isEmpty { mentionAliases[name.lowercased()] = candidate.profile.pubkey }
        replaceCurrentMentionToken(with: "@\(candidate.displayName) ")
    }

    private func replaceCurrentMentionToken(with replacement: String) {
        guard let atIndex = text.lastIndex(of: "@") else { return }
        let prefix = String(text[..<atIndex])
        let newText = prefix + replacement
        guard newText.count <= UI.postMaxLength else {
            errorMessage = "投稿は\(UI.postMaxLength)文字以内で入力してください"
            return
        }
        text = newText
        mentionSuggestions = []
    }


    private func normalizeTypedMentions(in content: String) async -> String {
        let pattern = #"@[\p{L}\p{N}._+\-]+(?:@[A-Za-z0-9.-]+)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return content }
        let ns = content as NSString
        let matches = regex.matches(in: content, range: NSRange(location: 0, length: ns.length)).reversed()
        var output = content

        for match in matches {
            let raw = ns.substring(with: match.range)
            let token = String(raw.dropFirst())
            guard !token.isEmpty else { continue }

            let npub: String?
            let lowered = token.lowercased()
            if lowered.hasPrefix("npub1") || lowered.hasPrefix("nprofile1") {
                npub = npubForMentionBech32(lowered)
            } else if token.contains("@") {
                npub = await npubForNip05(token)
            } else {
                // Username mentions are intentionally limited to followed users only.
                npub = npubForFollowedUsername(token)
            }

            guard let npub else { continue }
            if let range = Range(match.range, in: output) {
                output.replaceSubrange(range, with: "nostr:\(npub)")
            }
        }
        return output
    }

    private func npubForMentionBech32(_ bech32: String) -> String? {
        guard let parsed = NostrBech32.decode(bech32),
              parsed.type == .npub || parsed.type == .nprofile,
              let bytes = NostrKeyUtils.hexToBytes(parsed.hex), bytes.count == 32 else { return nil }
        return NIP19.encodeNpub(bytes)
    }

    private func npubForNip05(_ identifier: String) async -> String? {
        guard let pubkey = await repository.resolveNip05(identifier),
              let bytes = NostrKeyUtils.hexToBytes(pubkey), bytes.count == 32 else { return nil }
        return NIP19.encodeNpub(bytes)
    }

    private func npubForFollowedUsername(_ username: String) -> String? {
        let lowered = username.lowercased()
        if let pubkey = mentionAliases[lowered],
           let bytes = NostrKeyUtils.hexToBytes(pubkey), bytes.count == 32 {
            return NIP19.encodeNpub(bytes)
        }
        guard let candidate = followedMentionUsers.first(where: { candidate in
            let names = [candidate.profile.name, candidate.profile.displayName, candidate.displayName]
            return names.compactMap { $0?.lowercased() }.contains(lowered)
        }) else { return nil }
        return candidate.npub
    }

    private func extractMentionPTags(from content: String) -> [[String]] {
        let pattern = #"nostr:(?:npub1|nprofile1)[a-z0-9]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let ns = content as NSString
        var seen = Set<String>()
        var tags: [[String]] = []
        for match in regex.matches(in: content, range: NSRange(location: 0, length: ns.length)) {
            let raw = ns.substring(with: match.range)
            let bech32 = String(raw.dropFirst("nostr:".count)).lowercased()
            guard let parsed = NostrBech32.decode(bech32),
                  (parsed.type == .npub || parsed.type == .nprofile),
                  seen.insert(parsed.hex).inserted else { continue }
            tags.append(["p", parsed.hex])
        }
        return tags
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

    // MARK: - Custom Emoji Preview

    private var customEmojiPreviewRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(selectedCustomEmojis) { emoji in
                    HStack(spacing: 4) {
                        if let url = URL(string: emoji.url) {
                            AnimatedRemoteImage(url: url) {
                                Color.clear
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

        // Convert typed mentions before signing:
        // - @npub1... / @nprofile1... → nostr:...
        // - @name@domain (NIP-05) → resolve and convert to nostr:npub...
        // - @username → followed users only (exact profile name/display-name match)
        content = await normalizeTypedMentions(in: content)
        guard content.count <= UI.postMaxLength else {
            errorMessage = "メンション展開後の投稿は\(UI.postMaxLength)文字以内で入力してください"
            isPosting = false
            return
        }

        // Build custom emoji + mention tags.
        // NIP-27 profile mentions are written as nostr:npub... in content and p tags in the event.
        var customTags: [[String]] = []
        for emoji in selectedCustomEmojis {
            customTags.append(["emoji", emoji.shortcode, emoji.url])
        }
        customTags.append(contentsOf: extractMentionPTags(from: content))

        // targetRelays: nil = broadcast to all, non-nil = specific relays only
        let targetRelayList: [String]? = selectedRelays.count != allRelays.count
            ? Array(selectedRelays) : nil

        do {
            try await repository.publishNote(
                content:        content,
                replyToId:      replyToId,
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


private struct MentionCandidate: Identifiable {
    let profile: UserProfile
    var id: String { profile.pubkey }

    var displayName: String { profile.displayedName }

    var npub: String? {
        guard let bytes = NostrKeyUtils.hexToBytes(profile.pubkey), bytes.count == 32 else { return nil }
        return NIP19.encodeNpub(bytes)
    }

    var searchKeys: [String] {
        [profile.displayName, profile.name, profile.nip05]
            .compactMap { $0?.lowercased() }
            .filter { !$0.isEmpty }
    }
}

private func formatPostSheetNip05(_ nip05: String) -> String {
    nip05.hasPrefix("_@") ? String(nip05.dropFirst(2)) : nip05
}
