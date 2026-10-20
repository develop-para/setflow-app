begin;

-- A client is a trainer-owned space, independent from paid classes, gym
-- membership and the trainer's personal snapshot. Phone/name never grant
-- access to an app account. Only a member accepting a private token does.
create table public.trainer_clients (
  id uuid primary key default gen_random_uuid(),
  trainer_id uuid not null references public.trainers(id) on delete cascade,
  name text not null check (char_length(btrim(name)) between 1 and 80),
  phone text not null default '' check (char_length(phone) <= 30),
  notes text not null default '' check (char_length(notes) <= 10000),
  member_user_id uuid references public.users(id) on delete set null,
  member_bound_at timestamptz,
  member_consented_at timestamptz,
  member_revoked_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (member_user_id is null or member_bound_at is not null),
  check (member_consented_at is null or member_user_id is not null)
);
create index trainer_clients_trainer on public.trainer_clients(trainer_id,created_at desc);
create index trainer_clients_member on public.trainer_clients(member_user_id) where member_user_id is not null;

create table public.trainer_client_workouts (
  id uuid primary key,
  client_id uuid not null references public.trainer_clients(id) on delete cascade,
  workout_date date not null,
  session jsonb not null,
  notes text not null default '' check (char_length(notes) <= 10000),
  version integer not null default 1 check (version > 0),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique(client_id,workout_date)
);
create table public.trainer_client_invitations (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.trainer_clients(id) on delete cascade,
  token_hash text not null unique,
  expires_at timestamptz not null,
  accepted_by uuid references public.users(id) on delete set null,
  accepted_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz not null default clock_timestamp()
);
create index trainer_client_invitations_client on public.trainer_client_invitations(client_id);
create table public.trainer_client_requests (
  actor_user_id uuid not null references public.users(id) on delete cascade,
  request_id uuid not null,
  operation text not null,
  input jsonb not null,
  result jsonb not null,
  created_at timestamptz not null default clock_timestamp(),
  primary key(actor_user_id,request_id)
);
alter table public.trainer_clients enable row level security;
alter table public.trainer_client_workouts enable row level security;
alter table public.trainer_client_invitations enable row level security;
alter table public.trainer_client_requests enable row level security;
revoke all on public.trainer_clients,public.trainer_client_workouts,
  public.trainer_client_invitations,public.trainer_client_requests from public,anon,authenticated;
grant all on public.trainer_clients,public.trainer_client_workouts,
  public.trainer_client_invitations,public.trainer_client_requests to service_role;

-- Account purges must not be blocked by the trainer's independent records.
-- SET NULL removes account identity and this trigger ends sharing, while an
-- immutable binding marker prevents the old space being claimed by anyone.
create or replace function private.preserve_trainer_client_binding()
returns trigger language plpgsql set search_path = '' as $$
begin
  if old.member_bound_at is not null then
    new.member_bound_at := old.member_bound_at;
    if new.member_user_id is distinct from old.member_user_id then
      if new.member_user_id is not null then
        raise exception 'A previously bound client cannot be reassigned' using errcode = '42501'; end if;
      new.member_consented_at := null;
      new.member_revoked_at := clock_timestamp();
      new.updated_at := clock_timestamp();
    end if;
  end if;
  return new;
end;
$$;
create trigger preserve_trainer_client_binding before update on public.trainer_clients
  for each row execute function private.preserve_trainer_client_binding();

-- The actor's account FK is inserted when remembering the result. Lock it
-- before any trainer/client row so an account purge cannot hold that FK and
-- wait for a client already locked by this same mutation.
create or replace function private.lock_trainer_client_actor()
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform 1 from public.users where id = (select auth.uid()) for key share;
  if not found then raise exception 'Active account required' using errcode = '42501'; end if;
end;
$$;

create or replace function private.require_client_trainer()
returns uuid language plpgsql stable security definer set search_path = '' as $$
declare v_id uuid;
begin
  select id into v_id from public.trainers where user_id = (select auth.uid()) and status = 'approved';
  if v_id is null then raise exception 'Approved trainer required' using errcode = '42501'; end if;
  return v_id;
end;
$$;

