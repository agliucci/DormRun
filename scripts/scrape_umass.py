#!/usr/bin/env python3
"""
Scrape UMass residence halls + dining commons menus and refresh local seed data.

Sources:
  - https://www.umass.edu/living/housing-options/residence-directory
  - https://umassdining.com/locations-menus/{worcester,franklin,berkshire,hampshire}/menu
  - Blue Wall station menus under /menu/*-blue-wall*
  - https://www.umassdining.com/menu/terrace-dining-menu

Writes:
  - College Eats/Services/Mock/GeneratedUMassCatalog.swift
  - supabase/seed_buildings.sql  (buildings upsert fragment)
  - supabase/seed_menus_scraped.sql (dining categories + items)

Dining halls do not publish per-item prices; we assign placeholder
delivery-style prices by station so the app cart still works.
Re-run anytime menus change:  python3 scripts/scrape_umass.py
"""

from __future__ import annotations

import html as H
import json
import re
import ssl
import urllib.request
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT_SWIFT = ROOT / "College Eats" / "Services" / "Mock" / "GeneratedUMassCatalog.swift"
OUT_BUILDINGS_SQL = ROOT / "supabase" / "seed_buildings.sql"
OUT_MENUS_SQL = ROOT / "supabase" / "seed_menus_scraped.sql"

CAMPUS_ID = "a0000000-0000-4000-8000-000000000001"
UA = "UMassEatsBot/1.0 (+local catalog sync; contact campus app)"

RESIDENCE_URL = "https://www.umass.edu/living/housing-options/residence-directory"
DINING_LOCATIONS = {
    # Category UUID bases stay well above the demo seed (c…001–021).
    "worcester": {
        "urls": ["https://umassdining.com/locations-menus/worcester/menu"],
        "loc_id": "d0000000-0000-4000-8000-000000000001",
        "seed_loc": "d0000000-0000-4000-8000-000000000001",
        "prefix": "wc",
        "seed_cat_base": 1000,
    },
    "franklin": {
        "urls": ["https://umassdining.com/locations-menus/franklin/menu"],
        "loc_id": "d0000000-0000-4000-8000-000000000002",
        "seed_loc": "d0000000-0000-4000-8000-000000000002",
        "prefix": "fr",
        "seed_cat_base": 1100,
    },
    "berkshire": {
        "urls": ["https://umassdining.com/locations-menus/berkshire/menu"],
        "loc_id": "d0000000-0000-4000-8000-000000000003",
        "seed_loc": "d0000000-0000-4000-8000-000000000003",
        "prefix": "bk",
        "seed_cat_base": 1200,
    },
    "hampshire": {
        "urls": ["https://umassdining.com/locations-menus/hampshire/menu"],
        "loc_id": "d0000000-0000-4000-8000-000000000004",
        "seed_loc": "d0000000-0000-4000-8000-000000000004",
        "prefix": "hm",
        "seed_cat_base": 1300,
    },
    # Campus Center food court — each concept has its own daily menu page.
    "blue_wall": {
        "urls": [
            ("Harvest", "https://www.umassdining.com/menu/harvest-blue-wall-menu"),
            ("Yum Bakery", "https://www.umassdining.com/menu/um-bakery-blue-wall-menu"),
            ("Green Fields", "https://www.umassdining.com/menu/green-fields-blue-wall"),
            ("Tamales", "https://www.umassdining.com/menu/tamales-blue-wall-menu"),
            ("Wasabi", "https://www.umassdining.com/menu/wasabi-blue-wall"),
            ("Deli Delish", "https://www.umassdining.com/menu/deli-delish-blue-wall"),
            ("Star Ginger", "https://www.umassdining.com/menu/star-ginger-blue-wall-menu"),
            ("The Grill", "https://www.umassdining.com/menu/grill-blue-wall-menu"),
        ],
        "loc_id": "d0000000-0000-4000-8000-000000000005",
        "seed_loc": "d0000000-0000-4000-8000-000000000005",
        "prefix": "bw",
        "seed_cat_base": 1400,
        "max_items_per_station": 8,
    },
    "terrace": {
        "urls": ["https://www.umassdining.com/menu/terrace-dining-menu"],
        "loc_id": "d0000000-0000-4000-8000-000000000006",
        "seed_loc": "d0000000-0000-4000-8000-000000000006",
        "prefix": "tr",
        "seed_cat_base": 1600,
    },
}

