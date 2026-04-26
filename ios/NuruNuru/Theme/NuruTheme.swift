import SwiftUI

/// Adaptive color set resolved for the current color scheme.
/// Injected via the environment so all views get consistent theming.
/// Usage: @Environment(\.nuruTheme) private var theme
struct NuruTheme {
    let bgPrimary:     Color
    let bgSecondary:   Color
    let bgTertiary:    Color
    let textPrimary:   Color
    let textSecondary: Color
    let textTertiary:  Color
    let borderColor:   Color
    let borderStrong:  Color

    static let dark = NuruTheme(
        bgPrimary:     NuruColors.bgPrimary,
        bgSecondary:   NuruColors.bgSecondary,
        bgTertiary:    NuruColors.bgTertiary,
        textPrimary:   NuruColors.textPrimary,
        textSecondary: NuruColors.textSecondary,
        textTertiary:  NuruColors.textTertiary,
        borderColor:   NuruColors.borderColor,
        borderStrong:  NuruColors.borderStrong
    )

    static let light = NuruTheme(
        bgPrimary:     NuruColors.bgPrimaryLight,
        bgSecondary:   NuruColors.bgSecondaryLight,
        bgTertiary:    NuruColors.bgTertiaryLight,
        textPrimary:   NuruColors.textPrimaryLight,
        textSecondary: NuruColors.textSecondaryLight,
        textTertiary:  NuruColors.textTertiaryLight,
        borderColor:   NuruColors.borderColorLight,
        borderStrong:  NuruColors.borderColorLight
    )
}

// MARK: - Environment Key

private struct NuruThemeKey: EnvironmentKey {
    static let defaultValue = NuruTheme.dark
}

extension EnvironmentValues {
    var nuruTheme: NuruTheme {
        get { self[NuruThemeKey.self] }
        set { self[NuruThemeKey.self] = newValue }
    }
}
