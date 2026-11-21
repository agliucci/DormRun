-- Allow the scheduled scrape (service_role) to refresh dining menus.
grant select, insert, update, delete on public.menu_categories to service_role;
grant select, insert, update, delete on public.menu_items to service_role;
