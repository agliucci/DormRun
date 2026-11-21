import Foundation

/// Live Supabase email OTP auth + profile persistence. Used when `SupabaseConfig.isConfigured`.
actor SupabaseAuthRepository: AuthRepository {
    private let client: SupabaseHTTPClient
    private var cachedProfile: UserProfile?
    private var campuses: [Campus] = CampusRegistry.bundled

    init(client: SupabaseHTTPClient) {
        self.client = client
    }

    func sendOTP(email: String) async throws {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        try await refreshCampusesIfNeeded()
        guard CampusRegistry.isAllowedCampusEmail(trimmed, campuses: campuses) else {
            throw AppError(message: "That .edu isn’t on a supported campus yet.")
        }
        try await client.sendEmailOTP(email: trimmed)
    }

    func verifyOTP(email: String, code: String) async throws -> UserProfile {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        try await refreshCampusesIfNeeded()
        guard let campus = CampusRegistry.campus(forEmail: trimmed, from: campuses) else {
            throw AppError(message: "That .edu isn’t on a supported campus yet.")
        }

        let session = try await client.verifyEmailOTP(email: trimmed, code: code)
        if let remote = try await client.fetchProfile(userId: session.user.id) {
            let profile = mapProfile(remote, email: trimmed, fallbackCampusId: campus.id)
            cachedProfile = profile
            ProfilePersistence.save(profile)
            return profile
        }

        // Trigger may create the row; if not, seed a minimal profile.
        let seed = RemoteProfile(
            id: session.user.id,
            campus_id: campus.id,
            full_name: "",
            phone: "",
            home_building_id: nil,
            is_runner: false,
            vehicle_type: nil,
            rating: 5,
            avatar_url: nil,
            push_token: nil
        )
        let remote = try await client.upsertProfile(seed)
        let profile = mapProfile(remote, email: trimmed, fallbackCampusId: campus.id)
        cachedProfile = profile
        ProfilePersistence.save(profile)
        return profile
    }

    func currentProfile() async throws -> UserProfile? {
        if let cachedProfile { return cachedProfile }
        if let local = ProfilePersistence.load() {
            cachedProfile = local
            return local
        }
        guard let userId = await client.currentUserId else { return nil }
        guard let remote = try await client.fetchProfile(userId: userId) else { return nil }
        let email = remote.id // email may be missing on profile; keep persisted if available
        let profile = mapProfile(remote, email: ProfilePersistence.load()?.email ?? email, fallbackCampusId: MockCatalogData.campusId)
        cachedProfile = profile
        ProfilePersistence.save(profile)
        return profile
    }

    func updateProfile(_ profile: UserProfile) async throws -> UserProfile {
        try await refreshCampusesIfNeeded()
        let campusId = campuses.first(where: { $0.id == profile.campusId })?.id
            ?? CampusRegistry.campus(forEmail: profile.email, from: campuses)?.id
            ?? MockCatalogData.campusId

        let remote = RemoteProfile(
            id: profile.id,
            campus_id: campusId,
            full_name: profile.fullName,
            phone: profile.phone,
            home_building_id: profile.homeBuildingId,
            is_runner: profile.isRunner,
            vehicle_type: profile.vehicleType?.rawValue,
            rating: nil,
            avatar_url: profile.avatarURL?.absoluteString,
            push_token: nil
        )
        let saved = try await client.upsertProfile(remote)
        if let token = ProfilePersistence.pushToken {
            try? await client.updatePushToken(userId: profile.id, token: token)
        }
        let mapped = mapProfile(saved, email: profile.email, fallbackCampusId: campusId)
        var withMode = mapped
        withMode.mode = profile.mode
        withMode.campusId = campusId
        cachedProfile = withMode
        ProfilePersistence.save(withMode)
        return withMode
    }

    func signOut() async throws {
        try await client.signOut()
        cachedProfile = nil
        ProfilePersistence.clear()
    }

    private func refreshCampusesIfNeeded() async throws {
        if let remote = try? await client.fetchCampuses(), !remote.isEmpty {
            campuses = remote.map {
                Campus(
                    id: $0.id,
                    slug: $0.slug,
                    name: $0.name,
                    eduEmailDomains: $0.edu_email_domains,
                    latitude: MockCatalogData.campus.latitude,
                    longitude: MockCatalogData.campus.longitude
                )
            }
        }
    }

    private func mapProfile(_ remote: RemoteProfile, email: String, fallbackCampusId: String) -> UserProfile {
        UserProfile(
            id: remote.id,
            campusId: remote.campus_id ?? fallbackCampusId,
            fullName: remote.full_name ?? "",
            email: email,
            phone: remote.phone ?? "",
            homeBuildingId: remote.home_building_id,
            isRunner: remote.is_runner ?? false,
            vehicleType: remote.vehicle_type.flatMap(VehicleType.init(rawValue:)),
            rating: remote.rating ?? 5,
            avatarURL: remote.avatar_url.flatMap(URL.init(string:)),
            mode: ProfilePersistence.load()?.mode ?? .customer
        )
    }
}

