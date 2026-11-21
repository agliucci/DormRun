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
