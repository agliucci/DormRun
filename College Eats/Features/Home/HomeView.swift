import SwiftUI

struct HomeView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var locations: [DiningLocation] = []
    @State private var loadState: LoadPhase = .loading
    @State private var path = NavigationPath()
    @Namespace private var namespace

    private enum LoadPhase {
        case loading, loaded, empty, failed(String)
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                switch loadState {
                case .loading:
                    loadingView
                case .failed(let message):
                    EmptyStateView(
                        systemImage: EmptyStateCopy.offline.image,
                        title: "Couldn't load campus",
                        message: message,
                        actionTitle: "Try again"
                    ) { Task { await load() } }
                case .empty:
                    EmptyStateView(
                        systemImage: EmptyStateCopy.diningClosed.image,
                        title: EmptyStateCopy.diningClosed.title,
                        message: EmptyStateCopy.diningClosed.message
                    )
                case .loaded:
                    content
                }
            }
            .background(AppColors.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    campusChip
                }
            }
            .navigationDestination(for: AppRoute.self) { route in
                switch route {
                case .location(let location):
                    LocationDetailView(location: location, namespace: namespace, path: $path)
                case .cart:
                    CartView(path: $path)
                case .checkout:
                    CheckoutView(path: $path)
                case .tracking(let orderId):
                    TrackingView(orderId: orderId)
                case .chat(let orderId):
                    ChatRouteLoader(orderId: orderId)
                case .orders:
                    OrderHistoryView()
                case .designGallery:
                    ComponentGalleryView()
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                FloatingCartBarHost(summary: env.cart.cart.itemCount > 0 ? env.cart.cart.summary : nil) {
                    path.append(AppRoute.cart)
                }
            }
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private var campusChip: some View {
        HStack(spacing: AppSpacing.xxs) {
            Image(systemName: "building.columns.fill")
                .font(.system(size: 12, weight: .semibold))
            Text(env.session.selectedCampus.name)
                .font(AppTypography.caption)
                .fontWeight(.semibold)
                .lineLimit(1)
        }
        .foregroundStyle(AppColors.brand)
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, AppSpacing.xs)
        .background(AppColors.brand.opacity(0.12))
        .clipShape(Capsule(style: .continuous))
        .accessibilityLabel("Campus \(env.session.selectedCampus.name)")
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                greeting
                openNowSection
                allLocationsSection
            }
            .padding(.horizontal, AppSpacing.screenMargin)
            .padding(.top, AppSpacing.sm)
            .padding(.bottom, AppSpacing.xxl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var greeting: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            Text("\(env.session.timeOfDayGreeting), \(env.session.greetingName)")
                .font(AppTypography.title2)
                .foregroundStyle(AppColors.textPrimary)
                .tracking(-0.4)
                .minimumScaleFactor(0.85)
                .lineLimit(2)

            Text("What are we eating on campus?")
                .appText(.subheadline, color: AppColors.textSecondary)
        }
    }

    private var openLocations: [DiningLocation] {
        locations.filter { $0.openStatus() != .closed }
    }

    /// ETA uses the student's home / selected dropoff dorm when known.
    private var dropoffBuilding: Building? {
        let id = env.cart.dropoffBuildingId ?? env.session.profile?.homeBuildingId
        return env.session.buildings.first(where: { $0.id == id })
    }

    private var openNowSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("Open now")
                .appText(.title3)

            if openLocations.isEmpty {
                Text(EmptyStateCopy.diningClosed.message)
                    .appText(.subheadline, color: AppColors.textSecondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppSpacing.carouselGap) {
                        ForEach(openLocations) { location in
                            LocationCard(location: location.asCardModel(dropoff: dropoffBuilding), namespace: namespace) {
                                path.append(AppRoute.location(location))
                            }
                            .frame(width: 240)
                        }
                    }
                    .padding(.vertical, AppSpacing.xxs)
                    .padding(.trailing, AppSpacing.screenMargin)
                }
                .padding(.horizontal, -AppSpacing.screenMargin)
                .padding(.leading, AppSpacing.screenMargin)
            }
        }
    }

    private var allLocationsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("All locations")
                .appText(.title3)

            LazyVStack(spacing: AppSpacing.md) {
                ForEach(locations) { location in
                    LocationCard(location: location.asCardModel(dropoff: dropoffBuilding)) {
                        path.append(AppRoute.location(location))
                    }
                }
            }
        }
    }

    private var loadingView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                SkeletonView(height: 36).frame(width: 220)
                SkeletonView(height: 18).frame(width: 160)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppSpacing.carouselGap) {
                        ForEach(0..<3, id: \.self) { _ in
                            SkeletonLocationCard().frame(width: 240)
                        }
                    }
                }
            }
            .padding(AppSpacing.screenMargin)
        }
    }

    private func load() async {
        if locations.isEmpty { loadState = .loading }
        do {
            let result = try await env.campusRepository.fetchDiningLocations(campusId: env.session.selectedCampus.id)
            locations = result
            loadState = result.isEmpty ? .empty : .loaded
            let buildings = try await env.campusRepository.fetchBuildings(campusId: env.session.selectedCampus.id)
            env.session.buildings = buildings
            if env.cart.dropoffBuildingId == nil {
                env.cart.dropoffBuildingId = env.session.profile?.homeBuildingId ?? buildings.first?.id
            }
        } catch {
            loadState = .failed((error as? AppError)?.message ?? error.localizedDescription)
        }
    }
}
