import Foundation

actor MockCampusRepository: CampusRepository {
    func fetchCampuses() async throws -> [Campus] {
        try await delay()
        return [MockCatalogData.campus]
    }

    func campus(forEmailDomain domain: String) async throws -> Campus? {
        try await delay(0.2)
        let normalized = domain.lowercased()
        return MockCatalogData.campus.eduEmailDomains.contains(normalized) ? MockCatalogData.campus : nil
    }

    func fetchBuildings(campusId: String) async throws -> [Building] {
        try await delay()
        return MockCatalogData.buildings.filter { $0.campusId == campusId }
    }

    func fetchDiningLocations(campusId: String) async throws -> [DiningLocation] {
        try await delay(0.45)
        return MockCatalogData.locations.filter { $0.campusId == campusId }
    }

    func fetchMenu(locationId: String) async throws -> [MenuCategory] {
        try await delay(0.35)
        return MockCatalogData.menus(for: locationId)
    }

    private func delay(_ seconds: Double = 0.3) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}

actor MockAuthRepository: AuthRepository {
    private var profile: UserProfile? = MockCatalogData.demoCustomer
    private var pendingEmail: String?

    func sendOTP(email: String) async throws {
        try await Task.sleep(nanoseconds: 400_000_000)
        let domain = email.split(separator: "@").last.map(String.init)?.lowercased() ?? ""
        guard MockCatalogData.campus.eduEmailDomains.contains(domain) else {
            throw AppError(message: "Use your .edu email for a supported campus.")
        }
        pendingEmail = email.lowercased()
    }

    func verifyOTP(email: String, code: String) async throws -> UserProfile {
        try await Task.sleep(nanoseconds: 350_000_000)
        guard code.count == 6, code.allSatisfy(\.isNumber) else {
            throw AppError(message: "Enter the 6-digit code from your email.")
        }
        // Mock accepts any 6-digit code; 000000 also works.
        var next = profile ?? MockCatalogData.demoCustomer
        next.email = email.lowercased()
        profile = next
        pendingEmail = nil
        return next
    }

    func currentProfile() async throws -> UserProfile? {
        profile
    }

    func updateProfile(_ profile: UserProfile) async throws -> UserProfile {
        try await Task.sleep(nanoseconds: 250_000_000)
        self.profile = profile
        return profile
    }

    func signOut() async throws {
        profile = nil
    }
}

