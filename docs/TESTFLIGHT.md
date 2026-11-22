# TestFlight checklist (real-device pass)

Ship a build that exercises GPS, Live Activities, Apple Pay, and push on two phones.

## Before archive

1. Run `supabase/ONE_SHOT_ORDERS_PAYMENTS.sql` in the Supabase SQL editor.
2. Deploy edge functions:
   ```bash
   supabase functions deploy create-payment-intent create-connect-account-link create-cash-out transition-order
   supabase functions deploy stripe-webhook --no-verify-jwt
   ```
3. Live Stripe (Dashboard → **Live** mode):
   - Put `pk_live_…` in gitignored `Config.xcconfig` as `STRIPE_PUBLISHABLE_KEY`
   - `supabase secrets set STRIPE_SECRET_KEY=sk_live_…`
   - `supabase secrets set STRIPE_WEBHOOK_SECRET=whsec_…` (from Stripe webhook endpoint)
   - Webhook URL: `https://<project>.supabase.co/functions/v1/stripe-webhook`
   - Events: `payment_intent.succeeded`, `payment_intent.payment_failed`, `payment_intent.canceled`, `charge.refunded`
4. Re-link runner bank accounts in **live** Connect (test accounts do not carry over).
5. Apple Developer:
   - Push Notifications capability
   - App Groups + Live Activities
   - Apple Pay merchant id matches `STRIPE_MERCHANT_ID`
6. Bump `CURRENT_PROJECT_VERSION` for each TestFlight upload (Xcode or `project.xcproj`).

## Archive & upload

1. Xcode → Any iOS Device → Product → Archive
2. Distribute App → App Store Connect → Upload
3. App Store Connect → TestFlight → add internal testers
4. Install on **two physical iPhones** (customer + runner)

## Device pass

| Area | What to verify |
|------|----------------|
| Auth | Two `@umass.edu` accounts, OTP works |
| Place order | Customer pays with Apple Pay / card (live or test); order appears in Supabase `orders` |
| Accept | Runner sees job on other phone, accepts |
| GPS | Customer map updates while runner moves |
| Live Activity | Lock screen updates on status changes |
| Chat | Messages sync both ways |
| Handoff | Customer sees 4-digit PIN; runner enters it to complete |
| Push | Status change notification (if APNs key uploaded) |
| Cash out | Runner linked bank → Cash out creates Stripe Transfer |

## Notes

- Simulator is not enough for Live Activities, background GPS, Apple Pay, or push.
- Same Apple ID cannot accept its own order (`runner_id <> customer_id`).
- Keep `sk_live` / `service_role` / webhook secrets out of git and the app binary.
