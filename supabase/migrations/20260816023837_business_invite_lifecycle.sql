-- Token-based invitation lifecycle for gym members and approved trainers.
-- Raw invite tokens are returned only by the first successful create request;
-- only a SHA-256 digest is persisted. All mutations are bounded RPCs.

begin;

create table public.business_invites (
  id uuid primary key default gen_random_uuid(),
  gym_id uuid not null references public.gyms(id) on delete cascade,
  invite_kind text not null,
  member_id uuid references public.members(id) on delete restrict,
  created_by_user_id uuid not null references public.users(id) on delete restrict,
  recipient_name text,
  recipient_phone text,
  role_title text,
  token_hash bytea not null,
  status text not null default 'pending',
  expires_at timestamptz not null,
  accepted_by_user_id uuid references public.users(id) on delete set null,
  accepted_member_id uuid references public.members(id) on delete set null,
  accepted_trainer_id uuid references public.trainers(id) on delete set null,
  accepted_gym_trainer_id uuid references public.gym_trainers(id) on delete set null,
  accepted_at timestamptz,
  revoked_at timestamptz,
  create_request_id uuid not null,
  accepted_request_id uuid,
  revoked_request_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint business_invites_kind_check
    check (invite_kind in ('member', 'trainer')),
  constraint business_invites_status_check
    check (status in ('pending', 'accepted', 'revoked', 'expired')),
  constraint business_invites_expiry_check
    check (expires_at > created_at),
  constraint business_invites_shape_check
    check (
      (invite_kind = 'member' and role_title is null)
      or (invite_kind = 'trainer' and member_id is null and recipient_phone is null)
    ),
  constraint business_invites_acceptance_check
    check (
      status <> 'accepted'
      or (
        accepted_by_user_id is not null
        and accepted_at is not null
        and accepted_request_id is not null
        and (
          (
            invite_kind = 'member'
            and accepted_member_id is not null
            and accepted_trainer_id is null
            and accepted_gym_trainer_id is null
          )
          or (
            invite_kind = 'trainer'
            and accepted_member_id is null
            and accepted_trainer_id is not null
            and accepted_gym_trainer_id is not null
          )
        )
      )
    ),
  constraint business_invites_revocation_check
    check (
      status <> 'revoked'
      or (revoked_at is not null and revoked_request_id is not null)
    )
);

create unique index business_invites_token_hash_uidx
  on public.business_invites (token_hash);
create unique index business_invites_create_request_uidx
  on public.business_invites (created_by_user_id, create_request_id);
create unique index business_invites_accept_request_uidx
  on public.business_invites (accepted_by_user_id, accepted_request_id)
  where accepted_request_id is not null;
create unique index business_invites_revoke_request_uidx
  on public.business_invites (created_by_user_id, revoked_request_id)
  where revoked_request_id is not null;
create index business_invites_gym_status_created_idx
  on public.business_invites (gym_id, status, created_at desc);
create index business_invites_member_id_idx
  on public.business_invites (member_id)
  where member_id is not null;
create index business_invites_accepted_member_id_idx
  on public.business_invites (accepted_member_id)
  where accepted_member_id is not null;
create index business_invites_accepted_trainer_id_idx
  on public.business_invites (accepted_trainer_id)
  where accepted_trainer_id is not null;
create index business_invites_accepted_gym_trainer_id_idx
  on public.business_invites (accepted_gym_trainer_id)
  where accepted_gym_trainer_id is not null;

-- Prevent parallel member invitations from creating duplicate memberships for
-- the same authenticated user at one center.
create unique index if not exists members_one_user_per_gym_uidx
  on public.members (gym_id, user_id)
  where user_id is not null;

alter table public.business_invites enable row level security;

revoke all on table public.business_invites from public, anon, authenticated;
grant select (
  id,
  gym_id,
  invite_kind,
  member_id,
  created_by_user_id,
  recipient_name,
  recipient_phone,
  role_title,
  status,
  expires_at,
  accepted_by_user_id,
  accepted_member_id,
  accepted_trainer_id,
  accepted_gym_trainer_id,
  accepted_at,
  revoked_at,
  created_at,
  updated_at
) on public.business_invites to authenticated;
grant all on table public.business_invites to service_role;

