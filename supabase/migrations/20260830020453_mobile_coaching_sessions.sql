-- Mobile coaching relationships are independent from trainer employment at a
-- center. A member explicitly accepts a trainer invitation, each class names
-- its actual gym, and only a class-scoped snapshot is shared with that gym.

begin;

create unique index if not exists coachings_one_active_pair_uidx
  on public.coachings (trainer_id, user_id)
  where status = 'active';

create table public.coaching_connection_invites (
  id uuid primary key default gen_random_uuid(),
  trainer_id uuid not null references public.trainers(id) on delete cascade,
  created_by_user_id uuid not null references public.users(id) on delete restrict,
  recipient_name text,
  token_hash bytea not null,
  status text not null default 'pending',
  expires_at timestamptz not null,
  accepted_by_user_id uuid references public.users(id) on delete set null,
  accepted_coaching_id uuid references public.coachings(id) on delete set null,
  accepted_at timestamptz,
  create_request_id uuid not null,
  accepted_request_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint coaching_connection_invites_status_check
    check (status in ('pending', 'accepted', 'expired')),
  constraint coaching_connection_invites_recipient_name_check
    check (recipient_name is null or char_length(btrim(recipient_name)) between 1 and 120),
  constraint coaching_connection_invites_expiry_check
    check (expires_at > created_at),
  constraint coaching_connection_invites_acceptance_check
    check (
      status <> 'accepted'
      or (
        accepted_by_user_id is not null
        and accepted_coaching_id is not null
        and accepted_at is not null
        and accepted_request_id is not null
      )
    )
);

create unique index coaching_connection_invites_token_hash_uidx
  on public.coaching_connection_invites (token_hash);
create unique index coaching_connection_invites_create_request_uidx
  on public.coaching_connection_invites (created_by_user_id, create_request_id);
create unique index coaching_connection_invites_accept_request_uidx
  on public.coaching_connection_invites (accepted_by_user_id, accepted_request_id)
  where accepted_request_id is not null;
create index coaching_connection_invites_trainer_status_created_idx
  on public.coaching_connection_invites (trainer_id, status, created_at desc);

create table public.coaching_session_records (
  id uuid primary key default gen_random_uuid(),
  coaching_id uuid not null references public.coachings(id) on delete restrict,
  schedule_id uuid not null references public.coaching_schedules(id) on delete restrict,
  trainer_id uuid not null references public.trainers(id) on delete restrict,
  member_user_id uuid not null references public.users(id) on delete restrict,
  gym_id uuid not null references public.gyms(id) on delete restrict,
  routine_id uuid references public.coaching_routines(id) on delete set null,
  title text not null,
  session_date date not null,
  member_name_snapshot text not null,
  trainer_name_snapshot text not null,
  gym_name_snapshot text not null,
  member_goal_snapshot text,
  routine_title_snapshot text,
  routine_summary text,
  consultation_summary text,
  session_summary text not null,
  request_id uuid not null,
  shared_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  constraint coaching_session_records_title_check
    check (char_length(btrim(title)) between 1 and 120),
  constraint coaching_session_records_name_check
    check (
      char_length(btrim(member_name_snapshot)) between 1 and 120
      and char_length(btrim(trainer_name_snapshot)) between 1 and 120
      and char_length(btrim(gym_name_snapshot)) between 1 and 160
    ),
  constraint coaching_session_records_summary_check
    check (
      char_length(btrim(session_summary)) between 1 and 2000
      and char_length(coalesce(member_goal_snapshot, '')) <= 500
      and char_length(coalesce(routine_title_snapshot, '')) <= 160
      and char_length(coalesce(routine_summary, '')) <= 2000
      and char_length(coalesce(consultation_summary, '')) <= 2000
    )
);

create unique index coaching_session_records_schedule_uidx
  on public.coaching_session_records (schedule_id);
create unique index coaching_session_records_trainer_request_uidx
  on public.coaching_session_records (trainer_id, request_id);
