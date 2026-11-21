import Foundation
import ActivityKit

/// Live Activity + Dynamic Island bridge. Widget UI lives in `UMassEatsWidgets`.
@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    private var activity: Activity<OrderActivityAttributes>?

    func start(for orderId: String, status: String, eta: String, locationName: String = "") {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        end()

        let attributes = OrderActivityAttributes(orderId: orderId)
        let state = OrderActivityAttributes.ContentState(
            status: status,
            eta: eta,
            locationName: locationName
        )

        do {
            activity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: Date().addingTimeInterval(60 * 45)),
                pushType: nil
            )
        } catch {
            activity = nil
            #if DEBUG
            print("Live Activity start failed: \(error)")
            #endif
        }
    }

    func update(status: String, eta: String, locationName: String? = nil) {
        guard let activity else { return }
        let prior = activity.content.state
        let state = OrderActivityAttributes.ContentState(
            status: status,
            eta: eta,
            locationName: locationName ?? prior.locationName
        )
        Task {
            await activity.update(.init(state: state, staleDate: Date().addingTimeInterval(60 * 30)))
        }
    }

    func end() {
        guard let activity else { return }
        let finalState = activity.content.state
        Task {
            await activity.end(
                .init(state: finalState, staleDate: nil),
                dismissalPolicy: .after(.now + 15)
            )
        }
        self.activity = nil
    }
}