# Stable UUIDs for halls that already shipped in seed / mock data.
STABLE_BUILDING_IDS = {
    "kennedy hall": 1,
    "john quincy adams hall": 2,
    "coolidge hall": 3,
    "washington hall": 4,
    "pierpont hall": 5,
    "field hall": 6,
    "webster hall": 7,
    "dickinson house": 8,
    "van meter hall": 9,
    "brett hall": 10,
    "crabtree hall": 11,
    "knowlton hall": 12,
    "cashin hall": 13,
    "brown hall": 14,
    "oak hall": 15,
    "elm hall": 16,
    "maple hall": 17,
    "linden hall": 18,
}

NEIGHBORHOOD_COORDS = {
    "Southwest": (42.3840, -72.5315),
    "Orchard Hill": (42.3895, -72.5205),
    "Central": (42.3880, -72.5255),
    "Northeast": (42.3950, -72.5225),
    "Sylvan": (42.3975, -72.5275),
    "Commonwealth Honors College": (42.3888, -72.5290),
    "North Apartments": (42.4010, -72.5260),
}

SKIP_DISH_NAMES = {
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
}

SKIP_STATIONS = {"legends", "nutrition facts"}

CTX = ssl.create_default_context()


def fetch(url: str) -> str:
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=45, context=CTX) as resp:
        return resp.read().decode("utf-8", "ignore")


def building_uuid(n: int) -> str:
    return f"b0000000-0000-4000-8000-{n:012d}"


def category_uuid(n: int) -> str:
    return f"c0000000-0000-4000-8000-{n:012d}"


def item_uuid(n: int) -> str:
    return f"e0000000-0000-4000-8000-{n:012d}"


def normalize_area(area: str) -> str:
    area = H.unescape(area).replace("\xa0", " ").strip()
    if "Southwest" in area:
        return "Southwest"
    if "Orchard Hill" in area:
        return "Orchard Hill"
    if "Northeast" in area:
        return "Northeast"
    if "Sylvan" in area:
        return "Sylvan"
    if "North" in area:
        return "North Apartments"
    if "Honors" in area or "CHCRC" in area or "Commonwealth" in area:
        return "Commonwealth Honors College"
    if "Central" in area:
        return "Central"
    return area


def scrape_residences(html: str) -> list[dict]:
    blocks = re.findall(
        r"<strong>([^<]+)</strong>\s*<br>\s*<a[^>]*>([^<]+)</a>",
        html,
    )
    halls: list[tuple[str, str]] = []
    seen: set[str] = set()
    for name, area in blocks:
        name = H.unescape(name).replace("\xa0", " ").strip()
        name = re.sub(r"^[\u200b\s]+", "", name)
        if not name or name.lower().startswith("room"):
            continue
        key = name.lower()
        if key in seen:
            continue
        if not any(k in key for k in ("hall", "house", "apartment")):
            continue
        seen.add(key)
        halls.append((name, normalize_area(area)))

    # Assign stable then sequential IDs.
    used = set(STABLE_BUILDING_IDS.values())
    next_id = max(used | {0}) + 1
    rows: list[dict] = []
    for idx, (name, neigh) in enumerate(sorted(halls, key=lambda x: (x[1], x[0]))):
        key = name.lower()
        if key in STABLE_BUILDING_IDS:
            bid = STABLE_BUILDING_IDS[key]
        else:
            while next_id in used:
                next_id += 1
            bid = next_id
            used.add(bid)
            next_id += 1
        base_lat, base_lng = NEIGHBORHOOD_COORDS.get(neigh, (42.3912, -72.5267))
        # Fan out slightly so map pins don't stack.
        lat = round(base_lat + ((idx % 7) - 3) * 0.00035, 5)
        lng = round(base_lng + ((idx % 5) - 2) * 0.0004, 5)
        rows.append(
            {
                "id": building_uuid(bid),
                "name": name,
                "neighborhood": neigh,
                "latitude": lat,
                "longitude": lng,
            }
        )
    rows.sort(key=lambda r: (r["neighborhood"], r["name"]))
    return rows


