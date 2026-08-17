-- Checked, retry-safe handoff from a verified gym owner to an active,
-- approved trainer at that same gym.

create table if not exists private.consultation_assignment_requests (
  request_id uuid primary key,
  consultation_id uuid not null
    references public.consultations(id) on delete cascade,
  gym_id uuid not null references public.gyms(id) on delete cascade,
  trainer_id uuid not null references public.trainers(id) on delete cascade,
  assigned_by_user_id uuid not null references public.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

alter table private.consultation_assignment_requests enable row level security;

create index if not exists consultation_assignment_requests_consultation_idx
  on private.consultation_assignment_requests (consultation_id, created_at desc);
create index if not exists consultation_assignment_requests_gym_idx
  on private.consultation_assignment_requests (gym_id);
create index if not exists consultation_assignment_requests_trainer_idx
  on private.consultation_assignment_requests (trainer_id);
create index if not exists consultation_assignment_requests_actor_idx
  on private.consultation_assignment_requests (assigned_by_user_id);

revoke all on table private.consultation_assignment_requests
  from public, anon, authenticated;
grant all on table private.consultation_assignment_requests to service_role;

create or replace function private.can_access_business_consultation(
  p_consultation_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
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
            where t.id = coalesce(c.assigned_trainer_id, c.trainer_id)
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
$function$;

revoke all on function private.can_access_business_consultation(uuid)
  from public, anon;
grant execute on function private.can_access_business_consultation(uuid)
  to authenticated, service_role;

revoke update, delete on table public.consultations from authenticated;

create or replace function private.assign_business_consultation(
  p_request_id uuid,
  p_consultation_id uuid,
  p_gym_id uuid,
  p_trainer_id uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := auth.uid();
  v_status text;
  v_existing private.consultation_assignment_requests%rowtype;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;
  if p_request_id is null
     or p_consultation_id is null
     or p_gym_id is null
     or p_trainer_id is null then
    raise exception using errcode = '22023', message = 'Exact assignment UUIDs are required';
  end if;
  if not exists (
    select 1
    from public.gyms g
    where g.id = p_gym_id
      and g.owner_user_id = v_user_id
      and g.status = 'verified'
  ) then
    raise exception using errcode = '42501', message = 'A verified owned gym is required';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'consultation_assignment:' || p_request_id::text,
      0
    )
  );

  select r.*
    into v_existing
  from private.consultation_assignment_requests r
  where r.request_id = p_request_id;
  if found then
    if v_existing.consultation_id <> p_consultation_id
       or v_existing.gym_id <> p_gym_id
       or v_existing.trainer_id <> p_trainer_id
       or v_existing.assigned_by_user_id <> v_user_id then
      raise exception using errcode = '22023', message = 'An assignment request ID cannot be reused with different data';
    end if;
    select c.status
      into v_status
    from public.consultations c
    where c.id = v_existing.consultation_id;
    return jsonb_build_object(
      'consultation_id', v_existing.consultation_id,
      'gym_id', v_existing.gym_id,
      'trainer_id', v_existing.trainer_id,
      'status', v_status,
      'replayed', true
    );
  end if;

  select c.status
    into v_status
  from public.consultations c
  where c.id = p_consultation_id
    and c.gym_id = p_gym_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Gym consultation not found';
  end if;
  if v_status not in ('pending', 'assigned') then
    raise exception using errcode = '23514', message = 'Only an unanswered consultation can be assigned';
  end if;
  if not exists (
    select 1
    from public.gym_trainers gt
    join public.trainers t
      on t.id = gt.trainer_id
     and t.user_id = gt.trainer_user_id
     and t.status = 'approved'
    where gt.gym_id = p_gym_id
      and gt.trainer_id = p_trainer_id
      and gt.status = 'active'
  ) then
    raise exception using errcode = '42501', message = 'An active approved trainer at this gym is required';
  end if;

  update public.consultations
  set assigned_trainer_id = p_trainer_id,
      status = 'assigned',
      is_read = true
  where id = p_consultation_id;

  insert into private.consultation_assignment_requests (
    request_id,
    consultation_id,
    gym_id,
    trainer_id,
    assigned_by_user_id
  ) values (
    p_request_id,
    p_consultation_id,
    p_gym_id,
    p_trainer_id,
    v_user_id
  );

  return jsonb_build_object(
    'consultation_id', p_consultation_id,
    'gym_id', p_gym_id,
    'trainer_id', p_trainer_id,
    'status', 'assigned',
    'replayed', false
  );
end
$function$;

create or replace function public.assign_business_consultation(
  request_id uuid,
  consultation_id uuid,
  gym_id uuid,
  trainer_id uuid
)
returns jsonb
language sql
volatile
security invoker
set search_path = ''
as $function$
  select private.assign_business_consultation($1, $2, $3, $4);
$function$;

revoke all on function private.assign_business_consultation(
  uuid, uuid, uuid, uuid
) from public, anon;
grant execute on function private.assign_business_consultation(
  uuid, uuid, uuid, uuid
) to authenticated, service_role;
revoke all on function public.assign_business_consultation(
  uuid, uuid, uuid, uuid
) from public, anon;
grant execute on function public.assign_business_consultation(
  uuid, uuid, uuid, uuid
) to authenticated, service_role;

-- Keep replies separate from assignment, but tighten the old reply RPC so a
-- suspended trainer or unverified gym cannot answer through SECURITY DEFINER.
create or replace function private.reply_business_consultation(
  p_consultation_id uuid,
  p_text text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := auth.uid();
  v_text text := nullif(btrim(p_text), '');
  v_trainer_id uuid;
  v_assigned_trainer_id uuid;
  v_gym_id uuid;
  v_is_trainer boolean;
  v_is_gym boolean;
  v_sender_type text;
  v_message_id uuid;
  v_created_at timestamptz;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;
  if v_text is null or char_length(v_text) > 5000 then
    raise exception using errcode = '22023', message = 'Reply text must be between 1 and 5000 characters';
  end if;

  select c.trainer_id, c.assigned_trainer_id, c.gym_id
    into v_trainer_id, v_assigned_trainer_id, v_gym_id
  from public.consultations c
  where c.id = p_consultation_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Consultation not found';
  end if;

  select exists (
    select 1
    from public.trainers t
    where t.id = coalesce(v_assigned_trainer_id, v_trainer_id)
      and t.user_id = v_user_id
      and t.status = 'approved'
      and (
        v_gym_id is null
        or exists (
          select 1
          from public.gym_trainers gt
          join public.gyms g
            on g.id = gt.gym_id
           and g.status = 'verified'
          where gt.gym_id = v_gym_id
            and gt.trainer_id = t.id
            and gt.trainer_user_id = v_user_id
            and gt.status = 'active'
        )
      )
  ) into v_is_trainer;
  select exists (
    select 1
    from public.gyms g
    where g.id = v_gym_id
      and g.owner_user_id = v_user_id
      and g.status = 'verified'
  ) into v_is_gym;

  if not (v_is_trainer or v_is_gym) then
    raise exception using errcode = '42501', message = 'Verified business participant access required';
  end if;

  v_sender_type := case
    when v_is_trainer then 'trainer'
    when v_is_gym then 'gym'
    when v_gym_id is not null then 'gym'
    else 'trainer'
  end;

  insert into public.consultation_messages (
    consultation_id, sender_type, sender_id, text, created_at
  ) values (
    p_consultation_id, v_sender_type, v_user_id, v_text, now()
  )
  returning id, created_at into v_message_id, v_created_at;

  update public.consultations
  set status = 'replied',
      is_read = true
  where id = p_consultation_id;

  return jsonb_build_object(
    'message_id', v_message_id,
    'consultation_id', p_consultation_id,
    'status', 'replied',
    'sender_type', v_sender_type,
    'created_at', v_created_at
  );
end
$function$;
