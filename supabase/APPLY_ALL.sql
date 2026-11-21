-- UMass Eats: apply once in Supabase SQL Editor
-- Project: mnlzekxetlbxslxtaluz

-- UMass Eats: initial schema
-- Tables, RLS, order state machine, stale-order cleanup.

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table public.campuses (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  name text not null,
  edu_email_domains text[] not null default '{}',
  created_at timestamptz not null default now()
);

create table public.buildings (
  id uuid primary key default gen_random_uuid(),
  campus_id uuid not null references public.campuses(id) on delete cascade,
  name text not null,
  lat double precision not null,
  lng double precision not null,
  neighborhood text
);

create table public.dining_locations (
  id uuid primary key default gen_random_uuid(),
  campus_id uuid not null references public.campuses(id) on delete cascade,
  name text not null,
  type text not null check (type in ('commons', 'retail')),
  hours jsonb not null default '{}'::jsonb,
  lat double precision not null,
  lng double precision not null,
  image_url text,
  busy_level text not null default 'medium' check (busy_level in ('low', 'medium', 'high'))
);

create table public.menu_categories (
  id uuid primary key default gen_random_uuid(),
  location_id uuid not null references public.dining_locations(id) on delete cascade,
  name text not null,
  sort_order int not null default 0
);

create table public.menu_items (
  id uuid primary key default gen_random_uuid(),
  category_id uuid not null references public.menu_categories(id) on delete cascade,
  name text not null,
  description text,
  price_cents int not null check (price_cents >= 0),
  tags text[] not null default '{}',
  image_url text,
  is_available boolean not null default true
);

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  campus_id uuid references public.campuses(id),
  full_name text,
  phone text,
  home_building_id uuid references public.buildings(id) on delete set null,
  is_runner boolean not null default false,
  vehicle_type text,
  rating numeric(3, 2) not null default 5,
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.orders (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.profiles(id),
  runner_id uuid references public.profiles(id),
  location_id uuid not null references public.dining_locations(id),
  dropoff_building_id uuid not null references public.buildings(id),
  dropoff_note text,
  status text not null default 'placed'
    check (status in ('placed', 'accepted', 'at_pickup', 'picked_up', 'en_route', 'delivered', 'cancelled')),
  subtotal_cents int not null check (subtotal_cents >= 0),
  delivery_fee_cents int not null default 0 check (delivery_fee_cents >= 0),
  tip_cents int not null default 0 check (tip_cents >= 0),
  -- Shown to the customer, entered by the runner to complete delivery.
  handoff_code char(4) not null default lpad((floor(random() * 10000))::int::text, 4, '0'),
  placed_at timestamptz not null default now(),
  accepted_at timestamptz,
  at_pickup_at timestamptz,
  picked_up_at timestamptz,
  en_route_at timestamptz,
  delivered_at timestamptz,
  cancelled_at timestamptz,
  cancel_reason text,
  constraint orders_runner_not_customer check (runner_id is null or runner_id <> customer_id)
);

create table public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  menu_item_id uuid references public.menu_items(id) on delete set null,
  name text not null,
  unit_price_cents int not null check (unit_price_cents >= 0),
  quantity int not null default 1 check (quantity > 0),
  customizations jsonb not null default '{}'::jsonb,
  special_instructions text
);

create table public.runner_locations (
  runner_id uuid primary key references public.profiles(id) on delete cascade,
  order_id uuid references public.orders(id) on delete set null,
  lat double precision not null,
  lng double precision not null,
  updated_at timestamptz not null default now()
);

create table public.ratings (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null unique references public.orders(id) on delete cascade,
  from_user_id uuid not null references public.profiles(id),
  to_user_id uuid not null references public.profiles(id),
  stars int not null check (stars between 1 and 5),
  comment text,
  created_at timestamptz not null default now(),
  constraint ratings_not_self check (from_user_id <> to_user_id)
);

-- ---------------------------------------------------------------------------
-- Indexes
-- ---------------------------------------------------------------------------

create index buildings_campus_id_idx on public.buildings (campus_id);
create index dining_locations_campus_id_idx on public.dining_locations (campus_id);
create index menu_categories_location_id_idx on public.menu_categories (location_id);
create index menu_items_category_id_idx on public.menu_items (category_id);
create index profiles_campus_id_idx on public.profiles (campus_id);
create index orders_status_idx on public.orders (status);
create index orders_runner_id_idx on public.orders (runner_id);
create index orders_customer_id_idx on public.orders (customer_id);
create index orders_location_id_idx on public.orders (location_id);
create index orders_open_placed_idx on public.orders (placed_at) where status = 'placed';
create index order_items_order_id_idx on public.order_items (order_id);
create index runner_locations_order_id_idx on public.runner_locations (order_id);
create index ratings_to_user_id_idx on public.ratings (to_user_id);

-- ---------------------------------------------------------------------------
-- Helpers / triggers
-- ---------------------------------------------------------------------------

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

create trigger runner_locations_set_updated_at
  before update on public.runner_locations
  for each row execute function public.set_updated_at();

