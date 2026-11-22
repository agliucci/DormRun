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

    // MARK: - Orders

    func insertOrder(
        customerId: String,
        locationId: String,
        dropoffBuildingId: String,
        dropoffNote: String?,
        subtotalCents: Int,
        deliveryFeeCents: Int,
        tipCents: Int,
        fulfillmentMode: String,
        runnerMealBumpCents: Int,
        paymentIntentId: String?,
        paymentStatus: String
    ) async throws -> RemoteOrderInsertResult {
        struct Body: Encodable {
            let customer_id: String
            let location_id: String
            let dropoff_building_id: String
            let dropoff_note: String?
            let subtotal_cents: Int
            let delivery_fee_cents: Int
            let tip_cents: Int
            let fulfillment_mode: String
            let runner_meal_bump_cents: Int
            let payment_intent_id: String?
            let payment_status: String
            let status: String
        }
        let data = try await request(
            path: "/rest/v1/orders",
            method: "POST",
            body: Body(
                customer_id: customerId,
                location_id: locationId,
                dropoff_building_id: dropoffBuildingId,
                dropoff_note: dropoffNote,
                subtotal_cents: subtotalCents,
                delivery_fee_cents: deliveryFeeCents,
                tip_cents: tipCents,
                fulfillment_mode: fulfillmentMode,
                runner_meal_bump_cents: runnerMealBumpCents,
                payment_intent_id: paymentIntentId,
                payment_status: paymentStatus,
                status: "placed"
            ),
            authorized: true,
            prefer: "return=representation"
        )
        let rows = try JSONDecoder.supabase.decode([RemoteOrderInsertResult].self, from: data)
        guard let first = rows.first else {
            throw AppError(message: "Couldn't place order.")
        }
        return first
    }

    func insertOrderItems(_ items: [RemoteOrderItemInsert]) async throws {
        guard !items.isEmpty else { return }
        _ = try await request(
            path: "/rest/v1/order_items",
            method: "POST",
            body: items,
            authorized: true,
            prefer: "return=minimal"
        )
    }

    func fetchOrderRow(id: String) async throws -> RemoteOrderRow {
        let select = SupabaseOrderContract.orderSelectWithEmbeds
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let data = try await request(
            path: "/rest/v1/orders?id=eq.\(id)&select=\(select)&limit=1",
            method: "GET",
            body: Optional<String>.none,
            authorized: true
        )
        let rows = try JSONDecoder.supabase.decode([RemoteOrderRow].self, from: data)
        guard let first = rows.first else {
            throw AppError(message: "Order not found.")
        }
        return first
    }

    func fetchOrders(customerId: String) async throws -> [RemoteOrderRow] {
        let select = SupabaseOrderContract.orderSelectWithEmbeds
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let data = try await request(
            path: "/rest/v1/orders?customer_id=eq.\(customerId)&select=\(select)&order=placed_at.desc",
            method: "GET",
            body: Optional<String>.none,
            authorized: true
        )
        return try JSONDecoder.supabase.decode([RemoteOrderRow].self, from: data)
    }

    func fetchOpenOrders() async throws -> [RemoteOrderRow] {
        let select = SupabaseOrderContract.orderSelectWithEmbeds
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let data = try await request(
            path: "/rest/v1/orders?status=eq.placed&runner_id=is.null&select=\(select)&order=placed_at.asc",
            method: "GET",
            body: Optional<String>.none,
            authorized: true
        )
        return try JSONDecoder.supabase.decode([RemoteOrderRow].self, from: data)
    }

    func fetchRunnerActiveOrders(runnerId: String) async throws -> [RemoteOrderRow] {
        let select = SupabaseOrderContract.orderSelectWithEmbeds
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let data = try await request(
            path: "/rest/v1/orders?runner_id=eq.\(runnerId)&status=in.(accepted,at_pickup,picked_up,en_route)&select=\(select)&order=accepted_at.desc&limit=1",
            method: "GET",
            body: Optional<String>.none,
            authorized: true
        )
        return try JSONDecoder.supabase.decode([RemoteOrderRow].self, from: data)
    }

    func fetchRunnerDeliveredOrders(runnerId: String) async throws -> [RemoteOrderRow] {
        let select = SupabaseOrderContract.orderSelectWithEmbeds
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let data = try await request(
            path: "/rest/v1/orders?runner_id=eq.\(runnerId)&status=eq.delivered&select=\(select)&order=delivered_at.desc",
            method: "GET",
            body: Optional<String>.none,
            authorized: true
        )
        return try JSONDecoder.supabase.decode([RemoteOrderRow].self, from: data)
    }

    func fetchHandoffCode(orderId: String) async throws -> String {
        struct Body: Encodable { let p_order_id: String }
        let data = try await request(
            path: "/rest/v1/rpc/\(SupabaseOrderContract.getHandoffCodeRPC)",
            method: "POST",
            body: Body(p_order_id: orderId),
            authorized: true
        )
        if let code = try? JSONDecoder().decode(String.self, from: data) {
            return code
        }
        if let obj = try? JSONSerialization.jsonObject(with: data) as? String {
            return obj
        }
        throw AppError(message: "Couldn't load handoff code.")
    }

    func transitionOrder(orderId: String, newStatus: String, handoffCode: String?) async throws -> Data {
        struct Body: Encodable {
            let order_id: String
            let new_status: String
            let handoff_code: String?
        }
        return try await request(
            path: "/functions/v1/\(SupabaseOrderContract.transitionEdgeFunction)",
            method: "POST",
            body: Body(order_id: orderId, new_status: newStatus, handoff_code: handoffCode),
            authorized: true
        )
    }

    // MARK: - Edge functions

    func createPaymentIntent(amountCents: Int, customerEmail: String) async throws -> StripePaymentIntentResponse {
        struct Body: Encodable {
            let amount_cents: Int
            let currency: String
            let customer_email: String
        }
        let data = try await request(
            path: "/functions/v1/create-payment-intent",
            method: "POST",
            body: Body(amount_cents: amountCents, currency: "usd", customer_email: customerEmail),
            authorized: true
        )
        return try JSONDecoder().decode(StripePaymentIntentResponse.self, from: data)
    }

    func createConnectAccountLink(refreshURL: String, returnURL: String) async throws -> StripeConnectLinkResponse {
        struct Body: Encodable {
            let refresh_url: String
            let return_url: String
        }
        let data = try await request(
            path: "/functions/v1/create-connect-account-link",
            method: "POST",
            body: Body(refresh_url: refreshURL, return_url: returnURL),
            authorized: true
        )
        return try JSONDecoder().decode(StripeConnectLinkResponse.self, from: data)
    }

    func createCashOut() async throws -> StripeCashOutResponse {
        struct Body: Encodable {}
        let data = try await request(
            path: "/functions/v1/create-cash-out",
            method: "POST",
            body: Body(),
            authorized: true
        )
        return try JSONDecoder().decode(StripeCashOutResponse.self, from: data)
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
        prefer: String? = nil,
        isRetry: Bool = false
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
        if !(200..<300).contains(http.statusCode) {
            // Expired JWT on payments / REST — refresh once and retry.
            if http.statusCode == 401, authorized, !isRetry, await refreshSessionIfPossible() {
                return try await self.request(
                    path: path,
                    method: method,
                    body: body,
                    authorized: authorized,
                    prefer: prefer,
                    isRetry: true
                )
            }
            let message = String(data: data, encoding: .utf8) ?? "Request failed (\(http.statusCode))"
            throw AppError(message: simplifiedError(message, status: http.statusCode, path: path))
        }
        return data
    }

    @discardableResult
    private func refreshSessionIfPossible() async -> Bool {
        guard let refreshToken else { return false }
        struct Body: Encodable {
            let refresh_token: String
        }
        do {
            // Call auth refresh without going through authorized retry loop.
            guard let url = URL(string: "/auth/v1/token?grant_type=refresh_token", relativeTo: baseURL) else {
                return false
            }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(anonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONEncoder().encode(Body(refresh_token: refreshToken))
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return false
            }
            let session = try JSONDecoder().decode(AuthSession.self, from: data)
            persist(session: session)
            return true
        } catch {
            return false
        }
    }

    private func simplifiedError(_ raw: String, status: Int, path: String) -> String {
        let lower = raw.lowercased()
        let isOTPPath = path.contains("/auth/v1/verify") || path.contains("/auth/v1/otp")
        if isOTPPath || lower.contains("otp") || lower.contains("token has expired") && path.contains("/auth/") {
            return "Invalid or expired code. Request a new one."
        }
        if status == 401 {
            return "Session expired. Sign out and sign back in, then try again."
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
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        // PostgREST uses "message"; edge functions often use "error".
        if let message = obj["message"] as? String, !message.isEmpty { return message }
        if let error = obj["error"] as? String, !error.isEmpty { return error }
        if let errorObj = obj["error"] as? [String: Any],
           let message = errorObj["message"] as? String,
           !message.isEmpty {
            return message
        }
        return nil
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
    var stripe_account_id: String?
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

struct StripePaymentIntentResponse: Codable, Sendable {
    let paymentIntentId: String
    let clientSecret: String
    let publishableKey: String?
}

struct StripeConnectLinkResponse: Codable, Sendable {
    let url: String
    let accountId: String?
}

struct StripeCashOutResponse: Codable, Sendable {
    let transferredCents: Int
    let transferId: String?
    let message: String?
    let error: String?
}

struct RemoteOrderInsertResult: Codable, Sendable {
    let id: String
}

struct RemoteOrderItemInsert: Encodable, Sendable {
    let order_id: String
    let menu_item_id: String?
    let name: String
    let unit_price_cents: Int
    let quantity: Int
    let special_instructions: String?
}

struct RemoteOrderRow: Codable, Sendable {
    let id: String
    let customer_id: String
    let runner_id: String?
    let location_id: String
    let dropoff_building_id: String
    let dropoff_note: String?
    let status: String
    let subtotal_cents: Int
    let delivery_fee_cents: Int
    let tip_cents: Int
    let fulfillment_mode: String?
    let runner_meal_bump_cents: Int?
    let payment_intent_id: String?
    let payment_status: String?
    let runner_paid_out_at: String?
    let runner_transfer_id: String?
    let placed_at: String?
    let accepted_at: String?
    let at_pickup_at: String?
    let picked_up_at: String?
    let en_route_at: String?
    let delivered_at: String?
    let cancelled_at: String?
    let cancel_reason: String?
    let dining_locations: RemoteOrderLocationEmbed?
    let dropoff: RemoteOrderBuildingEmbed?
    let order_items: [RemoteOrderItemRow]?
    let runner_profile: RemoteOrderRunnerEmbed?
}

struct RemoteOrderLocationEmbed: Codable, Sendable {
    let name: String?
    let lat: Double?
    let lng: Double?
    let type: String?
}

struct RemoteOrderBuildingEmbed: Codable, Sendable {
    let name: String?
    let lat: Double?
    let lng: Double?
}

struct RemoteOrderItemRow: Codable, Sendable {
    let id: String
    let name: String
    let quantity: Int
    let unit_price_cents: Int
    let special_instructions: String?
}

struct RemoteOrderRunnerEmbed: Codable, Sendable {
    let id: String
    let full_name: String?
    let rating: Double?
    let vehicle_type: String?
    let avatar_url: String?
}

private extension JSONDecoder {
    static var supabase: JSONDecoder {
        let decoder = JSONDecoder()
        return decoder
    }
}
