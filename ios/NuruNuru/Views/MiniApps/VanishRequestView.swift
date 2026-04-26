import SwiftUI

/// NIP-62 Vanish Request — 全リレーまたは特定リレーへの削除依頼。
/// Mirrors Android VanishRequest.kt.
struct VanishRequestView: View {

    let repository:  NostrRepository

    @Environment(\.nuruTheme) private var theme
    @State private var mode:        VanishMode = .relay
    @State private var relayUrl:    String     = ""
    @State private var reason:      String     = ""
    @State private var confirm:     String     = ""
    @State private var isLoading:   Bool       = false
    @State private var result:      VanishResult? = nil

    private enum VanishMode { case relay, global }
    private enum VanishResult { case success, failure(String) }

    private var canSend: Bool {
        confirm == "削除" && !isLoading
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NuruSpacing.space4) {

                // 警告ボックス
                HStack(spacing: NuruSpacing.space2) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.red)
                    Text("この操作は取り消せません。送信後に投稿を復元することはできません。")
                        .font(NuruFont.bodySmall())
                        .foregroundStyle(theme.textPrimary)
                }
                .padding(NuruSpacing.space3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusMd))
                .overlay(RoundedRectangle(cornerRadius: NuruSpacing.radiusMd)
                    .stroke(Color.red.opacity(0.3), lineWidth: 1))

                // モード選択
                VStack(alignment: .leading, spacing: NuruSpacing.space2) {
                    Text("削除対象")
                        .font(NuruFont.bodyMedium())
                        .fontWeight(.semibold)
                        .foregroundStyle(theme.textPrimary)

                    HStack(spacing: NuruSpacing.space2) {
                        modeButton("特定リレー", mode: .relay, selectedColor: NuruColors.lineGreen)
                        modeButton("全リレー",   mode: .global, selectedColor: .red)
                    }
                }

                // リレーURL入力（特定リレーモード）
                if mode == .relay {
                    VStack(alignment: .leading, spacing: NuruSpacing.space2) {
                        Text("リレーURL")
                            .font(NuruFont.bodySmall())
                            .foregroundStyle(theme.textSecondary)
                        TextField("wss://", text: $relayUrl)
                            .font(NuruFont.bodyMedium())
                            .foregroundStyle(theme.textPrimary)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .padding(NuruSpacing.space3)
                            .background(theme.bgSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusMd))
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // 削除理由
                VStack(alignment: .leading, spacing: NuruSpacing.space2) {
                    Text("削除理由（任意）")
                        .font(NuruFont.bodySmall())
                        .foregroundStyle(theme.textSecondary)
                    TextEditor(text: $reason)
                        .font(NuruFont.bodyMedium())
                        .foregroundStyle(theme.textPrimary)
                        .scrollContentBackground(.hidden)
                        .frame(height: 80)
                        .padding(NuruSpacing.space2)
                        .background(theme.bgSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusMd))
                }

                // 安全確認入力
                VStack(alignment: .leading, spacing: NuruSpacing.space2) {
                    Text("確認のため「削除」と入力してください")
                        .font(NuruFont.bodySmall())
                        .foregroundStyle(theme.textSecondary)
                    TextField("削除", text: $confirm)
                        .font(NuruFont.bodyMedium())
                        .foregroundStyle(theme.textPrimary)
                        .padding(NuruSpacing.space3)
                        .background(theme.bgSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusMd))
                        .overlay(
                            RoundedRectangle(cornerRadius: NuruSpacing.radiusMd)
                                .stroke(confirm == "削除" ? Color.red : theme.borderColor, lineWidth: 1)
                        )
                }

                // 送信ボタン
                Button {
                    Task { await send() }
                } label: {
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    } else {
                        Text(mode == .global ? "全リレーに削除リクエストを送信" : "リレーに削除リクエストを送信")
                            .font(NuruFont.bodyMedium())
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    }
                }
                .background(canSend ? (mode == .global ? Color.red : Color.orange) : theme.bgTertiary)
                .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusMd))
                .buttonStyle(.plain)
                .disabled(!canSend)

                // 結果表示
                if let result {
                    resultBanner(result)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .padding(NuruSpacing.space4)
            .animation(.easeInOut(duration: 0.2), value: mode)
            .animation(.easeInOut(duration: 0.2), value: result != nil)
        }
        .background(theme.bgPrimary)
    }

    // MARK: - Subviews

    private func modeButton(_ label: String, mode: VanishMode, selectedColor: Color) -> some View {
        let selected = self.mode == mode
        return Button { self.mode = mode } label: {
            Text(label)
                .font(.system(size: 13, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? .white : theme.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(selected ? selectedColor : theme.bgSecondary)
                .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusSm))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func resultBanner(_ r: VanishResult) -> some View {
        switch r {
        case .success:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                Text("削除リクエストを送信しました")
            }
            .font(NuruFont.bodyMedium())
            .foregroundStyle(.white)
            .padding(NuruSpacing.space3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.green)
            .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusMd))

        case .failure(let msg):
            HStack(spacing: 6) {
                Image(systemName: "xmark.circle.fill")
                Text("エラー: \(msg)")
            }
            .font(NuruFont.bodyMedium())
            .foregroundStyle(.white)
            .padding(NuruSpacing.space3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red)
            .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusMd))
        }
    }

    // MARK: - Action

    private func send() async {
        isLoading = true
        let relays: [String]? = mode == .relay && !relayUrl.isEmpty ? [relayUrl] : nil
        do {
            try await repository.requestVanish(relays: relays, reason: reason)
            withAnimation { result = .success }
        } catch {
            withAnimation { result = .failure(error.localizedDescription) }
        }
        isLoading = false
    }
}
