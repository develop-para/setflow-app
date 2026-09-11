begin;

-- Coaching records are authoritative independently of a member's personal
-- snapshot. Older/offline clients therefore cannot overwrite a trainer's work.
create table public.coaching_workouts (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in ('lesson', 'assignment')),
  status text not null default 'assigned'
    check (status in ('assigned', 'in_progress', 'completed', 'cancelled')),
  trainer_id uuid not null references public.trainers(id) on delete cascade,
  member_user_id uuid not null references public.users(id) on delete cascade,
  schedule_id uuid references public.coaching_schedules(id) on delete set null,
  workout_date date not null,
  title text not null check (char_length(btrim(title)) between 1 and 120),
  instruction text not null default '' check (char_length(instruction) <= 2000),
  session jsonb not null check (jsonb_typeof(session) = 'object'),
  version integer not null default 1 check (version > 0),
  last_editor_user_id uuid references public.users(id) on delete set null,
  first_recorded_at timestamptz,
  completion_notified_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (kind = 'lesson' or schedule_id is null)
);
create unique index coaching_workouts_schedule_uidx
  on public.coaching_workouts(schedule_id) where schedule_id is not null;
create index coaching_workouts_member_date_idx
  on public.coaching_workouts(member_user_id, workout_date desc, id);
create index coaching_workouts_trainer_member_idx
  on public.coaching_workouts(trainer_id, member_user_id, workout_date desc);
create index coaching_workouts_last_editor_idx
  on public.coaching_workouts(last_editor_user_id);
create index coaching_workouts_pending_assignment_idx
  on public.coaching_workouts(member_user_id, workout_date)
  where kind = 'assignment' and status in ('assigned', 'in_progress');

create table public.coaching_recording_consents (
  schedule_id uuid primary key references public.coaching_schedules(id) on delete cascade,
  member_user_id uuid not null references public.users(id) on delete cascade,
  trainer_id uuid not null references public.trainers(id) on delete cascade,
  allowed boolean not null default false,
  updated_at timestamptz not null default clock_timestamp()
);
create index coaching_recording_consents_member_idx on public.coaching_recording_consents(member_user_id);
create index coaching_recording_consents_trainer_idx on public.coaching_recording_consents(trainer_id);

create table public.coaching_workout_requests (
  actor_user_id uuid not null references public.users(id) on delete cascade,
  request_id uuid not null,
  operation text not null,
  input jsonb not null,
  response jsonb not null,
  created_at timestamptz not null default clock_timestamp(),
  primary key (actor_user_id, request_id)
);
create table public.coaching_workout_events (
  id uuid primary key default gen_random_uuid(),
  workout_id uuid references public.coaching_workouts(id) on delete cascade,
  schedule_id uuid references public.coaching_schedules(id) on delete set null,
  member_user_id uuid not null references public.users(id) on delete cascade,
  actor_user_id uuid not null references public.users(id) on delete cascade,
  event text not null,
  version integer,
  created_at timestamptz not null default clock_timestamp()
);
create index coaching_workout_events_workout_idx on public.coaching_workout_events(workout_id, created_at);
create index coaching_workout_events_schedule_idx on public.coaching_workout_events(schedule_id);
create index coaching_workout_events_member_idx on public.coaching_workout_events(member_user_id);
create index coaching_workout_events_actor_idx on public.coaching_workout_events(actor_user_id);

create table public.coaching_reminder_preferences (
  member_user_id uuid primary key references public.users(id) on delete cascade,
  enabled boolean not null default false,
  hour integer not null default 19 check (hour between 6 and 22),
  last_reminded_on date,
  updated_at timestamptz not null default clock_timestamp()
);

alter table public.coaching_workouts enable row level security;
alter table public.coaching_recording_consents enable row level security;
alter table public.coaching_workout_requests enable row level security;
alter table public.coaching_workout_events enable row level security;
alter table public.coaching_reminder_preferences enable row level security;
-- Only checked domain RPCs access these tables; no direct client write path.
revoke all on public.coaching_workouts, public.coaching_recording_consents,
  public.coaching_workout_requests, public.coaching_workout_events,
  public.coaching_reminder_preferences from public, anon, authenticated;
grant all on public.coaching_workouts, public.coaching_recording_consents,
  public.coaching_workout_requests, public.coaching_workout_events,
  public.coaching_reminder_preferences to service_role;

create or replace function private.has_coaching_workout_relationship(p_trainer uuid, p_member uuid)
returns boolean language sql stable security definer set search_path = '' as $function$
  select p_member is not null and (
    private.has_active_coaching_schedule_relationship(p_trainer, p_member, null)
    or exists (
      select 1 from public.members member
      join public.member_assignments assignment
        on assignment.member_id = member.id and assignment.gym_id = member.gym_id
       and assignment.trainer_id = p_trainer and assignment.active
      join public.gym_trainers employment
        on employment.gym_id = member.gym_id and employment.trainer_id = p_trainer
       and employment.status = 'active'
      join public.gyms gym on gym.id = member.gym_id and gym.status = 'verified'
      where member.user_id = p_member and member.status = 'active'
    )
  );
$function$;

-- Return a normalized canonical session, never trusting ownership/date in JSON.
create or replace function private.validate_coaching_workout_session(p_session jsonb, p_date date)
returns jsonb language plpgsql immutable security invoker set search_path = '' as $function$
declare
  v_exercise jsonb;
  v_set jsonb;
  v_template jsonb;
  v_ids text[] := array[]::text[];
  v_id text;
  v_no integer;
  v_metric text;
  v_value numeric;
  v_cardio boolean;
