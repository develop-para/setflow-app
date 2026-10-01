begin;

-- Freeze the lesson's original ending boundary. Rescheduling a past lesson or
-- toggling its completion must never reopen the 48-hour correction window.
alter table public.coaching_workouts add column management_ended_at timestamptz;
update public.coaching_workouts w set management_ended_at = least(
  (w.workout_date + s.end_time) at time zone 'Asia/Seoul',s.completed_at)
  from public.coaching_schedules s where s.id = w.schedule_id and w.kind = 'lesson';

create or replace function private.capture_management_workout_end()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_completed timestamptz; v_planned timestamptz;
begin
  if new.kind = 'lesson' then
    select completed_at,(new.workout_date + end_time) at time zone 'Asia/Seoul'
      into v_completed,v_planned from public.coaching_schedules where id = new.schedule_id;
    if tg_op = 'INSERT' then
      new.management_ended_at := least(v_planned,v_completed);
    else
      new.management_ended_at := least(old.management_ended_at,v_completed);
    end if;
  end if;
  return new;
end;
$$;
create trigger capture_management_workout_end before insert or update on public.coaching_workouts
  for each row execute function private.capture_management_workout_end();

create or replace function private.capture_management_lesson_completion()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.completed_at is not null then
    update public.coaching_workouts set management_ended_at = least(management_ended_at,new.completed_at)
      where schedule_id = new.id and kind = 'lesson';
  end if;
  return new;
end;
$$;
create trigger capture_management_lesson_completion after update of completed_at on public.coaching_schedules
  for each row execute function private.capture_management_lesson_completion();
revoke all on function private.capture_management_workout_end(),private.capture_management_lesson_completion()
  from public,anon,authenticated;

-- Existing invitations and center assignments do not imply consent to edit
-- a member's lifetime history. Never backfill these explicit grants.
create table public.coaching_management_links (
  id uuid primary key default gen_random_uuid(),
  consultation_id uuid not null references public.consultations(id) on delete restrict,
  member_user_id uuid not null references public.users(id) on delete cascade,
  trainer_id uuid not null references public.trainers(id) on delete cascade,
  requested_by uuid not null references public.users(id) on delete restrict,
  status text not null default 'pending' check (status in ('pending','active','rejected','ended')),
  gym_id uuid references public.gyms(id) on delete set null,
  coaching_id uuid references public.coachings(id) on delete set null,
  created_at timestamptz not null default now(),
  accepted_at timestamptz,
  member_accepted_at timestamptz,
  trainer_accepted_at timestamptz,
  source_link_id uuid references public.coaching_management_links(id) on delete set null,
  ended_at timestamptz
);
create unique index coaching_management_open_pair on public.coaching_management_links(trainer_id,member_user_id)
  where status in ('pending','active');
create index coaching_management_member on public.coaching_management_links(member_user_id,created_at desc);
create index coaching_management_gym on public.coaching_management_links(gym_id) where gym_id is not null;

create table public.workout_corrections (
  id uuid primary key default gen_random_uuid(),
  link_id uuid not null references public.coaching_management_links(id) on delete cascade,
  requested_by uuid not null references public.users(id) on delete restrict,
  request_id uuid not null,
  record_key text not null,
  expected_revision text not null,
  exercise_id text not null,
  set_number integer not null,
  metric text not null,
  before_value numeric,
  after_value numeric not null,
  reason text not null check (char_length(btrim(reason)) between 1 and 500),
  workout_date date not null,
  workout_title text not null,
  exercise_name text not null,
  status text not null default 'pending' check (status in ('pending','applied','rejected','conflict','cancelled')),
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by uuid references public.users(id) on delete set null,
  unique(requested_by,request_id)
);
create index workout_corrections_link on public.workout_corrections(link_id,created_at desc);
alter table public.coaching_management_links enable row level security;
alter table public.workout_corrections enable row level security;
revoke all on public.coaching_management_links, public.workout_corrections from public,anon,authenticated;