def parse_menu(html: str) -> dict[str, list[dict]]:
    meals: dict[str, str | None] = {}
    for meal, mid in [
        ("Breakfast", "breakfast_menu"),
        ("Lunch", "lunch_menu"),
        ("Dinner", "dinner_menu"),
        ("Late Night", "latenight_menu"),
    ]:
        m = re.search(rf'id="{mid}"', html)
        if not m:
            meals[meal] = None
            continue
        start = m.start()
        nxt = len(html)
        for other in ["breakfast_menu", "lunch_menu", "dinner_menu", "latenight_menu"]:
            mm = re.search(rf'id="{other}"', html[start + 10 :])
            if mm:
                nxt = min(nxt, start + 10 + mm.start())
        meals[meal] = html[start:nxt]

    result: dict[str, list[dict]] = {}
    for meal, chunk in meals.items():
        if not chunk:
            result[meal] = []
            continue
        stations: dict[str, list[dict]] = defaultdict(list)
        current = "General"
        tokens: list[tuple[int, str, object]] = []
        for m in re.finditer(r"<h[23][^>]*>([^<]+)</h[23]>", chunk):
            t = H.unescape(m.group(1)).strip()
            t = re.sub(r"\s+", " ", t)
            t = re.sub(r"\s*(WOR|FRA|BER|HAM)\s*$", "", t, flags=re.I).strip()
            if t.lower() in {meal.lower()} | SKIP_STATIONS:
                continue
            tokens.append((m.start(), "station", t))
        for m in re.finditer(
            r'data-dish-name="([^"]+)"[^>]*>.*?</a>((?:<img[^>]+>|\s)*)',
            chunk,
            re.S,
        ):
            name = H.unescape(m.group(1)).strip()
            imgs = m.group(2)
            tags: list[str] = []
            if "icon-hal" in imgs:
                tags.append("halal")
            if "icon-vegan" in imgs or "icon-vn" in imgs:
                tags.append("vegan")
            elif "icon-veg" in imgs:
                tags.append("vegetarian")
            if "icon-gf" in imgs:
                tags.append("gf")
            tokens.append((m.start(), "dish", (name, tags)))
        tokens.sort(key=lambda x: x[0])
        for _, kind, val in tokens:
            if kind == "station":
                current = str(val)
            else:
                name, tags = val  # type: ignore[misc]
                if name.lower() in SKIP_DISH_NAMES:
                    continue
                stations[current].append({"name": name, "tags": tags})

        out: list[dict] = []
        for st, items in stations.items():
            seen: set[str] = set()
            uniq = []
            for it in items:
                if it["name"] in seen:
                    continue
                seen.add(it["name"])
                uniq.append(it)
            if uniq:
                out.append({"station": st, "items": uniq})
        result[meal] = out
    return result


def pick_active_meal(parsed: dict[str, list[dict]]) -> tuple[str, list[dict]]:
    """Prefer Lunch, then Dinner, then Late Night, then Breakfast."""
    for meal in ("Lunch", "Dinner", "Late Night", "Breakfast"):
        if parsed.get(meal):
            return meal, parsed[meal]
    return "Lunch", []


