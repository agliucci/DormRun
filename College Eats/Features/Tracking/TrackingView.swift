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
                    Text("Waiting for live runner GPS…")
                        .appText(.caption, color: AppColors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let runner = order.runner {
                    runnerCard(runner, eta: etaText(for: order))
                }
                if ![.placed, .cancelled].contains(order.status) {
                    NavigationLink {
                        OrderChatView(order: order)
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

                if order.status == .placed {
                    PrimaryButton(title: "Cancel order", style: .destructive) {
                        Task { await cancel(order) }
                    }
                }

                if order.status == .delivered {
                    PrimaryButton(title: "Rate your runner", systemImage: "star.fill") {
                        showRating = true
                    }
                }
            }
            .padding(AppSpacing.screenMargin)
            .padding(.bottom, AppSpacing.xxl)
            .frame(maxWidth: .infinity, alignment: .leading)
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
        .frame(height: 260)
        .appCornerRadius(AppRadius.xl)
        .mapStyle(.standard(elevation: .realistic))
        .allowsHitTesting(true)
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
        case .accepted, .atPickup:
            return "ETA \(DeliveryETA.formatMinutes(routeMinutes(for: order, fromRunner: false)))"
        case .pickedUp, .enRoute:
            return "ETA \(DeliveryETA.formatMinutes(routeMinutes(for: order, fromRunner: true)))"
        case .delivered:
            return "Delivered"
        case .cancelled:
            return "Cancelled"
        }
    }

    /// Distance-based campus ETA: dining→dorm before pickup, runner→dorm after.
    private func routeMinutes(for order: Order, fromRunner: Bool) -> Int {
        let dropoff = env.session.buildings.first(where: { $0.id == order.dropoffBuildingId })
        let vehicle = order.runner?.vehicleType ?? .bike

        if fromRunner, let runnerCoordinate, let dropoff {
            return DeliveryETA.remainingMinutes(from: runnerCoordinate, to: dropoff.coordinate, vehicle: vehicle)
        }

        let pickup = MockCatalogData.locations.first(where: { $0.id == order.locationId })
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
            LiveActivityManager.shared.start(
                for: orderId,
                status: loaded.status.label,
                eta: etaText(for: loaded),
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
                        cameraPosition = .region(
                            MKCoordinateRegion(
                                center: location.coordinate,
                                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                            )
                        )
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
