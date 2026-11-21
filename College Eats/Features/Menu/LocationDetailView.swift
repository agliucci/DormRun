import SwiftUI

struct LocationDetailView: View {
    let location: DiningLocation
    var namespace: Namespace.ID?
    @Binding var path: NavigationPath

    @Environment(AppEnvironment.self) private var env
    @State private var categories: [MenuCategory] = []
    @State private var search = ""
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedItem: MenuItem?
    @Namespace private var itemNamespace

    private var dropoffBuilding: Building? {
        let id = env.cart.dropoffBuildingId ?? env.session.profile?.homeBuildingId
        return env.session.buildings.first(where: { $0.id == id })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero
                statusRow
                    .padding(.horizontal, AppSpacing.screenMargin)
                    .padding(.top, AppSpacing.md)

                if location.openStatus() == .closed {
                    Text("This spot is closed right now — you can still browse the menu, but checkout is paused.")
                        .appText(.footnote, color: AppColors.warning)
                        .padding(AppSpacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppColors.warning.opacity(0.12))
                        .appCornerRadius(AppRadius.md)
                        .padding(.horizontal, AppSpacing.screenMargin)
                        .padding(.top, AppSpacing.sm)
                }

                searchField
                    .padding(.horizontal, AppSpacing.screenMargin)
                    .padding(.top, AppSpacing.md)

                if isLoading {
                    VStack(spacing: 0) {
                        ForEach(0..<4, id: \.self) { _ in
                            SkeletonMenuItemRow()
                        }
                    }
                    .padding(.top, AppSpacing.md)
                } else if let errorMessage {
                    EmptyStateView(
                        systemImage: EmptyStateCopy.offline.image,
                        title: "Menu didn't load",
                        message: errorMessage,
                        actionTitle: "Retry"
                    ) { Task { await loadMenu() } }
                    .frame(height: 280)
                } else if filteredCategories.isEmpty {
                    EmptyStateView(
                        systemImage: EmptyStateCopy.noResults.image,
                        title: EmptyStateCopy.noResults.title,
                        message: EmptyStateCopy.noResults.message
                    )
                    .frame(height: 260)
                } else {
                    menuList
                }
            }
            .padding(.bottom, 100)
        }
        .background(AppColors.background.ignoresSafeArea())
        .navigationTitle(location.name)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            FloatingCartBarHost(summary: env.cart.cart.itemCount > 0 ? env.cart.cart.summary : nil) {
                path.append(AppRoute.cart)
            }
        }
        .sheet(item: $selectedItem) { item in
            ItemCustomizationSheet(item: item, locationId: location.id, namespace: itemNamespace) {
                selectedItem = nil
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .task { await loadMenu() }
    }

    private var hero: some View {
        GeometryReader { geo in
            let minY = geo.frame(in: .named("detail")).minY
            let stretch = max(0, minY)

            CampusImageView(
                assetName: location.imageAssetName,
                url: location.imageURL,
                showsScrim: true
            )
                .frame(width: geo.size.width, height: 220 + stretch)
                .offset(y: -stretch)
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                        Text(location.name)
                            .font(AppTypography.title)
                            .foregroundStyle(AppColors.textOnDark)
                            .tracking(-0.4)
                        Text("\(location.type == .commons ? "Dining Commons" : "Retail") · \(location.neighborhood)")
                            .appText(.subheadline, color: AppColors.textOnDark.opacity(0.85))
                    }
                    .padding(AppSpacing.screenMargin)
                }
        }
        .frame(height: 220)
        .coordinateSpace(name: "detail")
    }

    private var statusRow: some View {
        FlowLayout(spacing: AppSpacing.xs) {
            PillTag(kind: .status(location.openStatus()))
            if location.openStatus() != .closed {
                PillTag(kind: .busy(location.busyLevel))
                PillTag(kind: .custom(
                    title: DeliveryETA.formatMinutes(location.estimatedDeliveryMinutes(to: dropoffBuilding)),
                    systemImage: "bicycle",
                    tint: AppColors.brand
                ))
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: AppSpacing.xs) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppColors.textTertiary)
            TextField("Search \(location.name)", text: $search)
                .font(AppTypography.body)
        }
        .padding(AppSpacing.md)
        .background(AppColors.surfaceMuted)
        .appCornerRadius(AppRadius.md)
    }

    private var filteredCategories: [MenuCategory] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return categories }
        return categories.compactMap { category in
            let items = category.items.filter {
                $0.name.lowercased().contains(query) || $0.description.lowercased().contains(query)
            }
            guard !items.isEmpty else { return nil }
            var copy = category
            copy.items = items
            return copy
        }
    }

    private var menuList: some View {
        LazyVStack(alignment: .leading, spacing: AppSpacing.lg, pinnedViews: [.sectionHeaders]) {
            ForEach(filteredCategories) { category in
                Section {
                    ForEach(category.items) { item in
                        MenuItemRow(item: item.asDisplayModel(), namespace: itemNamespace) {
                            selectedItem = item
                        }
                        Divider().overlay(AppColors.separator).padding(.leading, AppSpacing.md)
                    }
                } header: {
                    Text(category.name)
                        .appText(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, AppSpacing.screenMargin)
                        .padding(.vertical, AppSpacing.xs)
                        .background(AppColors.background.opacity(0.94))
                }
            }
        }
        .padding(.top, AppSpacing.md)
    }

    private func loadMenu() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            categories = try await env.campusRepository.fetchMenu(locationId: location.id)
        } catch {
            errorMessage = (error as? AppError)?.message ?? error.localizedDescription
        }
    }
}

