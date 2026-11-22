import SwiftUI

struct CartView: View {
    @Binding var path: NavigationPath
    @Environment(AppEnvironment.self) private var env
    @State private var didHideTabBar = false

    var body: some View {
        Group {
            if env.cart.cart.items.isEmpty {
                EmptyStateView(
                    systemImage: EmptyStateCopy.emptyCart.image,
                    title: EmptyStateCopy.emptyCart.title,
                    message: EmptyStateCopy.emptyCart.message,
                    actionTitle: "Browse dining"
                ) { path = NavigationPath() }
            } else {
                List {
                    Section {
                        Text(env.cart.pricingExplanation)
                            .appText(.footnote, color: AppColors.textSecondary)
                    }

                    ForEach(env.cart.cart.items) { item in
                        cartRow(item)
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            let id = env.cart.cart.items[index].id
                            env.cart.updateQuantity(itemId: id, quantity: 0)
                        }
                    }

                    Section {
                        if env.cart.fulfillmentMode == .mealSwipe {
                            feeRow("Food (runner swipe)", 0, subtitle: "Not charged to you")
                            feeRow("Runner bump", env.cart.appliedBumpCents)
                        } else {
                            feeRow("Food", env.cart.menuSubtotalCents)
                        }
                        feeRow("Delivery", env.cart.deliveryFeeCents)
                        feeRow("Tip", env.cart.tipCents)
                        HStack {
                            Text("Total").appText(.headline)
                            Spacer()
                            Text((Double(env.cart.totalCents) / 100).formatted(.currency(code: "USD")))
                                .font(AppTypography.priceLarge)
                                .monospacedDigit()
                                .contentTransition(.numericText())
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    PrimaryButton(title: "Checkout", systemImage: "arrow.right.circle.fill") {
                        path.append(AppRoute.checkout)
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
        }
        .background(AppColors.background.ignoresSafeArea())
        .navigationTitle("Cart")
        .navigationBarTitleDisplayMode(.inline)
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

    private func cartRow(_ item: CartItem) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.md) {
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(item.menuItem.name).appText(.headline)
                if !item.specialInstructions.isEmpty {
                    Text(item.specialInstructions).appText(.caption, color: AppColors.textSecondary)
                }
                if env.cart.fulfillmentMode == .mealSwipe {
                    Text("Via runner swipe")
                        .appText(.caption, color: AppColors.textSecondary)
                } else {
                    Text((Double(item.lineTotalCents) / 100).formatted(.currency(code: "USD")))
                        .font(AppTypography.price)
                        .monospacedDigit()
                }
            }
            Spacer()
            Stepper(
                value: Binding(
                    get: { item.quantity },
                    set: { env.cart.updateQuantity(itemId: item.id, quantity: $0) }
                ),
                in: 0...20
            ) {
                Text("\(item.quantity)")
                    .font(AppTypography.headline)
                    .monospacedDigit()
                    .frame(minWidth: 24)
            }
            .labelsHidden()
            .accessibilityLabel("Quantity \(item.quantity)")
        }
        .padding(.vertical, AppSpacing.xxs)
    }

    private func feeRow(_ title: String, _ cents: Int, subtitle: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).appText(.body, color: AppColors.textSecondary)
                if let subtitle {
                    Text(subtitle).appText(.caption, color: AppColors.textTertiary)
                }
            }
            Spacer()
            Text(cents == 0 && env.cart.fulfillmentMode == .mealSwipe && title.contains("Food")
                 ? "Swipe"
                 : (Double(cents) / 100).formatted(.currency(code: "USD")))
                .font(AppTypography.price)
                .monospacedDigit()
        }
    }
}

struct CheckoutView: View {
    @Binding var path: NavigationPath
    @Environment(AppEnvironment.self) private var env

    @State private var isPaying = false
    @State private var showPaymentSheet = false
    @State private var errorMessage: String?
    @State private var note: String = ""
    @State private var didHideTabBar = false

