import SwiftUI

/// Phase 1 showcase — every design-system component in one place.
struct ComponentGalleryView: View {
    @State private var cartSummary = CartBarSummary(itemCount: 2, totalCents: 1870)
    @State private var selectedTab: AppTab = .home
    @State private var colorSchemeOverride: ColorScheme? = nil
    @Namespace private var galleryNamespace

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: AppSpacing.xxl) {
                    header
                    section("Buttons") { buttonsSection }
                    section("Tags") { tagsSection }
                    section("Location cards") { locationCardsSection }
                    section("Menu items") { menuItemsSection }
                    section("Avatar") { avatarSection }
                    section("Status timeline") {
                        StatusTimeline(steps: GalleryMocks.timeline)
                            .padding(AppSpacing.md)
                            .background(AppCardBackground(radius: AppRadius.xl))
                    }
                    section("Slide to confirm") {
                        SlideToConfirm(title: "Slide to accept order") {
                            AppHaptics.success()
                        }
                    }
                    section("Skeletons") { skeletonsSection }
                    section("Empty states") { emptyStatesSection }
                    section("Floating tab bar") {
                        FloatingTabBar(selection: $selectedTab)
                    }
                    section("Cart bar controls") { cartControls }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, AppSpacing.screenMargin)
                .padding(.top, AppSpacing.sm)
                .padding(.bottom, 120)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle("Design System")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("System") { colorSchemeOverride = nil }
                        Button("Light") { colorSchemeOverride = .light }
                        Button("Dark") { colorSchemeOverride = .dark }
                    } label: {
                        Image(systemName: "circle.lefthalf.filled")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(AppColors.brand)
                            .frame(width: AppSpacing.minTapTarget, height: AppSpacing.minTapTarget)
                    }
                    .accessibilityLabel("Appearance")
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if cartSummary.itemCount > 0 {
                    FloatingCartBar(summary: cartSummary) {
                        AppHaptics.light()
                    }
                    .padding(.bottom, AppSpacing.xs)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(AppMotion.springGentle, value: cartSummary.itemCount)
        }
        .preferredColorScheme(colorSchemeOverride)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(DesignSystem.brandName)
                .font(AppTypography.title)
                .foregroundStyle(AppColors.brand)
                .tracking(-0.5)
                .minimumScaleFactor(0.85)
                .lineLimit(1)

            Text("Tokens, components, and motion. Tap around — nothing is wired to a backend yet.")
                .appText(.subheadline, color: AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(title)
                .appText(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var buttonsSection: some View {
        VStack(spacing: AppSpacing.sm) {
            PrimaryButton(title: "Place order", systemImage: "bag.fill") {}
            PrimaryButton(title: "Keep browsing", style: .secondary) {}
            PrimaryButton(title: "Go offline", style: .tertiary) {}
            PrimaryButton(title: "Cancel order", style: .destructive) {}
        }
    }

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            FlowLayout(spacing: AppSpacing.xs) {
                PillTag(kind: .status(.open))
                PillTag(kind: .status(.closingSoon))
                PillTag(kind: .status(.closed))
                PillTag(kind: .busy(.low))
                PillTag(kind: .busy(.medium))
                PillTag(kind: .busy(.high))
            }
            FlowLayout(spacing: AppSpacing.xs) {
                ForEach(DietaryTag.allCases) { tag in
                    PillTag(kind: .dietary(tag))
                }
                PillTag(kind: .custom(title: "22 min", systemImage: "bicycle", tint: AppColors.brand))
            }
        }
    }

    private var locationCardsSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.carouselGap) {
                LocationCard(location: GalleryMocks.worcester, namespace: galleryNamespace) {}
                    .frame(width: 240)
                LocationCard(location: GalleryMocks.franklin) {}
                    .frame(width: 240)
                LocationCard(location: GalleryMocks.closedHall) {}
                    .frame(width: 240)
            }
            .padding(.vertical, AppSpacing.xxs)
            .padding(.trailing, AppSpacing.screenMargin)
        }
        .scrollClipDisabled(false)
        .padding(.horizontal, -AppSpacing.screenMargin)
        .padding(.leading, AppSpacing.screenMargin)
    }

    private var menuItemsSection: some View {
        VStack(spacing: 0) {
            MenuItemRow(item: GalleryMocks.burger, namespace: galleryNamespace) {}
            Divider().overlay(AppColors.separator)
            MenuItemRow(item: GalleryMocks.bowl) {}
        }
        .background(AppCardBackground(radius: AppRadius.xl))
        .appCornerRadius(AppRadius.xl)
    }

    private var avatarSection: some View {
        HStack(spacing: AppSpacing.md) {
            AvatarView(name: "Maya Chen", size: .small, showsOnlineDot: true)
            AvatarView(name: "Jordan Lee", size: .medium)
            AvatarView(name: "Sam Rivera", size: .large, showsOnlineDot: true)
            Spacer(minLength: 0)
        }
    }

    private var skeletonsSection: some View {
        HStack(alignment: .top, spacing: AppSpacing.md) {
            SkeletonLocationCard()
                .frame(maxWidth: 180)
            VStack(spacing: AppSpacing.sm) {
                SkeletonMenuItemRow()
                SkeletonView(height: 48)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var emptyStatesSection: some View {
        EmptyStateView(
            systemImage: EmptyStateCopy.diningClosed.image,
            title: EmptyStateCopy.diningClosed.title,
            message: EmptyStateCopy.diningClosed.message,
            actionTitle: "Browse retail"
        ) {}
        .frame(minHeight: 280)
        .background(AppCardBackground(radius: AppRadius.xl))
        .appCornerRadius(AppRadius.xl)
    }

    private var cartControls: some View {
        HStack(spacing: AppSpacing.sm) {
            PrimaryButton(title: "Add item", style: .secondary) {
                withAnimation(AppMotion.spring) {
                    cartSummary.itemCount += 1
                    cartSummary.totalCents += 875
                }
            }
            PrimaryButton(title: "Clear", style: .tertiary) {
                withAnimation(AppMotion.springGentle) {
                    cartSummary = CartBarSummary(itemCount: 0, totalCents: 0)
                }
            }
        }
    }
}

#Preview("Gallery") {
    ComponentGalleryView()
}

#Preview("Gallery Dark") {
    ComponentGalleryView()
        .preferredColorScheme(.dark)
}
