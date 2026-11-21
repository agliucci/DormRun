-- Table-level grants required for PostgREST (RLS still applies).
-- Without these, anon/authenticated get "permission denied for table …".

grant usage on schema public to anon, authenticated, service_role;

grant select on public.campuses to anon, authenticated, service_role;
grant select on public.buildings to anon, authenticated, service_role;
grant select on public.dining_locations to anon, authenticated, service_role;
grant select on public.menu_categories to anon, authenticated, service_role;
grant select on public.menu_items to anon, authenticated, service_role;
-- Scheduled scrape writes with service_role
grant insert, update, delete on public.menu_categories to service_role;
grant insert, update, delete on public.menu_items to service_role;

grant select, insert, update on public.profiles to authenticated, service_role;
grant select on public.profiles to service_role;

grant select, insert on public.orders to authenticated, service_role;
grant select, insert on public.order_items to authenticated, service_role;

grant select, insert, update, delete on public.runner_locations to authenticated, service_role;
grant select, insert on public.ratings to authenticated, service_role;

-- Sequences if any were created
grant usage, select on all sequences in schema public to anon, authenticated, service_role;
