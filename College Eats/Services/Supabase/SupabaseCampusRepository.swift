import Foundation

/// Live campus catalog from Supabase (menus refresh when scrape-menus runs).
/// Falls back to bundled GeneratedUMassCatalog / MockCatalogData when offline.
actor SupabaseCampusRepository: CampusRepository {
    private let client: SupabaseHTTPClient
    private let fallback = MockCampusRepository()

    init(client: SupabaseHTTPClient) {
        self.client = client
    }

    func fetchCampuses() async throws -> [Campus] {
        do {
            let rows = try await client.fetchCampuses()
            let mapped = rows.map {
                Campus(
                    id: $0.id,
                    slug: $0.slug,
                    name: $0.name,
                    eduEmailDomains: $0.edu_email_domains,
                    latitude: MockCatalogData.campus.latitude,
                    longitude: MockCatalogData.campus.longitude
                )
            }
            return mapped.isEmpty ? try await fallback.fetchCampuses() : mapped
        } catch {
            return try await fallback.fetchCampuses()
        }
    }

    func campus(forEmailDomain domain: String) async throws -> Campus? {
        let normalized = domain.lowercased()
        let campuses = try await fetchCampuses()
        return campuses.first { $0.eduEmailDomains.contains(normalized) }
    }

    func fetchBuildings(campusId: String) async throws -> [Building] {
        do {
            let rows = try await client.fetchBuildings(campusId: campusId)
            let mapped = rows.map {
                Building(
                    id: $0.id,
                    campusId: $0.campus_id,
                    name: $0.name,
                    neighborhood: $0.neighborhood ?? "",
                    latitude: $0.lat,
                    longitude: $0.lng
                )
            }
            return mapped.isEmpty ? try await fallback.fetchBuildings(campusId: campusId) : mapped
        } catch {
            return try await fallback.fetchBuildings(campusId: campusId)
        }
    }

    func fetchDiningLocations(campusId: String) async throws -> [DiningLocation] {
        do {
            let rows = try await client.fetchDiningLocations(campusId: campusId)
            let mapped = rows.compactMap { Self.mapLocation($0) }
            return mapped.isEmpty ? try await fallback.fetchDiningLocations(campusId: campusId) : mapped
        } catch {
            return try await fallback.fetchDiningLocations(campusId: campusId)
        }
    }

    func fetchMenu(locationId: String) async throws -> [MenuCategory] {
        do {
            let rows = try await client.fetchMenu(locationId: locationId)
            let mapped = rows.map { cat in
                MenuCategory(
                    id: cat.id,
                    locationId: cat.location_id,
                    name: cat.name,
                    sortOrder: cat.sort_order,
                    items: (cat.menu_items ?? []).map { item in
                        MenuItem(
                            id: item.id,
                            categoryId: item.category_id,
                            name: item.name,
                            description: item.description ?? "",
                            priceCents: item.price_cents,
                            tags: Self.mapTags(item.tags ?? []),
                            imageURL: item.image_url.flatMap(URL.init(string:)),
                            isAvailable: item.is_available ?? true,
                            customizations: []
                        )
                    }
                )
            }
            if !mapped.isEmpty, mapped.contains(where: { !$0.items.isEmpty }) {
                return mapped
            }
            return try await fallback.fetchMenu(locationId: locationId)
        } catch {
            return try await fallback.fetchMenu(locationId: locationId)
        }
    }

    private static func mapLocation(_ row: RemoteDiningLocation) -> DiningLocation? {
        let type: DiningLocationType = row.type == "retail" ? .retail : .commons
        let busy: BusyLevel
        switch row.busy_level {
        case "low": busy = .low
        case "high": busy = .high
        default: busy = .medium
        }
        let asset = Self.assetName(for: row.name)
        // Keep neighborhood from mock when DB doesn't store it.
        let neighborhood = MockCatalogData.locations.first(where: { $0.id == row.id })?.neighborhood
            ?? MockCatalogData.locations.first(where: { $0.name.localizedCaseInsensitiveContains(row.name.split(separator: " ").first.map(String.init) ?? row.name) })?.neighborhood
            ?? "Campus"
        return DiningLocation(
            id: row.id,
            campusId: row.campus_id,
            name: row.name.replacingOccurrences(of: " Dining Commons", with: ""),
            type: type,
            neighborhood: neighborhood,
            imageURL: row.image_url.flatMap(URL.init(string:)),
            imageAssetName: asset,
            latitude: row.lat,
            longitude: row.lng,
            hours: row.hours ?? MockCatalogData.standardHours,
            busyLevel: busy
        )
    }

    private static func assetName(for name: String) -> String? {
        let lower = name.lowercased()
        if lower.contains("worcester") { return "DiningWorcester" }
        if lower.contains("franklin") { return "DiningFranklin" }
        if lower.contains("berkshire") { return "DiningBerkshire" }
        if lower.contains("hampshire") { return "DiningHampshire" }
        if lower.contains("blue wall") { return "DiningBlueWall" }
        if lower.contains("cosmic") { return "DiningCosmic" }
        return nil
    }

    private static func mapTags(_ tags: [String]) -> [DietaryTag] {
        tags.compactMap {
            switch $0 {
            case "vegan": .vegan
            case "vegetarian": .vegetarian
            case "gf": .glutenFree
            case "halal": .halal
            default: nil
            }
        }
    }
}
