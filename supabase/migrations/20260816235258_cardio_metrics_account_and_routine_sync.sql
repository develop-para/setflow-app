-- Store aerobic work as time, distance, and session RPE instead of forcing it
-- into the resistance-only weight/repetition shape. All fields are nullable so
-- existing resistance rows and older clients remain valid.

alter table public.workout_sets
  add column if not exists intensity_rpe numeric(3, 1);

alter table public.routine_sets
  add column if not exists duration_sec integer,
  add column if not exists distance_m numeric(8, 2),
  add column if not exists intensity_rpe numeric(3, 1);

alter table public.coaching_routine_sets
  add column if not exists duration_sec integer,
  add column if not exists distance_m numeric(8, 2),
  add column if not exists intensity_rpe numeric(3, 1),
  alter column target_reps drop not null;

alter table public.workout_sets
  drop constraint if exists workout_sets_cardio_metrics_valid;
alter table public.workout_sets
  add constraint workout_sets_cardio_metrics_valid check (
    (duration_sec is null or duration_sec between 0 and 604800)
    and (distance_m is null or distance_m between 0 and 999999.99)
    and (intensity_rpe is null or intensity_rpe between 1 and 10)
  ) not valid;
alter table public.workout_sets
  validate constraint workout_sets_cardio_metrics_valid;

alter table public.routine_sets
  drop constraint if exists routine_sets_content_valid;
alter table public.routine_sets
  add constraint routine_sets_content_valid check (
    set_no between 1 and 100
    and type in ('normal', 'warmup', 'drop', 'failure')
    and (target_weight is null or target_weight between 0 and 5000)
    and (target_reps is null or target_reps between 0 and 1000)
    and (duration_sec is null or duration_sec between 0 and 604800)
    and (distance_m is null or distance_m between 0 and 999999.99)
    and (intensity_rpe is null or intensity_rpe between 1 and 10)
    and (
      target_reps is not null
      or coalesce(duration_sec, 0) > 0
      or coalesce(distance_m, 0) > 0
    )
  ) not valid;
alter table public.routine_sets
  validate constraint routine_sets_content_valid;

alter table public.coaching_routine_sets
  drop constraint if exists coaching_routine_sets_content_valid;
alter table public.coaching_routine_sets
  add constraint coaching_routine_sets_content_valid check (
    set_no between 1 and 100
    and type in ('normal', 'warmup', 'drop', 'failure')
    and (target_weight is null or target_weight between 0 and 5000)
    and (target_reps is null or target_reps between 0 and 1000)
    and (duration_sec is null or duration_sec between 0 and 604800)
    and (distance_m is null or distance_m between 0 and 999999.99)
    and (intensity_rpe is null or intensity_rpe between 1 and 10)
    and (
      target_reps is not null
      or coalesce(duration_sec, 0) > 0
      or coalesce(distance_m, 0) > 0
    )
  ) not valid;
alter table public.coaching_routine_sets
  validate constraint coaching_routine_sets_content_valid;

-- e1RM is meaningful only for completed, ordinary resistance work in the
-- lower repetition range. Keep completion timestamps accurate for aerobic
-- rows as well, but never derive a lifting maximum from time or distance.
create or replace function public.tg_set_1rm()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $function$
declare
  v_is_cardio boolean := false;
begin
  select coalesce(
    pg_catalog.lower(pg_catalog.btrim(exercise.target_muscle))
      in ('유산소', 'cardio', 'aerobic'),
    false
  )
  into v_is_cardio
  from public.workout_exercises exercise
  where exercise.id = new.exercise_id;

  if new.completed then
    new.completed_at := coalesce(new.completed_at, pg_catalog.now());
  else
    new.completed_at := null;
  end if;

  if new.completed
     and not v_is_cardio
     and new.type = 'normal'
     and coalesce(new.weight, 0) > 0
     and coalesce(new.reps, 0) between 1 and 10
     and coalesce(new.duration_sec, 0) = 0
     and coalesce(new.distance_m, 0) = 0 then
    new.estimated_1rm := case
      when new.reps = 1 then pg_catalog.round(new.weight, 2)
      else least(
        9999.99,
        pg_catalog.round((
          new.weight * (1 + new.reps::numeric / 30)
          + new.weight * 36 / (37 - new.reps)
        ) / 2, 2)
      )
    end;
  else
    new.estimated_1rm := null;
  end if;

  return new;
end
$function$;

revoke all on function public.tg_set_1rm()
  from public, anon, authenticated;
grant execute on function public.tg_set_1rm() to service_role;

-- Remove stale derived values left by the legacy trigger (for example after a
-- completed set was changed back to incomplete, or for high-repetition work).
update public.workout_sets workout_set
set estimated_1rm = case
      when workout_set.completed
        and not coalesce(
          pg_catalog.lower(pg_catalog.btrim(exercise.target_muscle))
            in ('유산소', 'cardio', 'aerobic'),
          false
        )
        and workout_set.type = 'normal'
        and coalesce(workout_set.weight, 0) > 0
        and coalesce(workout_set.reps, 0) between 1 and 10
        and coalesce(workout_set.duration_sec, 0) = 0
        and coalesce(workout_set.distance_m, 0) = 0
      then case
        when workout_set.reps = 1
          then pg_catalog.round(workout_set.weight, 2)
        else least(
          9999.99,
          pg_catalog.round((
            workout_set.weight * (1 + workout_set.reps::numeric / 30)
            + workout_set.weight * 36 / (37 - workout_set.reps)
          ) / 2, 2)
        )
      end
      else null
    end,
    completed_at = case
      when workout_set.completed
        then coalesce(workout_set.completed_at, pg_catalog.now())
      else null
    end
from public.workout_exercises exercise
where exercise.id = workout_set.exercise_id;

-- Once an account has written the v9 cardio shape, an older client must not
-- overwrite it with a lower snapshot schema and silently erase those fields.
create or replace function private.reject_snapshot_schema_downgrade()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $function$
begin
  if new.schema_version < old.schema_version then
    raise exception using
      errcode = '22023',
      message = 'Snapshot schema downgrade is not allowed.';
  end if;
  return new;
end
$function$;

revoke all on function private.reject_snapshot_schema_downgrade()
  from public, anon, authenticated;
grant execute on function private.reject_snapshot_schema_downgrade()
  to service_role;

drop trigger if exists app_state_snapshot_schema_no_downgrade
  on public.app_state_snapshots;
create trigger app_state_snapshot_schema_no_downgrade
before update of schema_version on public.app_state_snapshots
for each row execute function private.reject_snapshot_schema_downgrade();

comment on column public.workout_sets.intensity_rpe is
  'Optional 1-10 session RPE for aerobic/timed work; NULL means not recorded.';
comment on column public.routine_sets.duration_sec is
  'Planned duration in seconds. Used instead of repetitions for timed/aerobic work.';
comment on column public.routine_sets.distance_m is
  'Optional planned distance in metres for distance-capable exercise modalities.';