actor MockOrderRepository: OrderRepository {
    private var orders: [Order] = []
    private var ratings: [RunnerRating] = []
    private var availableSeeded = false

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
        try await Task.sleep(nanoseconds: 500_000_000)
        _ = paymentIntentId
        let mode = OrderFulfillmentMode.forLocationType(location.type)
        let bump = mode == .mealSwipe ? runnerMealBumpCents : 0
        let code = String(format: "%04d", Int.random(in: 1000...9999))
        let order = Order(
            id: UUID().uuidString,
            customerId: customerId,
            runnerId: nil,
            locationId: location.id,
            locationName: location.name,
            dropoffBuildingId: dropoff.id,
            dropoffBuildingName: dropoff.name,
            dropoffNote: dropoffNote,
            status: .placed,
            subtotalCents: cart.subtotalCents,
            deliveryFeeCents: deliveryFeeCents,
            tipCents: tipCents,
            runnerMealBumpCents: bump,
            fulfillmentMode: mode,
            handoffCode: code,
            items: cart.items.map {
                OrderLineItem(
                    id: $0.id,
                    name: $0.menuItem.name,
                    quantity: $0.quantity,
                    unitPriceCents: $0.unitPriceCents,
                    specialInstructions: $0.specialInstructions.isEmpty ? nil : $0.specialInstructions
                )
            },
            runner: nil,
            placedAt: .now
        )
        orders.insert(order, at: 0)
        return order
    }

    func fetchOrder(id: String) async throws -> Order {
        guard let order = orders.first(where: { $0.id == id }) else {
            throw AppError(message: "Order not found.")
        }
        return order
    }

    func fetchOrders(forCustomerId customerId: String) async throws -> [Order] {
        try await Task.sleep(nanoseconds: 300_000_000)
        return orders.filter { $0.customerId == customerId }
    }

    func cancelOrder(id: String, customerId: String) async throws -> Order {
        guard let index = orders.firstIndex(where: { $0.id == id && $0.customerId == customerId }) else {
            throw AppError(message: "Order not found.")
        }
        guard orders[index].status == .placed else {
            throw AppError(message: "You can only cancel before a runner accepts.")
        }
        orders[index].status = .cancelled
        orders[index].cancelledAt = .now
        return orders[index]
    }

    func rateRunner(orderId: String, stars: Int, comment: String?) async throws {
        try await Task.sleep(nanoseconds: 200_000_000)
        guard let order = orders.first(where: { $0.id == orderId }) else {
            throw AppError(message: "Order not found.")
        }
        guard order.status == .delivered else {
            throw AppError(message: "You can rate after delivery.")
        }
        guard let runnerId = order.runnerId else {
            throw AppError(message: "No runner on this order.")
        }
        guard !ratings.contains(where: { $0.orderId == orderId }) else {
            throw AppError(message: "You already rated this delivery.")
        }
        let clamped = min(5, max(1, stars))
        ratings.append(
            RunnerRating(
                id: UUID().uuidString,
                orderId: orderId,
                fromUserId: order.customerId,
                toUserId: runnerId,
                stars: clamped,
                comment: comment?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                createdAt: .now
            )
        )
        let avg = averageRating(for: runnerId)
        for index in orders.indices where orders[index].runnerId == runnerId {
            if let existing = orders[index].runner {
                orders[index].runner = RunnerSnapshot(
                    id: existing.id,
                    name: existing.name,
                    rating: avg,
                    vehicleType: existing.vehicleType,
                    avatarURL: existing.avatarURL
                )
            }
        }
    }

    func fetchRatings(forRunnerId runnerId: String) async throws -> [RunnerRating] {
        try await Task.sleep(nanoseconds: 150_000_000)
        return ratings
            .filter { $0.toUserId == runnerId }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func averageRating(for runnerId: String) -> Double {
        let mine = ratings.filter { $0.toUserId == runnerId }
        guard !mine.isEmpty else { return 5.0 }
        let sum = mine.reduce(0) { $0 + $1.stars }
        return (Double(sum) / Double(mine.count) * 100).rounded() / 100
    }

    func fetchAvailableJobs(campusId: String) async throws -> [AvailableDeliveryJob] {
        try await Task.sleep(nanoseconds: 350_000_000)
        seedIfNeeded()
        return orders
            .filter { $0.status == .placed && $0.runnerId == nil }
            .map { order in
                AvailableDeliveryJob(
                    order: order,
                    pickupName: order.locationName,
                    dropoffName: order.dropoffBuildingName,
                    distanceMeters: Double.random(in: 400...1800),
                    itemCount: order.items.reduce(0) { $0 + $1.quantity },
                    payoutCents: order.runnerPayoutCents
                )
            }
    }

    func acceptJob(orderId: String, runner: RunnerSnapshot) async throws -> Order {
        try await Task.sleep(nanoseconds: 400_000_000)
        guard let index = orders.firstIndex(where: { $0.id == orderId }) else {
            throw AppError(message: "Job no longer available.")
        }
        guard orders[index].status == .placed else {
            throw AppError(message: "Someone else grabbed this one.")
        }
        orders[index].status = .accepted
        orders[index].runnerId = runner.id
        orders[index].runner = runner
        orders[index].acceptedAt = .now
        return orders[index]
    }

    func transition(orderId: String, to status: OrderStatus, runnerId: String, handoffCode: String?) async throws -> Order {
        try await Task.sleep(nanoseconds: 300_000_000)
        guard let index = orders.firstIndex(where: { $0.id == orderId }) else {
            throw AppError(message: "Order not found.")
        }
        guard orders[index].runnerId == runnerId else {
            throw AppError(message: "Not your delivery.")
        }

        let current = orders[index].status
        let allowed: [OrderStatus: OrderStatus] = [
            .accepted: .atPickup,
            .atPickup: .pickedUp,
            .pickedUp: .enRoute,
            .enRoute: .delivered,
        ]
        guard allowed[current] == status else {
            throw AppError(message: "Invalid status transition.")
        }
        if status == .delivered {
            guard let handoffCode, handoffCode == orders[index].handoffCode else {
                throw AppError(message: "Handoff code doesn't match.")
            }
        }

        orders[index].status = status
        let now = Date.now
        switch status {
        case .atPickup: orders[index].atPickupAt = now
        case .pickedUp: orders[index].pickedUpAt = now
        case .enRoute: orders[index].enRouteAt = now
        case .delivered: orders[index].deliveredAt = now
        default: break
        }
        return orders[index]
    }

    func fetchActiveRunnerOrder(runnerId: String) async throws -> Order? {
        orders.first {
            $0.runnerId == runnerId &&
            ![OrderStatus.delivered, .cancelled, .placed].contains($0.status)
        }
    }

    func fetchEarnings(runnerId: String) async throws -> EarningsSummary {
        try await Task.sleep(nanoseconds: 300_000_000)
        let delivered = orders
            .filter { $0.runnerId == runnerId && $0.status == .delivered }
            .sorted { ($0.deliveredAt ?? .distantPast) > ($1.deliveredAt ?? .distantPast) }
        let today = delivered
            .filter { ($0.deliveredAt ?? .distantPast).isToday }
            .reduce(0) { $0 + $1.runnerPayoutCents }
        let calendar = Calendar.current
        let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: .now)) ?? .now
        let weekOrders = delivered.filter { ($0.deliveredAt ?? .distantPast) >= weekStart }
        let week = weekOrders.reduce(0) { $0 + $1.runnerPayoutCents }

        // Mon…Sun bars from real deliveries this week (no fake floor).
        var dayTotals = Array(repeating: 0, count: 7)
        for order in weekOrders {
            guard let deliveredAt = order.deliveredAt else { continue }
            // Calendar: Sunday=1 … Saturday=7 → Mon-first index 0…6
            let weekday = calendar.component(.weekday, from: deliveredAt)
            let monFirst = (weekday + 5) % 7
            dayTotals[monFirst] += order.runnerPayoutCents
        }
        let labels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        let bars = labels.enumerated().map { index, label in
            DailyEarning(id: label, dayLabel: label, cents: dayTotals[index])
        }

        let linked = RunnerPayoutStore.isBankLinked
        return EarningsSummary(
            todayCents: today,
            weekCents: week,
            availableCents: week,
            dailyBars: bars,
            payoutStatus: linked
                ? "Bank linked · cash out sends tips, fees, and retail food reimbursements"
                : "Link a bank with Stripe Connect to cash out",
            bankLinked: linked,
            history: delivered
        )
    }

    private func seedIfNeeded() {
        guard !availableSeeded else { return }
        availableSeeded = true
        if orders.isEmpty {
            let sample = Order(
                id: "order-open-1",
                customerId: "other-customer",
                runnerId: nil,
                locationId: "d0000000-0000-4000-8000-000000000001",
                locationName: "Worcester",
                dropoffBuildingId: "b0000000-0000-4000-8000-000000000015",
                dropoffBuildingName: "Oak Hall",
                dropoffNote: "Lobby near the elevators",
                status: .placed,
                subtotalCents: 0,
                deliveryFeeCents: 299,
                tipCents: 300,
                runnerMealBumpCents: 250,
                fulfillmentMode: .mealSwipe,
                handoffCode: "4821",
                items: [
                    OrderLineItem(id: "li1", name: "Worcester Smash Burger", quantity: 1, unitPriceCents: 0, specialInstructions: nil),
                    OrderLineItem(id: "li2", name: "Harvest Grain Bowl", quantity: 1, unitPriceCents: 0, specialInstructions: "Extra tahini"),
                ],
                runner: nil,
                placedAt: Date().addingTimeInterval(-120)
            )
            let sample2 = Order(
                id: "order-open-2",
                customerId: "other-customer-2",
                runnerId: nil,
                locationId: "d0000000-0000-4000-8000-000000000005",
                locationName: "Blue Wall",
                dropoffBuildingId: "b0000000-0000-4000-8000-000000000013",
                dropoffBuildingName: "Cashin Hall",
                dropoffNote: "Side door",
                status: .placed,
                subtotalCents: 1248,
                deliveryFeeCents: 299,
                tipCents: 200,
                runnerMealBumpCents: 0,
                fulfillmentMode: .retailPurchase,
                handoffCode: "1190",
                items: [
                    OrderLineItem(id: "li3", name: "Personal Pepperoni Pizza", quantity: 1, unitPriceCents: 899, specialInstructions: nil),
                ],
                runner: nil,
                placedAt: Date().addingTimeInterval(-60)
            )
            orders.append(contentsOf: [sample, sample2])
        }
    }
}

