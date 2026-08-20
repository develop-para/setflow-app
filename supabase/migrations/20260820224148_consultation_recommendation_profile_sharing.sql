-- Share a member-approved immutable recommendation-profile snapshot with the
-- exact trainer selected for a consultation. Gym owners and admins retain
-- access to the consultation itself, but not to this health-adjacent survey.

create table public.consultation_recommendation_profile_shares (
  consultation_id uuid primary key
    references public.consultations(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  schema_version smallint not null default 1
    check (schema_version = 1),
  profile_snapshot jsonb not null,
  consented_at timestamptz not null default now(),
  revoked_at timestamptz,
  constraint consultation_recommendation_profile_revocation_order_check
    check (revoked_at is null or revoked_at >= consented_at)
);

comment on table public.consultation_recommendation_profile_shares is
  'Immutable member-approved recommendation survey snapshots scoped to one consultation.';
comment on column public.consultation_recommendation_profile_shares.profile_snapshot is
  'Schema-versioned injury/pain, equipment, experience, movement restriction, and dated recovery answers.';

create index consultation_recommendation_profile_shares_user_idx
  on public.consultation_recommendation_profile_shares (user_id, consented_at desc);

alter table public.consultation_recommendation_profile_shares
  enable row level security;

revoke all on table public.consultation_recommendation_profile_shares
  from public, anon, authenticated;
grant select on table public.consultation_recommendation_profile_shares
  to authenticated;
grant all on table public.consultation_recommendation_profile_shares
  to service_role;

create or replace function private.is_valid_recommendation_profile_snapshot(
  p_profile jsonb
)
returns boolean
language plpgsql
immutable
strict
security invoker
set search_path = ''
as $function$
declare
  v_equipment jsonb;
  v_pain_regions jsonb;
  v_movements jsonb;
  v_recovery_recorded_at timestamptz;
  v_updated_at timestamptz;
begin
  if pg_catalog.jsonb_typeof(p_profile) <> 'object' then
    return false;
  end if;
  if pg_catalog.octet_length(p_profile::text) > 8000 then
    return false;
  end if;
  if not (p_profile ?& array[
      'schemaVersion',
      'experienceLevel',
      'availableEquipment',
      'painRegions',
      'painLevel',
      'restrictedMovements',
      'injuryNote',
      'recoveryStatus',
      'recoveryRecordedAt',
      'updatedAt'
    ]) then
    return false;
  end if;
  if exists (
    select 1
    from pg_catalog.jsonb_object_keys(p_profile) as profile_key(key)
    where profile_key.key not in (
      'schemaVersion',
      'experienceLevel',
      'availableEquipment',
      'painRegions',
      'painLevel',
      'restrictedMovements',
      'injuryNote',
      'recoveryStatus',
      'recoveryRecordedAt',
      'updatedAt'
    )
  ) then
    return false;
  end if;
  if pg_catalog.jsonb_typeof(p_profile -> 'schemaVersion') <> 'number'
     or p_profile ->> 'schemaVersion' <> '1'
     or pg_catalog.jsonb_typeof(p_profile -> 'experienceLevel') <> 'string'
     or p_profile ->> 'experienceLevel' not in (
       'beginner', 'intermediate', 'advanced'
     ) then
    return false;
  end if;

  v_equipment := p_profile -> 'availableEquipment';
  if pg_catalog.jsonb_typeof(v_equipment) <> 'array' then
    return false;
  end if;
  if pg_catalog.jsonb_array_length(v_equipment) not between 1 and 16 then
    return false;
  end if;
  if exists (
    select 1
    from pg_catalog.jsonb_array_elements_text(v_equipment) as equipment(value)
    where equipment.value not in (
      'bodyweight',
      'dumbbells',
      'barbell',
      'bench',
      'squatRack',
      'cableStation',
      'machines',
      'pullupBar',
      'dipBars',
      'abWheel',
      'jumpRope',
      'treadmill',
      'stationaryBike',
      'stairClimber',
      'rowingMachine',
      'elliptical'
    )
  ) then
    return false;
  end if;
  if pg_catalog.jsonb_array_length(v_equipment) <> (
    select pg_catalog.count(distinct equipment.value)
    from pg_catalog.jsonb_array_elements_text(v_equipment) as equipment(value)
  ) then
    return false;
  end if;

  v_pain_regions := p_profile -> 'painRegions';
  if pg_catalog.jsonb_typeof(v_pain_regions) <> 'array' then
    return false;
  end if;
  if pg_catalog.jsonb_array_length(v_pain_regions) not between 0 and 8 then
    return false;
  end if;
  if exists (
    select 1
    from pg_catalog.jsonb_array_elements_text(v_pain_regions) as pain_region(value)
    where pain_region.value not in (
      'shoulder',
      'elbowWrist',
      'neckUpperBack',
      'lowerBack',
      'hip',
      'knee',
      'ankleFoot',
      'other'
    )
  ) then
    return false;
  end if;
  if pg_catalog.jsonb_array_length(v_pain_regions) <> (
    select pg_catalog.count(distinct pain_region.value)
    from pg_catalog.jsonb_array_elements_text(v_pain_regions) as pain_region(value)
  ) then
    return false;
  end if;
  if pg_catalog.jsonb_typeof(p_profile -> 'painLevel') <> 'number'
     or p_profile ->> 'painLevel' not in (
       '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '10'
     ) then
    return false;
  end if;
  if pg_catalog.jsonb_array_length(v_pain_regions) = 0
     and p_profile ->> 'painLevel' <> '0' then
    return false;
  end if;

  v_movements := p_profile -> 'restrictedMovements';
  if pg_catalog.jsonb_typeof(v_movements) <> 'array' then
    return false;
  end if;
  if pg_catalog.jsonb_array_length(v_movements) not between 0 and 9 then
    return false;
  end if;
  if exists (
    select 1
    from pg_catalog.jsonb_array_elements_text(v_movements) as movement(value)
    where movement.value not in (
      'horizontalPress',
      'overheadPress',
      'shoulderRaise',
      'verticalPull',
      'rowing',
      'squatLunge',
      'hipHinge',
      'impact',
      'trunkFlexionRotation'
    )
  ) then
    return false;
  end if;
  if pg_catalog.jsonb_array_length(v_movements) <> (
    select pg_catalog.count(distinct movement.value)
    from pg_catalog.jsonb_array_elements_text(v_movements) as movement(value)
  ) then
    return false;
  end if;

  if pg_catalog.jsonb_typeof(p_profile -> 'injuryNote') <> 'string'
     or pg_catalog.char_length(p_profile ->> 'injuryNote') > 500
     or pg_catalog.jsonb_typeof(p_profile -> 'recoveryStatus') <> 'string'
     or p_profile ->> 'recoveryStatus' not in (
       'recovered', 'normal', 'fatigued'
     ) then
    return false;
  end if;
  if pg_catalog.jsonb_typeof(p_profile -> 'recoveryRecordedAt') <> 'string'
     or p_profile ->> 'recoveryRecordedAt'
       !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]{1,6})?Z$'
     or pg_catalog.jsonb_typeof(p_profile -> 'updatedAt') <> 'string'
     or p_profile ->> 'updatedAt'
       !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]{1,6})?Z$' then
    return false;
  end if;
  begin
    v_recovery_recorded_at := (p_profile ->> 'recoveryRecordedAt')::timestamptz;
    v_updated_at := (p_profile ->> 'updatedAt')::timestamptz;
  exception when others then
    return false;
  end;
  if v_recovery_recorded_at > v_updated_at then
    return false;
  end if;
  return true;
