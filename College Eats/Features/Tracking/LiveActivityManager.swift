import Foundation
import ActivityKit

/// Live Activity + Dynamic Island — **one** activity per order that updates in place.
@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    private var activity: Activity<OrderActivityAttributes>?
    private var trackedOrderId: String?

    /// Start or refresh the single Live Activity for this order.
    func start(for orderId: String, status: String, eta: String, locationName: String = "") {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let safeETA = Self.sanitizedETA(eta)
        let state = OrderActivityAttributes.ContentState(
            status: status,
            eta: safeETA,
            locationName: locationName
        )

        // Already tracking this order → update only (never spawn another).
        if let existing = currentActivity(for: orderId) {
            activity = existing
            trackedOrderId = orderId
            Task {
                await existing.update(.init(state: state, staleDate: Date().addingTimeInterval(60 * 45)))
            }
            return
        }

        // Different order (or first time) — end every DormRun activity, then create one.
        Task {
            await endAllActivities()
            do {
                let created = try Activity.request(
                    attributes: OrderActivityAttributes(orderId: orderId),
                    content: .init(state: state, staleDate: Date().addingTimeInterval(60 * 45)),
                    pushType: nil
                )
                await MainActor.run {
                    self.activity = created
                    self.trackedOrderId = orderId
                }
            } catch {
                #if DEBUG
                print("Live Activity start failed: \(error)")
                #endif
            }
        }
    }

    func update(status: String, eta: String, locationName: String? = nil) {
        let safeETA = Self.sanitizedETA(eta)
        guard let activity = activity ?? Activity<OrderActivityAttributes>.activities.first else { return }
        let prior = activity.content.state
        // Don't let push/notification bodies overwrite ETA with a route string.
        let nextETA = Self.looksLikeRoute(safeETA) ? prior.eta : safeETA
        let state = OrderActivityAttributes.ContentState(
            status: status,
            eta: nextETA,
            locationName: locationName ?? prior.locationName
        )
        Task {
            await activity.update(.init(state: state, staleDate: Date().addingTimeInterval(60 * 30)))
        }
    }

    func end() {
        Task { await endAllActivities() }
        activity = nil
        trackedOrderId = nil
    }

    private func currentActivity(for orderId: String) -> Activity<OrderActivityAttributes>? {
        if let activity, activity.attributes.orderId == orderId {
            return activity
        }
        return Activity<OrderActivityAttributes>.activities.first { $0.attributes.orderId == orderId }
    }

    private func endAllActivities() async {
        for existing in Activity<OrderActivityAttributes>.activities {
            await existing.end(nil, dismissalPolicy: .immediate)
        }
        activity = nil
        trackedOrderId = nil
    }

    /// Keep live Maps/GPS ETAs intact; only block route strings wrongly passed as ETA.
    private static func sanitizedETA(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if looksLikeRoute(trimmed) { return "~10 min" }
        return trimmed.isEmpty ? "~10 min" : trimmed
    }

    private static func looksLikeRoute(_ value: String) -> Bool {
        value.contains("→") || value.contains("->")
    }
}
