import SwiftUI

struct EmptyStateView: View {
    var systemImage: String
    var title: String
    var message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            ZStack {
                Circle()
                    .fill(AppColors.surfaceMuted)
                    .frame(width: 96, height: 96)
                Image(systemName: systemImage)
                    .font(.system(size: 40, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(AppColors.brand)
                    .accessibilityHidden(true)
            }

            VStack(spacing: AppSpacing.xs) {
                Text(title)
                    .appText(.title3)
                    .multilineTextAlignment(.center)

                Text(message)
                    .appText(.body, color: AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, AppSpacing.xl)

            if let actionTitle, let action {
                PrimaryButton(title: actionTitle, style: .secondary, action: action)
                    .frame(maxWidth: 240)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(AppSpacing.screenMargin)
        .accessibilityElement(children: .combine)
    }
}

enum EmptyStateCopy {
    static let diningClosed = (
        image: "moon.zzz.fill",
        title: "Kitchen's closed",
        message: "Every dining hall is closed. Go to bed."
    )

    static let emptyCart = (
        image: "bag",
        title: "Cart's looking lonely",
        message: "Add something delicious. Your future self will thank you."
    )

    static let noOrders = (
        image: "receipt",
        title: "No orders yet",
        message: "Your late-night Worcester runs will show up here."
    )

    static let noRunnerJobs = (
        image: "bicycle",
        title: "Quiet on campus",
        message: "No open deliveries right now. Stretch, hydrate, stay ready."
    )

    static let offline = (
        image: "wifi.slash",
        title: "You're offline",
        message: "Campus Wi‑Fi being campus Wi‑Fi. We'll reconnect when we can."
    )

    static let noResults = (
        image: "magnifyingglass",
        title: "Nothing matched",
        message: "Try a different search — or just get the burger."
    )
}

#Preview {
    EmptyStateView(
        systemImage: EmptyStateCopy.diningClosed.image,
        title: EmptyStateCopy.diningClosed.title,
        message: EmptyStateCopy.diningClosed.message,
        actionTitle: "Browse retail spots"
    ) {}
    .background(AppColors.background)
}
