begin;

create index if not exists workout_sessions_member_history_idx
  on public.workout_sessions (user_id, date desc, id desc);

-- Class-scoped access includes records made before the class began.
-- Every page rechecks consent/assignment/completion and records the read.
create or replace function private.list_coaching_workout_history(
  p_schedule_id uuid, p_before_date date, p_before_id uuid
) returns jsonb
language plpgsql volatile security definer set search_path = ''
as $function$
declare
  v_schedule public.coaching_schedules%rowtype;
  v_role text;
  v_sessions jsonb;
  v_cursor jsonb;
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if (p_before_date is null) <> (p_before_id is null) then
    raise exception 'Incomplete history cursor' using errcode = '22023';
  end if;
  v_role := private.coaching_health_access_role(p_schedule_id);
  if v_role is null then
    raise exception 'Member consent is required' using errcode = '42501';
  end if;
  select * into strict v_schedule from public.coaching_schedules
    where id = p_schedule_id;
  insert into public.coaching_health_access_logs (
    schedule_id, member_user_id, trainer_id, gym_id, viewer_user_id, viewer_role
  ) values (v_schedule.id, v_schedule.member_user_id, v_schedule.trainer_id,
    v_schedule.gym_id, (select auth.uid()), v_role);

  with candidates as materialized (
    select session.* from public.workout_sessions session
    where session.user_id = v_schedule.member_user_id
      and (p_before_date is null or
        (session.date, session.id) < (p_before_date, p_before_id))
    order by session.date desc, session.id desc limit 21
  ), page as (
    select * from candidates order by date desc, id desc limit 20
  )
  select coalesce(jsonb_agg(pg_catalog.jsonb_build_object(
          'id', session.id,
          'user_id', session.user_id,
          'date', session.date,
          'category', session.category,
          'intensity', session.intensity,
          'feedback', session.feedback,
          'started_at', session.started_at,
          'ended_at', session.ended_at,
          'exercises', coalesce((
            select pg_catalog.jsonb_agg(
              pg_catalog.jsonb_build_object(
                'id', exercise.id,
                'base_exercise_id', exercise.base_exercise_id,
                'name', exercise.name,
                'target_muscle', exercise.target_muscle,
                'order_index', exercise.order_index,
                'sets', coalesce((
                  select pg_catalog.jsonb_agg(
                    pg_catalog.jsonb_build_object(
                      'id', workout_set.id,
                      'set_no', workout_set.set_no,
                      'type', workout_set.type,
                      'weight', workout_set.weight,
                      'reps', workout_set.reps,
                      'duration_sec', workout_set.duration_sec,
                      'distance_m', workout_set.distance_m,
                      'intensity_rpe', workout_set.intensity_rpe,
                      'rir', workout_set.rir,
                      'memo', workout_set.memo,
                      'completed', workout_set.completed,
                      'completed_at', workout_set.completed_at,
                      'estimated_1rm', workout_set.estimated_1rm,
                      'rest_seconds', workout_set.rest_seconds
                    ) order by workout_set.set_no
                  )
                  from public.workout_sets workout_set
                  where workout_set.exercise_id = exercise.id
                ), '[]'::jsonb)
              ) order by exercise.order_index
            )
            from public.workout_exercises exercise
            where exercise.session_id = session.id
          ), '[]'::jsonb),
          'feedbacks', coalesce((
            select pg_catalog.jsonb_agg(
              pg_catalog.jsonb_build_object(
                'id', feedback.id,
                'session_id', feedback.session_id,
                'trainer_user_id', feedback.trainer_id,
                'author_name', coalesce(
                  trainer.display_name,
                  account_user.nickname,
                  '담당자'
                ),
                'text', feedback.text,
                'created_at', feedback.created_at
              ) order by feedback.created_at desc
            )
            from public.session_feedback feedback
            left join public.trainers trainer
              on trainer.user_id = feedback.trainer_id
            left join public.users account_user
              on account_user.id = feedback.trainer_id
            where feedback.session_id = session.id
          ), '[]'::jsonb)
        ) order by session.date desc, session.id desc), '[]'::jsonb),
    case when (select count(*) from candidates) > 20 then
      (select jsonb_build_object('date', date, 'id', id)
       from page order by date asc, id asc limit 1)
    else null end
  into v_sessions, v_cursor
  from page session;

  return jsonb_build_object('schedule_id', v_schedule.id,
    'member_user_id', v_schedule.member_user_id,
    'sessions', v_sessions, 'next_cursor', v_cursor);
