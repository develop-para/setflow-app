-- Separate public business-directory fields from owner-only profile fields,
-- and ensure center trainers only see consultations explicitly addressed or
-- assigned to them.

begin;

revoke select on table public.trainers from authenticated;

grant select (
  id,
  display_name,
  keyword,
  intro,
  profile_image_url,
  career_years,
  center_name,
  rating_avg,
  post_count,
  coaching_total,
  is_public,
  verified_badge,
  status,
  created_at,
  updated_at
) on table public.trainers to authenticated;

create or replace function private.get_my_trainer_profile()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $function$
  select to_jsonb(t)
  from public.trainers t
  where t.user_id = (select auth.uid())
  order by t.updated_at desc
  limit 1;
$function$;

create or replace function private.get_my_gym_profile()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $function$
  select to_jsonb(g)
  from public.gyms g
  where g.owner_user_id = (select auth.uid())
  order by g.updated_at desc
  limit 1;
$function$;

revoke all on function private.get_my_trainer_profile()
  from public, anon;
revoke all on function private.get_my_gym_profile()
  from public, anon;
grant execute on function private.get_my_trainer_profile(),
  private.get_my_gym_profile()
  to authenticated, service_role;

create or replace function public.get_my_trainer_profile()
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $function$
  select private.get_my_trainer_profile();
$function$;

create or replace function public.get_my_gym_profile()
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $function$
  select private.get_my_gym_profile();
$function$;

revoke all on function public.get_my_trainer_profile()
  from public, anon;
revoke all on function public.get_my_gym_profile()
  from public, anon;
grant execute on function public.get_my_trainer_profile(),
  public.get_my_gym_profile()
  to authenticated, service_role;

create or replace function private.can_access_business_consultation(
  p_consultation_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select (select auth.uid()) is not null
    and exists (
      select 1
      from public.consultations c
      where c.id = p_consultation_id
        and (
          c.user_id = (select auth.uid())
          or exists (
            select 1
            from public.trainers t
            where t.id in (c.trainer_id, c.assigned_trainer_id)
              and t.user_id = (select auth.uid())
          )
          or exists (
            select 1
            from public.gyms g
            where g.id = c.gym_id
              and g.owner_user_id = (select auth.uid())
          )
          or exists (
            select 1
            from public.gym_trainers gt
            where gt.gym_id = c.gym_id
              and gt.trainer_id in (c.trainer_id, c.assigned_trainer_id)
              and gt.trainer_user_id = (select auth.uid())
              and gt.status = 'active'
          )
          or exists (
            select 1
            from public.admin_users au
            where au.user_id = (select auth.uid())
              and au.status = 'active'
          )
        )
    );
$function$;

commit;
