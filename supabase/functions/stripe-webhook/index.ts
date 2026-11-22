// Edge function: stripe-webhook
//
// POST /functions/v1/stripe-webhook
// Stripe-Signature: t=…,v1=…
//
// Confirms / fails / refunds PaymentIntents against public.orders.
// Deploy + secrets:
//   supabase secrets set STRIPE_SECRET_KEY=sk_live_… STRIPE_WEBHOOK_SECRET=whsec_…
//   supabase functions deploy stripe-webhook --no-verify-jwt
// Stripe Dashboard → Webhooks → add endpoint:
//   https://<project>.supabase.co/functions/v1/stripe-webhook
// Events: payment_intent.succeeded, payment_intent.payment_failed,
//         payment_intent.canceled, charge.refunded

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, stripe-signature",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

async function verifyStripeSignature(
  payload: string,
  header: string | null,
  secret: string,
): Promise<boolean> {
  if (!header) return false;
  const parts = Object.fromEntries(
    header.split(",").map((p) => {
      const [k, v] = p.split("=");
      return [k.trim(), v];
    }),
  );
  const timestamp = parts["t"];
  const signature = parts["v1"];
  if (!timestamp || !signature) return false;

  const age = Math.abs(Date.now() / 1000 - Number(timestamp));
  if (!Number.isFinite(age) || age > 300) return false;

  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signed = await crypto.subtle.sign(
    "HMAC",
    key,
    encoder.encode(`${timestamp}.${payload}`),
  );
  const digest = Array.from(new Uint8Array(signed))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");

  // Constant-time-ish compare
  if (digest.length !== signature.length) return false;
  let mismatch = 0;
  for (let i = 0; i < digest.length; i++) {
    mismatch |= digest.charCodeAt(i) ^ signature.charCodeAt(i);
  }
  return mismatch === 0;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const webhookSecret = Deno.env.get("STRIPE_WEBHOOK_SECRET");
  if (!webhookSecret) {
    return json({ error: "STRIPE_WEBHOOK_SECRET is not configured" }, 503);
  }

  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  if (!serviceKey || !supabaseUrl) {
    return json({ error: "Supabase service role is not configured" }, 503);
  }

  const payload = await req.text();
  const ok = await verifyStripeSignature(
    payload,
    req.headers.get("stripe-signature"),
    webhookSecret,
  );
  if (!ok) return json({ error: "Invalid Stripe signature" }, 400);

  let event: { type?: string; data?: { object?: Record<string, unknown> } };
  try {
    event = JSON.parse(payload);
  } catch {
    return json({ error: "Invalid JSON" }, 400);
  }

  const obj = event.data?.object ?? {};
  const piId =
    (typeof obj.id === "string" && obj.object === "payment_intent"
      ? obj.id
      : typeof obj.payment_intent === "string"
      ? obj.payment_intent
      : null) as string | null;

  if (!piId) {
    return json({ received: true, skipped: "no payment_intent id" });
  }

  let paymentStatus: string | null = null;
  switch (event.type) {
    case "payment_intent.succeeded":
      paymentStatus = "succeeded";
      break;
    case "payment_intent.payment_failed":
      paymentStatus = "failed";
      break;
    case "payment_intent.canceled":
      paymentStatus = "failed";
      break;
    case "charge.refunded":
      paymentStatus = "refunded";
      break;
    default:
      return json({ received: true, ignored: event.type });
  }

  const admin = createClient(supabaseUrl, serviceKey);
  const { data, error } = await admin
    .from("orders")
    .update({ payment_status: paymentStatus })
    .eq("payment_intent_id", piId)
    .select("id");

  if (error) {
    console.error("orders payment_status update failed", error.message);
    return json({ error: error.message }, 500);
  }

  return json({
    received: true,
    payment_status: paymentStatus,
    updated: (data ?? []).length,
  });
});