-- Create a profile on signup, matching campus by the email's domain
-- (e.g. someone@umass.edu -> umass-amherst). campus_id stays null if no match.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_domain text := lower(split_part(coalesce(new.email, ''), '@', 2));
  v_campus uuid;
begin
  select c.id into v_campus
  from public.campuses c
  where v_domain = any (c.edu_email_domains)
  limit 1;

  insert into public.profiles (id, campus_id, full_name)
  values (new.id, v_campus, new.raw_user_meta_data ->> 'full_name')
  on conflict (id) do nothing;

  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Keep profiles.rating = average of stars received.
create or replace function public.refresh_profile_rating()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.profiles p
  set rating = coalesce((select round(avg(r.stars)::numeric, 2) from public.ratings r where r.to_user_id = new.to_user_id), 5)
  where p.id = new.to_user_id;
  return new;
end;
$$;

create trigger ratings_refresh_profile_rating
  after insert or update on public.ratings
  for each row execute function public.refresh_profile_rating();

-- RLS helper predicates (security definer so policies don't recurse).
create or replace function public.is_runner(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select is_runner from public.profiles where id = p_user_id), false);
$$;

create or replace function public.user_campus_id(p_user_id uuid)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select campus_id from public.profiles where id = p_user_id;
$$;

-- True if auth.uid() is the customer or runner of the order.
create or replace function public.is_order_participant(p_order_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.orders o
    where o.id = p_order_id
      and (o.customer_id = auth.uid() or o.runner_id = auth.uid())
  );
$$;

-- ---------------------------------------------------------------------------
-- Row level security
-- ---------------------------------------------------------------------------

alter table public.campuses enable row level security;
alter table public.buildings enable row level security;
alter table public.dining_locations enable row level security;
alter table public.menu_categories enable row level security;
alter table public.menu_items enable row level security;
alter table public.profiles enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.runner_locations enable row level security;
alter table public.ratings enable row level security;

-- Public read-only reference data.
create policy campuses_public_read on public.campuses for select using (true);
create policy buildings_public_read on public.buildings for select using (true);
create policy dining_locations_public_read on public.dining_locations for select using (true);
create policy menu_categories_public_read on public.menu_categories for select using (true);
create policy menu_items_public_read on public.menu_items for select using (true);

-- profiles: own row, or the other party on a non-final order.
create policy profiles_select_own on public.profiles
  for select to authenticated
  using (id = auth.uid());

create policy profiles_select_order_counterparty on public.profiles
  for select to authenticated
  using (
    exists (
      select 1 from public.orders o
      where o.status not in ('delivered', 'cancelled')
        and (
          (o.customer_id = auth.uid() and o.runner_id = profiles.id)
          or (o.runner_id = auth.uid() and o.customer_id = profiles.id)
        )
    )
  );

create policy profiles_insert_own on public.profiles
  for insert to authenticated
  with check (id = auth.uid());

create policy profiles_update_own on public.profiles
  for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

-- orders: participants can read; runners on the same campus can also browse
-- open ('placed') orders to accept them. Insert as customer only; all later
-- changes go through transition_order_status().
create policy orders_select_participant on public.orders
  for select to authenticated
  using (customer_id = auth.uid() or runner_id = auth.uid());

create policy orders_select_open_for_runners on public.orders
  for select to authenticated
  using (
    status = 'placed'
    and runner_id is null
    and public.is_runner(auth.uid())
    and exists (
      select 1 from public.dining_locations d
      where d.id = orders.location_id
        and d.campus_id = public.user_campus_id(auth.uid())
    )
  );

create policy orders_insert_as_customer on public.orders
  for insert to authenticated
  with check (
    customer_id = auth.uid()
    and runner_id is null
    and status = 'placed'
  );

-- (No update/delete policies on orders: updates happen via SECURITY DEFINER functions.)

-- order_items: visible to order participants; customer may add items while placed.
create policy order_items_select_participant on public.order_items
  for select to authenticated
  using (public.is_order_participant(order_id));

create policy order_items_select_open_for_runners on public.order_items
  for select to authenticated
  using (
    exists (
      select 1 from public.orders o
      where o.id = order_items.order_id
        and o.status = 'placed'
        and o.runner_id is null
        and public.is_runner(auth.uid())
    )
  );

create policy order_items_insert_customer on public.order_items
  for insert to authenticated
  with check (
    exists (
      select 1 from public.orders o
      where o.id = order_items.order_id
        and o.customer_id = auth.uid()
        and o.status = 'placed'
    )
  );

-- runner_locations: runner manages own row; the customer of the runner's order can read.
create policy runner_locations_select on public.runner_locations
  for select to authenticated
  using (
    runner_id = auth.uid()
    or exists (
      select 1 from public.orders o
      where o.customer_id = auth.uid()
        and o.runner_id = runner_locations.runner_id
        and o.status in ('accepted', 'at_pickup', 'picked_up', 'en_route')
    )
  );

create policy runner_locations_insert_own on public.runner_locations
  for insert to authenticated
  with check (runner_id = auth.uid() and public.is_runner(auth.uid()));

