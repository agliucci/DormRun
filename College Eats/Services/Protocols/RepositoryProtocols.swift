import Foundation
import CoreLocation

protocol CampusRepository: Sendable {
    func fetchCampuses() async throws -> [Campus]
    func campus(forEmailDomain domain: String) async throws -> Campus?
    func fetchBuildings(campusId: String) async throws -> [Building]
    func fetchDiningLocations(campusId: String) async throws -> [DiningLocation]
    func fetchMenu(locationId: String) async throws -> [MenuCategory]
}

protocol AuthRepository: Sendable {
    func sendOTP(email: String) async throws
    func verifyOTP(email: String, code: String) async throws -> UserProfile
    func currentProfile() async throws -> UserProfile?
    func updateProfile(_ profile: UserProfile) async throws -> UserProfile
    func signOut() async throws
}

protocol OrderRepository: Sendable {
    func placeOrder(
        customerId: String,
        location: DiningLocation,
        dropoff: Building,
        dropoffNote: String,
        cart: Cart,
        tipCents: Int,
        deliveryFeeCents: Int,
        runnerMealBumpCents: Int,
        paymentIntentId: String?
    ) async throws -> Order

    func fetchOrder(id: String) async throws -> Order
    func fetchOrders(forCustomerId customerId: String) async throws -> [Order]
    func cancelOrder(id: String, customerId: String) async throws -> Order
    func rateRunner(orderId: String, stars: Int, comment: String?) async throws
    func fetchRatings(forRunnerId runnerId: String) async throws -> [RunnerRating]

    func fetchAvailableJobs(campusId: String) async throws -> [AvailableDeliveryJob]
    func acceptJob(orderId: String, runner: RunnerSnapshot) async throws -> Order
    func transition(orderId: String, to status: OrderStatus, runnerId: String, handoffCode: String?) async throws -> Order
    func fetchActiveRunnerOrder(runnerId: String) async throws -> Order?
    func fetchEarnings(runnerId: String) async throws -> EarningsSummary
}

protocol LocationPublishing: Sendable {
    func publishRunnerLocation(_ location: RunnerLocation) async throws
    func subscribeRunnerLocation(orderId: String) -> AsyncStream<RunnerLocation>
    func subscribeOrderUpdates(orderId: String) -> AsyncStream<Order>
}

protocol ChatRepository: Sendable {
    func fetchMessages(orderId: String) async throws -> [OrderMessage]
    func sendMessage(orderId: String, senderId: String, body: String) async throws -> OrderMessage
}

protocol PaymentService: Sendable {
    func presentPaymentSheet(amountCents: Int, customerEmail: String) async throws -> PaymentResult
    func createConnectOnboardingLink(runnerId: String) async throws -> URL
    func payoutStatus(runnerId: String) async throws -> String
    func cashOutAvailableBalance(runnerId: String) async throws -> CashOutResult
}

enum PaymentResult: Sendable {
    case completed(paymentIntentId: String?)
    case canceled
    case failed(String)
}

struct CashOutResult: Sendable {
    let transferredCents: Int
    let transferId: String?
    let message: String
}
