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
        orderRepository: (any OrderRepository)? = nil,
        chatRepository: ChatRepository? = nil,
        payments: PaymentService = StubPaymentService()
    ) {
        self.campusRepository = campusRepository ?? SupabaseClientProvider.makeCampusRepository()
        self.authRepository = authRepository ?? SupabaseClientProvider.makeAuthRepository()
        let orders = orderRepository ?? SupabaseClientProvider.makeOrderRepository()
        self.orderRepository = orders
        self.chatRepository = chatRepository ?? SupabaseClientProvider.makeChatRepository()
        self.realtime = MockRealtimeService(orderRepository: orders)
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
    var locationType: DiningLocationType?

    let deliveryFeeCents = 299
    /// Extra on commons swipe orders so the runner gets a little more than fee alone.
    let runnerMealBumpCents = 250
    let tipPresets = [0, 100, 200, 300, 500]

    var fulfillmentMode: OrderFulfillmentMode {
        OrderFulfillmentMode.forLocationType(locationType ?? .retail)
    }

    /// Menu total (shown as estimate on commons; charged only on retail).
    var menuSubtotalCents: Int { cart.subtotalCents }

    var chargedFoodCents: Int {
        fulfillmentMode.customerPaysFood ? menuSubtotalCents : 0
    }

    var appliedBumpCents: Int {
        fulfillmentMode == .mealSwipe ? runnerMealBumpCents : 0
    }

    var totalCents: Int {
        chargedFoodCents + appliedBumpCents + deliveryFeeCents + tipCents
    }

    var checkoutBarSummary: CartBarSummary {
        CartBarSummary(itemCount: cart.itemCount, totalCents: totalCents)
    }

    var pricingExplanation: String {
        switch fulfillmentMode {
        case .retailPurchase:
            return "You pay food + delivery + tip. The runner buys it with a card and gets food reimbursed plus their fee & tip."
        case .mealSwipe:
            return "Dining commons: you pay delivery + tip (+ small runner bump). The runner uses their own meal swipe — no second $21 guest charge."
        }
    }

    func add(
        _ item: MenuItem,
        quantity: Int,
        options: [String],
        instructions: String,
        locationId: String,
        locationType: DiningLocationType
    ) {
        if let existingLocation = cart.locationId, existingLocation != locationId {
            cart = Cart()
            self.locationType = nil
        }
        cart.locationId = locationId
        self.locationType = locationType
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
        locationType = nil
    }
}
