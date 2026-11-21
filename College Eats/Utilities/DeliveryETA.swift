import Foundation
import CoreLocation

/// Campus-scale delivery ETA for bike/scooter/walk runners.
/// UMass Amherst is compact — cross-campus bike rides are ~4–8 minutes, not 25+.
enum DeliveryETA {
    /// Typical campus path speed (mph), including stops / hills / paths.
    private static let bikeMph = 9.5
    private static let scooterMph = 11.0
    private static let walkMph = 3.2
    private static let defaultMph = bikeMph

    /// Meters between two campus points (haversine).
    static func distanceMeters(
        from a: CLLocationCoordinate2D,
        to b: CLLocationCoordinate2D
    ) -> CLLocationDistance {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    /// Pure travel minutes for a vehicle (no kitchen / handoff buffer).
    static func travelMinutes(
        meters: CLLocationDistance,
        vehicle: VehicleType? = .bike
    ) -> Int {
        let mph: Double
        switch vehicle {
        case .bike, .none: mph = bikeMph
        case .scooter, .eScooter: mph = scooterMph
        case .walk: mph = walkMph
        }
        let hours = (meters / 1609.344) / mph
        // Floor at 2 min so ultra-short hops still feel real; ceil for display.
        return max(2, Int(ceil(hours * 60.0)))
    }

    /// Dining hall → dorm estimate shown on cards / menu header.
    /// Includes a short pickup buffer (runner meets kitchen / bag handoff).
    static func estimateMinutes(
        from pickup: CLLocationCoordinate2D,
        to dropoff: CLLocationCoordinate2D?,
        busy: BusyLevel,
        vehicle: VehicleType = .bike
    ) -> Int {
        let destination = dropoff ?? Self.campusCentroid
        let meters = distanceMeters(from: pickup, to: destination)
        let ride = travelMinutes(meters: meters, vehicle: vehicle)
        let pickupBuffer: Int
        switch busy {
        case .low: pickupBuffer = 3
        case .medium: pickupBuffer = 4
        case .high: pickupBuffer = 6
        }
        // +1 for dorm door / building entry.
        return ride + pickupBuffer + 1
    }

    /// Live remaining minutes while runner is already moving.
    static func remainingMinutes(
        from runner: CLLocationCoordinate2D,
        to dropoff: CLLocationCoordinate2D,
        vehicle: VehicleType? = .bike
    ) -> Int {
        travelMinutes(meters: distanceMeters(from: runner, to: dropoff), vehicle: vehicle) + 1
    }

    /// Fallback when dropoff isn't known yet — median campus hop (~0.6 mi).
    private static let campusCentroid = CLLocationCoordinate2D(latitude: 42.3905, longitude: -72.5265)

    static func formatMinutes(_ minutes: Int) -> String {
        "~\(minutes) min"
    }
}
