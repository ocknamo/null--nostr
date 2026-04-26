import SwiftUI

/// Lightning zap sheet — mirrors Android ZapModal.kt.
/// NIP-57: generates zap request (kind 9734), fetches LNURL invoice, copies to clipboard.
struct ZapSheet: View {

    let repository:    NostrRepository
    let myPubkeyHex:   String
    let targetPost:    ScoredPost

    @Environment(\.dismiss)    private var dismiss
    @Environment(\.nuruTheme) private var theme
    @State private var amount:   String  = ""
    @State private var comment:  String  = ""
    @State private var isLoading: Bool   = false
    @State private var error:    String? = nil
    @State private var didCopy:  Bool    = false

    private let presets = [21, 100, 500, 1000, 5000, 10000]
    private let maxComment = 100

    private var amountInt: Int { Int(amount) ?? 0 }
    private var canSend:   Bool { amountInt > 0 && !isLoading }

    var body: some View {
        VStack(spacing: 0) {
            SheetNavBar(title: "Zap", onDismiss: { dismiss() }) {
                Color.clear.frame(width: 40, height: 40)
            }

            ScrollView {
                VStack(spacing: NuruSpacing.space4) {
                    // Recipient
                    recipientRow

                    // Amount input
                    VStack(alignment: .leading, spacing: NuruSpacing.space2) {
                        Text("金額 (sats)")
                            .font(NuruFont.labelSmall())
                            .foregroundStyle(theme.textTertiary)

                        TextField("0", text: $amount)
                            .font(.system(size: 32, weight: .semibold))
                            .foregroundStyle(theme.textPrimary)
                            .multilineTextAlignment(.center)
                            .keyboardType(.numberPad)
                            .padding(.vertical, NuruSpacing.space3)
                            .background(theme.bgSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusMd))
                    }

                    // Preset buttons
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: NuruSpacing.space2), count: 3),
                        spacing: NuruSpacing.space2
                    ) {
                        ForEach(presets, id: \.self) { preset in
                            Button {
                                amount = "\(preset)"
                            } label: {
                                Text("⚡ \(preset)")
                                    .font(NuruFont.bodyMedium())
                                    .foregroundStyle(amountInt == preset ? .white : NuruColors.colorZap)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, NuruSpacing.space2)
                                    .background(amountInt == preset ? NuruColors.colorZap : NuruColors.colorZap.opacity(0.15))
                                    .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusMd))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Comment
                    VStack(alignment: .leading, spacing: NuruSpacing.space2) {
                        HStack {
                            Text("コメント (任意)")
                                .font(NuruFont.labelSmall())
                                .foregroundStyle(theme.textTertiary)
                            Spacer()
                            Text("\(comment.count)/\(maxComment)")
                                .font(NuruFont.labelSmall())
                                .foregroundStyle(comment.count > maxComment ? NuruColors.colorError : theme.textTertiary)
                        }
                        TextField("応援メッセージ…", text: $comment, axis: .vertical)
                            .font(NuruFont.bodyMedium())
                            .foregroundStyle(theme.textPrimary)
                            .lineLimit(1...3)
                            .padding(NuruSpacing.space3)
                            .background(theme.bgSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusMd))
                            .onChange(of: comment) { _, v in
                                if v.count > maxComment { comment = String(v.prefix(maxComment)) }
                            }
                    }

                    // Error
                    if let err = error {
                        Text(err)
                            .font(NuruFont.bodySmall())
                            .foregroundStyle(NuruColors.colorError)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // Send button
                    Button(action: { Task { await sendZap() } }) {
                        Group {
                            if isLoading {
                                ProgressView().tint(.white)
                            } else if didCopy {
                                Label("コピーしました", systemImage: "checkmark")
                                    .font(NuruFont.buttonMedium())
                                    .foregroundStyle(.white)
                            } else {
                                Label("インボイスを生成", systemImage: "bolt.fill")
                                    .font(NuruFont.buttonMedium())
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(canSend ? NuruColors.colorZap : NuruColors.colorZap.opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusFull))
                    }
                    .disabled(!canSend)
                }
                .padding(NuruSpacing.space4)
            }
        }
        .background(theme.bgPrimary.ignoresSafeArea())
    }

    // MARK: - Recipient Row

    private var recipientRow: some View {
        HStack(spacing: NuruSpacing.space3) {
            AvatarView(
                url:  targetPost.profile?.picture,
                name: targetPost.profile?.displayedName ?? "?",
                size: 40
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(targetPost.profile?.displayedName ?? "Unknown")
                    .font(NuruFont.bodyMedium())
                    .foregroundStyle(theme.textPrimary)
                if let lud16 = targetPost.profile?.lud16 {
                    Text(lud16)
                        .font(NuruFont.bodySmall())
                        .foregroundStyle(theme.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Image(systemName: "bolt.fill")
                .foregroundStyle(NuruColors.colorZap)
        }
        .padding(NuruSpacing.space3)
        .background(theme.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusLg))
    }

    // MARK: - Send

    private func sendZap() async {
        guard canSend else { return }
        isLoading = true
        error     = nil
        do {
            let invoice = try await repository.generateZapInvoice(
                toEventId:     targetPost.event.id,
                toRecipient:   targetPost.event.pubkey,
                amountSats:    amountInt,
                comment:       comment.isEmpty ? nil : comment,
                myPubkeyHex:   myPubkeyHex
            )
            // Copy invoice to clipboard
            UIPasteboard.general.string = invoice
            didCopy = true
            // Dismiss after short delay
            try? await Task.sleep(for: .seconds(1.5))
            dismiss()
        } catch {
            self.error = "Zapの生成に失敗しました: \(error.localizedDescription)"
        }
        isLoading = false
    }
}