create policy business_invites_participant_read
on public.business_invites
for select
to authenticated
using (
  created_by_user_id = (select auth.uid())
  or accepted_by_user_id = (select auth.uid())
  or (select public.owns_gym(gym_id))
  or (select public.is_admin())
);

-- The legacy trainer_invites table granted full anonymous DML through a
-- PUBLIC policy. It is superseded by business_invites and is now read-only.
drop policy if exists rw_invites on public.trainer_invites;
alter table public.trainer_invites enable row level security;
revoke all on table public.trainer_invites from public, anon, authenticated;
grant select on table public.trainer_invites to authenticated;
grant all on table public.trainer_invites to service_role;

create policy trainer_invites_legacy_read
on public.trainer_invites
for select
to authenticated
using (
  (select public.owns_gym(gym_id))
  or trainer_user_id = (select auth.uid())
  or (select public.is_admin())
);

create or replace function private.business_invite_json(
  p_invite public.business_invites
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $function$
  select to_jsonb(p_invite)
    - array[
      'token_hash',
      'create_request_id',
      'accepted_request_id',
      'revoked_request_id'
    ]::text[];
$function$;

revoke all on function private.business_invite_json(public.business_invites)
  from public, anon, authenticated;
grant execute on function private.business_invite_json(public.business_invites)
  to service_role;

create or replace function private.create_business_invite(
  p_gym_id uuid,
  p_invite_kind text,
  p_request_id uuid,
  p_expires_at timestamptz,
  p_member_id uuid default null,
  p_recipient_name text default null,
  p_recipient_phone text default null,
  p_role_title text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := (select auth.uid());
  v_kind text := lower(btrim(coalesce(p_invite_kind, '')));
  v_name text := nullif(btrim(coalesce(p_recipient_name, '')), '');
  v_phone text := nullif(btrim(coalesce(p_recipient_phone, '')), '');
  v_role_title text := nullif(btrim(coalesce(p_role_title, '')), '');
  v_member public.members%rowtype;
  v_invite public.business_invites%rowtype;
  v_raw_token text;
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if p_request_id is null then
    raise exception 'request_id is required' using errcode = '22023';
  end if;
  if v_kind not in ('member', 'trainer') then
    raise exception 'invite_kind must be member or trainer' using errcode = '22023';
  end if;
  if char_length(coalesce(v_name, '')) > 120
    or char_length(coalesce(v_phone, '')) > 40
    or char_length(coalesce(v_role_title, '')) > 80
  then
    raise exception 'Invite text exceeds its allowed length'
      using errcode = '22023';
  end if;
  if p_expires_at is null
    or p_expires_at < now() + interval '5 minutes'
    or p_expires_at > now() + interval '30 days'
  then
    raise exception 'expires_at must be between 5 minutes and 30 days from now'
      using errcode = '22023';
  end if;

  perform 1
  from public.gyms g
  where g.id = p_gym_id
    and g.owner_user_id = v_user_id
    and g.status = 'verified'
  for share;
  if not found then
    raise exception 'Verified center ownership required' using errcode = '42501';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'business-invite-create:' || v_user_id::text || ':' || p_request_id::text,
      0
    )
  );

  if v_kind = 'member' then
    v_role_title := null;
    if p_member_id is not null then
      select m.* into v_member
      from public.members m
      where m.id = p_member_id
      for update;
      if not found or v_member.gym_id <> p_gym_id then
        raise exception 'Member does not belong to this center'
          using errcode = '23503';
      end if;
      if v_member.user_id is not null then
        raise exception 'Member is already linked to an account'
          using errcode = '23505';
      end if;
      v_name := coalesce(v_name, nullif(btrim(v_member.name), ''));
      v_phone := coalesce(v_phone, nullif(btrim(v_member.phone), ''));
    end if;
    if v_name is null then
      raise exception 'recipient_name is required for member invites'
        using errcode = '22023';
    end if;
  else
    if p_member_id is not null or v_phone is not null then
      raise exception 'Trainer invites cannot include member_id or recipient_phone'
        using errcode = '22023';
    end if;
    if v_role_title is null then
      v_role_title := '트레이너';
    end if;
  end if;

  select bi.* into v_invite
  from public.business_invites bi
  where bi.created_by_user_id = v_user_id
    and bi.create_request_id = p_request_id
  for update;
  if found then
    if v_invite.gym_id is distinct from p_gym_id
      or v_invite.invite_kind is distinct from v_kind
      or v_invite.member_id is distinct from p_member_id
      or v_invite.recipient_name is distinct from v_name
      or v_invite.recipient_phone is distinct from v_phone
      or v_invite.role_title is distinct from v_role_title
      or v_invite.expires_at is distinct from p_expires_at
    then
      raise exception 'request_id was already used with different input'
        using errcode = '22023';
    end if;
    return jsonb_build_object(
      'invite', private.business_invite_json(v_invite),
      'token', null,
      'token_issued', false
    );
  end if;

  v_raw_token := encode(extensions.gen_random_bytes(32), 'hex');

  insert into public.business_invites (
    gym_id,
    invite_kind,
    member_id,
    created_by_user_id,
    recipient_name,
    recipient_phone,
    role_title,
    token_hash,
    expires_at,
    create_request_id
  ) values (
    p_gym_id,
    v_kind,
    p_member_id,
    v_user_id,
    v_name,
    v_phone,
    v_role_title,
    extensions.digest(v_raw_token, 'sha256'),
    p_expires_at,
    p_request_id
  )
  returning * into v_invite;

  return jsonb_build_object(
    'invite', private.business_invite_json(v_invite),
    'token', v_raw_token,
    'token_issued', true
  );
