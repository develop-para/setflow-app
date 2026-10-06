-- A public directory suggestion is never a business workspace, a membership,
-- or permission to edit a gym. Owners still use the existing verified process.
begin;

create table private.gym_directory_requests (
  id text not null,
  owner_user_id uuid not null references public.users(id) on delete cascade,
  kind text not null,
  facility_id text,
  gym_name text not null,
  address text not null,
  note text not null default '',
  submitted_at timestamptz not null default now(),
  status text not null default 'pending',
  review_note text not null default '',
  reviewed_by uuid references public.users(id),
  reviewed_at timestamptz,
  primary key (owner_user_id, id),
  constraint gym_directory_requests_id_check check (
    id ~ '^[a-zA-Z0-9_:-]{1,80}$'
  ),
  constraint gym_directory_requests_kind_check check (
    kind in ('add', 'correction', 'claim')
  ),
  constraint gym_directory_requests_facility_check check (
    (kind = 'add' and facility_id is null)
    or (kind in ('correction', 'claim')
      and facility_id is not null
      and char_length(btrim(facility_id)) between 1 and 80)
  ),
  constraint gym_directory_requests_name_check check (
    char_length(btrim(gym_name)) between 1 and 150
  ),
  constraint gym_directory_requests_address_check check (
    char_length(btrim(address)) between 1 and 500
  ),
  constraint gym_directory_requests_note_check check (
    char_length(note) <= 2000
  ),
  constraint gym_directory_requests_status_check check (
    status in ('pending', 'reviewed', 'rejected')
  ),
  constraint gym_directory_requests_review_check check (
    char_length(review_note) <= 2000
    and ((status = 'pending' and reviewed_by is null and reviewed_at is null)
      or (status <> 'pending' and reviewed_by is not null and reviewed_at is not null))
  )
);

create index gym_directory_requests_pending_idx
  on private.gym_directory_requests (submitted_at) where status = 'pending';

alter table private.gym_directory_requests enable row level security;
revoke all on table private.gym_directory_requests from public, anon, authenticated;
grant select on table private.gym_directory_requests to authenticated;
grant update (status, review_note, reviewed_by, reviewed_at)
  on table private.gym_directory_requests to authenticated;
grant select, insert, update, delete on table private.gym_directory_requests to service_role;

create policy gym_directory_requests_active_session
  on private.gym_directory_requests as restrictive for all to authenticated
  using ((select private.has_active_app_session()))
  with check ((select private.has_active_app_session()));

create policy gym_directory_requests_owner_or_admin_read
  on private.gym_directory_requests for select to authenticated
  using (owner_user_id = (select auth.uid()) or (select private.is_admin()));

create policy gym_directory_requests_admin_review
  on private.gym_directory_requests for update to authenticated
  using ((select private.is_admin()))
  with check ((select private.is_admin()));

-- Safe to probe before login: exposes only whether this migration is installed.
create function public.gym_directory_request_service_available()
returns boolean language sql stable security invoker set search_path = ''
as $$ select true; $$;
revoke all on function public.gym_directory_request_service_available() from public;
grant execute on function public.gym_directory_request_service_available()
  to anon, authenticated, service_role;

create function private.submit_gym_directory_request(
  p_request_id text,
  p_request_kind text,
  p_facility_id text,
  p_gym_name text,
  p_address text,
  p_note text
)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  v_owner_id uuid := (select auth.uid());
  v_kind text := btrim(coalesce(p_request_kind, ''));
  v_facility_id text := nullif(btrim(p_facility_id), '');
  v_gym_name text := btrim(coalesce(p_gym_name, ''));
  v_address text := btrim(coalesce(p_address, ''));
  v_note text := btrim(coalesce(p_note, ''));
  v_row private.gym_directory_requests%rowtype;
