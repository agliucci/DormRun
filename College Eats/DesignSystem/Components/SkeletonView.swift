import SwiftUI

/// Shimmering skeleton placeholder — prefer this over bare ProgressView spinners.
struct SkeletonView: View {
    var cornerRadius: CGFloat = AppRadius.md
    var height: CGFloat? = nil

    @State private var phase: CGFloat = -1

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: false)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let animated = CGFloat(sin(t * 2.2) * 0.5 + 0.5)

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(AppColors.shimmerBase)
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    AppColors.shimmerBase.opacity(0),
                                    AppColors.shimmerHighlight.opacity(0.7),
                                    AppColors.shimmerBase.opacity(0)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .offset(x: (animated * 2 - 1) * 120)
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .accessibilityLabel("Loading")
        .accessibilityAddTraits(.updatesFrequently)
    }
}

/// Convenience skeleton layouts for common patterns.
struct SkeletonLocationCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            SkeletonView(cornerRadius: AppRadius.lg, height: 140)
            SkeletonView(cornerRadius: AppRadius.sm, height: 18)
                .frame(width: 140)
            SkeletonView(cornerRadius: AppRadius.sm, height: 14)
                .frame(width: 100)
        }
        .padding(AppSpacing.sm)
        .background(AppCardBackground(radius: AppRadius.xl))
    }
}

struct SkeletonMenuItemRow: View {
    var body: some View {
        HStack(spacing: AppSpacing.md) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                SkeletonView(cornerRadius: AppRadius.sm, height: 16)
                    .frame(width: 160)
                SkeletonView(cornerRadius: AppRadius.sm, height: 12)
                SkeletonView(cornerRadius: AppRadius.sm, height: 12)
                    .frame(width: 80)
            }
            Spacer(minLength: 0)
            SkeletonView(cornerRadius: AppRadius.md, height: 72)
                .frame(width: 72)
        }
        .padding(AppSpacing.md)
    }
}

#Preview("Skeleton") {
    VStack(spacing: AppSpacing.lg) {
        SkeletonLocationCard()
            .frame(width: 260)
        SkeletonMenuItemRow()
    }
    .padding()
    .background(AppColors.background)
}
