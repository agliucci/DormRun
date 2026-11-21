# DormRun

Campus food delivery — students order, student runners deliver. First campus: **UMass Amherst**. New colleges are data, not code.

## Run

1. Open `College Eats.xcodeproj` in Xcode (home-screen name is **DormRun**).
2. Prefer a **physical iPhone** for Live Activities, APNs, and runner GPS.
3. Sign in with `@umass.edu`.
4. Home → order → track (live runner GPS). Chat with your runner from tracking. Rate after delivery.

## Always-on menu scrape (published app)

Menus refresh from umassdining.com into Supabase every **3 hours** via GitHub Actions on [agliucci/DormRun](https://github.com/agliucci/DormRun) — independent of your Mac and of App Store publishes.

**One-time setup (required for cloud push):**

1. Open Supabase → **SQL Editor**
2. Paste and run `supabase/ONE_SHOT_MENU_AND_CHAT.sql`
3. Manually trigger the workflow once:
   ```bash
   gh workflow run "Scrape UMass menus"
   ```

Local Mac LaunchAgent still works as a backup (`./scripts/install_menu_scrape_launchd.sh`).

## Security note

If a `service_role` key was pasted into chat, rotate it in Supabase → Project Settings → API, update `scripts/.scrape.env`, and re-run:
`printf '%s' "$SUPABASE_SERVICE_ROLE_KEY" | gh secret set SUPABASE_SERVICE_ROLE_KEY`

## Features

- Live runner GPS on the customer tracking map
- Rate & review runners after delivery
- In-app chat between customer and runner
- Dining menus scraped from UMass Dining on a schedule