end
$function$;

create or replace function private.accept_business_invite(
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
  v_invite public.business_invites%rowtype;
  v_reused_invite_id uuid;
  v_member public.members%rowtype;
  v_trainer public.trainers%rowtype;
  v_gym_trainer public.gym_trainers%rowtype;
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
  where u.id = v_user_id
    and u.status = 'active'
  for share;
  if not found then
    raise exception 'Active user profile required' using errcode = '42501';
  end if;

  select bi.* into v_invite
  from public.business_invites bi
  where bi.token_hash = extensions.digest(v_token, 'sha256')
  for update;
  if not found then
    raise exception 'Invite is invalid or unavailable' using errcode = '22023';
  end if;

  select bi.id into v_reused_invite_id
  from public.business_invites bi
  where bi.accepted_by_user_id = v_user_id
    and bi.accepted_request_id = p_request_id
  limit 1;
  if found and v_reused_invite_id <> v_invite.id then
    raise exception 'request_id was already used for another invite'
      using errcode = '22023';
  end if;

  if v_invite.status = 'accepted' then
    if v_invite.accepted_by_user_id = v_user_id
      and v_invite.accepted_request_id = p_request_id
    then
      return jsonb_build_object(
        'accepted', true,
        'invite', private.business_invite_json(v_invite),
        'member_id', v_invite.accepted_member_id,
        'trainer_id', v_invite.accepted_trainer_id,
        'gym_trainer_id', v_invite.accepted_gym_trainer_id
      );
    end if;
    raise exception 'Invite is invalid or unavailable' using errcode = '22023';
  end if;

  if v_invite.status in ('revoked', 'expired') then
    return jsonb_build_object(
      'accepted', false,
      'invite', private.business_invite_json(v_invite),
      'member_id', null,
      'trainer_id', null,
      'gym_trainer_id', null
    );
  end if;

  if v_invite.expires_at <= now() then
    update public.business_invites
    set status = 'expired', updated_at = now()
    where id = v_invite.id
    returning * into v_invite;
    return jsonb_build_object(
      'accepted', false,
      'invite', private.business_invite_json(v_invite),
      'member_id', null,
      'trainer_id', null,
      'gym_trainer_id', null
    );
  end if;

  -- Revalidate the center at acceptance time. An invite issued by a center
  -- that was suspended or lost its active owner must not create access later.
  perform 1
  from public.gyms g
  join public.users owner_user on owner_user.id = g.owner_user_id
  where g.id = v_invite.gym_id
    and g.status = 'verified'
    and owner_user.status = 'active'
  for share of g, owner_user;
  if not found then
    raise exception 'Invite is invalid or unavailable' using errcode = '22023';
  end if;

  if v_invite.invite_kind = 'member' then
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(
        v_invite.gym_id::text || ':' || v_user_id::text,
        0
      )
    );

    if v_invite.member_id is not null then
      select m.* into v_member
      from public.members m
      where m.id = v_invite.member_id
      for update;
      if not found
        or v_member.gym_id <> v_invite.gym_id
        or (v_member.user_id is not null and v_member.user_id <> v_user_id)
      then
        raise exception 'Invite is invalid or unavailable' using errcode = '22023';
      end if;
      if exists (
        select 1
        from public.members m
        where m.gym_id = v_invite.gym_id
          and m.user_id = v_user_id
          and m.id <> v_member.id
      ) then
        raise exception 'Account is already linked to another member at this center'
          using errcode = '23505';
      end if;
      update public.members
      set user_id = v_user_id,
          name = coalesce(
            nullif(btrim(name), ''),
            v_invite.recipient_name,
            nullif(btrim(v_user.nickname), ''),
            '회원'
          ),
          phone = coalesce(nullif(btrim(phone), ''), v_invite.recipient_phone)
      where id = v_member.id
      returning * into v_member;
    else
      select m.* into v_member
      from public.members m
      where m.gym_id = v_invite.gym_id
        and m.user_id = v_user_id
      for update;
      if not found then
        insert into public.members (
          gym_id,
          user_id,
          name,
          phone
        ) values (
          v_invite.gym_id,
          v_user_id,
          coalesce(
            v_invite.recipient_name,
            nullif(btrim(v_user.nickname), ''),
            '회원'
          ),
          v_invite.recipient_phone
        )
        returning * into v_member;
      end if;
    end if;

    update public.business_invites
    set status = 'accepted',
        accepted_by_user_id = v_user_id,
        accepted_member_id = v_member.id,
        accepted_request_id = p_request_id,
        accepted_at = now(),
        updated_at = now()
    where id = v_invite.id
    returning * into v_invite;
  else
    select t.* into v_trainer
    from public.trainers t
    where t.user_id = v_user_id
      and t.status = 'approved'
    for share;
    if not found then
      raise exception 'An approved trainer profile is required'
        using errcode = '42501';
    end if;

    insert into public.gym_trainers (
      gym_id,
      trainer_user_id,
      trainer_id,
      role_title,
      status
    ) values (
      v_invite.gym_id,
      v_user_id,
      v_trainer.id,
      coalesce(v_invite.role_title, '트레이너'),
      'active'
    )
    on conflict (gym_id, trainer_user_id)
    do update set
      trainer_id = excluded.trainer_id,
      role_title = excluded.role_title,
      status = 'active'
    returning * into v_gym_trainer;

    update public.business_invites
    set status = 'accepted',
        accepted_by_user_id = v_user_id,
        accepted_trainer_id = v_trainer.id,
        accepted_gym_trainer_id = v_gym_trainer.id,
        accepted_request_id = p_request_id,
        accepted_at = now(),
        updated_at = now()
    where id = v_invite.id
    returning * into v_invite;
  end if;

  return jsonb_build_object(
    'accepted', true,
    'invite', private.business_invite_json(v_invite),
    'member_id', v_invite.accepted_member_id,
    'trainer_id', v_invite.accepted_trainer_id,
    'gym_trainer_id', v_invite.accepted_gym_trainer_id
  );
