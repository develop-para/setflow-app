-- Make coaching schedule creation retry-safe and serialize overlap checks.
-- Existing rows remain readable with a null request_id; every new client/RPC
-- create requires a caller-generated UUID.

alter table public.coaching_schedules
  add column if not exists request_id uuid;

create unique index if not exists coaching_schedules_trainer_request_uidx
  on public.coaching_schedules (trainer_id, request_id)
  where request_id is not null;

comment on column public.coaching_schedules.request_id is
  'Stable client request UUID used to recover a committed create response.';

create or replace function private.create_coaching_schedule(
  p_request_id uuid,
  p_trainer_id uuid,
  p_member_user_id uuid,
  p_gym_id uuid,
  p_title text,
  p_schedule_date date,
  p_start_at time without time zone,
  p_end_at time without time zone
)
returns public.coaching_schedules
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := auth.uid();
  v_title text := nullif(btrim(p_title), '');
  v_schedule public.coaching_schedules%rowtype;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;
  if p_request_id is null then
    raise exception using errcode = '22023', message = 'A request ID is required';
  end if;
  if p_trainer_id is null or not exists (
    select 1
    from public.trainers t
    where t.id = p_trainer_id
      and t.user_id = v_user_id
      and t.status = 'approved'
  ) then
    raise exception using errcode = '42501', message = 'An approved owned trainer profile is required';
  end if;
  if v_title is null or char_length(v_title) > 120 then
    raise exception using errcode = '22023', message = 'A valid schedule title is required';
  end if;
  if p_schedule_date is null
     or p_start_at is null
     or p_end_at is null
     or p_start_at >= p_end_at then
    raise exception using errcode = '22023', message = 'A valid schedule date and time range is required';
  end if;

  -- Serialize recovery for the same idempotency key even if a buggy retry
  -- changes the date and would otherwise acquire a different date lock.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'coaching_schedule:request:' || p_trainer_id::text || ':' || p_request_id::text,
      0
    )
  );

  select cs.*
    into v_schedule
  from public.coaching_schedules cs
  where cs.trainer_id = p_trainer_id
    and cs.request_id = p_request_id
  for update;

  if found then
    if v_schedule.member_user_id is distinct from p_member_user_id
       or v_schedule.gym_id is distinct from p_gym_id
       or v_schedule.title is distinct from v_title
       or v_schedule.date is distinct from p_schedule_date
       or v_schedule.start_time is distinct from p_start_at
       or v_schedule.end_time is distinct from p_end_at then
      raise exception using errcode = '22023', message = 'A request ID cannot be reused with different schedule data';
    end if;
    return v_schedule;
  end if;

  -- Recheck the full trainer/member relationship in the same transaction as
  -- the insert. Client-side workspace IDs are never authoritative.
  if p_gym_id is null then
    if p_member_user_id is not null and not exists (
      select 1
      from public.coachings c
      where c.trainer_id = p_trainer_id
        and c.user_id = p_member_user_id
        and c.status = 'active'
    ) then
      raise exception using errcode = '42501', message = 'The member has no active coaching relationship with this trainer';
    end if;
  else
    if not exists (
      select 1
      from public.gym_trainers gt
      join public.gyms g
        on g.id = gt.gym_id
       and g.status = 'verified'
      where gt.gym_id = p_gym_id
        and gt.trainer_id = p_trainer_id
        and gt.status = 'active'
    ) then
      raise exception using errcode = '42501', message = 'The trainer is not active at this gym';
    end if;
    if p_member_user_id is not null and not exists (
      select 1
      from public.members m
      join public.member_assignments ma
        on ma.member_id = m.id
       and ma.gym_id = m.gym_id
       and ma.active
      where m.gym_id = p_gym_id
        and m.user_id = p_member_user_id
        and m.status = 'active'
        and ma.trainer_id = p_trainer_id
    ) then
      raise exception using errcode = '42501', message = 'The member is not actively assigned to this trainer';
    end if;
  end if;

  -- Every creator locks in trainer -> member order. This makes the overlap
  -- predicate safe against concurrent inserts without requiring btree_gist.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'coaching_schedule:trainer:' || p_trainer_id::text || ':' || p_schedule_date::text,
      0
    )
  );
  if p_member_user_id is not null then
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(
        'coaching_schedule:member:' || p_member_user_id::text || ':' || p_schedule_date::text,
        0
      )
    );
  end if;

  if exists (
    select 1
    from public.coaching_schedules cs
    where cs.trainer_id = p_trainer_id
      and cs.date = p_schedule_date
      and cs.start_time < p_end_at
      and cs.end_time > p_start_at
  ) then
    raise exception using
      errcode = '23P01',
      message = 'COACHING_SCHEDULE_TRAINER_OVERLAP';
  end if;

  if p_member_user_id is not null and exists (
    select 1
    from public.coaching_schedules cs
    where cs.member_user_id = p_member_user_id
      and cs.date = p_schedule_date
      and cs.start_time < p_end_at
      and cs.end_time > p_start_at
  ) then
    raise exception using
      errcode = '23P01',
      message = 'COACHING_SCHEDULE_MEMBER_OVERLAP';
  end if;

  insert into public.coaching_schedules (
    request_id,
    trainer_id,
    member_user_id,
    gym_id,
    title,
    date,
    start_time,
    end_time
  ) values (
    p_request_id,
    p_trainer_id,
    p_member_user_id,
    p_gym_id,
    v_title,
    p_schedule_date,
    p_start_at,
    p_end_at
  )
  returning * into v_schedule;

  return v_schedule;
end
$function$;

create or replace function public.create_coaching_schedule(
  request_id uuid,
  trainer_id uuid,
  member_user_id uuid,
  gym_id uuid,
  title text,
  schedule_date date,
  start_at time without time zone,
  end_at time without time zone
)
returns public.coaching_schedules
language sql
volatile
security invoker
set search_path = ''
as $function$
  select created.*
  from private.create_coaching_schedule(
    $1, $2, $3, $4, $5, $6, $7, $8
  ) as created;
$function$;

revoke all on function private.create_coaching_schedule(
  uuid, uuid, uuid, uuid, text, date,
  time without time zone, time without time zone
) from public, anon;
grant execute on function private.create_coaching_schedule(
  uuid, uuid, uuid, uuid, text, date,
  time without time zone, time without time zone
) to authenticated, service_role;

revoke all on function public.create_coaching_schedule(
  uuid, uuid, uuid, uuid, text, date,
  time without time zone, time without time zone
) from public, anon;
grant execute on function public.create_coaching_schedule(
  uuid, uuid, uuid, uuid, text, date,
  time without time zone, time without time zone
) to authenticated, service_role;

-- Creation is now available only through the checked atomic RPC. Owning
-- trainers retain the existing update/delete policies for completion/removal.
revoke insert on table public.coaching_schedules from authenticated;
drop policy if exists coaching_schedules_trainer_insert
  on public.coaching_schedules;
