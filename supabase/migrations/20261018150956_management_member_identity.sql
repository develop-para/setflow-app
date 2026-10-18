begin;

-- Return the identity from each already-authorized relationship so clients
-- can open one member's records without relying on a non-unique display name.
-- Replacing these private functions preserves their signatures and grants;
-- the existing public wrappers and participant/active-consent checks remain.
create or replace function private.list_management_links()
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',l.id,'member_user_id',l.member_user_id,'member_name',private.display_name_of(l.member_user_id),
    'trainer_name',t.display_name,'status',case when l.status = 'active' and not private.management_active(l)
      then 'suspended' else l.status end,
    'viewer_role',private.management_role(l),
    'can_respond',l.status = 'pending' and (
      (private.management_role(l) = 'member' and l.member_accepted_at is null)
      or (private.management_role(l) = 'trainer' and l.trainer_accepted_at is null)),
    'gym_id',l.gym_id,'gym_name',g.name
  ) order by l.created_at desc),'[]'::jsonb)
  from public.coaching_management_links l join public.trainers t on t.id = l.trainer_id
  left join public.gyms g on g.id = l.gym_id where private.management_role(l) is not null;
$$;

create or replace function private.list_workout_corrections()
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'member_user_id',l.member_user_id,'member_name',private.display_name_of(l.member_user_id),
    'viewer_role',private.management_role(l),'record_key',c.record_key,'exercise_id',c.exercise_id,
    'correction_key',jsonb_build_array(c.exercise_id,c.set_number,c.metric)::text,
    'trainer_name',t.display_name,'workout_title',c.workout_title,'workout_date',c.workout_date,
    'exercise_name',c.exercise_name,'set_number',c.set_number,'metric',c.metric,
    'before_value',c.before_value,'after_value',c.after_value,'reason',c.reason,'status',c.status,
    'can_respond',c.status = 'pending' and l.member_user_id = (select auth.uid()) and private.management_active(l)
  ) order by (c.status = 'pending') desc,c.created_at desc),'[]'::jsonb)
  from public.workout_corrections c join public.coaching_management_links l on l.id = c.link_id
    join public.trainers t on t.id = l.trainer_id
  where private.management_role(l) is not null
    and (l.member_user_id = (select auth.uid()) or private.management_active(l));
$$;

commit;
