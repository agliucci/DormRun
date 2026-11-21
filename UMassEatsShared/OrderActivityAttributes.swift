import Foundation
import ActivityKit

public struct OrderActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public var status: String
        public var eta: String
        public var locationName: String

        public init(status: String, eta: String, locationName: String = "") {
            self.status = status
            self.eta = eta
            self.locationName = locationName
        }
    }

    public var orderId: String

    public init(orderId: String) {
        self.orderId = orderId
    }
}