exception when others then
  return false;
end;
$function$;

revoke all on function private.is_valid_recommendation_profile_snapshot(jsonb)
  from public, anon, authenticated;
grant execute on function private.is_valid_recommendation_profile_snapshot(jsonb)
  to service_role;

create or replace function private.can_read_consultation_recommendation_profile(
  p_consultation_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select (select auth.uid()) is not null
    and p_consultation_id is not null
    and exists (
      select 1
      from public.consultations c
      join public.trainers t
        on t.id = coalesce(c.assigned_trainer_id, c.trainer_id)
       and t.user_id = (select auth.uid())
       and t.status = 'approved'
      where c.id = p_consultation_id
        and (
          c.gym_id is null
          or exists (
            select 1
            from public.gym_trainers gt
            join public.gyms g
              on g.id = gt.gym_id
             and g.status = 'verified'
            where gt.gym_id = c.gym_id
              and gt.trainer_id = t.id
              and gt.trainer_user_id = (select auth.uid())
              and gt.status = 'active'
          )
        )
    );
$function$;

revoke all on function private.can_read_consultation_recommendation_profile(uuid)
  from public, anon;
grant execute on function private.can_read_consultation_recommendation_profile(uuid)
  to authenticated, service_role;

create policy consultation_recommendation_profile_participant_read
  on public.consultation_recommendation_profile_shares
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.consultations owned_consultation
      where owned_consultation.id = consultation_id
        and owned_consultation.user_id = (select auth.uid())
    )
    or (
      revoked_at is null
      and (
        select private.can_read_consultation_recommendation_profile(
          consultation_id
        )
      )
    )
  );

