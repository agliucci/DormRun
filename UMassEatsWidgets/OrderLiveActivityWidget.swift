import ActivityKit
import WidgetKit
import SwiftUI

struct OrderLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: OrderActivityAttributes.self) { context in
            // Lock Screen / banner
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("DormRun")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(context.state.status)
                        .font(.headline)
                    if !context.state.locationName.isEmpty {
                        Text(context.state.locationName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(context.state.eta)
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Color(red: 0.53, green: 0.11, blue: 0.11))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .activityBackgroundTint(Color(red: 0.98, green: 0.97, blue: 0.95))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("DormRun", systemImage: "bicycle")
                        .font(.caption.weight(.semibold))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.eta)
                        .font(.caption.monospacedDigit().weight(.bold))
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.status)
                        .font(.headline)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if !context.state.locationName.isEmpty {
                        Text(context.state.locationName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } compactLeading: {
                Image(systemName: "bicycle")
            } compactTrailing: {
                Text(shortETA(context.state.eta))
                    .font(.caption2.monospacedDigit().weight(.semibold))
            } minimal: {
                Image(systemName: "bicycle")
            }
        }
    }

    private func shortETA(_ eta: String) -> String {
        if let range = eta.range(of: #"\d+\s*min"#, options: .regularExpression) {
            return String(eta[range])
        }
        return String(eta.prefix(8))
    }
}