    var body: some View {
        Form {
            Section("Drop-off") {
                Picker("Building", selection: Binding(
                    get: { env.cart.dropoffBuildingId ?? "" },
                    set: { env.cart.dropoffBuildingId = $0 }
                )) {
                    ForEach(env.session.buildings) { building in
                        Text("\(building.name) · \(building.neighborhood)").tag(building.id)
                    }
                }
                TextField("Note (lobby of JQA, side door…)", text: $note, axis: .vertical)
                    .lineLimit(2...4)
            }

            Section("How this order works") {
                Text(env.cart.pricingExplanation)
                    .appText(.footnote, color: AppColors.textSecondary)
            }

            Section("Runner tip") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppSpacing.xs) {
                        ForEach(env.cart.tipPresets, id: \.self) { tip in
                            tipChip(tip)
                        }
                    }
                }
            }

            Section("Summary") {
                if env.cart.fulfillmentMode == .mealSwipe {
                    labeled("Food (runner swipe)", 0, alt: "Swipe")
                    labeled("Runner bump", env.cart.appliedBumpCents)
                } else {
                    labeled("Food", env.cart.menuSubtotalCents)
                }
                labeled("Delivery fee", env.cart.deliveryFeeCents)
                labeled("Tip", env.cart.tipCents)
                HStack {
                    Text("Total").appText(.headline)
                    Spacer()
                    Text((Double(env.cart.totalCents) / 100).formatted(.currency(code: "USD")))
                        .font(AppTypography.priceLarge)
                        .monospacedDigit()
                }
            }

            Section {
                Text(paymentFooterCopy)
                    .appText(.footnote, color: AppColors.textSecondary)
            }

            if let errorMessage {
                Text(errorMessage).foregroundStyle(AppColors.danger)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppColors.background.ignoresSafeArea())
        .navigationTitle("Checkout")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            PrimaryButton(
                title: "Pay · \((Double(env.cart.totalCents) / 100).formatted(.currency(code: "USD")))",
                systemImage: "apple.logo",
                isLoading: isPaying,
                isEnabled: env.cart.dropoffBuildingId != nil
            ) {
                errorMessage = nil
                showPaymentSheet = true
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
        .sheet(isPresented: $showPaymentSheet) {
            CheckoutPaymentSheet(
                amountCents: env.cart.totalCents,
                explanation: env.cart.pricingExplanation,
                isProcessing: isPaying,
                onPayWithApplePay: { Task { await placeOrder(preferApplePay: true) } },
                onPayWithCard: { Task { await placeOrder(preferApplePay: false) } },
                onCancel: { showPaymentSheet = false }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .onAppear {
            note = env.cart.dropoffNote
            if env.cart.dropoffBuildingId == nil {
                env.cart.dropoffBuildingId = env.session.profile?.homeBuildingId ?? env.session.buildings.first?.id
            }
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

    private var paymentFooterCopy: String {
        if SupabaseConfig.stripePublishableKey != nil {
            return "Apple Pay / card via Stripe. You’ll confirm on the next screen."
        }
        return "Payment sheet opens next — Apple Pay or card. Add your Stripe pk_test key in Config.xcconfig for live charges."
    }

    private func tipChip(_ tip: Int) -> some View {
        let selected = env.cart.tipCents == tip
        return Button {
            AppHaptics.selection()
            env.cart.tipCents = tip
        } label: {
            Text(tip == 0 ? "No tip" : (Double(tip) / 100).formatted(.currency(code: "USD")))
                .font(AppTypography.subheadline.weight(.semibold))
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, AppSpacing.sm)
                .frame(minHeight: AppSpacing.minTapTarget)
                .foregroundStyle(selected ? AppColors.textOnBrand : AppColors.textPrimary)
                .background(selected ? AppColors.brand : AppColors.surfaceMuted)
                .clipShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func labeled(_ title: String, _ cents: Int, alt: String? = nil) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(alt ?? (Double(cents) / 100).formatted(.currency(code: "USD")))
                .font(AppTypography.price)
                .monospacedDigit()
        }
    }

    private func placeOrder(preferApplePay: Bool) async {
        guard let profile = env.session.profile,
              let buildingId = env.cart.dropoffBuildingId,
              let building = env.session.buildings.first(where: { $0.id == buildingId }),
              let locationId = env.cart.cart.locationId
        else {
            errorMessage = "Missing drop-off or location."
            showPaymentSheet = false
            return
        }

        isPaying = true
        errorMessage = nil
        defer { isPaying = false }

        do {
            let locations = try await env.campusRepository.fetchDiningLocations(campusId: env.session.selectedCampus.id)
            guard let location = locations.first(where: { $0.id == locationId })
                    ?? MockCatalogData.locations.first(where: { $0.id == locationId }) else {
                errorMessage = "Couldn't find that dining location."
                showPaymentSheet = false
                return
            }

            let payment = try await env.payments.presentPaymentSheet(
                amountCents: env.cart.totalCents,
                customerEmail: profile.email
            )
            let paymentIntentId: String?
            switch payment {
            case .completed(let id):
                paymentIntentId = id
            case .canceled:
                return
            case .failed(let message):
                errorMessage = message
                showPaymentSheet = false
                return
            }

            env.cart.dropoffNote = note
            let order = try await env.orderRepository.placeOrder(
                customerId: profile.id,
                location: location,
                dropoff: building,
                dropoffNote: note,
                cart: env.cart.cart,
                tipCents: env.cart.tipCents,
                deliveryFeeCents: env.cart.deliveryFeeCents,
                runnerMealBumpCents: env.cart.appliedBumpCents,
                paymentIntentId: paymentIntentId
            )
            env.cart.clear()
            showPaymentSheet = false
            AppHaptics.success()
            LiveActivityManager.shared.start(
                for: order.id,
                status: order.status.label,
                eta: "Finding a runner…",
                locationName: "\(order.locationName) → \(order.dropoffBuildingName)"
            )
            // Reset stack so Back from tracking goes Home (not Checkout → Cart → …).
            path = NavigationPath()
            path.append(AppRoute.tracking(orderId: order.id))
            _ = preferApplePay
        } catch {
            errorMessage = (error as? AppError)?.message ?? error.localizedDescription
            showPaymentSheet = false
            AppHaptics.error()
        }
    }
}

/// Always-visible pay step so checkout never silently auto-completes.
struct CheckoutPaymentSheet: View {
    let amountCents: Int
    let explanation: String
    let isProcessing: Bool
    let onPayWithApplePay: () -> Void
    let onPayWithCard: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                Text((Double(amountCents) / 100).formatted(.currency(code: "USD")))
                    .font(AppTypography.display)
                    .monospacedDigit()

                Text(explanation)
                    .appText(.subheadline, color: AppColors.textSecondary)

                PrimaryButton(
                    title: "Apple Pay",
                    systemImage: "apple.logo",
                    isLoading: isProcessing
                ) {
                    onPayWithApplePay()
                }

                PrimaryButton(
                    title: "Pay with card",
                    systemImage: "creditcard.fill",
                    style: .secondary,
                    isLoading: isProcessing
                ) {
                    onPayWithCard()
                }

                Spacer(minLength: 0)
            }
            .padding(AppSpacing.screenMargin)
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle("Pay")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                        .disabled(isProcessing)
                }
            }
        }
    }
}

