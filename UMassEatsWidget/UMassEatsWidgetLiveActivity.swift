import ActivityKit
import WidgetKit
import SwiftUI

/// DoorDash-style lock screen + Dynamic Island for active DormRun orders.
struct UMassEatsWidgetLiveActivity: Widget {
    private let brand = Color(red: 0.86, green: 0.38, blue: 0.12)

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: OrderActivityAttributes.self) { context in
            lockScreen(context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Image(systemName: "bicycle")
                            .foregroundStyle(brand)
                        Text("DormRun")
                            .font(.caption.weight(.bold))
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.eta)
                        .font(.caption.monospacedDigit().weight(.bold))
                        .foregroundStyle(brand)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.status)
                        .font(.headline)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if !context.state.locationName.isEmpty {
                        Text(context.state.locationName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } compactLeading: {
                Image(systemName: "bicycle")
                    .foregroundStyle(brand)
            } compactTrailing: {
                Text(shortETA(context.state.eta))
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(brand)
            } minimal: {
                Image(systemName: "bicycle")
                    .foregroundStyle(brand)
            }
            .keylineTint(brand)
        }
    }

    @ViewBuilder
    private func lockScreen(_ context: ActivityViewContext<OrderActivityAttributes>) -> some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(brand.opacity(0.18))
                    .frame(width: 42, height: 42)
                Image(systemName: "bicycle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(brand)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("DormRun")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(context.state.status)
                    .font(.headline)
                    .foregroundStyle(.primary)
                if !context.state.locationName.isEmpty {
                    Text(context.state.locationName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text("ETA")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(context.state.eta)
                    .font(.subheadline.monospacedDigit().weight(.bold))
                    .foregroundStyle(brand)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .activityBackgroundTint(Color(red: 0.12, green: 0.09, blue: 0.08))
        .activitySystemActionForegroundColor(.white)
    }

    private func shortETA(_ eta: String) -> String {
        if let range = eta.range(of: #"\d+\s*min"#, options: .regularExpression) {
            return String(eta[range])
        }
        return String(eta.prefix(6))
    }
}
