-- Paste into Supabase SQL Editor once (idempotent).
-- Enables live multi-device orders + Stripe payment/payout columns.

alter table public.orders
  add column if not exists fulfillment_mode text not null default 'retail_purchase';

alter table public.orders
  drop constraint if exists orders_fulfillment_mode_check;
alter table public.orders
  add constraint orders_fulfillment_mode_check
  check (fulfillment_mode in ('retail_purchase', 'meal_swipe'));

alter table public.orders
  add column if not exists runner_meal_bump_cents int not null default 0;

alter table public.orders
  add column if not exists payment_intent_id text;

alter table public.orders
  add column if not exists payment_status text not null default 'pending';

alter table public.orders
  drop constraint if exists orders_payment_status_check;
alter table public.orders
  add constraint orders_payment_status_check
  check (payment_status in ('pending', 'succeeded', 'failed', 'refunded', 'unpaid'));

alter table public.orders
  add column if not exists runner_paid_out_at timestamptz;

alter table public.orders
  add column if not exists runner_transfer_id text;

create index if not exists orders_payment_intent_id_idx
  on public.orders (payment_intent_id)
  where payment_intent_id is not null;

create index if not exists orders_runner_unpaid_idx
  on public.orders (runner_id, status)
  where status = 'delivered' and runner_paid_out_at is null;

revoke all on public.orders from anon, authenticated;
grant select (
  id, customer_id, runner_id, location_id, dropoff_building_id, dropoff_note, status,
  subtotal_cents, delivery_fee_cents, tip_cents,
  fulfillment_mode, runner_meal_bump_cents,
  payment_intent_id, payment_status, runner_paid_out_at, runner_transfer_id,
  placed_at, accepted_at, at_pickup_at, picked_up_at, en_route_at,
  delivered_at, cancelled_at, cancel_reason
) on public.orders to authenticated;

grant insert (
  customer_id, location_id, dropoff_building_id, dropoff_note,
  subtotal_cents, delivery_fee_cents, tip_cents,
  fulfillment_mode, runner_meal_bump_cents,
  payment_intent_id, payment_status
) on public.orders to authenticated;
