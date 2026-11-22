import SwiftUI

/// 4pt spacing grid, radii, shadows, and layout constants.
enum AppSpacing {
    // MARK: - Scale (4pt grid)

    static let xxxs: CGFloat = 2
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let xxxl: CGFloat = 40
    static let huge: CGFloat = 48
    static let massive: CGFloat = 64

    // MARK: - Layout

    /// Standard horizontal screen margin.
    static let screenMargin: CGFloat = 20

    /// Minimum tap target (HIG).
    static let minTapTarget: CGFloat = 44

    /// Gap between carousel cards.
    static let carouselGap: CGFloat = 14

    /// Floating cart / tab bar bottom inset padding.
    /// Clears the floating tab bar so "View cart" isn't covered.
    static let floatingBarInset: CGFloat = 76
}

enum AppRadius {
    static let sm: CGFloat = 10
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 28
    static let pill: CGFloat = 100
}

enum AppShadow {
    /// Soft card lift — never harsh.
    static func card(colorScheme: ColorScheme) -> (color: Color, radius: CGFloat, x: CGFloat, y: CGFloat) {
        if colorScheme == .dark {
            (Color.black.opacity(0.35), 16, 0, 6)
        } else {
            (Color.black.opacity(0.08), 20, 0, 8)
        }
    }

    static func elevated(colorScheme: ColorScheme) -> (color: Color, radius: CGFloat, x: CGFloat, y: CGFloat) {
        if colorScheme == .dark {
            (Color.black.opacity(0.45), 24, 0, 10)
        } else {
            (Color.black.opacity(0.12), 28, 0, 12)
        }
    }

    static func floating(colorScheme: ColorScheme) -> (color: Color, radius: CGFloat, x: CGFloat, y: CGFloat) {
        if colorScheme == .dark {
            (Color.black.opacity(0.5), 30, 0, 14)
        } else {
            (Color.black.opacity(0.14), 32, 0, 14)
        }
    }
}

// MARK: - View helpers

extension View {
    func appCardShadow(_ colorScheme: ColorScheme) -> some View {
        let s = AppShadow.card(colorScheme: colorScheme)
        return shadow(color: s.color, radius: s.radius, x: s.x, y: s.y)
    }

    func appElevatedShadow(_ colorScheme: ColorScheme) -> some View {
        let s = AppShadow.elevated(colorScheme: colorScheme)
        return shadow(color: s.color, radius: s.radius, x: s.x, y: s.y)
    }

    func appFloatingShadow(_ colorScheme: ColorScheme) -> some View {
        let s = AppShadow.floating(colorScheme: colorScheme)
        return shadow(color: s.color, radius: s.radius, x: s.x, y: s.y)
    }

    /// Continuous corner radius wrapper.
    func appCornerRadius(_ radius: CGFloat) -> some View {
        clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// Soft layered card background used across location cards, menu rows, etc.
struct AppCardBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    var radius: CGFloat = AppRadius.xl
    var elevated: Bool = false

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(elevated ? AppColors.surfaceElevated : AppColors.surface)
            .appCardShadow(colorScheme)
    }
}
