import Foundation
import CoreLocation

// MARK: - Campus

struct Campus: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let slug: String
    let name: String
    let eduEmailDomains: [String]
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    let latitude: Double
    let longitude: Double
}

struct Building: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let campusId: String
    let name: String
    let neighborhood: String
    let latitude: Double
    let longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

enum DiningLocationType: String, Codable, Sendable {
    case commons
    case retail
}

/// How food is obtained at pickup.
/// - retailPurchase: customer pays menu prices; runner buys with a card; app reimburses food + pays fee/tip.
/// - mealSwipe: customer pays fee + tip (+ small bump); runner uses their own dining swipe; no food reimbursement.
enum OrderFulfillmentMode: String, Codable, Sendable {
    case retailPurchase
    case mealSwipe

    static func forLocationType(_ type: DiningLocationType) -> OrderFulfillmentMode {
        type == .retail ? .retailPurchase : .mealSwipe
    }

    var title: String {
        switch self {
        case .retailPurchase: "Retail · pay for food"
        case .mealSwipe: "Commons · runner swipe"
        }
    }

    var customerPaysFood: Bool { self == .retailPurchase }
}

struct DiningLocation: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let campusId: String
    let name: String
    let type: DiningLocationType
    let neighborhood: String
    let imageURL: URL?
    /// Local asset catalog name (preferred over remote URL when present).
    let imageAssetName: String?
    let latitude: Double
    let longitude: Double
    let hours: [String: [[String]]]
    let busyLevel: BusyLevel

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(
        id: String,
        campusId: String,
        name: String,
        type: DiningLocationType,
        neighborhood: String,
        imageURL: URL? = nil,
        imageAssetName: String? = nil,
        latitude: Double,
        longitude: Double,
        hours: [String: [[String]]],
        busyLevel: BusyLevel
    ) {
        self.id = id
        self.campusId = campusId
        self.name = name
        self.type = type
        self.neighborhood = neighborhood
        self.imageURL = imageURL
        self.imageAssetName = imageAssetName
        self.latitude = latitude
        self.longitude = longitude
        self.hours = hours
        self.busyLevel = busyLevel
    }

    func openStatus(at date: Date = .now, calendar: Calendar = .current) -> LocationOpenStatus {
        let weekdayKeys = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
        let weekday = calendar.component(.weekday, from: date) - 1
        let key = weekdayKeys[weekday]
        guard let windows = hours[key], !windows.isEmpty else { return .closed }

        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let nowMinutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)

        for window in windows {
            guard window.count == 2,
                  let open = Self.minutes(from: window[0]),
                  let close = Self.minutes(from: window[1]) else { continue }
            if nowMinutes >= open && nowMinutes < close {
                if close - nowMinutes <= 60 { return .closingSoon }
                return .open
            }
        }
        return .closed
    }

    /// Campus bike ETA to `dropoff` (or a typical mid-campus hop if nil).
    func estimatedDeliveryMinutes(to dropoff: Building? = nil, vehicle: VehicleType = .bike) -> Int {
        DeliveryETA.estimateMinutes(
            from: coordinate,
            to: dropoff?.coordinate,
            busy: busyLevel,
            vehicle: vehicle
        )
    }

    private static func minutes(from hhmm: String) -> Int? {
        let bits = hhmm.split(separator: ":")
        guard bits.count == 2, let h = Int(bits[0]), let m = Int(bits[1]) else { return nil }
        return h * 60 + m
    }

    func asCardModel(at date: Date = .now, dropoff: Building? = nil) -> DiningLocationCardModel {
        DiningLocationCardModel(
            id: id,
            name: name,
            subtitle: "\(type == .commons ? "Dining Commons" : "Retail") · \(neighborhood)",
            imageURL: imageURL,
            imageAssetName: imageAssetName,
            openStatus: openStatus(at: date),
            busyLevel: busyLevel,
            estimatedDeliveryMinutes: estimatedDeliveryMinutes(to: dropoff)
        )
    }
}

