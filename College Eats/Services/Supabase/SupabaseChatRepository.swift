import Foundation

actor SupabaseChatRepository: ChatRepository {
    private let client: SupabaseHTTPClient
    private let fallback = MockChatRepository()

    init(client: SupabaseHTTPClient) {
        self.client = client
    }

    func fetchMessages(orderId: String) async throws -> [OrderMessage] {
        do {
            let rows = try await client.fetchOrderMessages(orderId: orderId)
            return rows.map {
                OrderMessage(
                    id: $0.id,
                    orderId: $0.order_id,
                    senderId: $0.sender_id,
                    body: $0.body,
                    createdAt: ISO8601DateFormatter().date(from: $0.created_at) ?? .now
                )
            }
        } catch {
            return try await fallback.fetchMessages(orderId: orderId)
        }
    }

    func sendMessage(orderId: String, senderId: String, body: String) async throws -> OrderMessage {
        do {
            let row = try await client.sendOrderMessage(orderId: orderId, senderId: senderId, body: body)
            return OrderMessage(
                id: row.id,
                orderId: row.order_id,
                senderId: row.sender_id,
                body: row.body,
                createdAt: ISO8601DateFormatter().date(from: row.created_at) ?? .now
            )
        } catch {
            // Table may not be migrated yet — keep chat usable offline.
            return try await fallback.sendMessage(orderId: orderId, senderId: senderId, body: body)
        }
    }
}
