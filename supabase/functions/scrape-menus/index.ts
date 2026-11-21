// Edge function: scrape-menus
//
// POST /functions/v1/scrape-menus
// Header: Authorization: Bearer <service_role or cron secret>
//
// Pulls today's lunch/dinner stations from umassdining.com FoodPro HTML and
// replaces menu_categories + menu_items for the four dining commons.
// Schedule via Supabase Dashboard → Edge Functions → Schedules (e.g. every 3h),
// or:  supabase functions schedule scrape-menus --cron "0 */3 * * *"

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-cron-secret",
};

const LOCATIONS: Record<string, { seedId: string; url: string; catBase: number }> = {
  worcester: {
    seedId: "d0000000-0000-4000-8000-000000000001",
    url: "https://umassdining.com/locations-menus/worcester/menu",
    catBase: 1,
  },
  franklin: {
    seedId: "d0000000-0000-4000-8000-000000000002",
    url: "https://umassdining.com/locations-menus/franklin/menu",
    catBase: 50,
  },
  berkshire: {
    seedId: "d0000000-0000-4000-8000-000000000003",
    url: "https://umassdining.com/locations-menus/berkshire/menu",
    catBase: 100,
  },
  hampshire: {
    seedId: "d0000000-0000-4000-8000-000000000004",
    url: "https://umassdining.com/locations-menus/hampshire/menu",
    catBase: 150,
  },
};

const SKIP_DISHES = new Set([
  "onions",
  "diced tomatoes",
  "fresh green peppers",
  "sliced mushrooms",
  "american cheese",
  "shredded cheddar cheese",
  "hard boiled egg",
  "nori seaweed",
  "french fries",
  "halal french fries",
]);

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function uuid(prefix: "c" | "e", n: number): string {
  return `${prefix}0000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
}

function priceForStation(station: string): number {
  const s = station.toLowerCase();
  if (s.includes("soup")) return 450;
  if (s.includes("dessert") || s.includes("pastr") || s.includes("bread")) return 350;
  if (s.includes("grill")) return 950;
  if (s.includes("sushi") || s.includes("seasons")) return 1095;
  if (s.includes("noodle") || s.includes("tandoor") || s.includes("mediterranean") || s.includes("street")) {
    return 995;
  }
  return 875;
}

function parseStations(html: string): { meal: string; stations: { station: string; items: { name: string; tags: string[] }[] }[] } {
  const mealIds: [string, string][] = [
    ["Lunch", "lunch_menu"],
    ["Dinner", "dinner_menu"],
    ["Late Night", "latenight_menu"],
    ["Breakfast", "breakfast_menu"],
  ];

  let chosenMeal = "Lunch";
  let chunk = "";
  for (const [meal, id] of mealIds) {
    const start = html.indexOf(`id="${id}"`);
    if (start < 0) continue;
    let end = html.length;
    for (const [, other] of mealIds) {
      const next = html.indexOf(`id="${other}"`, start + 10);
      if (next > start) end = Math.min(end, next);
    }
    const slice = html.slice(start, end);
    if (slice.includes("data-dish-name=")) {
      chosenMeal = meal;
      chunk = slice;
      break;
    }
  }
  if (!chunk) return { meal: chosenMeal, stations: [] };

  type Tok = { i: number; kind: "station" | "dish"; val: string; tags?: string[] };
  const toks: Tok[] = [];
  const hRe = /<h[23][^>]*>([^<]+)<\/h[23]>/gi;
  let m: RegExpExecArray | null;
  while ((m = hRe.exec(chunk))) {
    let t = m[1].replace(/\s+/g, " ").trim();
    t = t.replace(/\s*(WOR|FRA|BER|HAM)\s*$/i, "").trim();
    if (!t || t.toLowerCase() === chosenMeal.toLowerCase() || t.toLowerCase() === "legends") continue;
    toks.push({ i: m.index, kind: "station", val: t });
  }
  const dRe = /data-dish-name="([^"]+)"[^>]*>(?:.*?)<\/a>((?:<img[^>]+>|\s)*)/gis;
  while ((m = dRe.exec(chunk))) {
    const name = m[1].trim();
    const imgs = m[2] ?? "";
    const tags: string[] = [];
    if (imgs.includes("icon-hal")) tags.push("halal");
    if (imgs.includes("icon-vegan") || imgs.includes("icon-vn")) tags.push("vegan");
    else if (imgs.includes("icon-veg")) tags.push("vegetarian");
    if (imgs.includes("icon-gf")) tags.push("gf");
    toks.push({ i: m.index, kind: "dish", val: name, tags });
  }
  toks.sort((a, b) => a.i - b.i);

  const byStation = new Map<string, { name: string; tags: string[] }[]>();
  let current = "General";
  for (const t of toks) {
    if (t.kind === "station") {
      current = t.val;
      continue;
    }
    if (SKIP_DISHES.has(t.val.toLowerCase())) continue;
    const list = byStation.get(current) ?? [];
    if (!list.some((x) => x.name === t.val)) {
      list.push({ name: t.val, tags: t.tags ?? [] });
      byStation.set(current, list);
    }
  }

  const stations = [...byStation.entries()].map(([station, items]) => ({
    station,
    items: items.slice(0, 12),
  }));
  return { meal: chosenMeal, stations };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const cronSecret = Deno.env.get("CRON_SECRET");
  const provided = req.headers.get("x-cron-secret");
  const auth = req.headers.get("Authorization") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const okCron = cronSecret && provided === cronSecret;
  const okService = serviceKey && auth === `Bearer ${serviceKey}`;
  if (!okCron && !okService) return json({ error: "Unauthorized" }, 401);

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    serviceKey || Deno.env.get("SUPABASE_ANON_KEY")!,
  );

  const summary: Record<string, unknown> = {};
  let itemN = 200;

  for (const [key, meta] of Object.entries(LOCATIONS)) {
    const res = await fetch(meta.url, {
      headers: { "User-Agent": "UMassEatsBot/1.0 (menu sync)" },
    });
    const html = await res.text();
    const { meal, stations } = parseStations(html);

    await supabase.from("menu_items").delete().in(
      "category_id",
      (
        await supabase
          .from("menu_categories")
          .select("id")
          .eq("location_id", meta.seedId)
      ).data?.map((r: { id: string }) => r.id) ?? [],
    );
    await supabase.from("menu_categories").delete().eq("location_id", meta.seedId);

    const cats = stations.map((st, i) => ({
      id: uuid("c", meta.catBase + i),
      location_id: meta.seedId,
      name: st.station,
      sort_order: i + 1,
    }));
    if (cats.length) {
      const { error: catErr } = await supabase.from("menu_categories").insert(cats);
      if (catErr) return json({ error: catErr.message, location: key }, 500);
    }

    const items: Record<string, unknown>[] = [];
    for (let i = 0; i < stations.length; i++) {
      const st = stations[i];
      const price = priceForStation(st.station);
      for (const it of st.items) {
        items.push({
          id: uuid("e", itemN++),
          category_id: uuid("c", meta.catBase + i),
          name: it.name,
          description: `From today's ${meal.toLowerCase()} menu · ${st.station}`,
          price_cents: price,
          tags: it.tags,
          image_url: null,
          is_available: true,
        });
      }
    }
    if (items.length) {
      const { error: itemErr } = await supabase.from("menu_items").insert(items);
      if (itemErr) return json({ error: itemErr.message, location: key }, 500);
    }

    summary[key] = { meal, stations: stations.length, items: items.length };
  }

  return json({ ok: true, scraped_at: new Date().toISOString(), locations: summary });
});