create index coaching_session_records_gym_date_idx
  on public.coaching_session_records (gym_id, session_date desc, shared_at desc);
create index coaching_session_records_member_date_idx
  on public.coaching_session_records (member_user_id, session_date desc);
create index coaching_session_records_trainer_date_idx
  on public.coaching_session_records (trainer_id, session_date desc);
create index coaching_session_records_coaching_idx
  on public.coaching_session_records (coaching_id);

comment on table public.coaching_connection_invites is
  'Member-consented trainer relationships that do not imply center employment.';
comment on table public.coaching_session_records is
  'Immutable class-scoped snapshots shared with the member, trainer, and actual class gym.';
comment on column public.coaching_session_records.member_goal_snapshot is
  'Goal snapshot consented through the coaching connection and visible only to class participants and the class gym.';

alter table public.coaching_connection_invites enable row level security;
alter table public.coaching_session_records enable row level security;

revoke all on table public.coaching_connection_invites from public, anon, authenticated;
grant select (
  id, trainer_id, created_by_user_id, recipient_name, status, expires_at,
  accepted_by_user_id, accepted_coaching_id, accepted_at, created_at, updated_at
) on public.coaching_connection_invites to authenticated;
grant all on table public.coaching_connection_invites to service_role;

revoke all on table public.coaching_session_records from public, anon, authenticated;
grant select (
  id, coaching_id, schedule_id, trainer_id, member_user_id, gym_id,
  routine_id, title, session_date, member_name_snapshot,
  trainer_name_snapshot, gym_name_snapshot, member_goal_snapshot,
  routine_title_snapshot, routine_summary, consultation_summary,
  session_summary, shared_at
) on public.coaching_session_records to authenticated;
grant all on table public.coaching_session_records to service_role;

create policy coaching_connection_invites_participant_read
on public.coaching_connection_invites
for select
to authenticated
using (
  created_by_user_id = (select auth.uid())
  or accepted_by_user_id = (select auth.uid())
  or (select public.is_admin())
);

create policy coaching_session_records_scoped_read
on public.coaching_session_records
for select
to authenticated
using (
  member_user_id = (select auth.uid())
  or (select public.owns_trainer(trainer_id))
  or (select public.owns_gym(gym_id))
  or (select public.is_admin())
);