# Dish-name rules first (specific), then station fallback. UMass doesn't ship dish photos.
DISH_IMAGE_RULES: list[tuple[tuple[str, ...], str]] = [
    (("ramen", "shoyu", "udon", "pho"), "https://images.unsplash.com/photo-1569718212165-3a8278d5f624?w=600&auto=format&fit=crop"),
    (("pizza",), "https://images.unsplash.com/photo-1513104890138-7c749659a591?w=600&auto=format&fit=crop"),
    (("burger", "smash"), "https://images.unsplash.com/photo-1568901346375-23c9450c58cd?w=600&auto=format&fit=crop"),
    (("sushi", "nigiri", "maki", "sashimi"), "https://images.unsplash.com/photo-1579871494447-9811cf80d66c?w=600&auto=format&fit=crop"),
    (("soup", "chowder", "bisque", "broth"), "https://images.unsplash.com/photo-1547592166-23ac45744acd?w=600&auto=format&fit=crop"),
    (("salad", "greens", "arugula", "caesar"), "https://images.unsplash.com/photo-1512621776951-a57141f2eefd?w=600&auto=format&fit=crop"),
    (("spaghetti", "lasagna", "penne", "fettuccine", "pasta"), "https://images.unsplash.com/photo-1621996346565-e3dbc646d9a9?w=600&auto=format&fit=crop"),
    (("lo mein", "chow mein", "stir fry"), "https://images.unsplash.com/photo-1585032226651-759b368d7246?w=600&auto=format&fit=crop"),
    (("taco", "burrito", "quesadilla", "tamale", "nacho"), "https://images.unsplash.com/photo-1565299585323-38d6b0865b47?w=600&auto=format&fit=crop"),
    (("wing", "tenders", "nugget"), "https://images.unsplash.com/photo-1527477396000-e27173b8ed81?w=600&auto=format&fit=crop"),
    (("chicken",), "https://images.unsplash.com/photo-1598103442097-8b74394b95c6?w=600&auto=format&fit=crop"),
    (("steak", "brisket", "beef"), "https://images.unsplash.com/photo-1600891964092-4316c288032e?w=600&auto=format&fit=crop"),
    (("salmon", "tuna", "cod", "fish"), "https://images.unsplash.com/photo-1519708227418-c8fd9a32b7a2?w=600&auto=format&fit=crop"),
    (("french toast", "pancake", "waffle", "omelet", "egg", "biscuit", "breakfast"), "https://images.unsplash.com/photo-1525351484163-7529414344d8?w=600&auto=format&fit=crop"),
    (("coffee", "latte", "espresso", "cappuccino"), "https://images.unsplash.com/photo-1461023058943-07fcbe16d735?w=600&auto=format&fit=crop"),
    (("oat bar", "granola", "cookie", "brownie", "blondie"), "https://images.unsplash.com/photo-1499636136210-6f4ee915583e?w=600&auto=format&fit=crop"),
    (("cake", "pie", "cheesecake"), "https://images.unsplash.com/photo-1578985545062-69928b1d9587?w=600&auto=format&fit=crop"),
    (("donut", "doughnut", "beignet"), "https://images.unsplash.com/photo-1551024601-bec78aea704b?w=600&auto=format&fit=crop"),
    (("sandwich", "panini", "wrap", "bagel", "club"), "https://images.unsplash.com/photo-1528735602780-2552fd8c2fcb?w=600&auto=format&fit=crop"),
    (("fries", "potato", "hash"), "https://images.unsplash.com/photo-1573080496689-91bc8691f4c4?w=600&auto=format&fit=crop"),
    (("rice bowl", "grain bowl", "power bowl"), "https://images.unsplash.com/photo-1512058564366-18510be2db19?w=600&auto=format&fit=crop"),
]

STATION_IMAGE_RULES: list[tuple[tuple[str, ...], str]] = [
    (("grill",), "https://images.unsplash.com/photo-1555939594-58d7cb561ad1?w=600&auto=format&fit=crop"),
    (("dessert", "bakery", "pastry"), "https://images.unsplash.com/photo-1499636136210-6f4ee915583e?w=600&auto=format&fit=crop"),
    (("noodle", "ramen"), "https://images.unsplash.com/photo-1569718212165-3a8278d5f624?w=600&auto=format&fit=crop"),
    (("pizza",), "https://images.unsplash.com/photo-1513104890138-7c749659a591?w=600&auto=format&fit=crop"),
    (("salad",), "https://images.unsplash.com/photo-1512621776951-a57141f2eefd?w=600&auto=format&fit=crop"),
    (("soup",), "https://images.unsplash.com/photo-1547592166-23ac45744acd?w=600&auto=format&fit=crop"),
    (("deli", "sandwich"), "https://images.unsplash.com/photo-1528735602780-2552fd8c2fcb?w=600&auto=format&fit=crop"),
]

DEFAULT_FOOD_IMAGE = "https://images.unsplash.com/photo-1546069901-ba9599a7e63c?w=600&auto=format&fit=crop"


def image_url_for_dish(name: str, station: str = "") -> str:
    dish = name.lower()
    station_hay = station.lower()
    for keys, url in DISH_IMAGE_RULES:
        if any(k in dish for k in keys):
            return url
    for keys, url in STATION_IMAGE_RULES:
        if any(k in station_hay for k in keys):
            return url
    return DEFAULT_FOOD_IMAGE


