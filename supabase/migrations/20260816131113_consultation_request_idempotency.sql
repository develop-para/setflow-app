-- Recover consultation creates and business replies after a committed RPC
-- response is lost. Request UUIDs are retained on the authoritative rows as
-- an immutable audit/idempotency key.

alter table public.consultations
  add column if not exists request_id uuid;
alter table public.consultation_messages
  add column if not exists request_id uuid;

create unique index if not exists consultations_user_request_uidx
  on public.consultations (user_id, request_id)
  where request_id is not null;
create unique index if not exists consultation_messages_sender_request_uidx
  on public.consultation_messages (sender_id, request_id)
  where request_id is not null;

comment on column public.consultations.request_id is
  'Stable member request UUID for idempotent consultation creation.';
comment on column public.consultation_messages.request_id is
  'Stable business participant request UUID for idempotent replies.';

create or replace function private.create_business_consultation(
  p_request_id uuid,
  p_trainer_id uuid,
  p_gym_id uuid,
  p_routine_id uuid,
  p_specialty text,
  p_goal text,
  p_level text,
  p_question text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := auth.uid();
  v_specialty text := nullif(btrim(p_specialty), '');
  v_goal text := nullif(btrim(p_goal), '');
  v_level text := nullif(btrim(p_level), '');
  v_question text := nullif(btrim(p_question), '');
  v_existing public.consultations%rowtype;
  v_consultation_id uuid;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;
  if p_request_id is null then
    raise exception using errcode = '22023', message = 'A request ID is required';
  end if;
  if num_nonnulls(p_trainer_id, p_gym_id) <> 1 then
    raise exception using errcode = '22023', message = 'Exactly one trainer or gym target is required';
  end if;
  if v_question is null or char_length(v_question) > 5000
     or char_length(coalesce(v_specialty, '')) > 200
     or char_length(coalesce(v_goal, '')) > 200
     or char_length(coalesce(v_level, '')) > 100 then
    raise exception using errcode = '22023', message = 'Consultation text is invalid';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'consultation_create:' || v_user_id::text || ':' || p_request_id::text,
      0
    )
  );

  select c.*
    into v_existing
  from public.consultations c
  where c.user_id = v_user_id
    and c.request_id = p_request_id
  for update;
  if found then
    if v_existing.trainer_id is distinct from p_trainer_id
       or v_existing.gym_id is distinct from p_gym_id
       or v_existing.routine_id is distinct from p_routine_id
       or v_existing.specialty is distinct from v_specialty
       or v_existing.goal is distinct from v_goal
       or v_existing.level is distinct from v_level
       or v_existing.question is distinct from v_question then
      raise exception using errcode = '22023', message = 'A consultation request ID cannot be reused with different data';
    end if;
    return jsonb_build_object(
      'consultation_id', v_existing.id,
      'status', v_existing.status,
      'replayed', true
    );
  end if;

  if p_trainer_id is not null and not exists (
    select 1
    from public.trainers t
    where t.id = p_trainer_id
      and t.status = 'approved'
      and t.is_public
  ) then
    raise exception using errcode = '42501', message = 'A public approved trainer is required';
  end if;
  if p_gym_id is not null and not exists (
    select 1
    from public.gyms g
    where g.id = p_gym_id
      and g.status = 'verified'
  ) then
    raise exception using errcode = '42501', message = 'A verified gym is required';
  end if;
  if p_routine_id is not null and not exists (
    select 1
    from public.coaching_routines cr
    where cr.id = p_routine_id
      and cr.status = 'approved'
      and (
        (p_trainer_id is not null and (
          cr.trainer_id = p_trainer_id
          or (cr.trainer_id is null and cr.gym_id is null)
        ))
        or (p_gym_id is not null and (
          cr.gym_id = p_gym_id
          or (cr.trainer_id is null and cr.gym_id is null)
        ))
      )
  ) then
    raise exception using errcode = '42501', message = 'The routine does not belong to the consultation target';
  end if;

  insert into public.consultations (
    request_id,
    user_id,
    trainer_id,
    gym_id,
    routine_id,
    specialty,
    goal,
    level,
    question,
    status,
    is_read,
    assigned_trainer_id
  ) values (
    p_request_id,
    v_user_id,
    p_trainer_id,
    p_gym_id,
    p_routine_id,
    v_specialty,
    v_goal,
    v_level,
    v_question,
    'pending',
    false,
    null
  )
  returning id into v_consultation_id;

  return jsonb_build_object(
    'consultation_id', v_consultation_id,
    'status', 'pending',
    'replayed', false
  );
