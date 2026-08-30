-- Member-owned, class-scoped access to current health information.
--
-- The health payload is never copied into a coaching session record. The
-- trainer or gym receives a live projection only while the schedule remains
-- incomplete and the member has explicitly approved that recipient.

begin;

create table public.coaching_health_consents (
  schedule_id uuid primary key
    constraint coaching_health_consents_schedule_id_fkey
    references public.coaching_schedules(id) on delete cascade,
  member_user_id uuid not null
    constraint coaching_health_consents_member_user_id_fkey
    references auth.users(id) on delete cascade,
  trainer_id uuid not null
    constraint coaching_health_consents_trainer_id_fkey
    references public.trainers(id) on delete cascade,
  gym_id uuid not null
    constraint coaching_health_consents_gym_id_fkey
    references public.gyms(id) on delete cascade,
  share_with_trainer boolean not null default false,
  share_with_gym boolean not null default false,
  trainer_consented_at timestamptz,
  trainer_revoked_at timestamptz,
  gym_consented_at timestamptz,
  gym_revoked_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint coaching_health_consents_trainer_time_check check (
    trainer_revoked_at is null
    or trainer_consented_at is null
    or trainer_revoked_at >= trainer_consented_at
  ),
  constraint coaching_health_consents_gym_time_check check (
    gym_revoked_at is null
    or gym_consented_at is null
    or gym_revoked_at >= gym_consented_at
  )
);

create index coaching_health_consents_member_idx
  on public.coaching_health_consents (member_user_id, updated_at desc);
create index coaching_health_consents_trainer_idx
  on public.coaching_health_consents (trainer_id, updated_at desc);
create index coaching_health_consents_gym_idx
  on public.coaching_health_consents (gym_id, updated_at desc);

comment on table public.coaching_health_consents is
  'Current member decision for live health access on one coaching schedule. Access automatically ends when the schedule is completed or deleted.';
comment on column public.coaching_health_consents.share_with_trainer is
  'Member approval for the trainer assigned to this schedule only.';
comment on column public.coaching_health_consents.share_with_gym is
  'Member approval for the actual gym assigned to this schedule only.';

create table public.coaching_health_consent_events (
  id uuid primary key default gen_random_uuid(),
  schedule_id uuid
    constraint coaching_health_consent_events_schedule_id_fkey
    references public.coaching_schedules(id) on delete set null,
  member_user_id uuid not null
    constraint coaching_health_consent_events_member_user_id_fkey
    references auth.users(id) on delete cascade,
  trainer_id uuid not null
    constraint coaching_health_consent_events_trainer_id_fkey
    references public.trainers(id) on delete cascade,
  gym_id uuid not null
    constraint coaching_health_consent_events_gym_id_fkey
    references public.gyms(id) on delete cascade,
  actor_user_id uuid not null
    constraint coaching_health_consent_events_actor_user_id_fkey
    references auth.users(id) on delete cascade,
  request_id uuid not null,
  previous_share_with_trainer boolean not null,
  previous_share_with_gym boolean not null,
  share_with_trainer boolean not null,
  share_with_gym boolean not null,
  created_at timestamptz not null default now(),
  constraint coaching_health_consent_events_actor_check
    check (actor_user_id = member_user_id),
  constraint coaching_health_consent_events_request_uidx
    unique (member_user_id, request_id)
);

create index coaching_health_consent_events_schedule_idx
  on public.coaching_health_consent_events (schedule_id, created_at desc);
create index coaching_health_consent_events_member_idx
  on public.coaching_health_consent_events (member_user_id, created_at desc);
create index coaching_health_consent_events_trainer_idx
  on public.coaching_health_consent_events (trainer_id);
create index coaching_health_consent_events_gym_idx
  on public.coaching_health_consent_events (gym_id);
create index coaching_health_consent_events_actor_idx
  on public.coaching_health_consent_events (actor_user_id);

comment on table public.coaching_health_consent_events is
  'Immutable audit trail of member health-sharing decisions; it contains no health payload.';

