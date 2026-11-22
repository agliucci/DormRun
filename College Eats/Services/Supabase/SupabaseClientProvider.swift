import Foundation

enum SupabaseClientProvider {
    private static let lock = NSLock()
    private static var cached: SupabaseHTTPClient?

    static func shared() -> SupabaseHTTPClient? {
        lock.lock()
        defer { lock.unlock() }
        if let cached { return cached }
        guard let url = SupabaseConfig.url, let key = SupabaseConfig.anonKey else { return nil }
        let client = SupabaseHTTPClient(baseURL: url, anonKey: key)
        cached = client
        return client
    }

    static func makeAuthRepository() -> any AuthRepository {
        if let client = shared() {
            return SupabaseAuthRepository(client: client)
        }
        return PersistingMockAuthRepository()
    }

    static func makeCampusRepository() -> any CampusRepository {
        if let client = shared() {
            return SupabaseCampusRepository(client: client)
        }
        return MockCampusRepository()
    }

    static func makeChatRepository() -> any ChatRepository {
        if let client = shared() {
            return SupabaseChatRepository(client: client)
        }
        return MockChatRepository()
    }

    static func makeOrderRepository() -> any OrderRepository {
        if let client = shared() {
            return SupabaseOrderRepository(client: client)
        }
        return MockOrderRepository()
    }

    static var usesLiveAuth: Bool {
        SupabaseConfig.isConfigured
    }
}