begin
  if not private.has_active_app_session() then
    raise exception using errcode = '42501', message = '유효한 로그인이 필요해요.';
  end if;
  if p_request_id is null or p_request_id !~ '^[a-zA-Z0-9_:-]{1,80}$'
    or v_kind not in ('add', 'correction', 'claim')
    or char_length(v_gym_name) not between 1 and 150
    or char_length(v_address) not between 1 and 500
    or char_length(v_note) > 2000
    or (v_kind = 'add' and v_facility_id is not null)
    or (v_kind <> 'add' and (v_facility_id is null or char_length(v_facility_id) > 80))
  then
    raise exception using errcode = '22023', message = '제안 내용을 확인해주세요.';
  end if;

  -- Serialize retries for this account/ID, including after a lost response.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('gym_directory_request:' || v_owner_id::text || ':' || p_request_id, 0)
  );
  select * into v_row from private.gym_directory_requests
    where owner_user_id = v_owner_id and id = p_request_id;
  if found then
    if v_row.kind is distinct from v_kind
      or v_row.facility_id is distinct from v_facility_id
      or v_row.gym_name is distinct from v_gym_name
      or v_row.address is distinct from v_address
      or v_row.note is distinct from v_note then
      raise exception using errcode = '23505', message = '이미 사용한 제안 ID의 내용이 달라요.';
    end if;
  else
    insert into private.gym_directory_requests (
      id, owner_user_id, kind, facility_id, gym_name, address, note
    ) values (
      p_request_id, v_owner_id, v_kind, v_facility_id, v_gym_name, v_address, v_note
    ) returning * into v_row;
  end if;
  return jsonb_build_object(
    'id', v_row.id, 'owner_user_id', v_row.owner_user_id,
    'submitted_at', v_row.submitted_at
  );
end;
$$;

create function public.submit_gym_directory_request(
  request_id text,
  request_kind text,
  facility_id text,
  gym_name text,
  address text,
  note text
)
returns jsonb language sql security invoker set search_path = ''
as $$ select private.submit_gym_directory_request($1, $2, $3, $4, $5, $6); $$;

revoke all on function private.submit_gym_directory_request(text, text, text, text, text, text)
  from public, anon;
revoke all on function public.submit_gym_directory_request(text, text, text, text, text, text)
  from public, anon;
grant execute on function private.submit_gym_directory_request(text, text, text, text, text, text),
  public.submit_gym_directory_request(text, text, text, text, text, text)
  to authenticated;

-- Review changes only the queue. It does not edit a directory or grant a role.
create function private.review_gym_directory_request(
  p_request_id text,
  p_owner_user_id uuid,
  p_decision text,
  p_review_note text
)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  v_note text := btrim(coalesce(p_review_note, ''));
  v_row private.gym_directory_requests%rowtype;
begin
  if not private.has_active_app_session() or not private.is_admin() then
    raise exception using errcode = '42501', message = '관리자 권한이 필요해요.';
  end if;
  if p_decision is null or p_decision not in ('reviewed', 'rejected')
    or char_length(v_note) > 2000 then
    raise exception using errcode = '22023', message = '검토 내용을 확인해주세요.';
  end if;
  update private.gym_directory_requests
    set status = p_decision, review_note = v_note,
      reviewed_by = (select auth.uid()), reviewed_at = now()
    where owner_user_id = p_owner_user_id and id = p_request_id and status = 'pending'
    returning * into v_row;
  if not found then
    raise exception using errcode = 'P0002', message = '검토할 제안이 없어요.';
  end if;
  return jsonb_build_object('id', v_row.id, 'status', v_row.status, 'reviewed_at', v_row.reviewed_at);
end;
$$;

create function public.review_gym_directory_request(
  request_id text, request_owner_user_id uuid, decision text, review_note text
)
returns jsonb language sql security invoker set search_path = ''
as $$ select private.review_gym_directory_request($1, $2, $3, $4); $$;

revoke all on function private.review_gym_directory_request(text, uuid, text, text)
  from public, anon;
revoke all on function public.review_gym_directory_request(text, uuid, text, text)
  from public, anon;
grant execute on function private.review_gym_directory_request(text, uuid, text, text),
  public.review_gym_directory_request(text, uuid, text, text) to authenticated;

notify pgrst, 'reload schema';
commit;
