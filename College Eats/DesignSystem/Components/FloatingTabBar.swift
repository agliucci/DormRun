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

/// Custom floating tab bar — solid capsule so labels stay readable on dark menus.
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
                .fill(barFill)
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(barStroke, lineWidth: 1)
                }
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.45 : 0.12), radius: 18, y: 8)
        }
        .padding(.horizontal, AppSpacing.screenMargin)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tab bar")
    }

    private var barFill: Color {
        colorScheme == .dark
            ? AppColors.surfaceElevated
            : Color.white.opacity(0.96)
    }

    private var barStroke: Color {
        colorScheme == .dark
            ? AppColors.border.opacity(0.9)
            : Color.black.opacity(0.06)
    }

    private func tabButton(_ tab: AppTab) -> some View {
        let selected = selection == tab
        return Button {
            AppHaptics.selection()
            withAnimation(AppMotion.spring) {
                selection = tab
            }
        } label: {
            VStack(spacing: AppSpacing.xxxs) {
                ZStack {
                    if selected {
                        Capsule(style: .continuous)
                            .fill(AppColors.brand.opacity(colorScheme == .dark ? 0.28 : 0.14))
                            .matchedGeometryEffect(id: "tab-pill", in: tabNamespace)
                    }
                    Image(systemName: tab.systemImage)
                        .font(.system(size: 18, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(selected ? AppColors.brand : AppColors.textSecondary)
                        .frame(width: AppSpacing.minTapTarget, height: 28)
                }
                .frame(height: 32)

                Text(tab.title)
                    .font(AppTypography.caption2)
                    .fontWeight(selected ? .semibold : .regular)
                    .foregroundStyle(selected ? AppColors.brand : AppColors.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
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