comment on column public.routine_sets.intensity_rpe is
  'Optional planned session RPE on the 1-10 scale.';
comment on column public.coaching_routine_sets.duration_sec is
  'Planned duration in seconds. Used instead of repetitions for timed/aerobic work.';
comment on column public.coaching_routine_sets.distance_m is
  'Optional planned distance in metres for distance-capable exercise modalities.';
comment on column public.coaching_routine_sets.intensity_rpe is
  'Optional planned session RPE on the 1-10 scale.';

-- Keep the pre-existing exposure model explicit. RLS remains the row-level
-- authority; adding columns must not accidentally broaden table access.
alter table public.workout_sets enable row level security;
alter table public.routine_sets enable row level security;
alter table public.coaching_routine_sets enable row level security;

revoke all on table public.workout_sets,
  public.routine_sets,
  public.coaching_routine_sets from anon, authenticated;
grant select, insert, update, delete on table public.workout_sets
  to authenticated;
grant select on table public.routine_sets,
  public.coaching_routine_sets to authenticated;
grant select on table public.coaching_routine_sets to anon;
grant all on table public.workout_sets,
  public.routine_sets,
  public.coaching_routine_sets to service_role;

create or replace function private.coaching_routine_json(p_routine_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $function$
  select pg_catalog.jsonb_build_object(
    'id', routine.id,
    'trainer_id', routine.trainer_id,
    'gym_id', routine.gym_id,
    'title', routine.title,
    'intro', routine.intro,
    'price', routine.price,
    'difficulty', routine.difficulty,
    'status', routine.status,
    'reject_reason', routine.reject_reason,
    'cumulative_users', routine.cumulative_users,
    'submitted_at', routine.submitted_at,
    'submitted_by_user_id', routine.submitted_by_user_id,
    'reviewed_at', routine.reviewed_at,
    'reviewed_by_user_id', routine.reviewed_by_user_id,
    'created_at', routine.created_at,
    'updated_at', routine.updated_at,
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
                'id', routine_set.id,
                'set_no', routine_set.set_no,
                'type', routine_set.type,
                'target_weight', routine_set.target_weight,
                'target_reps', routine_set.target_reps,
                'duration_sec', routine_set.duration_sec,
                'distance_m', routine_set.distance_m,
                'intensity_rpe', routine_set.intensity_rpe,
                'rest_seconds', routine_set.rest_seconds
              ) order by routine_set.set_no, routine_set.id
            )
            from public.coaching_routine_sets routine_set
            where routine_set.routine_exercise_id = exercise.id
          ), '[]'::jsonb)
        ) order by exercise.order_index, exercise.id
      )
      from public.coaching_routine_exercises exercise
      where exercise.routine_id = routine.id
    ), '[]'::jsonb)
  )
  from public.coaching_routines routine
  where routine.id = p_routine_id;
$function$;

create or replace function private.personal_routine_json(p_routine_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $function$
  select pg_catalog.jsonb_build_object(
    'id', routine.id,
    'owner_user_id', routine.owner_user_id,
    'name', routine.name,
    'description', routine.description,
    'color', routine.color,
    'source', routine.source,
    'market_routine_id', routine.market_routine_id,
    'source_coaching_routine_id', routine.source_coaching_routine_id,
    'source_routine_share_id', routine.source_routine_share_id,
    'created_at', routine.created_at,
    'updated_at', routine.updated_at,
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
                'id', routine_set.id,
                'set_no', routine_set.set_no,
                'type', routine_set.type,
                'target_weight', routine_set.target_weight,
                'target_reps', routine_set.target_reps,
                'duration_sec', routine_set.duration_sec,
                'distance_m', routine_set.distance_m,
                'intensity_rpe', routine_set.intensity_rpe,
                'rest_seconds', routine_set.rest_seconds
              ) order by routine_set.set_no, routine_set.id
            )
            from public.routine_sets routine_set
            where routine_set.routine_exercise_id = exercise.id
          ), '[]'::jsonb)
        ) order by exercise.order_index, exercise.id
      )
      from public.routine_exercises exercise
      where exercise.routine_id = routine.id
    ), '[]'::jsonb)
  )
  from public.routines routine
  where routine.id = p_routine_id;
$function$;

