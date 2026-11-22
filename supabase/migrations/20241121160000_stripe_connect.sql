-- Optional Stripe Connect account id for runner payouts.
alter table public.profiles
  add column if not exists stripe_account_id text;

comment on column public.profiles.stripe_account_id is
  'Stripe Connect Express account id for runner payouts (set by create-connect-account-link).';
