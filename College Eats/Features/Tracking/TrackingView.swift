import SwiftUI
import MapKit

struct TrackingView: View {
    let orderId: String

    @Environment(AppEnvironment.self) private var env
    @State private var order: Order?
    @State private var runnerCoordinate: CLLocationCoordinate2D?
    @State private var errorMessage: String?
    @State private var showRating = false
    @State private var showConfetti = false
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var didHideTabBar = false
    @State private var routeCoordinates: [CLLocationCoordinate2D] = []
    /// Live minutes from Apple Maps directions when GPS / route is available.
    @State private var liveRouteMinutes: Int?

    var body: some View {
        Group {
            if let order {
                content(order)
            } else if let errorMessage {
                EmptyStateView(
                    systemImage: EmptyStateCopy.offline.image,
                    title: "Can't track this order",
                    message: errorMessage,
                    actionTitle: "Retry"
                ) { Task { await load() } }
            } else {
                VStack(spacing: AppSpacing.md) {
                    SkeletonView(height: 220)
                    SkeletonView(height: 160)
                }
                .padding(AppSpacing.screenMargin)
            }
        }
        .background(AppColors.background.ignoresSafeArea())
        .navigationTitle("Tracking")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await load()
            await listen()
        }
        .sheet(isPresented: $showRating) {
            if let order {
                RateRunnerSheet(order: order)
            }
        }
        .overlay {
            if showConfetti {
                ConfettiBurstView()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
    }

    @ViewBuilder
    private func content(_ order: Order) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                statusHeader(order)
                map(order)
                if runnerCoordinate == nil, ![.delivered, .cancelled, .placed].contains(order.status) {
                    Text(env.runnerLocation.lastError
                         ?? "Waiting for live runner GPS… (runner must allow Location while delivering)")
                        .appText(.caption, color: AppColors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if runnerCoordinate != nil {
                    Text("Live runner location · route updates as they move")
                        .appText(.caption, color: AppColors.brand)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let runner = order.runner {
                    runnerCard(runner, eta: etaText(for: order))
                }
                if ![.placed, .cancelled].contains(order.status) {
                    NavigationLink {
                        OrderChatView(order: order, perspective: .asCustomer)
                    } label: {
                        Label("Chat with runner", systemImage: "bubble.left.and.bubble.right.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(AppColors.brand)
                }
                StatusTimeline(steps: order.timelineSteps())
                    .padding(AppSpacing.md)
                    .background(AppCardBackground(radius: AppRadius.xl))

                handoffCard(order)

                if order.status == .delivered {
                    PrimaryButton(title: "Rate your runner", systemImage: "star.fill") {
                        showRating = true
                    }
                }
            }
            .padding(AppSpacing.screenMargin)
            .padding(.bottom, 120)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if order.status == .placed {
                PrimaryButton(title: "Cancel order", style: .destructive) {
                    Task { await cancel(order) }
                }
                .padding(.horizontal, AppSpacing.screenMargin)
                .padding(.vertical, AppSpacing.sm)
                .background {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .overlay(alignment: .top) { Divider().opacity(0.35) }
                        .ignoresSafeArea(edges: .bottom)
                }
            }
        }
        .onAppear {
            guard !didHideTabBar else { return }
            env.setFloatingTabBarHidden(true)
            didHideTabBar = true
        }
        .onDisappear {
            guard didHideTabBar else { return }
            env.setFloatingTabBarHidden(false)
            didHideTabBar = false
        }
    }

    private func statusHeader(_ order: Order) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            Text(order.status.label)
                .font(AppTypography.title2)
                .foregroundStyle(AppColors.textPrimary)
            Text("\(order.locationName) → \(order.dropoffBuildingName)")
                .appText(.subheadline, color: AppColors.textSecondary)
            Text(etaText(for: order))
                .appText(.caption, color: AppColors.brand)
        }
    }

    private func map(_ order: Order) -> some View {
        Map(position: $cameraPosition) {
            if let pickup = MockCatalogData.locations.first(where: { $0.id == order.locationId }) {
                Marker(pickup.name, systemImage: "fork.knife", coordinate: pickup.coordinate)
                    .tint(AppColors.brand)
            }

            if let dropoff = env.session.buildings.first(where: { $0.id == order.dropoffBuildingId }) {
                Marker(dropoff.name, systemImage: "flag.fill", coordinate: dropoff.coordinate)
                    .tint(AppColors.accentWarm)
            }

            if routeCoordinates.count >= 2 {
                MapPolyline(coordinates: routeCoordinates)
                    .stroke(AppColors.brand, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            }

            if let runnerCoordinate {
                Annotation("Runner", coordinate: runnerCoordinate) {
                    ZStack {
                        Circle()
                            .fill(AppColors.brand)
                            .frame(width: 36, height: 36)
                            .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
                        Image(systemName: order.runner?.vehicleType.systemImage ?? "bicycle")
                            .foregroundStyle(AppColors.textOnBrand)
                            .font(.system(size: 14, weight: .bold))
                    }
                }
            }
        }
        .frame(height: 280)
        .appCornerRadius(AppRadius.xl)
        .mapStyle(.standard(elevation: .realistic))
        .allowsHitTesting(true)
        .onChange(of: runnerCoordinate?.latitude) { _, _ in
            Task { await refreshRoute(for: order) }
        }
        .onChange(of: order.status) { _, _ in
            Task { await refreshRoute(for: order) }
        }
        .task(id: order.id) {
            await refreshRoute(for: order)
        }
    }

    private func refreshRoute(for order: Order) async {
        let pickup = MockCatalogData.locations.first(where: { $0.id == order.locationId })?.coordinate
        let dropoff = env.session.buildings.first(where: { $0.id == order.dropoffBuildingId })?.coordinate

        let origin: CLLocationCoordinate2D?
        let destination: CLLocationCoordinate2D?
        switch order.status {
        case .accepted, .atPickup:
            origin = runnerCoordinate ?? pickup
            destination = pickup
        case .pickedUp, .enRoute:
            origin = runnerCoordinate ?? pickup
            destination = dropoff
        default:
            origin = pickup
            destination = dropoff
        }

        guard let origin, let destination else {
            routeCoordinates = []
            fitCamera(points: [pickup, dropoff, runnerCoordinate].compactMap { $0 })
            return
        }

        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        request.transportType = .walking

        do {
            let response = try await MKDirections(request: request).calculate()
            if let route = response.routes.first {
                routeCoordinates = route.polyline.coordinates
                // Live Maps travel time from current GPS → next stop.
                let minutes = max(1, Int(ceil(route.expectedTravelTime / 60)))
                liveRouteMinutes = minutes
                LiveActivityManager.shared.update(
                    status: order.status.label,
                    eta: DeliveryETA.formatMinutes(minutes),
                    locationName: "\(order.locationName) → \(order.dropoffBuildingName)"
                )
            } else {
                routeCoordinates = [origin, destination]
                liveRouteMinutes = DeliveryETA.remainingMinutes(from: origin, to: destination)
            }
        } catch {
            routeCoordinates = [origin, destination]
            liveRouteMinutes = DeliveryETA.remainingMinutes(from: origin, to: destination)
        }

        fitCamera(points: [origin, destination, runnerCoordinate, pickup, dropoff].compactMap { $0 })
    }

    private func fitCamera(points: [CLLocationCoordinate2D]) {
        guard !points.isEmpty else { return }
        var rect = MKMapRect.null
        for point in points {
            let mapPoint = MKMapPoint(point)
            rect = rect.union(MKMapRect(x: mapPoint.x, y: mapPoint.y, width: 1, height: 1))
        }
        let region = MKCoordinateRegion(rect.insetBy(dx: -rect.size.width * 0.35, dy: -rect.size.height * 0.35))
        withAnimation(AppMotion.pinGlide) {
            cameraPosition = .region(region)
        }
    }

    private func runnerCard(_ runner: RunnerSnapshot, eta: String) -> some View {
        HStack(spacing: AppSpacing.md) {
            AvatarView(name: runner.name, imageURL: runner.avatarURL, size: .large, showsOnlineDot: true)
            VStack(alignment: .leading, spacing: AppSpacing.xxxs) {
                Text(runner.name).appText(.headline)
                HStack(spacing: AppSpacing.xs) {
                    Label(String(format: "%.2f", runner.rating), systemImage: "star.fill")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.accentWarm)
                    Text(runner.vehicleType.label)
                        .appText(.caption, color: AppColors.textSecondary)
                }
                Text(eta).appText(.caption, color: AppColors.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(AppSpacing.md)
        .background(AppCardBackground(radius: AppRadius.xl))
    }

    private func handoffCard(_ order: Order) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text("Handoff code").appText(.caption, color: AppColors.textSecondary)
            Text(order.handoffCode)
                .font(AppTypography.code)
                .tracking(4)
                .foregroundStyle(AppColors.textPrimary)
                .monospacedDigit()
            Text("Show this to your runner when they arrive.")
                .appText(.footnote, color: AppColors.textSecondary)
            if !order.dropoffNote.isEmpty {
                Text("Note: \(order.dropoffNote)")
                    .appText(.caption, color: AppColors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.md)
        .background(AppColors.surfaceMuted)
        .appCornerRadius(AppRadius.xl)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Handoff code \(order.handoffCode.spacedDigits)")
    }

    private func etaText(for order: Order) -> String {
        switch order.status {
        case .placed:
            return "Finding a runner…"
        case .accepted, .atPickup, .pickedUp, .enRoute:
            if let liveRouteMinutes {
                return "ETA \(DeliveryETA.formatMinutes(liveRouteMinutes))"
            }
            return "ETA \(DeliveryETA.formatMinutes(routeMinutes(for: order)))"
        case .delivered:
            return "Delivered"
        case .cancelled:
            return "Cancelled"
        }
    }

    /// Fallback when Maps directions aren’t ready yet — uses live GPS when available.
    private func routeMinutes(for order: Order) -> Int {
        let dropoff = env.session.buildings.first(where: { $0.id == order.dropoffBuildingId })
        let vehicle = order.runner?.vehicleType ?? .bike
        let pickup = MockCatalogData.locations.first(where: { $0.id == order.locationId })

        switch order.status {
        case .accepted, .atPickup:
            if let runnerCoordinate, let pickup {
                return DeliveryETA.remainingMinutes(from: runnerCoordinate, to: pickup.coordinate, vehicle: vehicle)
            }
        case .pickedUp, .enRoute:
            if let runnerCoordinate, let dropoff {
                return DeliveryETA.remainingMinutes(from: runnerCoordinate, to: dropoff.coordinate, vehicle: vehicle)
            }
        default:
            break
        }

        if let pickup {
            return DeliveryETA.estimateMinutes(
                from: pickup.coordinate,
                to: dropoff?.coordinate,
                busy: pickup.busyLevel,
                vehicle: vehicle
            )
        }
        return 8
    }

    private func load() async {
        do {
            let loaded = try await env.orderRepository.fetchOrder(id: orderId)
            order = loaded
            // Reuses the same Live Activity if checkout already started one.
            LiveActivityManager.shared.start(
                for: orderId,
                status: loaded.status.label,
                eta: etaText(for: loaded).replacingOccurrences(of: "ETA ", with: ""),
                locationName: "\(loaded.locationName) → \(loaded.dropoffBuildingName)"
            )
        } catch {
            errorMessage = (error as? AppError)?.message ?? error.localizedDescription
        }
    }

    private func listen() async {
        let orderStream = env.realtime.subscribeOrderUpdates(orderId: orderId)
        let locationStream = env.realtime.subscribeRunnerLocation(orderId: orderId)

        await withTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor in
                for await update in orderStream {
                    withAnimation(AppMotion.spring) {
                        order = update
                    }
                    LiveActivityManager.shared.update(status: update.status.label, eta: etaText(for: update))
                    if update.status == .delivered {
                        showConfetti = true
                        AppHaptics.success()
                        LiveActivityManager.shared.end()
                        try? await Task.sleep(nanoseconds: 2_500_000_000)
                        showConfetti = false
                        showRating = true
                    }
                }
            }
            group.addTask { @MainActor in
                for await location in locationStream {
                    withAnimation(AppMotion.pinGlide) {
                        runnerCoordinate = location.coordinate
                    }
                    if let order {
                        await refreshRoute(for: order)
                    }
                }
            }
        }
    }

    private func cancel(_ order: Order) async {
        guard let customerId = env.session.profile?.id else { return }
        do {
            self.order = try await env.orderRepository.cancelOrder(id: order.id, customerId: customerId)
            LiveActivityManager.shared.end()
            AppHaptics.warning()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private extension MKPolyline {
    var coordinates: [CLLocationCoordinate2D] {
        var coords = Array(repeating: kCLLocationCoordinate2DInvalid, count: pointCount)
        getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))
        return coords
    }
}

struct RateRunnerSheet: View {
    let order: Order
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var stars = 5
    @State private var comment = ""
    @State private var errorMessage: String?
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            VStack(spacing: AppSpacing.xl) {
                Text("How was \(order.runner?.name ?? "your runner")?")
                    .appText(.title3)
                Text("Ratings help the campus community pick reliable runners.")
                    .appText(.footnote, color: AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                HStack(spacing: AppSpacing.sm) {
                    ForEach(1...5, id: \.self) { value in
                        Button {
                            stars = value
                            AppHaptics.selection()
                        } label: {
                            Image(systemName: value <= stars ? "star.fill" : "star")
                                .font(.system(size: 32))
                                .foregroundStyle(AppColors.accentWarm)
                                .frame(width: AppSpacing.minTapTarget, height: AppSpacing.minTapTarget)
                        }
                        .accessibilityLabel("\(value) stars")
                    }
                }
                TextField("Leave a short review (optional)", text: $comment, axis: .vertical)
                    .lineLimit(3...5)
                    .padding(AppSpacing.md)
                    .background(AppColors.surfaceMuted)
                    .appCornerRadius(AppRadius.md)
                if let errorMessage {
                    Text(errorMessage).appText(.footnote, color: AppColors.danger)
                }
                PrimaryButton(title: isSubmitting ? "Submitting…" : "Submit rating") {
                    Task { await submit() }
                }
                .disabled(isSubmitting)
                Spacer()
            }
            .padding(AppSpacing.screenMargin)
            .background(AppColors.background)
            .navigationTitle("Rate runner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func submit() async {
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await env.orderRepository.rateRunner(
                orderId: order.id,
                stars: stars,
                comment: comment
            )
            // Refresh averaged runner rating on the signed-in profile when relevant.
            if var profile = env.session.profile,
               let runnerId = order.runnerId,
               profile.id == runnerId {
                let reviews = (try? await env.orderRepository.fetchRatings(forRunnerId: runnerId)) ?? []
                if !reviews.isEmpty {
                    let sum = reviews.reduce(0) { $0 + $1.stars }
                    profile.rating = (Double(sum) / Double(reviews.count) * 100).rounded() / 100
                    env.session.profile = profile
                    _ = try? await env.authRepository.updateProfile(profile)
                }
            }
            AppHaptics.success()
            dismiss()
        } catch {
            errorMessage = (error as? AppError)?.message ?? error.localizedDescription
            AppHaptics.error()
        }
    }
}

/// Loads an order then presents chat (used from deep navigation routes).
struct ChatRouteLoader: View {
    let orderId: String
    @Environment(AppEnvironment.self) private var env
    @State private var order: Order?

    var body: some View {
        Group {
            if let order {
                OrderChatView(order: order)
            } else {
                ProgressView().tint(AppColors.brand)
            }
        }
        .task {
            order = try? await env.orderRepository.fetchOrder(id: orderId)
        }
    }
}

struct ConfettiBurstView: View {
    @State private var particles: [ConfettiParticle] = (0..<28).map { _ in ConfettiParticle() }

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                for particle in particles {
                    var copy = particle
                    copy.advance(time: t, in: size)
                    let rect = CGRect(x: copy.x, y: copy.y, width: 7, height: 10)
                    context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(copy.color))
                }
            }
        }
        .ignoresSafeArea()
    }
}

private struct ConfettiParticle {
    var seed = Double.random(in: 0...1)
    var x: CGFloat = 0
    var y: CGFloat = 0
    var color: Color = [AppColors.brand, AppColors.accentWarm, AppColors.success, AppColors.info].randomElement() ?? AppColors.brand

    mutating func advance(time: TimeInterval, in size: CGSize) {
        let phase = time + seed * 10
        x = size.width * CGFloat((sin(phase * 1.7 + seed) + 1) / 2)
        y = size.height * 0.15 + CGFloat(phase.truncatingRemainder(dividingBy: 2.4) / 2.4) * size.height * 0.7
    }
}

private extension String {
    var spacedDigits: String {
        map(String.init).joined(separator: " ")
    }
}