def price_for_station(station: str) -> int:
    s = station.lower()
    if "soup" in s:
        return 450
    if "dessert" in s or "pastr" in s or "bread" in s or "bakery" in s or "beignet" in s:
        return 350
    if "coffee" in s or "espresso" in s or "tea" in s or "peet" in s:
        return 425
    if "pizza" in s:
        return 899
    if "grill" in s or "burger" in s:
        return 950
    if "sushi" in s or "wasabi" in s or "steak" in s or "seasons" in s:
        return 1095
    if "noodle" in s or "tandoor" in s or "mediterranean" in s or "street" in s or "ginger" in s:
        return 995
    if "deli" in s or "sandwich" in s or "salad" in s:
        return 875
    if "breakfast" in s or "omelet" in s:
        return 795
    if "tamale" in s:
        return 795
    return 875


def normalize_menu_urls(meta: dict) -> list[tuple[str | None, str]]:
    """Return [(optional venue label, url), ...] for a dining location."""
    raw = meta.get("urls") or ([meta["url"]] if "url" in meta else [])
    out: list[tuple[str | None, str]] = []
    for entry in raw:
        if isinstance(entry, (tuple, list)) and len(entry) == 2:
            out.append((str(entry[0]), str(entry[1])))
        else:
            out.append((None, str(entry)))
    return out


def scrape_location_menu(meta: dict) -> tuple[str, list[dict]]:
    """Scrape one or more menu pages and merge stations (with venue prefixes)."""
    max_items = int(meta.get("max_items_per_station", 12))
    merged: list[dict] = []
    meal_used = "Lunch"
    for label, url in normalize_menu_urls(meta):
        html = fetch(url)
        parsed = parse_menu(html)
        meal, stations = pick_active_meal(parsed)
        meal_used = meal
        for st in stations:
            name = st["station"]
            if label:
                # Blue Wall concepts share generic station names (Soups, Pizza…).
                name = f"{label} · {name}"
            merged.append({"station": name, "items": st["items"][:max_items]})
    return meal_used, merged


def tags_to_swift(tags: list[str]) -> str:
    mapping = {
        "vegan": ".vegan",
        "vegetarian": ".vegetarian",
        "gf": ".glutenFree",
        "halal": ".halal",
    }
    parts = [mapping[t] for t in tags if t in mapping]
    if not parts:
        return "[]"
    return "[" + ", ".join(parts) + "]"


def tags_to_sql(tags: list[str]) -> str:
    mapping = {"vegan": "vegan", "vegetarian": "vegetarian", "gf": "gf", "halal": "halal"}
    parts = [mapping[t] for t in tags if t in mapping]
    if not parts:
        return "'{}'"
    return "'{" + ",".join(parts) + "}'"


def sql_escape(s: str) -> str:
    return s.replace("'", "''")


def slugify(s: str) -> str:
    s = s.lower()
    s = re.sub(r"[^a-z0-9]+", "-", s).strip("-")
    return s[:40] or "item"


def swift_menu_name(key: str) -> str:
    parts = key.split("_")
    return parts[0] + "".join(p[:1].upper() + p[1:] for p in parts[1:]) + "Menu"


