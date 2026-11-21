import Foundation

enum MockCatalogData {
    /// Must match `supabase/seed.sql` UUIDs so live profile saves succeed.
    static let campusId = "a0000000-0000-4000-8000-000000000001"
    static let customerId = "user-customer"
    static let runnerId = "user-runner"

    static let campus = Campus(
        id: campusId,
        slug: "umass-amherst",
        name: "UMass Amherst",
        eduEmailDomains: ["umass.edu"],
        latitude: 42.3912,
        longitude: -72.5267
    )

    static let standardHours: [String: [[String]]] = [
        "mon": [["07:00", "21:00"]],
        "tue": [["07:00", "21:00"]],
        "wed": [["07:00", "21:00"]],
        "thu": [["07:00", "21:00"]],
        "fri": [["07:00", "21:00"]],
        "sat": [["09:00", "20:00"]],
        "sun": [["09:00", "20:00"]],
    ]

    static let lateHours: [String: [[String]]] = [
        "mon": [["11:00", "23:00"]],
        "tue": [["11:00", "23:00"]],
        "wed": [["11:00", "23:00"]],
        "thu": [["11:00", "23:00"]],
        "fri": [["11:00", "24:00"]],
        "sat": [["11:00", "24:00"]],
        "sun": [["12:00", "22:00"]],
    ]

    /// Full residence directory from umass.edu (regenerate via `scripts/scrape_umass.py`).
    static let buildings: [Building] = GeneratedUMassCatalog.buildings

    /// IDs match `supabase/seed.sql` so live scrapes land on the same rows.
    static let locations: [DiningLocation] = [
        .init(id: "d0000000-0000-4000-8000-000000000001", campusId: campusId, name: "Worcester", type: .commons, neighborhood: "Southwest",
              imageAssetName: "DiningWorcester",
              latitude: 42.3855, longitude: -72.5318, hours: standardHours, busyLevel: .medium),
        .init(id: "d0000000-0000-4000-8000-000000000002", campusId: campusId, name: "Franklin", type: .commons, neighborhood: "Central",
              imageAssetName: "DiningFranklin",
              latitude: 42.3892, longitude: -72.5248, hours: standardHours, busyLevel: .high),
        .init(id: "d0000000-0000-4000-8000-000000000003", campusId: campusId, name: "Berkshire", type: .commons, neighborhood: "Southwest",
              imageAssetName: "DiningBerkshire",
              latitude: 42.3848, longitude: -72.5305, hours: standardHours, busyLevel: .low),
        .init(id: "d0000000-0000-4000-8000-000000000004", campusId: campusId, name: "Hampshire", type: .commons, neighborhood: "Southwest",
              imageAssetName: "DiningHampshire",
              latitude: 42.3835, longitude: -72.5295, hours: standardHours, busyLevel: .medium),
        .init(id: "d0000000-0000-4000-8000-000000000005", campusId: campusId, name: "Blue Wall", type: .retail, neighborhood: "Campus Center",
              imageAssetName: "DiningBlueWall",
              latitude: 42.3918, longitude: -72.5260, hours: lateHours, busyLevel: .high),
        .init(id: "d0000000-0000-4000-8000-000000000006", campusId: campusId, name: "Terrace", type: .retail, neighborhood: "Fieldstone",
              imageAssetName: "DiningTerrace",
              latitude: 42.3889, longitude: -72.5294, hours: lateHours, busyLevel: .medium),
    ]

    static func menus(for locationId: String) -> [MenuCategory] {
        if let scraped = GeneratedUMassCatalog.menus(for: locationId) {
            return scraped
        }
        return []
    }

    static let demoCustomer = UserProfile(
        id: customerId,
        campusId: campusId,
        fullName: "Alex Rivera",
        email: "arivera@umass.edu",
        phone: "4135550142",
        homeBuildingId: "b0000000-0000-4000-8000-000000000002",
        isRunner: true,
        vehicleType: .bike,
        rating: 4.9,
        avatarURL: nil,
        mode: .customer
    )

    static let demoRunner = RunnerSnapshot(
        id: runnerId,
        name: "Maya Chen",
        rating: 4.97,
        vehicleType: .scooter,
        avatarURL: URL(string: "https://i.pravatar.cc/150?u=maya")
    )

}