create policy runner_locations_update_own on public.runner_locations
  for update to authenticated
  using (runner_id = auth.uid())
  with check (runner_id = auth.uid());

create policy runner_locations_delete_own on public.runner_locations
  for delete to authenticated
  using (runner_id = auth.uid());

-- ratings: participants of the order can read; rate the counterparty after delivery.
create policy ratings_select on public.ratings
  for select to authenticated
  using (from_user_id = auth.uid() or to_user_id = auth.uid());

create policy ratings_insert_after_delivery on public.ratings
  for insert to authenticated
  with check (
    from_user_id = auth.uid()
    and exists (
      select 1 from public.orders o
      where o.id = ratings.order_id
        and o.status = 'delivered'
        and (
          (o.customer_id = auth.uid() and o.runner_id = ratings.to_user_id)
          or (o.runner_id = auth.uid() and o.customer_id = ratings.to_user_id)
        )
    )
  );

-- ---------------------------------------------------------------------------
-- Table privileges
-- ---------------------------------------------------------------------------
-- RLS is row-level only. We additionally lock down columns that clients must
-- not touch directly:
--   * orders.handoff_code is NOT readable by clients (otherwise the runner could
--     read it and skip the customer). Customers fetch it via get_handoff_code().
--     => iOS must select explicit columns on `orders`, not `*`.
--   * profiles.rating is maintained by trigger only.

revoke all on public.orders from anon, authenticated;
grant select (
  id, customer_id, runner_id, location_id, dropoff_building_id, dropoff_note, status,
  subtotal_cents, delivery_fee_cents, tip_cents, placed_at, accepted_at, at_pickup_at,
  picked_up_at, en_route_at, delivered_at, cancelled_at, cancel_reason
) on public.orders to authenticated;
grant insert (
  customer_id, location_id, dropoff_building_id, dropoff_note,
  subtotal_cents, delivery_fee_cents, tip_cents
) on public.orders to authenticated;

revoke update on public.profiles from authenticated;
grant update (campus_id, full_name, phone, home_building_id, is_runner, vehicle_type, avatar_url)
  on public.profiles to authenticated;

-- ---------------------------------------------------------------------------
-- Order state machine
-- ---------------------------------------------------------------------------
-- placed -> accepted -> at_pickup -> picked_up -> en_route -> delivered
-- cancelled: from 'placed' by the customer, or by the system (actor null /
-- service role) from any non-final state.
--
-- p_actor_id: the acting user. When called with a user JWT, it must equal
-- auth.uid(). Execute is only granted to authenticated and service_role; with
-- the service role (auth.uid() is null) the supplied actor is trusted; pass
-- null for system actions. Returns the updated order as jsonb (no handoff_code).

