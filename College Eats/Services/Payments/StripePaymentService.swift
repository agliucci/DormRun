import Foundation

/// Stripe PaymentSheet + Apple Pay + Connect Express — protocol-backed.
/// This stub keeps the app runnable without the Stripe iOS SDK.
/// When ready: add `stripe-ios` via SPM and replace the body of `presentPaymentSheet`.
struct StripePaymentService: PaymentService {
    var publishableKey: String?

    func presentPaymentSheet(amountCents: Int, customerEmail: String) async throws -> PaymentResult {
        // Test-mode stub until Stripe SDK is linked and a PaymentIntent Edge Function exists.
        _ = (publishableKey, customerEmail)
        try await Task.sleep(nanoseconds: 500_000_000)
        guard amountCents > 0 else { return .failed("Invalid amount") }
        return .completed
    }

    func createConnectOnboardingLink(runnerId: String) async throws -> URL {
        _ = runnerId
        guard let url = URL(string: "https://connect.stripe.com/express/oauth/test-stub") else {
            throw AppError(message: "Could not build Connect link.")
        }
        return url
    }

    func payoutStatus(runnerId: String) async throws -> String {
        _ = runnerId
        return "Stripe Connect Express · test mode · next payout Monday"
    }
}
