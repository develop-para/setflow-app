begin;

-- save_my_app_snapshot serializes on users before touching snapshots. Acquire
-- those same locks first so this one-time trigger/backfill migration cannot
-- deadlock with a device save that is already in flight.
do $lock_snapshot_accounts$
declare
  account_user_id uuid;
begin
  for account_user_id in
    select snapshot.user_id
    from public.app_state_snapshots snapshot
    order by snapshot.user_id
  loop
    perform 1
    from public.users account_user
    where account_user.id = account_user_id
    for update;
  end loop;
end
$lock_snapshot_accounts$;

-- Keep every account preference/profile projection in the same transaction as
-- the authoritative app snapshot.  The client no longer needs a second pair
-- of best-effort upserts after save_my_app_snapshot returns.
alter table public.user_settings
  add column if not exists auto_start_rest_timer boolean not null default true;

alter table public.user_goals
  add column if not exists priority smallint not null default 0;

alter table public.user_goals
  drop constraint if exists user_goals_goal_id_check;
alter table public.user_goals
  add constraint user_goals_goal_id_check
  check (goal_id = any (array[
    'strength'::text,
    'muscle'::text,
    'loss'::text,
    'fitness'::text,
    'health'::text
  ]));

alter table public.user_goals
  drop constraint if exists user_goals_priority_check;
alter table public.user_goals
  add constraint user_goals_priority_check
  check (priority between 0 and 4);

create or replace function private.project_app_snapshot_account_data()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  preferences_value jsonb := coalesce(new.payload -> 'preferences', '{}'::jsonb);
  profile_value jsonb := coalesce(new.payload -> 'profile', '{}'::jsonb);
  goals_value jsonb;
  weight_value numeric;
  height_value numeric;
  age_value smallint;
  gender_value text;
  nickname_value text;
  joined_goals text;
