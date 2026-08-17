-- Normalize member workout records for trainer/gym collaboration and split
-- read access from owner-only write access.  The app snapshot remains the
-- member's source of truth while these tables provide a safe shared projection.

alter table public.workout_sets
  add column if not exists rest_seconds integer not null default 90;

alter table public.workout_exercises
  add column if not exists client_id text;

update public.workout_exercises
set client_id = id::text
where client_id is null;

alter table public.workout_exercises
  alter column client_id set not null;

alter table public.workout_exercises
  drop constraint if exists workout_exercises_client_id_check;

alter table public.workout_exercises
  add constraint workout_exercises_client_id_check
  check (char_length(client_id) between 1 and 200);

create unique index if not exists workout_exercises_session_client_uidx
  on public.workout_exercises (session_id, client_id);

create unique index if not exists workout_sets_exercise_set_no_uidx
  on public.workout_sets (exercise_id, set_no);

alter table public.user_consents
  add column if not exists share_workout_records boolean not null default false;

alter table public.coaching_schedules
  add column if not exists gym_id uuid references public.gyms(id) on delete cascade;

create index if not exists coaching_schedules_gym_date_idx
  on public.coaching_schedules (gym_id, date);

alter table public.workout_sets
  drop constraint if exists workout_sets_rest_seconds_check;

alter table public.workout_sets
  add constraint workout_sets_rest_seconds_check
  check (rest_seconds between 0 and 3600);

alter table public.session_feedback
  add column if not exists request_id uuid;

create unique index if not exists session_feedback_trainer_request_uidx
  on public.session_feedback (trainer_id, request_id)
  where request_id is not null;

create index if not exists session_feedback_session_created_idx
  on public.session_feedback (session_id, created_at desc);

create index if not exists workout_exercises_session_order_idx
  on public.workout_exercises (session_id, order_index);

create index if not exists workout_sets_exercise_set_no_idx
  on public.workout_sets (exercise_id, set_no);

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
      )
      or exists (
        select 1
        from public.members m
        join public.gyms g
          on g.id = m.gym_id
         and g.status = 'verified'
        where m.user_id = p_target_user
          and g.owner_user_id = (select auth.uid())
      )
    );
$$;

create or replace function private.can_read_member_workout(
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
      p_target_user = (select auth.uid())
      or (
        exists (
          select 1
          from public.user_consents c
          where c.user_id = p_target_user
            and c.share_workout_records
        )
        and private.has_active_member_business_relationship(p_target_user)
      )
    );
$$;