create or replace function public.transition_order_status(
  p_order_id uuid,
  p_new_status text,
  p_actor_id uuid,
  p_handoff_code text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders;
  v_now timestamptz := now();
  v_caller uuid := auth.uid();
  v_is_system boolean := false;
begin
  if p_new_status not in ('accepted', 'at_pickup', 'picked_up', 'en_route', 'delivered', 'cancelled') then
    raise exception 'Invalid target status: %', p_new_status using errcode = '22023';
  end if;

  -- Never let a client impersonate another user.
  if v_caller is not null and p_actor_id is distinct from v_caller then
    raise exception 'Actor does not match authenticated user' using errcode = '42501';
  end if;
  v_is_system := (p_actor_id is null);

  select * into v_order from public.orders where id = p_order_id for update;
  if not found then
    raise exception 'Order not found' using errcode = 'P0002';
  end if;

  if v_order.status in ('delivered', 'cancelled') then
    raise exception 'Order is already %', v_order.status using errcode = '22023';
  end if;

  case p_new_status
    when 'cancelled' then
      if v_is_system then
        update public.orders
        set status = 'cancelled', cancelled_at = v_now,
            cancel_reason = coalesce(cancel_reason, 'system')
        where id = p_order_id
        returning * into v_order;
      else
        if p_actor_id <> v_order.customer_id then
          raise exception 'Only the customer can cancel an order' using errcode = '42501';
        end if;
        if v_order.status <> 'placed' then
          raise exception 'Order can only be cancelled while placed (currently %)', v_order.status
            using errcode = '22023';
        end if;
        update public.orders
        set status = 'cancelled', cancelled_at = v_now,
            cancel_reason = coalesce(cancel_reason, 'customer_cancelled')
        where id = p_order_id
        returning * into v_order;
      end if;

    when 'accepted' then
      if v_order.status <> 'placed' then
        raise exception 'Invalid transition % -> accepted', v_order.status using errcode = '22023';
      end if;
      if v_is_system or not public.is_runner(p_actor_id) then
        raise exception 'Only a runner can accept an order' using errcode = '42501';
      end if;
      if p_actor_id = v_order.customer_id then
        raise exception 'You cannot accept your own order' using errcode = '42501';
      end if;
      if public.user_campus_id(p_actor_id) is distinct from
         (select d.campus_id from public.dining_locations d where d.id = v_order.location_id) then
        raise exception 'Runner is not on this order''s campus' using errcode = '42501';
      end if;
      update public.orders
      set status = 'accepted', runner_id = p_actor_id, accepted_at = v_now
      where id = p_order_id
      returning * into v_order;

    when 'at_pickup', 'picked_up', 'en_route', 'delivered' then
      if (p_new_status = 'at_pickup' and v_order.status <> 'accepted')
         or (p_new_status = 'picked_up' and v_order.status <> 'at_pickup')
         or (p_new_status = 'en_route' and v_order.status <> 'picked_up')
         or (p_new_status = 'delivered' and v_order.status <> 'en_route') then
        raise exception 'Invalid transition % -> %', v_order.status, p_new_status using errcode = '22023';
      end if;

      if v_is_system or p_actor_id is distinct from v_order.runner_id then
        raise exception 'Only the assigned runner can update this order' using errcode = '42501';
      end if;

      if p_new_status = 'delivered' then
        if p_handoff_code is null or p_handoff_code <> v_order.handoff_code then
          raise exception 'Invalid or missing handoff code' using errcode = '22023';
        end if;
      end if;

      update public.orders
      set status = p_new_status,
          at_pickup_at = case when p_new_status = 'at_pickup' then v_now else at_pickup_at end,
          picked_up_at = case when p_new_status = 'picked_up' then v_now else picked_up_at end,
          en_route_at  = case when p_new_status = 'en_route'  then v_now else en_route_at end,
          delivered_at = case when p_new_status = 'delivered' then v_now else delivered_at end
      where id = p_order_id
      returning * into v_order;

      if p_new_status = 'delivered' then
        delete from public.runner_locations where order_id = p_order_id;
      end if;
  end case;

  -- handoff_code is deliberately stripped so the runner never sees it.
  return to_jsonb(v_order) - 'handoff_code';
end;
$$;

revoke all on function public.transition_order_status(uuid, text, uuid, text) from public, anon;
grant execute on function public.transition_order_status(uuid, text, uuid, text) to authenticated, service_role;

-- Customer-only accessor for the handoff code.
create or replace function public.get_handoff_code(p_order_id uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select o.handoff_code::text
  from public.orders o
  where o.id = p_order_id and o.customer_id = auth.uid();
$$;

revoke all on function public.get_handoff_code(uuid) from public, anon;
grant execute on function public.get_handoff_code(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Timeout: cancel orders with no runner after 20 minutes.
-- Schedule with pg_cron (see README) or call from a scheduled edge function.
-- ---------------------------------------------------------------------------

create or replace function public.cancel_stale_orders()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
begin
  with cancelled as (
    update public.orders
    set status = 'cancelled',
        cancelled_at = now(),
        cancel_reason = 'timeout_no_runner'
    where status = 'placed'
      and runner_id is null
      and placed_at < now() - interval '20 minutes'
    returning id
  )
  select count(*) into v_count from cancelled;

  return v_count;
end;
$$;

revoke all on function public.cancel_stale_orders() from public, anon, authenticated;
grant execute on function public.cancel_stale_orders() to service_role;

-- ---- push_token ----

-- APNs device token storage on profiles
alter table public.profiles
  add column if not exists push_token text;

comment on column public.profiles.push_token is 'APNs device token hex string for order status pushes';

-- ---- seed ----

-- UMass Eats seed data: UMass Amherst
--
-- Deterministic: every row uses a fixed UUID, so the seed is idempotent
-- (re-running upserts via ON CONFLICT). UUID prefixes:
--   a... campus, b... buildings, d... dining locations,
--   c... menu categories, e... menu items
--
-- Coordinates, dining hours, and menu items are APPROXIMATE / illustrative,
-- not official UMass Dining data. Replace with real data before launch.
-- Generated by a script; edit freely.

begin;

insert into public.campuses (id, slug, name, edu_email_domains) values
  ('a0000000-0000-4000-8000-000000000001', 'umass-amherst', 'UMass Amherst', '{umass.edu}')
on conflict (id) do update set slug = excluded.slug, name = excluded.name,
  edu_email_domains = excluded.edu_email_domains;

-- Buildings (residence halls grouped by residential area)
insert into public.buildings (id, campus_id, name, lat, lng, neighborhood) values
  ('b0000000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-000000000001', 'Kennedy', 42.3875, -72.5330, 'Southwest'),
  ('b0000000-0000-4000-8000-000000000002', 'a0000000-0000-4000-8000-000000000001', 'John Quincy Adams', 42.3881, -72.5322, 'Southwest'),
  ('b0000000-0000-4000-8000-000000000003', 'a0000000-0000-4000-8000-000000000001', 'Coolidge', 42.3870, -72.5321, 'Southwest'),
  ('b0000000-0000-4000-8000-000000000004', 'a0000000-0000-4000-8000-000000000001', 'Washington', 42.3884, -72.5336, 'Southwest'),
  ('b0000000-0000-4000-8000-000000000005', 'a0000000-0000-4000-8000-000000000001', 'Pierpont', 42.3867, -72.5337, 'Southwest'),
  ('b0000000-0000-4000-8000-000000000006', 'a0000000-0000-4000-8000-000000000001', 'Field', 42.3925, -72.5365, 'Orchard Hill'),
  ('b0000000-0000-4000-8000-000000000007', 'a0000000-0000-4000-8000-000000000001', 'Webster', 42.3931, -72.5357, 'Orchard Hill'),
  ('b0000000-0000-4000-8000-000000000008', 'a0000000-0000-4000-8000-000000000001', 'Dickinson', 42.3920, -72.5356, 'Orchard Hill'),
  ('b0000000-0000-4000-8000-000000000009', 'a0000000-0000-4000-8000-000000000001', 'Van Meter', 42.3895, -72.5255, 'Central'),
  ('b0000000-0000-4000-8000-000000000010', 'a0000000-0000-4000-8000-000000000001', 'Brett', 42.3901, -72.5247, 'Central'),
  ('b0000000-0000-4000-8000-000000000011', 'a0000000-0000-4000-8000-000000000001', 'Crabtree', 42.3965, -72.5225, 'Northeast'),
  ('b0000000-0000-4000-8000-000000000012', 'a0000000-0000-4000-8000-000000000001', 'Knowlton', 42.3971, -72.5217, 'Northeast'),
  ('b0000000-0000-4000-8000-000000000013', 'a0000000-0000-4000-8000-000000000001', 'Cashin', 42.3945, -72.5180, 'Sylvan'),
  ('b0000000-0000-4000-8000-000000000014', 'a0000000-0000-4000-8000-000000000001', 'Brown', 42.3951, -72.5172, 'Sylvan'),
  ('b0000000-0000-4000-8000-000000000015', 'a0000000-0000-4000-8000-000000000001', 'Oak', 42.3915, -72.5195, 'Commonwealth Honors College'),
  ('b0000000-0000-4000-8000-000000000016', 'a0000000-0000-4000-8000-000000000001', 'Elm', 42.3921, -72.5187, 'Commonwealth Honors College'),
  ('b0000000-0000-4000-8000-000000000017', 'a0000000-0000-4000-8000-000000000001', 'Maple', 42.3910, -72.5186, 'Commonwealth Honors College'),
  ('b0000000-0000-4000-8000-000000000018', 'a0000000-0000-4000-8000-000000000001', 'Linden', 42.3924, -72.5201, 'Commonwealth Honors College')
on conflict (id) do update set campus_id = excluded.campus_id, name = excluded.name,
  lat = excluded.lat, lng = excluded.lng, neighborhood = excluded.neighborhood;

-- Dining locations
insert into public.dining_locations (id, campus_id, name, type, hours, lat, lng, image_url, busy_level) values
  ('d0000000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-000000000001', 'Worcester Dining Commons', 'commons', '{"mon":[["07:00","21:00"]],"tue":[["07:00","21:00"]],"wed":[["07:00","21:00"]],"thu":[["07:00","21:00"]],"fri":[["07:00","21:00"]],"sat":[["07:00","21:00"]],"sun":[["07:00","21:00"]]}'::jsonb, 42.3922, -72.5236, null, 'high'),
  ('d0000000-0000-4000-8000-000000000002', 'a0000000-0000-4000-8000-000000000001', 'Franklin Dining Commons', 'commons', '{"mon":[["07:00","10:30"],["11:00","14:30"],["16:30","20:30"]],"tue":[["07:00","10:30"],["11:00","14:30"],["16:30","20:30"]],"wed":[["07:00","10:30"],["11:00","14:30"],["16:30","20:30"]],"thu":[["07:00","10:30"],["11:00","14:30"],["16:30","20:30"]],"fri":[["07:00","10:30"],["11:00","14:30"],["16:30","20:30"]],"sat":[["09:30","14:00"],["16:30","20:00"]],"sun":[["09:30","14:00"],["16:30","20:00"]]}'::jsonb, 42.3938, -72.533, null, 'medium'),
  ('d0000000-0000-4000-8000-000000000003', 'a0000000-0000-4000-8000-000000000001', 'Berkshire Dining Commons', 'commons', '{"mon":[["07:00","10:30"],["11:00","14:30"],["16:30","20:30"]],"tue":[["07:00","10:30"],["11:00","14:30"],["16:30","20:30"]],"wed":[["07:00","10:30"],["11:00","14:30"],["16:30","20:30"]],"thu":[["07:00","10:30"],["11:00","14:30"],["16:30","20:30"]],"fri":[["07:00","10:30"],["11:00","14:30"],["16:30","20:30"]],"sat":[["09:30","14:00"],["16:30","20:00"]],"sun":[["09:30","14:00"],["16:30","20:00"]]}'::jsonb, 42.3878, -72.532, null, 'medium'),
  ('d0000000-0000-4000-8000-000000000004', 'a0000000-0000-4000-8000-000000000001', 'Hampshire Dining Commons', 'commons', '{"mon":[["07:00","10:30"],["11:00","14:30"],["16:30","20:30"]],"tue":[["07:00","10:30"],["11:00","14:30"],["16:30","20:30"]],"wed":[["07:00","10:30"],["11:00","14:30"],["16:30","20:30"]],"thu":[["07:00","10:30"],["11:00","14:30"],["16:30","20:30"]],"fri":[["07:00","10:30"],["11:00","14:30"],["16:30","20:30"]],"sat":[["09:30","14:00"],["16:30","20:00"]],"sun":[["09:30","14:00"],["16:30","20:00"]]}'::jsonb, 42.3958, -72.524, null, 'low'),
  ('d0000000-0000-4000-8000-000000000005', 'a0000000-0000-4000-8000-000000000001', 'Blue Wall', 'retail', '{"mon":[["08:00","21:00"]],"tue":[["08:00","21:00"]],"wed":[["08:00","21:00"]],"thu":[["08:00","21:00"]],"fri":[["08:00","21:00"]],"sat":[["11:00","18:00"]],"sun":[["11:00","18:00"]]}'::jsonb, 42.3912, -72.5267, null, 'high'),
  ('d0000000-0000-4000-8000-000000000006', 'a0000000-0000-4000-8000-000000000001', 'Cosmic Cafe', 'retail', '{"mon":[["08:00","17:00"]],"tue":[["08:00","17:00"]],"wed":[["08:00","17:00"]],"thu":[["08:00","17:00"]],"fri":[["08:00","17:00"]],"sat":[],"sun":[]}'::jsonb, 42.3899, -72.5285, null, 'low')
on conflict (id) do update set campus_id = excluded.campus_id, name = excluded.name,
  type = excluded.type, hours = excluded.hours, lat = excluded.lat, lng = excluded.lng,
  image_url = excluded.image_url, busy_level = excluded.busy_level;

-- Menu categories
insert into public.menu_categories (id, location_id, name, sort_order) values
  ('c0000000-0000-4000-8000-000000000001', 'd0000000-0000-4000-8000-000000000001', 'Grill', 1),
  ('c0000000-0000-4000-8000-000000000002', 'd0000000-0000-4000-8000-000000000001', 'Pizza & Pasta', 2),
  ('c0000000-0000-4000-8000-000000000003', 'd0000000-0000-4000-8000-000000000001', 'Global Kitchen', 3),
  ('c0000000-0000-4000-8000-000000000004', 'd0000000-0000-4000-8000-000000000002', 'Comfort Classics', 1),
  ('c0000000-0000-4000-8000-000000000005', 'd0000000-0000-4000-8000-000000000002', 'Salad Bar', 2),
  ('c0000000-0000-4000-8000-000000000006', 'd0000000-0000-4000-8000-000000000002', 'Halal Station', 3),
  ('c0000000-0000-4000-8000-000000000007', 'd0000000-0000-4000-8000-000000000002', 'Desserts', 4),
  ('c0000000-0000-4000-8000-000000000008', 'd0000000-0000-4000-8000-000000000003', 'Mongolian Grill', 1),
  ('c0000000-0000-4000-8000-000000000009', 'd0000000-0000-4000-8000-000000000003', 'Mexican', 2),
  ('c0000000-0000-4000-8000-000000000010', 'd0000000-0000-4000-8000-000000000003', 'Homestyle', 3),
  ('c0000000-0000-4000-8000-000000000011', 'd0000000-0000-4000-8000-000000000003', 'Breakfast All Day', 4),
  ('c0000000-0000-4000-8000-000000000012', 'd0000000-0000-4000-8000-000000000004', 'Grill & Deli', 1),
  ('c0000000-0000-4000-8000-000000000013', 'd0000000-0000-4000-8000-000000000004', 'Plant-Based Kitchen', 2),
  ('c0000000-0000-4000-8000-000000000014', 'd0000000-0000-4000-8000-000000000004', 'Halal', 3),
  ('c0000000-0000-4000-8000-000000000015', 'd0000000-0000-4000-8000-000000000004', 'Desserts', 4),
  ('c0000000-0000-4000-8000-000000000016', 'd0000000-0000-4000-8000-000000000005', 'Grab & Go', 1),
  ('c0000000-0000-4000-8000-000000000017', 'd0000000-0000-4000-8000-000000000005', 'Hot Food', 2),
  ('c0000000-0000-4000-8000-000000000018', 'd0000000-0000-4000-8000-000000000005', 'Drinks & Snacks', 3),
  ('c0000000-0000-4000-8000-000000000019', 'd0000000-0000-4000-8000-000000000006', 'Coffee', 1),
  ('c0000000-0000-4000-8000-000000000020', 'd0000000-0000-4000-8000-000000000006', 'Bakery', 2),
  ('c0000000-0000-4000-8000-000000000021', 'd0000000-0000-4000-8000-000000000006', 'Sandwiches', 3)
on conflict (id) do update set location_id = excluded.location_id, name = excluded.name,
  sort_order = excluded.sort_order;

-- Menu items (tags: vegan | vegetarian | gf | halal; prices in cents)
insert into public.menu_items (id, category_id, name, description, price_cents, tags, image_url, is_available) values
  ('e0000000-0000-4000-8000-000000000001', 'c0000000-0000-4000-8000-000000000001', 'Cheeseburger', 'Flame-grilled beef patty, cheddar, lettuce, tomato, brioche bun', 650, '{}', null, true),
  ('e0000000-0000-4000-8000-000000000002', 'c0000000-0000-4000-8000-000000000001', 'Crispy Chicken Sandwich', 'Buttermilk fried chicken, pickles, house sauce', 700, '{}', null, true),
  ('e0000000-0000-4000-8000-000000000003', 'c0000000-0000-4000-8000-000000000001', 'Black Bean Burger', 'House-made black bean patty with chipotle mayo', 650, '{vegetarian}', null, true),
  ('e0000000-0000-4000-8000-000000000004', 'c0000000-0000-4000-8000-000000000002', 'Margherita Pizza (2 slices)', 'Fresh mozzarella, basil, tomato sauce', 550, '{vegetarian}', null, true),
  ('e0000000-0000-4000-8000-000000000005', 'c0000000-0000-4000-8000-000000000002', 'Penne Marinara', 'Penne with slow-simmered tomato sauce', 600, '{vegan}', null, true),
  ('e0000000-0000-4000-8000-000000000006', 'c0000000-0000-4000-8000-000000000003', 'Chicken Tikka Bowl', 'Halal chicken tikka over basmati rice with raita', 800, '{halal,gf}', null, true),
  ('e0000000-0000-4000-8000-000000000007', 'c0000000-0000-4000-8000-000000000003', 'Vegetable Stir Fry', 'Seasonal vegetables, tofu, ginger-soy glaze, steamed rice', 700, '{vegan}', null, true),
  ('e0000000-0000-4000-8000-000000000008', 'c0000000-0000-4000-8000-000000000003', 'Falafel Wrap', 'Falafel, hummus, cucumber, pickled onion, warm pita', 650, '{vegan}', null, true),
  ('e0000000-0000-4000-8000-000000000009', 'c0000000-0000-4000-8000-000000000004', 'Roast Turkey Dinner', 'Sliced roast turkey, mashed potatoes, gravy, green beans', 850, '{gf}', null, true),
  ('e0000000-0000-4000-8000-000000000010', 'c0000000-0000-4000-8000-000000000004', 'Mac & Cheese', 'Baked cavatappi in a three-cheese sauce', 600, '{vegetarian}', null, true),
  ('e0000000-0000-4000-8000-000000000011', 'c0000000-0000-4000-8000-000000000004', 'Meatloaf Plate', 'Home-style meatloaf with roasted vegetables', 800, '{}', null, true),
  ('e0000000-0000-4000-8000-000000000012', 'c0000000-0000-4000-8000-000000000005', 'Build-Your-Own Salad', 'Greens, 5 toppings, choice of dressing', 700, '{vegan,gf}', null, true),
  ('e0000000-0000-4000-8000-000000000013', 'c0000000-0000-4000-8000-000000000005', 'Grilled Chicken Caesar', 'Romaine, parmesan, croutons, Caesar dressing', 750, '{}', null, true),
  ('e0000000-0000-4000-8000-000000000014', 'c0000000-0000-4000-8000-000000000006', 'Halal Chicken Over Rice', 'Spiced halal chicken, rice, white sauce, salad', 800, '{halal,gf}', null, true),
  ('e0000000-0000-4000-8000-000000000015', 'c0000000-0000-4000-8000-000000000006', 'Lamb Gyro', 'Halal lamb, tzatziki, tomato, onion, pita', 850, '{halal}', null, true),
  ('e0000000-0000-4000-8000-000000000016', 'c0000000-0000-4000-8000-000000000007', 'Fresh-Baked Cookie', 'Chocolate chunk cookie baked daily', 200, '{vegetarian}', null, true),
  ('e0000000-0000-4000-8000-000000000017', 'c0000000-0000-4000-8000-000000000008', 'Chicken Mongolian Bowl', 'Wok-seared chicken, vegetables, noodles, house sauce', 800, '{}', null, true),
  ('e0000000-0000-4000-8000-000000000018', 'c0000000-0000-4000-8000-000000000008', 'Tofu Mongolian Bowl', 'Crispy tofu, vegetables, rice noodles, ginger garlic sauce', 750, '{vegan}', null, true),
  ('e0000000-0000-4000-8000-000000000019', 'c0000000-0000-4000-8000-000000000009', 'Chicken Burrito', 'Seasoned chicken, rice, beans, cheese, pico de gallo', 750, '{}', null, true),
  ('e0000000-0000-4000-8000-000000000020', 'c0000000-0000-4000-8000-000000000009', 'Veggie Quesadilla', 'Peppers, onions, black beans, cheddar jack', 650, '{vegetarian}', null, true),
  ('e0000000-0000-4000-8000-000000000021', 'c0000000-0000-4000-8000-000000000009', 'Taco Trio (Vegan)', 'Three tacos with spiced jackfruit, slaw, and lime crema', 700, '{vegan,gf}', null, true),
  ('e0000000-0000-4000-8000-000000000022', 'c0000000-0000-4000-8000-000000000010', 'Baked Salmon', 'Lemon-dill salmon, wild rice, steamed broccoli', 950, '{gf}', null, true),
  ('e0000000-0000-4000-8000-000000000023', 'c0000000-0000-4000-8000-000000000010', 'Eggplant Parmesan', 'Breaded eggplant, marinara, mozzarella', 700, '{vegetarian}', null, true),
  ('e0000000-0000-4000-8000-000000000024', 'c0000000-0000-4000-8000-000000000011', 'Veggie Omelet', 'Three-egg omelet with spinach, peppers, mushrooms', 600, '{vegetarian,gf}', null, true),
  ('e0000000-0000-4000-8000-000000000025', 'c0000000-0000-4000-8000-000000000012', 'Turkey Club', 'Roast turkey, bacon, lettuce, tomato on toasted bread', 700, '{}', null, true),
  ('e0000000-0000-4000-8000-000000000026', 'c0000000-0000-4000-8000-000000000012', 'Grilled Cheese & Tomato Soup', 'Sourdough grilled cheese with a cup of tomato soup', 650, '{vegetarian}', null, true),
  ('e0000000-0000-4000-8000-000000000027', 'c0000000-0000-4000-8000-000000000012', 'Beef Hot Dog', 'All-beef frank on a toasted split-top bun', 450, '{}', null, true),
  ('e0000000-0000-4000-8000-000000000028', 'c0000000-0000-4000-8000-000000000013', 'Chickpea Curry', 'Coconut chickpea curry with brown rice', 700, '{vegan,gf}', null, true),
  ('e0000000-0000-4000-8000-000000000029', 'c0000000-0000-4000-8000-000000000013', 'Lentil Shepherd''s Pie', 'Lentils and vegetables under mashed potato crust', 700, '{vegan,gf}', null, true),
  ('e0000000-0000-4000-8000-000000000030', 'c0000000-0000-4000-8000-000000000013', 'Quinoa Power Bowl', 'Quinoa, roasted sweet potato, kale, tahini', 750, '{vegan,gf}', null, true),
  ('e0000000-0000-4000-8000-000000000031', 'c0000000-0000-4000-8000-000000000014', 'Halal Beef Kebab Plate', 'Grilled halal beef skewers, rice pilaf, grilled vegetables', 850, '{halal,gf}', null, true),
  ('e0000000-0000-4000-8000-000000000032', 'c0000000-0000-4000-8000-000000000015', 'Vanilla Soft Serve', 'Cup of vanilla soft serve', 300, '{vegetarian,gf}', null, true),
  ('e0000000-0000-4000-8000-000000000033', 'c0000000-0000-4000-8000-000000000016', 'Chicken Caesar Wrap', 'Grilled chicken, romaine, parmesan, Caesar dressing', 800, '{}', null, true),
  ('e0000000-0000-4000-8000-000000000034', 'c0000000-0000-4000-8000-000000000016', 'Hummus & Veggie Wrap', 'Hummus, cucumber, peppers, spinach', 700, '{vegan}', null, true),
  ('e0000000-0000-4000-8000-000000000035', 'c0000000-0000-4000-8000-000000000017', 'Chicken Tenders & Fries', 'Five breaded tenders with crinkle-cut fries', 850, '{}', null, true),
  ('e0000000-0000-4000-8000-000000000036', 'c0000000-0000-4000-8000-000000000017', 'Cheese Pizza Slice', 'Large New York-style slice', 400, '{vegetarian}', null, true),
  ('e0000000-0000-4000-8000-000000000037', 'c0000000-0000-4000-8000-000000000018', 'Fresh Fruit Cup', 'Seasonal cut fruit', 400, '{vegan,gf}', null, true),
  ('e0000000-0000-4000-8000-000000000038', 'c0000000-0000-4000-8000-000000000019', 'Drip Coffee', 'Locally roasted house blend (12 oz)', 250, '{vegan,gf}', null, true),
  ('e0000000-0000-4000-8000-000000000039', 'c0000000-0000-4000-8000-000000000019', 'Latte', 'Double espresso with steamed milk (12 oz)', 450, '{vegetarian,gf}', null, true),
  ('e0000000-0000-4000-8000-000000000040', 'c0000000-0000-4000-8000-000000000019', 'Iced Oat Milk Latte', 'Double espresso over ice with oat milk (16 oz)', 525, '{vegan}', null, true),
  ('e0000000-0000-4000-8000-000000000041', 'c0000000-0000-4000-8000-000000000020', 'Blueberry Muffin', 'Baked in-house each morning', 325, '{vegetarian}', null, true),
  ('e0000000-0000-4000-8000-000000000042', 'c0000000-0000-4000-8000-000000000020', 'Vegan Banana Bread', 'Slice of dairy-free, egg-free banana bread', 350, '{vegan}', null, true),
  ('e0000000-0000-4000-8000-000000000043', 'c0000000-0000-4000-8000-000000000021', 'Egg & Cheese Bagel', 'Fried egg and cheddar on a toasted bagel', 500, '{vegetarian}', null, true)
on conflict (id) do update set category_id = excluded.category_id, name = excluded.name,
  description = excluded.description, price_cents = excluded.price_cents, tags = excluded.tags,
  image_url = excluded.image_url, is_available = excluded.is_available;

commit;
