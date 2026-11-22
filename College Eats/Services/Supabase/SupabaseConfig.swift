import Foundation

/// Reads secrets from Info.plist keys injected via Config.xcconfig.
/// Never hardcode keys in source.
enum SupabaseConfig {
    static var url: URL? {
        guard let string = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
              !string.isEmpty,
              !string.contains("YOUR_PROJECT"),
              let url = URL(string: string) else { return nil }
        return url
    }

    static var anonKey: String? {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String,
              !key.isEmpty,
              !key.contains("your-anon") else { return nil }
        return key
    }

    static var stripePublishableKey: String? {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "STRIPE_PUBLISHABLE_KEY") as? String,
              !key.isEmpty,
              !key.contains("your_key"),
              !key.contains("placeholder") else { return nil }
        return key
    }

    /// Apple Pay merchant id, e.g. merchant.com.yourname.dormrun
    static var stripeMerchantId: String? {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "STRIPE_MERCHANT_ID") as? String,
              !id.isEmpty,
              !id.contains("your") else { return nil }
        return id
    }

    static var isConfigured: Bool {
        url != nil && anonKey != nil
    }
}

/// Builds `AppEnvironment` with live repos when `Config.xcconfig` has Supabase URL + anon key.
enum LiveRepositoryFactory {
    @MainActor
    static func makeEnvironment() -> AppEnvironment {
        AppEnvironment(
            payments: StripePaymentService(
                publishableKey: SupabaseConfig.stripePublishableKey,
                merchantId: SupabaseConfig.stripeMerchantId
            )
        )
    }
}