struct MenuCategory: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let locationId: String
    let name: String
    let sortOrder: Int
    var items: [MenuItem]
}

struct MenuItem: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let categoryId: String
    let name: String
    let description: String
    let priceCents: Int
    let tags: [DietaryTag]
    let imageURL: URL?
    let isAvailable: Bool
    var customizations: [MenuCustomization]

    var formattedPrice: String {
        (Double(priceCents) / 100.0).formatted(.currency(code: "USD"))
    }

    func asDisplayModel() -> MenuItemDisplayModel {
        MenuItemDisplayModel(
            id: id,
            name: name,
            description: description,
            priceCents: priceCents,
            imageURL: imageURL,
            tags: tags,
            isAvailable: isAvailable
        )
    }
}

struct MenuCustomization: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let name: String
    let options: [CustomizationOption]
    let isRequired: Bool
    let allowsMultiple: Bool
}

struct CustomizationOption: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let name: String
    let priceCentsDelta: Int
}

// MARK: - Profile & Auth

struct UserProfile: Identifiable, Hashable, Codable, Sendable {
    let id: String
    var campusId: String
    var fullName: String
    var email: String
    var phone: String
    var homeBuildingId: String?
    var isRunner: Bool
    var vehicleType: VehicleType?
    var rating: Double
    var avatarURL: URL?
    var mode: AppUserMode
}

enum AppUserMode: String, Codable, Sendable {
    case customer
    case runner
}

// MARK: - Cart & Orders

struct CartItem: Identifiable, Hashable, Sendable {
    let id: String
    let menuItem: MenuItem
    var quantity: Int
    var selectedOptionIds: [String]
    var specialInstructions: String

    var unitPriceCents: Int {
        let extras = menuItem.customizations
            .flatMap(\.options)
            .filter { selectedOptionIds.contains($0.id) }
            .reduce(0) { $0 + $1.priceCentsDelta }
        return menuItem.priceCents + extras
    }

    var lineTotalCents: Int { unitPriceCents * quantity }
}

struct Cart: Sendable {
    var locationId: String?
    var items: [CartItem] = []

    var itemCount: Int { items.reduce(0) { $0 + $1.quantity } }
    var subtotalCents: Int { items.reduce(0) { $0 + $1.lineTotalCents } }

    var summary: CartBarSummary {
        CartBarSummary(itemCount: itemCount, totalCents: subtotalCents)
    }
}