create or replace function private.management_role(p_link public.coaching_management_links)
returns text language sql stable security definer set search_path = '' as $$
  select case
    when p_link.member_user_id = (select auth.uid()) then 'member'
    when exists (select 1 from public.trainers t where t.id = p_link.trainer_id
      and t.user_id = (select auth.uid()) and t.status = 'approved') then 'trainer'
    when (p_link.status = 'active' or (p_link.status = 'pending' and p_link.source_link_id is not null)) and exists (
      select 1 from public.gyms g join public.members m on m.gym_id = g.id
      where g.id = p_link.gym_id and g.owner_user_id = (select auth.uid())
        and g.status = 'verified' and m.user_id = p_link.member_user_id and m.status = 'active'
    ) then 'gym' else null end;
$$;

create or replace function private.management_active(p_link public.coaching_management_links)
returns boolean language sql stable security definer set search_path = '' as $$
  select p_link.status = 'active' and exists (
    select 1 from public.trainers t join public.coachings c on c.trainer_id = t.id
    where t.id = p_link.trainer_id and t.status = 'approved'
      and c.id = p_link.coaching_id and c.user_id = p_link.member_user_id and c.status = 'active'
  );
$$;

create or replace function private.list_management_links()
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',l.id,'member_name',private.display_name_of(l.member_user_id),
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

create or replace function private.request_management_link(p_consultation uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare c public.consultations%rowtype; t public.trainers%rowtype; l public.coaching_management_links%rowtype;
begin
  select * into c from public.consultations where id = p_consultation;
  select * into t from public.trainers where id = coalesce(c.assigned_trainer_id,c.trainer_id) and status = 'approved';
  if c.id is null or t.id is null or c.user_id = t.user_id
    or (select auth.uid()) is null or (select auth.uid()) not in (c.user_id,t.user_id) then
    raise exception 'Consultation participant required' using errcode = '42501';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('management:' || t.id::text || ':' || c.user_id::text,0));
  if exists(select 1 from public.coaching_management_links where trainer_id = t.id
    and member_user_id = c.user_id and status in ('pending','active')) then return; end if;
  insert into public.coaching_management_links(consultation_id,member_user_id,trainer_id,requested_by,member_accepted_at,trainer_accepted_at)
    values(c.id,c.user_id,t.id,(select auth.uid()),
      case when (select auth.uid()) = c.user_id then clock_timestamp() end,
      case when (select auth.uid()) = t.user_id then clock_timestamp() end) returning * into l;
  perform private.enqueue_push(case when (select auth.uid()) = c.user_id then t.user_id else c.user_id end,
    'coaching_feedback','운동 관리 연결 요청','공유 범위를 확인하고 연결을 수락해주세요.',
    jsonb_build_object('event','coaching_management','linkId',l.id::text));
end;
$$;

