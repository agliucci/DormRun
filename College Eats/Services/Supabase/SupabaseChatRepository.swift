import Foundation

actor SupabaseChatRepository: ChatRepository {
    private let client: SupabaseHTTPClient
    /// Shared so send + fetch hit the same in-memory store when live orders aren’t in Supabase yet.
    private let fallback = MockChatRepository()

    init(client: SupabaseHTTPClient) {
        self.client = client
    }

    func fetchMessages(orderId: String) async throws -> [OrderMessage] {
        let offline = (try? await fallback.fetchMessages(orderId: orderId)) ?? []
        do {
            let rows = try await client.fetchOrderMessages(orderId: orderId)
            let live = rows.map(Self.mapRow)
            // Live orders table doesn’t know about mock order IDs — empty live + offline = use offline.
            if live.isEmpty && !offline.isEmpty {
                return offline
            }
            return merge(live: live, offline: offline)
        } catch {
            return offline
        }
    }

    func sendMessage(orderId: String, senderId: String, body: String) async throws -> OrderMessage {
        do {
            let row = try await client.sendOrderMessage(orderId: orderId, senderId: senderId, body: body)
            return Self.mapRow(row)
        } catch {
            // Order lives only in the mock repo → FK fails; chat still works offline.
            return try await fallback.sendMessage(orderId: orderId, senderId: senderId, body: body)
        }
    }

    private static func mapRow(_ row: RemoteOrderMessage) -> OrderMessage {
        OrderMessage(
            id: row.id,
            orderId: row.order_id,
            senderId: row.sender_id,
            body: row.body,
            createdAt: ISO8601DateFormatter().date(from: row.created_at) ?? .now
        )
    }

    private func merge(live: [OrderMessage], offline: [OrderMessage]) -> [OrderMessage] {
        var byId: [String: OrderMessage] = [:]
        for message in live + offline {
            byId[message.id] = message
        }
        return byId.values.sorted { $0.createdAt < $1.createdAt }
    }
}