end
$function$;

create or replace function private.revoke_business_invite(
  p_invite_id uuid,
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
  v_invite public.business_invites%rowtype;
  v_reused_invite_id uuid;
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if p_request_id is null then
    raise exception 'request_id is required' using errcode = '22023';
  end if;

  select bi.* into v_invite
  from public.business_invites bi
  where bi.id = p_invite_id
  for update;
  if not found
    or v_invite.created_by_user_id <> v_user_id
    or not public.owns_gym(v_invite.gym_id)
  then
    raise exception 'Invite not found' using errcode = '42501';
  end if;

  select bi.id into v_reused_invite_id
  from public.business_invites bi
  where bi.created_by_user_id = v_user_id
    and bi.revoked_request_id = p_request_id
  limit 1;
  if found and v_reused_invite_id <> v_invite.id then
    raise exception 'request_id was already used for another invite'
      using errcode = '22023';
  end if;

  if v_invite.status = 'revoked'
    and v_invite.revoked_request_id = p_request_id
  then
    return private.business_invite_json(v_invite);
  end if;
  if v_invite.status = 'accepted' then
    raise exception 'Accepted invites cannot be revoked' using errcode = '22023';
  end if;
  if v_invite.status = 'expired' or v_invite.expires_at <= now() then
    update public.business_invites
    set status = 'expired', updated_at = now()
    where id = v_invite.id
    returning * into v_invite;
    return private.business_invite_json(v_invite);
  end if;

  update public.business_invites
  set status = 'revoked',
      revoked_at = now(),
      revoked_request_id = p_request_id,
      updated_at = now()
  where id = v_invite.id
  returning * into v_invite;

  return private.business_invite_json(v_invite);
end
$function$;

revoke all on function private.create_business_invite(
  uuid, text, uuid, timestamptz, uuid, text, text, text
) from public, anon, authenticated;
revoke all on function private.accept_business_invite(text, uuid)
  from public, anon, authenticated;
revoke all on function private.revoke_business_invite(uuid, uuid)
  from public, anon, authenticated;
grant execute on function private.create_business_invite(
  uuid, text, uuid, timestamptz, uuid, text, text, text
) to authenticated, service_role;
grant execute on function private.accept_business_invite(text, uuid)
  to authenticated, service_role;
grant execute on function private.revoke_business_invite(uuid, uuid)
  to authenticated, service_role;

create or replace function public.create_business_invite(
  gym_id uuid,
  invite_kind text,
  request_id uuid,
  expires_at timestamptz,
  member_id uuid default null,
  recipient_name text default null,
  recipient_phone text default null,
  role_title text default null
)
returns jsonb
language sql
volatile
security invoker
set search_path = ''
as $function$
  select private.create_business_invite(
    gym_id,
    invite_kind,
    request_id,
    expires_at,
    member_id,
    recipient_name,
    recipient_phone,
    role_title
  );
$function$;

create or replace function public.accept_business_invite(
  token text,
  request_id uuid
)
returns jsonb
language sql
volatile
security invoker
set search_path = ''
as $function$
  select private.accept_business_invite(token, request_id);
$function$;

create or replace function public.revoke_business_invite(
  invite_id uuid,
  request_id uuid
)
returns jsonb
language sql
volatile
security invoker
set search_path = ''
as $function$
  select private.revoke_business_invite(invite_id, request_id);
$function$;

revoke all on function public.create_business_invite(
  uuid, text, uuid, timestamptz, uuid, text, text, text
) from public, anon;
revoke all on function public.accept_business_invite(text, uuid)
  from public, anon;
revoke all on function public.revoke_business_invite(uuid, uuid)
  from public, anon;
grant execute on function public.create_business_invite(
  uuid, text, uuid, timestamptz, uuid, text, text, text
) to authenticated, service_role;
grant execute on function public.accept_business_invite(text, uuid)
  to authenticated, service_role;
grant execute on function public.revoke_business_invite(uuid, uuid)
  to authenticated, service_role;

commit;