create or replace function private.respond_management_link(p_link uuid,p_accept boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare l public.coaching_management_links%rowtype; v_coaching uuid; v_ready boolean;
begin
  if p_accept is null then raise exception 'Decision required' using errcode = '22023'; end if;
  select * into l from public.coaching_management_links where id = p_link;
  perform 1 from public.users where id = l.member_user_id for update;
  select * into l from public.coaching_management_links where id = p_link for update;
  if l.id is null or private.management_role(l) not in ('member','trainer')
    or private.management_role(l) is null then
    raise exception 'Only the receiving participant can respond' using errcode = '42501';
  end if;
  if l.status <> 'pending' then return; end if;
  if (private.management_role(l) = 'member' and l.member_accepted_at is not null)
    or (private.management_role(l) = 'trainer' and l.trainer_accepted_at is not null) then
    raise exception 'This participant already consented' using errcode = '42501'; end if;
  if not exists(select 1 from public.trainers where id = l.trainer_id and status = 'approved') then
    raise exception 'Approved trainer required' using errcode = '42501'; end if;
  if p_accept then
    if l.source_link_id is not null and not exists (
      select 1 from public.coaching_management_links source
      join public.members m on m.user_id = source.member_user_id and m.gym_id = source.gym_id and m.status = 'active'
      join public.gym_trainers gt on gt.gym_id = source.gym_id and gt.trainer_id = l.trainer_id and gt.status = 'active'
      where source.id = l.source_link_id and source.gym_id = l.gym_id and private.management_active(source)
    ) then raise exception 'Trainer change is no longer available' using errcode = '42501'; end if;
    update public.coaching_management_links set
      member_accepted_at = case when private.management_role(l) = 'member' then clock_timestamp() else member_accepted_at end,
      trainer_accepted_at = case when private.management_role(l) = 'trainer' then clock_timestamp() else trainer_accepted_at end
      where id = l.id returning * into l;
    v_ready := l.member_accepted_at is not null and l.trainer_accepted_at is not null;
    if not v_ready then return; end if;
    perform pg_advisory_xact_lock(hashtextextended('coaching-connection:' || l.trainer_id::text || ':' || l.member_user_id::text,0));
    select id into v_coaching from public.coachings where trainer_id = l.trainer_id
      and user_id = l.member_user_id and status = 'active';
    if v_coaching is null then
      insert into public.coachings(user_id,trainer_id,program_name,start_date,status)
        values(l.member_user_id,l.trainer_id,'운동 기록 관리',current_date,'active') returning id into v_coaching;
    end if;
  end if;
  update public.coaching_management_links set status = case when p_accept then 'active' else 'rejected' end,
    accepted_at = case when p_accept then clock_timestamp() end, coaching_id = v_coaching where id = l.id;
  if p_accept and l.source_link_id is not null then
    update public.coaching_management_links set status = 'ended',ended_at = clock_timestamp()
      where source_link_id = l.source_link_id and status = 'pending';
    update public.coaching_management_links set status = 'ended',gym_id = null,ended_at = clock_timestamp() where id = l.source_link_id;
    update public.workout_corrections set status = 'cancelled',resolved_at = clock_timestamp(),resolved_by = (select auth.uid())
      where link_id = l.source_link_id and status = 'pending';
  end if;
  perform private.enqueue_push(l.requested_by,'coaching_feedback',
    case when p_accept then '운동 관리 연결을 수락했어요' else '운동 관리 연결을 거절했어요' end,
    '연결 관리에서 상태를 확인할 수 있어요.',jsonb_build_object('event','coaching_management','linkId',l.id::text));
end;
$$;

create or replace function private.end_management_link(p_link uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare l public.coaching_management_links%rowtype;
begin
  select * into l from public.coaching_management_links where id = p_link;
  perform 1 from public.users where id = l.member_user_id for update;
  select * into l from public.coaching_management_links where id = p_link for update;
  if l.id is null or private.management_role(l) is null then
    raise exception 'Management participant required' using errcode = '42501'; end if;
  update public.coaching_management_links set status = 'ended',ended_at = clock_timestamp()
    where source_link_id = p_link and status = 'pending';
  -- A center can withdraw its own participation; it cannot terminate the
  -- member's independent relationship with a trainer.
  if private.management_role(l) = 'gym' then
    update public.coaching_management_links set gym_id = null where id = p_link;
    return;
  end if;
  update public.coaching_management_links set status = 'ended',gym_id = null,ended_at = clock_timestamp() where id = p_link;
  update public.workout_corrections set status = 'cancelled',resolved_at = clock_timestamp(),resolved_by = (select auth.uid())
    where link_id = p_link and status = 'pending';
end;
$$;

create or replace function private.set_management_gym(p_link uuid,p_gym uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare l public.coaching_management_links%rowtype;
begin
  select * into l from public.coaching_management_links where id = p_link;
  perform 1 from public.users where id = l.member_user_id for update;
  select * into l from public.coaching_management_links where id = p_link for update;
  if l.id is null or l.member_user_id is distinct from (select auth.uid()) or not private.management_active(l) then
    raise exception 'Only the connected member can share with a gym' using errcode = '42501'; end if;
  if p_gym is not null and not exists(select 1 from public.members m join public.gyms g on g.id = m.gym_id
    where m.user_id = l.member_user_id and m.gym_id = p_gym and m.status = 'active' and g.status = 'verified') then
    raise exception 'Active gym membership required' using errcode = '42501'; end if;
  if l.gym_id is distinct from p_gym then
    update public.coaching_management_links set status = 'ended',ended_at = clock_timestamp()
      where source_link_id = p_link and status = 'pending';
    update public.coaching_management_links set gym_id = p_gym where id = p_link;
  end if;
end;
$$;

create or replace function private.request_management_trainer_change(p_link uuid,p_trainer uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare l public.coaching_management_links%rowtype; t public.trainers%rowtype; v_new uuid;
begin
  select * into l from public.coaching_management_links where id = p_link;
  if l.id is null or private.management_role(l) is distinct from 'gym' then
    raise exception 'Sharing gym required' using errcode = '42501'; end if;
  perform 1 from public.users where id = l.member_user_id for update;
  select * into l from public.coaching_management_links where id = p_link for update;
  if not private.management_active(l) or private.management_role(l) is distinct from 'gym' then
    raise exception 'Active management consent required' using errcode = '42501'; end if;
  select t1.* into t from public.trainers t1 join public.gym_trainers gt on gt.trainer_id = t1.id
    where t1.id = p_trainer and t1.status = 'approved' and gt.gym_id = l.gym_id and gt.status = 'active';
  if t.id is null or t.id = l.trainer_id or t.user_id = l.member_user_id then
    raise exception 'Another approved gym trainer required' using errcode = '22023'; end if;
  if exists(select 1 from public.coaching_management_links where source_link_id = l.id and trainer_id = t.id and status = 'pending') then return; end if;
  if exists(select 1 from public.coaching_management_links where trainer_id = t.id and member_user_id = l.member_user_id and status in ('pending','active')) then
    raise exception 'A management request already exists for this trainer' using errcode = '22023'; end if;
  insert into public.coaching_management_links(consultation_id,member_user_id,trainer_id,requested_by,gym_id,source_link_id)
    values(l.consultation_id,l.member_user_id,t.id,(select auth.uid()),l.gym_id,l.id) returning id into v_new;
  perform private.enqueue_push(l.member_user_id,'coaching_feedback','담당 트레이너 변경 요청',
    t.display_name || ' 트레이너로 변경하려면 동의가 필요해요.',jsonb_build_object('event','coaching_management','linkId',v_new::text));
  perform private.enqueue_push(t.user_id,'coaching_feedback','회원 관리 연결 요청',
    '회원과 트레이너가 모두 수락하면 기록 관리가 시작돼요.',jsonb_build_object('event','coaching_management','linkId',v_new::text));
end;
$$;

-- Raw records are only available to the checked RPCs below. Personal records
-- come from the canonical snapshot, so custom exercises and old records remain
-- intact; corrections also update its normalized projection in the same tx.
create or replace function private.management_end_time(p_time text)
returns timestamptz language sql stable security invoker set search_path = '' as $$
  -- Historical Flutter snapshots contain local ISO strings without an offset.
  -- Like lesson dates, those legacy wall-clock values are Korean local time.
  select case when p_time ~* '(z|[+-][0-9]{2}:[0-9]{2})$' then p_time::timestamptz
    else p_time::timestamp at time zone 'Asia/Seoul' end;
$$;

create or replace function private.management_record(p_member uuid,p_key text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare s jsonb; w public.coaching_workouts%rowtype; v_kind text; v_title text;
  v_ended timestamptz; v_date date; v_revision text;
begin
  if p_key like 'personal:%' then
    select value into s from public.app_state_snapshots a,
      lateral jsonb_array_elements(a.payload -> 'sessions')
      where a.user_id = p_member and left(value ->> 'date',10) = substring(p_key from 10);
    v_kind := 'personal'; v_title := '개인 운동';
    v_ended := private.management_end_time(s ->> 'endedAt');
    v_revision := md5(s::text);
  elsif p_key like 'coaching:%' then
    select * into w from public.coaching_workouts where id::text = substring(p_key from 10) and member_user_id = p_member;
    s := w.session; v_kind := w.kind; v_title := w.title;
    v_ended := private.management_end_time(s ->> 'endedAt');
    if w.kind = 'lesson' then
      v_ended := w.management_ended_at;
    end if;
    v_revision := md5(s::text || ':' || w.version::text || ':' || w.status);
  end if;
  if s is null then return null; end if;
  v_date := left(s ->> 'date',10)::date;
  return jsonb_build_object('key',p_key,'revision',v_revision,'session',s,'kind',v_kind,'title',v_title,
    'date',v_date,'cancelled',coalesce(w.status = 'cancelled',false),
    -- Unknown/legacy end times fail closed. The caller never supplies the clock.
    'requires_approval',v_ended is null or (v_kind <> 'lesson' and v_ended > statement_timestamp())
      or statement_timestamp() >= v_ended + interval '48 hours');
end;
$$;

create or replace function private.list_managed_workouts(p_link uuid,p_before text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare l public.coaching_management_links%rowtype; v_rows jsonb; v_next text;
begin
  select * into l from public.coaching_management_links where id = p_link;
  if l.id is null or not private.management_active(l) or private.management_role(l) is null then
    raise exception 'Active management consent required' using errcode = '42501'; end if;
  with records as (
    select 'personal:' || left(s ->> 'date',10) as key,left(s ->> 'date',10) as date
      from public.app_state_snapshots a,lateral jsonb_array_elements(a.payload -> 'sessions') s where a.user_id = l.member_user_id
    union all
    select 'coaching:' || id::text,workout_date::text from public.coaching_workouts where member_user_id = l.member_user_id
  ), candidates as materialized (
    select *,date || '/' || key as cursor from records where p_before is null or date || '/' || key < p_before
    order by date desc,key desc limit 21
  ), page as (select * from candidates order by date desc,key desc limit 20)
  select coalesce(jsonb_agg(private.management_record(l.member_user_id,key) || jsonb_build_object(
    'can_propose',private.management_role(l) = 'trainer'
      and not (private.management_record(l.member_user_id,key) ->> 'cancelled')::boolean
  ) order by date desc,key desc),'[]'::jsonb),
    case when (select count(*) from candidates) > 20 then (select cursor from page order by cursor limit 1) end
    into v_rows,v_next from page;
  return jsonb_build_object('workouts',v_rows,'next_cursor',v_next);
end;
$$;

-- Called only with member account, link and record locks already held.
create or replace function private.apply_workout_correction(p_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare c public.workout_corrections%rowtype; l public.coaching_management_links%rowtype;
  r jsonb; s jsonb; v_ex integer; v_set integer; v_snapshot integer; v_path text[];
  v_workout uuid; v_session uuid; v_target uuid; v_now timestamptz := clock_timestamp();
begin
  select * into strict c from public.workout_corrections where id = p_id;
  select * into strict l from public.coaching_management_links where id = c.link_id;
  r := private.management_record(l.member_user_id,c.record_key);
  if r is null or r ->> 'revision' is distinct from c.expected_revision then
    update public.workout_corrections set status = 'conflict',resolved_at = v_now,resolved_by = (select auth.uid()) where id = p_id;
    return;
  end if;
  s := r -> 'session';
  select (ordinality - 1)::integer into strict v_ex from jsonb_array_elements(s -> 'exercises') with ordinality
    where value ->> 'id' = c.exercise_id;
  select (ordinality - 1)::integer into strict v_set from jsonb_array_elements(s #> array['exercises',v_ex::text,'sets']) with ordinality
    where (value ->> 'number')::integer = c.set_number;
  v_path := array['exercises',v_ex::text,'sets',v_set::text,c.metric];
  s := jsonb_set(s,v_path,to_jsonb(c.after_value));
  if r ->> 'kind' = 'personal' then
    s := jsonb_set(s,'{correctionVersions}',coalesce(s -> 'correctionVersions','{}'::jsonb)
      || jsonb_build_object(jsonb_build_array(c.exercise_id,c.set_number,c.metric)::text,c.id::text));
    select (ordinality - 1)::integer into strict v_snapshot from public.app_state_snapshots a,
      lateral jsonb_array_elements(a.payload -> 'sessions') with ordinality
      where a.user_id = l.member_user_id and left(value ->> 'date',10) = c.workout_date::text;
    update public.app_state_snapshots set payload = jsonb_set(payload,array['sessions',v_snapshot::text],s),
      updated_at = v_now where user_id = l.member_user_id;
    select ws.id,sets.id into strict v_session,v_target from public.workout_sessions ws
      join public.workout_exercises e on e.session_id = ws.id
      join public.workout_sets sets on sets.exercise_id = e.id
      where ws.user_id = l.member_user_id and ws.date = c.workout_date
        and e.client_id = c.exercise_id and sets.set_no = c.set_number;
    update public.workout_sets set
      weight = case when c.metric = 'weight' then c.after_value else weight end,
      reps = case when c.metric = 'reps' then c.after_value::integer else reps end,
      rest_seconds = case when c.metric = 'restSeconds' then c.after_value::integer else rest_seconds end,
      duration_sec = case when c.metric = 'durationSeconds' then c.after_value::integer else duration_sec end,
      distance_m = case when c.metric = 'distanceKm' then c.after_value * 1000 else distance_m end,
      intensity_rpe = case when c.metric = 'intensityRpe' then c.after_value else intensity_rpe end,
      rir = case when c.metric = 'rir' then c.after_value::integer else rir end
      where id = v_target;
    update public.workout_sets set estimated_1rm = case
      when completed and type::text = 'normal' and reps between 1 and 10 and weight > 0
        and duration_sec is null and distance_m is null then
        case when reps = 1 then round(weight,2) else least(9999.99,
          round((weight * (1 + reps::numeric / 30) + weight * 36 / (37 - reps)) / 2,2)) end
      else null end where id = v_target;
    update public.workout_sessions set updated_at = v_now where id = v_session;
  else
    v_workout := substring(c.record_key from 10)::uuid;
    update public.coaching_workouts set session = s,version = version + 1,
      updated_at = v_now,last_editor_user_id = c.requested_by where id = v_workout;
  end if;
  update public.workout_corrections set status = 'applied',resolved_at = v_now,resolved_by = (select auth.uid()) where id = p_id;
  perform private.enqueue_push(l.member_user_id,'coaching_feedback','운동 기록이 수정되었어요',
    c.exercise_name || ' ' || c.set_number::text || '세트',jsonb_build_object('event','coaching_management','linkId',l.id::text));
end;
$$;

create or replace function private.propose_workout_correction(
  p_link uuid,p_key text,p_revision text,p_exercise text,p_set integer,p_metric text,p_value numeric,p_reason text,p_request uuid
) returns void language plpgsql security definer set search_path = '' as $$
declare l public.coaching_management_links%rowtype; c public.workout_corrections%rowtype;
  r jsonb; e jsonb; s jsonb; v_min numeric; v_max numeric; v_integer boolean;
begin
  select * into l from public.coaching_management_links where id = p_link;
  if l.id is null or private.management_role(l) is distinct from 'trainer' then
    raise exception 'Connected trainer required' using errcode = '42501'; end if;
  -- Same order as account snapshot saves: user -> snapshot -> workout projection.
  perform 1 from public.users where id = l.member_user_id for update;
  select * into l from public.coaching_management_links where id = p_link for update;
  if not private.management_active(l) or private.management_role(l) is distinct from 'trainer' then
    raise exception 'Active management consent required' using errcode = '42501'; end if;
  if p_request is null or p_reason is null or char_length(btrim(p_reason)) not between 1 and 500 then
    raise exception 'Request ID and correction reason required' using errcode = '22023'; end if;
  select * into c from public.workout_corrections where requested_by = (select auth.uid()) and request_id = p_request;
  if found then
    if (c.link_id,c.record_key,c.expected_revision,c.exercise_id,c.set_number,c.metric,c.after_value,c.reason)
      is distinct from (p_link,p_key,p_revision,p_exercise,p_set,p_metric,p_value,btrim(p_reason)) then
      raise exception 'Request ID is bound to another correction' using errcode = '22023'; end if;
    return;
  end if;
  if p_key like 'coaching:%' then
    perform 1 from public.coaching_workouts where id::text = substring(p_key from 10) for update;
  else
    perform 1 from public.app_state_snapshots where user_id = l.member_user_id for update;
  end if;
  r := private.management_record(l.member_user_id,p_key);
  if r is null or (r ->> 'cancelled')::boolean then raise exception 'Workout unavailable' using errcode = '42501'; end if;
  if r ->> 'revision' is distinct from p_revision then
    raise exception 'Workout changed; reload before correcting' using errcode = 'PT409'; end if;
  select value into e from jsonb_array_elements(r #> '{session,exercises}') where value ->> 'id' = p_exercise;
  select value into s from jsonb_array_elements(e -> 'sets') where (value ->> 'number')::integer = p_set;
  if s is null then raise exception 'Set unavailable' using errcode = '22023'; end if;
  select lo,hi,whole into v_min,v_max,v_integer from (values
    ('weight',0::numeric,999::numeric,false),('reps',1,1000,true),('restSeconds',0,3600,true),
    ('durationSeconds',1,604800,true),('distanceKm',.01,999,false),('intensityRpe',1,10,false),('rir',0,10,true)
  ) metrics(name,lo,hi,whole) where name = p_metric;
  if v_min is null or p_value is null or p_value not between v_min and v_max
    or (v_integer and mod(p_value,1) <> 0) then raise exception 'Invalid metric value' using errcode = '22023'; end if;
  if e #>> '{template,muscle}' in ('유산소','cardio','aerobic') and p_metric in ('weight','reps','rir') then
    raise exception 'Unsupported cardio metric' using errcode = '22023'; end if;
  if (s ->> p_metric)::numeric is not distinct from p_value then
    raise exception 'Value has not changed' using errcode = '22023'; end if;
  insert into public.workout_corrections(link_id,requested_by,request_id,record_key,expected_revision,
    exercise_id,set_number,metric,before_value,after_value,reason,workout_date,workout_title,exercise_name)
    values(l.id,(select auth.uid()),p_request,p_key,p_revision,p_exercise,p_set,p_metric,(s ->> p_metric)::numeric,
      p_value,btrim(p_reason),(r ->> 'date')::date,r ->> 'title',coalesce(e #>> '{template,name}','운동')) returning * into c;
  if (r ->> 'requires_approval')::boolean then
    perform private.enqueue_push(l.member_user_id,'coaching_feedback','운동 기록 수정 승인 요청',
      c.exercise_name || ' 수정 내용을 확인해주세요.',jsonb_build_object('event','coaching_management','linkId',l.id::text));
  else
    perform private.apply_workout_correction(c.id);
  end if;
end;
$$;

create or replace function private.respond_workout_correction(p_correction uuid,p_accept boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare c public.workout_corrections%rowtype; l public.coaching_management_links%rowtype;
begin
  if p_accept is null then raise exception 'Decision required' using errcode = '22023'; end if;
  select * into c from public.workout_corrections where id = p_correction;
  select * into l from public.coaching_management_links where id = c.link_id;
  if l.id is null or l.member_user_id is distinct from (select auth.uid()) then
    raise exception 'Only the record owner can approve' using errcode = '42501'; end if;
  perform 1 from public.users where id = l.member_user_id for update;
  select * into l from public.coaching_management_links where id = c.link_id for update;
  select * into c from public.workout_corrections where id = p_correction for update;
  if c.status <> 'pending' then return; end if;
  if not private.management_active(l) then
    update public.workout_corrections set status = 'cancelled',resolved_at = clock_timestamp(),resolved_by = (select auth.uid()) where id = c.id;
  elsif not p_accept then
    update public.workout_corrections set status = 'rejected',resolved_at = clock_timestamp(),resolved_by = (select auth.uid()) where id = c.id;
  else
    if c.record_key like 'coaching:%' then
      perform 1 from public.coaching_workouts where id::text = substring(c.record_key from 10) for update;
    else
      perform 1 from public.app_state_snapshots where user_id = l.member_user_id for update;
    end if;
    perform private.apply_workout_correction(c.id);
  end if;
  perform private.enqueue_push(c.requested_by,'coaching_feedback','기록 수정 요청 결과가 도착했어요',
    '운동 관리에서 승인 결과를 확인해주세요.',jsonb_build_object('event','coaching_management','linkId',l.id::text));
end;
$$;

create or replace function private.list_workout_corrections()
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'member_name',private.display_name_of(l.member_user_id),
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

-- Snapshot-level timestamp merging used to pick a whole local day, even when
-- only a preference changed. Require acknowledgment of every server correction
-- on an existing day before accepting that day again. The adapter merges only
-- the unseen corrected fields, preserving unrelated offline work.
create or replace function private.save_my_account_snapshot(
  p_expected_user_id uuid,p_schema_version smallint,p_payload jsonb,p_sessions jsonb,p_expected_updated_at timestamptz
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_updated timestamptz;
begin
  if p_expected_user_id is null or (select auth.uid()) is distinct from p_expected_user_id then
    raise exception 'The authenticated account changed before snapshot save.' using errcode = '42501'; end if;
  perform 1 from public.users where id = p_expected_user_id for update;
  if exists (
    select 1 from public.app_state_snapshots a,
      lateral jsonb_array_elements(a.payload -> 'sessions') old_session,
      lateral jsonb_array_elements(p_payload -> 'sessions') new_session,
      lateral jsonb_each_text(coalesce(old_session -> 'correctionVersions','{}'::jsonb)) correction
    where a.user_id = p_expected_user_id and left(old_session ->> 'date',10) = left(new_session ->> 'date',10)
      and new_session #>> array['correctionVersions',correction.key] is distinct from correction.value
  ) then raise exception 'Workout corrections changed; reload before saving'
      using errcode = 'PT409',detail = 'snapshot_version_conflict'; end if;
  begin
    return private.save_my_app_snapshot(p_schema_version,p_payload,p_sessions,p_expected_updated_at);
  exception when serialization_failure then
    select updated_at into v_updated from public.app_state_snapshots where user_id = p_expected_user_id
      and schema_version = p_schema_version and payload = p_payload;
    if found then return jsonb_build_object('updated_at',v_updated,'workouts',jsonb_build_object('idempotent',true)); end if;
    raise exception 'Snapshot changed on another device; reload before saving'
      using errcode = 'PT409',detail = 'snapshot_version_conflict';
  end;
end;
$$;
revoke all on function private.save_my_account_snapshot(uuid,smallint,jsonb,jsonb,timestamptz) from public,anon,authenticated;
grant execute on function private.save_my_account_snapshot(uuid,smallint,jsonb,jsonb,timestamptz) to authenticated,service_role;

create or replace function public.list_management_links()
returns jsonb language sql security invoker set search_path = '' as $$ select private.list_management_links(); $$;
create or replace function public.request_management_link(consultation_id uuid)
returns void language sql security invoker set search_path = '' as $$ select private.request_management_link($1); $$;
create or replace function public.respond_management_link(link_id uuid,accept boolean)
returns void language sql security invoker set search_path = '' as $$ select private.respond_management_link($1,$2); $$;
create or replace function public.end_management_link(link_id uuid)
returns void language sql security invoker set search_path = '' as $$ select private.end_management_link($1); $$;
create or replace function public.set_management_gym(link_id uuid,gym_id uuid)
returns void language sql security invoker set search_path = '' as $$ select private.set_management_gym($1,$2); $$;
create or replace function public.request_management_trainer_change(link_id uuid,trainer_id uuid)
returns void language sql security invoker set search_path = '' as $$ select private.request_management_trainer_change($1,$2); $$;
create or replace function public.list_managed_workouts(link_id uuid,before_key text default null)
returns jsonb language sql security invoker set search_path = '' as $$ select private.list_managed_workouts($1,$2); $$;
create or replace function public.propose_workout_correction(link_id uuid,record_key text,expected_revision text,
  exercise_id text,set_number integer,metric text,value numeric,reason text,request_id uuid)
returns void language sql security invoker set search_path = '' as $$ select private.propose_workout_correction($1,$2,$3,$4,$5,$6,$7,$8,$9); $$;
create or replace function public.respond_workout_correction(correction_id uuid,accept boolean)
returns void language sql security invoker set search_path = '' as $$ select private.respond_workout_correction($1,$2); $$;
create or replace function public.list_workout_corrections()
returns jsonb language sql security invoker set search_path = '' as $$ select private.list_workout_corrections(); $$;

revoke all on function private.management_role(public.coaching_management_links),
  private.management_active(public.coaching_management_links),private.management_record(uuid,text),
  private.management_end_time(text),private.apply_workout_correction(uuid) from public,anon,authenticated;

-- Only authenticated wrappers and their checked private implementations are callable.
do $$
declare f record;
begin
  for f in select p.oid::regprocedure signature from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public','private') and p.proname in (
      'list_management_links','request_management_link','respond_management_link','end_management_link',
      'set_management_gym','request_management_trainer_change','list_managed_workouts','propose_workout_correction','respond_workout_correction','list_workout_corrections')
  loop
    execute format('revoke all on function %s from public,anon,authenticated',f.signature);
    execute format('grant execute on function %s to authenticated,service_role',f.signature);
  end loop;
end;
$$;

commit;
