import SwiftUI

struct RootView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var tab: AppTab = .home

    var body: some View {
        Group {
            if env.session.isBootstrapping {
                launch
            } else if !env.session.isSignedIn {
                AuthGateView()
            } else if !env.session.isOnboardingComplete {
                OnboardingView()
            } else {
                mainShell
            }
        }
        .task { await bootstrap() }
    }

    private var launch: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()
            VStack(spacing: AppSpacing.md) {
                Text(DesignSystem.brandName)
                    .font(AppTypography.title)
                    .foregroundStyle(AppColors.brand)
                SkeletonView(height: 8)
                    .frame(width: 120)
            }
        }
    }

    private var mainShell: some View {
        tabContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                FloatingTabBar(selection: $tab)
                    .padding(.bottom, AppSpacing.xxs)
            }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch tab {
        case .home:
            HomeView()
        case .orders:
            OrderHistoryView()
        case .runner:
            if env.session.profile?.mode == .runner {
                RunnerHomeView()
            } else {
                runnerUpsell
            }
        case .profile:
            ProfileView()
        }
    }

    private var runnerUpsell: some View {
        NavigationStack {
            VStack(spacing: AppSpacing.xl) {
                EmptyStateView(
                    systemImage: "bicycle",
                    title: "Switch to Runner mode",
                    message: "Toggle Customer / Runner in Profile to go online, accept orders, and track earnings.",
                    actionTitle: "Open Profile"
                ) {
                    tab = .profile
                }

                NavigationLink {
                    EarningsView()
                } label: {
                    Text("Preview earnings")
                        .font(AppTypography.headline)
                        .foregroundStyle(AppColors.brand)
                        .frame(minHeight: AppSpacing.minTapTarget)
                }
            }
            .padding(AppSpacing.screenMargin)
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle("Runner")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func bootstrap() async {
        defer { env.session.isBootstrapping = false }
        if let profile = try? await env.authRepository.currentProfile() {
            env.session.profile = profile
            env.session.isOnboardingComplete = !profile.fullName.isEmpty && !profile.phone.isEmpty
            env.cart.dropoffBuildingId = profile.homeBuildingId
        }
        if let campuses = try? await env.campusRepository.fetchCampuses(), let first = campuses.first {
            env.session.selectedCampus = first
        }
        if let buildings = try? await env.campusRepository.fetchBuildings(campusId: env.session.selectedCampus.id) {
            env.session.buildings = buildings
        }
    }
}
