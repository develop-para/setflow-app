alter table public.members
  add column if not exists status text not null default 'active',
  add column if not exists ended_at timestamptz,
  add column if not exists rejoined_at timestamptz,
  add column if not exists ended_by_user_id uuid
    references public.users(id) on delete set null;

-- This migration is timestamped before the separately generated atomic
-- schedule migration in a clean replay, so declare its idempotency column here
-- as well. The later migration repeats both statements with IF NOT EXISTS.
alter table public.coaching_schedules
  add column if not exists request_id uuid;
create unique index if not exists coaching_schedules_trainer_request_uidx
  on public.coaching_schedules (trainer_id, request_id)
  where request_id is not null;

do $$
begin
  if not exists (
    select 1
    from pg_catalog.pg_constraint
    where conrelid = 'public.members'::regclass
      and conname = 'members_status_lifecycle_check'
  ) then
    alter table public.members
      add constraint members_status_lifecycle_check
      check (
        (status = 'active' and ended_at is null and ended_by_user_id is null)
        or
        (status = 'ended' and ended_at is not null)
      );
  end if;
end;
$$;

create index if not exists members_gym_active_created_idx
  on public.members (gym_id, created_at desc)
  where status = 'active';
create index if not exists members_user_active_idx
  on public.members (user_id)
  where status = 'active' and user_id is not null;

revoke update (status, ended_at, ended_by_user_id, rejoined_at)
  on public.members from authenticated;

create table if not exists private.business_membership_end_requests (
  request_id uuid primary key,
  member_id uuid not null references public.members(id) on delete restrict,
  ended_by_user_id uuid references public.users(id) on delete set null,
  response jsonb,
  created_at timestamptz not null default now()
);
create index if not exists business_membership_end_requests_member_idx
  on private.business_membership_end_requests (member_id, created_at desc);
revoke all on table private.business_membership_end_requests
  from public, anon, authenticated;
grant all on table private.business_membership_end_requests to service_role;

create or replace view public.v_gym_settlement_summary
with (security_invoker = true)
as
with settlement_totals as (
  select si.gym_id, sum(si.amount) as total_revenue
  from public.settlement_items si
  group by si.gym_id
), member_totals as (
  select m.gym_id, count(*) as member_count
  from public.members m
  where m.status = 'active'
  group by m.gym_id
), trainer_totals as (
  select gt.gym_id, count(*) as trainer_count
  from public.gym_trainers gt
  where gt.status = 'active'
  group by gt.gym_id
)
select
  g.id as gym_id,
  g.name,
  coalesce(st.total_revenue, 0::numeric) as total_revenue,
  coalesce(mt.member_count, 0::bigint) as member_count,
  coalesce(tt.trainer_count, 0::bigint) as trainer_count
from public.gyms g
left join settlement_totals st on st.gym_id = g.id
left join member_totals mt on mt.gym_id = g.id
left join trainer_totals tt on tt.gym_id = g.id;