begin
  if p_session is null or jsonb_typeof(p_session) <> 'object'
    or pg_column_size(p_session) > 524288
    or jsonb_typeof(p_session -> 'date') is distinct from 'string'
    or jsonb_typeof(p_session -> 'exercises') is distinct from 'array'
    or jsonb_array_length(p_session -> 'exercises') > 50 then
    raise exception 'Invalid coaching workout session' using errcode = '22023';
  end if;
  begin
    if (left(p_session ->> 'date', 10))::date is distinct from p_date then
      raise exception 'Workout date cannot change' using errcode = '22023';
    end if;
    if p_session ? 'startedAt' then perform (p_session ->> 'startedAt')::timestamptz; end if;
    if p_session ? 'endedAt' then perform (p_session ->> 'endedAt')::timestamptz; end if;
  exception when invalid_datetime_format or datetime_field_overflow then
    raise exception 'Invalid workout date or time' using errcode = '22023';
  end;
  for v_exercise in select value from jsonb_array_elements(p_session -> 'exercises') loop
    v_id := btrim(coalesce(v_exercise ->> 'id', ''));
    v_template := v_exercise -> 'template';
    if jsonb_typeof(v_exercise) <> 'object'
      or jsonb_typeof(v_exercise -> 'id') is distinct from 'string'
      or char_length(v_id) not between 1 and 200 or v_id = any(v_ids)
      or jsonb_typeof(v_template) is distinct from 'object'
      or jsonb_typeof(v_exercise -> 'templateId') is distinct from 'string'
      or jsonb_typeof(v_template -> 'id') is distinct from 'string'
      or (v_exercise ->> 'templateId') is distinct from (v_template ->> 'id')
      or char_length(btrim(coalesce(v_template ->> 'id', ''))) not between 1 and 200
      or jsonb_typeof(v_template -> 'name') is distinct from 'string'
      or char_length(btrim(coalesce(v_template ->> 'name', ''))) not between 1 and 120
      or jsonb_typeof(v_template -> 'muscle') is distinct from 'string'
      or char_length(btrim(coalesce(v_template ->> 'muscle', ''))) not between 1 and 80
      or coalesce(v_template ->> 'measurement', '') not in ('weightReps', 'repsOnly', 'duration')
      or jsonb_typeof(v_exercise -> 'sets') is distinct from 'array'
      or jsonb_array_length(v_exercise -> 'sets') not between 1 and 30 then
      raise exception 'Invalid or duplicate coaching exercise' using errcode = '22023';
    end if;
    v_ids := array_append(v_ids, v_id);
    v_cardio := lower(btrim(v_template ->> 'muscle')) in ('유산소', 'cardio', 'aerobic');
    v_no := 0;
    for v_set in select value from jsonb_array_elements(v_exercise -> 'sets') loop
      v_no := v_no + 1;
      if jsonb_typeof(v_set) <> 'object'
        or jsonb_typeof(v_set -> 'number') is distinct from 'number'
        or (v_set ->> 'number')::numeric <> v_no
        or jsonb_typeof(v_set -> 'completed') is distinct from 'boolean'
        or coalesce(v_set ->> 'type', '일반') not in
          ('일반', '웜업', '드랍', '실패', 'normal', 'warmup', 'drop', 'fail', 'failure') then
        raise exception 'Invalid coaching set number or type' using errcode = '22023';
      end if;
      foreach v_metric in array array['weight','reps','restSeconds','durationSeconds','distanceKm','intensityRpe'] loop
        if jsonb_typeof(v_set -> v_metric) is distinct from 'number' then
          raise exception 'Coaching set metrics must be numeric' using errcode = '22023';
        end if;
        v_value := (v_set ->> v_metric)::numeric;
        if v_value < 0 or v_value > (case v_metric
          when 'weight' then 9999.99 when 'reps' then 1000
          when 'restSeconds' then 3600 when 'durationSeconds' then 604800
          when 'distanceKm' then 999.99999 else 10 end)
          or (v_metric in ('reps','restSeconds','durationSeconds') and mod(v_value,1) <> 0)
          or (v_metric = 'intensityRpe' and v_value > 0 and v_value < 1)
          or (v_cardio and v_metric in ('weight','reps') and v_value <> 0) then
          raise exception 'Coaching set metric is outside supported range' using errcode = '22023';
        end if;
      end loop;
      if (v_set ->> 'completed')::boolean and (
        (v_cardio and (v_set ->> 'durationSeconds')::numeric <= 0 and (v_set ->> 'distanceKm')::numeric <= 0)
        or (not v_cardio and v_template ->> 'measurement' = 'duration' and (v_set ->> 'durationSeconds')::numeric <= 0)
        or (not v_cardio and v_template ->> 'measurement' <> 'duration' and (v_set ->> 'reps')::numeric <= 0)
      ) then
        raise exception 'A completed set needs recorded repetitions, time or distance' using errcode = '22023';
      end if;
      if v_set ? 'memo' and (jsonb_typeof(v_set -> 'memo') is distinct from 'string'
        or char_length(v_set ->> 'memo') > 1000) then
        raise exception 'Invalid coaching set memo' using errcode = '22023';
      end if;
      if v_set ? 'rir' and v_set -> 'rir' <> 'null'::jsonb then
        if jsonb_typeof(v_set -> 'rir') <> 'number'
          or (v_set ->> 'rir')::numeric not between 0 and 10
          or mod((v_set ->> 'rir')::numeric,1) <> 0 then
          raise exception 'Invalid RIR' using errcode = '22023';
        end if;
      end if;
    end loop;
  end loop;
  return jsonb_set(p_session, '{date}', to_jsonb(p_date::text || 'T00:00:00.000'));
