import SwiftUI

/// Type scale for UMass Eats.
/// Display & titles use SF Pro Rounded; body uses SF Pro; prices/codes use monospaced digits.
enum AppTypography {
    // MARK: - Display (hero / brand moments)

    static let display = Font.system(.largeTitle, design: .rounded, weight: .bold)
    static let displayLarge = Font.system(size: 40, weight: .bold, design: .rounded)

    // MARK: - Titles

    static let title = Font.system(.title, design: .rounded, weight: .bold)
    static let title2 = Font.system(.title2, design: .rounded, weight: .bold)
    static let title3 = Font.system(.title3, design: .rounded, weight: .semibold)

    // MARK: - Headline / Body

    static let headline = Font.system(.headline, design: .default, weight: .semibold)
    static let body = Font.system(.body, design: .default, weight: .regular)
    static let bodyEmphasized = Font.system(.body, design: .default, weight: .semibold)
    static let callout = Font.system(.callout, design: .default, weight: .regular)
    static let subheadline = Font.system(.subheadline, design: .default, weight: .regular)
    static let footnote = Font.system(.footnote, design: .default, weight: .regular)

    // MARK: - Caption

    static let caption = Font.system(.caption, design: .default, weight: .medium)
    static let caption2 = Font.system(.caption2, design: .default, weight: .medium)

    // MARK: - Mono (prices, handoff codes, OTPs)

    static let price = Font.system(.body, design: .monospaced, weight: .semibold)
    static let priceLarge = Font.system(.title3, design: .monospaced, weight: .bold)
    static let code = Font.system(size: 28, weight: .bold, design: .monospaced)
    static let codeSmall = Font.system(.title3, design: .monospaced, weight: .bold)
}

// MARK: - Text style modifiers

struct AppTextStyle: ViewModifier {
    enum Style {
        case display
        case title
        case title2
        case title3
        case headline
        case body
        case bodyEmphasized
        case callout
        case subheadline
        case footnote
        case caption
        case caption2
        case price
        case priceLarge
        case code
    }

    let style: Style
    let color: Color

    func body(content: Content) -> some View {
        content
            .font(font)
            .foregroundStyle(color)
            .tracking(tracking)
            .lineSpacing(lineSpacing)
    }

    private var font: Font {
        switch style {
        case .display: AppTypography.display
        case .title: AppTypography.title
        case .title2: AppTypography.title2
        case .title3: AppTypography.title3
        case .headline: AppTypography.headline
        case .body: AppTypography.body
        case .bodyEmphasized: AppTypography.bodyEmphasized
        case .callout: AppTypography.callout
        case .subheadline: AppTypography.subheadline
        case .footnote: AppTypography.footnote
        case .caption: AppTypography.caption
        case .caption2: AppTypography.caption2
        case .price: AppTypography.price
        case .priceLarge: AppTypography.priceLarge
        case .code: AppTypography.code
        }
    }

    private var tracking: CGFloat {
        switch style {
        case .display, .title, .title2: -0.6
        case .title3, .headline: -0.3
        case .code: 2
        default: 0
        }
    }

    private var lineSpacing: CGFloat {
        switch style {
        case .body, .callout, .subheadline: 2
        default: 0
        }
    }
}

extension View {
    func appText(_ style: AppTextStyle.Style, color: Color = AppColors.textPrimary) -> some View {
        modifier(AppTextStyle(style: style, color: color))
    }
}