def write_swift(buildings: list[dict], menus: dict[str, dict]) -> None:
    lines: list[str] = []
    lines.append("// Auto-generated by scripts/scrape_umass.py — do not edit by hand.")
    lines.append("// Re-run: python3 scripts/scrape_umass.py")
    lines.append("import Foundation")
    lines.append("")
    lines.append("enum GeneratedUMassCatalog {")
    lines.append(f'    static let campusId = "{CAMPUS_ID}"')
    lines.append("")
    lines.append("    static let buildings: [Building] = [")
    for b in buildings:
        lines.append(
            "        .init(id: \"{id}\", campusId: campusId, name: \"{name}\", "
            "neighborhood: \"{neigh}\", latitude: {lat}, longitude: {lng}),".format(
                id=b["id"],
                name=b["name"].replace('"', '\\"'),
                neigh=b["neighborhood"],
                lat=b["latitude"],
                lng=b["longitude"],
            )
        )
    lines.append("    ]")
    lines.append("")
    lines.append("    static func menus(for locationId: String) -> [MenuCategory]? {")
    lines.append("        switch locationId {")
    for key, meta in DINING_LOCATIONS.items():
        lines.append(f'        case "{meta["loc_id"]}": return {swift_menu_name(key)}')
    lines.append("        default: return nil")
    lines.append("        }")
    lines.append("    }")
    lines.append("")

    for key, meta in DINING_LOCATIONS.items():
        meal_name = menus[key]["meal"]
        stations = menus[key]["stations"]
        loc = meta["loc_id"]
        prefix = meta["prefix"]
        menu_var = swift_menu_name(key)
        display = key.replace("_", " ").title()
        lines.append(f"    // {display} — scraped {meal_name} menu from UMass Dining")
        lines.append(f"    private static let {menu_var}: [MenuCategory] = [")
        for i, st in enumerate(stations):
            cat_id = f"{prefix}-{slugify(st['station'])}"
            lines.append(
                f'        MenuCategory(id: "{cat_id}", locationId: "{loc}", '
                f'name: "{st["station"].replace(chr(34), chr(92)+chr(34))}", '
                f"sortOrder: {i}, items: ["
            )
            price = price_for_station(st["station"])
            for j, it in enumerate(st["items"]):
                item_id = f"{prefix}-i{i}-{j}"
                name = it["name"].replace("\\", "\\\\").replace('"', '\\"')
                desc = f'From today\\\'s {meal_name.lower()} menu · {st["station"]}'
                desc = desc.replace("\\'", "'")  # use normal apostrophe in Swift string
                # Use Swift string with escaped quotes only
                desc_swift = f"From today's {meal_name.lower()} menu · {st['station']}".replace(
                    '"', '\\"'
                )
                tags = tags_to_swift(it["tags"])
                img = image_url_for_dish(it["name"], st["station"]).replace('"', '\\"')
                lines.append(
                    f'            genItem("{item_id}", "{cat_id}", "{name}", '
                    f'"{desc_swift}", {price}, {tags}, "{img}"),'
                )
            lines.append("        ]),")
        lines.append("    ]")
        lines.append("")

    lines.append("    private static func genItem(")
    lines.append("        _ id: String,")
    lines.append("        _ categoryId: String,")
    lines.append("        _ name: String,")
    lines.append("        _ description: String,")
    lines.append("        _ price: Int,")
    lines.append("        _ tags: [DietaryTag],")
    lines.append("        _ image: String")
    lines.append("    ) -> MenuItem {")
    lines.append("        MenuItem(")
    lines.append("            id: id,")
    lines.append("            categoryId: categoryId,")
    lines.append("            name: name,")
    lines.append("            description: description,")
    lines.append("            priceCents: price,")
    lines.append("            tags: tags,")
    lines.append("            imageURL: URL(string: image),")
    lines.append("            isAvailable: true,")
    lines.append("            customizations: []")
    lines.append("        )")
    lines.append("    }")
    lines.append("}")
    lines.append("")
    OUT_SWIFT.write_text("\n".join(lines))
    print(f"wrote {OUT_SWIFT.relative_to(ROOT)}")


def write_buildings_sql(buildings: list[dict]) -> None:
    lines = [
        "-- Auto-generated by scripts/scrape_umass.py",
        "insert into public.buildings (id, campus_id, name, lat, lng, neighborhood) values",
    ]
    vals = []
    for b in buildings:
        vals.append(
            f"  ('{b['id']}', '{CAMPUS_ID}', '{sql_escape(b['name'])}', "
            f"{b['latitude']}, {b['longitude']}, '{sql_escape(b['neighborhood'])}')"
        )
    lines.append(",\n".join(vals))
    lines.append(
        "on conflict (id) do update set campus_id = excluded.campus_id, name = excluded.name,\n"
        "  lat = excluded.lat, lng = excluded.lng, neighborhood = excluded.neighborhood;"
    )
    OUT_BUILDINGS_SQL.write_text("\n".join(lines) + "\n")
    print(f"wrote {OUT_BUILDINGS_SQL.relative_to(ROOT)} ({len(buildings)} halls)")


