-- Ensure Connect account id column exists. Only service_role writes it.
alter table public.profiles
  add column if not exists stripe_account_id text;

comment on column public.profiles.stripe_account_id is
  'Stripe Connect Express account id (acct_…). Set by edge function, not by clients.';

-- Keep clients from updating stripe_account_id (column-level grants).
-- Re-assert the safe update list without stripe_account_id.
revoke update on public.profiles from authenticated;
grant update (
  campus_id, full_name, phone, home_building_id, is_runner, vehicle_type, avatar_url, push_token
) on public.profiles to authenticated;