end;
$function$;

create or replace function private.coaching_workout_status(p_session jsonb)
returns text language sql immutable security invoker set search_path = '' as $function$
  select case when count(*) > 0 and bool_and((workout_set ->> 'completed')::boolean)
    then 'completed' when bool_or((workout_set ->> 'completed')::boolean)
    then 'in_progress' else 'assigned' end
  from jsonb_array_elements(p_session -> 'exercises') exercise,
    lateral jsonb_array_elements(exercise -> 'sets') workout_set;
$function$;

create or replace function private.coaching_workout_json(p_workout public.coaching_workouts)
returns jsonb language plpgsql stable security definer set search_path = '' as $function$
declare
  v_schedule public.coaching_schedules%rowtype;
  v_allowed boolean := false;
  v_trainer_user uuid;
  v_trainer_name text;
  v_approved boolean := false;
  v_active boolean;
  v_reason text;
  v_starts timestamptz;
  v_ends timestamptz;
  v_uid uuid := (select auth.uid());
begin
  select user_id, display_name, status = 'approved'
    into v_trainer_user, v_trainer_name, v_approved
    from public.trainers where id = p_workout.trainer_id;
  v_active := private.has_coaching_workout_relationship(p_workout.trainer_id, p_workout.member_user_id);
  if p_workout.kind = 'lesson' then
    select * into v_schedule from public.coaching_schedules where id = p_workout.schedule_id;
    select consent.allowed into v_allowed from public.coaching_recording_consents consent
      where consent.schedule_id = p_workout.schedule_id
        and consent.trainer_id = p_workout.trainer_id and consent.member_user_id = p_workout.member_user_id;
    v_allowed := coalesce(v_allowed, false);
    v_starts := (v_schedule.date + v_schedule.start_time) at time zone 'Asia/Seoul';
    v_ends := (v_schedule.date + v_schedule.end_time) at time zone 'Asia/Seoul';
    v_reason := case
      when v_uid is distinct from v_trainer_user then '수업 기록은 담당 트레이너가 입력해요'
      when not coalesce(v_approved,false) or not v_active then '활성 코칭 관계가 필요해요'
      when v_schedule.id is null or v_schedule.trainer_id <> p_workout.trainer_id
        or v_schedule.member_user_id is distinct from p_workout.member_user_id
        or v_schedule.date <> p_workout.workout_date then '수업 일정이 변경되었어요'
      when not private.has_active_coaching_schedule_relationship(v_schedule.trainer_id, v_schedule.member_user_id, v_schedule.gym_id)
        then '활성 코칭 관계가 필요해요'
      when v_schedule.completed_at is not null then '종료된 수업이에요'
      when not v_allowed then '회원의 수업 기록 허용이 필요해요'
      when statement_timestamp() < v_starts then '예약된 수업 시간에 기록할 수 있어요'
      when statement_timestamp() >= v_ends then '수업 시간이 끝났어요'
      else null end;
  else
    v_allowed := true;
    v_reason := case
      when v_uid is distinct from p_workout.member_user_id then '과제 결과는 회원이 기록해요'
      when p_workout.status = 'cancelled' then '취소된 과제예요'
      when not v_active or not coalesce(v_approved,false) then '활성 코칭 관계가 필요해요'
      else null end;
  end if;
  return jsonb_build_object(
    'id', p_workout.id, 'kind', p_workout.kind, 'status', p_workout.status,
    'trainer_id', p_workout.trainer_id, 'member_user_id', p_workout.member_user_id,
    'trainer_name', coalesce(nullif(btrim(v_trainer_name),''),'트레이너'),
    'member_name', private.display_name_of(p_workout.member_user_id),
    'title', p_workout.title, 'instruction', p_workout.instruction,
    'date', p_workout.workout_date, 'session', p_workout.session,
    'version', p_workout.version, 'can_edit', v_reason is null,
    'recording_allowed', v_allowed, 'schedule_id', p_workout.schedule_id,
    'starts_at', v_starts, 'ends_at', v_ends, 'edit_blocked_reason', v_reason,
    'updated_at', p_workout.updated_at,
    'last_editor_name', case when p_workout.last_editor_user_id is not null
      then private.display_name_of(p_workout.last_editor_user_id) else null end
  );
end;
$function$;