def write_menus_sql(menus: dict[str, dict]) -> None:
    """Replace commons categories/items (ids >= seed_cat_base ranges) with scraped data."""
    cat_rows: list[str] = []
    item_rows: list[str] = []
    item_n = 200  # keep clear of legacy 1–43 demo items; scrape uses 200+
    cat_ids_by_loc: dict[str, list[str]] = {}

    for key, meta in DINING_LOCATIONS.items():
        stations = menus[key]["stations"]
        meal = menus[key]["meal"]
        loc = meta["seed_loc"]
        cat_ids: list[str] = []
        for i, st in enumerate(stations):
            cid_n = meta["seed_cat_base"] + i
            cid = category_uuid(cid_n)
            cat_ids.append(cid)
            cat_rows.append(
                f"  ('{cid}', '{loc}', '{sql_escape(st['station'])}', {i + 1})"
            )
            price = price_for_station(st["station"])
            for it in st["items"]:
                eid = item_uuid(item_n)
                item_n += 1
                desc = f"From today's {meal.lower()} menu · {st['station']}"
                img = image_url_for_dish(it["name"], st["station"])
                item_rows.append(
                    f"  ('{eid}', '{cid}', '{sql_escape(it['name'])}', "
                    f"'{sql_escape(desc)}', {price}, {tags_to_sql(it['tags'])}, "
                    f"'{sql_escape(img)}', true)"
                )
        cat_ids_by_loc[loc] = cat_ids

    loc_ids = [f"    '{m['seed_loc']}'" for m in DINING_LOCATIONS.values()]
    loc_list = ",\n".join(loc_ids)
    lines = [
        "-- Auto-generated by scripts/scrape_umass.py",
        "-- Scraped dining menus. Run after base seed.sql if you want live dining data.",
        "begin;",
        "",
        "-- Remove prior scraped categories/items for known dining locations",
        "delete from public.menu_items where category_id in (",
        "  select id from public.menu_categories where location_id in (",
        loc_list,
        "  )",
        ");",
        "delete from public.menu_categories where location_id in (",
        loc_list,
        ");",
        "",
        "insert into public.menu_categories (id, location_id, name, sort_order) values",
        ",\n".join(cat_rows) + ";",
        "",
        "insert into public.menu_items (id, category_id, name, description, price_cents, tags, image_url, is_available) values",
        ",\n".join(item_rows) + ";",
        "",
        "commit;",
    ]
    OUT_MENUS_SQL.write_text("\n".join(lines) + "\n")
    print(
        f"wrote {OUT_MENUS_SQL.relative_to(ROOT)} "
        f"({len(cat_rows)} categories, {len(item_rows)} items)"
    )


def _load_scrape_env() -> tuple[str, str]:
    """Load Supabase URL + service role from env or scripts/.scrape.env."""
    import os

    env_path = ROOT / "scripts" / ".scrape.env"
    if env_path.exists():
        for line in env_path.read_text().splitlines():
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            if line.startswith("export "):
                line = line[len("export ") :]
            name, _, value = line.partition("=")
            value = value.strip().strip('"').strip("'")
            # Prefer file values over empty shell exports.
            os.environ[name.strip()] = value

    base = os.environ.get("SUPABASE_URL", "").rstrip("/")
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
    return base, key


