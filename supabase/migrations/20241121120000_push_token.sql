-- APNs device token storage on profiles
alter table public.profiles
  add column if not exists push_token text;

comment on column public.profiles.push_token is 'APNs device token hex string for order status pushes';