create or replace function private.revoke_consultation_recommendation_profile_share(
  p_consultation_id uuid
)
returns timestamptz
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := auth.uid();
  v_revoked_at timestamptz;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;
  update public.consultation_recommendation_profile_shares profile_share
  set revoked_at = coalesce(profile_share.revoked_at, now())
  from public.consultations consultation
  where profile_share.consultation_id = p_consultation_id
    and consultation.id = profile_share.consultation_id
    and consultation.user_id = v_user_id
  returning profile_share.revoked_at into v_revoked_at;
  if not found then
    raise exception using errcode = '42501', message = 'Share not found or access denied';
  end if;
  return v_revoked_at;
end;
$function$;

create or replace function public.revoke_consultation_recommendation_profile_share(
  consultation_id uuid
)
returns timestamptz
language sql
volatile
security invoker
set search_path = ''
as $function$
  select private.revoke_consultation_recommendation_profile_share($1);
$function$;

revoke all on function private.revoke_consultation_recommendation_profile_share(uuid)
  from public, anon;
grant execute on function private.revoke_consultation_recommendation_profile_share(uuid)
  to authenticated, service_role;
revoke all on function public.revoke_consultation_recommendation_profile_share(uuid)
  from public, anon;
grant execute on function public.revoke_consultation_recommendation_profile_share(uuid)
  to authenticated, service_role;

