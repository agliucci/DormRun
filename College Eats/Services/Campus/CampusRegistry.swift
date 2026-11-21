import Foundation

/// Data-driven campus gate: map `.edu` domains → campus without code changes per school.
enum CampusRegistry {
    /// Seed campuses shipped with the app. Add a row here (or load from Supabase `campuses`) to expand.
    static let bundled: [Campus] = [
        MockCatalogData.campus,
        // Example of how a second school would land — data only:
        // Campus(id: "...", slug: "smith", name: "Smith College", eduEmailDomains: ["smith.edu"], latitude: ..., longitude: ...)
    ]

    static func campus(forEmail email: String, from campuses: [Campus] = bundled) -> Campus? {
        guard let domain = emailDomain(from: email) else { return nil }
        return campuses.first { campus in
            campus.eduEmailDomains.contains { $0.caseInsensitiveCompare(domain) == .orderedSame }
        }
    }

    static func emailDomain(from email: String) -> String? {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let parts = trimmed.split(separator: "@")
        guard parts.count == 2, parts[1].contains(".") else { return nil }
        return String(parts[1])
    }

    static func isAllowedCampusEmail(_ email: String, campuses: [Campus] = bundled) -> Bool {
        campus(forEmail: email, from: campuses) != nil
    }
}