create or replace function private.coaching_connection_invite_json(
  p_invite public.coaching_connection_invites
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $function$
  select to_jsonb(p_invite)
    - array['token_hash', 'create_request_id', 'accepted_request_id']::text[];
$function$;

create or replace function private.coaching_connection_json(
  p_coaching public.coachings
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $function$
  select jsonb_build_object(
    'id', (p_coaching).id,
    'trainer_id', (p_coaching).trainer_id,
    'member_user_id', (p_coaching).user_id,
    'member_name', coalesce(nullif(btrim(u.nickname), ''), '회원'),
    'member_goal', up.goal,
    'program_name', (p_coaching).program_name,
    'status', (p_coaching).status,
    'start_date', (p_coaching).start_date,
    'created_at', (p_coaching).created_at,
    'trainer_name', coalesce(nullif(btrim(t.display_name), ''), '트레이너')
  )
  from public.users u
  join public.trainers t on t.id = (p_coaching).trainer_id
  left join public.user_profiles up on up.user_id = (p_coaching).user_id
  where u.id = (p_coaching).user_id;
$function$;

create or replace function private.create_coaching_connection_invite(
  p_request_id uuid,
  p_expires_at timestamptz,
  p_recipient_name text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := (select auth.uid());
  v_trainer public.trainers%rowtype;
  v_invite public.coaching_connection_invites%rowtype;
  v_name text := nullif(btrim(coalesce(p_recipient_name, '')), '');
  v_raw_token text;
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if p_request_id is null then
    raise exception 'request_id is required' using errcode = '22023';
  end if;
  if char_length(coalesce(v_name, '')) > 120 then
    raise exception 'recipient_name is too long' using errcode = '22023';
  end if;
  if p_expires_at is null
    or p_expires_at < now() + interval '5 minutes'
    or p_expires_at > now() + interval '30 days'
  then
    raise exception 'expires_at must be between 5 minutes and 30 days from now'
      using errcode = '22023';
  end if;

  select t.* into v_trainer
  from public.trainers t
  where t.user_id = v_user_id
    and t.status = 'approved'
  for share;
  if not found then
    raise exception 'An approved trainer profile is required' using errcode = '42501';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'coaching-connection-invite:' || v_user_id::text || ':' || p_request_id::text,
      0
    )
  );

  select i.* into v_invite
  from public.coaching_connection_invites i
  where i.created_by_user_id = v_user_id
    and i.create_request_id = p_request_id
  for update;
  if found then
    if v_invite.trainer_id is distinct from v_trainer.id
      or v_invite.recipient_name is distinct from v_name
      or v_invite.expires_at is distinct from p_expires_at
    then
      raise exception 'request_id was already used with different input'
        using errcode = '22023';
    end if;
    return jsonb_build_object(
      'invite', private.coaching_connection_invite_json(v_invite),
      'token', null,
      'token_issued', false
    );
  end if;

  v_raw_token := encode(extensions.gen_random_bytes(32), 'hex');
  insert into public.coaching_connection_invites (
    trainer_id,
    created_by_user_id,
    recipient_name,
    token_hash,
    expires_at,
    create_request_id
  ) values (
    v_trainer.id,
    v_user_id,
    v_name,
    extensions.digest(v_raw_token, 'sha256'),
    p_expires_at,
    p_request_id
  ) returning * into v_invite;

  return jsonb_build_object(
    'invite', private.coaching_connection_invite_json(v_invite),
    'token', v_raw_token,
    'token_issued', true
  );
end
$function$;

create or replace function private.accept_coaching_connection_invite(
  p_token text,
  p_request_id uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := (select auth.uid());
  v_token text := lower(btrim(coalesce(p_token, '')));
  v_user public.users%rowtype;
  v_invite public.coaching_connection_invites%rowtype;
  v_coaching public.coachings%rowtype;
  v_reused_invite_id uuid;
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if p_request_id is null then
    raise exception 'request_id is required' using errcode = '22023';
  end if;
  if v_token !~ '^[0-9a-f]{64}$' then
    raise exception 'Invite is invalid or unavailable' using errcode = '22023';
  end if;

  select u.* into v_user
  from public.users u
  where u.id = v_user_id and u.status = 'active'
  for share;
  if not found then
    raise exception 'Active user profile required' using errcode = '42501';
  end if;

  select i.* into v_invite
  from public.coaching_connection_invites i
  where i.token_hash = extensions.digest(v_token, 'sha256')
  for update;
  if not found then
    raise exception 'Invite is invalid or unavailable' using errcode = '22023';
  end if;
  if exists (
    select 1 from public.trainers t
    where t.id = v_invite.trainer_id and t.user_id = v_user_id
  ) then
    raise exception 'A trainer cannot accept their own member invite' using errcode = '22023';
  end if;

  select i.id into v_reused_invite_id
  from public.coaching_connection_invites i
  where i.accepted_by_user_id = v_user_id
    and i.accepted_request_id = p_request_id
  limit 1;
  if found and v_reused_invite_id <> v_invite.id then
    raise exception 'request_id was already used for another invite' using errcode = '22023';
  end if;

  if v_invite.status = 'accepted' then
    if v_invite.accepted_by_user_id = v_user_id
      and v_invite.accepted_request_id = p_request_id
    then
      select c.* into v_coaching
      from public.coachings c where c.id = v_invite.accepted_coaching_id;
      return jsonb_build_object(
        'accepted', true,
        'invite', private.coaching_connection_invite_json(v_invite),
        'connection', private.coaching_connection_json(v_coaching)
      );
    end if;
    raise exception 'Invite is invalid or unavailable' using errcode = '22023';
  end if;

  if v_invite.status = 'expired' or v_invite.expires_at <= now() then
    update public.coaching_connection_invites
    set status = 'expired', updated_at = now()
    where id = v_invite.id
    returning * into v_invite;
    return jsonb_build_object(
      'accepted', false,
      'invite', private.coaching_connection_invite_json(v_invite),
      'connection', null
    );
  end if;

  perform 1
  from public.trainers t
  where t.id = v_invite.trainer_id and t.status = 'approved'
  for share;
  if not found then
    raise exception 'Invite is invalid or unavailable' using errcode = '22023';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'coaching-connection:' || v_invite.trainer_id::text || ':' || v_user_id::text,
      0
    )
  );
  select c.* into v_coaching
  from public.coachings c
  where c.trainer_id = v_invite.trainer_id
    and c.user_id = v_user_id
    and c.status = 'active'
  for update;
  if not found then
    insert into public.coachings (
      user_id, trainer_id, program_name, start_date, status
    ) values (
      v_user_id, v_invite.trainer_id, '개인 코칭', current_date, 'active'
    ) returning * into v_coaching;
  end if;

  update public.coaching_connection_invites
  set status = 'accepted',
      accepted_by_user_id = v_user_id,
      accepted_coaching_id = v_coaching.id,
      accepted_at = now(),
      accepted_request_id = p_request_id,
      updated_at = now()
  where id = v_invite.id
  returning * into v_invite;

  return jsonb_build_object(
    'accepted', true,
    'invite', private.coaching_connection_invite_json(v_invite),
    'connection', private.coaching_connection_json(v_coaching)
  );
