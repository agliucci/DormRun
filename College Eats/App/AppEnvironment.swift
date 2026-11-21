import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
final class AppEnvironment {
    let campusRepository: CampusRepository
    let authRepository: AuthRepository
    let orderRepository: OrderRepository
    let chatRepository: ChatRepository
    let realtime: LocationPublishing
    let payments: PaymentService
    let runnerLocation: RunnerLocationService

    var session = SessionStore()
    var cart = CartStore()

    var showDesignGallery = false
    /// Detail screens (chat, etc.) hide the floating tab bar so the composer isn't covered.
    private(set) var floatingTabBarHideCount = 0
    var hidesFloatingTabBar: Bool { floatingTabBarHideCount > 0 }
    var usesLiveAuth: Bool { SupabaseClientProvider.usesLiveAuth }

    func setFloatingTabBarHidden(_ hidden: Bool) {
        if hidden {
            floatingTabBarHideCount += 1
        } else {
            floatingTabBarHideCount = max(0, floatingTabBarHideCount - 1)
        }
    }

    init(
        campusRepository: CampusRepository? = nil,
        authRepository: AuthRepository? = nil,
        orderRepository: MockOrderRepository = MockOrderRepository(),
        chatRepository: ChatRepository? = nil,
        payments: PaymentService = StubPaymentService()
    ) {
        self.campusRepository = campusRepository ?? SupabaseClientProvider.makeCampusRepository()
        self.authRepository = authRepository ?? SupabaseClientProvider.makeAuthRepository()
        self.orderRepository = orderRepository
        self.chatRepository = chatRepository ?? SupabaseClientProvider.makeChatRepository()
        self.realtime = MockRealtimeService(orderRepository: orderRepository)
        self.payments = payments
        self.runnerLocation = RunnerLocationService()
        self.runnerLocation.attach(environment: self)
    }

    static let preview = AppEnvironment()
}

@Observable
@MainActor
final class SessionStore {
    var profile: UserProfile?
    var selectedCampus: Campus = MockCatalogData.campus
    var buildings: [Building] = MockCatalogData.buildings
    var isOnboardingComplete = false
    var isOnlineAsRunner = false
    var isBootstrapping = true
    var authError: AppError?

    var isSignedIn: Bool { profile != nil }

    var greetingName: String {
        guard let name = profile?.fullName.split(separator: " ").first, !name.isEmpty else { return "there" }
        return String(name)
    }

    var timeOfDayGreeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Still up?"
        }
    }
}

@Observable
@MainActor
final class CartStore {
    var cart = Cart()
    var tipCents: Int = 200
    var dropoffBuildingId: String?
    var dropoffNote: String = ""

    let deliveryFeeCents = 299
    let tipPresets = [0, 100, 200, 300, 500]

    var totalCents: Int {
        cart.subtotalCents + deliveryFeeCents + tipCents
    }

    func add(_ item: MenuItem, quantity: Int, options: [String], instructions: String, locationId: String) {
        if let existingLocation = cart.locationId, existingLocation != locationId {
            cart = Cart()
        }
        cart.locationId = locationId
        if let index = cart.items.firstIndex(where: {
            $0.menuItem.id == item.id && $0.selectedOptionIds == options && $0.specialInstructions == instructions
        }) {
            cart.items[index].quantity += quantity
        } else {
            cart.items.append(
                CartItem(
                    id: UUID().uuidString,
                    menuItem: item,
                    quantity: quantity,
                    selectedOptionIds: options,
                    specialInstructions: instructions
                )
            )
        }
        AppHaptics.success()
    }

    func updateQuantity(itemId: String, quantity: Int) {
        guard let index = cart.items.firstIndex(where: { $0.id == itemId }) else { return }
        if quantity <= 0 {
            cart.items.remove(at: index)
        } else {
            cart.items[index].quantity = quantity
        }
        if cart.items.isEmpty {
            clear()
        }
    }

    func clear() {
        cart = Cart()
        tipCents = 200
        dropoffNote = ""
    }
}
