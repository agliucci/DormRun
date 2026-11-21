import SwiftUI

/// Design system entry documentation.
///
/// Use tokens everywhere — never hardcode colors, fonts, or spacing in feature views:
/// - Colors: `AppColors.*`
/// - Type: `AppTypography.*` / `.appText(_:color:)`
/// - Spacing: `AppSpacing.*`, `AppRadius.*`, `AppShadow.*`
/// - Motion: `AppMotion.*`, `AppHaptics.*`
///
/// Components live in `DesignSystem/Components/`.
enum DesignSystem {
    static let brandName = "DormRun"
    static let spring = AppMotion.spring
}
