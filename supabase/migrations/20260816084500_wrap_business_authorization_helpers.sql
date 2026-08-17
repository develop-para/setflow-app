-- Keep authorization lookups callable by RLS and the client without exposing
-- SECURITY DEFINER functions through the public Data API schema.

begin;

create or replace function private.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (
    select 1
    from public.admin_users au
    where au.user_id = (select auth.uid())
      and au.status = 'active'
  );
$function$;

create or replace function private.owns_trainer(p_trainer_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (
    select 1
    from public.trainers t
    where t.id = p_trainer_id
      and t.user_id = (select auth.uid())
  );
$function$;

create or replace function private.owns_gym(p_gym_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (
    select 1
    from public.gyms g
    where g.id = p_gym_id
      and g.owner_user_id = (select auth.uid())
  );
$function$;

revoke all on function private.is_admin() from public, anon;
revoke all on function private.owns_trainer(uuid) from public, anon;
revoke all on function private.owns_gym(uuid) from public, anon;
grant execute on function private.is_admin(),
  private.owns_trainer(uuid), private.owns_gym(uuid)
  to authenticated, service_role;

create or replace function public.is_admin()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $function$
  select private.is_admin();
$function$;

create or replace function public.owns_trainer(t_id uuid)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $function$
  select private.owns_trainer(t_id);
$function$;

create or replace function public.owns_gym(g_id uuid)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $function$
  select private.owns_gym(g_id);
$function$;

revoke all on function public.is_admin() from public, anon;
revoke all on function public.owns_trainer(uuid) from public, anon;
revoke all on function public.owns_gym(uuid) from public, anon;
grant execute on function public.is_admin(),
  public.owns_trainer(uuid), public.owns_gym(uuid)
  to authenticated, service_role;

commit;