end
$function$;

create or replace function private.list_my_coaching_connections()
returns table (
  id uuid,
  trainer_id uuid,
  member_user_id uuid,
  member_name text,
  member_goal text,
  program_name text,
  status text,
  start_date date,
  created_at timestamptz,
  trainer_name text,
  session_count bigint,
  last_session_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $function$
  select
    c.id,
    c.trainer_id,
    c.user_id,
    coalesce(nullif(btrim(u.nickname), ''), '회원') as member_name,
    up.goal as member_goal,
    c.program_name,
    c.status,
    c.start_date,
    c.created_at,
    coalesce(nullif(btrim(t.display_name), ''), '트레이너') as trainer_name,
    count(sr.id) as session_count,
    max(sr.shared_at) as last_session_at
  from public.coachings c
  join public.users u on u.id = c.user_id
  join public.trainers t on t.id = c.trainer_id
  left join public.user_profiles up on up.user_id = c.user_id
  left join public.coaching_session_records sr on sr.coaching_id = c.id
  where c.user_id = (select auth.uid())
     or t.user_id = (select auth.uid())
     or (select public.is_admin())
  group by c.id, u.nickname, up.goal, t.display_name
  order by (c.status = 'active') desc, max(sr.shared_at) desc nulls last, c.created_at desc;
$function$;

create or replace function private.publish_coaching_session_record(
  p_request_id uuid,
  p_schedule_id uuid,
  p_routine_id uuid,
  p_session_summary text,
  p_routine_summary text default null,
  p_consultation_summary text default null
)
returns public.coaching_session_records
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := (select auth.uid());
  v_summary text := nullif(btrim(coalesce(p_session_summary, '')), '');
  v_routine_summary text := nullif(btrim(coalesce(p_routine_summary, '')), '');
  v_consultation_summary text := nullif(btrim(coalesce(p_consultation_summary, '')), '');
  v_schedule public.coaching_schedules%rowtype;
  v_coaching public.coachings%rowtype;
  v_record public.coaching_session_records%rowtype;
  v_member_name text;
  v_trainer_name text;
  v_gym_name text;
  v_member_goal text;
  v_routine_title text;
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if p_request_id is null or p_schedule_id is null then
    raise exception 'request_id and schedule_id are required' using errcode = '22023';
  end if;
  if v_summary is null or char_length(v_summary) > 2000
    or char_length(coalesce(v_routine_summary, '')) > 2000
    or char_length(coalesce(v_consultation_summary, '')) > 2000
  then
    raise exception 'A valid class summary is required' using errcode = '22023';
  end if;

  select cs.* into v_schedule
  from public.coaching_schedules cs
  where cs.id = p_schedule_id
  for update;
  if not found
    or v_schedule.member_user_id is null
    or v_schedule.gym_id is null
    or not public.owns_trainer(v_schedule.trainer_id)
  then
    raise exception 'An owned member class at a verified gym is required'
      using errcode = '42501';
  end if;

  select c.* into v_coaching
  from public.coachings c
  where c.trainer_id = v_schedule.trainer_id
    and c.user_id = v_schedule.member_user_id
    and c.status = 'active'
  for share;
  if not found then
    raise exception 'An active member coaching connection is required'
      using errcode = '42501';
  end if;

  select coalesce(nullif(btrim(u.nickname), ''), '회원'), up.goal
    into v_member_name, v_member_goal
  from public.users u
  left join public.user_profiles up on up.user_id = u.id
  where u.id = v_schedule.member_user_id and u.status = 'active';
  if not found then
    raise exception 'Active member profile required' using errcode = '42501';
  end if;

  select coalesce(nullif(btrim(t.display_name), ''), '트레이너')
    into v_trainer_name
  from public.trainers t
  where t.id = v_schedule.trainer_id and t.user_id = v_user_id and t.status = 'approved';
  if not found then
    raise exception 'Approved trainer profile required' using errcode = '42501';
  end if;

  select g.name into v_gym_name
  from public.gyms g
  where g.id = v_schedule.gym_id and g.status = 'verified';
  if not found then
    raise exception 'Verified class gym required' using errcode = '42501';
  end if;

  if p_routine_id is not null then
    select r.title into v_routine_title
    from public.coaching_routines r
    where r.id = p_routine_id and r.trainer_id = v_schedule.trainer_id;
    if not found then
      raise exception 'The routine is not owned by this trainer' using errcode = '42501';
    end if;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'coaching-session-record:' || v_schedule.trainer_id::text || ':' || p_request_id::text,
      0
    )
  );
  select sr.* into v_record
  from public.coaching_session_records sr
  where sr.trainer_id = v_schedule.trainer_id and sr.request_id = p_request_id
  for update;
  if found then
    if v_record.schedule_id is distinct from p_schedule_id
      or v_record.routine_id is distinct from p_routine_id
      or v_record.session_summary is distinct from v_summary
      or v_record.routine_summary is distinct from v_routine_summary
      or v_record.consultation_summary is distinct from v_consultation_summary
    then
      raise exception 'request_id was already used with different input'
        using errcode = '22023';
    end if;
    return v_record;
  end if;

  if exists (
    select 1 from public.coaching_session_records sr
    where sr.schedule_id = p_schedule_id
  ) then
    raise exception 'This schedule was already shared' using errcode = '23505';
  end if;

  update public.coaching_schedules
  set completed_at = coalesce(completed_at, now())
  where id = p_schedule_id;

  insert into public.coaching_session_records (
    coaching_id, schedule_id, trainer_id, member_user_id, gym_id, routine_id,
    title, session_date, member_name_snapshot, trainer_name_snapshot,
    gym_name_snapshot, member_goal_snapshot, routine_title_snapshot,
    routine_summary, consultation_summary, session_summary, request_id
  ) values (
    v_coaching.id, v_schedule.id, v_schedule.trainer_id,
    v_schedule.member_user_id, v_schedule.gym_id, p_routine_id,
    v_schedule.title, v_schedule.date, v_member_name, v_trainer_name,
    v_gym_name, nullif(btrim(coalesce(v_member_goal, '')), ''),
    v_routine_title, v_routine_summary, v_consultation_summary, v_summary,
    p_request_id
  ) returning * into v_record;

  return v_record;