-- Trainer writes and member acceptance finish before a concurrent approval
-- revocation can commit, or observe that revocation and fail. Always acquire
-- this lock before actor/request and client locks, never in the reverse order.
create or replace function private.lock_approved_client_trainer(p_trainer uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform 1 from public.trainers where id = p_trainer and status = 'approved' for share;
  if not found then raise exception 'Approved trainer required' using errcode = '42501'; end if;
end;
$$;

-- Serialize retries by actor/request and reject reusing an id for new input.
-- The caller must authorize the resource before replaying a saved response.
create or replace function private.previous_trainer_client_request(p_request uuid,p_operation text,p_input jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare r public.trainer_client_requests%rowtype;
begin
  if (select auth.uid()) is null then raise exception 'Sign in required' using errcode = '42501'; end if;
  if p_request is null then raise exception 'Request id required' using errcode = '22023'; end if;
  perform pg_advisory_xact_lock(hashtextextended('trainer-client-request:' || (select auth.uid())::text || ':' || p_request::text,0));
  select * into r from public.trainer_client_requests where actor_user_id = (select auth.uid()) and request_id = p_request;
  if found then
    if r.operation is distinct from p_operation or r.input is distinct from p_input then
      raise exception 'Request id is bound to another operation' using errcode = '22023';
    end if;
    return r.result;
  end if;
  return null;
end;
$$;
create or replace function private.remember_trainer_client_request(p_request uuid,p_operation text,p_input jsonb,p_result jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  insert into public.trainer_client_requests(actor_user_id,request_id,operation,input,result)
    values((select auth.uid()),p_request,p_operation,p_input,p_result);
  return p_result;
end;
$$;
create or replace function private.trainer_client_json(p_client public.trainer_clients)
returns jsonb language sql stable security invoker set search_path = '' as $$
  select jsonb_build_object('id',p_client.id,'name',p_client.name,'phone',p_client.phone,
    'notes',p_client.notes,'member_user_id',case when p_client.member_consented_at is not null then p_client.member_user_id end,
    'can_connect',not (p_client.member_bound_at is not null and p_client.member_user_id is null));
$$;
create or replace function private.trainer_client_workout_json(p_workout public.trainer_client_workouts,p_edit boolean)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id',p_workout.id,'client_id',p_workout.client_id,'session',p_workout.session,
    'notes',p_workout.notes,'version',p_workout.version,'source','trainer','author_name',t.display_name,'can_edit',p_edit)
  from public.trainer_clients c join public.trainers t on t.id = c.trainer_id where c.id = p_workout.client_id;
$$;

create or replace function private.list_trainer_clients()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_trainer uuid := private.require_client_trainer();
begin
  return (select coalesce(jsonb_agg(private.trainer_client_json(c) order by c.created_at desc),'[]'::jsonb)
    from public.trainer_clients c where c.trainer_id = v_trainer);
end;
$$;

create or replace function private.create_trainer_client(p_name text,p_phone text,p_notes text,p_request uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_trainer uuid := private.require_client_trainer(); c public.trainer_clients%rowtype;
  v_input jsonb := jsonb_build_object('name',p_name,'phone',p_phone,'notes',p_notes); v_result jsonb;
begin
  perform private.lock_trainer_client_actor();
  perform private.lock_approved_client_trainer(v_trainer);
  v_result := private.previous_trainer_client_request(p_request,'create_client',v_input);
  if v_result is not null then return v_result; end if;
  if p_name is null or char_length(btrim(p_name)) not between 1 and 80 or p_phone is null
    or char_length(p_phone) > 30 or p_notes is null or char_length(p_notes) > 10000 then
    raise exception 'Invalid client name, phone or notes' using errcode = '22023'; end if;
  insert into public.trainer_clients(trainer_id,name,phone,notes)
    values(v_trainer,btrim(p_name),btrim(p_phone),p_notes) returning * into c;
  return private.remember_trainer_client_request(p_request,'create_client',v_input,private.trainer_client_json(c));
end;
$$;
create or replace function private.update_trainer_client(p_client uuid,p_name text,p_phone text,p_notes text,p_request uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_trainer uuid := private.require_client_trainer(); c public.trainer_clients%rowtype;
  v_input jsonb := jsonb_build_object('client_id',p_client,'name',p_name,'phone',p_phone,'notes',p_notes); v_result jsonb;
begin
  perform private.lock_trainer_client_actor();
  select * into c from public.trainer_clients where id = p_client and trainer_id = v_trainer;
  if c.id is null then raise exception 'Client owner required' using errcode = '42501'; end if;
  perform private.lock_approved_client_trainer(v_trainer);
  v_result := private.previous_trainer_client_request(p_request,'update_client',v_input);
  if v_result is not null then return v_result; end if;
  if p_name is null or char_length(btrim(p_name)) not between 1 and 80 or p_phone is null
    or char_length(p_phone) > 30 or p_notes is null or char_length(p_notes) > 10000 then
    raise exception 'Invalid client name, phone or notes' using errcode = '22023'; end if;
  update public.trainer_clients set name = btrim(p_name),phone = btrim(p_phone),notes = p_notes,updated_at = clock_timestamp()
    where id = p_client returning * into c;
  return private.remember_trainer_client_request(p_request,'update_client',v_input,private.trainer_client_json(c));
end;
$$;

create or replace function private.save_trainer_client_workout(
  p_client uuid,p_session jsonb,p_notes text,p_request uuid,p_workout uuid,p_version integer)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_trainer uuid := private.require_client_trainer(); c public.trainer_clients%rowtype;
  w public.trainer_client_workouts%rowtype; v_date date; v_session jsonb; v_result jsonb;
  v_input jsonb := jsonb_build_object('client_id',p_client,'session',p_session,'notes',p_notes,'workout_id',p_workout,'expected_version',p_version);
begin
  perform private.lock_trainer_client_actor();
  select * into c from public.trainer_clients where id = p_client and trainer_id = v_trainer;
  if c.id is null then raise exception 'Client owner required' using errcode = '42501'; end if;
  perform private.lock_approved_client_trainer(v_trainer);
  v_result := private.previous_trainer_client_request(p_request,'save_workout',v_input);
  if v_result is not null then return v_result; end if;
  if p_workout is null or p_version is null or p_version < 0 or p_notes is null or char_length(p_notes) > 10000 then
    raise exception 'Workout id, version and notes required' using errcode = '22023'; end if;
  v_date := (left(p_session ->> 'date',10))::date;
  if v_date is null then raise exception 'Workout date required' using errcode = '22023'; end if;
  v_session := private.validate_coaching_workout_session(p_session,v_date);
  -- Also serialize first creation on the client/day to stop duplicate records
  -- from two devices before either receives its first server version.
  perform pg_advisory_xact_lock(hashtextextended('trainer-client-day:' || p_client::text || ':' || v_date::text,0));
  select * into w from public.trainer_client_workouts where id = p_workout for update;
  if w.id is null then
    if p_version <> 0 or exists(select 1 from public.trainer_client_workouts where client_id = p_client and workout_date = v_date) then
      raise exception 'Workout changed; reload before saving' using errcode = 'PT409'; end if;
    insert into public.trainer_client_workouts(id,client_id,workout_date,session,notes)
      values(p_workout,p_client,v_date,v_session,p_notes) returning * into w;
  else
    if w.client_id <> p_client then raise exception 'Workout owner required' using errcode = '42501'; end if;
    if w.version <> p_version then raise exception 'Workout changed; reload before saving' using errcode = 'PT409'; end if;
    if w.workout_date <> v_date then raise exception 'Workout date cannot change' using errcode = '22023'; end if;
    update public.trainer_client_workouts set session = v_session,notes = p_notes,version = version + 1,updated_at = clock_timestamp()
      where id = p_workout returning * into w;
  end if;
  return private.remember_trainer_client_request(p_request,'save_workout',v_input,private.trainer_client_workout_json(w,true));
end;
$$;

create or replace function private.list_trainer_client_workouts(p_client uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_trainer uuid := private.require_client_trainer(); c public.trainer_clients%rowtype; v_result jsonb;
begin
  select * into c from public.trainer_clients where id = p_client and trainer_id = v_trainer;
  if c.id is null then raise exception 'Client owner required' using errcode = '42501'; end if;
  with records as (
    select w.workout_date::text as day,w.id::text as key,private.trainer_client_workout_json(w,true) as record
      from public.trainer_client_workouts w where w.client_id = c.id
    union all
    -- A member's own history is read-only, and only explicit, unrevoked token
    -- acceptance grants access. A paid coaching or center is not required.
    select left(s ->> 'date',10),'personal:' || left(s ->> 'date',10),jsonb_build_object(
      'id','personal:' || left(s ->> 'date',10),'client_id',c.id,'session',s || jsonb_build_object('exercises',
        (select coalesce(jsonb_agg(e || case when e ? 'template' then '{}'::jsonb else
          coalesce((select jsonb_build_object('template',custom) from jsonb_array_elements(coalesce(a.payload -> 'customExercises','[]'::jsonb)) custom
            where custom ->> 'id' = e ->> 'templateId' limit 1),'{}'::jsonb) end),'[]'::jsonb)
         from jsonb_array_elements(coalesce(s -> 'exercises','[]'::jsonb)) e)),
      'notes','','version',0,'source','member','author_name',coalesce(u.nickname,'회원'),'can_edit',false)
      from public.app_state_snapshots a join public.users u on u.id = a.user_id,
        lateral jsonb_array_elements(coalesce(a.payload -> 'sessions','[]'::jsonb)) s
      where a.user_id = c.member_user_id and c.member_consented_at is not null
  ) select coalesce(jsonb_agg(record order by day desc,key),'[]'::jsonb) into v_result from records;
  return v_result;
end;
$$;

create or replace function private.create_trainer_client_invitation(p_client uuid,p_expires timestamptz,p_request uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_trainer uuid := private.require_client_trainer(); c public.trainer_clients%rowtype; v_token text; v_result jsonb;
  v_input jsonb := jsonb_build_object('client_id',p_client,'expires_at',p_expires);
begin
  perform private.lock_trainer_client_actor();
  select * into c from public.trainer_clients where id = p_client and trainer_id = v_trainer;
  if c.id is null then raise exception 'Client owner required' using errcode = '42501'; end if;
  perform private.lock_approved_client_trainer(v_trainer);
  v_result := private.previous_trainer_client_request(p_request,'create_invitation',v_input);
  select * into c from public.trainer_clients where id = p_client for update;
  if c.member_bound_at is not null and c.member_user_id is null then
    raise exception 'Original member account was deleted; create a new client space' using errcode = 'PT410'; end if;
  if v_result is not null then
    if not exists(select 1 from public.trainer_client_invitations where client_id = p_client
      and token_hash = encode(sha256(convert_to(v_result ->> 'token','UTF8')),'hex')
      and accepted_at is null and revoked_at is null and expires_at > clock_timestamp()) then
      raise exception 'Invitation no longer available; create a new invitation' using errcode = 'PT410';
    end if;
    return v_result;
  end if;
  if p_expires is null or p_expires <= clock_timestamp() or p_expires > clock_timestamp() + interval '7 days' then
    raise exception 'Invitation expiry must be within seven days' using errcode = '22023'; end if;
  update public.trainer_client_invitations set revoked_at = clock_timestamp()
    where client_id = p_client and accepted_at is null and revoked_at is null;
  v_token := replace(gen_random_uuid()::text,'-','') || replace(gen_random_uuid()::text,'-','');
  insert into public.trainer_client_invitations(client_id,token_hash,expires_at)
    values(p_client,encode(sha256(convert_to(v_token,'UTF8')),'hex'),p_expires);
  v_result := jsonb_build_object('client_id',p_client,'token',v_token,'expires_at',p_expires);
  return private.remember_trainer_client_request(p_request,'create_invitation',v_input,v_result);
end;
$$;

create or replace function private.accept_trainer_client_invitation(p_token text,p_request uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare i public.trainer_client_invitations%rowtype; c public.trainer_clients%rowtype; v_uid uuid := (select auth.uid());
  v_result jsonb; v_input jsonb := jsonb_build_object('token',p_token);
begin
  if v_uid is null then raise exception 'Sign in required' using errcode = '42501'; end if;
  perform private.lock_trainer_client_actor();
  if p_token is null or char_length(p_token) <> 64 then raise exception 'Invalid invitation' using errcode = '42501'; end if;
  select * into i from public.trainer_client_invitations where token_hash = encode(sha256(convert_to(p_token,'UTF8')),'hex');
  if i.id is null then raise exception 'Invalid invitation' using errcode = '42501'; end if;
  select * into c from public.trainer_clients where id = i.client_id;
  if not exists(select 1 from public.trainers where id = c.trainer_id and status = 'approved' and user_id <> v_uid)
    or (c.member_bound_at is not null and c.member_user_id is null)
    or (c.member_user_id is not null and c.member_user_id <> v_uid) then
    raise exception 'Invitation cannot be accepted by this account' using errcode = '42501'; end if;
  perform private.lock_approved_client_trainer(c.trainer_id);
  v_result := private.previous_trainer_client_request(p_request,'accept_invitation',v_input);
  -- After the trainer, writes lock actor/request -> client -> invitation. Recheck the grant
  -- after waiting so revocation or another acceptance cannot be bypassed.
  select * into c from public.trainer_clients where id = i.client_id for update;
  select * into i from public.trainer_client_invitations where id = i.id for update;
  if not exists(select 1 from public.trainers where id = c.trainer_id and status = 'approved' and user_id <> v_uid)
    or (c.member_bound_at is not null and c.member_user_id is null)
    or (c.member_user_id is not null and c.member_user_id <> v_uid) then
    raise exception 'Invitation cannot be accepted by this account' using errcode = '42501'; end if;
  if v_result is not null then
    if c.member_consented_at is null or c.member_user_id is distinct from v_uid or i.accepted_by is distinct from v_uid then
      raise exception 'Sharing was revoked; accept a new invitation' using errcode = 'PT410'; end if;
    return v_result;
  end if;
  if i.accepted_at is not null or i.revoked_at is not null or i.expires_at <= clock_timestamp() then
    raise exception 'Invitation expired or already used' using errcode = '42501'; end if;
  update public.trainer_client_invitations set accepted_by = v_uid,accepted_at = clock_timestamp() where id = i.id;
  update public.trainer_clients set member_user_id = v_uid,member_bound_at = coalesce(member_bound_at,clock_timestamp()),
    member_consented_at = clock_timestamp(),member_revoked_at = null,
    updated_at = clock_timestamp() where id = c.id;
  return private.remember_trainer_client_request(p_request,'accept_invitation',v_input,jsonb_build_object('accepted',true));
end;
$$;

create or replace function private.list_my_trainer_client_workouts()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if (select auth.uid()) is null then raise exception 'Sign in required' using errcode = '42501'; end if;
  -- Preserve the member's access to their coach-authored historical records
  -- after sharing ends. Trainer-only client notes/phone are never returned.
  return (select coalesce(jsonb_agg(private.trainer_client_workout_json(w,false) order by w.workout_date desc,w.id),'[]'::jsonb)
    from public.trainer_client_workouts w join public.trainer_clients c on c.id = w.client_id
    where c.member_user_id = (select auth.uid()));
end;
$$;
create or replace function private.end_my_trainer_client_link(p_client uuid,p_request uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare c public.trainer_clients%rowtype; v_input jsonb := jsonb_build_object('client_id',p_client); v_result jsonb;
begin
  perform private.lock_trainer_client_actor();
  select * into c from public.trainer_clients where id = p_client and member_user_id = (select auth.uid());
  if c.id is null then raise exception 'Linked member required' using errcode = '42501'; end if;
  v_result := private.previous_trainer_client_request(p_request,'end_link',v_input);
  select * into c from public.trainer_clients where id = p_client and member_user_id = (select auth.uid()) for update;
  if c.id is null then raise exception 'Linked member required' using errcode = '42501'; end if;
  if v_result is not null then
    if c.member_consented_at is not null then
      raise exception 'Sharing was enabled again; disconnect with a new request' using errcode = 'PT410'; end if;
    return v_result;
  end if;
  update public.trainer_clients set member_consented_at = null,member_revoked_at = clock_timestamp(),updated_at = clock_timestamp() where id = c.id;
  update public.trainer_client_invitations set revoked_at = clock_timestamp()
    where client_id = c.id and accepted_at is null and revoked_at is null;
  -- Keep immutable member identity to prevent relinking old records to a
  -- different person. A new person must receive a new independent space.
  return private.remember_trainer_client_request(p_request,'end_link',v_input,jsonb_build_object('ended',true));
end;
$$;

create or replace function private.list_my_trainer_client_links()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if (select auth.uid()) is null then raise exception 'Sign in required' using errcode = '42501'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('client_id',c.id,'trainer_name',t.display_name,
    'client_name',c.name,'is_sharing',c.member_consented_at is not null) order by c.created_at desc),'[]'::jsonb)
    from public.trainer_clients c join public.trainers t on t.id = c.trainer_id
    where c.member_user_id = (select auth.uid()));
end;
$$;

create or replace function public.list_trainer_clients()
returns jsonb language sql security invoker set search_path = '' as $$ select private.list_trainer_clients(); $$;
create or replace function public.create_trainer_client(name text,phone text,notes text,request_id uuid)
returns jsonb language sql security invoker set search_path = '' as $$ select private.create_trainer_client($1,$2,$3,$4); $$;
create or replace function public.update_trainer_client(client_id uuid,name text,phone text,notes text,request_id uuid)
returns jsonb language sql security invoker set search_path = '' as $$ select private.update_trainer_client($1,$2,$3,$4,$5); $$;
create or replace function public.save_trainer_client_workout(client_id uuid,session jsonb,notes text,request_id uuid,workout_id uuid,expected_version integer)
returns jsonb language sql security invoker set search_path = '' as $$ select private.save_trainer_client_workout($1,$2,$3,$4,$5,$6); $$;
create or replace function public.list_trainer_client_workouts(client_id uuid)
returns jsonb language sql security invoker set search_path = '' as $$ select private.list_trainer_client_workouts($1); $$;
create or replace function public.create_trainer_client_invitation(client_id uuid,expires_at timestamptz,request_id uuid)
returns jsonb language sql security invoker set search_path = '' as $$ select private.create_trainer_client_invitation($1,$2,$3); $$;
create or replace function public.accept_trainer_client_invitation(token text,request_id uuid)
returns jsonb language sql security invoker set search_path = '' as $$ select private.accept_trainer_client_invitation($1,$2); $$;
create or replace function public.list_my_trainer_client_workouts()
returns jsonb language sql security invoker set search_path = '' as $$ select private.list_my_trainer_client_workouts(); $$;
create or replace function public.end_my_trainer_client_link(client_id uuid,request_id uuid)
returns jsonb language sql security invoker set search_path = '' as $$ select private.end_my_trainer_client_link($1,$2); $$;
create or replace function public.list_my_trainer_client_links()
returns jsonb language sql security invoker set search_path = '' as $$ select private.list_my_trainer_client_links(); $$;

do $$
declare f record;
begin
  for f in select p.oid::regprocedure as signature,n.nspname,p.proname
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public','private') and p.proname in (
      'preserve_trainer_client_binding','lock_trainer_client_actor','require_client_trainer','lock_approved_client_trainer','previous_trainer_client_request','remember_trainer_client_request','trainer_client_json','trainer_client_workout_json',
      'list_trainer_clients','create_trainer_client','update_trainer_client','save_trainer_client_workout','list_trainer_client_workouts',
      'create_trainer_client_invitation','accept_trainer_client_invitation','list_my_trainer_client_workouts','end_my_trainer_client_link','list_my_trainer_client_links')
  loop
    execute format('revoke all on function %s from public,anon,authenticated',f.signature);
    if f.proname in ('list_trainer_clients','create_trainer_client','update_trainer_client','save_trainer_client_workout','list_trainer_client_workouts',
      'create_trainer_client_invitation','accept_trainer_client_invitation','list_my_trainer_client_workouts','end_my_trainer_client_link','list_my_trainer_client_links') then
      execute format('grant execute on function %s to authenticated,service_role',f.signature);
    end if;
  end loop;
end;
$$;

commit;
