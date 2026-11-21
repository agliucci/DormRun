import SwiftUI

/// Floating cart bar that springs in when the cart has items.
struct FloatingCartBar: View {
    let summary: CartBarSummary
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button {
            AppHaptics.light()
            action()
        } label: {
            HStack(spacing: AppSpacing.md) {
                ZStack {
                    Circle()
                        .fill(AppColors.textOnBrand.opacity(0.2))
                        .frame(width: 36, height: 36)
                    Text("\(summary.itemCount)")
                        .font(AppTypography.headline)
                        .foregroundStyle(AppColors.textOnBrand)
                        .contentTransition(.numericText())
                        .monospacedDigit()
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("View cart")
                        .font(AppTypography.headline)
                        .foregroundStyle(AppColors.textOnBrand)
                    Text(summary.itemCount == 1 ? "1 item" : "\(summary.itemCount) items")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textOnBrand.opacity(0.8))
                }

                Spacer(minLength: 0)

                Text(summary.formattedTotal)
                    .font(AppTypography.priceLarge)
                    .foregroundStyle(AppColors.textOnBrand)
                    .contentTransition(.numericText())
                    .monospacedDigit()
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm)
            .frame(minHeight: AppSpacing.minTapTarget + 8)
            .background {
                RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous)
                    .fill(AppColors.brand)
                    .appFloatingShadow(colorScheme)
            }
        }
        .buttonStyle(PressableButtonStyle())
        .padding(.horizontal, AppSpacing.screenMargin)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("View cart, \(summary.itemCount) items, \(summary.formattedTotal)")
        .accessibilityAddTraits(.isButton)
    }
}

/// Convenience wrapper that animates presence based on item count.
/// Prefer attaching via `.safeAreaInset(edge: .bottom)` so content isn't covered.
struct FloatingCartBarHost: View {
    let summary: CartBarSummary?
    let action: () -> Void

    var body: some View {
        Group {
            if let summary, summary.itemCount > 0 {
                FloatingCartBar(summary: summary, action: action)
                    .padding(.bottom, AppSpacing.floatingBarInset)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(AppMotion.springGentle, value: summary?.itemCount ?? 0)
        .animation(AppMotion.spring, value: summary?.totalCents ?? 0)
    }
}

#Preview {
    ZStack {
        AppColors.background.ignoresSafeArea()
        FloatingCartBarHost(summary: CartBarSummary(itemCount: 3, totalCents: 2845)) {}
    }
}
