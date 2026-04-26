import SwiftUI

// MARK: - Report Type

private struct ReportType: Identifiable {
    let id:          String
    let label:       String
    let description: String
}

private let reportTypes: [ReportType] = [
    ReportType(id: "spam",          label: "スパム",               description: "宣伝目的の迷惑投稿"),
    ReportType(id: "nudity",        label: "ヌード・性的コンテンツ", description: "露骨な性的コンテンツ"),
    ReportType(id: "profanity",     label: "ヘイトスピーチ",        description: "差別的・攻撃的な表現"),
    ReportType(id: "illegal",       label: "違法コンテンツ",        description: "法律に違反する可能性のある内容"),
    ReportType(id: "impersonation", label: "なりすまし",            description: "他人になりすましている"),
    ReportType(id: "malware",       label: "マルウェア",            description: "悪意のあるリンクやファイル"),
    ReportType(id: "other",         label: "その他",               description: "上記以外の問題"),
]

// MARK: - ReportSheet

/// 通報ダイアログ (7種類) — Mirrors Android ReportModal composable.
/// Usage: .sheet(isPresented:) { ReportSheet(onReport:onDismiss:) }
struct ReportSheet: View {
    let onReport:    (String, String) -> Void
    let onDismiss:   () -> Void
    var isSubmitting: Bool = false

    @State private var selectedType:    String? = nil
    @State private var additionalInfo:  String  = ""
    @Environment(\.nuruTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("投稿を通報")
                    .font(NuruFont.titleMedium())
                    .fontWeight(.bold)
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: NuruIcons.close)
                        .font(.system(size: 16))
                        .foregroundStyle(theme.textTertiary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, NuruSpacing.space4)

            Divider().background(theme.borderColor)

            // Body
            ScrollView {
                VStack(alignment: .leading, spacing: NuruSpacing.space3) {
                    Text("この投稿を通報する理由を選択してください。")
                        .font(NuruFont.bodySmall())
                        .foregroundStyle(theme.textSecondary)
                        .padding(.horizontal, 24)
                        .padding(.top, NuruSpacing.space4)

                    ForEach(reportTypes) { type in
                        reportRow(type)
                    }

                    if selectedType != nil {
                        VStack(alignment: .leading, spacing: NuruSpacing.space2) {
                            Text("追加情報 (任意)")
                                .font(NuruFont.labelSmall())
                                .foregroundStyle(theme.textSecondary)

                            TextEditor(text: $additionalInfo)
                                .font(NuruFont.bodySmall())
                                .foregroundStyle(theme.textPrimary)
                                .scrollContentBackground(.hidden)
                                .background(theme.bgSecondary)
                                .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusMd))
                                .overlay(
                                    RoundedRectangle(cornerRadius: NuruSpacing.radiusMd)
                                        .stroke(Color.red.opacity(0.5), lineWidth: 1)
                                )
                                .frame(height: 100)
                                .onChange(of: additionalInfo) { _, new in
                                    if new.count > 500 { additionalInfo = String(new.prefix(500)) }
                                }

                            Text("\(additionalInfo.count)/500")
                                .font(NuruFont.labelSmall())
                                .foregroundStyle(theme.textTertiary)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .padding(.horizontal, 24)
                    }
                }
                .padding(.bottom, NuruSpacing.space4)
            }

            // Footer buttons
            HStack(spacing: NuruSpacing.space3) {
                Button(action: onDismiss) {
                    Text("キャンセル")
                        .font(NuruFont.bodyMedium())
                        .foregroundStyle(theme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(theme.bgPrimary)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(theme.borderColor, lineWidth: 1))
                }
                .buttonStyle(.plain)

                Button {
                    if let t = selectedType { onReport(t, additionalInfo) }
                } label: {
                    Group {
                        if isSubmitting {
                            ProgressView().tint(.white)
                        } else {
                            Text("通報する")
                                .font(NuruFont.bodyMedium())
                                .fontWeight(.bold)
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(selectedType != nil && !isSubmitting ? Color.red : Color.red.opacity(0.4))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(selectedType == nil || isSubmitting)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, NuruSpacing.space5)
        }
        .background(theme.bgPrimary)
    }

    private func reportRow(_ type: ReportType) -> some View {
        let selected = selectedType == type.id
        return Button {
            selectedType = type.id
        } label: {
            HStack(spacing: NuruSpacing.space3) {
                // Radio button
                ZStack {
                    Circle()
                        .stroke(selected ? Color.red : theme.textTertiary, lineWidth: 2)
                        .frame(width: 18, height: 18)
                    if selected {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 10, height: 10)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(type.label)
                        .font(NuruFont.bodyMedium())
                        .fontWeight(.medium)
                        .foregroundStyle(theme.textPrimary)
                    Text(type.description)
                        .font(NuruFont.labelSmall())
                        .foregroundStyle(theme.textTertiary)
                }
                Spacer()
            }
            .padding(NuruSpacing.space3)
            .background(selected ? Color.red.opacity(0.05) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusMd))
            .overlay(
                RoundedRectangle(cornerRadius: NuruSpacing.radiusMd)
                    .stroke(selected ? Color.red : theme.borderColor, lineWidth: 1)
            )
            .padding(.horizontal, 24)
        }
        .buttonStyle(.plain)
    }
}
