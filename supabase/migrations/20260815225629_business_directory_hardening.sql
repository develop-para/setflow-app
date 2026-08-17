-- Keep the authenticated gym directory limited to display-safe fields.
-- Owners and admins can read the registered business number through their
-- own/admin-scoped gym application row, so it does not belong in the shared
-- verified-gym directory projection.

begin;

revoke select on table public.gyms from authenticated;

grant select (
  id,
  owner_user_id,
  name,
  rep_name,
  gym_type,
  address,
  description,
  cover_image_url,
  plan_tier,
  status,
  created_at,
  updated_at
) on table public.gyms to authenticated;

commit;
