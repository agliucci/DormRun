import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case home
    case orders
    case runner
    case profile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .orders: "Orders"
        case .runner: "Deliver"
        case .profile: "Profile"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house.fill"
        case .orders: "receipt"
        case .runner: "bicycle"
        case .profile: "person.crop.circle"
        }
    }
}

/// Custom floating tab bar — white / liquid-glass capsule (not pink-tinted material).
struct FloatingTabBar: View {
    @Binding var selection: AppTab
    @Environment(\.colorScheme) private var colorScheme
    @Namespace private var tabNamespace

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                tabButton(tab)
            }
        }
        .padding(.horizontal, AppSpacing.xs)
        .padding(.vertical, AppSpacing.xxs)
        .background {
            Capsule(style: .continuous)
                .fill(Color.white.opacity(colorScheme == .dark ? 0.14 : 0.92))
                .background {
                    Capsule(style: .continuous)
                        .fill(.ultraThinMaterial)
                }
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(
                            Color.white.opacity(colorScheme == .dark ? 0.22 : 0.95),
                            lineWidth: 0.5
                        )
                }
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.08), radius: 16, y: 6)
                .clipShape(Capsule(style: .continuous))
        }
        .padding(.horizontal, AppSpacing.screenMargin)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tab bar")
    }

    private func tabButton(_ tab: AppTab) -> some View {
        Button {
            AppHaptics.selection()
            withAnimation(AppMotion.spring) {
                selection = tab
            }
        } label: {
            VStack(spacing: AppSpacing.xxxs) {
                ZStack {
                    if selection == tab {
                        Capsule(style: .continuous)
                            .fill(AppColors.brand.opacity(0.12))
                            .matchedGeometryEffect(id: "tab-pill", in: tabNamespace)
                    }
                    Image(systemName: tab.systemImage)
                        .font(.system(size: 18, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(selection == tab ? AppColors.brand : AppColors.textTertiary)
                        .frame(width: AppSpacing.minTapTarget, height: 28)
                }
                .frame(height: 32)

                Text(tab.title)
                    .font(AppTypography.caption2)
                    .foregroundStyle(selection == tab ? AppColors.brand : AppColors.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(selection == tab ? [.isSelected, .isButton] : .isButton)
    }
}

#Preview {
    struct Host: View {
        @State private var tab: AppTab = .orders
        var body: some View {
            ZStack(alignment: .bottom) {
                AppColors.background.ignoresSafeArea()
                LinearGradient(colors: [AppColors.brand.opacity(0.35), AppColors.background], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                FloatingTabBar(selection: $tab)
                    .padding(.bottom, AppSpacing.sm)
            }
        }
    }
    return Host()
}
