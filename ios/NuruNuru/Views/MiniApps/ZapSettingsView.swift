import SwiftUI

// Zap settings mini-app.
struct ZapSettingsView: View {

    let prefs: AppPreferences
    @Environment(\.nuruTheme) private var theme

    @State private var selected: Int = 21
    @State private var showCustomInput: Bool = false
    @State private var customAmount: String = ""

    private let presets = [21, 100, 500, 1000, 5000, 10000]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NuruSpacing.space5) {
                VStack(alignment: .leading, spacing: NuruSpacing.space2) {
                    Text("デフォルトZap金額")
                        .font(NuruFont.labelSmall())
                        .foregroundStyle(theme.textTertiary)
                    HStack {
                        Image(systemName: NuruIcons.bitcoin)
                            .foregroundStyle(NuruColors.colorZap)
                        Text("₿\(selected.formatted(.number.grouping(.automatic)))")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(theme.textPrimary)
                    }
                }
                .padding(NuruSpacing.space4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.bgSecondary)
                .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusLg))

                VStack(alignment: .leading, spacing: NuruSpacing.space2) {
                    Text("クイック設定")
                        .font(NuruFont.labelSmall())
                        .foregroundStyle(theme.textTertiary)
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: NuruSpacing.space2), count: 3),
                        spacing: NuruSpacing.space2
                    ) {
                        ForEach(presets, id: \.self) { preset in
                            Button { apply(amount: preset) } label: {
                                Text("₿\(preset.formatted(.number.grouping(.automatic)))")
                                    .font(NuruFont.bodyMedium())
                                    .foregroundStyle(selected == preset ? .white : NuruColors.colorZap)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, NuruSpacing.space3)
                                    .background(selected == preset ? NuruColors.colorZap : NuruColors.colorZap.opacity(0.15))
                                    .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusMd))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: NuruSpacing.space2) {
                    if showCustomInput {
                        HStack(spacing: NuruSpacing.space2) {
                            TextField("金額", text: $customAmount)
                                .font(NuruFont.bodyMedium())
                                .foregroundStyle(theme.textPrimary)
                                .keyboardType(.numberPad)
                                .padding(.horizontal, NuruSpacing.space3)
                                .frame(height: 48)
                                .background(theme.bgSecondary)
                                .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusMd))
                                .onChange(of: customAmount) { _, value in
                                    customAmount = String(value.filter(\.isNumber).prefix(12))
                                }

                            Button {
                                guard let amount = Int(customAmount), amount > 0 else { return }
                                apply(amount: amount)
                            } label: {
                                Text("設定")
                                    .font(NuruFont.buttonMedium())
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, NuruSpacing.space4)
                                    .frame(height: 48)
                                    .background(NuruColors.lineGreen)
                                    .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusMd))
                            }
                            .buttonStyle(.plain)

                            Button {
                                showCustomInput = false
                                customAmount = ""
                            } label: {
                                Image(systemName: "xmark")
                                    .foregroundStyle(theme.textTertiary)
                                    .frame(width: 36, height: 36)
                            }
                            .buttonStyle(.plain)
                        }
                    } else {
                        Button { showCustomInput = true } label: {
                            Text("カスタム金額を設定")
                                .font(NuruFont.bodyMedium())
                                .foregroundStyle(NuruColors.lineGreen)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, NuruSpacing.space2)
                        }
                        .buttonStyle(.plain)
                    }

                    Text("現在の設定: ₿\(selected.formatted(.number.grouping(.automatic)))")
                        .font(NuruFont.labelSmall())
                        .foregroundStyle(theme.textTertiary)
                        .padding(.horizontal, NuruSpacing.space1)
                }
            }
            .padding(NuruSpacing.space4)
        }
        .background(theme.bgPrimary)
        .onAppear { selected = max(1, prefs.defaultZapAmount) }
    }

    private func apply(amount: Int) {
        selected = amount
        prefs.defaultZapAmount = amount
        showCustomInput = false
        customAmount = ""
    }
}