def push_menus_to_supabase(menus: dict[str, dict]) -> None:
    """Upsert scraped dining menus via PostgREST (service role required)."""
    import urllib.error

    base, service_key = _load_scrape_env()
    if not base or not service_key:
        raise SystemExit(
            "Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY to use --push "
            "(Project Settings → API → service_role)."
        )
    print(f"  supabase push → {base} (key len {len(service_key)})")

    def rest(method: str, path: str, body: object | None = None) -> None:
        data = None if body is None else json.dumps(body).encode()
        req = urllib.request.Request(
            f"{base}/rest/v1/{path}",
            data=data,
            method=method,
            headers={
                "User-Agent": UA,
                "apikey": service_key,
                "Authorization": f"Bearer {service_key}",
                "Content-Type": "application/json",
                "Prefer": (
                    "resolution=merge-duplicates,return=minimal"
                    if method == "POST"
                    else "return=minimal"
                ),
            },
        )
        try:
            with urllib.request.urlopen(req, timeout=60, context=CTX) as resp:
                resp.read()
        except urllib.error.HTTPError as e:
            raise RuntimeError(f"{method} {path} → {e.code}: {e.read()[:400]!r}") from e

    def get_json(path: str):
        req = urllib.request.Request(
            f"{base}/rest/v1/{path}",
            headers={
                "User-Agent": UA,
                "apikey": service_key,
                "Authorization": f"Bearer {service_key}",
            },
        )
        with urllib.request.urlopen(req, timeout=60, context=CTX) as resp:
            return json.loads(resp.read().decode() or "[]")

    # Keep Cosmic Cafe → Terrace rename in sync for already-seeded projects.
    terrace_id = DINING_LOCATIONS["terrace"]["seed_loc"]
    try:
        rest(
            "PATCH",
            f"dining_locations?id=eq.{terrace_id}",
            {
                "name": "Terrace",
                "lat": 42.3889,
                "lng": -72.5294,
                "busy_level": "medium",
                "hours": {
                    "mon": [["08:00", "20:00"]],
                    "tue": [["08:00", "20:00"]],
                    "wed": [["08:00", "20:00"]],
                    "thu": [["08:00", "20:00"]],
                    "fri": [["08:00", "20:00"]],
                    "sat": [["10:00", "18:00"]],
                    "sun": [["10:00", "18:00"]],
                },
            },
        )
        print("  renamed location → Terrace")
    except RuntimeError as e:
        print(f"  skip Terrace rename ({e})")

    item_n = 200
    for loc_key, meta in DINING_LOCATIONS.items():
        loc = meta["seed_loc"]
        stations = menus[loc_key]["stations"]
        meal = menus[loc_key]["meal"]

        existing = get_json(f"menu_categories?location_id=eq.{loc}&select=id")
        for row in existing:
            rest("DELETE", f"menu_items?category_id=eq.{row['id']}")
        rest("DELETE", f"menu_categories?location_id=eq.{loc}")

        cats = [
            {
                "id": category_uuid(meta["seed_cat_base"] + i),
                "location_id": loc,
                "name": st["station"],
                "sort_order": i + 1,
            }
            for i, st in enumerate(stations)
        ]
        if cats:
            rest("POST", "menu_categories", cats)

        items = []
        for i, st in enumerate(stations):
            price = price_for_station(st["station"])
            cid = category_uuid(meta["seed_cat_base"] + i)
            for it in st["items"]:
                items.append(
                    {
                        "id": item_uuid(item_n),
                        "category_id": cid,
                        "name": it["name"],
                        "description": f"From today's {meal.lower()} menu · {st['station']}",
                        "price_cents": price,
                        "tags": it["tags"],
                        "image_url": image_url_for_dish(it["name"], st["station"]),
                        "is_available": True,
                    }
                )
                item_n += 1
        if items:
            for start in range(0, len(items), 80):
                rest("POST", "menu_items", items[start : start + 80])
        print(f"  pushed {loc_key}: {len(cats)} categories, {len(items)} items")


def main() -> None:
    import argparse

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--push",
        action="store_true",
        help="Also upsert menus into Supabase (needs SUPABASE_SERVICE_ROLE_KEY).",
    )
    args = parser.parse_args()

    print("Fetching residence directory…")
    residences_html = fetch(RESIDENCE_URL)
    buildings = scrape_residences(residences_html)
    print(f"  {len(buildings)} halls")

    menus: dict[str, dict] = {}
    for key, meta in DINING_LOCATIONS.items():
        print(f"Fetching {key} menu…")
        meal, stations = scrape_location_menu(meta)
        menus[key] = {"meal": meal, "stations": stations}
        n = sum(len(s["items"]) for s in stations)
        print(f"  {meal}: {len(stations)} stations, {n} items")

    write_swift(buildings, menus)
    write_buildings_sql(buildings)
    write_menus_sql(menus)

    if args.push:
        print("Pushing menus to Supabase…")
        push_menus_to_supabase(menus)

    meta_path = ROOT / "scripts" / "last_scrape.json"
    meta_path.write_text(
        json.dumps(
            {
                "buildings": len(buildings),
                "menus": {
                    k: {
                        "meal": v["meal"],
                        "stations": len(v["stations"]),
                        "items": sum(len(s["items"]) for s in v["stations"]),
                    }
                    for k, v in menus.items()
                },
            },
            indent=2,
        )
        + "\n"
    )
    print("done.")


if __name__ == "__main__":
    main()
