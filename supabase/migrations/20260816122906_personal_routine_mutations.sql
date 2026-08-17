-- Keep personal routine edits and deletions atomic with the normalized routine
-- projection. Direct table DML remains revoked from Data API roles.

create index if not exists routine_exercises_routine_id_idx
  on public.routine_exercises (routine_id);

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
  actor_user_id uuid := auth.uid();
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
  new_exercise_id uuid;
  sets_value jsonb;
  set_item jsonb;
  set_number bigint;
  set_type text;
  target_weight_value numeric;
  target_reps_value integer;
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

  -- Child rows are replaced inside this transaction. Source provenance on the
  -- parent row is deliberately retained.
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
       or pg_catalog.jsonb_array_length(sets_value) > 20 then
      raise exception using
        errcode = '22023',
        message = 'Every exercise supports up to 20 sets.';
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
        set_item->>'type',
        'normal'
      )));
      if set_type not in ('normal', 'warmup', 'drop', 'failure') then
        raise exception using
          errcode = '22023',
          message = 'Unknown routine set type.';
      end if;

      if nullif(pg_catalog.btrim(coalesce(
        set_item->>'target_weight',
        set_item->>'targetWeight',
        ''
      )), '') is null then
        target_weight_value := null;
      else
        target_weight_value := coalesce(
          set_item->>'target_weight',
          set_item->>'targetWeight'
        )::numeric;
      end if;

      if nullif(pg_catalog.btrim(coalesce(
        set_item->>'target_reps',
        set_item->>'targetReps',
        ''
      )), '') is null then
        target_reps_value := null;
      else
        target_reps_value := coalesce(
          set_item->>'target_reps',
          set_item->>'targetReps'
        )::integer;
      end if;

      rest_seconds_value := coalesce(nullif(pg_catalog.btrim(coalesce(
        set_item->>'rest_seconds',
        set_item->>'restSeconds',
        ''
      )), '')::integer, 90);

      if target_weight_value is not null
         and (target_weight_value < 0 or target_weight_value > 5000) then
        raise exception using
          errcode = '22023',
          message = 'Target weight is outside the supported range.';
      end if;
      if target_reps_value is not null
         and target_reps_value not between 0 and 1000 then
        raise exception using
          errcode = '22023',
          message = 'Target repetitions must be between 0 and 1000.';
      end if;
      if rest_seconds_value not between 0 and 3600 then
        raise exception using
          errcode = '22023',
          message = 'Rest time must be between 0 and 3600 seconds.';
      end if;

      insert into public.routine_sets (
        routine_exercise_id, set_no, type,
        target_weight, target_reps, rest_seconds
      ) values (
        new_exercise_id,
        set_number::integer,
        set_type,
        target_weight_value,
        target_reps_value,
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

create or replace function private.delete_personal_routine(
  p_routine_id uuid,
  p_request_id uuid default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  actor_user_id uuid := auth.uid();
  deleted_routine_id uuid;
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

  request_hash := private.routine_request_hash(pg_catalog.jsonb_build_object(
    'routine_id', p_routine_id
  ));
  cached_response := private.begin_routine_rpc_request(
    actor_user_id,
    'delete_personal_routine',
    p_request_id,
    request_hash
  );
  if cached_response is not null then
    return cached_response;
  end if;

  delete from public.routines routine
  where routine.id = p_routine_id
    and routine.owner_user_id = actor_user_id
  returning routine.id into deleted_routine_id;

  if deleted_routine_id is null then
    raise exception using
      errcode = 'P0002',
      message = 'The personal routine was not found.';
  end if;

  response_value := pg_catalog.jsonb_build_object(
    'deleted_routine_id',
    deleted_routine_id
  );
  return private.finish_routine_rpc_request(
    actor_user_id,
    'delete_personal_routine',
    p_request_id,
    request_hash,
    response_value
  );
end
$function$;

revoke all on function private.save_personal_routine(
  uuid, text, text, text, jsonb, uuid
) from public, anon;
revoke all on function private.delete_personal_routine(uuid, uuid)
  from public, anon;

grant execute on function private.save_personal_routine(
  uuid, text, text, text, jsonb, uuid
), private.delete_personal_routine(uuid, uuid)
  to authenticated, service_role;

create or replace function public.save_personal_routine(
  routine_id uuid,
  name text,
  description text,
  color text,
  exercises jsonb,
  request_id uuid default null
)
returns jsonb
language sql
volatile
security invoker
set search_path = ''
as $function$
  select private.save_personal_routine($1, $2, $3, $4, $5, $6);
$function$;

create or replace function public.delete_personal_routine(
  routine_id uuid,
  request_id uuid default null
)
returns jsonb
language sql
volatile
security invoker
set search_path = ''
as $function$
  select private.delete_personal_routine($1, $2);
$function$;

revoke all on function public.save_personal_routine(
  uuid, text, text, text, jsonb, uuid
) from public, anon, authenticated;
revoke all on function public.delete_personal_routine(uuid, uuid)
  from public, anon, authenticated;

grant execute on function public.save_personal_routine(
  uuid, text, text, text, jsonb, uuid
), public.delete_personal_routine(uuid, uuid)
  to authenticated, service_role;

comment on function public.save_personal_routine(
  uuid, text, text, text, jsonb, uuid
) is 'Atomically replace an authenticated owner personal routine and its child rows.';
comment on function public.delete_personal_routine(uuid, uuid)
  is 'Idempotently delete an authenticated owner personal routine.';
