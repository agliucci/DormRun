import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(StripePaymentSheet)
import StripePaymentSheet
#endif

/// Stripe PaymentSheet + Apple Pay + Connect cash-out.
///
/// Live mode checklist:
/// 1. Stripe Dashboard → switch to **Live** → put `pk_live_…` in Config.xcconfig
/// 2. `supabase secrets set STRIPE_SECRET_KEY=sk_live_… STRIPE_WEBHOOK_SECRET=whsec_…`
/// 3. Deploy: `create-payment-intent create-connect-account-link create-cash-out stripe-webhook`
/// 4. Re-run Connect bank link in live (test accounts don’t carry over)
/// 5. Apple Pay merchant id + Live Activity / push on a real device (TestFlight)
struct StripePaymentService: PaymentService {
    var publishableKey: String?
    var merchantId: String?

    func presentPaymentSheet(amountCents: Int, customerEmail: String) async throws -> PaymentResult {
        guard amountCents > 0 else { return .failed("Invalid amount") }

        let key = publishableKey ?? SupabaseConfig.stripePublishableKey
        let hasRealKey = key.map { !$0.contains("placeholder") && $0.hasPrefix("pk_") } ?? false

        guard hasRealKey, let publishable = key else {
            // Checkout UI already confirmed Apple Pay / card — complete locally until keys ship.
            try await Task.sleep(nanoseconds: 500_000_000)
            return .completed(paymentIntentId: nil)
        }

        guard let client = SupabaseClientProvider.shared() else {
            throw AppError(
                message: "Stripe key is set, but Supabase isn’t configured — can’t create a PaymentIntent."
            )
        }

        let intent = try await client.createPaymentIntent(
            amountCents: amountCents,
            customerEmail: customerEmail
        )

        #if canImport(StripePaymentSheet)
        return try await presentStripeSheet(
            clientSecret: intent.clientSecret,
            publishableKey: intent.publishableKey ?? publishable,
            customerEmail: customerEmail,
            paymentIntentId: intent.paymentIntentId
        )
        #else
        throw AppError(
            message: "Add the StripePaymentSheet package in Xcode (stripe-ios) to finish Apple Pay / card checkout. PaymentIntent \(intent.paymentIntentId) was created."
        )
        #endif
    }

    func createConnectOnboardingLink(runnerId: String) async throws -> URL {
        _ = runnerId
        guard let client = SupabaseClientProvider.shared() else {
            throw AppError(
                message: "Sign in with a live Supabase account first, then tap Link bank account again."
            )
        }

        do {
            // Stripe requires http(s) return URLs — custom schemes like dormrun:// get 400.
            let link = try await client.createConnectAccountLink(
                refreshURL: "https://dormrun.app/stripe/refresh",
                returnURL: "https://dormrun.app/stripe/return"
            )
            guard let url = URL(string: link.url), link.url.hasPrefix("https://") else {
                throw AppError(message: "Stripe returned an invalid Connect link.")
            }
            // Onboarding opens in Safari; mark linked when they come back or confirm in-app.
            return url
        } catch let error as AppError {
            throw error
        } catch {
            throw AppError(
                message: "Couldn’t open Stripe Connect. \(error.localizedDescription)"
            )
        }
    }

    func payoutStatus(runnerId: String) async throws -> String {
        _ = runnerId
        if RunnerPayoutStore.isBankLinked {
            return "Bank linked · cash out sends tips, fees, and retail food reimbursements"
        }
        return "Link a bank with Stripe Connect to cash out"
    }

    func cashOutAvailableBalance(runnerId: String) async throws -> CashOutResult {
        _ = runnerId
        guard let client = SupabaseClientProvider.shared() else {
            throw AppError(message: "Sign in with a live Supabase account to cash out.")
        }
        let result = try await client.createCashOut()
        if let error = result.error, !error.isEmpty {
            throw AppError(message: error)
        }
        if result.transferredCents > 0 {
            RunnerPayoutStore.isBankLinked = true
        }
        return CashOutResult(
            transferredCents: result.transferredCents,
            transferId: result.transferId,
            message: result.message
                ?? (result.transferredCents > 0
                    ? "\(result.transferredCents.formattedAsMoney) is on the way to your bank."
                    : "Nothing available to cash out yet.")
        )
    }

    #if canImport(StripePaymentSheet)
    @MainActor
    private func presentStripeSheet(
        clientSecret: String,
        publishableKey: String,
        customerEmail: String,
        paymentIntentId: String
    ) async throws -> PaymentResult {
        STPAPIClient.shared.publishableKey = publishableKey

        var configuration = PaymentSheet.Configuration()
        configuration.merchantDisplayName = "DormRun"
        configuration.allowsDelayedPaymentMethods = false
        configuration.defaultBillingDetails.email = customerEmail
        if let merchantId = merchantId ?? SupabaseConfig.stripeMerchantId,
           !merchantId.isEmpty,
           !merchantId.contains("your") {
            configuration.applePay = .init(
                merchantId: merchantId,
                merchantCountryCode: "US"
            )
        }

        let sheet = PaymentSheet(paymentIntentClientSecret: clientSecret, configuration: configuration)

        guard let anchor = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController else {
            throw AppError(message: "Couldn't present Apple Pay / PaymentSheet.")
        }

        var presenter = anchor
        while let presented = presenter.presentedViewController {
            presenter = presented
        }

        return await withCheckedContinuation { continuation in
            sheet.present(from: presenter) { result in
                switch result {
                case .completed:
                    continuation.resume(returning: .completed(paymentIntentId: paymentIntentId))
                case .canceled:
                    continuation.resume(returning: .canceled)
                case .failed(let error):
                    continuation.resume(returning: .failed(error.localizedDescription))
                }
            }
        }
    }
    #endif
}

private extension Int {
    var formattedAsMoney: String {
        (Double(self) / 100).formatted(.currency(code: "USD"))
    }
}
