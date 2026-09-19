begin;

-- JWT validation authenticates a request, but a signed-out token can remain
-- cryptographically valid until expiry. Consult the live session/account too.
create or replace function private.has_active_app_session()
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (
    select 1
    from auth.sessions s
    join auth.users au on au.id = s.user_id
    join public.users u on u.id = s.user_id
    where s.id = nullif((select auth.jwt()) ->> 'session_id', '')::uuid
      and s.user_id = (select auth.uid())
      and (s.not_after is null or s.not_after > now())
      and au.deleted_at is null
      and (au.banned_until is null or au.banned_until <= now())
      and not coalesce(au.is_anonymous, false)
      and u.status = 'active'
  );
$function$;

revoke all on function private.has_active_app_session() from public, anon;
grant execute on function private.has_active_app_session() to authenticated;

-- The pre-request hook also covers SECURITY DEFINER RPCs, which bypass RLS.
-- It intentionally leaves public guest reads and server service jobs alone.
create or replace function private.check_app_session()
returns void
language plpgsql
security invoker
set search_path = ''
as $function$
begin
  -- A separate branch matters: Postgres may check function privileges while
  -- planning both sides of an AND even when its first side is false.
  if current_setting('role', true) <> 'authenticated' then
    return;
  end if;
  if not private.has_active_app_session() then
    raise exception using errcode = '42501',
      message = '로그인 세션이 만료되었거나 이용이 제한된 계정이에요. 다시 로그인해주세요.';
  end if;
end;
$function$;

revoke all on function private.check_app_session() from public;
grant usage on schema private to anon, authenticated, service_role;
grant execute on function private.check_app_session()
  to anon, authenticated, service_role;

-- Refuse to silently replace a hook introduced by another deployment.
do $block$
declare
  v_setting text;
begin
  select setting into v_setting
  from pg_db_role_setting rs
  join pg_roles r on r.oid = rs.setrole
  cross join lateral unnest(rs.setconfig) setting
  where r.rolname = 'authenticator'
    and setting like 'pgrst.db_pre_request=%'
    and setting not in (
      'pgrst.db_pre_request=',
      'pgrst.db_pre_request=private.check_app_session'
    )
  limit 1;
  if v_setting is not null then
    raise exception 'Existing Data API pre-request hook must be composed first';
  end if;
end;
$block$;

alter role authenticator set pgrst.db_pre_request = 'private.check_app_session';

-- Storage and Realtime do not use the PostgREST hook. Add a restrictive AND
-- policy alongside existing ownership policies; this never grants new access.
-- An uncorrelated SELECT evaluates the indexed session lookup once per query.
do $block$
declare
  v_table record;
begin
  for v_table in
    select n.nspname, c.relname
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where c.relkind in ('r', 'p') and c.relrowsecurity
      and (n.nspname = 'public'
        or (n.nspname = 'storage' and c.relname = 'objects'))
  loop
    execute format(
      'create policy app_active_session on %I.%I as restrictive for all to authenticated '
      'using ((select private.has_active_app_session())) '
      'with check ((select private.has_active_app_session()))',
      v_table.nspname, v_table.relname
    );
  end loop;
end;
$block$;

-- One snapshot of the authoritative grants and display data. No caller-supplied
-- user id, saved app role, or editable user_metadata participates in this grant.
create or replace function private.get_my_business_access()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := (select auth.uid());
  v_user jsonb;
  v_trainer jsonb;
  v_gym jsonb;
  v_roles jsonb := '["member"]'::jsonb;
begin
  if not private.has_active_app_session() then
    raise exception using errcode = '42501', message = '유효한 로그인이 필요해요.';
  end if;

  select jsonb_build_object('id', u.id, 'email', u.email, 'role', u.role)
    into v_user from public.users u where u.id = v_user_id;
  v_trainer := private.get_my_trainer_profile();
  v_gym := private.get_my_gym_profile();
  if v_trainer ->> 'status' = 'approved' then
    v_roles := v_roles || '["trainer"]'::jsonb;
  end if;
  if v_gym ->> 'status' = 'verified' then
    v_roles := v_roles || '["gym"]'::jsonb;
  end if;
  if private.is_admin() then
    v_roles := v_roles || '["admin"]'::jsonb;
  end if;

  return jsonb_build_object(
    'user', v_user,
    'available_roles', v_roles,
    'trainer', v_trainer,
    'gym', v_gym,
    'trainer_application', (
      select to_jsonb(a) from public.trainer_applications a
      where a.user_id = v_user_id order by a.submitted_at desc, a.id limit 1
    ),
    'gym_application', (
      select to_jsonb(a) from public.gym_applications a
      where a.owner_user_id = v_user_id order by a.submitted_at desc, a.id limit 1
    )
  );
end;
$function$;

create or replace function public.get_my_business_access()
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $function$
  select private.get_my_business_access();
$function$;

revoke all on function private.get_my_business_access() from public, anon;
revoke all on function public.get_my_business_access() from public, anon;
grant execute on function private.get_my_business_access(),
  public.get_my_business_access() to authenticated;

-- Ownership alone is intentionally sufficient for submitting approval papers,
-- but never for authoring professional coaching content before approval.
create or replace function private.can_author_coaching_routine(
  p_trainer_id uuid, p_gym_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select private.has_active_app_session() and (
    exists (select 1 from public.trainers t
      where t.id = p_trainer_id and t.user_id = (select auth.uid())
        and t.status = 'approved')
    or exists (select 1 from public.gyms g
      where g.id = p_gym_id and g.owner_user_id = (select auth.uid())
        and g.status = 'verified')
  );
$function$;
revoke all on function private.can_author_coaching_routine(uuid, uuid)
  from public, anon;
grant execute on function private.can_author_coaching_routine(uuid, uuid)
  to authenticated;

create policy coaching_routines_approved_author_insert
on public.coaching_routines as restrictive for insert to authenticated
with check (private.can_author_coaching_routine(trainer_id, gym_id));
create policy coaching_routines_approved_author_update
on public.coaching_routines as restrictive for update to authenticated
using (private.can_author_coaching_routine(trainer_id, gym_id))
with check (private.can_author_coaching_routine(trainer_id, gym_id));
create policy coaching_routines_approved_author_delete
on public.coaching_routines as restrictive for delete to authenticated
using (private.can_author_coaching_routine(trainer_id, gym_id));

notify pgrst, 'reload config';
notify pgrst, 'reload schema';
commit;
