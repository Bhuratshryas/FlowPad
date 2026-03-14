import SwiftUI

/// App-wide design system: color hierarchy and spacing for a professional, readable UI.
/// Color theory: primary (attention) → strong neutrals (content) → softer neutrals (support).
enum AppTheme {
    // MARK: - Text (hierarchy)
    /// Headings, titles, primary content — highest emphasis.
    static let textPrimary = Color(white: 0.12)
    /// Supporting text, metadata, secondary content.
    static let textSecondary = Color(white: 0.40)
    /// Hints, placeholders, disabled state.
    static let textTertiary = Color(white: 0.55)

    // MARK: - Surfaces (elevation)
    /// Page / canvas background.
    static let surfaceBase = Color(white: 0.97)
    /// Section headers, grouped bars — one step above base.
    static let surfaceOverlay = Color(white: 0.93)
    /// Cards, inputs — elevated content.
    static let surfaceRaised = Color.white
    /// Borders and dividers.
    static let border = Color(white: 0.88)
    /// Subtle border for raised surfaces.
    static let borderSubtle = Color(white: 0.92)

    // MARK: - Semantic (use sparingly)
    /// Primary actions, links, key icons — accent only.
    static var accent: Color { Color.accentColor }
    static let destructive = Color.red
    static let pin = Color.orange

    // MARK: - Spacing
    static let spacingXS: CGFloat = 4
    static let spacingS: CGFloat = 8
    static let spacingM: CGFloat = 16
    static let spacingL: CGFloat = 24
    static let radiusCard: CGFloat = 12
    static let radiusInput: CGFloat = 10
}
