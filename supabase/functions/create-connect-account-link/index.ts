// Edge function: create-connect-account-link
//
// POST /functions/v1/create-connect-account-link
// Authorization: Bearer <user JWT>
// Body: { "refresh_url": "https://…", "return_url": "https://…" }
//
// Your Stripe platform uses Managed Risk, which requires:
//   - Accounts v2 (no legacy `type`)
//   - defaults.responsibilities.losses_collector = "stripe"
//   - Merchant configuration + card_payments
// Recipient + application liability is rejected on Managed Risk platforms.
//
// Requires: supabase secrets set STRIPE_SECRET_KEY=sk_test_...

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const STRIPE_VERSION = "2026-11-18.endive";

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function httpsOrDefault(value: string | undefined, fallback: string): string {
  if (value && /^https?:\/\//i.test(value)) return value;
  return fallback;
}

async function stripeV2(
  path: string,
  stripeKey: string,
  body: unknown,
): Promise<{ ok: boolean; status: number; json: any }> {
  const res = await fetch(`https://api.stripe.com${path}`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${stripeKey}`,
      "Content-Type": "application/json",
      "Stripe-Version": STRIPE_VERSION,
    },
    body: JSON.stringify(body),
  });
  const parsed = await res.json();
  return { ok: res.ok, status: res.status, json: parsed };
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

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: userData, error: userError } = await userClient.auth.getUser();
  if (userError || !userData.user) return json({ error: "Unauthorized" }, 401);

  const admin = serviceKey ? createClient(supabaseUrl, serviceKey) : userClient;

  let payload: { refresh_url?: string; return_url?: string };
  try {
    payload = await req.json();
  } catch {
    payload = {};
  }

  const refreshUrl = httpsOrDefault(payload.refresh_url, "https://dormrun.app/stripe/refresh");
  const returnUrl = httpsOrDefault(payload.return_url, "https://dormrun.app/stripe/return");

  const { data: profile, error: profileError } = await admin
    .from("profiles")
    .select("stripe_account_id, full_name")
    .eq("id", userData.user.id)
    .maybeSingle();

  if (profileError) {
    return json({ error: `Profile lookup failed: ${profileError.message}` }, 400);
  }

  let accountId = (profile as { stripe_account_id?: string } | null)?.stripe_account_id;
  const displayName =
    (profile as { full_name?: string } | null)?.full_name?.trim() ||
    userData.user.email?.split("@")[0] ||
    "DormRun runner";

  if (!accountId) {
    // Exact Managed Risk shape from Stripe docs:
    // https://docs.stripe.com/connect/risk-management/connected-accounts-with-managed-risk
    const created = await stripeV2("/v2/core/accounts", stripeKey, {
      contact_email: userData.user.email ?? undefined,
      display_name: displayName,
      dashboard: "full",
      identity: {
        country: "us",
        entity_type: "individual",
      },
      defaults: {
        responsibilities: {
          fees_collector: "stripe",
          losses_collector: "stripe",
        },
      },
      configuration: {
        merchant: {
          capabilities: {
            card_payments: { requested: true },
          },
        },
      },
      metadata: {
        user_id: userData.user.id,
        app: "dormrun",
      },
      include: ["configuration.merchant", "identity", "defaults", "requirements"],
    });

    if (!created.ok) {
      return json(
        {
          error: created.json?.error?.message ?? created.json?.message ?? "Could not create Connect account",
          stripe: created.json,
        },
        400,
      );
    }

    accountId = created.json.id as string;

    const { error: updateError } = await admin
      .from("profiles")
      .update({ stripe_account_id: accountId })
      .eq("id", userData.user.id);

    if (updateError) {
      console.error("stripe_account_id save failed:", updateError.message);
    }
  }

  // Account Links v2 — do not pass `configurations` (unknown field on current API).
  const link = await stripeV2("/v2/core/account_links", stripeKey, {
    account: accountId,
    use_case: {
      type: "account_onboarding",
      account_onboarding: {
        collection_options: { fields: "eventually_due" },
        return_url: returnUrl,
        refresh_url: refreshUrl,
      },
    },
  });

  if (!link.ok) {
    return json(
      {
        error: link.json?.error?.message ?? link.json?.message ?? "Could not create account link",
        stripe: link.json,
      },
      400,
    );
  }

  const url = link.json.url as string | undefined;
  if (!url) {
    return json({ error: "Stripe returned no onboarding URL", stripe: link.json }, 400);
  }

  return json({ url, accountId });
});
