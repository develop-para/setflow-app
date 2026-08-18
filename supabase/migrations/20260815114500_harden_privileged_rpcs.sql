-- Coaching activation changes payment ownership and must only run server-side.
revoke execute on function public.activate_coaching(uuid, uuid, uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.activate_coaching(uuid, uuid, uuid, uuid)
  to service_role;

-- Keep the user-facing routine RPC, but prevent SECURITY DEFINER from reading
-- another user's private routine by UUID.
create or replace function public.apply_routine(p_routine uuid, p_date date)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_sess uuid;
  v_ex record;
  v_new_ex uuid;
begin
  if v_uid is null then
    raise exception '로그인이 필요합니다';
  end if;
  if not exists (
    select 1
    from public.routines r
    where r.id = p_routine and r.owner_user_id = v_uid
  ) then
    raise exception '접근 가능한 루틴이 없습니다';
  end if;

  insert into public.workout_sessions(user_id, date)
  values (v_uid, p_date)
  on conflict (user_id, date) do nothing;

  select id into v_sess
  from public.workout_sessions
  where user_id = v_uid and date = p_date;

  for v_ex in
    select *
    from public.routine_exercises
    where routine_id = p_routine
    order by order_index
  loop
    insert into public.workout_exercises(
      session_id,
      base_exercise_id,
      name,
      target_muscle,
      order_index
    )
    values (
      v_sess,
      v_ex.base_exercise_id,
      v_ex.name,
      v_ex.target_muscle,
      v_ex.order_index
    )
    returning id into v_new_ex;

    insert into public.workout_sets(
      exercise_id,
      set_no,
      type,
      weight,
      reps,
      completed
    )
    select
      v_new_ex,
      rs.set_no,
      coalesce(rs.type, 'normal'),
      coalesce(rs.target_weight, 0),
      coalesce(rs.target_reps, 0),
      false
    from public.routine_sets rs
    where rs.routine_exercise_id = v_ex.id
    order by rs.set_no;
  end loop;

  return v_sess;
end;
$$;

revoke execute on function public.apply_routine(uuid, date) from public, anon;
grant execute on function public.apply_routine(uuid, date)
  to authenticated, service_role;