struct ItemCustomizationSheet: View {
    let item: MenuItem
    let locationId: String
    var namespace: Namespace.ID?
    var onDismiss: () -> Void

    @Environment(AppEnvironment.self) private var env
    @State private var quantity = 1
    @State private var selectedOptions: Set<String> = []
    @State private var instructions = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    AsyncImageView(url: item.imageURL, cornerRadius: AppRadius.xl)
                        .frame(height: 180)

                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Text(item.name).appText(.title2)
                        Text(item.description).appText(.body, color: AppColors.textSecondary)
                        Text(item.formattedPrice).font(AppTypography.priceLarge).foregroundStyle(AppColors.textPrimary)
                        FlowLayout(spacing: AppSpacing.xs) {
                            ForEach(item.tags) { tag in
                                PillTag(kind: .dietary(tag), isCompact: true)
                            }
                        }
                    }

                    ForEach(item.customizations) { group in
                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                            Text(group.name + (group.isRequired ? " · Required" : ""))
                                .appText(.headline)
                            ForEach(group.options) { option in
                                optionRow(group: group, option: option)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Text("Special instructions").appText(.headline)
                        TextField("No pickles, sauce on the side…", text: $instructions, axis: .vertical)
                            .lineLimit(3...5)
                            .padding(AppSpacing.md)
                            .background(AppColors.surfaceMuted)
                            .appCornerRadius(AppRadius.md)
                    }

                    quantityStepper
                }
                .padding(AppSpacing.screenMargin)
            }
            .background(AppColors.background)
            .safeAreaInset(edge: .bottom) {
                PrimaryButton(
                    title: "Add \(lineTotal.formatted(.currency(code: "USD")))",
                    systemImage: "plus"
                ) {
                    env.cart.add(
                        item,
                        quantity: quantity,
                        options: Array(selectedOptions),
                        instructions: instructions.trimmingCharacters(in: .whitespacesAndNewlines),
                        locationId: locationId
                    )
                    onDismiss()
                }
                .padding(AppSpacing.screenMargin)
                .background(.ultraThinMaterial)
            }
            .navigationTitle("Customize")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { onDismiss() }
                }
            }
            .onAppear { seedRequiredDefaults() }
        }
    }

    private func optionRow(group: MenuCustomization, option: CustomizationOption) -> some View {
        let isOn = selectedOptions.contains(option.id)
        return Button {
            AppHaptics.selection()
            if group.allowsMultiple {
                if isOn { selectedOptions.remove(option.id) } else { selectedOptions.insert(option.id) }
            } else {
                for other in group.options { selectedOptions.remove(other.id) }
                selectedOptions.insert(option.id)
            }
        } label: {
            HStack {
                Image(systemName: isOn ? (group.allowsMultiple ? "checkmark.square.fill" : "checkmark.circle.fill") : (group.allowsMultiple ? "square" : "circle"))
                    .foregroundStyle(isOn ? AppColors.brand : AppColors.textTertiary)
                Text(option.name).appText(.body)
                Spacer()
                if option.priceCentsDelta != 0 {
                    Text("+\((Double(option.priceCentsDelta) / 100).formatted(.currency(code: "USD")))")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                        .monospacedDigit()
                }
            }
            .padding(.vertical, AppSpacing.xs)
            .frame(minHeight: AppSpacing.minTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var quantityStepper: some View {
        HStack {
            Text("Quantity").appText(.headline)
            Spacer()
            HStack(spacing: AppSpacing.md) {
                Button {
                    quantity = max(1, quantity - 1)
                    AppHaptics.light()
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(AppColors.brand)
                        .frame(width: AppSpacing.minTapTarget, height: AppSpacing.minTapTarget)
                }
                Text("\(quantity)")
                    .font(AppTypography.title3)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Button {
                    quantity += 1
                    AppHaptics.light()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(AppColors.brand)
                        .frame(width: AppSpacing.minTapTarget, height: AppSpacing.minTapTarget)
                }
            }
        }
    }

    private var lineTotal: Double {
        let extras = item.customizations.flatMap(\.options)
            .filter { selectedOptions.contains($0.id) }
            .reduce(0) { $0 + $1.priceCentsDelta }
        return Double((item.priceCents + extras) * quantity) / 100.0
    }

    private func seedRequiredDefaults() {
        for group in item.customizations where group.isRequired {
            if let first = group.options.first {
                selectedOptions.insert(first.id)
            }
        }
    }
}