end
$function$;

-- A mobile trainer may teach an actively connected member at any verified
-- gym. Legacy center assignments continue to work unchanged.
create or replace function private.has_active_coaching_schedule_relationship(
  p_trainer_id uuid,
  p_member_user_id uuid,
  p_gym_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select case
    when p_gym_id is null then
      p_member_user_id is null
      or exists (
        select 1 from public.coachings c
        where c.trainer_id = p_trainer_id
          and c.user_id = p_member_user_id
          and c.status = 'active'
      )
    else
      exists (
        select 1 from public.gyms g
        where g.id = p_gym_id and g.status = 'verified'
      )
      and (
        (
          p_member_user_id is not null
          and exists (
            select 1 from public.coachings c
            where c.trainer_id = p_trainer_id
              and c.user_id = p_member_user_id
              and c.status = 'active'
          )
        )
        or (
          exists (
            select 1 from public.gym_trainers gt
            where gt.gym_id = p_gym_id
              and gt.trainer_id = p_trainer_id
              and gt.status = 'active'
          )
          and (
            p_member_user_id is null
            or exists (
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
            )
          )
        )
      )
  end;
$function$;

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
  v_user_id uuid := (select auth.uid());
  v_title text := nullif(btrim(p_title), '');
  v_schedule public.coaching_schedules%rowtype;
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if p_request_id is null then
    raise exception 'A request ID is required' using errcode = '22023';
  end if;
  if p_trainer_id is null or not exists (
    select 1 from public.trainers t
    where t.id = p_trainer_id and t.user_id = v_user_id and t.status = 'approved'
  ) then
    raise exception 'An approved owned trainer profile is required' using errcode = '42501';
  end if;
  if v_title is null or char_length(v_title) > 120 then
    raise exception 'A valid schedule title is required' using errcode = '22023';
  end if;
  if p_schedule_date is null or p_start_at is null or p_end_at is null
    or p_start_at >= p_end_at
  then
    raise exception 'A valid schedule date and time range is required' using errcode = '22023';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'coaching_schedule:request:' || p_trainer_id::text || ':' || p_request_id::text,
      0
    )
  );
  select cs.* into v_schedule
  from public.coaching_schedules cs
  where cs.trainer_id = p_trainer_id and cs.request_id = p_request_id
  for update;
  if found then
    if v_schedule.member_user_id is distinct from p_member_user_id
      or v_schedule.gym_id is distinct from p_gym_id
      or v_schedule.title is distinct from v_title
      or v_schedule.date is distinct from p_schedule_date
      or v_schedule.start_time is distinct from p_start_at
      or v_schedule.end_time is distinct from p_end_at
    then
      raise exception 'A request ID cannot be reused with different schedule data'
        using errcode = '22023';
    end if;
    return v_schedule;
  end if;

  if not private.has_active_coaching_schedule_relationship(
    p_trainer_id, p_member_user_id, p_gym_id
  ) then
    raise exception 'The schedule does not have an active coaching relationship'
      using errcode = '42501';
  end if;

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
    select 1 from public.coaching_schedules cs
    where cs.trainer_id = p_trainer_id and cs.date = p_schedule_date
      and cs.start_time < p_end_at and cs.end_time > p_start_at
  ) then
    raise exception 'COACHING_SCHEDULE_TRAINER_OVERLAP' using errcode = '23P01';
  end if;
  if p_member_user_id is not null and exists (
    select 1 from public.coaching_schedules cs
    where cs.member_user_id = p_member_user_id and cs.date = p_schedule_date
      and cs.start_time < p_end_at and cs.end_time > p_start_at
  ) then
    raise exception 'COACHING_SCHEDULE_MEMBER_OVERLAP' using errcode = '23P01';
  end if;

  insert into public.coaching_schedules (
    request_id, trainer_id, member_user_id, gym_id, title, date, start_time, end_time
  ) values (
    p_request_id, p_trainer_id, p_member_user_id, p_gym_id,
    v_title, p_schedule_date, p_start_at, p_end_at
  ) returning * into v_schedule;
  return v_schedule;