end;
$function$;

create or replace function public.list_coaching_workout_history(
  schedule_id uuid, before_date date default null, before_id uuid default null
) returns jsonb language sql volatile security invoker set search_path = ''
as $function$
  select private.list_coaching_workout_history($1, $2, $3);
$function$;
revoke all on function private.list_coaching_workout_history(uuid, date, uuid),
  public.list_coaching_workout_history(uuid, date, uuid) from public, anon, authenticated;
grant execute on function private.list_coaching_workout_history(uuid, date, uuid),
  public.list_coaching_workout_history(uuid, date, uuid) to authenticated, service_role;

create or replace function private.get_coaching_health_overview(
  p_schedule_id uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := (select auth.uid());
  v_access_role text;
  v_schedule public.coaching_schedules%rowtype;
  v_consent public.coaching_health_consents%rowtype;
  v_result jsonb;
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  v_access_role := private.coaching_health_access_role(p_schedule_id);
  if v_access_role is null then
    raise exception 'Member consent is required for this health overview'
      using errcode = '42501';
  end if;

  select schedule.*
  into strict v_schedule
  from public.coaching_schedules schedule
  where schedule.id = p_schedule_id;

  select consent.*
  into v_consent
  from public.coaching_health_consents consent
  where consent.schedule_id = p_schedule_id;

  insert into public.coaching_health_access_logs (
    schedule_id,
    member_user_id,
    trainer_id,
    gym_id,
    viewer_user_id,
    viewer_role
  ) values (
    v_schedule.id,
    v_schedule.member_user_id,
    v_schedule.trainer_id,
    v_schedule.gym_id,
    v_user_id,
    v_access_role
  );

  select jsonb_build_object(
    'schedule_id', v_schedule.id,
    'member_user_id', v_schedule.member_user_id,
    'trainer_id', v_schedule.trainer_id,
    'gym_id', v_schedule.gym_id,
    'access_role', v_access_role,
    'access_ends_on_completion', true,
    'member_name', coalesce(nullif(btrim(member.nickname), ''), '회원'),
    'profile', jsonb_strip_nulls(jsonb_build_object(
      'height_cm', profile.height,
      'weight_kg', profile.weight,
      'age', profile.age,
      'gender', profile.gender,
      'goal', profile.goal,
      'updated_at', profile.updated_at
    )),
    'recommendation_profile', coalesce(
      snapshot.payload #> '{profile,recommendationProfile}',
      'null'::jsonb
    ),
    'recommendation_profile_updated_at', snapshot.updated_at,
    'body_compositions', coalesce((
      select jsonb_agg(
        jsonb_strip_nulls(jsonb_build_object(
          'id', body.id,
          'record_date', body.record_date,
          'weight_kg', body.weight_kg,
          'skeletal_muscle_mass', body.skeletal_muscle_mass,
          'body_fat_pct', body.body_fat_pct,
          'bmi', body.bmi,
          'source', body.source,
          'created_at', body.created_at
        )) order by body.record_date desc, body.created_at desc
      )
      from (
        select composition.*
        from public.body_compositions composition
        where composition.user_id = v_schedule.member_user_id
        order by composition.record_date desc, composition.created_at desc
      ) body
    ), '[]'::jsonb),
    'consent', jsonb_build_object(
      'share_with_trainer', coalesce(v_consent.share_with_trainer, false),
      'share_with_gym', coalesce(v_consent.share_with_gym, false),
      'updated_at', v_consent.updated_at
    ),
    'read_at', clock_timestamp()
  ) into v_result
  from public.users member
  left join public.user_profiles profile
    on profile.user_id = member.id
  left join public.app_state_snapshots snapshot
    on snapshot.user_id = member.id
  where member.id = v_schedule.member_user_id;

  if v_result is null then
    raise exception 'Member health information was not found'
      using errcode = 'P0002';
  end if;
  return v_result;
end
$function$;


commit;