create table public.coaching_health_access_logs (
  id uuid primary key default gen_random_uuid(),
  schedule_id uuid
    constraint coaching_health_access_logs_schedule_id_fkey
    references public.coaching_schedules(id) on delete set null,
  member_user_id uuid not null
    constraint coaching_health_access_logs_member_user_id_fkey
    references auth.users(id) on delete cascade,
  trainer_id uuid not null
    constraint coaching_health_access_logs_trainer_id_fkey
    references public.trainers(id) on delete cascade,
  gym_id uuid not null
    constraint coaching_health_access_logs_gym_id_fkey
    references public.gyms(id) on delete cascade,
  viewer_user_id uuid not null
    constraint coaching_health_access_logs_viewer_user_id_fkey
    references auth.users(id) on delete cascade,
  viewer_role text not null
    constraint coaching_health_access_logs_role_check
    check (viewer_role in ('member', 'trainer', 'gym')),
  accessed_at timestamptz not null default now()
);

create index coaching_health_access_logs_schedule_idx
  on public.coaching_health_access_logs (schedule_id, accessed_at desc);
create index coaching_health_access_logs_member_idx
  on public.coaching_health_access_logs (member_user_id, accessed_at desc);
create index coaching_health_access_logs_trainer_idx
  on public.coaching_health_access_logs (trainer_id);
create index coaching_health_access_logs_gym_idx
  on public.coaching_health_access_logs (gym_id);
create index coaching_health_access_logs_viewer_idx
  on public.coaching_health_access_logs (viewer_user_id, accessed_at desc);

comment on table public.coaching_health_access_logs is
  'Member-visible audit trail of who opened a class-scoped live health overview; it contains no health payload.';

alter table public.coaching_health_consents enable row level security;
alter table public.coaching_health_consent_events enable row level security;
alter table public.coaching_health_access_logs enable row level security;

revoke all on table public.coaching_health_consents,
  public.coaching_health_consent_events,
  public.coaching_health_access_logs
  from public, anon, authenticated;

grant select (
  schedule_id,
  member_user_id,
  trainer_id,
  gym_id,
  share_with_trainer,
  share_with_gym,
  trainer_consented_at,
  trainer_revoked_at,
  gym_consented_at,
  gym_revoked_at,
  created_at,
  updated_at
) on public.coaching_health_consents to authenticated;

grant select (
  id,
  schedule_id,
  member_user_id,
  trainer_id,
  gym_id,
  actor_user_id,
  previous_share_with_trainer,
  previous_share_with_gym,
  share_with_trainer,
  share_with_gym,
  created_at
) on public.coaching_health_consent_events to authenticated;

grant select (
  id,
  schedule_id,
  member_user_id,
  trainer_id,
  gym_id,
  viewer_user_id,
  viewer_role,
  accessed_at
) on public.coaching_health_access_logs to authenticated;

grant all on table public.coaching_health_consents,
  public.coaching_health_consent_events,
  public.coaching_health_access_logs
  to service_role;

create policy coaching_health_consents_participant_read
on public.coaching_health_consents
for select
to authenticated
using (
  member_user_id = (select auth.uid())
  or (select public.owns_trainer(trainer_id))
  or (select public.owns_gym(gym_id))
);

create policy coaching_health_consent_events_member_read
on public.coaching_health_consent_events
for select
to authenticated
using (member_user_id = (select auth.uid()));

create policy coaching_health_access_logs_member_read
on public.coaching_health_access_logs
for select
to authenticated
using (member_user_id = (select auth.uid()));

