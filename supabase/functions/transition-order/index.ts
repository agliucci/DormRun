// Edge function: transition-order
//
// POST /functions/v1/transition-order
// Authorization: Bearer <user JWT>
// Body: { "order_id": "<uuid>", "new_status": "accepted|at_pickup|picked_up|en_route|delivered|cancelled",
//         "handoff_code": "1234" }   // handoff_code required for "delivered"
//
// Thin wrapper over the Postgres RPC `transition_order_status`. The actor is
// always the authenticated user (never taken from the request body), and all
// state-machine rules are enforced in the database.
// TODO: push notifications to the customer/runner on status changes.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const ALLOWED_STATUSES = new Set([
  "accepted",
  "at_pickup",
  "picked_up",
  "en_route",
  "delivered",
  "cancelled",
]);

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return json({ error: "Missing Authorization header" }, 401);

  let payload: { order_id?: string; new_status?: string; handoff_code?: string | null };
  try {
    payload = await req.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  const { order_id, new_status, handoff_code } = payload;
  if (!order_id || !new_status || !ALLOWED_STATUSES.has(new_status)) {
    return json({ error: "order_id and a valid new_status are required" }, 400);
  }

  // Client scoped to the caller's JWT so auth.uid() resolves inside Postgres.
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: authHeader } } },
  );

  const { data: userData, error: userError } = await supabase.auth.getUser();
  if (userError || !userData.user) return json({ error: "Unauthorized" }, 401);

  const { data, error } = await supabase.rpc("transition_order_status", {
    p_order_id: order_id,
    p_new_status: new_status,
    p_actor_id: userData.user.id,
    p_handoff_code: handoff_code ?? null,
  });

  if (error) {
    // 42501 = insufficient_privilege, 22023 = invalid transition/parameter, P0002 = not found
    const status = error.code === "42501" ? 403 : error.code === "P0002" ? 404 : 400;
    return json({ error: error.message, code: error.code }, status);
  }

  return json({ order: data });
});