create or replace function private.clone_coaching_routine(
  p_source_routine_id uuid,
  p_owner_user_id uuid,
  p_market_routine_id uuid default null,
  p_share_id uuid default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  source_row public.coaching_routines%rowtype;
  source_exercise record;
  new_routine_id uuid;
  new_exercise_id uuid;
  existing_routine_id uuid;
  routine_color text := '#10CEBD';
begin
  if p_owner_user_id is null then
    raise exception using
      errcode = '42501',
      message = 'Authentication is required.';
  end if;

  if p_market_routine_id is not null and p_share_id is not null then
    raise exception using
      errcode = '22023',
      message = 'A routine copy cannot have two import sources.';
  end if;

  if p_share_id is not null then
    select id into existing_routine_id
    from public.routines
    where owner_user_id = p_owner_user_id
      and source_routine_share_id = p_share_id;
  elsif p_market_routine_id is not null then
    select id into existing_routine_id
    from public.routines
    where owner_user_id = p_owner_user_id
      and market_routine_id = p_market_routine_id;
  end if;

  if existing_routine_id is not null then
    return private.personal_routine_json(existing_routine_id);
  end if;

  select * into source_row
  from public.coaching_routines
  where id = p_source_routine_id
  for update;

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'The source routine was not found.';
  end if;

  if p_market_routine_id is not null then
    select coalesce(color_hex, '#10CEBD') into routine_color
    from public.market_routines
    where id = p_market_routine_id
      and coaching_routine_id = p_source_routine_id;

    if not found then
      raise exception using
        errcode = '22023',
        message = 'The market routine does not match its source.';
    end if;
  end if;

  insert into public.routines (
    owner_user_id, name, description, color, source,
    market_routine_id, source_coaching_routine_id,
    source_routine_share_id
  ) values (
    p_owner_user_id,
    source_row.title,
    source_row.intro,
    routine_color,
    case when p_market_routine_id is null then 'copy' else 'market' end,
    p_market_routine_id,
    p_source_routine_id,
    p_share_id
  )
  returning id into new_routine_id;

  for source_exercise in
    select *
    from public.coaching_routine_exercises
    where routine_id = p_source_routine_id
    order by order_index, id
  loop
    insert into public.routine_exercises (
      routine_id, base_exercise_id, name, target_muscle, order_index
    ) values (
      new_routine_id,
      source_exercise.base_exercise_id,
      coalesce(nullif(pg_catalog.btrim(source_exercise.name), ''), '운동'),
      source_exercise.target_muscle,
      coalesce(source_exercise.order_index, 0)
    )
    returning id into new_exercise_id;

    insert into public.routine_sets (
      routine_exercise_id, set_no, type,
      target_weight, target_reps, duration_sec, distance_m,
      intensity_rpe, rest_seconds
    )
    select
      new_exercise_id,
      coalesce(routine_set.set_no, (pg_catalog.row_number() over (
        order by routine_set.id
      ))::integer),
      coalesce(routine_set.type, 'normal'),
      routine_set.target_weight,
      routine_set.target_reps,
      routine_set.duration_sec,
      routine_set.distance_m,
      routine_set.intensity_rpe,
      routine_set.rest_seconds
    from public.coaching_routine_sets routine_set
    where routine_set.routine_exercise_id = source_exercise.id
    order by routine_set.set_no, routine_set.id;
  end loop;

  update public.coaching_routines
  set cumulative_users = cumulative_users + 1,
      updated_at = pg_catalog.now()
  where id = p_source_routine_id;

  if p_market_routine_id is not null then
    update public.market_routines
    set coaching_count = coaching_count + 1
    where id = p_market_routine_id;
  end if;

  return private.personal_routine_json(new_routine_id);
end
$function$;

create or replace function private.save_coaching_routine(
  p_routine_id uuid,
  p_owner_role text,
  p_title text,
  p_intro text,
  p_difficulty text,
  p_price numeric,
  p_exercises jsonb,
  p_request_id uuid default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  actor_user_id uuid := (select auth.uid());
  normalized_owner_role text := pg_catalog.lower(pg_catalog.btrim(
    coalesce(p_owner_role, '')
  ));
  normalized_title text := pg_catalog.btrim(coalesce(p_title, ''));
  normalized_intro text := nullif(pg_catalog.btrim(coalesce(p_intro, '')), '');
  normalized_difficulty text := pg_catalog.lower(pg_catalog.btrim(
    coalesce(p_difficulty, '')
  ));
  normalized_price numeric := coalesce(p_price, 0);
  owner_trainer_id uuid;
  owner_gym_id uuid;
  current_row public.coaching_routines%rowtype;
  saved_routine_id uuid;
  exercise_item jsonb;
  exercise_number bigint;
  exercise_name text;
  exercise_target text;
  base_exercise_text text;
  is_cardio_exercise boolean;
  new_exercise_id uuid;
  sets_value jsonb;
  set_item jsonb;
  set_number bigint;
  set_type text;
  target_weight_value numeric;
  target_reps_value integer;
  duration_seconds_value integer;
  distance_meters_value numeric;
  intensity_rpe_value numeric;
  rest_seconds_value integer;
  request_hash text;
  cached_response jsonb;
  response_value jsonb;
begin
  if actor_user_id is null then
    raise exception using
      errcode = '42501',
      message = 'Authentication is required.';
  end if;

  if normalized_owner_role not in ('trainer', 'gym') then
    raise exception using
      errcode = '22023',
      message = 'owner_role must be trainer or gym.';
  end if;

  if pg_catalog.char_length(normalized_title) not between 1 and 120 then
    raise exception using
      errcode = '22023',
      message = 'Routine title must contain 1 to 120 characters.';
  end if;

  if normalized_intro is not null
     and pg_catalog.char_length(normalized_intro) > 2000 then
    raise exception using
      errcode = '22023',
      message = 'Routine introduction is too long.';
  end if;

  if normalized_difficulty not in ('beginner', 'intermediate', 'advanced') then
    raise exception using
      errcode = '22023',
      message = 'Unknown routine difficulty.';
  end if;

  if normalized_price < 0 or normalized_price > 100000000 then
    raise exception using
      errcode = '22023',
      message = 'Routine price is outside the supported range.';
  end if;

  if p_exercises is null
     or pg_catalog.jsonb_typeof(p_exercises) <> 'array'
     or pg_catalog.jsonb_array_length(p_exercises) not between 1 and 50 then
    raise exception using
      errcode = '22023',
      message = 'A routine requires between 1 and 50 exercises.';
  end if;

  if normalized_owner_role = 'trainer' then
    select id into owner_trainer_id
    from public.trainers
    where user_id = actor_user_id
      and status = 'approved'
    limit 1;

    if owner_trainer_id is null then
      raise exception using
        errcode = '42501',
        message = 'An approved trainer profile is required.';
    end if;
  else
    select id into owner_gym_id
    from public.gyms
    where owner_user_id = actor_user_id
      and status = 'verified'
    order by created_at
    limit 1;

    if owner_gym_id is null then
      raise exception using
        errcode = '42501',
        message = 'A verified gym profile is required.';
    end if;
  end if;

  request_hash := private.routine_request_hash(pg_catalog.jsonb_build_object(
    'routine_id', p_routine_id,
    'owner_role', normalized_owner_role,
    'title', normalized_title,
    'intro', normalized_intro,
    'difficulty', normalized_difficulty,
    'price', normalized_price,
    'exercises', p_exercises
  ));
  cached_response := private.begin_routine_rpc_request(
    actor_user_id, 'save_coaching_routine', p_request_id, request_hash
  );
  if cached_response is not null then
    return cached_response;
  end if;

  if p_routine_id is null then
    insert into public.coaching_routines (
      trainer_id, gym_id, title, intro, price, difficulty, status,
      reject_reason, submitted_at, submitted_by_user_id,
      reviewed_at, reviewed_by_user_id
    ) values (
      owner_trainer_id, owner_gym_id, normalized_title, normalized_intro,
      normalized_price, normalized_difficulty, 'draft',
      null, null, null, null, null
    )
    returning id into saved_routine_id;
  else
    select * into current_row
    from public.coaching_routines
    where id = p_routine_id
    for update;

    if not found then
      raise exception using
        errcode = 'P0002',
        message = 'The routine was not found.';
    end if;

    if current_row.status not in ('draft', 'rejected') then
      raise exception using
        errcode = '55000',
        message = 'Only draft or rejected routines can be edited.';
    end if;

    if current_row.trainer_id is distinct from owner_trainer_id
       or current_row.gym_id is distinct from owner_gym_id then
      raise exception using
        errcode = '42501',
        message = 'The routine belongs to a different workspace.';
    end if;

    update public.coaching_routines
    set title = normalized_title,
        intro = normalized_intro,
        price = normalized_price,
        difficulty = normalized_difficulty,
        status = 'draft',
        reject_reason = null,
        submitted_at = null,
        submitted_by_user_id = null,
        reviewed_at = null,
        reviewed_by_user_id = null,
        updated_at = pg_catalog.now()
    where id = current_row.id
    returning id into saved_routine_id;

    delete from public.coaching_routine_exercises
    where routine_id = saved_routine_id;
  end if;

  for exercise_item, exercise_number in
    select value, ordinality
    from pg_catalog.jsonb_array_elements(p_exercises) with ordinality
  loop
    if pg_catalog.jsonb_typeof(exercise_item) <> 'object' then
      raise exception using
        errcode = '22023',
        message = 'Every exercise must be a JSON object.';
    end if;

    exercise_name := pg_catalog.btrim(coalesce(exercise_item->>'name', ''));
    exercise_target := pg_catalog.btrim(coalesce(
      exercise_item->>'target_muscle',
      exercise_item->>'targetMuscle',
      ''
    ));
    base_exercise_text := nullif(pg_catalog.btrim(coalesce(
      exercise_item->>'base_exercise_id',
      exercise_item->>'baseExerciseId',
      ''
    )), '');
    is_cardio_exercise := pg_catalog.lower(exercise_target)
      in ('유산소', 'cardio', 'aerobic');

    if pg_catalog.char_length(exercise_name) not between 1 and 120 then
      raise exception using
        errcode = '22023',
        message = 'Every exercise requires a name of 1 to 120 characters.';
    end if;
    if pg_catalog.char_length(exercise_target) not between 1 and 80 then
      raise exception using
        errcode = '22023',
        message = 'Every exercise requires a target muscle.';
    end if;

    sets_value := coalesce(exercise_item->'sets', '[]'::jsonb);
    if pg_catalog.jsonb_typeof(sets_value) <> 'array'
       or pg_catalog.jsonb_array_length(sets_value) not between 1 and 20 then
      raise exception using
        errcode = '22023',
        message = 'Every exercise requires between 1 and 20 sets.';
    end if;

    begin
      insert into public.coaching_routine_exercises (
        routine_id, base_exercise_id, name, target_muscle, order_index
      ) values (
        saved_routine_id,
        case when base_exercise_text is null
          then null else base_exercise_text::uuid end,
        exercise_name,
        exercise_target,
        (exercise_number - 1)::integer
      )
      returning id into new_exercise_id;
    exception
      when invalid_text_representation then
        raise exception using
          errcode = '22023',
          message = 'base_exercise_id must be a UUID.';
    end;

    for set_item, set_number in
      select value, ordinality
      from pg_catalog.jsonb_array_elements(sets_value) with ordinality
    loop
      if pg_catalog.jsonb_typeof(set_item) <> 'object' then
        raise exception using
          errcode = '22023',
          message = 'Every set must be a JSON object.';
      end if;

      set_type := pg_catalog.lower(pg_catalog.btrim(coalesce(
        set_item->>'type', 'normal'
      )));
      if set_type not in ('normal', 'warmup', 'drop', 'failure') then
        raise exception using
          errcode = '22023',
          message = 'Unknown routine set type.';
      end if;

      begin
        target_weight_value := nullif(pg_catalog.btrim(coalesce(
          set_item->>'target_weight',
          set_item->>'targetWeight',
          ''
        )), '')::numeric;
        target_reps_value := nullif(pg_catalog.btrim(coalesce(
          set_item->>'target_reps',
          set_item->>'targetReps',
          ''
        )), '')::integer;
        duration_seconds_value := nullif(pg_catalog.btrim(coalesce(
          set_item->>'duration_sec',
          set_item->>'durationSeconds',
          ''
        )), '')::integer;
        distance_meters_value := nullif(pg_catalog.btrim(coalesce(
          set_item->>'distance_m',
          set_item->>'distanceMeters',
          ''
        )), '')::numeric;
        intensity_rpe_value := nullif(pg_catalog.btrim(coalesce(
          set_item->>'intensity_rpe',
          set_item->>'intensityRpe',
          ''
        )), '')::numeric;
        rest_seconds_value := coalesce(nullif(pg_catalog.btrim(coalesce(
          set_item->>'rest_seconds',
          set_item->>'restSeconds',
          ''
        )), '')::integer, 90);
      exception
        when invalid_text_representation or numeric_value_out_of_range then
          raise exception using
            errcode = '22023',
            message = 'Routine set metrics must be numeric.';
      end;

      duration_seconds_value := nullif(duration_seconds_value, 0);
      distance_meters_value := nullif(distance_meters_value, 0);
      intensity_rpe_value := nullif(intensity_rpe_value, 0);

      if target_weight_value is not null
         and target_weight_value not between 0 and 5000 then
        raise exception using
          errcode = '22023',
          message = 'Target weight is outside the supported range.';
      end if;
      if duration_seconds_value is not null
         and duration_seconds_value not between 1 and 604800 then
        raise exception using
          errcode = '22023',
          message = 'Duration must be between 1 second and 7 days.';
      end if;
      if distance_meters_value is not null
         and distance_meters_value not between 0.01 and 999999.99 then
        raise exception using
          errcode = '22023',
          message = 'Distance is outside the supported range.';
      end if;
      if intensity_rpe_value is not null
         and intensity_rpe_value not between 1 and 10 then
        raise exception using
          errcode = '22023',
          message = 'Intensity RPE must be between 1 and 10.';
      end if;
      if rest_seconds_value not between 0 and 3600 then
        raise exception using
          errcode = '22023',
          message = 'Rest time must be between 0 and 3600 seconds.';
      end if;

      if is_cardio_exercise then
        if duration_seconds_value is null and distance_meters_value is null then
          raise exception using
            errcode = '22023',
            message = 'Cardio sets require a duration or distance.';
        end if;
        target_weight_value := null;
        target_reps_value := null;
      elsif target_reps_value is null
         or target_reps_value not between 1 and 1000 then
        raise exception using
          errcode = '22023',
          message = 'Target repetitions must be between 1 and 1000.';
      end if;

      insert into public.coaching_routine_sets (
        routine_exercise_id, set_no, type,
        target_weight, target_reps, duration_sec, distance_m,
        intensity_rpe, rest_seconds
      ) values (
        new_exercise_id,
        set_number::integer,
        set_type,
        target_weight_value,
        target_reps_value,
        duration_seconds_value,
        distance_meters_value,
        intensity_rpe_value,
        rest_seconds_value
      );
    end loop;
  end loop;

  response_value := private.coaching_routine_json(saved_routine_id);
  return private.finish_routine_rpc_request(
    actor_user_id, 'save_coaching_routine', p_request_id,
    request_hash, response_value
  );
end
$function$;

create or replace function private.save_personal_routine(
  p_routine_id uuid,
  p_name text,
  p_description text,
  p_color text,
  p_exercises jsonb,
  p_request_id uuid default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  actor_user_id uuid := (select auth.uid());
  normalized_name text := pg_catalog.btrim(coalesce(p_name, ''));
  normalized_description text := nullif(
    pg_catalog.btrim(coalesce(p_description, '')),
    ''
  );
  normalized_color text := pg_catalog.upper(
    pg_catalog.btrim(coalesce(p_color, ''))
  );
  current_row public.routines%rowtype;
  exercise_item jsonb;
  exercise_number bigint;
  exercise_name text;
  exercise_target text;
  base_exercise_text text;
  is_cardio_exercise boolean;
  new_exercise_id uuid;
  sets_value jsonb;
  set_item jsonb;
  set_number bigint;
  set_type text;
  target_weight_value numeric;
  target_reps_value integer;
  duration_seconds_value integer;
  distance_meters_value numeric;
  intensity_rpe_value numeric;
  rest_seconds_value integer;
  request_hash text;
  cached_response jsonb;
  response_value jsonb;
begin
  if actor_user_id is null then
    raise exception using
      errcode = '42501',
      message = 'Authentication is required.';
  end if;

  if p_routine_id is null then
    raise exception using
      errcode = '22023',
      message = 'routine_id is required.';
  end if;

  if pg_catalog.char_length(normalized_name) not between 1 and 120 then
    raise exception using
      errcode = '22023',
      message = 'Routine name must contain 1 to 120 characters.';
  end if;

  if normalized_description is not null
     and pg_catalog.char_length(normalized_description) > 2000 then
    raise exception using
      errcode = '22023',
      message = 'Routine description is too long.';
  end if;

  if normalized_color !~ '^#[0-9A-F]{6}$' then
    raise exception using
      errcode = '22023',
      message = 'Routine color must use #RRGGBB format.';
  end if;

  if p_exercises is null
     or pg_catalog.jsonb_typeof(p_exercises) <> 'array'
     or pg_catalog.jsonb_array_length(p_exercises) not between 1 and 50 then
    raise exception using
      errcode = '22023',
      message = 'A routine requires between 1 and 50 exercises.';
  end if;

  request_hash := private.routine_request_hash(pg_catalog.jsonb_build_object(
    'routine_id', p_routine_id,
    'name', normalized_name,
    'description', normalized_description,
    'color', normalized_color,
    'exercises', p_exercises
  ));
  cached_response := private.begin_routine_rpc_request(
    actor_user_id,
    'save_personal_routine',
    p_request_id,
    request_hash
  );
  if cached_response is not null then
    return cached_response;
  end if;

  select * into current_row
  from public.routines routine
  where routine.id = p_routine_id
    and routine.owner_user_id = actor_user_id
  for update;

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'The personal routine was not found.';
  end if;

  update public.routines
  set name = normalized_name,
      description = normalized_description,
      color = normalized_color,
      updated_at = pg_catalog.now()
  where id = current_row.id;

  delete from public.routine_exercises
  where routine_id = current_row.id;

  for exercise_item, exercise_number in
    select value, ordinality
    from pg_catalog.jsonb_array_elements(p_exercises) with ordinality
  loop
    if pg_catalog.jsonb_typeof(exercise_item) <> 'object' then
      raise exception using
        errcode = '22023',
        message = 'Every exercise must be a JSON object.';
    end if;

    exercise_name := pg_catalog.btrim(coalesce(exercise_item->>'name', ''));
    exercise_target := pg_catalog.btrim(coalesce(
      exercise_item->>'target_muscle',
      exercise_item->>'targetMuscle',
      ''
    ));
    base_exercise_text := nullif(pg_catalog.btrim(coalesce(
      exercise_item->>'base_exercise_id',
      exercise_item->>'baseExerciseId',
      ''
    )), '');
    is_cardio_exercise := pg_catalog.lower(exercise_target)
      in ('유산소', 'cardio', 'aerobic');

    if pg_catalog.char_length(exercise_name) not between 1 and 120 then
      raise exception using
        errcode = '22023',
        message = 'Every exercise requires a name of 1 to 120 characters.';
    end if;
    if pg_catalog.char_length(exercise_target) not between 1 and 80 then
      raise exception using
        errcode = '22023',
        message = 'Every exercise requires a target muscle.';
    end if;

    sets_value := coalesce(exercise_item->'sets', '[]'::jsonb);
    if pg_catalog.jsonb_typeof(sets_value) <> 'array'
       or pg_catalog.jsonb_array_length(sets_value) not between 1 and 20 then
      raise exception using
        errcode = '22023',
        message = 'Every exercise requires between 1 and 20 sets.';
    end if;

    begin
      insert into public.routine_exercises (
        routine_id, base_exercise_id, name, target_muscle, order_index
      ) values (
        current_row.id,
        case when base_exercise_text is null
          then null else base_exercise_text::uuid end,
        exercise_name,
        exercise_target,
        (exercise_number - 1)::integer
      )
      returning id into new_exercise_id;
    exception
      when invalid_text_representation then
        raise exception using
          errcode = '22023',
          message = 'base_exercise_id must be a UUID.';
    end;

    for set_item, set_number in
      select value, ordinality
      from pg_catalog.jsonb_array_elements(sets_value) with ordinality
    loop
      if pg_catalog.jsonb_typeof(set_item) <> 'object' then
        raise exception using
          errcode = '22023',
          message = 'Every set must be a JSON object.';
      end if;

      set_type := pg_catalog.lower(pg_catalog.btrim(coalesce(
        set_item->>'type', 'normal'
      )));
      if set_type not in ('normal', 'warmup', 'drop', 'failure') then
        raise exception using
          errcode = '22023',
          message = 'Unknown routine set type.';
      end if;

      begin
        target_weight_value := nullif(pg_catalog.btrim(coalesce(
          set_item->>'target_weight',
          set_item->>'targetWeight',
          ''
        )), '')::numeric;
        target_reps_value := nullif(pg_catalog.btrim(coalesce(
          set_item->>'target_reps',
          set_item->>'targetReps',
          ''
        )), '')::integer;
        duration_seconds_value := nullif(pg_catalog.btrim(coalesce(
          set_item->>'duration_sec',
          set_item->>'durationSeconds',
          ''
        )), '')::integer;
        distance_meters_value := nullif(pg_catalog.btrim(coalesce(
          set_item->>'distance_m',
          set_item->>'distanceMeters',
          ''
        )), '')::numeric;
        intensity_rpe_value := nullif(pg_catalog.btrim(coalesce(
          set_item->>'intensity_rpe',
          set_item->>'intensityRpe',
          ''
        )), '')::numeric;
        rest_seconds_value := coalesce(nullif(pg_catalog.btrim(coalesce(
          set_item->>'rest_seconds',
          set_item->>'restSeconds',
          ''
        )), '')::integer, 90);
      exception
        when invalid_text_representation or numeric_value_out_of_range then
          raise exception using
            errcode = '22023',
            message = 'Routine set metrics must be numeric.';
      end;

      duration_seconds_value := nullif(duration_seconds_value, 0);
      distance_meters_value := nullif(distance_meters_value, 0);
      intensity_rpe_value := nullif(intensity_rpe_value, 0);

      if target_weight_value is not null
         and target_weight_value not between 0 and 5000 then
        raise exception using
          errcode = '22023',
          message = 'Target weight is outside the supported range.';
      end if;
      if duration_seconds_value is not null
         and duration_seconds_value not between 1 and 604800 then
        raise exception using
          errcode = '22023',
          message = 'Duration must be between 1 second and 7 days.';
      end if;
      if distance_meters_value is not null
         and distance_meters_value not between 0.01 and 999999.99 then
        raise exception using
          errcode = '22023',
          message = 'Distance is outside the supported range.';
      end if;
      if intensity_rpe_value is not null
         and intensity_rpe_value not between 1 and 10 then
        raise exception using
          errcode = '22023',
          message = 'Intensity RPE must be between 1 and 10.';
      end if;
      if rest_seconds_value not between 0 and 3600 then
        raise exception using
          errcode = '22023',
          message = 'Rest time must be between 0 and 3600 seconds.';
      end if;

      if is_cardio_exercise then
        if duration_seconds_value is null and distance_meters_value is null then
          raise exception using
            errcode = '22023',
            message = 'Cardio sets require a duration or distance.';
        end if;
        target_weight_value := null;
        target_reps_value := null;
      elsif target_reps_value is null
         or target_reps_value not between 0 and 1000 then
        raise exception using
          errcode = '22023',
          message = 'Target repetitions must be between 0 and 1000.';
      end if;

      insert into public.routine_sets (
        routine_exercise_id, set_no, type,
        target_weight, target_reps, duration_sec, distance_m,
        intensity_rpe, rest_seconds
      ) values (
        new_exercise_id,
        set_number::integer,
        set_type,
        target_weight_value,
        target_reps_value,
        duration_seconds_value,
        distance_meters_value,
        intensity_rpe_value,
        rest_seconds_value
      );
    end loop;
  end loop;

  response_value := private.personal_routine_json(current_row.id);
  return private.finish_routine_rpc_request(
    actor_user_id,
    'save_personal_routine',
    p_request_id,
    request_hash,
    response_value
  );
end
$function$;

create or replace function private.sync_my_workout_snapshot(
  p_sessions jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := (select auth.uid());
  v_session jsonb;
  v_exercise jsonb;
  v_set jsonb;
  v_session_id uuid;
  v_exercise_id uuid;
  v_date date;
  v_session_count integer;
  v_exercise_count integer;
  v_set_count integer;
  v_total_exercises integer := 0;
  v_total_sets integer := 0;
  v_order integer;
  v_type text;
  v_client_id text;
  v_set_no integer;
  v_weight numeric;
  v_reps integer;
  v_duration_seconds integer;
  v_distance_meters numeric;
  v_intensity_rpe numeric;
  v_has_duration boolean;
  v_has_distance boolean;
  v_has_intensity_rpe boolean;
  v_completed boolean;
  v_rest_seconds integer;
  v_is_cardio boolean;
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if p_sessions is null
     or pg_catalog.jsonb_typeof(p_sessions) <> 'array' then
    raise exception 'sessions must be an array' using errcode = '22023';
  end if;
  if pg_catalog.pg_column_size(p_sessions) > 5242880 then
    raise exception 'workout payload is too large' using errcode = '22023';
  end if;

  perform 1
  from public.users account_user
  where account_user.id = v_user_id
  for update;
  if not found then
    raise exception 'Authenticated profile is missing' using errcode = '42501';
  end if;

  v_session_count := pg_catalog.jsonb_array_length(p_sessions);
  if v_session_count > 730 then
    raise exception 'Too many workout sessions' using errcode = '22023';
  end if;

  create temporary table if not exists pg_temp.setflow_sync_dates (
    workout_date date primary key
  ) on commit drop;
  truncate table pg_temp.setflow_sync_dates;

  create temporary table if not exists pg_temp.setflow_sync_exercises (
    session_id uuid not null,
    client_id text not null,
    primary key (session_id, client_id)
  ) on commit drop;
  truncate table pg_temp.setflow_sync_exercises;

  create temporary table if not exists pg_temp.setflow_sync_sets (
    exercise_id uuid not null,
    set_no integer not null,
    primary key (exercise_id, set_no)
  ) on commit drop;
  truncate table pg_temp.setflow_sync_sets;

  for v_session in
    select value from pg_catalog.jsonb_array_elements(p_sessions)
  loop
    begin
      v_date := (v_session ->> 'date')::timestamptz::date;
    exception when others then
      raise exception 'Invalid workout date' using errcode = '22023';
    end;

    if v_date is null then
      raise exception 'Workout date is required' using errcode = '22023';
    end if;

    insert into pg_temp.setflow_sync_dates(workout_date) values (v_date)
    on conflict do nothing;
    if not found then
      raise exception 'Duplicate workout date' using errcode = '22023';
    end if;

    insert into public.workout_sessions(user_id, date, updated_at)
    values (v_user_id, v_date, pg_catalog.now())
    on conflict (user_id, date) do update
      set updated_at = excluded.updated_at
    returning id into v_session_id;

    if pg_catalog.jsonb_typeof(v_session -> 'exercises') <> 'array' then
      raise exception 'exercises must be an array' using errcode = '22023';
    end if;
    v_exercise_count := pg_catalog.jsonb_array_length(
      v_session -> 'exercises'
    );
    if v_exercise_count > 100 then
      raise exception 'Too many exercises in a session' using errcode = '22023';
    end if;
    v_total_exercises := v_total_exercises + v_exercise_count;
    if v_total_exercises > 5000 then
      raise exception 'Too many exercises in workout payload'
        using errcode = '22023';
    end if;

    v_order := 0;
    for v_exercise in
      select value
      from pg_catalog.jsonb_array_elements(v_session -> 'exercises')
    loop
      if nullif(pg_catalog.btrim(v_exercise ->> 'name'), '') is null then
        raise exception 'Exercise name is required' using errcode = '22023';
      end if;
      v_client_id := nullif(pg_catalog.btrim(v_exercise ->> 'client_id'), '');
      if v_client_id is null
         or pg_catalog.char_length(v_client_id) > 200 then
        raise exception
          'Exercise client_id is required and must be at most 200 characters'
          using errcode = '22023';
      end if;
      v_is_cardio := pg_catalog.lower(pg_catalog.btrim(coalesce(
        v_exercise ->> 'target_muscle',
        ''
      ))) in ('유산소', 'cardio', 'aerobic');

      insert into public.workout_exercises(
        session_id,
        client_id,
        base_exercise_id,
        name,
        target_muscle,
        order_index
      ) values (
        v_session_id,
        v_client_id,
        case
          when coalesce(v_exercise ->> 'base_exercise_id', '')
            ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
          then (
            select master_exercise.id
            from public.master_exercises master_exercise
            where master_exercise.id =
              (v_exercise ->> 'base_exercise_id')::uuid
              and (
                not master_exercise.is_custom
                or master_exercise.owner_user_id = v_user_id
              )
          )
          else null
        end,
        pg_catalog.left(pg_catalog.btrim(v_exercise ->> 'name'), 120),
        nullif(pg_catalog.left(pg_catalog.btrim(coalesce(
          v_exercise ->> 'target_muscle',
          ''
        )), 80), ''),
        v_order
      )
      on conflict (session_id, client_id) do update
      set base_exercise_id = excluded.base_exercise_id,
          name = excluded.name,
          target_muscle = excluded.target_muscle,
          order_index = excluded.order_index
      returning id into v_exercise_id;

      insert into pg_temp.setflow_sync_exercises(session_id, client_id)
      values (v_session_id, v_client_id)
      on conflict do nothing;
      if not found then
        raise exception 'Duplicate exercise client_id in a session'
          using errcode = '22023';
      end if;
      v_order := v_order + 1;

      if pg_catalog.jsonb_typeof(v_exercise -> 'sets') <> 'array' then
        raise exception 'sets must be an array' using errcode = '22023';
      end if;
      v_set_count := pg_catalog.jsonb_array_length(v_exercise -> 'sets');
      if v_set_count > 100 then
        raise exception 'Too many sets in an exercise' using errcode = '22023';
      end if;
      v_total_sets := v_total_sets + v_set_count;
      if v_total_sets > 50000 then
        raise exception 'Too many sets in workout payload'
          using errcode = '22023';
      end if;

      for v_set in
        select value from pg_catalog.jsonb_array_elements(v_exercise -> 'sets')
      loop
        v_has_duration :=
          (v_set ? 'duration_sec') or (v_set ? 'durationSeconds');
        v_has_distance :=
          (v_set ? 'distance_m') or (v_set ? 'distanceMeters');
        v_has_intensity_rpe :=
          (v_set ? 'intensity_rpe') or (v_set ? 'intensityRpe');
        begin
          v_set_no := (v_set ->> 'set_no')::integer;
          v_weight := coalesce(nullif(pg_catalog.btrim(coalesce(
            v_set ->> 'weight', ''
          )), '')::numeric, 0);
          v_reps := coalesce(nullif(pg_catalog.btrim(coalesce(
            v_set ->> 'reps', ''
          )), '')::integer, 0);
          v_duration_seconds := nullif(pg_catalog.btrim(coalesce(
            v_set ->> 'duration_sec',
            v_set ->> 'durationSeconds',
            ''
          )), '')::integer;
          v_distance_meters := nullif(pg_catalog.btrim(coalesce(
            v_set ->> 'distance_m',
            v_set ->> 'distanceMeters',
            ''
          )), '')::numeric;
          v_intensity_rpe := nullif(pg_catalog.btrim(coalesce(
            v_set ->> 'intensity_rpe',
            v_set ->> 'intensityRpe',
            ''
          )), '')::numeric;
          v_completed := coalesce((v_set ->> 'completed')::boolean, false);
          v_rest_seconds := coalesce(nullif(pg_catalog.btrim(coalesce(
            v_set ->> 'rest_seconds',
            v_set ->> 'restSeconds',
            ''
          )), '')::integer, 90);
        exception
          when invalid_text_representation or numeric_value_out_of_range then
            raise exception 'Workout set metrics must be numeric'
              using errcode = '22023';
        end;

        if v_set_no not between 1 and 100 then
          raise exception 'Set number must be between 1 and 100'
            using errcode = '22023';
        end if;

        v_duration_seconds := nullif(v_duration_seconds, 0);
        v_distance_meters := nullif(v_distance_meters, 0);
        v_intensity_rpe := nullif(v_intensity_rpe, 0);

        if v_duration_seconds is not null
           and v_duration_seconds not between 1 and 604800 then
          raise exception 'Duration must be between 1 second and 7 days'
            using errcode = '22023';
        end if;
        if v_distance_meters is not null
           and v_distance_meters not between 0.01 and 999999.99 then
          raise exception 'Distance is outside the supported range'
            using errcode = '22023';
        end if;
        if v_intensity_rpe is not null
           and v_intensity_rpe not between 1 and 10 then
          raise exception 'Intensity RPE must be between 1 and 10'
            using errcode = '22023';
        end if;

        v_weight := greatest(0, least(9999.99, v_weight));
        v_reps := greatest(0, least(1000, v_reps));
        v_rest_seconds := greatest(
          0,
          least(3600, v_rest_seconds)
        );
        if v_is_cardio then
          v_weight := 0;
          v_reps := 0;
        end if;

        insert into pg_temp.setflow_sync_sets(exercise_id, set_no)
        values (v_exercise_id, v_set_no)
        on conflict do nothing;
        if not found then
          raise exception 'Duplicate set number in an exercise'
            using errcode = '22023';
        end if;

        v_type := case pg_catalog.lower(coalesce(v_set ->> 'type', 'normal'))
          when 'warmup' then 'warmup'
          when 'drop' then 'drop'
          when 'failure' then 'fail'
          when 'fail' then 'fail'
          else 'normal'
        end;

        insert into public.workout_sets(
          exercise_id,
          set_no,
          type,
          weight,
          reps,
          duration_sec,
          distance_m,
          intensity_rpe,
          completed,
          completed_at,
          estimated_1rm,
          rest_seconds
        ) values (
          v_exercise_id,
          v_set_no,
          v_type,
          v_weight,
          v_reps,
          v_duration_seconds,
          v_distance_meters,
          v_intensity_rpe,
          v_completed,
          case when v_completed then pg_catalog.now() else null end,
          case
            when v_completed
              and v_type = 'normal'
              and v_reps between 1 and 10
              and v_weight > 0
              and v_duration_seconds is null
              and v_distance_meters is null
            then case
              when v_reps = 1 then pg_catalog.round(v_weight, 2)
              else least(
                9999.99,
                pg_catalog.round((
                  v_weight * (1 + v_reps::numeric / 30)
                  + v_weight * 36 / (37 - v_reps)
                ) / 2, 2)
              )
            end
            else null
          end,
          v_rest_seconds
        )
        on conflict (exercise_id, set_no) do update
        set type = excluded.type,
            weight = excluded.weight,
            reps = excluded.reps,
            duration_sec = case
              when v_has_duration then excluded.duration_sec
              else public.workout_sets.duration_sec
            end,
            distance_m = case
              when v_has_distance then excluded.distance_m
              else public.workout_sets.distance_m
            end,
            intensity_rpe = case
              when v_has_intensity_rpe then excluded.intensity_rpe
              else public.workout_sets.intensity_rpe
            end,
            completed = excluded.completed,
            completed_at = case
              when not excluded.completed then null
              when public.workout_sets.completed_at is null
                then pg_catalog.now()
              else public.workout_sets.completed_at
            end,
            estimated_1rm = excluded.estimated_1rm,
            rest_seconds = excluded.rest_seconds;
      end loop;
    end loop;
  end loop;

  delete from public.workout_sets workout_set
  using public.workout_exercises exercise, public.workout_sessions session
  where workout_set.exercise_id = exercise.id
    and exercise.session_id = session.id
    and session.user_id = v_user_id
    and not exists (
      select 1
      from pg_temp.setflow_sync_sets keep
      where keep.exercise_id = workout_set.exercise_id
        and keep.set_no = workout_set.set_no
    );

  delete from public.workout_exercises exercise
  using public.workout_sessions session
  where exercise.session_id = session.id
    and session.user_id = v_user_id
    and not exists (
      select 1
      from pg_temp.setflow_sync_exercises keep
      where keep.session_id = exercise.session_id
        and keep.client_id = exercise.client_id
    );

  delete from public.workout_sessions session
  where session.user_id = v_user_id
    and not exists (
      select 1
      from pg_temp.setflow_sync_dates keep
      where keep.workout_date = session.date
    );

  update public.members member
  set last_activity_at = (
        select pg_catalog.max(session.date)::timestamptz
        from public.workout_sessions session
        where session.user_id = v_user_id
      ),
      completion_rate = coalesce((
        select pg_catalog.round(
          100.0 * pg_catalog.count(*) filter (where workout_set.completed)
          / nullif(pg_catalog.count(*), 0),
          2
        )
        from public.workout_sessions session
        join public.workout_exercises exercise
          on exercise.session_id = session.id
        join public.workout_sets workout_set
          on workout_set.exercise_id = exercise.id
        where session.user_id = v_user_id
          and session.date >= current_date - 28
      ), 0)
  where member.user_id = v_user_id;

  return pg_catalog.jsonb_build_object(
    'session_count', v_session_count,
    'exercise_count', v_total_exercises,
    'set_count', v_total_sets,
    'synced_at', pg_catalog.now()
  );
end;
$function$;

create or replace function private.apply_routine(
  p_routine uuid,
  p_date date
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_session_id uuid;
  v_ex record;
  v_new_exercise_id uuid;
begin
  if v_uid is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;
  if p_routine is null or p_date is null then
    raise exception using
      errcode = '22023', message = 'Routine and date are required';
  end if;
  if not exists (
    select 1
    from public.routines routine
    where routine.id = p_routine
      and routine.owner_user_id = v_uid
  ) then
    raise exception using
      errcode = '42501', message = 'An owned routine is required';
  end if;

  insert into public.workout_sessions (user_id, date)
  values (v_uid, p_date)
  on conflict (user_id, date) do nothing;

  select session.id
    into v_session_id
  from public.workout_sessions session
  where session.user_id = v_uid
    and session.date = p_date;

  for v_ex in
    select exercise.*
    from public.routine_exercises exercise
    where exercise.routine_id = p_routine
    order by exercise.order_index, exercise.id
  loop
    insert into public.workout_exercises (
      session_id,
      client_id,
      base_exercise_id,
      name,
      target_muscle,
      order_index
    ) values (
      v_session_id,
      'routine-' || extensions.gen_random_uuid()::text,
      v_ex.base_exercise_id,
      v_ex.name,
      v_ex.target_muscle,
      v_ex.order_index
    )
    returning id into v_new_exercise_id;

    insert into public.workout_sets (
      exercise_id,
      set_no,
      type,
      weight,
      reps,
      duration_sec,
      distance_m,
      intensity_rpe,
      completed,
      rest_seconds
    )
    select
      v_new_exercise_id,
      routine_set.set_no,
      case routine_set.type when 'failure' then 'fail'
        else coalesce(routine_set.type, 'normal') end,
      coalesce(routine_set.target_weight, 0),
      coalesce(routine_set.target_reps, 0),
      routine_set.duration_sec,
      routine_set.distance_m,
      routine_set.intensity_rpe,
      false,
      routine_set.rest_seconds
    from public.routine_sets routine_set
    where routine_set.routine_exercise_id = v_ex.id
    order by routine_set.set_no;
  end loop;

  return v_session_id;
end
$function$;

create or replace function private.copy_session(
  p_from date,
  p_to date
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_source_id uuid;
  v_destination_id uuid;
  v_ex record;
  v_new_exercise_id uuid;
begin
  if v_uid is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;
  if p_from is null or p_to is null or p_from = p_to then
    raise exception using
      errcode = '22023',
      message = 'Distinct source and target dates are required';
  end if;

  select session.id
    into v_source_id
  from public.workout_sessions session
  where session.user_id = v_uid
    and session.date = p_from;
  if not found then
    raise exception using
      errcode = 'P0002', message = 'Owned source session not found';
  end if;

  insert into public.workout_sessions (user_id, date)
  values (v_uid, p_to)
  on conflict (user_id, date) do nothing;
  select session.id
    into v_destination_id
  from public.workout_sessions session
  where session.user_id = v_uid
    and session.date = p_to;

  for v_ex in
    select exercise.*
    from public.workout_exercises exercise
    where exercise.session_id = v_source_id
    order by exercise.order_index, exercise.id
  loop
    insert into public.workout_exercises (
      session_id,
      client_id,
      base_exercise_id,
      name,
      target_muscle,
      order_index
    ) values (
      v_destination_id,
      'copy-' || extensions.gen_random_uuid()::text,
      v_ex.base_exercise_id,
      v_ex.name,
      v_ex.target_muscle,
      v_ex.order_index
    )
    returning id into v_new_exercise_id;

    insert into public.workout_sets (
      exercise_id,
      set_no,
      type,
      weight,
      reps,
      duration_sec,
      distance_m,
      intensity_rpe,
      rir,
      memo,
      completed,
      rest_seconds
    )
    select
      v_new_exercise_id,
      workout_set.set_no,
      workout_set.type,
      workout_set.weight,
      workout_set.reps,
      workout_set.duration_sec,
      workout_set.distance_m,
      workout_set.intensity_rpe,
      workout_set.rir,
      workout_set.memo,
      false,
      workout_set.rest_seconds
    from public.workout_sets workout_set
    where workout_set.exercise_id = v_ex.id
    order by workout_set.set_no;
  end loop;

  return v_destination_id;
end
$function$;

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
  v_shared boolean := false;
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
    select coalesce(consent.share_workout_records, false)
    into v_shared
    from public.user_consents consent
    where consent.user_id = v_member.user_id;
    v_shared := coalesce(v_shared, false);
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
    'share_workout_records', v_shared,
    'can_read_workouts', v_can_read,
    'sessions', v_sessions
  );
end;
$function$;

-- CREATE OR REPLACE retains ACLs, but spell them out so a restored database or
-- partially applied branch has the same least-privilege contract.
revoke all on function private.coaching_routine_json(uuid),
  private.personal_routine_json(uuid),
  private.clone_coaching_routine(uuid, uuid, uuid, uuid),
  private.save_coaching_routine(
    uuid, text, text, text, text, numeric, jsonb, uuid
  ),
  private.save_personal_routine(uuid, text, text, text, jsonb, uuid),
  private.sync_my_workout_snapshot(jsonb),
  private.apply_routine(uuid, date),
  private.copy_session(date, date),
  private.get_business_member_detail(uuid, date, date)
  from public, anon, authenticated;

grant execute on function private.coaching_routine_json(uuid),
  private.personal_routine_json(uuid),
  private.clone_coaching_routine(uuid, uuid, uuid, uuid),
  private.save_personal_routine(uuid, text, text, text, jsonb, uuid),
  private.sync_my_workout_snapshot(jsonb)
  to service_role;

grant execute on function private.save_coaching_routine(
    uuid, text, text, text, text, numeric, jsonb, uuid
  ),
  private.apply_routine(uuid, date),
  private.copy_session(date, date),
  private.get_business_member_detail(uuid, date, date)
  to authenticated, service_role;
