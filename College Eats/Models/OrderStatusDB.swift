import Foundation

extension Date {
    var isToday: Bool {
        Calendar.current.isDateInToday(self)
    }
}

extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension OrderStatus {
    /// Postgres / edge-function wire value (`at_pickup`, not `atPickup`).
    var dbValue: String {
        switch self {
        case .placed: "placed"
        case .accepted: "accepted"
        case .atPickup: "at_pickup"
        case .pickedUp: "picked_up"
        case .enRoute: "en_route"
        case .delivered: "delivered"
        case .cancelled: "cancelled"
        }
    }

    init?(dbValue: String) {
        switch dbValue {
        case "placed": self = .placed
        case "accepted": self = .accepted
        case "at_pickup": self = .atPickup
        case "picked_up": self = .pickedUp
        case "en_route": self = .enRoute
        case "delivered": self = .delivered
        case "cancelled": self = .cancelled
        default: return nil
        }
    }
}

extension OrderFulfillmentMode {
    var dbValue: String {
        switch self {
        case .retailPurchase: "retail_purchase"
        case .mealSwipe: "meal_swipe"
        }
    }

    init?(dbValue: String) {
        switch dbValue {
        case "retail_purchase", "retailPurchase": self = .retailPurchase
        case "meal_swipe", "mealSwipe": self = .mealSwipe
        default: return nil
        }
    }
}