end
$function$;

create or replace function public.create_coaching_connection_invite(
  request_id uuid,
  expires_at timestamptz,
  recipient_name text default null
)
returns jsonb
language sql
volatile
security invoker
set search_path = ''
as $function$
  select private.create_coaching_connection_invite($1, $2, $3);
$function$;

create or replace function public.accept_coaching_connection_invite(
  token text,
  request_id uuid
)
returns jsonb
language sql
volatile
security invoker
set search_path = ''
as $function$
  select private.accept_coaching_connection_invite($1, $2);
$function$;

create or replace function public.list_my_coaching_connections()
returns table (
  id uuid,
  trainer_id uuid,
  member_user_id uuid,
  member_name text,
  member_goal text,
  program_name text,
  status text,
  start_date date,
  created_at timestamptz,
  trainer_name text,
  session_count bigint,
  last_session_at timestamptz
)
language sql
stable
security invoker
set search_path = ''
as $function$
  select * from private.list_my_coaching_connections();
$function$;

create or replace function public.publish_coaching_session_record(
  request_id uuid,
  schedule_id uuid,
  routine_id uuid,
  session_summary text,
  routine_summary text default null,
  consultation_summary text default null
)
returns public.coaching_session_records
language sql
volatile
security invoker
set search_path = ''
as $function$
  select published.*
  from private.publish_coaching_session_record($1, $2, $3, $4, $5, $6) published;
