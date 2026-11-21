import SwiftUI

struct CartView: View {
    @Binding var path: NavigationPath
    @Environment(AppEnvironment.self) private var env

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
                        feeRow("Subtotal", env.cart.cart.subtotalCents)
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
                .safeAreaInset(edge: .bottom) {
                    PrimaryButton(title: "Checkout", systemImage: "lock.fill") {
                        path.append(AppRoute.checkout)
                    }
                    .padding(AppSpacing.screenMargin)
                    .background(.ultraThinMaterial)
                }
            }
        }
        .background(AppColors.background.ignoresSafeArea())
        .navigationTitle("Cart")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func cartRow(_ item: CartItem) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.md) {
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(item.menuItem.name).appText(.headline)
                if !item.specialInstructions.isEmpty {
                    Text(item.specialInstructions).appText(.caption, color: AppColors.textSecondary)
                }
                Text((Double(item.lineTotalCents) / 100).formatted(.currency(code: "USD")))
                    .font(AppTypography.price)
                    .monospacedDigit()
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

    private func feeRow(_ title: String, _ cents: Int) -> some View {
        HStack {
            Text(title).appText(.body, color: AppColors.textSecondary)
            Spacer()
            Text((Double(cents) / 100).formatted(.currency(code: "USD")))
                .font(AppTypography.price)
                .monospacedDigit()
        }
    }
}

struct CheckoutView: View {
    @Binding var path: NavigationPath
    @Environment(AppEnvironment.self) private var env

    @State private var isPaying = false
    @State private var errorMessage: String?
    @State private var note: String = ""

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
                labeled("Subtotal", env.cart.cart.subtotalCents)
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
                Text("Apple Pay / PaymentSheet is stubbed — tapping Place order simulates a successful Stripe test charge.")
                    .appText(.caption, color: AppColors.textTertiary)
            }

            if let errorMessage {
                Text(errorMessage).foregroundStyle(AppColors.danger)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppColors.background.ignoresSafeArea())
        .navigationTitle("Checkout")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(
                title: "Place order · Apple Pay",
                systemImage: "apple.logo",
                isLoading: isPaying,
                isEnabled: env.cart.dropoffBuildingId != nil
            ) {
                Task { await placeOrder() }
            }
            .padding(AppSpacing.screenMargin)
            .background(.ultraThinMaterial)
        }
        .onAppear {
            note = env.cart.dropoffNote
            if env.cart.dropoffBuildingId == nil {
                env.cart.dropoffBuildingId = env.session.profile?.homeBuildingId ?? env.session.buildings.first?.id
            }
        }
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

    private func labeled(_ title: String, _ cents: Int) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text((Double(cents) / 100).formatted(.currency(code: "USD")))
                .font(AppTypography.price)
                .monospacedDigit()
        }
    }

    private func placeOrder() async {
        guard let profile = env.session.profile,
              let buildingId = env.cart.dropoffBuildingId,
              let building = env.session.buildings.first(where: { $0.id == buildingId }),
              let locationId = env.cart.cart.locationId
        else {
            errorMessage = "Missing drop-off or location."
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
                return
            }

            let payment = try await env.payments.presentPaymentSheet(
                amountCents: env.cart.totalCents,
                customerEmail: profile.email
            )
            guard case .completed = payment else {
                if case .canceled = payment { return }
                if case .failed(let message) = payment { errorMessage = message }
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
                deliveryFeeCents: env.cart.deliveryFeeCents
            )
            env.cart.clear()
            AppHaptics.success()
            path.append(AppRoute.tracking(orderId: order.id))
        } catch {
            errorMessage = (error as? AppError)?.message ?? error.localizedDescription
            AppHaptics.error()
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
                                Text("\(order.status.label) · \(order.placedAt.formatted(date: .abbreviated, time: .shortened))")
                                    .appText(.caption, color: AppColors.textSecondary)
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
            .navigationTitle("Orders")
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
        // Lightweight reorder: jump home; full cart rebuild lands in a later polish.
        AppHaptics.light()
        _ = order
    }
}
