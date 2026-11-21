import SwiftUI
import CoreLocation

struct RunnerHomeView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var jobs: [AvailableDeliveryJob] = []
    @State private var activeOrder: Order?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var path = NavigationPath()
    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.xl) {
                    onlineToggle
                    earningsEntry
                    if let activeOrder {
                        activeBanner(activeOrder)
                    }
                    availableSection
                }
                .padding(AppSpacing.screenMargin)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle("Deliver")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: AppRoute.self) { route in
                if case .tracking(let id) = route {
                    RunnerActiveDeliveryView(orderId: id)
                }
            }
            .task { await refresh() }
            .refreshable { await refresh() }
            .onChange(of: env.session.isOnlineAsRunner) { _, isOnline in
                if isOnline {
                    Task { await refresh() }
                }
            }
            .onDisappear {
                // Keep publishing only while an active delivery exists.
                if activeOrder == nil {
                    env.runnerLocation.stopPublishing()
                }
            }
        }
    }

    private var onlineToggle: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text(env.session.isOnlineAsRunner ? "You're online" : "You're offline")
                .font(AppTypography.title2)
                .foregroundStyle(AppColors.textPrimary)

            Text(env.session.isOnlineAsRunner
               ? "New campus deliveries will show up below."
               : "Go online when you're ready to make some money.")
                .appText(.subheadline, color: AppColors.textSecondary)

            Button {
                withAnimation(AppMotion.spring) {
                    env.session.isOnlineAsRunner.toggle()
                }
                AppHaptics.rigid()
            } label: {
                Text(env.session.isOnlineAsRunner ? "Go Offline" : "Go Online")
                    .font(AppTypography.title3)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 64)
                    .foregroundStyle(AppColors.textOnBrand)
                    .background(env.session.isOnlineAsRunner ? AppColors.textSecondary : AppColors.brand)
                    .appCornerRadius(AppRadius.xxl)
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel(env.session.isOnlineAsRunner ? "Go offline" : "Go online")
        }
        .padding(AppSpacing.lg)
        .background(AppCardBackground(radius: AppRadius.xxl, elevated: true))
    }

    private var earningsEntry: some View {
        NavigationLink {
            EarningsView()
        } label: {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: "banknote.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(AppColors.brand)
                    .frame(width: 44, height: 44)
                    .background(AppColors.brand.opacity(0.12))
                    .appCornerRadius(AppRadius.md)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Earnings & cash out")
                        .appText(.headline)
                    Text("See tips, weekly totals, and withdraw to your bank")
                        .appText(.caption, color: AppColors.textSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.textTertiary)
            }
            .padding(AppSpacing.md)
            .background(AppCardBackground(radius: AppRadius.xl))
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel("Earnings and cash out")
    }

    private func activeBanner(_ order: Order) -> some View {
        Button {
            path.append(AppRoute.tracking(orderId: order.id))
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Active delivery").appText(.caption, color: AppColors.textOnBrand.opacity(0.85))
                    Text("\(order.locationName) → \(order.dropoffBuildingName)")
                        .font(AppTypography.headline)
                        .foregroundStyle(AppColors.textOnBrand)
                    Text(order.status.label)
                        .appText(.caption, color: AppColors.textOnBrand.opacity(0.9))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(AppColors.textOnBrand)
            }
            .padding(AppSpacing.md)
            .background(AppColors.brand)
            .appCornerRadius(AppRadius.xl)
        }
        .buttonStyle(PressableButtonStyle())
    }

    private var availableSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("Available orders").appText(.title3)

            if !env.session.isOnlineAsRunner {
                EmptyStateView(
                    systemImage: "moon.zzz",
                    title: "Offline mode",
                    message: "Flip the big button when you're ready to deliver."
                )
                .frame(height: 220)
            } else if isLoading {
                ForEach(0..<2, id: \.self) { _ in
                    SkeletonView(height: 140).appCornerRadius(AppRadius.xl)
                }
            } else if let errorMessage {
                EmptyStateView(
                    systemImage: EmptyStateCopy.offline.image,
                    title: "Couldn't load jobs",
                    message: errorMessage,
                    actionTitle: "Retry"
                ) { Task { await refresh() } }
                .frame(height: 240)
            } else if jobs.isEmpty {
                EmptyStateView(
                    systemImage: EmptyStateCopy.noRunnerJobs.image,
                    title: EmptyStateCopy.noRunnerJobs.title,
                    message: EmptyStateCopy.noRunnerJobs.message
                )
                .frame(height: 240)
            } else {
                ForEach(jobs) { job in
                    jobCard(job)
                }
            }
        }
    }

    private func jobCard(_ job: AvailableDeliveryJob) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(job.pickupName).appText(.headline)
                    Text("→ \(job.dropoffName)")
                        .appText(.subheadline, color: AppColors.textSecondary)
                }
                Spacer()
                Text(job.formattedPayout)
                    .font(AppTypography.priceLarge)
                    .foregroundStyle(AppColors.brand)
                    .monospacedDigit()
            }

            HStack(spacing: AppSpacing.md) {
                Label(job.formattedDistance, systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                Label("\(job.itemCount) items", systemImage: "bag")
            }
            .font(AppTypography.caption)
            .foregroundStyle(AppColors.textSecondary)

            SlideToConfirm(title: "Slide to accept") {
                Task { await accept(job) }
            }
        }
        .padding(AppSpacing.md)
        .background(AppCardBackground(radius: AppRadius.xl))
    }

    private func refresh() async {
        isLoading = jobs.isEmpty
        errorMessage = nil
        defer { isLoading = false }
        do {
            if let runnerId = env.session.profile?.id {
                activeOrder = try await env.orderRepository.fetchActiveRunnerOrder(runnerId: runnerId)
            }
            guard env.session.isOnlineAsRunner else {
                jobs = []
                return
            }
            jobs = try await env.orderRepository.fetchAvailableJobs(campusId: env.session.selectedCampus.id)
        } catch {
            errorMessage = (error as? AppError)?.message ?? error.localizedDescription
        }
    }

    private func accept(_ job: AvailableDeliveryJob) async {
        guard let runnerId = env.session.profile?.id else { return }
        do {
            let order = try await env.orderRepository.acceptJob(orderId: job.order.id, runnerId: runnerId)
            activeOrder = order
            jobs.removeAll { $0.id == job.id }
            env.runnerLocation.startPublishing(orderId: order.id, runnerId: runnerId)
            LiveActivityManager.shared.start(
                for: order.id,
                status: order.status.label,
                eta: "Head to \(order.locationName)",
                locationName: "\(order.locationName) → \(order.dropoffBuildingName)"
            )
            path.append(AppRoute.tracking(orderId: order.id))
        } catch {
            errorMessage = (error as? AppError)?.message ?? error.localizedDescription
            AppHaptics.error()
        }
    }
}

