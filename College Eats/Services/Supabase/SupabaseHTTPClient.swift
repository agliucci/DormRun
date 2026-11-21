import Foundation

/// Minimal Supabase Auth + PostgREST client via URLSession (no SPM required to compile).
actor SupabaseHTTPClient {
    let baseURL: URL
    let anonKey: String

    private var accessToken: String?
    private var refreshToken: String?
    private var userId: String?

    private let session: URLSession = .shared
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let access = "umasseats.supabase.access"
        static let refresh = "umasseats.supabase.refresh"
        static let userId = "umasseats.supabase.userId"
    }

    init(baseURL: URL, anonKey: String) {
        self.baseURL = baseURL
        self.anonKey = anonKey
        self.accessToken = defaults.string(forKey: Keys.access)
        self.refreshToken = defaults.string(forKey: Keys.refresh)
        self.userId = defaults.string(forKey: Keys.userId)
    }

    var currentUserId: String? { userId }
    var isSignedIn: Bool { accessToken != nil && userId != nil }

    // MARK: - Auth OTP

    func sendEmailOTP(email: String) async throws {
        struct Body: Encodable { let email: String }
        _ = try await request(
            path: "/auth/v1/otp",
            method: "POST",
            body: Body(email: email),
            authorized: false
        )
    }

    func verifyEmailOTP(email: String, code: String) async throws -> AuthSession {
        struct Body: Encodable {
            let email: String
            let token: String
            let type: String
        }
        let data = try await request(
            path: "/auth/v1/verify",
            method: "POST",
            body: Body(email: email, token: code, type: "email"),
            authorized: false
        )
        let session = try JSONDecoder().decode(AuthSession.self, from: data)
        persist(session: session)
        return session
    }

    func signOut() async throws {
        _ = try? await request(path: "/auth/v1/logout", method: "POST", body: Optional<String>.none, authorized: true)
        clearSession()
    }

    // MARK: - Profiles

    func fetchProfile(userId: String) async throws -> RemoteProfile? {
        let data = try await request(
            path: "/rest/v1/profiles?id=eq.\(userId)&select=*",
            method: "GET",
            body: Optional<String>.none,
            authorized: true,
            prefer: "return=representation"
        )
        let rows = try JSONDecoder.supabase.decode([RemoteProfile].self, from: data)
        return rows.first
    }

    func upsertProfile(_ profile: RemoteProfile) async throws -> RemoteProfile {
        // Only columns the role may write (rating is trigger-owned; push_token optional).
        struct ProfileWrite: Encodable {
            let campus_id: String?
            let full_name: String?
            let phone: String?
            let home_building_id: String?
            let is_runner: Bool?
            let vehicle_type: String?
            let avatar_url: String?
        }
        let body = ProfileWrite(
            campus_id: profile.campus_id,
            full_name: profile.full_name,
            phone: profile.phone,
            home_building_id: profile.home_building_id,
            is_runner: profile.is_runner,
            vehicle_type: profile.vehicle_type,
            avatar_url: profile.avatar_url
        )
        let data = try await request(
            path: "/rest/v1/profiles?id=eq.\(profile.id)",
            method: "PATCH",
            body: body,
            authorized: true,
            prefer: "return=representation"
        )
        let rows = try JSONDecoder.supabase.decode([RemoteProfile].self, from: data)
        if let first = rows.first { return first }

        // Row missing (trigger didn't fire) — insert then patch.
        struct ProfileInsert: Encodable {
            let id: String
            let campus_id: String?
            let full_name: String?
            let phone: String?
            let home_building_id: String?
            let is_runner: Bool?
            let vehicle_type: String?
        }
        let inserted = try await request(
            path: "/rest/v1/profiles",
            method: "POST",
            body: ProfileInsert(
                id: profile.id,
                campus_id: profile.campus_id,
                full_name: profile.full_name,
                phone: profile.phone,
                home_building_id: profile.home_building_id,
                is_runner: profile.is_runner,
                vehicle_type: profile.vehicle_type
            ),
            authorized: true,
            prefer: "return=representation"
        )
        let created = try JSONDecoder.supabase.decode([RemoteProfile].self, from: inserted)
        guard let first = created.first else {
            throw AppError(message: "Could not save profile.")
        }
        return first
    }

    func updatePushToken(userId: String, token: String) async throws {
        struct Patch: Encodable { let push_token: String }
        _ = try await request(
            path: "/rest/v1/profiles?id=eq.\(userId)",
            method: "PATCH",
            body: Patch(push_token: token),
            authorized: true,
            prefer: "return=minimal"
        )
    }

    func publishRunnerLocation(runnerId: String, orderId: String?, lat: Double, lng: Double) async throws {
        struct Row: Encodable {
            let runner_id: String
            let order_id: String?
            let lat: Double
            let lng: Double
            let updated_at: String
        }
        let iso = ISO8601DateFormatter().string(from: .now)
        _ = try await request(
            path: "/rest/v1/runner_locations?on_conflict=runner_id",
            method: "POST",
            body: Row(runner_id: runnerId, order_id: orderId, lat: lat, lng: lng, updated_at: iso),
            authorized: true,
            prefer: "resolution=merge-duplicates,return=minimal"
        )
    }

    func fetchRunnerLocation(orderId: String) async throws -> RunnerLocation? {
        let data = try await request(
            path: "/rest/v1/runner_locations?order_id=eq.\(orderId)&select=runner_id,order_id,lat,lng,updated_at&limit=1",
            method: "GET",
            body: Optional<String>.none,
            authorized: true
        )
        let rows = try JSONDecoder.supabase.decode([RemoteRunnerLocation].self, from: data)
        return rows.first.map {
            RunnerLocation(
                runnerId: $0.runner_id,
                orderId: $0.order_id,
                latitude: $0.lat,
                longitude: $0.lng,
                updatedAt: ISO8601DateFormatter().date(from: $0.updated_at) ?? .now
            )
        }
    }

    func fetchBuildings(campusId: String) async throws -> [RemoteBuilding] {
        let data = try await request(
            path: "/rest/v1/buildings?campus_id=eq.\(campusId)&select=*&order=name.asc",
            method: "GET",
            body: Optional<String>.none,
            authorized: false
        )
        return try JSONDecoder.supabase.decode([RemoteBuilding].self, from: data)
    }

    func fetchDiningLocations(campusId: String) async throws -> [RemoteDiningLocation] {
        let data = try await request(
            path: "/rest/v1/dining_locations?campus_id=eq.\(campusId)&select=*",
            method: "GET",
            body: Optional<String>.none,
            authorized: false
        )
        return try JSONDecoder.supabase.decode([RemoteDiningLocation].self, from: data)
    }

    func fetchMenu(locationId: String) async throws -> [RemoteMenuCategory] {
        let data = try await request(
            path: "/rest/v1/menu_categories?location_id=eq.\(locationId)&select=id,location_id,name,sort_order,menu_items(id,category_id,name,description,price_cents,tags,image_url,is_available)&order=sort_order.asc",
            method: "GET",
            body: Optional<String>.none,
            authorized: false
        )
        return try JSONDecoder.supabase.decode([RemoteMenuCategory].self, from: data)
    }

    func fetchCampuses() async throws -> [RemoteCampus] {
        let data = try await request(
            path: "/rest/v1/campuses?select=*",
            method: "GET",
            body: Optional<String>.none,
            authorized: false
        )
        return try JSONDecoder.supabase.decode([RemoteCampus].self, from: data)
    }

    func submitRating(orderId: String, fromUserId: String, toUserId: String, stars: Int, comment: String?) async throws {
        struct Row: Encodable {
            let order_id: String
            let from_user_id: String
            let to_user_id: String
            let stars: Int
            let comment: String?
        }
        _ = try await request(
            path: "/rest/v1/ratings",
            method: "POST",
            body: Row(
                order_id: orderId,
                from_user_id: fromUserId,
                to_user_id: toUserId,
                stars: stars,
                comment: comment
            ),
            authorized: true,
            prefer: "return=minimal"
        )
    }

    func fetchRatings(forRunnerId runnerId: String) async throws -> [RemoteRating] {
        let data = try await request(
            path: "/rest/v1/ratings?to_user_id=eq.\(runnerId)&select=*&order=created_at.desc",
            method: "GET",
            body: Optional<String>.none,
            authorized: true
        )
        return try JSONDecoder.supabase.decode([RemoteRating].self, from: data)
    }

    func fetchOrderMessages(orderId: String) async throws -> [RemoteOrderMessage] {
        let data = try await request(
            path: "/rest/v1/order_messages?order_id=eq.\(orderId)&select=*&order=created_at.asc",
            method: "GET",
            body: Optional<String>.none,
            authorized: true
        )
        return try JSONDecoder.supabase.decode([RemoteOrderMessage].self, from: data)
    }

    func sendOrderMessage(orderId: String, senderId: String, body: String) async throws -> RemoteOrderMessage {
        struct Row: Encodable {
            let order_id: String
            let sender_id: String
            let body: String
        }
        let data = try await request(
            path: "/rest/v1/order_messages",
            method: "POST",
            body: Row(order_id: orderId, sender_id: senderId, body: body),
            authorized: true,
            prefer: "return=representation"
        )
        let rows = try JSONDecoder.supabase.decode([RemoteOrderMessage].self, from: data)
        guard let first = rows.first else {
            throw AppError(message: "Couldn't send message.")
        }
        return first
    }

    // MARK: - Internals

    private func persist(session: AuthSession) {
        accessToken = session.accessToken
        refreshToken = session.refreshToken
        userId = session.user.id
        defaults.set(session.accessToken, forKey: Keys.access)
        defaults.set(session.refreshToken, forKey: Keys.refresh)
        defaults.set(session.user.id, forKey: Keys.userId)
    }

    private func clearSession() {
        accessToken = nil
        refreshToken = nil
        userId = nil
        defaults.removeObject(forKey: Keys.access)
        defaults.removeObject(forKey: Keys.refresh)
        defaults.removeObject(forKey: Keys.userId)
    }

    private func request<Body: Encodable>(
        path: String,
        method: String,
        body: Body?,
        authorized: Bool,
        prefer: String? = nil
    ) async throws -> Data {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw AppError(message: "Invalid Supabase URL.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        if authorized, let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        } else {
            request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        }
        if let prefer {
            request.setValue(prefer, forHTTPHeaderField: "Prefer")
        }
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AppError.generic
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Request failed (\(http.statusCode))"
            throw AppError(message: simplifiedAuthError(message, status: http.statusCode))
        }
        return data
    }

    private func simplifiedAuthError(_ raw: String, status: Int) -> String {
        let lower = raw.lowercased()
        if lower.contains("otp") || status == 401 {
            return "Invalid or expired code. Request a new one."
        }
        if status == 429 {
            return "Too many attempts. Wait a moment and try again."
        }
        if lower.contains("foreign key") || lower.contains("home_building") {
            return "That dorm isn’t linked in the database. Pull to refresh and pick again."
        }
        if lower.contains("invalid input syntax for type uuid") {
            return "Profile IDs don’t match the campus database. Rebuild the app and try again."
        }
        if let message = postgrestMessage(from: raw) {
            return message
        }
        return "Couldn’t save (\(status)). Try again."
    }

    private func postgrestMessage(from raw: String) -> String? {
        guard let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = obj["message"] as? String,
              !message.isEmpty else { return nil }
        return message
    }
}

