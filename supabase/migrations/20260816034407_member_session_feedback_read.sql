create or replace function private.list_my_session_feedback(
  p_from_date date,
  p_to_date date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_from date := coalesce(p_from_date, current_date - 90);
  v_to date := coalesce(p_to_date, current_date);
  v_feedback jsonb := '[]'::jsonb;
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if v_from > v_to or v_to - v_from > 366 then
    raise exception 'Invalid feedback date range' using errcode = '22023';
  end if;

  select coalesce(jsonb_agg(feedback_json order by session_date desc, created_at desc), '[]'::jsonb)
  into v_feedback
  from (
    select
      s.date as session_date,
      sf.created_at,
      jsonb_build_object(
        'id', sf.id,
        'session_id', sf.session_id,
        'session_date', s.date,
        'trainer_user_id', sf.trainer_id,
        'author_name', coalesce(t.display_name, u.nickname, '담당자'),
        'text', sf.text,
        'created_at', sf.created_at
      ) as feedback_json
    from public.workout_sessions s
    join public.session_feedback sf on sf.session_id = s.id
    left join public.trainers t on t.user_id = sf.trainer_id
    left join public.users u on u.id = sf.trainer_id
    where s.user_id = v_user_id
      and s.date between v_from and v_to
    order by s.date desc, sf.created_at desc
    limit 1000
  ) feedback_rows;

  return v_feedback;
end;
$$;

revoke all on function private.list_my_session_feedback(date, date)
  from public, anon, authenticated;
grant execute on function private.list_my_session_feedback(date, date)
  to authenticated, service_role;

create or replace function public.list_my_session_feedback(
  from_date date default current_date - 90,
  to_date date default current_date
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select private.list_my_session_feedback(from_date, to_date);
$$;

revoke all on function public.list_my_session_feedback(date, date)
  from public, anon;
grant execute on function public.list_my_session_feedback(date, date)
  to authenticated, service_role;
