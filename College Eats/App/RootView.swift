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
                HStack(spacing: AppSpacing.sm) {
                    Image("BrandMark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text(DesignSystem.brandName)
                            .font(AppTypography.title.italic())
                            .foregroundStyle(AppColors.textPrimary)
                        Text(".")
                            .font(AppTypography.title)
                            .foregroundStyle(AppColors.brand)
                    }
                }
                SkeletonView(height: 8)
                    .frame(width: 120)
            }
        }
    }

    private var mainShell: some View {
        tabContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !env.hidesFloatingTabBar {
                    FloatingTabBar(selection: $tab)
                        .padding(.bottom, AppSpacing.xxs)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(AppMotion.spring, value: env.hidesFloatingTabBar)
            .onChange(of: tab) { _, newTab in
                applyMode(for: newTab)
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
            RunnerHomeView()
        case .profile:
            ProfileView()
        }
    }

    /// Runner tab = deliver mode for chat labels etc. Staying online survives Home/Orders switches.
    private func applyMode(for tab: AppTab) {
        guard var profile = env.session.profile else { return }
        let desired: AppUserMode = (tab == .runner) ? .runner : .customer
        guard profile.mode != desired else { return }
        profile.mode = desired
        env.session.profile = profile
        Task { _ = try? await env.authRepository.updateProfile(profile) }
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
        // After login, ask once so ETAs / runner pin work before the first delivery.
        if env.session.isSignedIn, env.session.isOnboardingComplete {
            env.runnerLocation.requestPermissionIfNeeded()
        }
    }
}
