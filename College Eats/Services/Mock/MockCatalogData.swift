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
        .init(id: "d0000000-0000-4000-8000-000000000006", campusId: campusId, name: "Cosmic Café", type: .retail, neighborhood: "Library",
              imageAssetName: "DiningCosmic",
              latitude: 42.3898, longitude: -72.5282, hours: lateHours, busyLevel: .low),
    ]

    static func menus(for locationId: String) -> [MenuCategory] {
        if let scraped = GeneratedUMassCatalog.menus(for: locationId) {
            return scraped
        }
        switch locationId {
        case "d0000000-0000-4000-8000-000000000005": return blueWallMenu
        case "d0000000-0000-4000-8000-000000000006": return cosmicMenu
        default: return []
        }
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

    // MARK: - Retail menus (commons come from GeneratedUMassCatalog / scrape)

    private static let blueWallMenu: [MenuCategory] = [
        MenuCategory(id: "bw-quick", locationId: "d0000000-0000-4000-8000-000000000005", name: "Quick Bites", sortOrder: 0, items: [
            item("bwi-1", "bw-quick", "Personal Pepperoni Pizza", "Crispy edge, lots of cheese.", 899, [], "https://images.unsplash.com/photo-1513104890138-7c749659a591?w=600"),
            item("bwi-2", "bw-quick", "Chicken Quesadilla", "Pepper jack, salsa, sour cream.", 849, [.halal], "https://images.unsplash.com/photo-1618040996337-56904b7850b9?w=600"),
            item("bwi-3", "bw-quick", "Soft Serve Cup", "Vanilla-chocolate twist.", 349, [.vegetarian], "https://images.unsplash.com/photo-1563805042-7684c019e1cb?w=600"),
        ]),
    ]

    private static let cosmicMenu: [MenuCategory] = [
        MenuCategory(id: "cc-drinks", locationId: "d0000000-0000-4000-8000-000000000006", name: "Café", sortOrder: 0, items: [
            item("ci-1", "cc-drinks", "Iced Oat Latte", "Double shot, oat milk, no syrup drama.", 495, [.vegan], "https://images.unsplash.com/photo-1461023058943-07fcbe16d735?w=600"),
            item("ci-2", "cc-drinks", "Everything Bagel", "Toasted, cream cheese.", 425, [.vegetarian], "https://images.unsplash.com/photo-1509440159596-0249088772ff?w=600"),
        ]),
    ]

    private static func item(
        _ id: String,
        _ categoryId: String,
        _ name: String,
        _ description: String,
        _ price: Int,
        _ tags: [DietaryTag],
        _ image: String
    ) -> MenuItem {
        MenuItem(
            id: id,
            categoryId: categoryId,
            name: name,
            description: description,
            priceCents: price,
            tags: tags,
            imageURL: URL(string: image),
            isAvailable: true,
            customizations: [
                MenuCustomization(
                    id: "\(id)-size",
                    name: "Size",
                    options: [
                        CustomizationOption(id: "\(id)-reg", name: "Regular", priceCentsDelta: 0),
                        CustomizationOption(id: "\(id)-lg", name: "Large", priceCentsDelta: 150),
                    ],
                    isRequired: true,
                    allowsMultiple: false
                ),
                MenuCustomization(
                    id: "\(id)-extras",
                    name: "Extras",
                    options: [
                        CustomizationOption(id: "\(id)-extra-sauce", name: "Extra sauce", priceCentsDelta: 50),
                        CustomizationOption(id: "\(id)-no-onion", name: "No onion", priceCentsDelta: 0),
                    ],
                    isRequired: false,
                    allowsMultiple: true
                ),
            ]
        )
    }
}