create or replace function private.create_business_consultation(
  p_request_id uuid,
  p_trainer_id uuid,
  p_gym_id uuid,
  p_routine_id uuid,
  p_specialty text,
  p_goal text,
  p_level text,
  p_question text,
  p_recommendation_profile jsonb
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := auth.uid();
  v_specialty text := nullif(btrim(p_specialty), '');
  v_goal text := nullif(btrim(p_goal), '');
  v_level text := nullif(btrim(p_level), '');
  v_question text := nullif(btrim(p_question), '');
  v_existing public.consultations%rowtype;
  v_existing_profile jsonb;
  v_consultation_id uuid;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;
  if p_request_id is null then
    raise exception using errcode = '22023', message = 'A request ID is required';
  end if;
  if num_nonnulls(p_trainer_id, p_gym_id) <> 1 then
    raise exception using errcode = '22023', message = 'Exactly one trainer or gym target is required';
  end if;
  if v_question is null or char_length(v_question) > 5000
     or char_length(coalesce(v_specialty, '')) > 200
     or char_length(coalesce(v_goal, '')) > 200
     or char_length(coalesce(v_level, '')) > 100 then
    raise exception using errcode = '22023', message = 'Consultation text is invalid';
  end if;
  if p_recommendation_profile is not null
     and not coalesce(
       private.is_valid_recommendation_profile_snapshot(
         p_recommendation_profile
       ),
       false
     ) then
    raise exception using errcode = '22023', message = 'Recommendation profile snapshot is invalid';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'consultation_create:' || v_user_id::text || ':' || p_request_id::text,
      0
    )
  );

  select c.*
    into v_existing
  from public.consultations c
  where c.user_id = v_user_id
    and c.request_id = p_request_id
  for update;
  if found then
    select profile_share.profile_snapshot
      into v_existing_profile
    from public.consultation_recommendation_profile_shares profile_share
    where profile_share.consultation_id = v_existing.id;
    if v_existing.trainer_id is distinct from p_trainer_id
       or v_existing.gym_id is distinct from p_gym_id
       or v_existing.routine_id is distinct from p_routine_id
       or v_existing.specialty is distinct from v_specialty
       or v_existing.goal is distinct from v_goal
       or v_existing.level is distinct from v_level
       or v_existing.question is distinct from v_question
       or v_existing_profile is distinct from p_recommendation_profile then
      raise exception using errcode = '22023', message = 'A consultation request ID cannot be reused with different data';
    end if;
    return jsonb_build_object(
      'consultation_id', v_existing.id,
      'status', v_existing.status,
      'replayed', true
    );
  end if;

  if p_trainer_id is not null and not exists (
    select 1
    from public.trainers t
    where t.id = p_trainer_id
      and t.status = 'approved'
      and t.is_public
  ) then
    raise exception using errcode = '42501', message = 'A public approved trainer is required';
  end if;
  if p_gym_id is not null and not exists (
    select 1
    from public.gyms g
    where g.id = p_gym_id
      and g.status = 'verified'
  ) then
    raise exception using errcode = '42501', message = 'A verified gym is required';
  end if;
  if p_routine_id is not null and not exists (
    select 1
    from public.coaching_routines cr
    where cr.id = p_routine_id
      and cr.status = 'approved'
      and (
        (p_trainer_id is not null and (
          cr.trainer_id = p_trainer_id
          or (cr.trainer_id is null and cr.gym_id is null)
        ))
        or (p_gym_id is not null and (
          cr.gym_id = p_gym_id
          or (cr.trainer_id is null and cr.gym_id is null)
        ))
      )
  ) then
    raise exception using errcode = '42501', message = 'The routine does not belong to the consultation target';
  end if;

  insert into public.consultations (
    request_id,
    user_id,
    trainer_id,
    gym_id,
    routine_id,
    specialty,
    goal,
    level,
    question,
    status,
    is_read,
    assigned_trainer_id
  ) values (
    p_request_id,
    v_user_id,
    p_trainer_id,
    p_gym_id,
    p_routine_id,
    v_specialty,
    v_goal,
    v_level,
    v_question,
    'pending',
    false,
    null
  )
  returning id into v_consultation_id;

  if p_recommendation_profile is not null then
    insert into public.consultation_recommendation_profile_shares (
      consultation_id,
      user_id,
      schema_version,
      profile_snapshot,
      consented_at
    ) values (
      v_consultation_id,
      v_user_id,
      1,
      p_recommendation_profile,
      now()
    );
  end if;

  return jsonb_build_object(
    'consultation_id', v_consultation_id,
    'status', 'pending',
    'replayed', false
  );
end
$function$;

-- Compatibility endpoint for clients released before recommendation-profile
-- sharing. They create the same consultation without a sensitive snapshot.
create or replace function private.create_business_consultation(
  p_request_id uuid,
  p_trainer_id uuid,
  p_gym_id uuid,
  p_routine_id uuid,
  p_specialty text,
  p_goal text,
  p_level text,
  p_question text
)
returns jsonb
language sql
volatile
security invoker
set search_path = ''
as $function$
  select private.create_business_consultation(
    $1, $2, $3, $4, $5, $6, $7, $8, null
  );
$function$;

create or replace function public.create_business_consultation(
  request_id uuid,
  trainer_id uuid,
  gym_id uuid,
  routine_id uuid,
  specialty text,
  goal text,
  level text,
  question text,
  recommendation_profile jsonb
)
returns jsonb
language sql
volatile
security invoker
set search_path = ''
as $function$
  select private.create_business_consultation(
    $1, $2, $3, $4, $5, $6, $7, $8, $9
  );
