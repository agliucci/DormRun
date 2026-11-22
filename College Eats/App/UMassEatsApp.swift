import SwiftUI

@main
struct UMassEatsApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var environment = AppEnvironment(
        payments: StripePaymentService(
            publishableKey: SupabaseConfig.stripePublishableKey,
            merchantId: SupabaseConfig.stripeMerchantId
        )
    )

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment)
                .tint(AppColors.brand)
                .task {
                    await PushNotificationService.shared.requestAuthorizationAndRegister()
                }
                .onOpenURL { url in
                    handleStripeReturn(url)
                }
        }
    }

    private func handleStripeReturn(_ url: URL) {
        guard url.scheme == "dormrun" else { return }
        switch url.host {
        case "stripe-return":
            RunnerPayoutStore.markLinkedFromReturnURL()
            AppHaptics.success()
        case "stripe-refresh":
            break
        default:
            break
        }
    }
}
