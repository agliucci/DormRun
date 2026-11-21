import SwiftUI

struct StatusTimeline: View {
    let steps: [TimelineStep]
    var compact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                timelineRow(step: step, isLast: index == steps.count - 1)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func timelineRow(step: TimelineStep, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.sm) {
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(dotFill(for: step))
                        .frame(width: 14, height: 14)
                    if step.isCurrent {
                        Circle()
                            .stroke(AppColors.brand.opacity(0.35), lineWidth: 4)
                            .frame(width: 22, height: 22)
                    }
                    if step.isCompleted {
                        Image(systemName: "checkmark")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(AppColors.textOnBrand)
                    }
                }
                .frame(width: 22, height: 22)

                if !isLast {
                    Rectangle()
                        .fill(step.isCompleted ? AppColors.brand : AppColors.border)
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 22)

            VStack(alignment: .leading, spacing: AppSpacing.xxxs) {
                Text(step.title)
                    .font(step.isCurrent ? AppTypography.headline : AppTypography.body)
                    .foregroundStyle(step.isCompleted || step.isCurrent ? AppColors.textPrimary : AppColors.textTertiary)

                if let subtitle = step.subtitle {
                    Text(subtitle)
                        .appText(.caption, color: AppColors.textSecondary)
                }
            }
            .padding(.bottom, isLast ? 0 : (compact ? AppSpacing.sm : AppSpacing.md))
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("\(step.title)\(step.subtitle.map { ", \($0)" } ?? "")\(step.isCurrent ? ", current" : "")\(step.isCompleted ? ", completed" : "")")
        }
    }

    private func dotFill(for step: TimelineStep) -> Color {
        if step.isCompleted || step.isCurrent {
            AppColors.brand
        } else {
            AppColors.border
        }
    }
}

#Preview {
    StatusTimeline(steps: GalleryMocks.timeline)
        .padding(AppSpacing.screenMargin)
        .background(AppColors.background)
}