create or replace function private.coaching_health_consent_json(
  p_consent public.coaching_health_consents
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $function$
  select jsonb_build_object(
    'schedule_id', (p_consent).schedule_id,
    'member_user_id', (p_consent).member_user_id,
    'trainer_id', (p_consent).trainer_id,
    'gym_id', (p_consent).gym_id,
    'share_with_trainer', (p_consent).share_with_trainer,
    'share_with_gym', (p_consent).share_with_gym,
    'trainer_consented_at', (p_consent).trainer_consented_at,
    'trainer_revoked_at', (p_consent).trainer_revoked_at,
    'gym_consented_at', (p_consent).gym_consented_at,
    'gym_revoked_at', (p_consent).gym_revoked_at,
    'created_at', (p_consent).created_at,
    'updated_at', (p_consent).updated_at
  );
$function$;

create or replace function private.coaching_health_access_role(
  p_schedule_id uuid
)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := (select auth.uid());
  v_schedule public.coaching_schedules%rowtype;
  v_consent public.coaching_health_consents%rowtype;
begin
  if v_user_id is null or p_schedule_id is null then
    return null;
  end if;

  select schedule.*
  into v_schedule
  from public.coaching_schedules schedule
  where schedule.id = p_schedule_id;

  if not found or v_schedule.member_user_id is null or v_schedule.gym_id is null then
    return null;
  end if;

  if v_schedule.member_user_id = v_user_id then
    return 'member';
  end if;

  -- Full health access for the trainer and gym ends immediately when the
  -- trainer completes the schedule. Deleting a cancelled schedule cascades
  -- the current consent row and has the same effect.
  if v_schedule.completed_at is not null then
    return null;
  end if;

  select consent.*
  into v_consent
  from public.coaching_health_consents consent
  where consent.schedule_id = v_schedule.id
    and consent.member_user_id = v_schedule.member_user_id
    and consent.trainer_id = v_schedule.trainer_id
    and consent.gym_id = v_schedule.gym_id;

  if not found then
    return null;
  end if;

  if v_consent.share_with_trainer and exists (
    select 1
    from public.trainers trainer
    where trainer.id = v_schedule.trainer_id
      and trainer.user_id = v_user_id
      and trainer.status = 'approved'
  ) then
    return 'trainer';
  end if;

  if v_consent.share_with_gym and exists (
    select 1
    from public.gyms gym
    where gym.id = v_schedule.gym_id
      and gym.owner_user_id = v_user_id
      and gym.status = 'verified'
  ) then
    return 'gym';
  end if;

  return null;
end
$function$;

-- Replace the legacy account-wide switch. Body composition access now needs
-- at least one incomplete coaching schedule with consent for the exact
-- trainer or gym owned by the caller.
create or replace function private.can_read_member_body_data(
  p_target_user uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select (select auth.uid()) is not null
    and p_target_user is not null
    and (
      p_target_user = (select auth.uid())
      or exists (
        select 1
        from public.coaching_health_consents consent
        join public.coaching_schedules schedule
          on schedule.id = consent.schedule_id
         and schedule.member_user_id = consent.member_user_id
         and schedule.trainer_id = consent.trainer_id
         and schedule.gym_id = consent.gym_id
        left join public.trainers trainer
          on trainer.id = consent.trainer_id
         and trainer.user_id = (select auth.uid())
         and trainer.status = 'approved'
        left join public.gyms gym
          on gym.id = consent.gym_id
         and gym.owner_user_id = (select auth.uid())
         and gym.status = 'verified'
        where consent.member_user_id = p_target_user
          and schedule.completed_at is null
          and (
            (consent.share_with_trainer and trainer.id is not null)
            or (consent.share_with_gym and gym.id is not null)
          )
      )
    );
$function$;

revoke all on function private.coaching_health_consent_json(
  public.coaching_health_consents
), private.coaching_health_access_role(uuid)
  from public, anon, authenticated;
grant execute on function private.coaching_health_consent_json(
  public.coaching_health_consents
), private.coaching_health_access_role(uuid)
  to authenticated, service_role;

-- The existing public.can_read_member_body_data wrapper invokes this helper
-- as authenticated, so retain only the narrowly required execute grant.
revoke all on function private.can_read_member_body_data(uuid)
  from public, anon, authenticated;
grant execute on function private.can_read_member_body_data(uuid)
  to authenticated, service_role;

create or replace function private.set_coaching_health_consent(
  p_schedule_id uuid,
  p_share_with_trainer boolean,
  p_share_with_gym boolean,
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
  v_schedule public.coaching_schedules%rowtype;
  v_existing public.coaching_health_consents%rowtype;
  v_saved public.coaching_health_consents%rowtype;
  v_previous_trainer boolean := false;
  v_previous_gym boolean := false;
  v_now timestamptz := clock_timestamp();
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if p_schedule_id is null or p_request_id is null then
    raise exception 'schedule_id and request_id are required'
      using errcode = '22023';
  end if;

  select schedule.*
  into v_schedule
  from public.coaching_schedules schedule
  where schedule.id = p_schedule_id
  for update;

  if not found
     or v_schedule.member_user_id is distinct from v_user_id
     or v_schedule.gym_id is null then
    raise exception 'Only the scheduled member can set health sharing'
      using errcode = '42501';
  end if;
  if v_schedule.completed_at is not null then
    raise exception 'Health sharing has expired for this schedule'
      using errcode = '22023';
  end if;

  -- A retried request returns the current server state without appending a
  -- duplicate audit event.
  if exists (
    select 1
    from public.coaching_health_consent_events event
    where event.member_user_id = v_user_id
      and event.request_id = p_request_id
      and event.schedule_id is not distinct from p_schedule_id
  ) then
    select consent.*
    into v_saved
    from public.coaching_health_consents consent
    where consent.schedule_id = p_schedule_id;
    return private.coaching_health_consent_json(v_saved);
  end if;

  select consent.*
  into v_existing
  from public.coaching_health_consents consent
  where consent.schedule_id = p_schedule_id
  for update;

  if found then
    v_previous_trainer := v_existing.share_with_trainer;
    v_previous_gym := v_existing.share_with_gym;
  end if;

  insert into public.coaching_health_consents (
    schedule_id,
    member_user_id,
    trainer_id,
    gym_id,
    share_with_trainer,
    share_with_gym,
    trainer_consented_at,
    trainer_revoked_at,
    gym_consented_at,
    gym_revoked_at,
    created_at,
    updated_at
  ) values (
    v_schedule.id,
    v_user_id,
    v_schedule.trainer_id,
    v_schedule.gym_id,
    p_share_with_trainer,
    p_share_with_gym,
    case when p_share_with_trainer then v_now else null end,
    null,
    case when p_share_with_gym then v_now else null end,
    null,
    v_now,
    v_now
  )
  on conflict (schedule_id) do update
  set share_with_trainer = excluded.share_with_trainer,
      share_with_gym = excluded.share_with_gym,
      trainer_consented_at = case
        when excluded.share_with_trainer
             and not public.coaching_health_consents.share_with_trainer
          then v_now
        else public.coaching_health_consents.trainer_consented_at
      end,
      trainer_revoked_at = case
        when excluded.share_with_trainer then null
        when public.coaching_health_consents.share_with_trainer then v_now
        else public.coaching_health_consents.trainer_revoked_at
      end,
      gym_consented_at = case
        when excluded.share_with_gym
             and not public.coaching_health_consents.share_with_gym
          then v_now
        else public.coaching_health_consents.gym_consented_at
      end,
      gym_revoked_at = case
        when excluded.share_with_gym then null
        when public.coaching_health_consents.share_with_gym then v_now
        else public.coaching_health_consents.gym_revoked_at
      end,
      updated_at = v_now
  returning * into v_saved;

  insert into public.coaching_health_consent_events (
    schedule_id,
    member_user_id,
    trainer_id,
    gym_id,
    actor_user_id,
    request_id,
    previous_share_with_trainer,
    previous_share_with_gym,
    share_with_trainer,
    share_with_gym,
    created_at
  ) values (
    v_schedule.id,
    v_user_id,
    v_schedule.trainer_id,
    v_schedule.gym_id,
    v_user_id,
    p_request_id,
    v_previous_trainer,
    v_previous_gym,
    p_share_with_trainer,
    p_share_with_gym,
    v_now
  );

  -- The legacy switch no longer grants access. Keep it false so old clients
  -- cannot imply that an account-wide permission is still active.
  update public.user_consents consent
  set share_body_data = false,
      updated_at = v_now
  where consent.user_id = v_user_id
    and consent.share_body_data;

  return private.coaching_health_consent_json(v_saved);
end
$function$;

create or replace function public.set_coaching_health_consent(
  schedule_id uuid,
  share_with_trainer boolean,
  share_with_gym boolean,
  request_id uuid
)
returns jsonb
language sql
volatile
security invoker
set search_path = ''
as $function$
  select private.set_coaching_health_consent($1, $2, $3, $4);
$function$;

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
        limit 50
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

create or replace function public.get_coaching_health_overview(
  schedule_id uuid
)
returns jsonb
language sql
volatile
security invoker
set search_path = ''
as $function$
  select private.get_coaching_health_overview($1);
$function$;

revoke all on function private.set_coaching_health_consent(
  uuid, boolean, boolean, uuid
), private.get_coaching_health_overview(uuid)
  from public, anon, authenticated;
grant execute on function private.set_coaching_health_consent(
  uuid, boolean, boolean, uuid
), private.get_coaching_health_overview(uuid)
  to authenticated, service_role;

revoke all on function public.set_coaching_health_consent(
  uuid, boolean, boolean, uuid
), public.get_coaching_health_overview(uuid)
  from public, anon, authenticated;
grant execute on function public.set_coaching_health_consent(
  uuid, boolean, boolean, uuid
), public.get_coaching_health_overview(uuid)
  to authenticated, service_role;

update public.user_consents
set share_body_data = false,
    updated_at = clock_timestamp()
where share_body_data;

comment on column public.user_consents.share_body_data is
  'Deprecated account-wide flag. Health access is granted only by coaching_health_consents for one incomplete schedule.';

commit;