struct AuthSession: Decodable, Sendable {
    let accessToken: String
    let refreshToken: String
    let user: AuthUser

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case user
    }
}

struct AuthUser: Decodable, Sendable {
    let id: String
    let email: String?
}

struct RemoteProfile: Codable, Sendable {
    var id: String
    var campus_id: String?
    var full_name: String?
    var phone: String?
    var home_building_id: String?
    var is_runner: Bool?
    var vehicle_type: String?
    var rating: Double?
    var avatar_url: String?
    var push_token: String?
}

struct RemoteCampus: Codable, Sendable {
    let id: String
    let slug: String
    let name: String
    let edu_email_domains: [String]
}

struct RemoteRunnerLocation: Codable, Sendable {
    let runner_id: String
    let order_id: String?
    let lat: Double
    let lng: Double
    let updated_at: String
}

struct RemoteBuilding: Codable, Sendable {
    let id: String
    let campus_id: String
    let name: String
    let lat: Double
    let lng: Double
    let neighborhood: String?
}

struct RemoteDiningLocation: Codable, Sendable {
    let id: String
    let campus_id: String
    let name: String
    let type: String
    let hours: [String: [[String]]]?
    let lat: Double
    let lng: Double
    let image_url: String?
    let busy_level: String?
}

struct RemoteMenuCategory: Codable, Sendable {
    let id: String
    let location_id: String
    let name: String
    let sort_order: Int
    let menu_items: [RemoteMenuItem]?
}

struct RemoteMenuItem: Codable, Sendable {
    let id: String
    let category_id: String
    let name: String
    let description: String?
    let price_cents: Int
    let tags: [String]?
    let image_url: String?
    let is_available: Bool?
}

struct RemoteRating: Codable, Sendable {
    let id: String
    let order_id: String
    let from_user_id: String
    let to_user_id: String
    let stars: Int
    let comment: String?
    let created_at: String
}

struct RemoteOrderMessage: Codable, Sendable {
    let id: String
    let order_id: String
    let sender_id: String
    let body: String
    let created_at: String
}

private extension JSONDecoder {
    static var supabase: JSONDecoder {
        let decoder = JSONDecoder()
        return decoder
    }
}
