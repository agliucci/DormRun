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

**GitHub Actions secrets are not public** — only the workflow can read them. Your repo can stay private.

Still rotate `service_role` if it was pasted into chat:
1. Supabase → Project Settings → API → **Regenerate** `service_role`
2. Update local `scripts/.scrape.env`
3. `printf '%s' 'NEW_SERVICE_ROLE_KEY' | gh secret set SUPABASE_SERVICE_ROLE_KEY`

Safe in the app: Supabase **anon** key + Stripe **publishable** (`pk_`) key.  
Never put in the app or git: `service_role`, Stripe **secret** (`sk_`).

## Stripe + Apple Pay

1. Create a [Stripe](https://dashboard.stripe.com) account (test mode is fine).
2. Put `pk_test_…` (or `pk_live_…` for real money) in gitignored `Config.xcconfig` as `STRIPE_PUBLISHABLE_KEY`.
3. Set secrets on Supabase only (never in the app):
   ```bash
   supabase secrets set STRIPE_SECRET_KEY=sk_test_…   # or sk_live_…
   supabase secrets set STRIPE_WEBHOOK_SECRET=whsec_…
   supabase functions deploy create-payment-intent create-connect-account-link create-cash-out transition-order
   supabase functions deploy stripe-webhook --no-verify-jwt
   ```
4. Run `supabase/ONE_SHOT_ORDERS_PAYMENTS.sql` in the SQL editor (live multi-device orders + payout columns).
5. Stripe Dashboard → Webhooks → `https://<project>.supabase.co/functions/v1/stripe-webhook`  
   Events: `payment_intent.succeeded`, `payment_intent.payment_failed`, `payment_intent.canceled`, `charge.refunded`.
6. Xcode → Add Package → `https://github.com/stripe/stripe-ios` → product **StripePaymentSheet**.
7. Apple Developer → Merchants → Merchant ID → enable **Apple Pay** → set `STRIPE_MERCHANT_ID`.

**Live mode:** switch Dashboard to Live, put `pk_live` / `sk_live` in place, redeploy secrets, and **re-link Connect banks** (test accounts don’t carry over). Cash out uses Stripe Transfers to the runner’s Connect account.

Until publishable + secret keys are set, Place order still succeeds in **stub mode**.

## TestFlight

See [docs/TESTFLIGHT.md](docs/TESTFLIGHT.md) for archive, two-phone GPS / Live Activity / Apple Pay / push pass.

## Features

- Live runner GPS on the customer tracking map
- Rate & review runners after delivery
- In-app chat between customer and runner
- Dining menus scraped from UMass Dining on a schedule