struct Order: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let customerId: String
    var runnerId: String?
    let locationId: String
    let locationName: String
    let dropoffBuildingId: String
    let dropoffBuildingName: String
    var dropoffNote: String
    var status: OrderStatus
    /// Menu / station estimate (what the runner should grab). Charged to customer only for retail.
    let subtotalCents: Int
    let deliveryFeeCents: Int
    let tipCents: Int
    /// Small customer bump on commons swipe orders (extra for the runner).
    let runnerMealBumpCents: Int
    let fulfillmentMode: OrderFulfillmentMode
    let handoffCode: String
    let items: [OrderLineItem]
    var runner: RunnerSnapshot?
    var placedAt: Date
    var acceptedAt: Date?
    var atPickupAt: Date?
    var pickedUpAt: Date?
    var enRouteAt: Date?
    var deliveredAt: Date?
    var cancelledAt: Date?

    /// What Stripe charges the customer.
    var chargedFoodCents: Int { fulfillmentMode.customerPaysFood ? subtotalCents : 0 }

    var totalCents: Int {
        chargedFoodCents + runnerMealBumpCents + deliveryFeeCents + tipCents
    }

    /// What the runner should receive: fee + tip + bump, plus food reimbursement on retail.
    nonisolated var runnerPayoutCents: Int {
        deliveryFeeCents + tipCents + runnerMealBumpCents
            + (fulfillmentMode == .retailPurchase ? subtotalCents : 0)
    }

    var formattedTotal: String {
        (Double(totalCents) / 100.0).formatted(.currency(code: "USD"))
    }

    var pickupInstructions: String {
        switch fulfillmentMode {
        case .retailPurchase:
            let food = (Double(subtotalCents) / 100).formatted(.currency(code: "USD"))
            return "Buy with your card (~\(food)). You’re reimbursed for food plus fee & tip."
        case .mealSwipe:
            return "Use one of your meal swipes, grab the listed items, then deliver. You’re paid fee + tip (no food reimbursement)."
        }
    }

    func timelineSteps() -> [TimelineStep] {
        let sequence = OrderStatus.deliverySequence
        let currentIndex = sequence.firstIndex(of: status) ?? 0
        return sequence.map { step in
            let idx = sequence.firstIndex(of: step) ?? 0
            let time: String? = {
                switch step {
                case .placed: return placedAt.formatted(date: .omitted, time: .shortened)
                case .accepted: return acceptedAt?.formatted(date: .omitted, time: .shortened)
                case .atPickup: return atPickupAt?.formatted(date: .omitted, time: .shortened)
                case .pickedUp: return pickedUpAt?.formatted(date: .omitted, time: .shortened)
                case .enRoute: return enRouteAt?.formatted(date: .omitted, time: .shortened)
                case .delivered: return deliveredAt?.formatted(date: .omitted, time: .shortened)
                case .cancelled: return cancelledAt?.formatted(date: .omitted, time: .shortened)
                }
            }()
            return TimelineStep(
                id: step.rawValue,
                status: step,
                title: step.label,
                subtitle: time,
                isCompleted: status != .cancelled && idx < currentIndex,
                isCurrent: status != .cancelled && idx == currentIndex
            )
        }
    }
}

struct OrderLineItem: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let name: String
    let quantity: Int
    let unitPriceCents: Int
    let specialInstructions: String?
}

struct RunnerSnapshot: Hashable, Codable, Sendable {
    let id: String
    let name: String
    let rating: Double
    let vehicleType: VehicleType
    let avatarURL: URL?
}

struct RunnerLocation: Hashable, Codable, Sendable {
    let runnerId: String
    let orderId: String?
    let latitude: Double
    let longitude: Double
    let updatedAt: Date

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct OrderMessage: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let orderId: String
    let senderId: String
    let body: String
    let createdAt: Date
}

struct RunnerRating: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let orderId: String
    let fromUserId: String
    let toUserId: String
    let stars: Int
    let comment: String?
    let createdAt: Date
}

struct AvailableDeliveryJob: Identifiable, Hashable, Sendable {
    let order: Order
    let pickupName: String
    let dropoffName: String
    let distanceMeters: Double
    let itemCount: Int
    let payoutCents: Int

    var id: String { order.id }

    var formattedPayout: String {
        (Double(payoutCents) / 100.0).formatted(.currency(code: "USD"))
    }

    var formattedDistance: String {
        let miles = distanceMeters / 1609.34
        return String(format: "%.1f mi", miles)
    }
}

struct EarningsSummary: Sendable {
    var todayCents: Int
    var weekCents: Int
    /// Balance ready to send to the runner's bank (tips + delivery fees).
    var availableCents: Int
    var dailyBars: [DailyEarning]
    var payoutStatus: String
    var bankLinked: Bool
    var history: [Order]
}

struct DailyEarning: Identifiable, Sendable {
    let id: String
    let dayLabel: String
    let cents: Int
}

struct AppError: Identifiable, Error, LocalizedError, Sendable {
    let id = UUID().uuidString
    let message: String

    var errorDescription: String? { message }

    static let offline = AppError(message: "You're offline. Check campus Wi‑Fi and try again.")
    static let generic = AppError(message: "Something went wrong. Try again.")
}

enum LoadState<T: Sendable>: Sendable {
    case idle
    case loading
    case loaded(T)
    case empty(message: String)
    case failed(AppError)
}
