-- Run once in Supabase Dashboard → SQL Editor (enables cloud menu scrape + chat).
grant select, insert, update, delete on public.menu_categories to service_role;
grant select, insert, update, delete on public.menu_items to service_role;

create table if not exists public.order_messages (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  body text not null check (char_length(trim(body)) between 1 and 2000),
  created_at timestamptz not null default now()
);

create index if not exists order_messages_order_id_created_at_idx
  on public.order_messages (order_id, created_at);

alter table public.order_messages enable row level security;

drop policy if exists order_messages_select on public.order_messages;
create policy order_messages_select on public.order_messages
  for select to authenticated
  using (
    exists (
      select 1 from public.orders o
      where o.id = order_messages.order_id
        and (o.customer_id = auth.uid() or o.runner_id = auth.uid())
    )
  );

drop policy if exists order_messages_insert on public.order_messages;
create policy order_messages_insert on public.order_messages
  for insert to authenticated
  with check (
    sender_id = auth.uid()
    and exists (
      select 1 from public.orders o
      where o.id = order_messages.order_id
        and (o.customer_id = auth.uid() or o.runner_id = auth.uid())
        and o.status in ('accepted', 'at_pickup', 'picked_up', 'en_route', 'delivered')
    )
  );

grant select, insert on public.order_messages to authenticated, service_role;
