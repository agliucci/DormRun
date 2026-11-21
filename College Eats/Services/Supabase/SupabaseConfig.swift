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
              !key.contains("your_key") else { return nil }
        return key
    }

    static var isConfigured: Bool {
        url != nil && anonKey != nil
    }
}

/// Live Supabase repositories land here once `supabase-swift` is added via SPM
/// and Config.xcconfig is filled in. Until then, `AppEnvironment` uses mocks.
enum LiveRepositoryFactory {
    @MainActor
    static func makeEnvironment() -> AppEnvironment {
        // Swap to live implementations when SupabaseConfig.isConfigured && package linked.
        AppEnvironment()
    }
}
