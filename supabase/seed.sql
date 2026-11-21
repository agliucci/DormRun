-- UMass Eats seed data: UMass Amherst
--
-- Deterministic: every row uses a fixed UUID, so the seed is idempotent
-- (re-running upserts via ON CONFLICT). UUID prefixes:
--   a... campus, b... buildings, d... dining locations,
--   c... menu categories, e... menu items
--
-- Buildings: full residence directory via scripts/scrape_umass.py.
-- Menu items below are starter retail/demo data. For live dining-commons
-- stations, run seed_menus_scraped.sql after this seed (same scraper).

begin;

insert into public.campuses (id, slug, name, edu_email_domains) values
  ('a0000000-0000-4000-8000-000000000001', 'umass-amherst', 'UMass Amherst', '{umass.edu}')
on conflict (id) do update set slug = excluded.slug, name = excluded.name,
  edu_email_domains = excluded.edu_email_domains;

-- Buildings (full UMass residence directory — regenerate via scripts/scrape_umass.py → seed_buildings.sql)
insert into public.buildings (id, campus_id, name, lat, lng, neighborhood) values
  ('b0000000-0000-4000-8000-000000000019', 'a0000000-0000-4000-8000-000000000001', 'Baker Hall', 42.38695, -72.5263, 'Central'),
  ('b0000000-0000-4000-8000-000000000010', 'a0000000-0000-4000-8000-000000000001', 'Brett Hall', 42.3873, -72.5259, 'Central'),
  ('b0000000-0000-4000-8000-000000000020', 'a0000000-0000-4000-8000-000000000001', 'Brooks Hall', 42.38765, -72.5255, 'Central'),
  ('b0000000-0000-4000-8000-000000000021', 'a0000000-0000-4000-8000-000000000001', 'Butterfield Hall', 42.388, -72.5251, 'Central'),
  ('b0000000-0000-4000-8000-000000000022', 'a0000000-0000-4000-8000-000000000001', 'Chadbourne Hall', 42.38835, -72.5247, 'Central'),
  ('b0000000-0000-4000-8000-000000000023', 'a0000000-0000-4000-8000-000000000001', 'Gorman Hall', 42.3887, -72.5263, 'Central'),
  ('b0000000-0000-4000-8000-000000000024', 'a0000000-0000-4000-8000-000000000001', 'Greenough Hall', 42.38905, -72.5259, 'Central'),
  ('b0000000-0000-4000-8000-000000000009', 'a0000000-0000-4000-8000-000000000001', 'Van Meter Hall', 42.38695, -72.5255, 'Central'),
  ('b0000000-0000-4000-8000-000000000025', 'a0000000-0000-4000-8000-000000000001', 'Wheeler Hall', 42.3873, -72.5251, 'Central'),
  ('b0000000-0000-4000-8000-000000000026', 'a0000000-0000-4000-8000-000000000001', 'Birch Hall', 42.38845, -72.5282, 'Commonwealth Honors College'),
  ('b0000000-0000-4000-8000-000000000016', 'a0000000-0000-4000-8000-000000000001', 'Elm Hall', 42.3888, -72.5298, 'Commonwealth Honors College'),
  ('b0000000-0000-4000-8000-000000000018', 'a0000000-0000-4000-8000-000000000001', 'Linden Hall', 42.38915, -72.5294, 'Commonwealth Honors College'),
  ('b0000000-0000-4000-8000-000000000017', 'a0000000-0000-4000-8000-000000000001', 'Maple Hall', 42.3895, -72.529, 'Commonwealth Honors College'),
  ('b0000000-0000-4000-8000-000000000015', 'a0000000-0000-4000-8000-000000000001', 'Oak Hall', 42.38985, -72.5286, 'Commonwealth Honors College'),
  ('b0000000-0000-4000-8000-000000000027', 'a0000000-0000-4000-8000-000000000001', 'Sycamore Hall', 42.38775, -72.5282, 'Commonwealth Honors College'),
  ('b0000000-0000-4000-8000-000000000028', 'a0000000-0000-4000-8000-000000000001', 'North Apartment A', 42.4003, -72.5268, 'North Apartments'),
  ('b0000000-0000-4000-8000-000000000029', 'a0000000-0000-4000-8000-000000000001', 'North Apartment B', 42.40065, -72.5264, 'North Apartments'),
  ('b0000000-0000-4000-8000-000000000030', 'a0000000-0000-4000-8000-000000000001', 'North Apartment C', 42.401, -72.526, 'North Apartments'),
  ('b0000000-0000-4000-8000-000000000031', 'a0000000-0000-4000-8000-000000000001', 'North Apartment D', 42.40135, -72.5256, 'North Apartments'),
  ('b0000000-0000-4000-8000-000000000011', 'a0000000-0000-4000-8000-000000000001', 'Crabtree Hall', 42.3957, -72.5217, 'Northeast'),
  ('b0000000-0000-4000-8000-000000000032', 'a0000000-0000-4000-8000-000000000001', 'Dwight Hall', 42.39605, -72.5233, 'Northeast'),
  ('b0000000-0000-4000-8000-000000000033', 'a0000000-0000-4000-8000-000000000001', 'Hamlin Hall', 42.39395, -72.5229, 'Northeast'),
  ('b0000000-0000-4000-8000-000000000034', 'a0000000-0000-4000-8000-000000000001', 'Johnson Hall', 42.3943, -72.5225, 'Northeast'),
  ('b0000000-0000-4000-8000-000000000012', 'a0000000-0000-4000-8000-000000000001', 'Knowlton Hall', 42.39465, -72.5221, 'Northeast'),
  ('b0000000-0000-4000-8000-000000000035', 'a0000000-0000-4000-8000-000000000001', 'Leach Hall', 42.395, -72.5217, 'Northeast'),
  ('b0000000-0000-4000-8000-000000000036', 'a0000000-0000-4000-8000-000000000001', 'Lewis Hall', 42.39535, -72.5233, 'Northeast'),
  ('b0000000-0000-4000-8000-000000000037', 'a0000000-0000-4000-8000-000000000001', 'Mary Lyon Hall', 42.3957, -72.5229, 'Northeast'),
  ('b0000000-0000-4000-8000-000000000038', 'a0000000-0000-4000-8000-000000000001', 'Thatcher Hall', 42.39605, -72.5225, 'Northeast'),
  ('b0000000-0000-4000-8000-000000000008', 'a0000000-0000-4000-8000-000000000001', 'Dickinson House', 42.38845, -72.5201, 'Orchard Hill'),
  ('b0000000-0000-4000-8000-000000000006', 'a0000000-0000-4000-8000-000000000001', 'Field Hall', 42.3888, -72.5197, 'Orchard Hill'),
  ('b0000000-0000-4000-8000-000000000039', 'a0000000-0000-4000-8000-000000000001', 'Grayson Hall', 42.38915, -72.5213, 'Orchard Hill'),
  ('b0000000-0000-4000-8000-000000000007', 'a0000000-0000-4000-8000-000000000001', 'Webster Hall', 42.3895, -72.5209, 'Orchard Hill'),
  ('b0000000-0000-4000-8000-000000000040', 'a0000000-0000-4000-8000-000000000001', 'Cance Hall', 42.38435, -72.5315, 'Southwest'),
  ('b0000000-0000-4000-8000-000000000003', 'a0000000-0000-4000-8000-000000000001', 'Coolidge Hall', 42.3847, -72.5311, 'Southwest'),
  ('b0000000-0000-4000-8000-000000000041', 'a0000000-0000-4000-8000-000000000001', 'Crampton Hall', 42.38505, -72.5307, 'Southwest'),
  ('b0000000-0000-4000-8000-000000000042', 'a0000000-0000-4000-8000-000000000001', 'Emerson Hall', 42.38295, -72.5323, 'Southwest'),
  ('b0000000-0000-4000-8000-000000000043', 'a0000000-0000-4000-8000-000000000001', 'James Hall', 42.3833, -72.5319, 'Southwest'),
  ('b0000000-0000-4000-8000-000000000044', 'a0000000-0000-4000-8000-000000000001', 'John Adams Hall', 42.38365, -72.5315, 'Southwest'),
  ('b0000000-0000-4000-8000-000000000002', 'a0000000-0000-4000-8000-000000000001', 'John Quincy Adams Hall', 42.384, -72.5311, 'Southwest'),
  ('b0000000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-000000000001', 'Kennedy Hall', 42.38435, -72.5307, 'Southwest'),
  ('b0000000-0000-4000-8000-000000000045', 'a0000000-0000-4000-8000-000000000001', 'MacKimmie Hall', 42.3847, -72.5323, 'Southwest'),
  ('b0000000-0000-4000-8000-000000000046', 'a0000000-0000-4000-8000-000000000001', 'Melville Hall', 42.38505, -72.5319, 'Southwest'),
  ('b0000000-0000-4000-8000-000000000047', 'a0000000-0000-4000-8000-000000000001', 'Moore Hall', 42.38295, -72.5315, 'Southwest'),
  ('b0000000-0000-4000-8000-000000000048', 'a0000000-0000-4000-8000-000000000001', 'Patterson Hall', 42.3833, -72.5311, 'Southwest'),
  ('b0000000-0000-4000-8000-000000000005', 'a0000000-0000-4000-8000-000000000001', 'Pierpont Hall', 42.38365, -72.5307, 'Southwest'),
  ('b0000000-0000-4000-8000-000000000049', 'a0000000-0000-4000-8000-000000000001', 'Prince Hall', 42.384, -72.5323, 'Southwest'),
  ('b0000000-0000-4000-8000-000000000050', 'a0000000-0000-4000-8000-000000000001', 'Thoreau Hall', 42.38435, -72.5319, 'Southwest'),
  ('b0000000-0000-4000-8000-000000000004', 'a0000000-0000-4000-8000-000000000001', 'Washington Hall', 42.3847, -72.5315, 'Southwest'),
  ('b0000000-0000-4000-8000-000000000014', 'a0000000-0000-4000-8000-000000000001', 'Brown Hall', 42.39855, -72.5271, 'Sylvan'),
  ('b0000000-0000-4000-8000-000000000013', 'a0000000-0000-4000-8000-000000000001', 'Cashin Hall', 42.39645, -72.5267, 'Sylvan'),
  ('b0000000-0000-4000-8000-000000000051', 'a0000000-0000-4000-8000-000000000001', 'McNamara Hall', 42.3968, -72.5283, 'Sylvan')
