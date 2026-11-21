import Foundation

enum AppRoute: Hashable {
    case location(DiningLocation)
    case cart
    case checkout
    case tracking(orderId: String)
    case chat(orderId: String)
    case orders
    case designGallery
}
