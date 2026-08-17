-- Owner identity is available only through the authenticated user's private
-- profile RPC, not through the shared verified-gym directory.

begin;

revoke select (owner_user_id) on table public.gyms from authenticated;

commit;