$function$;

revoke all on function private.coaching_connection_invite_json(public.coaching_connection_invites)
  from public, anon, authenticated;
revoke all on function private.coaching_connection_json(public.coachings)
  from public, anon, authenticated;
revoke all on function private.create_coaching_connection_invite(uuid, timestamptz, text)
  from public, anon;
revoke all on function private.accept_coaching_connection_invite(text, uuid)
  from public, anon;
revoke all on function private.list_my_coaching_connections()
  from public, anon;
revoke all on function private.publish_coaching_session_record(uuid, uuid, uuid, text, text, text)
  from public, anon;
grant execute on function private.create_coaching_connection_invite(uuid, timestamptz, text)
  to authenticated, service_role;
grant execute on function private.accept_coaching_connection_invite(text, uuid)
  to authenticated, service_role;
grant execute on function private.list_my_coaching_connections()
  to authenticated, service_role;
grant execute on function private.publish_coaching_session_record(uuid, uuid, uuid, text, text, text)
  to authenticated, service_role;
grant execute on function private.coaching_connection_invite_json(public.coaching_connection_invites)
  to service_role;
grant execute on function private.coaching_connection_json(public.coachings)
  to service_role;

revoke all on function public.create_coaching_connection_invite(uuid, timestamptz, text)
  from public, anon;
revoke all on function public.accept_coaching_connection_invite(text, uuid)
  from public, anon;
revoke all on function public.list_my_coaching_connections()
  from public, anon;
revoke all on function public.publish_coaching_session_record(uuid, uuid, uuid, text, text, text)
  from public, anon;
grant execute on function public.create_coaching_connection_invite(uuid, timestamptz, text)
  to authenticated, service_role;
grant execute on function public.accept_coaching_connection_invite(text, uuid)
  to authenticated, service_role;
grant execute on function public.list_my_coaching_connections()
  to authenticated, service_role;
grant execute on function public.publish_coaching_session_record(uuid, uuid, uuid, text, text, text)
  to authenticated, service_role;

commit;