on conflict (id) do update set campus_id = excluded.campus_id, name = excluded.name,
  lat = excluded.lat, lng = excluded.lng, neighborhood = excluded.neighborhood;

-- Dining locations
insert into public.dining_locations (id, campus_id, name, type, hours, lat, lng, image_url, busy_level) values
  ('d0000000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-000000000001', 'Worcester Dining Commons', 'commons', '{"mon":[["07:00","21:00"]],"tue":[["07:00","21:00"]],"wed":[["07:00","21:00"]],"thu":[["07:00","21:00"]],"fri":[["07:00","21:00"]],"sat":[["07:00","21:00"]],"sun":[["07:00","21:00"]]}'::jsonb, 42.3922, -72.5236, null, 'high'),
  ('d0000000-0000-4000-8000-000000000002', 'a0000000-0000-4000-8000-000000000001', 'Franklin Dining Commons', 'commons', '{"mon":[["07:00","10:30"],["11:00","14:30"],["16:30","20:30"]],"tue":[["07:00","10:30"],["11:00","14:30"],["16:30","20:30"]],"wed":[["07:00","10:30"],["11:00","14:30"],["16:30","20:30"]],"thu":[["07:00","10:30"],["11:00","14:30"],["16:30","20:30"]],"fri":[["07:00","10:30"],["11:00","14:30"],["16:30","20:30"]],"sat":[["09:30","14:00"],["16:30","20:00"]],"sun":[["09:30","14:00"],["16:30","20:00"]]}'::jsonb, 42.3938, -72.533, null, 'medium'),
  ('d0000000-0000-4000-8000-000000000003', 'a0000000-0000-4000-8000-000000000001', 'Berkshire Dining Commons', 'commons', '{"mon":[["07:00","10:30"],["11:00","14:30"],["16:30","20:30"]],"tue":[["07:00","10:30"],["11:00","14:30"],["16:30","20:30"]],"wed":[["07:00","10:30"],["11:00","14:30"],["16:30","20:30"]],"thu":[["07:00","10:30"],["11:00","14:30"],["16:30","20:30"]],"fri":[["07:00","10:30"],["11:00","14:30"],["16:30","20:30"]],"sat":[["09:30","14:00"],["16:30","20:00"]],"sun":[["09:30","14:00"],["16:30","20:00"]]}'::jsonb, 42.3878, -72.532, null, 'medium'),
  ('d0000000-0000-4000-8000-000000000004', 'a0000000-0000-4000-8000-000000000001', 'Hampshire Dining Commons', 'commons', '{"mon":[["07:00","10:30"],["11:00","14:30"],["16:30","20:30"]],"tue":[["07:00","10:30"],["11:00","14:30"],["16:30","20:30"]],"wed":[["07:00","10:30"],["11:00","14:30"],["16:30","20:30"]],"thu":[["07:00","10:30"],["11:00","14:30"],["16:30","20:30"]],"fri":[["07:00","10:30"],["11:00","14:30"],["16:30","20:30"]],"sat":[["09:30","14:00"],["16:30","20:00"]],"sun":[["09:30","14:00"],["16:30","20:00"]]}'::jsonb, 42.3958, -72.524, null, 'low'),
  ('d0000000-0000-4000-8000-000000000005', 'a0000000-0000-4000-8000-000000000001', 'Blue Wall', 'retail', '{"mon":[["08:00","21:00"]],"tue":[["08:00","21:00"]],"wed":[["08:00","21:00"]],"thu":[["08:00","21:00"]],"fri":[["08:00","21:00"]],"sat":[["11:00","18:00"]],"sun":[["11:00","18:00"]]}'::jsonb, 42.3912, -72.5267, null, 'high'),
  ('d0000000-0000-4000-8000-000000000006', 'a0000000-0000-4000-8000-000000000001', 'Terrace', 'retail', '{"mon":[["08:00","20:00"]],"tue":[["08:00","20:00"]],"wed":[["08:00","20:00"]],"thu":[["08:00","20:00"]],"fri":[["08:00","20:00"]],"sat":[["10:00","18:00"]],"sun":[["10:00","18:00"]]}'::jsonb, 42.3889, -72.5294, null, 'medium')
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
