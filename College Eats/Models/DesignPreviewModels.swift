import Foundation

// Lightweight display models used by DesignSystem components and the gallery.
// Full domain models land in Phase 2+.

enum DietaryTag: String, CaseIterable, Identifiable, Codable, Sendable {
    case vegan
    case vegetarian
    case glutenFree
    case halal

    var id: String { rawValue }

    var label: String {
        switch self {
        case .vegan: "Vegan"
        case .vegetarian: "Vegetarian"
        case .glutenFree: "GF"
        case .halal: "Halal"
        }
    }

    var systemImage: String {
        switch self {
        case .vegan: "leaf.fill"
        case .vegetarian: "carrot.fill"
        case .glutenFree: "scalemass.fill"
        case .halal: "moon.stars.fill"
        }
    }
}

enum LocationOpenStatus: String, Codable, Sendable {
    case open
    case closingSoon
    case closed

    var label: String {
        switch self {
        case .open: "Open"
        case .closingSoon: "Closing soon"
        case .closed: "Closed"
        }
    }
}

enum BusyLevel: String, Codable, Sendable {
    case low
    case medium
    case high

    var label: String {
        switch self {
        case .low: "Not busy"
        case .medium: "Busy"
        case .high: "Packed"
        }
    }
}

enum OrderStatus: String, CaseIterable, Identifiable, Codable, Sendable {
    case placed
    case accepted
    case atPickup
    case pickedUp
    case enRoute
    case delivered
    case cancelled

    var id: String { rawValue }

    var label: String {
        switch self {
        case .placed: "Order placed"
        case .accepted: "Runner accepted"
        case .atPickup: "At pickup"
        case .pickedUp: "Picked up"
        case .enRoute: "On the way"
        case .delivered: "Delivered"
        case .cancelled: "Cancelled"
        }
    }

    /// Active delivery sequence (excludes cancelled).
    static let deliverySequence: [OrderStatus] = [
        .placed, .accepted, .atPickup, .pickedUp, .enRoute, .delivered
    ]
}

enum VehicleType: String, CaseIterable, Codable, Sendable {
    case walk
    case bike
    case scooter
    case eScooter

    var label: String {
        switch self {
        case .walk: "Walking"
        case .bike: "Bike"
        case .scooter: "Scooter"
        case .eScooter: "E-scooter"
        }
    }

    var systemImage: String {
        switch self {
        case .walk: "figure.walk"
        case .bike: "bicycle"
        case .scooter: "scooter"
        case .eScooter: "scooter"
        }
    }
}

struct DiningLocationCardModel: Identifiable, Sendable {
    let id: String
    let name: String
    let subtitle: String
    let imageURL: URL?
    var imageAssetName: String? = nil
    let openStatus: LocationOpenStatus
    let busyLevel: BusyLevel
    let estimatedDeliveryMinutes: Int
}

struct MenuItemDisplayModel: Identifiable, Sendable {
    let id: String
    let name: String
    let description: String
    let priceCents: Int
    let imageURL: URL?
    let tags: [DietaryTag]
    let isAvailable: Bool

    var formattedPrice: String {
        let dollars = Double(priceCents) / 100.0
        return dollars.formatted(.currency(code: "USD"))
    }
}

struct TimelineStep: Identifiable, Sendable {
    let id: String
    let status: OrderStatus
    let title: String
    let subtitle: String?
    let isCompleted: Bool
    let isCurrent: Bool
}

struct CartBarSummary: Equatable, Sendable {
    var itemCount: Int
    var totalCents: Int

    var formattedTotal: String {
        (Double(totalCents) / 100.0).formatted(.currency(code: "USD"))
    }
}

enum GalleryMocks {
    static let worcester = DiningLocationCardModel(
        id: "worcester",
        name: "Worcester",
        subtitle: "Dining Commons · Southwest",
        imageURL: nil,
        imageAssetName: "DiningWorcester",
        openStatus: .open,
        busyLevel: .medium,
        estimatedDeliveryMinutes: 9
    )

    static let franklin = DiningLocationCardModel(
        id: "franklin",
        name: "Franklin",
        subtitle: "Dining Commons · Central",
        imageURL: nil,
        imageAssetName: "DiningFranklin",
        openStatus: .closingSoon,
        busyLevel: .high,
        estimatedDeliveryMinutes: 11
    )

    static let closedHall = DiningLocationCardModel(
        id: "berkshire",
        name: "Berkshire",
        subtitle: "Dining Commons · Southwest",
        imageURL: nil,
        imageAssetName: "DiningBerkshire",
        openStatus: .closed,
        busyLevel: .low,
        estimatedDeliveryMinutes: 0
    )

    static let burger = MenuItemDisplayModel(
        id: "burger",
        name: "Berkshire Burger",
        description: "Angus patty, cheddar, special sauce, toasted brioche.",
        priceCents: 995,
        imageURL: URL(string: "https://images.unsplash.com/photo-1568901346375-23c9450c58cd?w=400"),
        tags: [.halal],
        isAvailable: true
    )

    static let bowl = MenuItemDisplayModel(
        id: "bowl",
        name: "Harvest Grain Bowl",
        description: "Farro, roasted squash, kale, tahini drizzle.",
        priceCents: 875,
        imageURL: URL(string: "https://images.unsplash.com/photo-1512621776951-a57141f2eefd?w=400"),
        tags: [.vegan, .glutenFree],
        isAvailable: true
    )

    static let timeline: [TimelineStep] = [
        TimelineStep(id: "1", status: .placed, title: "Order placed", subtitle: "4:02 PM", isCompleted: true, isCurrent: false),
        TimelineStep(id: "2", status: .accepted, title: "Maya accepted", subtitle: "4:04 PM", isCompleted: true, isCurrent: false),
        TimelineStep(id: "3", status: .atPickup, title: "At Worcester", subtitle: "Picking up your order", isCompleted: false, isCurrent: true),
        TimelineStep(id: "4", status: .pickedUp, title: "Picked up", subtitle: nil, isCompleted: false, isCurrent: false),
        TimelineStep(id: "5", status: .enRoute, title: "On the way", subtitle: nil, isCompleted: false, isCurrent: false),
        TimelineStep(id: "6", status: .delivered, title: "Delivered", subtitle: nil, isCompleted: false, isCurrent: false),
    ]
}