begin
  if pg_catalog.jsonb_typeof(preferences_value) <> 'object'
     or pg_catalog.jsonb_typeof(profile_value) <> 'object' then
    raise exception using
      errcode = '22023',
      message = 'snapshot preferences and profile must be objects';
  end if;

  goals_value := case
    when pg_catalog.jsonb_typeof(profile_value -> 'goals') = 'array'
      then profile_value -> 'goals'
    else '[]'::jsonb
  end;
  if pg_catalog.jsonb_array_length(goals_value) > 5 then
    raise exception using
      errcode = '22023',
      message = 'at most five training goals are supported';
  end if;

  weight_value := case
    when pg_catalog.jsonb_typeof(profile_value -> 'weight') = 'number'
      then (profile_value ->> 'weight')::numeric
    else null
  end;
  height_value := case
    when pg_catalog.jsonb_typeof(profile_value -> 'heightCm') = 'number'
      then (profile_value ->> 'heightCm')::numeric
    else null
  end;
  age_value := case
    when pg_catalog.jsonb_typeof(profile_value -> 'age') = 'number'
      then (profile_value ->> 'age')::smallint
    else null
  end;
  gender_value := case
    when pg_catalog.upper(pg_catalog.btrim(coalesce(profile_value ->> 'gender', '')))
      in ('M', 'F', 'O')
      then pg_catalog.upper(pg_catalog.btrim(profile_value ->> 'gender'))
    else null
  end;
  nickname_value := nullif(pg_catalog.btrim(coalesce(profile_value ->> 'nickname', '')), '');

  if weight_value is not null and weight_value not between 20 and 1000 then
    raise exception using errcode = '22023', message = 'weight is outside the supported range';
  end if;
  if height_value is not null and height_value not between 50 and 300 then
    raise exception using errcode = '22023', message = 'height is outside the supported range';
  end if;
  if age_value is not null and age_value not between 10 and 120 then
    raise exception using errcode = '22023', message = 'age is outside the supported range';
  end if;
  if nickname_value is not null
     and pg_catalog.char_length(nickname_value) not between 2 and 30 then
    raise exception using errcode = '22023', message = 'nickname must contain 2 to 30 characters';
  end if;

  if nickname_value is not null then
    update public.users
    set nickname = nickname_value,
        updated_at = pg_catalog.clock_timestamp()
    where id = new.user_id;
  end if;

  select pg_catalog.string_agg(pg_catalog.left(goal.value, 80), ', ' order by goal.ordinality)
  into joined_goals
  from pg_catalog.jsonb_array_elements_text(goals_value)
    with ordinality as goal(value, ordinality);

  insert into public.user_settings (
    user_id,
    weight_unit,
    theme,
    default_rest_seconds,
    use_rir,
    auto_start_rest_timer,
    timer_vibration,
    push_coaching_feedback,
    updated_at
  ) values (
    new.user_id,
    case when preferences_value ->> 'weightUnit' in ('kg', 'lb')
      then preferences_value ->> 'weightUnit' else 'kg' end,
    case when preferences_value ->> 'isDarkMode' = 'true' then 'dark' else 'light' end,
    greatest(30, least(
      600,
      case when pg_catalog.jsonb_typeof(preferences_value -> 'restDefaultSeconds') = 'number'
        then (preferences_value ->> 'restDefaultSeconds')::integer else 90 end
    )),
    case when pg_catalog.jsonb_typeof(preferences_value -> 'useRir') = 'boolean'
      then (preferences_value ->> 'useRir')::boolean else false end,
    case when pg_catalog.jsonb_typeof(preferences_value -> 'autoStartRestTimer') = 'boolean'
      then (preferences_value ->> 'autoStartRestTimer')::boolean else true end,
    case when pg_catalog.jsonb_typeof(preferences_value -> 'timerVibration') = 'boolean'
      then (preferences_value ->> 'timerVibration')::boolean else true end,
    case when pg_catalog.jsonb_typeof(preferences_value -> 'pushCoachingFeedback') = 'boolean'
      then (preferences_value ->> 'pushCoachingFeedback')::boolean else true end,
    pg_catalog.clock_timestamp()
  )
  on conflict (user_id) do update
  set weight_unit = excluded.weight_unit,
      theme = excluded.theme,
      default_rest_seconds = excluded.default_rest_seconds,
      use_rir = excluded.use_rir,
      auto_start_rest_timer = excluded.auto_start_rest_timer,
      timer_vibration = excluded.timer_vibration,
      push_coaching_feedback = excluded.push_coaching_feedback,
      updated_at = excluded.updated_at;

  insert into public.user_profiles (
    user_id, weight, height, age, gender, goal, updated_at
  ) values (
    new.user_id,
    weight_value,
    height_value,
    age_value,
    gender_value,
    joined_goals,
    pg_catalog.clock_timestamp()
  )
  on conflict (user_id) do update
  set weight = excluded.weight,
      height = excluded.height,
      age = excluded.age,
      gender = excluded.gender,
      goal = excluded.goal,
      updated_at = excluded.updated_at;

  delete from public.user_goals where user_id = new.user_id;
  insert into public.user_goals (user_id, goal_id, priority)
  select new.user_id, normalized.goal_id, normalized.priority
  from (
    select mapped.goal_id, pg_catalog.min(mapped.ordinality - 1)::smallint as priority
    from (
      select
        goal.ordinality,
        case
          when goal.value ~ '(근력|파워)' then 'strength'
          when goal.value ~ '(근육|근비대)' then 'muscle'
          when goal.value ~ '(체중|감량|다이어트|체지방)' then 'loss'
          when goal.value ~ '(체력|근지구력|지구력)' then 'fitness'
          when goal.value ~ '(건강|유지)' then 'health'
          else null
        end as goal_id
      from pg_catalog.jsonb_array_elements_text(goals_value)
        with ordinality as goal(value, ordinality)
    ) mapped
    where mapped.goal_id is not null
    group by mapped.goal_id
  ) normalized
  order by normalized.priority;

  return new;
end
$function$;

drop trigger if exists app_state_snapshot_project_account_data
  on public.app_state_snapshots;
create trigger app_state_snapshot_project_account_data
after insert or update of payload on public.app_state_snapshots
for each row execute function private.project_app_snapshot_account_data();

revoke all on function private.project_app_snapshot_account_data()
  from public, anon, authenticated;
grant execute on function private.project_app_snapshot_account_data()
  to service_role;

