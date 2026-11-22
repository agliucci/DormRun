import Foundation
import CoreLocation

/// Live order + runner GPS fan-out. No simulated paths or auto status advances.
final class MockRealtimeService: LocationPublishing, @unchecked Sendable {
    private let orderRepository: any OrderRepository

    init(orderRepository: any OrderRepository) {
        self.orderRepository = orderRepository
    }

    func publishRunnerLocation(_ location: RunnerLocation) async throws {
        await RunnerLocationHub.shared.publish(location)
    }

    func subscribeRunnerLocation(orderId: String) -> AsyncStream<RunnerLocation> {
        AsyncStream { continuation in
            let task = Task {
                // Same-device / in-process GPS from the active runner.
                let hubTask = Task {
                    let live = await RunnerLocationHub.shared.stream(orderId: orderId)
                    for await update in live {
                        if Task.isCancelled { break }
                        if update.orderId == nil || update.orderId == orderId {
                            continuation.yield(update)
                        }
                    }
                }

                // Cross-device: poll Supabase runner_locations for this order.
                while !Task.isCancelled {
                    if let client = SupabaseClientProvider.shared(),
                       let remote = try? await client.fetchRunnerLocation(orderId: orderId) {
                        await RunnerLocationHub.shared.publish(remote)
                        continuation.yield(remote)
                    }
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                }

                hubTask.cancel()
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func subscribeOrderUpdates(orderId: String) -> AsyncStream<Order> {
        AsyncStream { continuation in
            let task = Task {
                var lastStatus: OrderStatus?
                while !Task.isCancelled {
                    do {
                        let order = try await orderRepository.fetchOrder(id: orderId)
                        if order.status != lastStatus {
                            lastStatus = order.status
                            continuation.yield(order)
                            await MainActor.run {
                                PushNotificationService.shared.notifyOrderStatus(
                                    orderId: order.id,
                                    title: order.status.label,
                                    body: "\(order.locationName) → \(order.dropoffBuildingName)"
                                )
                                LiveActivityManager.shared.update(
                                    status: order.status.label,
                                    eta: order.status == .delivered ? "Delivered" : "~10 min",
                                    locationName: "\(order.locationName) → \(order.dropoffBuildingName)"
                                )
                            }
                        }
                        if order.status == .delivered || order.status == .cancelled {
                            break
                        }
                    } catch {
                        break
                    }
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

struct StubPaymentService: PaymentService {
    func presentPaymentSheet(amountCents: Int, customerEmail: String) async throws -> PaymentResult {
        try await Task.sleep(nanoseconds: 600_000_000)
        _ = customerEmail
        guard amountCents > 0 else { return .failed("Invalid amount") }
        return .completed(paymentIntentId: nil)
    }

    func cashOutAvailableBalance(runnerId: String) async throws -> CashOutResult {
        _ = runnerId
        try await Task.sleep(nanoseconds: 400_000_000)
        return CashOutResult(
            transferredCents: 0,
            transferId: nil,
            message: "Stub cash-out — configure Stripe live keys for real transfers."
        )
    }

    func createConnectOnboardingLink(runnerId: String) async throws -> URL {
        _ = runnerId
        guard let url = URL(string: "https://connect.stripe.com/express/oauth/test-stub") else {
            throw AppError(message: "Could not build onboarding link.")
        }
        return url
    }

    func payoutStatus(runnerId: String) async throws -> String {
        _ = runnerId
        return "Stripe Connect Express · test mode · next payout Monday"
    }
}