/// Mock OTP auth with campus gate + UserDefaults profile persistence (works offline / without keys).
actor PersistingMockAuthRepository: AuthRepository {
    private var profile: UserProfile?
    private var pendingEmail: String?

    init() {
        profile = ProfilePersistence.load()
    }

    func sendOTP(email: String) async throws {
        try await Task.sleep(nanoseconds: 350_000_000)
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard CampusRegistry.isAllowedCampusEmail(trimmed) else {
            throw AppError(message: "Use a campus .edu — right now that’s @umass.edu.")
        }
        pendingEmail = trimmed
    }

    func verifyOTP(email: String, code: String) async throws -> UserProfile {
        try await Task.sleep(nanoseconds: 350_000_000)
        guard code.count == 6, code.allSatisfy(\.isNumber) else {
            throw AppError(message: "Enter the 6-digit code from your email.")
        }
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let campus = CampusRegistry.campus(forEmail: trimmed) else {
            throw AppError(message: "That .edu isn’t on a supported campus yet.")
        }

        if var existing = profile, existing.email == trimmed {
            existing.campusId = campus.id
            profile = existing
            ProfilePersistence.save(existing)
            return existing
        }

        let created = UserProfile(
            id: UUID().uuidString,
            campusId: campus.id,
            fullName: "",
            email: trimmed,
            phone: "",
            homeBuildingId: nil,
            isRunner: false,
            vehicleType: nil,
            rating: 5,
            avatarURL: nil,
            mode: .customer
        )
        profile = created
        ProfilePersistence.save(created)
        pendingEmail = nil
        return created
    }

    func currentProfile() async throws -> UserProfile? {
        if let profile { return profile }
        let loaded = ProfilePersistence.load()
        profile = loaded
        return loaded
    }

    func updateProfile(_ profile: UserProfile) async throws -> UserProfile {
        try await Task.sleep(nanoseconds: 200_000_000)
        self.profile = profile
        ProfilePersistence.save(profile)
        return profile
    }

    func signOut() async throws {
        profile = nil
        ProfilePersistence.clear()
    }
}

enum ProfilePersistence {
    private static let profileKey = "umasseats.profile"
    private static let pushKey = "umasseats.pushToken"

    static var pushToken: String? {
        get { UserDefaults.standard.string(forKey: pushKey) }
        set { UserDefaults.standard.set(newValue, forKey: pushKey) }
    }

    static func save(_ profile: UserProfile) {
        if let data = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(data, forKey: profileKey)
        }
    }

    static func load() -> UserProfile? {
        guard let data = UserDefaults.standard.data(forKey: profileKey) else { return nil }
        return try? JSONDecoder().decode(UserProfile.self, from: data)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: profileKey)
    }
}
