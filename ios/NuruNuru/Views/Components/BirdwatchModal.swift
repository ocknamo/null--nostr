import SwiftUI

// MARK: - Birdwatch Types

struct BirdwatchType: Identifiable {
    let value: String
    let label: String
    let icon:  String
    var id: String { value }
}

private let birdwatchTypes: [BirdwatchType] = [
    BirdwatchType(value: "misleading",      label: "誤解を招く情報", icon: "!"),
    BirdwatchType(value: "missing_context", label: "背景情報が不足", icon: "?"),
    BirdwatchType(value: "factual_error",   label: "事実誤認",       icon: "×"),
    BirdwatchType(value: "outdated",        label: "古い情報",       icon: "○"),
    BirdwatchType(value: "satire",          label: "風刺・ジョーク", icon: "S"),
]

// MARK: - BirdwatchModal

/// Context notes submission sheet.
/// Mirrors Android BirdwatchModal composable.
struct BirdwatchModal: View {

    var onDismiss:      () -> Void
    var onSubmit:       (String, String, String) -> Void   // type, content, sourceUrl
    var existingNotes:  [NostrEvent] = []
    var isSubmitting:   Bool         = false

    @State private var selectedType:  String? = nil
    @State private var noteContent:   String  = ""
    @State private var sourceUrl:     String  = ""
    @State private var showExisting:  Bool    = false

    @Environment(\.nuruTheme) private var theme

    private static let blue = Color(red: 0.13, green: 0.59, blue: 0.95)

    var body: some View {
        VStack(spacing: 0) {
            // Drag handle
            Capsule()
                .fill(theme.borderColor)
                .frame(width: 36, height: 4)
                .padding(.top, 8)

            // Header
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Self.blue)
                Text("Birdwatch")
                    .font(NuruFont.titleMedium())
                    .fontWeight(.bold)
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16))
                        .foregroundStyle(theme.textTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            Divider().background(theme.borderColor)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Existing notes toggle
                    if !existingNotes.isEmpty {
                        existingNotesSection
                    }

                    Text("この投稿に追加のコンテキストを提供してください。")
                        .font(NuruFont.bodySmall())
                        .foregroundStyle(theme.textSecondary)

                    // Type selection
                    typeSelectionSection

                    // Content field
                    contentSection

                    // Source URL
                    sourceUrlSection
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 8)
            }

            Divider().background(theme.borderColor)

            // Footer buttons
            HStack(spacing: 12) {
                Button(action: onDismiss) {
                    Text("キャンセル")
                        .font(NuruFont.bodyMedium())
                        .foregroundStyle(theme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(theme.borderColor, lineWidth: 1))
                }
                .buttonStyle(.plain)

                Button {
                    if let type = selectedType {
                        onSubmit(type, noteContent, sourceUrl)
                    }
                } label: {
                    Group {
                        if isSubmitting {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                        } else {
                            Text("追加する")
                                .font(NuruFont.bodyMedium())
                                .fontWeight(.bold)
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(canSubmit ? Self.blue : Self.blue.opacity(0.4))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit)
            }
            .padding(24)
        }
        .background(theme.bgPrimary)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var canSubmit: Bool {
        selectedType != nil && !noteContent.trimmingCharacters(in: .whitespaces).isEmpty && !isSubmitting
    }

    // MARK: - Sections

    private var existingNotesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showExisting.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: showExisting ? "chevron.up" : "info.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(theme.textSecondary)
                    Text("既存のコンテキスト (\(existingNotes.count)件)")
                        .font(NuruFont.bodySmall())
                        .fontWeight(.medium)
                        .foregroundStyle(theme.textSecondary)
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            if showExisting {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(existingNotes.prefix(3), id: \.id) { note in
                        Text(note.content)
                            .font(.system(size: 11))
                            .foregroundStyle(theme.textSecondary)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(theme.bgSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var typeSelectionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("コンテキストの種類")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.textSecondary)

            let rows = [Array(birdwatchTypes.prefix(2)), Array(birdwatchTypes.dropFirst(2).prefix(2)), [birdwatchTypes.last!]]
            VStack(spacing: 8) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 8) {
                        ForEach(row) { type in
                            BirdwatchTypeButton(
                                type:       type,
                                isSelected: selectedType == type.value,
                                onSelect:   { selectedType = type.value }
                            )
                        }
                    }
                }
            }
        }
    }

    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("コンテキストの内容 *")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.textSecondary)
            TextEditor(text: $noteContent)
                .font(NuruFont.bodySmall())
                .foregroundStyle(theme.textPrimary)
                .frame(height: 120)
                .padding(8)
                .background(theme.bgSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(noteContent.isEmpty ? theme.borderColor : Self.blue, lineWidth: 1)
                )
                .onChange(of: noteContent) {
                    if noteContent.count > 1000 {
                        noteContent = String(noteContent.prefix(1000))
                    }
                }
            if noteContent.isEmpty {
                Text("この投稿に関する追加情報を入力してください...")
                    .font(NuruFont.bodySmall())
                    .foregroundStyle(theme.textTertiary)
                    .allowsHitTesting(false)
                    .padding(.horizontal, 12)
                    .padding(.top, -100)
            }
        }
    }

    private var sourceUrlSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ソースURL (任意)")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.textSecondary)
            TextField("https://example.com/source", text: $sourceUrl)
                .font(NuruFont.bodySmall())
                .foregroundStyle(theme.textPrimary)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(10)
                .background(theme.bgSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(sourceUrl.isEmpty ? theme.borderColor : Self.blue, lineWidth: 1)
                )
        }
    }
}

// MARK: - Type Button

private struct BirdwatchTypeButton: View {

    let type:       BirdwatchType
    let isSelected: Bool
    let onSelect:   () -> Void

    @Environment(\.nuruTheme) private var theme

    private static let blue = Color(red: 0.13, green: 0.59, blue: 0.95)

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Self.blue : theme.bgSecondary)
                        .frame(width: 20, height: 20)
                    Text(type.icon)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(isSelected ? .white : theme.textTertiary)
                }
                Text(type.label)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                Spacer()
            }
            .padding(8)
            .background(isSelected ? Self.blue.opacity(0.1) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Self.blue : theme.borderColor, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }
}
