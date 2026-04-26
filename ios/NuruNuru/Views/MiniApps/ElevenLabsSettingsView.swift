import SwiftUI

/// ElevenLabs TTS 設定 — APIキーと言語を保存。
/// Mirrors Android ElevenLabsSettingsApp.kt.
struct ElevenLabsSettingsView: View {

    let prefs: AppPreferences

    @Environment(\.nuruTheme) private var theme
    @State private var apiKey:     String = ""
    @State private var language:   String = "jpn"
    @State private var showKey:    Bool   = false
    @State private var saved:      Bool   = false
    @State private var isTesting:  Bool   = false
    @State private var testError:  String? = nil

    private let languages: [(code: String, label: String)] = [
        ("jpn", "日本語 (Japanese)"),
        ("eng", "英語 (English)"),
        ("cmn", "中国語 (Chinese)"),
        ("spa", "スペイン語 (Spanish)"),
        ("fra", "フランス語 (French)"),
        ("deu", "ドイツ語 (German)"),
        ("ita", "イタリア語 (Italian)"),
        ("por", "ポルトガル語 (Portuguese)"),
        ("hin", "ヒンディー語 (Hindi)")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NuruSpacing.space5) {

                // API キーセクション
                VStack(alignment: .leading, spacing: NuruSpacing.space2) {
                    Text("APIキー")
                        .font(NuruFont.bodyMedium())
                        .fontWeight(.semibold)
                        .foregroundStyle(theme.textPrimary)

                    HStack {
                        Group {
                            if showKey {
                                TextField("xi-api-key...", text: $apiKey)
                            } else {
                                SecureField("xi-api-key...", text: $apiKey)
                            }
                        }
                        .font(NuruFont.bodyMedium())
                        .foregroundStyle(theme.textPrimary)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                        Button {
                            showKey.toggle()
                        } label: {
                            Image(systemName: showKey ? "eye.slash" : "eye")
                                .font(.system(size: 16))
                                .foregroundStyle(theme.textTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(NuruSpacing.space3)
                    .background(theme.bgSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusMd))
                    .overlay(
                        RoundedRectangle(cornerRadius: NuruSpacing.radiusMd)
                            .stroke(apiKey.isEmpty ? theme.borderColor : NuruColors.lineGreen, lineWidth: 1)
                    )

                    Text("ElevenLabsダッシュボードから取得してください")
                        .font(NuruFont.labelSmall())
                        .foregroundStyle(theme.textTertiary)
                }

                // 言語セクション
                VStack(alignment: .leading, spacing: NuruSpacing.space2) {
                    Text("言語")
                        .font(NuruFont.bodyMedium())
                        .fontWeight(.semibold)
                        .foregroundStyle(theme.textPrimary)

                    Menu {
                        ForEach(languages, id: \.code) { lang in
                            Button {
                                language = lang.code
                            } label: {
                                HStack {
                                    Text(lang.label)
                                    if language == lang.code {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Text(languages.first(where: { $0.code == language })?.label ?? language)
                                .font(NuruFont.bodyMedium())
                                .foregroundStyle(NuruColors.lineGreen)
                            Spacer()
                            Image(systemName: NuruIcons.chevronDown)
                                .font(.system(size: 12))
                                .foregroundStyle(theme.textTertiary)
                        }
                        .padding(NuruSpacing.space3)
                        .background(theme.bgSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusMd))
                        .overlay(
                            RoundedRectangle(cornerRadius: NuruSpacing.radiusMd)
                                .stroke(theme.borderColor, lineWidth: 1)
                        )
                    }
                }

                // 保存ボタン
                Button {
                    prefs.elevenLabsApiKey   = apiKey
                    prefs.elevenLabsLanguage = language
                    withAnimation { saved = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation { saved = false }
                    }
                } label: {
                    HStack {
                        if saved {
                            Image(systemName: "checkmark")
                        }
                        Text(saved ? "保存しました" : "保存")
                    }
                    .font(NuruFont.bodyMedium())
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(saved ? Color.green : NuruColors.lineGreen)
                    .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusMd))
                }
                .buttonStyle(.plain)
                .animation(.easeInOut(duration: 0.2), value: saved)

                // テスト再生ボタン
                VStack(alignment: .leading, spacing: NuruSpacing.space2) {
                    Text("テスト再生")
                        .font(NuruFont.bodyMedium())
                        .fontWeight(.semibold)
                        .foregroundStyle(theme.textPrimary)

                    Button {
                        guard !apiKey.isEmpty else { return }
                        isTesting  = true
                        testError  = nil
                        let key    = apiKey
                        Task {
                            do {
                                try await ElevenLabsTTSService.shared.speak(
                                    text:   "こんにちは、ぬるぬるです。これはテスト再生です。",
                                    apiKey: key
                                )
                            } catch {
                                testError = error.localizedDescription
                            }
                            isTesting = false
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if isTesting {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .tint(.white)
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 16))
                            }
                            Text(isTesting ? "再生中..." : "テスト再生")
                        }
                        .font(NuruFont.bodyMedium())
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(apiKey.isEmpty || isTesting
                                    ? NuruColors.lineGreen.opacity(0.4)
                                    : NuruColors.lineGreen)
                        .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusMd))
                    }
                    .buttonStyle(.plain)
                    .disabled(apiKey.isEmpty || isTesting)

                    if let err = testError {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.circle")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.red)
                            Text(err)
                                .font(NuruFont.labelSmall())
                                .foregroundStyle(Color.red)
                        }
                    }
                }
            }
            .padding(NuruSpacing.space4)
        }
        .background(theme.bgPrimary)
        .onAppear {
            apiKey   = prefs.elevenLabsApiKey
            language = prefs.elevenLabsLanguage
        }
    }
}
