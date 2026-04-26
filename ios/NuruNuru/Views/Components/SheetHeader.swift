import SwiftUI

/// Drag handle shown at the top of bottom sheets.
struct SheetDragHandle: View {
    @Environment(\.nuruTheme) private var theme

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(theme.borderStrong)
            .frame(width: 36, height: 4)
            .padding(.top, NuruSpacing.space2)
    }
}

/// Standard sheet nav bar: drag handle + [xmark] [title] [trailing].
///
/// Pass a `Color.clear.frame(width: 40, height: 40)` trailing when no action is needed,
/// or any button/label to balance the layout.
struct SheetNavBar<Trailing: View>: View {
    let title:     String
    let onDismiss: () -> Void
    @ViewBuilder let trailing: () -> Trailing

    @Environment(\.nuruTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            SheetDragHandle()

            HStack {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(theme.textPrimary)
                        .frame(width: 40, height: 40)
                }
                Spacer()
                Text(title)
                    .font(NuruFont.titleMedium())
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                trailing()
            }
            .padding(.horizontal, NuruSpacing.space4)

            Divider().background(theme.borderColor)
        }
    }
}
