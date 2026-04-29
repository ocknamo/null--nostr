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
    @FocusState private var focusedField: BirdwatchFocusedField?

    @Environment(\.nuruTheme) private var theme

    private static let blue = Color(red: 0.13, green: 0.59, blue: 0.95)

    private enum BirdwatchFocusedField: Hashable {
        case content
        case sourceUrl
    }

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
                Button {
                    focusedField = nil
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16))
                        .foregroundStyle(theme.textTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            Divider().background(theme.borderColor)

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
            .padding(.bottom, 16)
            .frame(maxHeight: .infinity, alignment: .top)

            Divider().background(theme.borderColor)

            // Footer buttons
            HStack(spacing: 12) {
                Button {
                    focusedField = nil
                    onDismiss()
                } label: {
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
                    focusedField = nil
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
        // Prevent the iOS keyboard swipe-down gesture from dismissing the entire sheet.
        // Birdwatch can still be closed explicitly via xmark / キャンセル / 追加する.
        .interactiveDismissDisabled(true)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完了") {
                    focusedField = nil
                }
                .font(.system(size: 15, weight: .semibold))
            }
        }
    }

    private var canSubmit: Bool {
        selectedType != nil && !noteContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSubmitting
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
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(theme.bgSecondary)

                TextEditor(text: $noteContent)
                    .font(NuruFont.bodySmall())
                    .foregroundStyle(theme.textPrimary)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .padding(8)
                    .focused($focusedField, equals: .content)
                    .onChange(of: noteContent) { _, newValue in
                        if newValue.count > 1000 {
                            noteContent = String(newValue.prefix(1000))
                        }
                    }

                if noteContent.isEmpty {
                    Text("この投稿に関する追加情報を入力してください...")
                        .font(NuruFont.bodySmall())
                        .foregroundStyle(theme.textTertiary)
                        .allowsHitTesting(false)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 18)
                }
            }
            .frame(height: 140)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(noteContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? theme.borderColor : Self.blue, lineWidth: 1)
            )
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
                .focused($focusedField, equals: .sourceUrl)
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

    private enum BirdwatchFocusedField: Hashable {
        case content
        case sourceUrl
    }

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