-- Bind each snapshot mutation to the account the client loaded. This closes
-- the last SDK-level TOCTOU window where an auth token could rotate between a
-- local UID check and HTTP header construction.
create or replace function private.save_my_account_snapshot(
  p_expected_user_id uuid,
  p_schema_version smallint,
  p_payload jsonb,
  p_sessions jsonb,
  p_expected_updated_at timestamp with time zone
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if p_expected_user_id is null
     or (select auth.uid()) is distinct from p_expected_user_id then
    raise exception using
      errcode = '42501',
      message = 'The authenticated account changed before snapshot save.';
  end if;
  return private.save_my_app_snapshot(
    p_schema_version,
    p_payload,
    p_sessions,
    p_expected_updated_at
  );
end
$function$;

create or replace function public.save_my_account_snapshot(
  expected_user_id uuid,
  schema_version smallint,
  payload jsonb,
  sessions jsonb,
  expected_updated_at timestamp with time zone default null
)
returns jsonb
language sql
security invoker
set search_path = ''
as $function$
  select private.save_my_account_snapshot($1, $2, $3, $4, $5);
$function$;

create or replace function private.clear_my_account_data(
  p_expected_user_id uuid,
  p_expected_updated_at timestamp with time zone
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if p_expected_user_id is null
     or (select auth.uid()) is distinct from p_expected_user_id then
    raise exception using
      errcode = '42501',
      message = 'The authenticated account changed before data clear.';
  end if;
  return private.clear_my_app_data(p_expected_updated_at);
end
$function$;

create or replace function public.clear_my_account_data(
  expected_user_id uuid,
  expected_updated_at timestamp with time zone default null
)
returns jsonb
language sql
security invoker
set search_path = ''
as $function$
  select private.clear_my_account_data($1, $2);
$function$;

revoke all on function private.save_my_account_snapshot(
  uuid, smallint, jsonb, jsonb, timestamp with time zone
), private.clear_my_account_data(uuid, timestamp with time zone)
  from public, anon, authenticated;
grant execute on function private.save_my_account_snapshot(
  uuid, smallint, jsonb, jsonb, timestamp with time zone
), private.clear_my_account_data(uuid, timestamp with time zone)
  to authenticated, service_role;

revoke all on function public.save_my_account_snapshot(
  uuid, smallint, jsonb, jsonb, timestamp with time zone
), public.clear_my_account_data(uuid, timestamp with time zone)
  from public, anon, authenticated;
grant execute on function public.save_my_account_snapshot(
  uuid, smallint, jsonb, jsonb, timestamp with time zone
), public.clear_my_account_data(uuid, timestamp with time zone)
  to authenticated, service_role;

-- Retire the account-unbound legacy entry points. The new client uses the
-- expected-user variants above; keeping the old wrappers callable would
-- preserve the SDK token-rotation race this migration is closing.
revoke all on function public.save_my_app_snapshot(
  smallint, jsonb, jsonb, timestamp with time zone
), public.clear_my_app_data(timestamp with time zone)
  from public, anon, authenticated;
revoke all on function private.save_my_app_snapshot(
  smallint, jsonb, jsonb, timestamp with time zone
), private.clear_my_app_data(timestamp with time zone)
  from public, anon, authenticated;
grant execute on function private.save_my_app_snapshot(
  smallint, jsonb, jsonb, timestamp with time zone
), private.clear_my_app_data(timestamp with time zone)
  to service_role;

-- Existing snapshots predate the projection trigger. Replaying the payload is
-- idempotent and leaves the optimistic-concurrency updated_at value untouched.
update public.app_state_snapshots set payload = payload;

-- save_personal_routine historically updated only server-created/imported UUID
-- rows.  This wrapper creates an authenticated owner's custom parent inside the
-- same transaction, then delegates all validation, child replacement and
-- idempotency handling to the already audited implementation.
create or replace function private.upsert_personal_routine(
  p_routine_id uuid,
  p_name text,
  p_description text,
  p_color text,
  p_exercises jsonb,
  p_request_id uuid default null
)
returns jsonb
language plpgsql
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
  request_hash text;
  cached_response jsonb;
  response_value jsonb;
  existing_owner_user_id uuid;
begin
  if actor_user_id is null then
    raise exception using errcode = '42501', message = 'Authentication is required.';
  end if;
  if p_routine_id is null then
    raise exception using errcode = '22023', message = 'routine_id is required.';
  end if;

  -- Use the exact cache namespace and normalized payload of
  -- private.save_personal_routine.  The advisory request lock is always taken
  -- before a routine row lock, matching the existing mutation lock order.
  -- A replay returns before inserting a missing parent, so a delayed retry
  -- cannot resurrect a routine that the owner deleted after the first save.
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

  perform 1 from public.users where id = actor_user_id;
  if not found then
    raise exception using errcode = '42501', message = 'Authenticated profile is missing.';
  end if;

  -- Do not attempt an INSERT for an existing row: PostgreSQL fires BEFORE
  -- INSERT limit triggers before resolving ON CONFLICT, which would otherwise
  -- make the fourth free routine impossible to edit.
  select routine.owner_user_id
    into existing_owner_user_id
  from public.routines routine
  where routine.id = p_routine_id
  for update;

  if found and existing_owner_user_id <> actor_user_id then
    raise exception using
      errcode = '42501',
      message = 'The personal routine belongs to another account.';
  elsif not found then
    -- Every routine INSERT path locks the owner through tg_routine_limit.
    -- Take that same lock, then recheck the UUID so concurrent retries with
    -- different request IDs converge on one parent instead of raising 23505.
    perform 1
    from public.users account_user
    where account_user.id = actor_user_id
    for update;
    if not found then
      raise exception using
        errcode = '42501',
        message = 'Authenticated profile is missing.';
    end if;

    select routine.owner_user_id
      into existing_owner_user_id
    from public.routines routine
    where routine.id = p_routine_id
    for update;

    if found and existing_owner_user_id <> actor_user_id then
      raise exception using
        errcode = '42501',
        message = 'The personal routine belongs to another account.';
    elsif not found then
      insert into public.routines (
        id, owner_user_id, name, description, color, source
      ) values (
        p_routine_id,
        actor_user_id,
        coalesce(p_name, ''),
        nullif(pg_catalog.btrim(coalesce(p_description, '')), ''),
        p_color,
        'custom'
      );
    end if;
  end if;

  -- The outer function owns the idempotency lock/cache. Passing NULL prevents
  -- a second advisory lock and keeps create + child replacement atomic.
  response_value := private.save_personal_routine(
    p_routine_id,
    p_name,
    p_description,
    p_color,
    p_exercises,
    null
  );
  return private.finish_routine_rpc_request(
    actor_user_id,
    'save_personal_routine',
    p_request_id,
    request_hash,
    response_value
  );
end
$function$;

revoke all on function private.upsert_personal_routine(
  uuid, text, text, text, jsonb, uuid
) from public, anon, authenticated;
grant execute on function private.upsert_personal_routine(
  uuid, text, text, text, jsonb, uuid
) to authenticated, service_role;

-- Authenticated clients must enter through the public wrapper so every save,
-- including creation, follows the same advisory-lock-before-row-lock order.
revoke all on function private.save_personal_routine(
  uuid, text, text, text, jsonb, uuid
) from public, anon, authenticated;
grant execute on function private.save_personal_routine(
  uuid, text, text, text, jsonb, uuid
) to service_role;

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
security invoker
set search_path = ''
as $function$
  select private.upsert_personal_routine($1, $2, $3, $4, $5, $6);
$function$;

revoke all on function public.save_personal_routine(
  uuid, text, text, text, jsonb, uuid
) from public, anon, authenticated;
grant execute on function public.save_personal_routine(
  uuid, text, text, text, jsonb, uuid
) to authenticated, service_role;

-- Serialize the free-tier quota across every creation path (custom save,
-- market import, trainer share acceptance, and server-side clone). Without
-- the owner row lock, concurrent inserts can each observe three routines and
-- both commit a fifth row.
create or replace function public.tg_routine_limit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if new.owner_user_id is null then
    raise exception using errcode = '23502', message = 'Routine owner is required.';
  end if;

  perform 1
  from public.users account_user
  where account_user.id = new.owner_user_id
  for update;
  if not found then
    raise exception using errcode = '23503', message = 'Routine owner is missing.';
  end if;

  if not (select private.is_admin())
     and (
       select pg_catalog.count(*)
       from public.routines routine
       where routine.owner_user_id = new.owner_user_id
     ) >= 4
     and not exists (
       select 1
       from public.subscriptions subscription
       join public.plans plan on plan.id = subscription.plan_id
       where subscription.user_id = new.owner_user_id
         and subscription.status = 'active'
         and (
           subscription.current_period_end is null
           or subscription.current_period_end > pg_catalog.now()
         )
         and plan.audience = 'b2c'
         and plan.price > 0
     ) then
    raise exception using
      errcode = '23514',
      message = '무료 루틴 한도(4개)를 초과했습니다. 프리미엄으로 업그레이드하세요.';
  end if;
  return new;
end
$function$;

revoke all on function public.tg_routine_limit()
  from public, anon, authenticated;
grant execute on function public.tg_routine_limit() to service_role;

-- An accepted share creates an owner-controlled copy. Deleting that personal
-- copy sets accepted_routine_id to NULL through the existing FK; keep the
-- accepted delivery audit instead of making the copy undeletable.
alter table public.routine_shares
  drop constraint if exists routine_shares_response_shape;
alter table public.routine_shares
  add constraint routine_shares_response_shape check (
    (
      status = 'accepted'
      and responded_by_user_id is not null
      and responded_at is not null
    )
    or (
      status = 'declined'
      and responded_by_user_id is not null
      and accepted_routine_id is null
      and responded_at is not null
    )
    or (
      status in ('pending', 'revoked', 'expired')
      and accepted_routine_id is null
    )
  );

-- RPC-owned account and personal-routine tables are readable only by the
-- authenticated owner/admin policies below.  Remove legacy TRUNCATE, TRIGGER,
-- REFERENCES and direct DML grants, including column-level ACLs.
revoke all on table public.app_state_snapshots,
  public.user_settings, public.user_profiles, public.user_goals,
  public.routines, public.routine_exercises, public.routine_sets
  from anon, authenticated;

do $revoke_account_data_column_acl$
declare
  target_relation regclass;
  column_list text;
begin
  foreach target_relation in array array[
    'public.app_state_snapshots'::regclass,
    'public.user_settings'::regclass,
    'public.user_profiles'::regclass,
    'public.user_goals'::regclass,
    'public.routines'::regclass,
    'public.routine_exercises'::regclass,
    'public.routine_sets'::regclass
  ]
  loop
    select pg_catalog.string_agg(
      pg_catalog.format('%I', attribute.attname), ', '
      order by attribute.attnum
    ) into column_list
    from pg_catalog.pg_attribute attribute
    where attribute.attrelid = target_relation
      and attribute.attnum > 0
      and not attribute.attisdropped;

    execute pg_catalog.format(
      'revoke select (%1$s), insert (%1$s), update (%1$s), references (%1$s) '
      'on table %2$s from anon, authenticated',
      column_list,
      target_relation
    );
  end loop;
end
$revoke_account_data_column_acl$;

grant select on table public.app_state_snapshots,
  public.user_settings, public.user_goals,
  public.routines, public.routine_exercises, public.routine_sets
  to authenticated;
grant select (user_id, goal) on table public.user_profiles
  to authenticated;

drop policy if exists app_state_snapshots_insert_own on public.app_state_snapshots;
drop policy if exists app_state_snapshots_update_own on public.app_state_snapshots;
drop policy if exists app_state_snapshots_delete_own on public.app_state_snapshots;

drop policy if exists user_settings_own on public.user_settings;
drop policy if exists user_settings_read_own on public.user_settings;
drop policy if exists user_settings_insert_own on public.user_settings;
drop policy if exists user_settings_update_own on public.user_settings;
create policy user_settings_read_own
  on public.user_settings for select to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists user_profiles_own on public.user_profiles;
drop policy if exists user_profiles_read_own on public.user_profiles;
drop policy if exists user_profiles_insert_own on public.user_profiles;
drop policy if exists user_profiles_update_own on public.user_profiles;
drop policy if exists user_profiles_read_member_goal on public.user_profiles;

create or replace function private.can_read_member_goal(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select p_user_id is not null
    and (
      p_user_id = (select auth.uid())
      or (select private.is_admin())
      or exists (
        select 1
        from public.members member
        where member.user_id = p_user_id
          and (select private.can_access_business_member(member.id))
      )
    );
$function$;

revoke all on function private.can_read_member_goal(uuid)
  from public, anon, authenticated;
grant execute on function private.can_read_member_goal(uuid)
  to authenticated, service_role;

create policy user_profiles_read_member_goal
  on public.user_profiles for select to authenticated
  using ((select private.can_read_member_goal(user_id)));

drop policy if exists own_goals on public.user_goals;
drop policy if exists user_goals_read_own on public.user_goals;
create policy user_goals_read_own
  on public.user_goals for select to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists own_routines on public.routines;
drop policy if exists personal_routines_read_own on public.routines;
create policy personal_routines_read_own
  on public.routines for select to authenticated
  using (
    owner_user_id = (select auth.uid())
    or (select public.is_admin())
  );

drop policy if exists rw_routine_ex on public.routine_exercises;
drop policy if exists personal_routine_exercises_read_own
  on public.routine_exercises;
create policy personal_routine_exercises_read_own
  on public.routine_exercises for select to authenticated
  using (
    exists (
      select 1 from public.routines routine
      where routine.id = routine_exercises.routine_id
        and (
          routine.owner_user_id = (select auth.uid())
          or (select public.is_admin())
        )
    )
  );

drop policy if exists rw_routine_sets on public.routine_sets;
drop policy if exists personal_routine_sets_read_own on public.routine_sets;
create policy personal_routine_sets_read_own
  on public.routine_sets for select to authenticated
  using (
    exists (
      select 1
      from public.routine_exercises exercise
      join public.routines routine on routine.id = exercise.routine_id
      where exercise.id = routine_sets.routine_exercise_id
        and (
          routine.owner_user_id = (select auth.uid())
          or (select public.is_admin())
        )
    )
  );

-- Normalize the small number of pre-integration snapshots that have no
-- workout projection yet. New saves use the client catalog and do not enter
-- this path. Unknown legacy templates retain their stable key as a safe name.
do $backfill_legacy_snapshot_workouts$
declare
  snapshot_row record;
  normalized_sessions jsonb;
begin
  for snapshot_row in
    select snapshot.user_id, snapshot.payload
    from public.app_state_snapshots snapshot
    where pg_catalog.jsonb_typeof(snapshot.payload -> 'sessions') = 'array'
      and pg_catalog.jsonb_array_length(snapshot.payload -> 'sessions') > 0
      and not exists (
        select 1 from public.workout_sessions session
        where session.user_id = snapshot.user_id
      )
  loop
    select coalesce(pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        'date', session_value ->> 'date',
        'exercises', (
          select coalesce(pg_catalog.jsonb_agg(
            pg_catalog.jsonb_build_object(
              'client_id', coalesce(nullif(exercise_value ->> 'id', ''),
                'legacy-' || exercise_ordinality::text),
              'base_exercise_id', null,
              'name', case exercise_value ->> 'templateId'
                when 'bench' then '바벨 벤치 프레스'
                when 'incline' then '인클라인 덤벨 프레스'
                when 'squat' then '스쿼트'
                when 'legpress' then '레그 프레스'
                when 'latpull' then '렛 풀 다운'
                when 'row' then '바벨 로우'
                when 'ohp' then '오버헤드 프레스'
                when 'lateral' then '사이드 레터럴 레이즈'
                when 'curl' then '덤벨 컬'
                when 'plank' then '플랭크'
                when 'run' then '트레드밀 러닝'
                else coalesce(nullif(exercise_value ->> 'templateId', ''), '운동')
              end,
              'target_muscle', case exercise_value ->> 'templateId'
                when 'bench' then '가슴' when 'incline' then '가슴'
                when 'squat' then '하체' when 'legpress' then '하체'
                when 'latpull' then '등' when 'row' then '등'
                when 'ohp' then '어깨' when 'lateral' then '어깨'
                when 'curl' then '팔' when 'plank' then '복근'
                when 'run' then '유산소' else '기타'
              end,
              'order_index', exercise_ordinality - 1,
              'sets', (
                select coalesce(pg_catalog.jsonb_agg(
                  pg_catalog.jsonb_build_object(
                    'set_no', coalesce((set_value ->> 'number')::integer,
                      set_ordinality::integer),
                    'type', case pg_catalog.lower(coalesce(set_value ->> 'type', 'normal'))
                      when '웜업' then 'warmup' when 'warmup' then 'warmup'
                      when '드랍' then 'drop' when 'drop' then 'drop'
                      when '실패' then 'fail' when 'failure' then 'fail'
                      when 'fail' then 'fail' else 'normal'
                    end,
                    'weight', coalesce((set_value ->> 'weight')::numeric, 0),
                    'reps', coalesce((set_value ->> 'reps')::integer, 0),
                    'completed', coalesce((set_value ->> 'completed')::boolean, false),
                    'rest_seconds', coalesce((set_value ->> 'restSeconds')::integer, 90)
                  ) order by set_ordinality
                ), '[]'::jsonb)
                from pg_catalog.jsonb_array_elements(
                  coalesce(exercise_value -> 'sets', '[]'::jsonb)
                ) with ordinality as workout_set(set_value, set_ordinality)
              )
            ) order by exercise_ordinality
          ), '[]'::jsonb)
          from pg_catalog.jsonb_array_elements(
            coalesce(session_value -> 'exercises', '[]'::jsonb)
          ) with ordinality as workout_exercise(exercise_value, exercise_ordinality)
        )
      ) order by session_ordinality
    ), '[]'::jsonb)
    into normalized_sessions
    from pg_catalog.jsonb_array_elements(snapshot_row.payload -> 'sessions')
      with ordinality as workout_session(session_value, session_ordinality);

    perform pg_catalog.set_config(
      'request.jwt.claim.sub', snapshot_row.user_id::text, true
    );
    perform private.sync_my_workout_snapshot(normalized_sessions);
  end loop;
end
$backfill_legacy_snapshot_workouts$;

-- Complete the trainer/member sharing lifecycle. A sender (or an active admin
-- performing emergency moderation) may revoke only a still-pending offer;
-- retries use the same audited request cache as the other routine mutations.
create or replace function private.revoke_routine_share(
  p_share_id uuid,
  p_request_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  actor_user_id uuid := (select auth.uid());
  share_row public.routine_shares%rowtype;
  request_hash text;
  cached_response jsonb;
  response_value jsonb;
begin
  if actor_user_id is null then
    raise exception using errcode = '42501', message = 'Authentication is required.';
  end if;
  if p_share_id is null then
    raise exception using errcode = '22023', message = 'share_id is required.';
  end if;

  request_hash := private.routine_request_hash(pg_catalog.jsonb_build_object(
    'share_id', p_share_id
  ));
  cached_response := private.begin_routine_rpc_request(
    actor_user_id,
    'revoke_routine_share',
    p_request_id,
    request_hash
  );
  if cached_response is not null then
    return cached_response;
  end if;

  select * into share_row
  from public.routine_shares share
  where share.id = p_share_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'The routine share was not found.';
  end if;
  if share_row.sender_user_id <> actor_user_id
     and not (select private.is_admin()) then
    raise exception using
      errcode = '42501',
      message = 'Only the sender or an active administrator may revoke this share.';
  end if;

  if share_row.status = 'pending' then
    update public.routine_shares
    set status = 'revoked',
        responded_by_user_id = actor_user_id,
        responded_at = pg_catalog.clock_timestamp(),
        updated_at = pg_catalog.clock_timestamp()
    where id = p_share_id;
  elsif share_row.status <> 'revoked' then
    raise exception using
      errcode = '55000',
      message = 'Only a pending routine share can be revoked.';
  end if;

  response_value := pg_catalog.jsonb_build_object(
    'share_id', p_share_id,
    'status', 'revoked'
  );
  return private.finish_routine_rpc_request(
    actor_user_id,
    'revoke_routine_share',
    p_request_id,
    request_hash,
    response_value
  );
end
$function$;

revoke all on function private.revoke_routine_share(uuid, uuid)
  from public, anon, authenticated;
grant execute on function private.revoke_routine_share(uuid, uuid)
  to authenticated, service_role;

create or replace function public.revoke_routine_share(
  share_id uuid,
  request_id uuid default null
)
returns jsonb
language sql
volatile
security invoker
set search_path = ''
as $function$
  select private.revoke_routine_share($1, $2);
$function$;

revoke all on function public.revoke_routine_share(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.revoke_routine_share(uuid, uuid)
  to authenticated, service_role;

-- Align the application transaction with the stricter upload contract.  The
-- legacy submit function still performs its original metadata preflight, and
-- this row-boundary guard is the authoritative final check before a document
-- can become application evidence.  It also blocks already-staged oversized
-- or HEIC/HEIF objects after the bucket policy is tightened below.
create or replace function private.validate_trainer_document_object()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  actor_user_id uuid := (select auth.uid());
  object_mime text;
  object_size bigint;
begin
  if actor_user_id is null then
    raise exception using errcode = '42501', message = 'Authentication is required.';
  end if;
  if new.file_path is null
     or new.doc_type not in ('national', 'private', 'id', 'award')
     or pg_catalog.array_length(pg_catalog.string_to_array(new.file_path, '/'), 1) <> 4
     or pg_catalog.split_part(new.file_path, '/', 1) <> actor_user_id::text
     or pg_catalog.split_part(new.file_path, '/', 2) <> 'pending'
     or pg_catalog.split_part(new.file_path, '/', 4)
          !~ ('^' || new.doc_type || '\.(jpg|jpeg|png|webp)$') then
    raise exception using errcode = '22023', message = 'Invalid trainer document object key.';
  end if;

  select pg_catalog.lower(coalesce(object.metadata ->> 'mimetype', '')),
         coalesce((object.metadata ->> 'size')::bigint, 0)
    into object_mime, object_size
  from storage.objects object
  where object.bucket_id = 'trainer-documents'
    and object.name = new.file_path
    and (object.owner = actor_user_id or object.owner_id = actor_user_id::text);

  if not found
     or object_size not between 1 and 4194304
     or object_mime not in ('image/jpeg', 'image/png', 'image/webp')
     or (object_mime = 'image/jpeg'
          and pg_catalog.split_part(new.file_path, '/', 4) !~ '\.(jpg|jpeg)$')
     or (object_mime = 'image/png'
          and pg_catalog.split_part(new.file_path, '/', 4) !~ '\.png$')
     or (object_mime = 'image/webp'
          and pg_catalog.split_part(new.file_path, '/', 4) !~ '\.webp$') then
    raise exception using
      errcode = '42501',
      message = 'Trainer document must be an owned JPEG, PNG, or WebP image up to 4 MiB.';
  end if;

  return new;
end
$function$;

drop trigger if exists trainer_document_object_contract
  on public.trainer_documents;
create trigger trainer_document_object_contract
before insert or update of file_path, doc_type on public.trainer_documents
for each row execute function private.validate_trainer_document_object();

revoke all on function private.validate_trainer_document_object()
  from public, anon, authenticated;
grant execute on function private.validate_trainer_document_object()
  to service_role;

-- Trainer evidence objects are immutable to applicants after upload. This is
-- intentionally stricter than a link-aware NOT EXISTS check: an upload DELETE
-- racing the application transaction could otherwise commit just before the
-- evidence row becomes visible. Admin/service cleanup handles orphan uploads.
create or replace function private.can_mutate_trainer_document_object(
  p_bucket_id text,
  p_object_name text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select p_bucket_id <> 'trainer-documents'
    or (select private.is_admin());
$function$;

revoke all on function private.can_mutate_trainer_document_object(text, text)
  from public, anon, authenticated;
grant execute on function private.can_mutate_trainer_document_object(text, text)
  to authenticated, service_role;

drop policy if exists trainer_documents_linked_object_immutable_delete
  on storage.objects;
create policy trainer_documents_linked_object_immutable_delete
  on storage.objects as restrictive for delete to authenticated
  using (
    (select private.can_mutate_trainer_document_object(bucket_id, name))
  );

drop policy if exists trainer_documents_linked_object_immutable_update
  on storage.objects;
create policy trainer_documents_linked_object_immutable_update
  on storage.objects as restrictive for update to authenticated
  using (
    (select private.can_mutate_trainer_document_object(bucket_id, name))
  )
  with check (
    (select private.can_mutate_trainer_document_object(bucket_id, name))
  );

-- Client-side image optimization targets are comfortably below these hard
-- limits. Storage enforces byte size and declared MIME for every client; the
-- app additionally decodes/re-encodes pixels and validates image signatures.
update storage.buckets
set file_size_limit = 2097152,
    allowed_mime_types = array[
      'image/jpeg', 'image/png', 'image/webp'
    ]::text[]
where id = 'post-images';

update storage.buckets
set file_size_limit = 4194304,
    allowed_mime_types = array[
      'image/jpeg', 'image/png', 'image/webp'
    ]::text[]
where id = 'trainer-documents';

commit;
