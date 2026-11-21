import SwiftUI

/// Semantic color tokens for DormRun. Always use these — never hardcode colors in views.
enum AppColors {
    // MARK: - Brand

    /// DormRun orange-red — primary CTAs and key accents.
    static let brand = Color("Brand", bundle: .main)

    /// Brighter orange highlight for secondary accents and busy/closing-soon chips.
    static let accentWarm = Color("AccentWarm", bundle: .main)

    /// Logo gradient (bright orange → deep vermillion).
    static let brandGradient = LinearGradient(
        colors: [Color(hex: "#F15014"), Color(hex: "#B11616")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: - Surfaces

    static let background = Color("Background", bundle: .main)
    static let surface = Color("Surface", bundle: .main)
    static let surfaceElevated = Color("SurfaceElevated", bundle: .main)
    static let surfaceMuted = Color("SurfaceMuted", bundle: .main)

    // MARK: - Text

    static let textPrimary = Color("TextPrimary", bundle: .main)
    static let textSecondary = Color("TextSecondary", bundle: .main)
    static let textTertiary = Color("TextTertiary", bundle: .main)
    static let textOnBrand = Color("TextOnBrand", bundle: .main)
    static let textOnDark = Color("TextOnDark", bundle: .main)

    // MARK: - Borders & Dividers

    static let border = Color("Border", bundle: .main)
    static let separator = Color("Separator", bundle: .main)

    // MARK: - Semantic Status

    static let success = Color("Success", bundle: .main)
    static let warning = Color("Warning", bundle: .main)
    static let danger = Color("Danger", bundle: .main)
    static let info = Color("Info", bundle: .main)

    // MARK: - Open / Busy Indicators

    static let statusOpen = Color("StatusOpen", bundle: .main)
    static let statusClosingSoon = Color("StatusClosingSoon", bundle: .main)
    static let statusClosed = Color("StatusClosed", bundle: .main)
    static let busyLow = Color("BusyLow", bundle: .main)
    static let busyMedium = Color("BusyMedium", bundle: .main)
    static let busyHigh = Color("BusyHigh", bundle: .main)

    // MARK: - Overlays

    static let scrim = Color("Scrim", bundle: .main)
    static let shimmerBase = Color("ShimmerBase", bundle: .main)
    static let shimmerHighlight = Color("ShimmerHighlight", bundle: .main)
}

// MARK: - Fallback hex helpers (used if asset catalog colors are missing at compile-preview time)

extension Color {
    /// Creates a Color from a hex string like `#881C1C` or `881C1C`.
    init(hex: String, opacity: Double = 1) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)

        let r, g, b: UInt64
        switch cleaned.count {
        case 6:
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        case 8:
            (r, g, b) = ((int >> 24) & 0xFF, (int >> 16) & 0xFF, (int >> 8) & 0xFF)
        default:
            (r, g, b) = (0, 0, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: opacity
        )
    }
}
