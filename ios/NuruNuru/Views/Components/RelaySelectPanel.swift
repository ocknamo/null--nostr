import SwiftUI

/// Relay selection panel with NIP-70 protection toggle.
/// Mirrors Android RelaySelectPanel in PostModal.kt.
struct RelaySelectPanel: View {
    let relays: [String]
    @Binding var selectedRelays: Set<String>
    @Binding var nip70Protected: Bool

    @Environment(\.nuruTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: NuruSpacing.space2) {
            ForEach(relays, id: \.self) { url in
                HStack(spacing: NuruSpacing.space2) {
                    Image(systemName: selectedRelays.contains(url)
                          ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18))
                        .foregroundStyle(selectedRelays.contains(url)
                                         ? NuruColors.lineGreen : theme.textTertiary)
                    Text(url.replacingOccurrences(of: "wss://", with: ""))
                        .font(NuruFont.bodySmall())
                        .foregroundStyle(theme.textPrimary)
                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if selectedRelays.contains(url) {
                        // Prevent deselecting all relays
                        if selectedRelays.count > 1 {
                            selectedRelays.remove(url)
                        }
                    } else {
                        selectedRelays.insert(url)
                    }
                }
            }

            Divider().background(theme.borderColor)

            // NIP-70 toggle
            HStack(spacing: NuruSpacing.space2) {
                Image(systemName: nip70Protected ? "lock.fill" : "lock.open")
                    .font(.system(size: 16))
                    .foregroundStyle(nip70Protected ? NuruColors.lineGreen : theme.textTertiary)
                Text("リレーによる再配信を防止")
                    .font(NuruFont.bodySmall())
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                Toggle("", isOn: $nip70Protected)
                    .toggleStyle(SwitchToggleStyle(tint: NuruColors.lineGreen))
                    .labelsHidden()
            }
        }
        .padding(NuruSpacing.space3)
        .background(theme.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusMd))
    }
}