$function$;

create or replace function public.create_business_consultation(
  request_id uuid,
  trainer_id uuid,
  gym_id uuid,
  routine_id uuid,
  specialty text,
  goal text,
  level text,
  question text
)
returns jsonb
language sql
volatile
security invoker
set search_path = ''
as $function$
  select private.create_business_consultation(
    $1, $2, $3, $4, $5, $6, $7, $8
  );
$function$;

revoke all on function private.create_business_consultation(
  uuid, uuid, uuid, uuid, text, text, text, text, jsonb
) from public, anon;
grant execute on function private.create_business_consultation(
  uuid, uuid, uuid, uuid, text, text, text, text, jsonb
) to authenticated, service_role;
revoke all on function private.create_business_consultation(
  uuid, uuid, uuid, uuid, text, text, text, text
) from public, anon;
grant execute on function private.create_business_consultation(
  uuid, uuid, uuid, uuid, text, text, text, text
) to authenticated, service_role;

revoke all on function public.create_business_consultation(
  uuid, uuid, uuid, uuid, text, text, text, text, jsonb
) from public, anon;
grant execute on function public.create_business_consultation(
  uuid, uuid, uuid, uuid, text, text, text, text, jsonb
) to authenticated, service_role;
revoke all on function public.create_business_consultation(
  uuid, uuid, uuid, uuid, text, text, text, text
) from public, anon;
grant execute on function public.create_business_consultation(
  uuid, uuid, uuid, uuid, text, text, text, text
) to authenticated, service_role;

-- Keep the two existing consent scopes distinct. The previous projection
-- returned only share_workout_records and the client accidentally treated it
-- as both body-data and workout-record consent.
create or replace function private.get_business_member_detail(
  p_member_id uuid,
  p_from_date date,
  p_to_date date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_member public.members%rowtype;
  v_from date := coalesce(p_from_date, current_date - 90);
  v_to date := coalesce(p_to_date, current_date);
  v_share_body boolean := false;
  v_share_workout boolean := false;
  v_can_read boolean := false;
  v_sessions jsonb := '[]'::jsonb;
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if v_from > v_to or v_to - v_from > 366 then
    raise exception 'Invalid workout date range' using errcode = '22023';
  end if;

  select member.* into v_member
  from public.members member
  where member.id = p_member_id;

  if not found
     or not (select private.can_access_business_member(p_member_id)) then
    raise exception 'Member access denied' using errcode = '42501';
  end if;

  if v_member.user_id is not null then
    select
      coalesce(consent.share_body_data, false),
      coalesce(consent.share_workout_records, false)
    into v_share_body, v_share_workout
    from public.user_consents consent
    where consent.user_id = v_member.user_id;
    v_share_body := coalesce(v_share_body, false);
    v_share_workout := coalesce(v_share_workout, false);
    v_can_read := (select private.can_read_member_workout(v_member.user_id));
  end if;

  if v_can_read then
    select coalesce(
      pg_catalog.jsonb_agg(session_json order by session_date desc),
      '[]'::jsonb
    )
    into v_sessions
    from (
      select session.date as session_date,
        pg_catalog.jsonb_build_object(
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
        ) as session_json
      from public.workout_sessions session
      where session.user_id = v_member.user_id
        and session.date between v_from and v_to
    ) member_sessions;
  end if;

  return pg_catalog.jsonb_build_object(
    'member_id', v_member.id,
    'member_user_id', v_member.user_id,
    'share_body_data', v_share_body,
    'share_workout_records', v_share_workout,
    'can_read_workouts', v_can_read,
    'sessions', v_sessions
  );
end;
$function$;

revoke all on function private.get_business_member_detail(uuid, date, date)
  from public, anon, authenticated;
grant execute on function private.get_business_member_detail(uuid, date, date)
  to authenticated, service_role;
