// Edge function: create-cash-out
//
// POST /functions/v1/create-cash-out
// Authorization: Bearer <user JWT>
// Body: {} (optional)
//
// Transfers available runner earnings (delivered, not yet paid out) from the
// platform Stripe balance to the runner's Connect account, then marks orders.
//
// Requires: STRIPE_SECRET_KEY, SUPABASE_SERVICE_ROLE_KEY
// Runner must have profiles.stripe_account_id from create-connect-account-link.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function runnerPayoutCents(row: {
  fulfillment_mode?: string | null;
  subtotal_cents?: number | null;
  delivery_fee_cents?: number | null;
  tip_cents?: number | null;
  runner_meal_bump_cents?: number | null;
}): number {
  const fee = Number(row.delivery_fee_cents ?? 0);
  const tip = Number(row.tip_cents ?? 0);
  const bump = Number(row.runner_meal_bump_cents ?? 0);
  const food =
    row.fulfillment_mode === "retail_purchase" ? Number(row.subtotal_cents ?? 0) : 0;
  return fee + tip + bump + food;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const stripeKey = Deno.env.get("STRIPE_SECRET_KEY");
  if (!stripeKey) {
    return json({ error: "STRIPE_SECRET_KEY is not configured on this function." }, 503);
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return json({ error: "Missing Authorization header" }, 401);

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!serviceKey) {
    return json({ error: "SUPABASE_SERVICE_ROLE_KEY is not configured" }, 503);
  }

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: userData, error: userError } = await userClient.auth.getUser();
  if (userError || !userData.user) return json({ error: "Unauthorized" }, 401);

  const admin = createClient(supabaseUrl, serviceKey);

  const { data: profile, error: profileError } = await admin
    .from("profiles")
    .select("stripe_account_id, is_runner")
    .eq("id", userData.user.id)
    .maybeSingle();

  if (profileError) {
    return json({ error: `Profile lookup failed: ${profileError.message}` }, 400);
  }

  const accountId = (profile as { stripe_account_id?: string } | null)?.stripe_account_id;
  if (!accountId) {
    return json(
      { error: "Link a bank account with Stripe Connect before cashing out." },
      400,
    );
  }

  const { data: orders, error: ordersError } = await admin
    .from("orders")
    .select(
      "id, fulfillment_mode, subtotal_cents, delivery_fee_cents, tip_cents, runner_meal_bump_cents, payment_status",
    )
    .eq("runner_id", userData.user.id)
    .eq("status", "delivered")
    .is("runner_paid_out_at", null);

  if (ordersError) {
    return json({ error: ordersError.message }, 400);
  }

  const unpaid = (orders ?? []).filter((o) =>
    o.payment_status === "succeeded" || o.payment_status === "unpaid" || !o.payment_status
  );

  if (unpaid.length === 0) {
    return json({ transferredCents: 0, message: "Nothing available to cash out yet." });
  }

  const amount = unpaid.reduce((sum, row) => sum + runnerPayoutCents(row), 0);
  if (amount < 50) {
    return json(
      { error: "Available balance is below Stripe’s $0.50 transfer minimum." },
      400,
    );
  }

  const orderIds = unpaid.map((o) => o.id as string);
  const body = new URLSearchParams();
  body.set("amount", String(amount));
  body.set("currency", "usd");
  body.set("destination", accountId);
  body.set("metadata[app]", "dormrun");
  body.set("metadata[runner_id]", userData.user.id);
  body.set("metadata[order_ids]", orderIds.join(","));

  const stripeRes = await fetch("https://api.stripe.com/v1/transfers", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${stripeKey}`,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body,
  });
  const stripeJson = await stripeRes.json();
  if (!stripeRes.ok) {
    return json(
      {
        error: stripeJson?.error?.message ?? "Stripe transfer failed",
        stripe: stripeJson,
      },
      400,
    );
  }

  const transferId = stripeJson.id as string;
  const now = new Date().toISOString();
  const { error: markError } = await admin
    .from("orders")
    .update({ runner_paid_out_at: now, runner_transfer_id: transferId })
    .in("id", orderIds);

  if (markError) {
    console.error("Failed to mark orders paid out after transfer", markError.message);
    return json(
      {
        error:
          `Transfer ${transferId} succeeded but orders were not marked paid out: ${markError.message}`,
        transferId,
        transferredCents: amount,
      },
      500,
    );
  }

  return json({
    transferredCents: amount,
    transferId,
    orderCount: orderIds.length,
    message: `$${(amount / 100).toFixed(2)} is on the way to your bank.`,
  });
});