actor MockChatRepository: ChatRepository {
    private var messages: [String: [OrderMessage]] = [
        "preview-order": [
            OrderMessage(
                id: "m1",
                orderId: "preview-order",
                senderId: MockCatalogData.runnerId,
                body: "Hey! Grabbing your order at Blue Wall now.",
                createdAt: .now.addingTimeInterval(-180)
            ),
            OrderMessage(
                id: "m2",
                orderId: "preview-order",
                senderId: MockCatalogData.customerId,
                body: "Awesome — lobby door by the elevators.",
                createdAt: .now.addingTimeInterval(-90)
            ),
            OrderMessage(
                id: "m3",
                orderId: "preview-order",
                senderId: MockCatalogData.runnerId,
                body: "On my way, ~4 min.",
                createdAt: .now.addingTimeInterval(-30)
            ),
        ]
    ]

    func fetchMessages(orderId: String) async throws -> [OrderMessage] {
        try await Task.sleep(nanoseconds: 120_000_000)
        return (messages[orderId] ?? []).sorted { $0.createdAt < $1.createdAt }
    }

    func sendMessage(orderId: String, senderId: String, body: String) async throws -> OrderMessage {
        try await Task.sleep(nanoseconds: 120_000_000)
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AppError(message: "Message can't be empty.") }
        let message = OrderMessage(
            id: UUID().uuidString,
            orderId: orderId,
            senderId: senderId,
            body: trimmed,
            createdAt: .now
        )
        messages[orderId, default: []].append(message)
        return message
    }
}