-- A request ID is scoped to its authenticated actor and bound to exact input.
-- The lock makes concurrent creation/retries return one committed result.
create or replace function private.coaching_workout_replay(p_request uuid, p_operation text, p_input jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $function$
declare v_request public.coaching_workout_requests%rowtype;
begin
  if (select auth.uid()) is null then raise exception 'Authentication required' using errcode = '42501'; end if;
  if p_request is null then raise exception 'request_id is required' using errcode = '22023'; end if;
  perform pg_advisory_xact_lock(hashtextextended('coaching-workout:' || (select auth.uid())::text || ':' || p_request::text,0));
  select * into v_request from public.coaching_workout_requests
    where actor_user_id = (select auth.uid()) and request_id = p_request;
  if found then
    if v_request.operation is distinct from p_operation or v_request.input is distinct from p_input then
      raise exception 'A request ID cannot be reused with different workout data' using errcode = '22023';
    end if;
    return v_request.response;
  end if;
  return null;
end;
$function$;

create or replace function private.open_lesson_workout(p_schedule uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $function$
declare
  v_schedule public.coaching_schedules%rowtype;
  v_workout public.coaching_workouts%rowtype;
begin
  if (select auth.uid()) is null then raise exception 'Authentication required' using errcode = '42501'; end if;
  select * into v_schedule from public.coaching_schedules where id = p_schedule for update;
  if not found or v_schedule.member_user_id is null then
    raise exception 'Coaching schedule is not available' using errcode = '42501';
  end if;
  if (select auth.uid()) <> v_schedule.member_user_id and not exists (
    select 1 from public.trainers where id = v_schedule.trainer_id
      and user_id = (select auth.uid()) and status = 'approved'
      and private.has_active_coaching_schedule_relationship(id, v_schedule.member_user_id, v_schedule.gym_id)
  ) then raise exception 'Assigned trainer or member required' using errcode = '42501'; end if;
  select * into v_workout from public.coaching_workouts where schedule_id = p_schedule;
  if not found then
    insert into public.coaching_workouts(kind, trainer_id, member_user_id, schedule_id, workout_date, title, session)
    values ('lesson', v_schedule.trainer_id, v_schedule.member_user_id, v_schedule.id,
      v_schedule.date, v_schedule.title,
      jsonb_build_object('date', v_schedule.date::text || 'T00:00:00.000', 'exercises', '[]'::jsonb))
    returning * into v_workout;
  elsif v_workout.member_user_id <> v_schedule.member_user_id or v_workout.trainer_id <> v_schedule.trainer_id then
    raise exception 'Schedule participants changed; create a new schedule' using errcode = '42501';
  end if;
  return private.coaching_workout_json(v_workout);
end;
$function$;

create or replace function private.set_lesson_recording_consent(p_schedule uuid, p_allowed boolean)
returns void language plpgsql volatile security definer set search_path = '' as $function$
declare v_schedule public.coaching_schedules%rowtype; v_old boolean;
begin
  if (select auth.uid()) is null then raise exception 'Authentication required' using errcode = '42501'; end if;
  if p_allowed is null then raise exception 'allowed is required' using errcode = '22023'; end if;
  select * into v_schedule from public.coaching_schedules where id = p_schedule for update;
  if not found or v_schedule.member_user_id is distinct from (select auth.uid()) then
    raise exception 'Only the scheduled member may grant recording consent' using errcode = '42501';
  end if;
  if p_allowed and (v_schedule.completed_at is not null or
    clock_timestamp() >= ((v_schedule.date + v_schedule.end_time) at time zone 'Asia/Seoul')) then
    raise exception 'The coaching lesson has ended' using errcode = '22023';
  end if;
  select allowed into v_old from public.coaching_recording_consents where schedule_id = p_schedule
    and trainer_id = v_schedule.trainer_id and member_user_id = v_schedule.member_user_id;
  insert into public.coaching_recording_consents(schedule_id, member_user_id, trainer_id, allowed)
    values(p_schedule, v_schedule.member_user_id, v_schedule.trainer_id, p_allowed)
  on conflict(schedule_id) do update set member_user_id = excluded.member_user_id,
    trainer_id = excluded.trainer_id, allowed = excluded.allowed, updated_at = clock_timestamp();
  if v_old is distinct from p_allowed then
    insert into public.coaching_workout_events(schedule_id, member_user_id, actor_user_id, event)
    values(p_schedule, v_schedule.member_user_id, (select auth.uid()),
      case when p_allowed then 'recording_allowed' else 'recording_revoked' end);
  end if;
end;
$function$;

create or replace function private.list_coaching_workouts(p_member uuid default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $function$
declare v_result jsonb;
begin
  if (select auth.uid()) is null then raise exception 'Authentication required' using errcode = '42501'; end if;
  select coalesce(jsonb_agg(private.coaching_workout_json(workout) order by workout.workout_date desc, workout.created_at desc),'[]'::jsonb)
  into v_result from public.coaching_workouts workout
  where (p_member is null or workout.member_user_id = p_member)
    and (workout.member_user_id = (select auth.uid()) or exists (
      select 1 from public.trainers trainer where trainer.id = workout.trainer_id
        and trainer.user_id = (select auth.uid()) and trainer.status = 'approved'
        and private.has_coaching_workout_relationship(trainer.id, workout.member_user_id)
    ));
  return v_result;
end;
$function$;

create or replace function private.create_workout_assignment(
  p_member uuid, p_date date, p_title text, p_instruction text, p_session jsonb, p_request uuid
) returns jsonb language plpgsql volatile security definer set search_path = '' as $function$
declare
  v_trainer uuid; v_session jsonb; v_workout public.coaching_workouts%rowtype;
  v_input jsonb := jsonb_build_object('member',p_member,'date',p_date,'title',p_title,'instruction',p_instruction,'session',p_session);
  v_response jsonb;
begin
  v_response := private.coaching_workout_replay(p_request,'create',v_input);
  if v_response is not null then return v_response; end if;
  select id into v_trainer from public.trainers
    where user_id = (select auth.uid()) and status = 'approved';
  if v_trainer is null or not private.has_coaching_workout_relationship(v_trainer,p_member) then
    raise exception 'An approved assigned trainer is required' using errcode = '42501';
  end if;
  if p_date is null or p_date < (clock_timestamp() at time zone 'Asia/Seoul')::date
    or p_date > (clock_timestamp() at time zone 'Asia/Seoul')::date + 365
    or p_title is null or char_length(btrim(p_title)) not between 1 and 120
    or char_length(coalesce(p_instruction,'')) > 2000 then
    raise exception 'Invalid assignment date, title or instruction' using errcode = '22023';
  end if;
  v_session := private.validate_coaching_workout_session(p_session,p_date);
  if jsonb_array_length(v_session -> 'exercises') = 0 or private.coaching_workout_status(v_session) <> 'assigned' then
    raise exception 'An assignment needs uncompleted exercise sets' using errcode = '22023';
  end if;
  insert into public.coaching_workouts(kind,trainer_id,member_user_id,workout_date,title,instruction,session,last_editor_user_id)
  values('assignment',v_trainer,p_member,p_date,btrim(p_title),coalesce(p_instruction,''),v_session,(select auth.uid()))
  returning * into v_workout;
  insert into public.coaching_workout_events(workout_id,member_user_id,actor_user_id,event,version)
    values(v_workout.id,p_member,(select auth.uid()),'assigned',v_workout.version);
  perform private.enqueue_push(p_member,'coaching_feedback','오늘의 운동 과제가 도착했어요',v_workout.title,
    jsonb_build_object('event','coaching_workout','workoutId',v_workout.id::text,'date',p_date::text));
  v_response := private.coaching_workout_json(v_workout);
  insert into public.coaching_workout_requests(actor_user_id,request_id,operation,input,response)
    values((select auth.uid()),p_request,'create',v_input,v_response);
  return v_response;
end;
$function$;

create or replace function private.save_coaching_workout(p_id uuid,p_version integer,p_session jsonb,p_request uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $function$
declare
  v_workout public.coaching_workouts%rowtype; v_schedule public.coaching_schedules%rowtype;
  v_session jsonb; v_status text; v_capability jsonb; v_trainer_user uuid;
  v_input jsonb := jsonb_build_object('id',p_id,'version',p_version,'session',p_session);
  v_response jsonb; v_notify boolean; v_event text;
begin
  v_response := private.coaching_workout_replay(p_request,'save',v_input);
  if v_response is not null then return v_response; end if;
  -- All lesson mutations lock schedule before workout, including consent.
  select * into v_workout from public.coaching_workouts where id = p_id;
  if not found then raise exception 'Coaching workout unavailable' using errcode = '42501'; end if;
  if v_workout.schedule_id is not null then
    select * into v_schedule from public.coaching_schedules where id = v_workout.schedule_id for update;
  end if;
  select * into v_workout from public.coaching_workouts where id = p_id for update;
  if not found then raise exception 'Coaching workout unavailable' using errcode = '42501'; end if;
  v_capability := private.coaching_workout_json(v_workout);
  if not (v_capability ->> 'can_edit')::boolean then
    raise exception 'Coaching recording is not allowed: %',v_capability ->> 'edit_blocked_reason' using errcode = '42501';
  end if;
  if v_workout.kind = 'lesson' and (
    clock_timestamp() < ((v_schedule.date + v_schedule.start_time) at time zone 'Asia/Seoul') or
    clock_timestamp() >= ((v_schedule.date + v_schedule.end_time) at time zone 'Asia/Seoul')
  ) then raise exception 'Outside the reserved lesson time' using errcode = '42501'; end if;
  if p_version is null or p_version <> v_workout.version then
    raise exception 'Coaching workout changed; reload before saving'
      using errcode = 'PT409', detail = 'coaching_workout_version_conflict';
  end if;
  v_session := private.validate_coaching_workout_session(p_session,v_workout.workout_date);
  v_status := private.coaching_workout_status(v_session);
  v_notify := case when v_workout.kind = 'lesson' then
      v_workout.first_recorded_at is null and jsonb_array_length(v_session -> 'exercises') > 0
    else v_status = 'completed' and v_workout.completion_notified_at is null end;
  update public.coaching_workouts set session = v_session,status = v_status,version = version + 1,
    last_editor_user_id = (select auth.uid()),updated_at = clock_timestamp(),
    first_recorded_at = case when jsonb_array_length(v_session -> 'exercises') > 0
      then coalesce(first_recorded_at,clock_timestamp()) else first_recorded_at end,
    completion_notified_at = case when kind = 'assignment' and v_status = 'completed'
      then coalesce(completion_notified_at,clock_timestamp()) else completion_notified_at end
    where id = p_id returning * into v_workout;
  v_event := case when v_status = 'completed' then 'completed' else 'recorded' end;
  insert into public.coaching_workout_events(workout_id,schedule_id,member_user_id,actor_user_id,event,version)
    values(p_id,v_workout.schedule_id,v_workout.member_user_id,(select auth.uid()),v_event,v_workout.version);
  if v_notify then
    select user_id into v_trainer_user from public.trainers where id = v_workout.trainer_id;
    perform private.enqueue_push(case when v_workout.kind = 'lesson' then v_workout.member_user_id else v_trainer_user end,
      'coaching_feedback',case when v_workout.kind = 'lesson' then '트레이너가 수업을 기록했어요' else '회원이 운동 과제를 마쳤어요' end,
      v_workout.title,jsonb_build_object('event','coaching_workout','workoutId',p_id::text,'date',v_workout.workout_date::text));
  end if;
  v_response := private.coaching_workout_json(v_workout);
  insert into public.coaching_workout_requests(actor_user_id,request_id,operation,input,response)
    values((select auth.uid()),p_request,'save',v_input,v_response);
  return v_response;
end;
$function$;

create or replace function private.cancel_workout_assignment(p_id uuid,p_version integer,p_request uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $function$
declare
  v_workout public.coaching_workouts%rowtype;
  v_input jsonb := jsonb_build_object('id',p_id,'version',p_version); v_response jsonb;
begin
  v_response := private.coaching_workout_replay(p_request,'cancel',v_input);
  if v_response is not null then return v_response; end if;
  select * into v_workout from public.coaching_workouts where id = p_id for update;
  if not found or v_workout.kind <> 'assignment' or not (
    v_workout.member_user_id = (select auth.uid()) or exists (
      select 1 from public.trainers where id = v_workout.trainer_id
        and user_id = (select auth.uid()) and status = 'approved'
        and private.has_coaching_workout_relationship(id,v_workout.member_user_id)
    )) then raise exception 'Only the assigned trainer or member may cancel this task' using errcode = '42501'; end if;
  if p_version is null or p_version <> v_workout.version then
    raise exception 'Coaching workout changed; reload before cancelling'
      using errcode = 'PT409', detail = 'coaching_workout_version_conflict';
  end if;
  if v_workout.status in ('completed','cancelled') then
    raise exception 'Completed or cancelled assignments cannot be cancelled' using errcode = '22023';
  end if;
  update public.coaching_workouts set status = 'cancelled',version = version + 1,
    last_editor_user_id = (select auth.uid()),updated_at = clock_timestamp()
    where id = p_id returning * into v_workout;
  insert into public.coaching_workout_events(workout_id,member_user_id,actor_user_id,event,version)
    values(p_id,v_workout.member_user_id,(select auth.uid()),
      case when v_workout.member_user_id = (select auth.uid()) then 'declined' else 'cancelled' end,v_workout.version);
  v_response := private.coaching_workout_json(v_workout);
  insert into public.coaching_workout_requests(actor_user_id,request_id,operation,input,response)
    values((select auth.uid()),p_request,'cancel',v_input,v_response);
  return v_response;
end;
$function$;

create or replace function private.get_my_coaching_reminder()
returns jsonb language plpgsql stable security definer set search_path = '' as $function$
declare v_result jsonb;
begin
  if (select auth.uid()) is null then raise exception 'Authentication required' using errcode = '42501'; end if;
  select jsonb_build_object('enabled',enabled,'hour',hour) into v_result
    from public.coaching_reminder_preferences where member_user_id = (select auth.uid());
  return coalesce(v_result,jsonb_build_object('enabled',false,'hour',19));
end;
$function$;
create or replace function private.set_my_coaching_reminder(p_enabled boolean,p_hour integer)
returns jsonb language plpgsql volatile security definer set search_path = '' as $function$
begin
  if (select auth.uid()) is null then raise exception 'Authentication required' using errcode = '42501'; end if;
  if p_enabled is null or p_hour is null or p_hour not between 6 and 22 then
    raise exception 'Reminder hour must be between 6 and 22' using errcode = '22023';
  end if;
  insert into public.coaching_reminder_preferences(member_user_id,enabled,hour)
    values((select auth.uid()),p_enabled,p_hour)
  on conflict(member_user_id) do update set enabled = excluded.enabled,hour = excluded.hour,updated_at = clock_timestamp();
  return private.get_my_coaching_reminder();
end;
$function$;

create or replace function private.remind_coaching_workouts()
returns integer language plpgsql volatile security definer set search_path = '' as $function$
declare
  v_pref public.coaching_reminder_preferences%rowtype;
  v_workout public.coaching_workouts%rowtype;
  v_today date := (clock_timestamp() at time zone 'Asia/Seoul')::date;
  v_hour integer := extract(hour from clock_timestamp() at time zone 'Asia/Seoul');
  v_count integer := 0;
begin
  for v_pref in select * from public.coaching_reminder_preferences
    where enabled and hour = v_hour and last_reminded_on is distinct from v_today
    order by member_user_id for update skip locked
  loop
    select workout.* into v_workout from public.coaching_workouts workout
      join public.trainers trainer on trainer.id = workout.trainer_id and trainer.status = 'approved'
      where workout.member_user_id = v_pref.member_user_id and workout.kind = 'assignment'
        and workout.status in ('assigned','in_progress') and workout.workout_date <= v_today
        and private.has_coaching_workout_relationship(workout.trainer_id,workout.member_user_id)
      order by workout.workout_date,workout.created_at limit 1 for update of workout skip locked;
    if found then
      perform private.enqueue_push(v_pref.member_user_id,'coaching_feedback','오늘의 운동 과제를 확인해요',v_workout.title,
        jsonb_build_object('event','coaching_workout','workoutId',v_workout.id::text,'date',v_workout.workout_date::text));
      update public.coaching_reminder_preferences set last_reminded_on = v_today
        where member_user_id = v_pref.member_user_id;
      v_count := v_count + 1;
    end if;
  end loop;
  return v_count;
end;
$function$;

create or replace function public.open_lesson_workout(schedule_id uuid)
returns jsonb language sql volatile security invoker set search_path = '' as $function$
  select private.open_lesson_workout($1);
$function$;
create or replace function public.set_lesson_recording_consent(schedule_id uuid,allowed boolean)
returns void language sql volatile security invoker set search_path = '' as $function$
  select private.set_lesson_recording_consent($1,$2);
$function$;
create or replace function public.list_coaching_workouts(member_user_id uuid default null)
returns jsonb language sql stable security invoker set search_path = '' as $function$
  select private.list_coaching_workouts($1);
$function$;
create or replace function public.create_workout_assignment(member_user_id uuid,date date,title text,instruction text,session jsonb,request_id uuid)
returns jsonb language sql volatile security invoker set search_path = '' as $function$
  select private.create_workout_assignment($1,$2,$3,$4,$5,$6);
$function$;
create or replace function public.save_coaching_workout(workout_id uuid,expected_version integer,session jsonb,request_id uuid)
returns jsonb language sql volatile security invoker set search_path = '' as $function$
  select private.save_coaching_workout($1,$2,$3,$4);
$function$;
create or replace function public.cancel_workout_assignment(workout_id uuid,expected_version integer,request_id uuid)
returns jsonb language sql volatile security invoker set search_path = '' as $function$
  select private.cancel_workout_assignment($1,$2,$3);
$function$;
create or replace function public.get_my_coaching_reminder()
returns jsonb language sql stable security invoker set search_path = '' as $function$
  select private.get_my_coaching_reminder();
$function$;
create or replace function public.set_my_coaching_reminder(enabled boolean,hour integer)
returns jsonb language sql volatile security invoker set search_path = '' as $function$
  select private.set_my_coaching_reminder($1,$2);
$function$;

-- Keep the existing class-scoped consent gate, audit, and personal projection.
-- It supplies the first 20 personal candidates plus whether a 21st exists.
-- Twenty personal + twenty-one canonical candidates suffice for the next
-- global page of twenty, preserving the existing (date, UUID) cursor contract.
alter function private.list_coaching_workout_history(uuid,date,uuid)
  rename to list_coaching_workout_history_personal;

-- The history adapter requires UUIDs for every exercise and set. Canonical
-- client IDs may be arbitrary stable strings, so give this read projection
-- deterministic, namespaced UUIDs without changing the canonical source IDs.
create or replace function private.coaching_history_uuid(p_key text)
returns uuid language sql immutable security invoker set search_path = '' as $function$
  select (substr(hash,1,12) || '3' || substr(hash,14,3) || '8' || substr(hash,18))::uuid
  from (select md5('setflow:coaching-history:' || p_key) as hash) digest;
$function$;

create or replace function private.coaching_workout_history_json(p_workout public.coaching_workouts)
returns jsonb language sql stable security definer set search_path = '' as $function$
  select jsonb_build_object(
    'id',p_workout.id,'user_id',p_workout.member_user_id,'date',p_workout.workout_date,
    'category',null,'intensity',null,'feedback',p_workout.instruction,
    'started_at',p_workout.session ->> 'startedAt','ended_at',p_workout.session ->> 'endedAt',
    'coaching_workout_id',p_workout.id,'coaching_kind',p_workout.kind,
    'exercises',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',private.coaching_history_uuid(jsonb_build_array('exercise',p_workout.id,exercise ->> 'id')::text),
        'base_exercise_id',exercise #>> '{template,databaseId}',
        'name',exercise #>> '{template,name}','target_muscle',exercise #>> '{template,muscle}',
        'order_index',exercise_order - 1,
        'sets',(
          select jsonb_agg(jsonb_build_object(
            'id',private.coaching_history_uuid(jsonb_build_array('set',p_workout.id,exercise ->> 'id',workout_set ->> 'number')::text),
            'set_no',(workout_set ->> 'number')::integer,
            'type',case coalesce(workout_set ->> 'type','일반')
              when '웜업' then 'warmup' when '드랍' then 'drop' when '실패' then 'fail'
              when '일반' then 'normal' else workout_set ->> 'type' end,
            'weight',(workout_set ->> 'weight')::numeric,'reps',(workout_set ->> 'reps')::integer,
            'duration_sec',nullif((workout_set ->> 'durationSeconds')::integer,0),
            'distance_m',nullif((workout_set ->> 'distanceKm')::numeric * 1000,0),
            'intensity_rpe',nullif((workout_set ->> 'intensityRpe')::numeric,0),
            'rir',workout_set -> 'rir','memo',workout_set ->> 'memo',
            'completed',(workout_set ->> 'completed')::boolean,
            'completed_at',null,'estimated_1rm',null,
            'rest_seconds',(workout_set ->> 'restSeconds')::integer
          ) order by (workout_set ->> 'number')::integer)
          from jsonb_array_elements(exercise -> 'sets') workout_set
          where p_workout.status <> 'cancelled' or (workout_set ->> 'completed')::boolean
        )
      ) order by exercise_order)
      from jsonb_array_elements(p_workout.session -> 'exercises') with ordinality as item(exercise,exercise_order)
      where p_workout.status <> 'cancelled' or exists (
        select 1 from jsonb_array_elements(exercise -> 'sets') workout_set
        where (workout_set ->> 'completed')::boolean
      )
    ),'[]'::jsonb),'feedbacks','[]'::jsonb
  );
$function$;

create or replace function private.list_coaching_workout_history(p_schedule_id uuid,p_before_date date,p_before_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $function$
declare v_personal jsonb; v_sessions jsonb; v_cursor jsonb; v_member uuid;
begin
  -- This rechecks member health consent and logs exactly one access per page.
  v_personal := private.list_coaching_workout_history_personal(p_schedule_id,p_before_date,p_before_id);
  v_member := (v_personal ->> 'member_user_id')::uuid;
  with canonical as materialized (
    select workout.* from public.coaching_workouts workout
    where workout.member_user_id = v_member
      and jsonb_array_length(workout.session -> 'exercises') > 0
      and (p_before_date is null or (workout.workout_date,workout.id) < (p_before_date,p_before_id))
      and (workout.status <> 'cancelled' or exists (
        select 1 from jsonb_array_elements(workout.session -> 'exercises') exercise,
          lateral jsonb_array_elements(exercise -> 'sets') workout_set
        where (workout_set ->> 'completed')::boolean
      ))
    order by workout.workout_date desc,workout.id desc limit 21
  ), candidates as materialized (
    select value as payload from jsonb_array_elements(v_personal -> 'sessions')
    union all
    select private.coaching_workout_history_json(canonical) from canonical
  ), page as materialized (
    select payload from candidates
    order by (payload ->> 'date')::date desc,(payload ->> 'id')::uuid desc limit 20
  )
  select coalesce(jsonb_agg(payload order by (payload ->> 'date')::date desc,(payload ->> 'id')::uuid desc),'[]'::jsonb),
    case when (select count(*) from candidates) > 20 or v_personal -> 'next_cursor' <> 'null'::jsonb
      then (select jsonb_build_object('date',payload ->> 'date','id',payload ->> 'id') from page
        order by (payload ->> 'date')::date,(payload ->> 'id')::uuid limit 1)
      else null end
  into v_sessions,v_cursor from page;
  return jsonb_build_object('schedule_id',p_schedule_id,'member_user_id',v_member,
    'sessions',v_sessions,'next_cursor',v_cursor);
end;
$function$;

revoke all on function private.has_coaching_workout_relationship(uuid,uuid),
  private.validate_coaching_workout_session(jsonb,date),private.coaching_workout_status(jsonb),
  private.coaching_workout_json(public.coaching_workouts),private.coaching_workout_replay(uuid,text,jsonb),
  private.remind_coaching_workouts(),private.coaching_workout_history_json(public.coaching_workouts),
  private.coaching_history_uuid(text)
  from public,anon,authenticated;
grant execute on function private.has_coaching_workout_relationship(uuid,uuid),
  private.validate_coaching_workout_session(jsonb,date),private.coaching_workout_status(jsonb),
  private.coaching_workout_json(public.coaching_workouts),private.coaching_workout_replay(uuid,text,jsonb),
  private.remind_coaching_workouts(),private.coaching_workout_history_json(public.coaching_workouts),
  private.coaching_history_uuid(text)
  to service_role;

revoke all on function private.list_coaching_workout_history(uuid,date,uuid) from public,anon,authenticated;
grant execute on function private.list_coaching_workout_history(uuid,date,uuid) to authenticated,service_role;

revoke all on function private.open_lesson_workout(uuid),private.set_lesson_recording_consent(uuid,boolean),
  private.list_coaching_workouts(uuid),private.create_workout_assignment(uuid,date,text,text,jsonb,uuid),
  private.save_coaching_workout(uuid,integer,jsonb,uuid),private.cancel_workout_assignment(uuid,integer,uuid),
  private.get_my_coaching_reminder(),private.set_my_coaching_reminder(boolean,integer),
  public.open_lesson_workout(uuid),public.set_lesson_recording_consent(uuid,boolean),
  public.list_coaching_workouts(uuid),public.create_workout_assignment(uuid,date,text,text,jsonb,uuid),
  public.save_coaching_workout(uuid,integer,jsonb,uuid),public.cancel_workout_assignment(uuid,integer,uuid),
  public.get_my_coaching_reminder(),public.set_my_coaching_reminder(boolean,integer) from public,anon,authenticated;
grant execute on function private.open_lesson_workout(uuid),private.set_lesson_recording_consent(uuid,boolean),
  private.list_coaching_workouts(uuid),private.create_workout_assignment(uuid,date,text,text,jsonb,uuid),
  private.save_coaching_workout(uuid,integer,jsonb,uuid),private.cancel_workout_assignment(uuid,integer,uuid),
  private.get_my_coaching_reminder(),private.set_my_coaching_reminder(boolean,integer),
  public.open_lesson_workout(uuid),public.set_lesson_recording_consent(uuid,boolean),
  public.list_coaching_workouts(uuid),public.create_workout_assignment(uuid,date,text,text,jsonb,uuid),
  public.save_coaching_workout(uuid,integer,jsonb,uuid),public.cancel_workout_assignment(uuid,integer,uuid),
  public.get_my_coaching_reminder(),public.set_my_coaching_reminder(boolean,integer) to authenticated,service_role;

-- Production already has pg_cron. A local SQL test can run without extensions.
do $cron$
begin
  if exists(select 1 from pg_namespace where nspname = 'cron') then
    perform cron.schedule('setflow-coaching-workout-reminders','*/10 * * * *',
      'select private.remind_coaching_workouts()');
  end if;
end;
$cron$;

commit;