struct RunnerActiveDeliveryView: View {
    let orderId: String
    @Environment(AppEnvironment.self) private var env
    @State private var order: Order?
    @State private var code = ""
    @State private var errorMessage: String?
    @State private var isWorking = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                if let order {
                    Text(order.status.label).font(AppTypography.title2)
                    Text("\(order.locationName) → \(order.dropoffBuildingName)")
                        .appText(.subheadline, color: AppColors.textSecondary)
                    if !order.dropoffNote.isEmpty {
                        Text("Note: \(order.dropoffNote)")
                            .appText(.body, color: AppColors.textSecondary)
                    }

                    StatusTimeline(steps: order.timelineSteps())
                        .padding(AppSpacing.md)
                        .background(AppCardBackground(radius: AppRadius.xl))

                    NavigationLink {
                        OrderChatView(order: order)
                    } label: {
                        Label("Chat with customer", systemImage: "bubble.left.and.bubble.right.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(AppColors.brand)

                    nextAction(for: order)

                    if let errorMessage {
                        Text(errorMessage).appText(.footnote, color: AppColors.danger)
                    }
                } else {
                    SkeletonView(height: 200)
                }
            }
            .padding(AppSpacing.screenMargin)
        }
        .background(AppColors.background.ignoresSafeArea())
        .navigationTitle("Active delivery")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    @ViewBuilder
    private func nextAction(for order: Order) -> some View {
        switch order.status {
        case .accepted:
            PrimaryButton(title: "I'm at pickup", systemImage: "mappin.and.ellipse", isLoading: isWorking) {
                Task { await advance(to: .atPickup) }
            }
        case .atPickup:
            PrimaryButton(title: "Picked up", systemImage: "bag.fill", isLoading: isWorking) {
                Task { await advance(to: .pickedUp) }
            }
        case .pickedUp:
            PrimaryButton(title: "Start navigation / En route", systemImage: "location.fill", isLoading: isWorking) {
                Task { await advance(to: .enRoute) }
            }
        case .enRoute:
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Text("Enter customer's 4-digit code").appText(.headline)
                TextField("••••", text: $code)
                    .keyboardType(.numberPad)
                    .font(AppTypography.code)
                    .multilineTextAlignment(.center)
                    .padding(AppSpacing.md)
                    .background(AppColors.surfaceMuted)
                    .appCornerRadius(AppRadius.md)
                    .onChange(of: code) { _, value in
                        code = String(value.filter(\.isNumber).prefix(4))
                    }
                PrimaryButton(
                    title: "Complete delivery",
                    systemImage: "checkmark.circle.fill",
                    isLoading: isWorking,
                    isEnabled: code.count == 4
                ) {
                    Task { await advance(to: .delivered, code: code) }
                }
            }
        case .delivered:
            EmptyStateView(
                systemImage: "checkmark.seal.fill",
                title: "Delivered",
                message: "Nice work. Payout will show in Earnings."
            )
            .frame(height: 220)
        default:
            EmptyView()
        }
    }

    private func load() async {
        order = try? await env.orderRepository.fetchOrder(id: orderId)
    }

    private func advance(to status: OrderStatus, code: String? = nil) async {
        guard let runnerId = env.session.profile?.id else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            order = try await env.orderRepository.transition(
                orderId: orderId,
                to: status,
                runnerId: runnerId,
                handoffCode: code
            )
            AppHaptics.success()
            if let order {
                LiveActivityManager.shared.update(
                    status: order.status.label,
                    eta: status == .delivered ? "Delivered" : "Keep going",
                    locationName: "\(order.locationName) → \(order.dropoffBuildingName)"
                )
                PushNotificationService.shared.notifyOrderStatus(
                    orderId: order.id,
                    title: order.status.label,
                    body: "\(order.locationName) → \(order.dropoffBuildingName)"
                )
            }
            if status == .delivered {
                env.runnerLocation.stopPublishing()
                LiveActivityManager.shared.end()
            }
        } catch {
            errorMessage = (error as? AppError)?.message ?? error.localizedDescription
            AppHaptics.error()
        }
    }
}
