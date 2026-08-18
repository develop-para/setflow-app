-- Keep public certification directory reads display-safe. Owners receive their
-- complete certification data only through the authenticated profile RPC.

begin;

revoke select on table public.trainer_certifications from authenticated;

grant select (id, trainer_id, title)
  on table public.trainer_certifications
  to authenticated;

create or replace function private.get_my_trainer_profile()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $function$
  select to_jsonb(t) || jsonb_build_object(
    'certifications',
    coalesce(
      (
        select jsonb_agg(to_jsonb(c) order by c.created_at desc, c.id)
        from public.trainer_certifications c
        where c.trainer_id = t.id
      ),
      '[]'::jsonb
    )
  )
  from public.trainers t
  where t.user_id = (select auth.uid())
  order by t.updated_at desc
  limit 1;
$function$;

revoke all on function private.get_my_trainer_profile()
  from public, anon;
grant execute on function private.get_my_trainer_profile()
  to authenticated, service_role;

commit;
