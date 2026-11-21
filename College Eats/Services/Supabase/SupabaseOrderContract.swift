import Foundation

/// Contract notes for live Supabase order access (see `supabase/migrations` + README).
///
/// Critical rules from the schema:
/// 1. Never `select *` on `orders` — `handoff_code` is column-revoked so runners can't peek.
/// 2. Customers load the code via RPC `get_handoff_code(p_order_id)`.
/// 3. Status changes go through `transition_order_status` / Edge Function `transition-order`
///    — there is no client UPDATE policy on `orders`.
/// 4. `p_actor_id` must match `auth.uid()` for user JWTs; null actor = service role only.
/// 5. RPC return JSON omits `handoff_code`.
enum SupabaseOrderContract {
    /// Columns safe to select on `orders` for list/detail queries.
    static let orderSelectColumns = [
        "id",
        "customer_id",
        "runner_id",
        "location_id",
        "dropoff_building_id",
        "dropoff_note",
        "status",
        "subtotal_cents",
        "delivery_fee_cents",
        "tip_cents",
        "placed_at",
        "accepted_at",
        "at_pickup_at",
        "picked_up_at",
        "en_route_at",
        "delivered_at",
        "cancelled_at",
        "cancel_reason",
    ].joined(separator: ",")

    static let getHandoffCodeRPC = "get_handoff_code"
    static let transitionStatusRPC = "transition_order_status"
    static let transitionEdgeFunction = "transition-order"
}