create or replace function private.can_write_member_workout(
  p_target_user uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (select auth.uid()) is not null
    and p_target_user = (select auth.uid());
$$;

create or replace function private.can_read_member_body_data(
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
      p_target_user = (select auth.uid())
      or (
        exists (
          select 1
          from public.user_consents c
          where c.user_id = p_target_user
            and c.share_body_data
        )
        and private.has_active_member_business_relationship(p_target_user)
      )
    );
$$;

revoke all on function private.has_active_member_business_relationship(uuid)
  from public, anon, authenticated;
grant execute on function private.has_active_member_business_relationship(uuid)
  to authenticated, service_role;
revoke all on function private.can_read_member_workout(uuid) from public;
revoke all on function private.can_read_member_workout(uuid) from anon;
revoke all on function private.can_read_member_workout(uuid) from authenticated;
revoke all on function private.can_write_member_workout(uuid) from public;
revoke all on function private.can_write_member_workout(uuid) from anon;
revoke all on function private.can_write_member_workout(uuid) from authenticated;
revoke all on function private.can_read_member_body_data(uuid) from public;
revoke all on function private.can_read_member_body_data(uuid) from anon;
revoke all on function private.can_read_member_body_data(uuid) from authenticated;
grant execute on function private.can_read_member_workout(uuid)
  to authenticated, service_role;
grant execute on function private.can_write_member_workout(uuid)
  to authenticated, service_role;
grant execute on function private.can_read_member_body_data(uuid)
  to authenticated, service_role;

-- Member profile/assignment access must expire together with the trainer's
-- active center affiliation. A stale active assignment alone is not enough.
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
    and (
      exists (
        select 1
        from public.members m
        where m.id = p_member_id
          and m.user_id = (select auth.uid())
      )
      or exists (
        select 1
        from public.members m
        join public.gyms g
          on g.id = m.gym_id
         and g.status = 'verified'
        where m.id = p_member_id
          and g.owner_user_id = (select auth.uid())
      )
      or exists (
        select 1
        from public.members m
        join public.member_assignments ma
          on ma.member_id = m.id
         and ma.gym_id = m.gym_id
         and ma.active
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
        where m.id = p_member_id
      )
      or exists (
        select 1
        from public.admin_users au
        where au.user_id = (select auth.uid())
          and au.status = 'active'
      )
    );
$$;

revoke all on function private.can_access_business_member(uuid)
  from public, anon;
grant execute on function private.can_access_business_member(uuid)
  to authenticated, service_role;

create or replace function private.can_access_business_consultation(
  p_consultation_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (select auth.uid()) is not null
    and p_consultation_id is not null
    and exists (
      select 1
      from public.consultations c
      where c.id = p_consultation_id
        and (
          c.user_id = (select auth.uid())
          or exists (
            select 1
            from public.trainers t
            where t.id in (c.trainer_id, c.assigned_trainer_id)
              and t.user_id = (select auth.uid())
              and t.status = 'approved'
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
          )
          or exists (
            select 1
            from public.gyms g
            where g.id = c.gym_id
              and g.owner_user_id = (select auth.uid())
              and g.status = 'verified'
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

revoke all on function private.can_access_business_consultation(uuid)
  from public, anon;
grant execute on function private.can_access_business_consultation(uuid)
  to authenticated, service_role;

create or replace function public.can_read_member_workout(
  target_user uuid
)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select private.can_read_member_workout(target_user);
$$;

create or replace function public.can_write_member_workout(
  target_user uuid
)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select private.can_write_member_workout(target_user);
$$;

create or replace function public.can_read_member_body_data(
  target_user uuid
)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select private.can_read_member_body_data(target_user);
$$;

-- Keep the legacy helper compatible for any old client, but make it read-only
-- in meaning.  Write policies below no longer call this helper.
create or replace function public.can_access_member_workout(
  target_user uuid
)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select private.can_read_member_workout(target_user);
$$;

revoke all on function public.can_read_member_workout(uuid) from public;
revoke all on function public.can_read_member_workout(uuid) from anon;
revoke all on function public.can_write_member_workout(uuid) from public;
revoke all on function public.can_write_member_workout(uuid) from anon;
revoke all on function public.can_read_member_body_data(uuid) from public;
revoke all on function public.can_read_member_body_data(uuid) from anon;
revoke all on function public.can_access_member_workout(uuid) from public;
revoke all on function public.can_access_member_workout(uuid) from anon;
grant execute on function public.can_read_member_workout(uuid) to authenticated;
grant execute on function public.can_write_member_workout(uuid) to authenticated;
grant execute on function public.can_read_member_body_data(uuid) to authenticated;
grant execute on function public.can_access_member_workout(uuid) to authenticated;
grant execute on function public.can_read_member_workout(uuid) to service_role;
grant execute on function public.can_write_member_workout(uuid) to service_role;
grant execute on function public.can_read_member_body_data(uuid) to service_role;
grant execute on function public.can_access_member_workout(uuid) to service_role;

drop policy if exists rd_sessions on public.workout_sessions;
drop policy if exists wr_sessions on public.workout_sessions;
drop policy if exists workout_sessions_shared_read on public.workout_sessions;
drop policy if exists workout_sessions_owner_insert on public.workout_sessions;
drop policy if exists workout_sessions_owner_update on public.workout_sessions;
drop policy if exists workout_sessions_owner_delete on public.workout_sessions;

create policy workout_sessions_shared_read
on public.workout_sessions
for select
to authenticated
using ((select public.can_read_member_workout(user_id)));

create policy workout_sessions_owner_insert
on public.workout_sessions
for insert
to authenticated
with check ((select public.can_write_member_workout(user_id)));

create policy workout_sessions_owner_update
on public.workout_sessions
for update
to authenticated
using ((select public.can_write_member_workout(user_id)))
with check ((select public.can_write_member_workout(user_id)));

create policy workout_sessions_owner_delete
on public.workout_sessions
for delete
to authenticated
using ((select public.can_write_member_workout(user_id)));

drop policy if exists rw_exercises on public.workout_exercises;
drop policy if exists workout_exercises_shared_read on public.workout_exercises;
drop policy if exists workout_exercises_owner_insert on public.workout_exercises;
drop policy if exists workout_exercises_owner_update on public.workout_exercises;
drop policy if exists workout_exercises_owner_delete on public.workout_exercises;

create policy workout_exercises_shared_read
on public.workout_exercises
for select
to authenticated
using (
  exists (
    select 1
    from public.workout_sessions s
    where s.id = workout_exercises.session_id
      and (select public.can_read_member_workout(s.user_id))
  )
);

create policy workout_exercises_owner_insert
on public.workout_exercises
for insert
to authenticated
with check (
  exists (
    select 1
    from public.workout_sessions s
    where s.id = workout_exercises.session_id
      and (select public.can_write_member_workout(s.user_id))
  )
);

create policy workout_exercises_owner_update
on public.workout_exercises
for update
to authenticated
using (
  exists (
    select 1
    from public.workout_sessions s
    where s.id = workout_exercises.session_id
      and (select public.can_write_member_workout(s.user_id))
  )
)
with check (
  exists (
    select 1
    from public.workout_sessions s
    where s.id = workout_exercises.session_id
      and (select public.can_write_member_workout(s.user_id))
  )
);

create policy workout_exercises_owner_delete
on public.workout_exercises
for delete
to authenticated
using (
  exists (
    select 1
    from public.workout_sessions s
    where s.id = workout_exercises.session_id
      and (select public.can_write_member_workout(s.user_id))
  )
);

drop policy if exists rw_sets on public.workout_sets;
drop policy if exists workout_sets_shared_read on public.workout_sets;
drop policy if exists workout_sets_owner_insert on public.workout_sets;
drop policy if exists workout_sets_owner_update on public.workout_sets;
drop policy if exists workout_sets_owner_delete on public.workout_sets;

create policy workout_sets_shared_read
on public.workout_sets
for select
to authenticated
using (
  exists (
    select 1
    from public.workout_exercises e
    join public.workout_sessions s on s.id = e.session_id
    where e.id = workout_sets.exercise_id
      and (select public.can_read_member_workout(s.user_id))
  )
);

create policy workout_sets_owner_insert
on public.workout_sets
for insert
to authenticated
with check (
  exists (
    select 1
    from public.workout_exercises e
    join public.workout_sessions s on s.id = e.session_id
    where e.id = workout_sets.exercise_id
      and (select public.can_write_member_workout(s.user_id))
  )
);

create policy workout_sets_owner_update
on public.workout_sets
for update
to authenticated
using (
  exists (
    select 1
    from public.workout_exercises e
    join public.workout_sessions s on s.id = e.session_id
    where e.id = workout_sets.exercise_id
      and (select public.can_write_member_workout(s.user_id))
  )
)
with check (
  exists (
    select 1
    from public.workout_exercises e
    join public.workout_sessions s on s.id = e.session_id
    where e.id = workout_sets.exercise_id
      and (select public.can_write_member_workout(s.user_id))
  )
);

create policy workout_sets_owner_delete
on public.workout_sets
for delete
to authenticated
using (
  exists (
    select 1
    from public.workout_exercises e
    join public.workout_sessions s on s.id = e.session_id
    where e.id = workout_sets.exercise_id
      and (select public.can_write_member_workout(s.user_id))
  )
);

drop policy if exists rw_sess_feedback on public.session_feedback;
drop policy if exists session_feedback_shared_read on public.session_feedback;

create policy session_feedback_shared_read
on public.session_feedback
for select
to authenticated
using (
  exists (
    select 1
    from public.workout_sessions s
    where s.id = session_feedback.session_id
      and (select public.can_read_member_workout(s.user_id))
  )
);

revoke all on table public.workout_sessions from anon;
revoke all on table public.workout_exercises from anon;
revoke all on table public.workout_sets from anon;
revoke all on table public.session_feedback from anon;
revoke all on table public.workout_sessions from authenticated;
revoke all on table public.workout_exercises from authenticated;
revoke all on table public.workout_sets from authenticated;
revoke all on table public.session_feedback from authenticated;
grant select, insert, update, delete on table public.workout_sessions to authenticated;
grant select, insert, update, delete on table public.workout_exercises to authenticated;
grant select, insert, update, delete on table public.workout_sets to authenticated;
grant select on table public.session_feedback to authenticated;
grant all on table public.workout_sessions to service_role;
grant all on table public.workout_exercises to service_role;
grant all on table public.workout_sets to service_role;
grant all on table public.session_feedback to service_role;

drop policy if exists own_bodycomp on public.body_compositions;
drop policy if exists body_compositions_shared_read on public.body_compositions;
drop policy if exists body_compositions_owner_insert on public.body_compositions;
drop policy if exists body_compositions_owner_update on public.body_compositions;
drop policy if exists body_compositions_owner_delete on public.body_compositions;

create policy body_compositions_shared_read
on public.body_compositions
for select
to authenticated
using ((select public.can_read_member_body_data(user_id)));

create policy body_compositions_owner_insert
on public.body_compositions
for insert
to authenticated
with check (user_id = (select auth.uid()));

create policy body_compositions_owner_update
on public.body_compositions
for update
to authenticated
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));

create policy body_compositions_owner_delete
on public.body_compositions
for delete
to authenticated
using (user_id = (select auth.uid()));

revoke all on table public.body_compositions from anon;
revoke all on table public.body_compositions from authenticated;
grant select, insert, update, delete on table public.body_compositions
  to authenticated;
grant all on table public.body_compositions to service_role;

-- A center can create an unlinked member profile, but linking an auth account
-- must happen through an explicit invite acceptance workflow. Never allow an
-- owner to attach an arbitrary known user UUID during a direct INSERT.
revoke insert (user_id) on table public.members from authenticated;
revoke insert (completion_rate, last_activity_at)
  on table public.members from authenticated;
revoke update (completion_rate, last_activity_at)
  on table public.members from authenticated;

-- Assignment is relationship metadata, not a workout event. Do not falsify
-- the member's last activity timestamp when changing the assigned trainer.
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
  v_assignment_id uuid;
  v_is_admin boolean;
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select m.gym_id into v_gym_id
  from public.members m
  where m.id = p_member_id
  for update;
  if not found then
    raise exception 'Member not found' using errcode = 'P0002';
  end if;

  select exists (
    select 1
    from public.admin_users au
    where au.user_id = v_user_id
      and au.status = 'active'
  ) into v_is_admin;

  if not v_is_admin and not exists (
    select 1
    from public.gyms g
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
  where member_id = p_member_id
    and active;

  if p_trainer_id is not null then
    insert into public.member_assignments(
      gym_id,
      member_id,
      trainer_id,
      assigned_at,
      active
    ) values (
      v_gym_id,
      p_member_id,
      p_trainer_id,
      now(),
      true
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

create or replace function private.sync_my_workout_snapshot(
  p_sessions jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
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
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if p_sessions is null or jsonb_typeof(p_sessions) <> 'array' then
    raise exception 'sessions must be an array' using errcode = '22023';
  end if;
  if pg_column_size(p_sessions) > 5242880 then
    raise exception 'workout payload is too large' using errcode = '22023';
  end if;

  -- Serialize every save/sync/clear for this account. This also makes the
  -- first snapshot insert race deterministic instead of raising a random
  -- unique-violation under two simultaneous devices.
  perform 1
  from public.users u
  where u.id = v_user_id
  for update;
  if not found then
    raise exception 'Authenticated profile is missing' using errcode = '42501';
  end if;

  v_session_count := jsonb_array_length(p_sessions);
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
    select value from jsonb_array_elements(p_sessions)
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
    values (v_user_id, v_date, now())
    on conflict (user_id, date) do update
      set updated_at = excluded.updated_at
    returning id into v_session_id;

    if jsonb_typeof(v_session -> 'exercises') <> 'array' then
      raise exception 'exercises must be an array' using errcode = '22023';
    end if;
    v_exercise_count := jsonb_array_length(v_session -> 'exercises');
    if v_exercise_count > 100 then
      raise exception 'Too many exercises in a session' using errcode = '22023';
    end if;
    v_total_exercises := v_total_exercises + v_exercise_count;
    if v_total_exercises > 5000 then
      raise exception 'Too many exercises in workout payload' using errcode = '22023';
    end if;

    v_order := 0;
    for v_exercise in
      select value from jsonb_array_elements(v_session -> 'exercises')
    loop
      if nullif(btrim(v_exercise ->> 'name'), '') is null then
        raise exception 'Exercise name is required' using errcode = '22023';
      end if;
      v_client_id := nullif(btrim(v_exercise ->> 'client_id'), '');
      if v_client_id is null or char_length(v_client_id) > 200 then
        raise exception 'Exercise client_id is required and must be at most 200 characters'
          using errcode = '22023';
      end if;

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
            select me.id
            from public.master_exercises me
            where me.id = (v_exercise ->> 'base_exercise_id')::uuid
              and (not me.is_custom or me.owner_user_id = v_user_id)
          )
          else null
        end,
        left(btrim(v_exercise ->> 'name'), 120),
        nullif(left(btrim(coalesce(v_exercise ->> 'target_muscle', '')), 80), ''),
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

      if jsonb_typeof(v_exercise -> 'sets') <> 'array' then
        raise exception 'sets must be an array' using errcode = '22023';
      end if;
      v_set_count := jsonb_array_length(v_exercise -> 'sets');
      if v_set_count > 100 then
        raise exception 'Too many sets in an exercise' using errcode = '22023';
      end if;
      v_total_sets := v_total_sets + v_set_count;
      if v_total_sets > 50000 then
        raise exception 'Too many sets in workout payload' using errcode = '22023';
      end if;

      for v_set in
        select value from jsonb_array_elements(v_exercise -> 'sets')
      loop
        v_set_no := (v_set ->> 'set_no')::integer;
        if v_set_no not between 1 and 100 then
          raise exception 'Set number must be between 1 and 100'
            using errcode = '22023';
        end if;
        insert into pg_temp.setflow_sync_sets(exercise_id, set_no)
        values (v_exercise_id, v_set_no)
        on conflict do nothing;
        if not found then
          raise exception 'Duplicate set number in an exercise'
            using errcode = '22023';
        end if;

        v_type := case lower(coalesce(v_set ->> 'type', 'normal'))
          when 'warmup' then 'warmup'
          when 'drop' then 'drop'
          when 'fail' then 'fail'
          else 'normal'
        end;
        insert into public.workout_sets(
          exercise_id,
          set_no,
          type,
          weight,
          reps,
          completed,
          completed_at,
          estimated_1rm,
          rest_seconds
        ) values (
          v_exercise_id,
          v_set_no,
          v_type,
          greatest(0, least(10000, coalesce((v_set ->> 'weight')::numeric, 0))),
          greatest(0, least(1000, coalesce((v_set ->> 'reps')::integer, 0))),
          coalesce((v_set ->> 'completed')::boolean, false),
          case when coalesce((v_set ->> 'completed')::boolean, false) then now() else null end,
          case
            when coalesce((v_set ->> 'reps')::integer, 0) between 1 and 15
              and coalesce((v_set ->> 'weight')::numeric, 0) > 0
            then round(
              coalesce((v_set ->> 'weight')::numeric, 0)
              * (1 + coalesce((v_set ->> 'reps')::numeric, 0) / 30),
              2
            )
            else null
          end,
          greatest(0, least(3600, coalesce((v_set ->> 'rest_seconds')::integer, 90)))
        )
        on conflict (exercise_id, set_no) do update
        set type = excluded.type,
            weight = excluded.weight,
            reps = excluded.reps,
            completed = excluded.completed,
            completed_at = case
              when not excluded.completed then null
              when public.workout_sets.completed_at is null then now()
              else public.workout_sets.completed_at
            end,
            estimated_1rm = excluded.estimated_1rm,
            rest_seconds = excluded.rest_seconds;
      end loop;
    end loop;
  end loop;

  delete from public.workout_sets ws
  using public.workout_exercises e, public.workout_sessions s
  where ws.exercise_id = e.id
    and e.session_id = s.id
    and s.user_id = v_user_id
    and not exists (
      select 1
      from pg_temp.setflow_sync_sets keep
      where keep.exercise_id = ws.exercise_id
        and keep.set_no = ws.set_no
    );

  delete from public.workout_exercises e
  using public.workout_sessions s
  where e.session_id = s.id
    and s.user_id = v_user_id
    and not exists (
      select 1
      from pg_temp.setflow_sync_exercises keep
      where keep.session_id = e.session_id
        and keep.client_id = e.client_id
    );

  delete from public.workout_sessions s
  where s.user_id = v_user_id
    and not exists (
      select 1
      from pg_temp.setflow_sync_dates d
      where d.workout_date = s.date
    );

  update public.members m
  set last_activity_at = (
        select max(s.date)::timestamp with time zone
        from public.workout_sessions s
        where s.user_id = v_user_id
      ),
      completion_rate = coalesce((
        select round(
          100.0 * count(*) filter (where ws.completed)
          / nullif(count(*), 0),
          2
        )
        from public.workout_sessions s
        join public.workout_exercises e on e.session_id = s.id
        join public.workout_sets ws on ws.exercise_id = e.id
        where s.user_id = v_user_id
          and s.date >= current_date - 28
      ), 0)
  where m.user_id = v_user_id;

  return jsonb_build_object(
    'session_count', v_session_count,
    'exercise_count', v_total_exercises,
    'set_count', v_total_sets,
    'synced_at', now()
  );
end;
$$;

create or replace function private.save_my_app_snapshot(
  p_schema_version smallint,
  p_payload jsonb,
  p_sessions jsonb,
  p_expected_updated_at timestamp with time zone
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_current_updated_at timestamp with time zone;
  v_next_updated_at timestamp with time zone := clock_timestamp();
  v_exists boolean := false;
  v_sync jsonb;
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if p_schema_version is null or p_schema_version < 1 then
    raise exception 'Invalid schema version' using errcode = '22023';
  end if;
  if jsonb_typeof(coalesce(p_payload, '{}'::jsonb)) <> 'object' then
    raise exception 'payload must be an object' using errcode = '22023';
  end if;
  if pg_column_size(p_payload) > 5242880 then
    raise exception 'snapshot payload is too large' using errcode = '22023';
  end if;

  perform 1
  from public.users u
  where u.id = v_user_id
  for update;
  if not found then
    raise exception 'Authenticated profile is missing' using errcode = '42501';
  end if;

  select s.updated_at
  into v_current_updated_at
  from public.app_state_snapshots s
  where s.user_id = v_user_id
  for update;
  v_exists := found;

  if v_exists then
    if p_expected_updated_at is null
      or v_current_updated_at <> p_expected_updated_at
    then
      raise exception 'Snapshot changed on another device; reload before saving'
        using errcode = '40001';
    end if;
    update public.app_state_snapshots
    set schema_version = p_schema_version,
        payload = p_payload,
        updated_at = v_next_updated_at
    where user_id = v_user_id;
  else
    if p_expected_updated_at is not null then
      raise exception 'Snapshot no longer exists; reload before saving'
        using errcode = '40001';
    end if;
    insert into public.app_state_snapshots(
      user_id,
      schema_version,
      payload,
      updated_at
    ) values (
      v_user_id,
      p_schema_version,
      p_payload,
      v_next_updated_at
    );
  end if;

  v_sync := private.sync_my_workout_snapshot(p_sessions);
  return jsonb_build_object(
    'updated_at', v_next_updated_at,
    'workouts', v_sync
  );
end;
$$;

create or replace function private.clear_my_app_data(
  p_expected_updated_at timestamp with time zone
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_current_updated_at timestamp with time zone;
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  perform 1
  from public.users u
  where u.id = v_user_id
  for update;
  if not found then
    raise exception 'Authenticated profile is missing' using errcode = '42501';
  end if;

  select s.updated_at
  into v_current_updated_at
  from public.app_state_snapshots s
  where s.user_id = v_user_id
  for update;

  if found
    and (
      p_expected_updated_at is null
      or v_current_updated_at <> p_expected_updated_at
    )
  then
    raise exception 'Snapshot changed on another device; reload before clearing'
      using errcode = '40001';
  end if;

  delete from public.app_state_snapshots where user_id = v_user_id;
  delete from public.workout_sessions where user_id = v_user_id;
  update public.members
  set last_activity_at = null,
      completion_rate = 0
  where user_id = v_user_id;

  return jsonb_build_object('cleared', true, 'cleared_at', now());
end;
$$;

revoke all on function private.sync_my_workout_snapshot(jsonb) from public;
revoke all on function private.sync_my_workout_snapshot(jsonb) from anon;
revoke all on function private.sync_my_workout_snapshot(jsonb) from authenticated;
grant execute on function private.sync_my_workout_snapshot(jsonb)
  to service_role;
revoke all on function private.save_my_app_snapshot(
  smallint, jsonb, jsonb, timestamp with time zone
) from public, anon, authenticated;
revoke all on function private.clear_my_app_data(timestamp with time zone)
  from public, anon, authenticated;
grant execute on function private.save_my_app_snapshot(
  smallint, jsonb, jsonb, timestamp with time zone
) to authenticated, service_role;
grant execute on function private.clear_my_app_data(timestamp with time zone)
  to authenticated, service_role;

create or replace function public.sync_my_workout_snapshot(
  sessions jsonb
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select private.sync_my_workout_snapshot(sessions);
$$;

revoke all on function public.sync_my_workout_snapshot(jsonb) from public;
revoke all on function public.sync_my_workout_snapshot(jsonb) from anon;
revoke all on function public.sync_my_workout_snapshot(jsonb) from authenticated;
grant execute on function public.sync_my_workout_snapshot(jsonb) to service_role;

create or replace function public.save_my_app_snapshot(
  schema_version smallint,
  payload jsonb,
  sessions jsonb,
  expected_updated_at timestamp with time zone default null
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select private.save_my_app_snapshot(
    schema_version,
    payload,
    sessions,
    expected_updated_at
  );
$$;

create or replace function public.clear_my_app_data(
  expected_updated_at timestamp with time zone default null
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select private.clear_my_app_data(expected_updated_at);
$$;

revoke all on function public.save_my_app_snapshot(
  smallint, jsonb, jsonb, timestamp with time zone
) from public, anon;
revoke all on function public.clear_my_app_data(timestamp with time zone)
  from public, anon;
grant execute on function public.save_my_app_snapshot(
  smallint, jsonb, jsonb, timestamp with time zone
) to authenticated, service_role;
grant execute on function public.clear_my_app_data(timestamp with time zone)
  to authenticated, service_role;

-- Snapshot writes now go through the version-checked atomic RPC. Direct read
-- remains available to the owning client for startup hydration.
revoke all on table public.app_state_snapshots from anon;
revoke all on table public.app_state_snapshots from authenticated;
grant select on table public.app_state_snapshots to authenticated;

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
as $$
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

  select m.* into v_member
  from public.members m
  where m.id = p_member_id;

  if not found or not private.can_access_business_member(p_member_id) then
    raise exception 'Member access denied' using errcode = '42501';
  end if;

  if v_member.user_id is not null then
    select coalesce(c.share_workout_records, false)
    into v_shared
    from public.user_consents c
    where c.user_id = v_member.user_id;
    v_shared := coalesce(v_shared, false);
    v_can_read := private.can_read_member_workout(v_member.user_id);
  end if;

  if v_can_read then
    select coalesce(jsonb_agg(session_json order by session_date desc), '[]'::jsonb)
    into v_sessions
    from (
      select s.date as session_date,
        jsonb_build_object(
          'id', s.id,
          'user_id', s.user_id,
          'date', s.date,
          'category', s.category,
          'intensity', s.intensity,
          'feedback', s.feedback,
          'started_at', s.started_at,
          'ended_at', s.ended_at,
          'exercises', coalesce((
            select jsonb_agg(
              jsonb_build_object(
                'id', e.id,
                'base_exercise_id', e.base_exercise_id,
                'name', e.name,
                'target_muscle', e.target_muscle,
                'order_index', e.order_index,
                'sets', coalesce((
                  select jsonb_agg(
                    jsonb_build_object(
                      'id', ws.id,
                      'set_no', ws.set_no,
                      'type', ws.type,
                      'weight', ws.weight,
                      'reps', ws.reps,
                      'duration_sec', ws.duration_sec,
                      'distance_m', ws.distance_m,
                      'rir', ws.rir,
                      'memo', ws.memo,
                      'completed', ws.completed,
                      'completed_at', ws.completed_at,
                      'estimated_1rm', ws.estimated_1rm,
                      'rest_seconds', ws.rest_seconds
                    ) order by ws.set_no
                  )
                  from public.workout_sets ws
                  where ws.exercise_id = e.id
                ), '[]'::jsonb)
              ) order by e.order_index
            )
            from public.workout_exercises e
            where e.session_id = s.id
          ), '[]'::jsonb),
          'feedbacks', coalesce((
            select jsonb_agg(
              jsonb_build_object(
                'id', sf.id,
                'session_id', sf.session_id,
                'trainer_user_id', sf.trainer_id,
                'author_name', coalesce(t.display_name, u.nickname, '담당자'),
                'text', sf.text,
                'created_at', sf.created_at
              ) order by sf.created_at desc
            )
            from public.session_feedback sf
            left join public.trainers t on t.user_id = sf.trainer_id
            left join public.users u on u.id = sf.trainer_id
            where sf.session_id = s.id
          ), '[]'::jsonb)
        ) as session_json
      from public.workout_sessions s
      where s.user_id = v_member.user_id
        and s.date between v_from and v_to
    ) q;
  end if;

  return jsonb_build_object(
    'member_id', v_member.id,
    'member_user_id', v_member.user_id,
    'share_workout_records', v_shared,
    'can_read_workouts', v_can_read,
    'sessions', v_sessions
  );
end;
$$;

revoke all on function private.get_business_member_detail(uuid, date, date) from public;
revoke all on function private.get_business_member_detail(uuid, date, date) from anon;
revoke all on function private.get_business_member_detail(uuid, date, date) from authenticated;
grant execute on function private.get_business_member_detail(uuid, date, date)
  to authenticated, service_role;

create or replace function public.get_business_member_detail(
  member_id uuid,
  from_date date default current_date - 90,
  to_date date default current_date
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select private.get_business_member_detail(member_id, from_date, to_date);
$$;

revoke all on function public.get_business_member_detail(uuid, date, date) from public;
revoke all on function public.get_business_member_detail(uuid, date, date) from anon;
grant execute on function public.get_business_member_detail(uuid, date, date) to authenticated;
grant execute on function public.get_business_member_detail(uuid, date, date) to service_role;

create or replace function private.send_business_session_feedback(
  p_session_id uuid,
  p_text text,
  p_request_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_target_user uuid;
  v_feedback public.session_feedback%rowtype;
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if nullif(btrim(p_text), '') is null or char_length(btrim(p_text)) > 2000 then
    raise exception 'Feedback must be between 1 and 2000 characters' using errcode = '22023';
  end if;

  select s.user_id into v_target_user
  from public.workout_sessions s
  where s.id = p_session_id
  for share;

  if not found
    or v_target_user = v_user_id
    or not private.can_read_member_workout(v_target_user)
    or not private.has_active_member_business_relationship(v_target_user)
  then
    raise exception 'Session feedback access denied' using errcode = '42501';
  end if;

  if p_request_id is null then
    insert into public.session_feedback(
      session_id,
      trainer_id,
      text,
      request_id
    ) values (
      p_session_id,
      v_user_id,
      btrim(p_text),
      null
    ) returning * into v_feedback;
  else
    insert into public.session_feedback(
      session_id,
      trainer_id,
      text,
      request_id
    ) values (
      p_session_id,
      v_user_id,
      btrim(p_text),
      p_request_id
    )
    on conflict (trainer_id, request_id)
      where request_id is not null
    do nothing
    returning * into v_feedback;

    if not found then
      select sf.* into v_feedback
      from public.session_feedback sf
      where sf.trainer_id = v_user_id
        and sf.request_id = p_request_id;
      if not found then
        raise exception 'Feedback idempotency lookup failed'
          using errcode = '40001';
      end if;
      if v_feedback.session_id <> p_session_id
        or v_feedback.text <> btrim(p_text)
      then
        raise exception 'request_id was already used for different feedback'
          using errcode = '22023';
      end if;
    end if;
  end if;

  return to_jsonb(v_feedback);
end;
$$;

revoke all on function private.send_business_session_feedback(uuid, text, uuid) from public;
revoke all on function private.send_business_session_feedback(uuid, text, uuid) from anon;
revoke all on function private.send_business_session_feedback(uuid, text, uuid) from authenticated;
grant execute on function private.send_business_session_feedback(uuid, text, uuid)
  to authenticated, service_role;

create or replace function public.send_business_session_feedback(
  session_id uuid,
  text text,
  request_id uuid default null
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select private.send_business_session_feedback(session_id, text, request_id);
$$;

revoke all on function public.send_business_session_feedback(uuid, text, uuid) from public;
revoke all on function public.send_business_session_feedback(uuid, text, uuid) from anon;
grant execute on function public.send_business_session_feedback(uuid, text, uuid) to authenticated;
grant execute on function public.send_business_session_feedback(uuid, text, uuid) to service_role;

-- Coaching rows are activated by the payment/service workflow.  A member must
-- never be able to create an active coaching contract by direct REST writes.
drop policy if exists rw_coachings on public.coachings;
drop policy if exists coachings_participant_read on public.coachings;
create policy coachings_participant_read
on public.coachings
for select
to authenticated
using (
  user_id = (select auth.uid())
  or (select owns_trainer(trainer_id))
  or (select is_admin())
);

revoke all on table public.coachings from anon;
revoke all on table public.coachings from authenticated;
grant select on table public.coachings to authenticated;
grant all on table public.coachings to service_role;

-- Members can read schedules addressed to them. Trainers retain management
-- access; gym owners can see schedules created by active trainers at their gym.
drop policy if exists rw_schedules on public.coaching_schedules;
drop policy if exists coaching_schedules_shared_read on public.coaching_schedules;
drop policy if exists coaching_schedules_trainer_insert on public.coaching_schedules;
drop policy if exists coaching_schedules_trainer_update on public.coaching_schedules;
drop policy if exists coaching_schedules_trainer_delete on public.coaching_schedules;

create policy coaching_schedules_shared_read
on public.coaching_schedules
for select
to authenticated
using (
  member_user_id = (select auth.uid())
  or (select owns_trainer(trainer_id))
  or (gym_id is not null and (select owns_gym(gym_id)))
  or (select is_admin())
);

create policy coaching_schedules_trainer_insert
on public.coaching_schedules
for insert
to authenticated
with check (
  (select owns_trainer(trainer_id))
  and (
    (
      gym_id is null
      and (
        member_user_id is null
        or exists (
          select 1
          from public.coachings c
          where c.trainer_id = coaching_schedules.trainer_id
            and c.user_id = coaching_schedules.member_user_id
            and c.status = 'active'
        )
      )
    )
    or (
      gym_id is not null
      and exists (
        select 1
        from public.gym_trainers gt
        where gt.gym_id = coaching_schedules.gym_id
          and gt.trainer_id = coaching_schedules.trainer_id
          and gt.status = 'active'
      )
      and (
        member_user_id is null
        or exists (
          select 1
          from public.members m
          join public.member_assignments ma
            on ma.member_id = m.id
           and ma.active
          where m.gym_id = coaching_schedules.gym_id
            and m.user_id = coaching_schedules.member_user_id
            and ma.trainer_id = coaching_schedules.trainer_id
        )
      )
    )
  )
);

create policy coaching_schedules_trainer_update
on public.coaching_schedules
for update
to authenticated
using ((select owns_trainer(trainer_id)))
with check (
  (select owns_trainer(trainer_id))
  and (
    (
      gym_id is null
      and (
        member_user_id is null
        or exists (
          select 1
          from public.coachings c
          where c.trainer_id = coaching_schedules.trainer_id
            and c.user_id = coaching_schedules.member_user_id
            and c.status = 'active'
        )
      )
    )
    or (
      gym_id is not null
      and exists (
        select 1
        from public.gym_trainers gt
        where gt.gym_id = coaching_schedules.gym_id
          and gt.trainer_id = coaching_schedules.trainer_id
          and gt.status = 'active'
      )
      and (
        member_user_id is null
        or exists (
          select 1
          from public.members m
          join public.member_assignments ma
            on ma.member_id = m.id
           and ma.active
          where m.gym_id = coaching_schedules.gym_id
            and m.user_id = coaching_schedules.member_user_id
            and ma.trainer_id = coaching_schedules.trainer_id
        )
      )
    )
  )
);

create policy coaching_schedules_trainer_delete
on public.coaching_schedules
for delete
to authenticated
using ((select owns_trainer(trainer_id)));

revoke all on table public.coaching_schedules from anon;
revoke all on table public.coaching_schedules from authenticated;
grant select, insert, update, delete on table public.coaching_schedules to authenticated;
grant all on table public.coaching_schedules to service_role;

-- Consent rows are private account settings. Remove legacy table-wide grants
-- such as TRUNCATE/REFERENCES and expose only the fields the member controls.
revoke all on table public.user_consents from anon;
revoke all on table public.user_consents from authenticated;
grant select (
  user_id,
  share_body_data,
  share_workout_records,
  marketing,
  updated_at
) on public.user_consents to authenticated;
grant update (
  share_body_data,
  share_workout_records,
  marketing,
  updated_at
) on public.user_consents to authenticated;
grant all on table public.user_consents to service_role;
