import Foundation
import CoreLocation

/// Live order place / accept / transition against Supabase + `transition-order`.
actor SupabaseOrderRepository: OrderRepository {
    private let client: SupabaseHTTPClient

    init(client: SupabaseHTTPClient) {
        self.client = client
    }

    func placeOrder(
        customerId: String,
        location: DiningLocation,
        dropoff: Building,
        dropoffNote: String,
        cart: Cart,
        tipCents: Int,
        deliveryFeeCents: Int,
        runnerMealBumpCents: Int,
        paymentIntentId: String?
    ) async throws -> Order {
        let mode = OrderFulfillmentMode.forLocationType(location.type)
        let bump = mode == .mealSwipe ? runnerMealBumpCents : 0
        let paymentStatus = paymentIntentId == nil ? "unpaid" : "succeeded"

        let inserted = try await client.insertOrder(
            customerId: customerId,
            locationId: location.id,
            dropoffBuildingId: dropoff.id,
            dropoffNote: dropoffNote.isEmpty ? nil : dropoffNote,
            subtotalCents: cart.subtotalCents,
            deliveryFeeCents: deliveryFeeCents,
            tipCents: tipCents,
            fulfillmentMode: mode.dbValue,
            runnerMealBumpCents: bump,
            paymentIntentId: paymentIntentId,
            paymentStatus: paymentStatus
        )

        let lineItems = cart.items.map {
            let menuId = UUID(uuidString: $0.menuItem.id) != nil ? $0.menuItem.id : nil
            return RemoteOrderItemInsert(
                order_id: inserted.id,
                menu_item_id: menuId,
                name: $0.menuItem.name,
                unit_price_cents: $0.unitPriceCents,
                quantity: $0.quantity,
                special_instructions: $0.specialInstructions.isEmpty ? nil : $0.specialInstructions
            )
        }
        if !lineItems.isEmpty {
            try await client.insertOrderItems(lineItems)
        }

        return try await fetchOrder(id: inserted.id)
    }

    func fetchOrder(id: String) async throws -> Order {
        let row = try await client.fetchOrderRow(id: id)
        var order = try Self.mapOrder(row)
        if let uid = await client.currentUserId, uid == order.customerId {
            if let code = try? await client.fetchHandoffCode(orderId: id) {
                order = order.withHandoffCode(code)
            }
        }
        return order
    }

    func fetchOrders(forCustomerId customerId: String) async throws -> [Order] {
        let rows = try await client.fetchOrders(customerId: customerId)
        return try rows.map { try Self.mapOrder($0) }
    }

    func cancelOrder(id: String, customerId: String) async throws -> Order {
        _ = customerId
        _ = try await client.transitionOrder(orderId: id, newStatus: "cancelled", handoffCode: nil)
        return try await fetchOrder(id: id)
    }

    func rateRunner(orderId: String, stars: Int, comment: String?) async throws {
        let order = try await fetchOrder(id: orderId)
        guard order.status == .delivered else {
            throw AppError(message: "You can rate after delivery.")
        }
        guard let runnerId = order.runnerId else {
            throw AppError(message: "No runner on this order.")
        }
        guard let fromId = await client.currentUserId else {
            throw AppError(message: "Sign in to rate.")
        }
        try await client.submitRating(
            orderId: orderId,
            fromUserId: fromId,
            toUserId: runnerId,
            stars: min(5, max(1, stars)),
            comment: comment?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        )
    }

    func fetchRatings(forRunnerId runnerId: String) async throws -> [RunnerRating] {
        let rows = try await client.fetchRatings(forRunnerId: runnerId)
        return rows.map {
            RunnerRating(
                id: $0.id,
                orderId: $0.order_id,
                fromUserId: $0.from_user_id,
                toUserId: $0.to_user_id,
                stars: $0.stars,
                comment: $0.comment,
                createdAt: Self.parseDate($0.created_at) ?? .now
            )
        }
    }

    func fetchAvailableJobs(campusId: String) async throws -> [AvailableDeliveryJob] {
        _ = campusId
        let rows = try await client.fetchOpenOrders()
        return try rows.map { row in
            let order = try Self.mapOrder(row)
            let pickup = row.dining_locations
            let drop = row.dropoff
            let distance: Double = {
                guard let plat = pickup?.lat, let plng = pickup?.lng,
                      let dlat = drop?.lat, let dlng = drop?.lng else {
                    return 800
                }
                let a = CLLocation(latitude: plat, longitude: plng)
                let b = CLLocation(latitude: dlat, longitude: dlng)
                return a.distance(from: b)
            }()
            return AvailableDeliveryJob(
                order: order,
                pickupName: pickup?.name ?? order.locationName,
                dropoffName: drop?.name ?? order.dropoffBuildingName,
                distanceMeters: distance,
                itemCount: order.items.reduce(0) { $0 + $1.quantity },
                payoutCents: order.runnerPayoutCents
            )
        }
    }

    func acceptJob(orderId: String, runner: RunnerSnapshot) async throws -> Order {
        _ = runner
        _ = try await client.transitionOrder(orderId: orderId, newStatus: "accepted", handoffCode: nil)
        return try await fetchOrder(id: orderId)
    }

    func transition(orderId: String, to status: OrderStatus, runnerId: String, handoffCode: String?) async throws -> Order {
        _ = runnerId
        _ = try await client.transitionOrder(
            orderId: orderId,
            newStatus: status.dbValue,
            handoffCode: handoffCode
        )
        return try await fetchOrder(id: orderId)
    }

    func fetchActiveRunnerOrder(runnerId: String) async throws -> Order? {
        let rows = try await client.fetchRunnerActiveOrders(runnerId: runnerId)
        guard let first = rows.first else { return nil }
        return try Self.mapOrder(first)
    }

    func fetchEarnings(runnerId: String) async throws -> EarningsSummary {
        let rows = try await client.fetchRunnerDeliveredOrders(runnerId: runnerId)
        let delivered = try rows
            .map { try Self.mapOrder($0) }
            .sorted { ($0.deliveredAt ?? .distantPast) > ($1.deliveredAt ?? .distantPast) }

        let today = delivered
            .filter { ($0.deliveredAt ?? .distantPast).isToday }
            .reduce(0) { $0 + $1.runnerPayoutCents }

        let calendar = Calendar.current
        let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: .now)) ?? .now
        let weekOrders = delivered.filter { ($0.deliveredAt ?? .distantPast) >= weekStart }
        let week = weekOrders.reduce(0) { $0 + $1.runnerPayoutCents }

        var dayTotals = Array(repeating: 0, count: 7)
        for order in weekOrders {
            guard let deliveredAt = order.deliveredAt else { continue }
            let weekday = calendar.component(.weekday, from: deliveredAt)
            let monFirst = (weekday + 5) % 7
            dayTotals[monFirst] += order.runnerPayoutCents
        }
        let labels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        let bars = labels.enumerated().map { index, label in
            DailyEarning(id: label, dayLabel: label, cents: dayTotals[index])
        }

        let available = rows
            .filter { $0.runner_paid_out_at == nil }
            .compactMap { try? Self.mapOrder($0) }
            .reduce(0) { $0 + $1.runnerPayoutCents }

        let profile = try? await client.fetchProfile(userId: runnerId)
        let linked = (profile?.stripe_account_id?.isEmpty == false) || RunnerPayoutStore.isBankLinked
        if linked { RunnerPayoutStore.isBankLinked = true }

        return EarningsSummary(
            todayCents: today,
            weekCents: week,
            availableCents: available,
            dailyBars: bars,
            payoutStatus: linked
                ? "Bank linked · cash out sends tips, fees, and retail food reimbursements"
                : "Link a bank with Stripe Connect to cash out",
            bankLinked: linked,
            history: delivered
        )
    }

    // MARK: - Mapping

    private static func mapOrder(_ row: RemoteOrderRow) throws -> Order {
        guard let status = OrderStatus(dbValue: row.status) else {
            throw AppError(message: "Unknown order status: \(row.status)")
        }
        let mode = OrderFulfillmentMode(dbValue: row.fulfillment_mode ?? "retail_purchase") ?? .retailPurchase
        let items = (row.order_items ?? []).map {
            OrderLineItem(
                id: $0.id,
                name: $0.name,
                quantity: $0.quantity,
                unitPriceCents: $0.unit_price_cents,
                specialInstructions: $0.special_instructions
            )
        }
        let runner: RunnerSnapshot? = {
            guard let profile = row.runner_profile else { return nil }
            let vehicle = VehicleType(rawValue: profile.vehicle_type ?? "walk") ?? .walk
            return RunnerSnapshot(
                id: profile.id,
                name: profile.full_name ?? "Runner",
                rating: profile.rating ?? 5.0,
                vehicleType: vehicle,
                avatarURL: profile.avatar_url.flatMap(URL.init(string:))
            )
        }()

        return Order(
            id: row.id,
            customerId: row.customer_id,
            runnerId: row.runner_id,
            locationId: row.location_id,
            locationName: row.dining_locations?.name ?? "Dining",
            dropoffBuildingId: row.dropoff_building_id,
            dropoffBuildingName: row.dropoff?.name ?? "Building",
            dropoffNote: row.dropoff_note ?? "",
            status: status,
            subtotalCents: row.subtotal_cents,
            deliveryFeeCents: row.delivery_fee_cents,
            tipCents: row.tip_cents,
            runnerMealBumpCents: row.runner_meal_bump_cents ?? 0,
            fulfillmentMode: mode,
            handoffCode: "",
            items: items,
            runner: runner,
            placedAt: parseDate(row.placed_at) ?? .now,
            acceptedAt: parseDate(row.accepted_at),
            atPickupAt: parseDate(row.at_pickup_at),
            pickedUpAt: parseDate(row.picked_up_at),
            enRouteAt: parseDate(row.en_route_at),
            deliveredAt: parseDate(row.delivered_at),
            cancelledAt: parseDate(row.cancelled_at)
        )
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        if let d = ISO8601DateFormatter().date(from: value) { return d }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: value)
    }
}

private extension Order {
    func withHandoffCode(_ code: String) -> Order {
        Order(
            id: id,
            customerId: customerId,
            runnerId: runnerId,
            locationId: locationId,
            locationName: locationName,
            dropoffBuildingId: dropoffBuildingId,
            dropoffBuildingName: dropoffBuildingName,
            dropoffNote: dropoffNote,
            status: status,
            subtotalCents: subtotalCents,
            deliveryFeeCents: deliveryFeeCents,
            tipCents: tipCents,
            runnerMealBumpCents: runnerMealBumpCents,
            fulfillmentMode: fulfillmentMode,
            handoffCode: code,
            items: items,
            runner: runner,
            placedAt: placedAt,
            acceptedAt: acceptedAt,
            atPickupAt: atPickupAt,
            pickedUpAt: pickedUpAt,
            enRouteAt: enRouteAt,
            deliveredAt: deliveredAt,
            cancelledAt: cancelledAt
        )
    }
}
