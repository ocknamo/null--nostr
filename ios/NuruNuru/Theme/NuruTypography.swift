// ============================================================
// Auto-generated from design-tokens/constants.json — DO NOT EDIT
// Run: npm run tokens
// ============================================================

import SwiftUI

/// LINE Seed JP font family — must be bundled in the app.
/// Mirrors Android's LineSeedJP FontFamily in Type.kt.
///
/// Font files: Resources/Fonts/LineSeedJP-Rg.ttf, LineSeedJP-Bd.ttf
/// Registered in Info.plist under UIAppFonts.
enum NuruFont {

    // MARK: - Font Names (PostScript names embedded in the TTF files)
    // Verified via font binary inspection: LINESeedJP-Regular / LINESeedJP-Bold
    static let regular = "LINESeedJP-Regular"
    static let bold    = "LINESeedJP-Bold"

    // MARK: - Text Styles (matching Android Type.kt)

    /// 16pt regular, lineHeight 24pt — body text
    static func bodyLarge() -> Font {
        .custom(regular, size: 16, relativeTo: .body)
    }

    /// 14pt regular, lineHeight 20pt
    static func bodyMedium() -> Font {
        .custom(regular, size: 14, relativeTo: .callout)
    }

    /// 12pt regular, lineHeight 16pt
    static func bodySmall() -> Font {
        .custom(regular, size: 12, relativeTo: .footnote)
    }

    /// 20pt semibold, lineHeight 28pt — screen titles
    static func titleLarge() -> Font {
        .custom(bold, size: 20, relativeTo: .title2)
    }

    /// 16pt semibold, lineHeight 24pt — section headers
    static func titleMedium() -> Font {
        .custom(bold, size: 16, relativeTo: .headline)
    }

    /// 10pt medium, lineHeight 14pt — metadata labels
    static func labelSmall() -> Font {
        .custom(regular, size: 10, relativeTo: .caption2)
    }

    /// 18pt bold — primary action buttons
    static func buttonLarge() -> Font {
        .custom(bold, size: 18, relativeTo: .headline)
    }

    /// 16pt bold — secondary action buttons
    static func buttonMedium() -> Font {
        .custom(bold, size: 16, relativeTo: .subheadline)
    }

    /// 32pt bold — display / logo
    static func displayLarge() -> Font {
        .custom(bold, size: 32, relativeTo: .largeTitle)
    }
}