struct OrderHistoryView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var orders: [Order] = []
    @State private var isLoading = true
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if isLoading {
                    ProgressView().tint(AppColors.brand)
                } else if orders.isEmpty {
                    EmptyStateView(
                        systemImage: EmptyStateCopy.noOrders.image,
                        title: EmptyStateCopy.noOrders.title,
                        message: EmptyStateCopy.noOrders.message
                    )
                } else {
                    List(orders) { order in
                        Button {
                            path.append(AppRoute.tracking(orderId: order.id))
                        } label: {
                            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                                HStack {
                                    Text(order.locationName).appText(.headline)
                                    Spacer()
                                    Text(order.formattedTotal).font(AppTypography.price).monospacedDigit()
                                }
                                Text("\(order.status.label) · \(order.fulfillmentMode.title)")
                                    .appText(.caption, color: AppColors.textSecondary)
                                Text(order.placedAt.formatted(date: .abbreviated, time: .shortened))
                                    .appText(.caption, color: AppColors.textTertiary)
                            }
                        }
                        .swipeActions {
                            Button("Reorder") {
                                reorder(order)
                            }
                            .tint(AppColors.brand)
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle("Your orders")
            .navigationDestination(for: AppRoute.self) { route in
                if case .tracking(let id) = route {
                    TrackingView(orderId: id)
                }
            }
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private func load() async {
        guard let customerId = env.session.profile?.id else { return }
        isLoading = orders.isEmpty
        defer { isLoading = false }
        orders = (try? await env.orderRepository.fetchOrders(forCustomerId: customerId)) ?? []
    }

    private func reorder(_ order: Order) {
        AppHaptics.light()
        _ = order
    }
}
