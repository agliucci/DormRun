// Edge function: create-payment-intent
//
// POST /functions/v1/create-payment-intent
// Authorization: Bearer <user JWT>
// Body: { "amount_cents": 1299, "currency": "usd", "customer_email": "a@umass.edu" }
//
// Creates a Stripe PaymentIntent with the secret key (server-side only).
// Set secrets:  supabase secrets set STRIPE_SECRET_KEY=sk_test_...
// Optional:     supabase secrets set STRIPE_WEBHOOK_SECRET=whsec_...

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

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const stripeKey = Deno.env.get("STRIPE_SECRET_KEY");
  if (!stripeKey) {
    return json({ error: "STRIPE_SECRET_KEY is not configured on this function." }, 503);
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return json({ error: "Missing Authorization header" }, 401);

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: authHeader } } },
  );
  const { data: userData, error: userError } = await supabase.auth.getUser();
  if (userError || !userData.user) return json({ error: "Unauthorized" }, 401);

  let payload: { amount_cents?: number; currency?: string; customer_email?: string };
  try {
    payload = await req.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  const amount = Math.floor(Number(payload.amount_cents ?? 0));
  if (!Number.isFinite(amount) || amount < 50) {
    return json({ error: "amount_cents must be at least 50" }, 400);
  }
  const currency = (payload.currency ?? "usd").toLowerCase();
  const email = payload.customer_email ?? userData.user.email ?? undefined;

  const body = new URLSearchParams();
  body.set("amount", String(amount));
  body.set("currency", currency);
  body.set("automatic_payment_methods[enabled]", "true");
  body.set("metadata[user_id]", userData.user.id);
  body.set("metadata[app]", "dormrun");
  if (email) body.set("receipt_email", email);

  const stripeRes = await fetch("https://api.stripe.com/v1/payment_intents", {
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
      { error: stripeJson?.error?.message ?? "Stripe PaymentIntent failed", stripe: stripeJson },
      400,
    );
  }

  return json({
    paymentIntentId: stripeJson.id,
    clientSecret: stripeJson.client_secret,
    publishableKey: Deno.env.get("STRIPE_PUBLISHABLE_KEY") ?? null,
  });
});
