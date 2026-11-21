import SwiftUI

@main
struct UMassEatsApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var environment = AppEnvironment(
        payments: StripePaymentService(publishableKey: SupabaseConfig.stripePublishableKey)
    )

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment)
                .tint(AppColors.brand)
                .task {
                    await PushNotificationService.shared.requestAuthorizationAndRegister()
                }
        }
    }
}