create or replace function private.has_active_member_business_relationship(
  p_target_user uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (select auth.uid()) is not null
    and p_target_user is not null
    and (
      exists (
        select 1
        from public.members m
        join public.member_assignments ma
          on ma.member_id = m.id
         and ma.gym_id = m.gym_id
         and ma.active
        join public.trainers t
          on t.id = ma.trainer_id
         and t.user_id = (select auth.uid())
         and t.status = 'approved'
        join public.gym_trainers gt
          on gt.gym_id = m.gym_id
         and gt.trainer_id = t.id
         and gt.trainer_user_id = (select auth.uid())
         and gt.status = 'active'
        join public.gyms g
          on g.id = m.gym_id
         and g.status = 'verified'
        where m.user_id = p_target_user
          and m.status = 'active'
      )
      or exists (
        select 1
        from public.members m
        join public.gyms g
          on g.id = m.gym_id
         and g.status = 'verified'
        where m.user_id = p_target_user
          and m.status = 'active'
          and g.owner_user_id = (select auth.uid())
      )
    );
$$;

create or replace function private.can_access_business_member(
  p_member_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (select auth.uid()) is not null
    and p_member_id is not null
    and exists (
      select 1
      from public.members m
      where m.id = p_member_id
        and m.status = 'active'
        and (
          m.user_id = (select auth.uid())
          or exists (
            select 1
            from public.gyms g
            where g.id = m.gym_id
              and g.owner_user_id = (select auth.uid())
              and g.status = 'verified'
          )
          or exists (
            select 1
            from public.member_assignments ma
            join public.trainers t
              on t.id = ma.trainer_id
             and t.status = 'approved'
             and t.user_id = (select auth.uid())
            join public.gym_trainers gt
              on gt.gym_id = m.gym_id
             and gt.trainer_id = t.id
             and gt.trainer_user_id = (select auth.uid())
             and gt.status = 'active'
            join public.gyms g
              on g.id = m.gym_id
             and g.status = 'verified'
            where ma.member_id = m.id
              and ma.gym_id = m.gym_id
              and ma.active
          )
          or exists (
            select 1
            from public.admin_users au
            where au.user_id = (select auth.uid())
              and au.status = 'active'
          )
        )
    );
$$;

revoke all on function private.has_active_member_business_relationship(uuid)
  from public, anon, authenticated;
grant execute on function private.has_active_member_business_relationship(uuid)
  to authenticated, service_role;
revoke all on function private.can_access_business_member(uuid)
  from public, anon, authenticated;
grant execute on function private.can_access_business_member(uuid)
  to authenticated, service_role;

create or replace function private.assign_gym_member(
  p_member_id uuid,
  p_trainer_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_gym_id uuid;
  v_member_status text;
  v_assignment_id uuid;
  v_is_admin boolean;
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select m.gym_id, m.status into v_gym_id, v_member_status
  from public.members m
  where m.id = p_member_id
  for update;
  if not found then
    raise exception 'Member not found' using errcode = 'P0002';
  end if;
  if v_member_status <> 'active' then
    raise exception 'Membership has ended' using errcode = '22023';
  end if;

  select exists (
    select 1 from public.admin_users au
    where au.user_id = v_user_id and au.status = 'active'
  ) into v_is_admin;
  if not v_is_admin and not exists (
    select 1 from public.gyms g
    where g.id = v_gym_id
      and g.owner_user_id = v_user_id
      and g.status = 'verified'
  ) then
    raise exception 'Gym owner access required' using errcode = '42501';
  end if;

  if p_trainer_id is not null and not exists (
    select 1
    from public.gym_trainers gt
    join public.trainers t on t.id = gt.trainer_id
    where gt.gym_id = v_gym_id
      and gt.trainer_id = p_trainer_id
      and gt.status = 'active'
      and t.status = 'approved'
  ) then
    raise exception 'Trainer is not active at this gym' using errcode = '23503';
  end if;

  update public.member_assignments
  set active = false
  where member_id = p_member_id and active;

  if p_trainer_id is not null then
    insert into public.member_assignments(
      gym_id, member_id, trainer_id, assigned_at, active
    ) values (
      v_gym_id, p_member_id, p_trainer_id, now(), true
    ) returning id into v_assignment_id;
  end if;

  return jsonb_build_object(
    'assignment_id', v_assignment_id,
    'gym_id', v_gym_id,
    'member_id', p_member_id,
    'trainer_id', p_trainer_id,
    'active', p_trainer_id is not null
  );
end;
$$;

create or replace function private.end_business_membership(
  p_member_id uuid,
  p_request_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_member public.members%rowtype;
  v_gym_name text;
  v_request_member_id uuid;
  v_request_actor_id uuid;
  v_response jsonb;
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if p_member_id is null or p_request_id is null then
    raise exception 'member_id and request_id are required' using errcode = '22023';
  end if;

  select m.* into v_member
  from public.members m
  join public.gyms g on g.id = m.gym_id
  where m.id = p_member_id
    and (
      m.user_id = v_user_id
      or (
        g.owner_user_id = v_user_id
        and g.status = 'verified'
      )
    )
  for update of m;
  if not found then
    raise exception 'Membership termination access denied' using errcode = '42501';
  end if;
  select g.name into v_gym_name
  from public.gyms g
  where g.id = v_member.gym_id;

  insert into private.business_membership_end_requests(
    request_id, member_id, ended_by_user_id
  ) values (
    p_request_id, v_member.id, v_user_id
  ) on conflict (request_id) do nothing;
  select r.member_id, r.ended_by_user_id, r.response
    into v_request_member_id, v_request_actor_id, v_response
  from private.business_membership_end_requests r
  where r.request_id = p_request_id
  for update;
  if v_request_member_id is distinct from v_member.id
    or v_request_actor_id is distinct from v_user_id
  then
    raise exception 'request_id was already used for another membership payload'
      using errcode = '22023';
  end if;
  if v_response is not null then
    return v_response;
  end if;

  if v_member.status = 'active' then
    update public.members
    set status = 'ended',
        ended_at = statement_timestamp(),
        ended_by_user_id = v_user_id
    where id = v_member.id
    returning * into v_member;

    update public.member_assignments
    set active = false
    where member_id = v_member.id and active;
  elsif v_member.status <> 'ended' then
    raise exception 'Unknown membership status' using errcode = '22023';
  end if;

  v_response := jsonb_build_object(
    'id', v_member.id,
    'gym_id', v_member.gym_id,
    'gym_name', v_gym_name,
    'user_id', v_member.user_id,
    'name', v_member.name,
    'status', v_member.status,
    'ended_at', v_member.ended_at
  );
  update private.business_membership_end_requests
  set response = v_response
  where request_id = p_request_id;
  return v_response;
end;
$$;

revoke all on function private.end_business_membership(uuid, uuid)
  from public, anon, authenticated;
grant execute on function private.end_business_membership(uuid, uuid)
  to authenticated, service_role;

create or replace function public.end_business_membership(
  member_id uuid,
  request_id uuid
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select private.end_business_membership(member_id, request_id);
$$;

revoke all on function public.end_business_membership(uuid, uuid)
  from public, anon;
grant execute on function public.end_business_membership(uuid, uuid)
  to authenticated, service_role;

create or replace function private.list_my_business_memberships()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when (select auth.uid()) is null then
      pg_catalog.jsonb_build_array()
    else coalesce(
      (
        select pg_catalog.jsonb_agg(
          pg_catalog.jsonb_build_object(
            'id', m.id,
            'gym_id', m.gym_id,
            'gym_name', g.name,
            'user_id', m.user_id,
            'name', m.name,
            'status', m.status,
            'created_at', m.created_at,
            'ended_at', m.ended_at
          ) order by m.created_at desc
        )
        from public.members m
        join public.gyms g on g.id = m.gym_id
        where m.user_id = (select auth.uid())
          and m.status = 'active'
      ),
      pg_catalog.jsonb_build_array()
    )
  end;
$$;

revoke all on function private.list_my_business_memberships()
  from public, anon, authenticated;
grant execute on function private.list_my_business_memberships()
  to authenticated, service_role;

create or replace function public.list_my_business_memberships()
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select private.list_my_business_memberships();
$$;

revoke all on function public.list_my_business_memberships()
  from public, anon;
grant execute on function public.list_my_business_memberships()
  to authenticated, service_role;

-- Preserve the already hardened token/idempotency implementation and wrap it
-- with the membership lifecycle transition. Because both calls share one
-- transaction, an invite cannot become accepted unless reactivation succeeds.
do $$
begin
  if pg_catalog.to_regprocedure(
    'private.accept_business_invite_before_membership_lifecycle(text,uuid)'
  ) is null then
    execute 'alter function private.accept_business_invite(text, uuid) '
      || 'rename to accept_business_invite_before_membership_lifecycle';
  end if;
end;
$$;

revoke all on function private.accept_business_invite_before_membership_lifecycle(text, uuid)
  from public, anon, authenticated;
grant execute on function private.accept_business_invite_before_membership_lifecycle(text, uuid)
  to service_role;

create or replace function private.accept_business_invite(
  p_token text,
  p_request_id uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_token text := lower(btrim(coalesce(p_token, '')));
  v_was_pending boolean := false;
  v_result jsonb;
  v_member_id uuid;
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

  select bi.status = 'pending' into v_was_pending
  from public.business_invites bi
  where bi.token_hash = extensions.digest(v_token, 'sha256')
  for update;
  v_was_pending := coalesce(v_was_pending, false);

  v_result := private.accept_business_invite_before_membership_lifecycle(
    p_token,
    p_request_id
  );
  if v_was_pending
    and coalesce((v_result ->> 'accepted')::boolean, false)
    and nullif(v_result ->> 'member_id', '') is not null
  then
    v_member_id := (v_result ->> 'member_id')::uuid;
    update public.members
    set rejoined_at = case
          when status = 'ended' then statement_timestamp()
          else rejoined_at
        end,
        status = 'active',
        ended_at = null,
        ended_by_user_id = null
    where id = v_member_id
      and user_id = v_user_id;
    if not found then
      raise exception 'Accepted membership does not belong to the caller'
        using errcode = '42501';
    end if;
  end if;
  return v_result;
end;
$$;

revoke all on function private.accept_business_invite(text, uuid)
  from public, anon, authenticated;
grant execute on function private.accept_business_invite(text, uuid)
  to authenticated, service_role;

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
as $$
  select case
    when p_gym_id is null then
      p_member_user_id is null
      or exists (
        select 1
        from public.coachings c
        where c.trainer_id = p_trainer_id
          and c.user_id = p_member_user_id
          and c.status = 'active'
      )
    else
      exists (
        select 1
        from public.gym_trainers gt
        join public.gyms g
          on g.id = gt.gym_id
         and g.status = 'verified'
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
  end;
$$;

revoke all on function private.has_active_coaching_schedule_relationship(uuid, uuid, uuid)
  from public, anon, authenticated;
grant execute on function private.has_active_coaching_schedule_relationship(uuid, uuid, uuid)
  to authenticated, service_role;

drop policy if exists coaching_schedules_shared_read
  on public.coaching_schedules;
create policy coaching_schedules_shared_read
on public.coaching_schedules
for select
to authenticated
using (
  member_user_id = (select auth.uid())
  or (select is_admin())
  or (
    (
      (select owns_trainer(trainer_id))
      or (gym_id is not null and (select owns_gym(gym_id)))
    )
    and (select private.has_active_coaching_schedule_relationship(
      trainer_id, member_user_id, gym_id
    ))
  )
);

drop policy if exists coaching_schedules_trainer_update
  on public.coaching_schedules;
create policy coaching_schedules_trainer_update
on public.coaching_schedules
for update
to authenticated
using (
  (select owns_trainer(trainer_id))
  and (select private.has_active_coaching_schedule_relationship(
    trainer_id, member_user_id, gym_id
  ))
)
with check (
  (select owns_trainer(trainer_id))
  and (select private.has_active_coaching_schedule_relationship(
    trainer_id, member_user_id, gym_id
  ))
);

drop policy if exists coaching_schedules_trainer_delete
  on public.coaching_schedules;
create policy coaching_schedules_trainer_delete
on public.coaching_schedules
for delete
to authenticated
using (
  (select owns_trainer(trainer_id))
  and (select private.has_active_coaching_schedule_relationship(
    trainer_id, member_user_id, gym_id
  ))
);

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
as $$
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
    select 1
    from public.trainers t
    where t.id = p_trainer_id
      and t.user_id = v_user_id
      and t.status = 'approved'
  ) then
    raise exception 'An approved owned trainer profile is required'
      using errcode = '42501';
  end if;
  if v_title is null or char_length(v_title) > 120 then
    raise exception 'A valid schedule title is required' using errcode = '22023';
  end if;
  if p_schedule_date is null or p_start_at is null or p_end_at is null
    or p_start_at >= p_end_at
  then
    raise exception 'A valid schedule date and time range is required'
      using errcode = '22023';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'coaching_schedule:request:' || p_trainer_id::text || ':' || p_request_id::text,
      0
    )
  );

  select cs.* into v_schedule
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
    raise exception 'The member has no active relationship with this trainer'
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
    select 1
    from public.coaching_schedules cs
    where cs.trainer_id = p_trainer_id
      and cs.date = p_schedule_date
      and cs.start_time < p_end_at
      and cs.end_time > p_start_at
  ) then
    raise exception 'COACHING_SCHEDULE_TRAINER_OVERLAP' using errcode = '23P01';
  end if;
  if p_member_user_id is not null and exists (
    select 1
    from public.coaching_schedules cs
    where cs.member_user_id = p_member_user_id
      and cs.date = p_schedule_date
      and cs.start_time < p_end_at
      and cs.end_time > p_start_at
  ) then
    raise exception 'COACHING_SCHEDULE_MEMBER_OVERLAP' using errcode = '23P01';
  end if;

  insert into public.coaching_schedules(
    request_id, trainer_id, member_user_id, gym_id,
    title, date, start_time, end_time
  ) values (
    p_request_id, p_trainer_id, p_member_user_id, p_gym_id,
    v_title, p_schedule_date, p_start_at, p_end_at
  ) returning * into v_schedule;
  return v_schedule;
end;
$$;
