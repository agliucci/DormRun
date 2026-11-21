-- Allow authenticated users to update their own push_token (APNs).
grant update (campus_id, full_name, phone, home_building_id, is_runner, vehicle_type, avatar_url, push_token)
  on public.profiles to authenticated;