end
$function$;

create or replace function public.create_business_consultation(
  request_id uuid,
  trainer_id uuid,
  gym_id uuid,
  routine_id uuid,
  specialty text,
  goal text,
  level text,
  question text
)
returns jsonb
language sql
volatile
security invoker
set search_path = ''
as $function$
  select private.create_business_consultation(
    $1, $2, $3, $4, $5, $6, $7, $8
  );
$function$;

-- Idempotent business reply. The authorization matches the immediately prior
-- handoff migration and intentionally excludes admin sender masquerading.
create or replace function private.reply_business_consultation(
  p_request_id uuid,
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
  v_existing public.consultation_messages%rowtype;
  v_trainer_id uuid;
  v_assigned_trainer_id uuid;
  v_gym_id uuid;
  v_status text;
  v_is_trainer boolean;
  v_is_gym boolean;
  v_sender_type text;
  v_message_id uuid;
  v_created_at timestamptz;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;
  if p_request_id is null then
    raise exception using errcode = '22023', message = 'A request ID is required';
  end if;
  if p_consultation_id is null
     or v_text is null
     or char_length(v_text) > 5000 then
    raise exception using errcode = '22023', message = 'Reply input is invalid';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'consultation_reply:' || v_user_id::text || ':' || p_request_id::text,
      0
    )
  );
  select cm.*
    into v_existing
  from public.consultation_messages cm
  where cm.sender_id = v_user_id
    and cm.request_id = p_request_id
  for update;
  if found then
    if v_existing.consultation_id <> p_consultation_id
       or v_existing.text <> v_text then
      raise exception using errcode = '22023', message = 'A reply request ID cannot be reused with different data';
    end if;
    select c.status into v_status
    from public.consultations c
    where c.id = p_consultation_id;
    return jsonb_build_object(
      'message_id', v_existing.id,
      'consultation_id', p_consultation_id,
      'status', v_status,
      'sender_type', v_existing.sender_type,
      'created_at', v_existing.created_at,
      'replayed', true
    );
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

  v_sender_type := case when v_is_trainer then 'trainer' else 'gym' end;
  insert into public.consultation_messages (
    request_id,
    consultation_id,
    sender_type,
    sender_id,
    text,
    created_at
  ) values (
    p_request_id,
    p_consultation_id,
    v_sender_type,
    v_user_id,
    v_text,
    now()
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
    'created_at', v_created_at,
    'replayed', false
  );
end
$function$;

-- Compatibility endpoint for old clients: mandatory request validation makes
-- the previous two-argument call fail instead of creating duplicate replies.
create or replace function private.reply_business_consultation(
  p_consultation_id uuid,
  p_text text
)
returns jsonb
language sql
volatile
security invoker
set search_path = ''
as $function$
  select private.reply_business_consultation(null, $1, $2);
$function$;

create or replace function public.reply_business_consultation(
  request_id uuid,
  consultation_id uuid,
  "text" text
)
returns jsonb
language sql
volatile
security invoker
set search_path = ''
as $function$
  select private.reply_business_consultation($1, $2, $3);
$function$;

revoke all on function private.create_business_consultation(
  uuid, uuid, uuid, uuid, text, text, text, text
) from public, anon;
grant execute on function private.create_business_consultation(
  uuid, uuid, uuid, uuid, text, text, text, text
) to authenticated, service_role;
revoke all on function public.create_business_consultation(
  uuid, uuid, uuid, uuid, text, text, text, text
) from public, anon;
grant execute on function public.create_business_consultation(
  uuid, uuid, uuid, uuid, text, text, text, text
) to authenticated, service_role;

revoke all on function private.reply_business_consultation(uuid, uuid, text)
  from public, anon;
grant execute on function private.reply_business_consultation(uuid, uuid, text)
  to authenticated, service_role;
revoke all on function public.reply_business_consultation(uuid, uuid, text)
  from public, anon;
grant execute on function public.reply_business_consultation(uuid, uuid, text)
  to authenticated, service_role;

-- Consultation creation is now available only through the checked RPC.
revoke insert on table public.consultations from authenticated;
drop policy if exists consultations_requester_insert on public.consultations;
