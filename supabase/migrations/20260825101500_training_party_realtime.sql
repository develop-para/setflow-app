begin;

-- 함께 운동을 폴링에서 리얼타임으로.
--
-- 방 상태의 진실은 그대로 RPC가 쥔다 — 바뀐 것은 "언제 아느냐"뿐이다.
-- 각 변경 RPC가 끝에서 방 전체 JSON을 private 브로드캐스트로 쏘고,
-- 클라이언트는 `party:<uuid>` 채널을 구독한다. 수신 권한은
-- realtime.messages의 select 정책이 검사한다 — 이 정책의 서브쿼리는
-- realtime 스키마(수파베이스 전용 계층)에 있으므로, "우리 테이블 RLS에
-- 서브쿼리 0개"(EC2 이전 비용) 규칙 밖이다. EC2로 가면 이 계층 전체가
-- 다른 것으로 바뀐다.

-- 방 JSON을 멤버십 검사 없이 만드는 내부 조립기. 브로드캐스트는 "남은
-- 멤버들"에게 가야 하는데, 나간 사람이 호출한 leave 안에서는 auth.uid()가
-- 더 이상 멤버가 아니라 기존 get_training_party로는 조립이 안 된다.
-- 권한은 아래에서 전부 회수한다 — RPC 내부 전용이다.
create or replace function public.training_party_json(p_party_id uuid)
returns jsonb
language sql
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'id', p.id,
    'code', p.code,
    'host_user_id', p.host_user_id,
    'mode', p.mode,
    'starts_at', p.starts_at,
    'current_turn_user_id', p.current_turn_user_id,
    'members', coalesce((
      select jsonb_agg(jsonb_build_object(
        'user_id', m.user_id,
        'display_name', m.display_name,
        'state', m.state,
        'rest_ends_at', m.rest_ends_at,
        'completed_sets', m.completed_sets,
        'turn_order', m.turn_order
      ) order by m.turn_order)
      from public.training_party_members m where m.party_id = p.id
    ), '[]'::jsonb),
    'routines', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', r.id,
        'sender_user_id', r.sender_user_id,
        'sender_name', r.sender_name,
        'name', r.name,
        'payload', r.payload,
        'created_at', r.created_at
      ) order by r.created_at desc)
      from public.training_party_routines r where r.party_id = p.id
    ), '[]'::jsonb)
  )
  from public.training_parties p
  where p.id = p_party_id;
$$;

revoke execute on function public.training_party_json(uuid)
  from public, anon, authenticated;

-- get_training_party는 같은 조립기 + 멤버십 검사로 얇아진다.
create or replace function public.get_training_party(p_party_id uuid)
returns jsonb
language sql
security definer
set search_path = public
as $$
  select public.training_party_json(p_party_id)
  where exists (
    select 1 from public.training_parties p
    where p.id = p_party_id and auth.uid() = any (p.member_ids)
  );
$$;

-- 방이 바뀔 때마다 부르는 한 곳. 방이 사라졌으면 party:null을 쏴서
-- 클라이언트가 로비로 내려가게 한다.
create or replace function public.broadcast_training_party(p_party_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform realtime.send(
    jsonb_build_object('party', public.training_party_json(p_party_id)),
    'party',
    'party:' || p_party_id,
    true
  );
end;
$$;

revoke execute on function public.broadcast_training_party(uuid)
  from public, anon, authenticated;

-- 수신 권한: 그 방의 멤버만 party:<id> 채널을 들을 수 있다.
drop policy if exists training_party_members_can_listen on realtime.messages;
create policy training_party_members_can_listen on realtime.messages
  for select to authenticated
  using (
    realtime.messages.extension = 'broadcast'
    and realtime.topic() like 'party:%'
    and exists (
      select 1 from public.training_parties p
      where p.id::text = split_part(realtime.topic(), ':', 2)
        and (select auth.uid()) = any (p.member_ids)
    )
  );

-- 변경 RPC들이 끝에서 브로드캐스트를 쏘도록 재정의한다. 로직은 기존과
-- 동일하고 마지막 줄만 다르다.

create or replace function public.join_training_party(
  p_code text,
  p_display_name text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_party training_parties;
  v_order integer;
begin
  if v_user is null then
    raise exception 'auth required';
  end if;
  select * into v_party from training_parties
    where code = upper(trim(p_code));
  if not found then
    raise exception 'party not found';
  end if;

  if not (v_user = any (v_party.member_ids)) then
    select coalesce(max(turn_order) + 1, 0) into v_order
      from training_party_members where party_id = v_party.id;
    insert into training_party_members (party_id, user_id, display_name, turn_order)
      values (v_party.id, v_user, coalesce(nullif(p_display_name, ''), '회원'), v_order)
      on conflict (party_id, user_id) do nothing;
    update training_parties
      set member_ids = array_append(member_ids, v_user), updated_at = now()
      where id = v_party.id;
  end if;

  perform broadcast_training_party(v_party.id);
  return get_training_party(v_party.id);
end;
$$;

create or replace function public.leave_training_party(p_party_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_next uuid;
begin
  delete from training_party_members
    where party_id = p_party_id and user_id = v_user;
  update training_parties
    set member_ids = array_remove(member_ids, v_user), updated_at = now()
    where id = p_party_id;

  -- 나간 사람에게 차례가 걸려 있으면 방이 멈춘다. 남은 사람에게 넘긴다.
  select user_id into v_next from training_party_members
    where party_id = p_party_id order by turn_order limit 1;
  update training_parties
    set current_turn_user_id = case
          when current_turn_user_id = v_user then v_next
          else current_turn_user_id end
    where id = p_party_id;

  delete from training_parties
    where id = p_party_id and cardinality(member_ids) = 0;

  -- 방이 지워졌으면 party:null이 나가고, 남았으면 갱신된 방이 나간다.
  perform broadcast_training_party(p_party_id);
end;
$$;

create or replace function public.set_training_party_mode(
  p_party_id uuid,
  p_mode text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1 from training_parties
    where id = p_party_id and auth.uid() = any (member_ids)
  ) then
    raise exception 'not a member';
  end if;

  -- 규칙을 바꾸면 이전 규칙이 정한 차례는 무효다.
  update training_parties
    set mode = p_mode, current_turn_user_id = null, starts_at = null,
        updated_at = now()
    where id = p_party_id;
  update training_party_members
    set state = 'waiting', rest_ends_at = null
    where party_id = p_party_id;

  perform broadcast_training_party(p_party_id);
  return get_training_party(p_party_id);
end;
$$;

create or replace function public.start_training_party(
  p_party_id uuid,
  p_lead_seconds integer
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_party training_parties;
  v_first uuid;
begin
  select * into v_party from training_parties
    where id = p_party_id and auth.uid() = any (member_ids);
  if not found then
    raise exception 'not a member';
  end if;

  select user_id into v_first from training_party_members
    where party_id = p_party_id order by turn_order limit 1;

  update training_parties
    set starts_at = now() + make_interval(secs => greatest(coalesce(p_lead_seconds, 5), 0)),
        current_turn_user_id = case when v_party.mode = 'alternating' then v_first else null end,
        updated_at = now()
    where id = p_party_id;

  update training_party_members
    set state = case
          when v_party.mode = 'together' or user_id = v_first then 'lifting'
          else 'resting' end,
        rest_ends_at = null
    where party_id = p_party_id;

  perform broadcast_training_party(p_party_id);
  return get_training_party(p_party_id);
end;
$$;

create or replace function public.report_training_party_set(
  p_party_id uuid,
  p_rest_seconds integer
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_party training_parties;
  v_rest_ends timestamptz;
  v_next uuid;
begin
  select * into v_party from training_parties
    where id = p_party_id and v_user = any (member_ids);
  if not found then
    raise exception 'not a member';
  end if;

  v_rest_ends := now() + make_interval(secs => greatest(coalesce(p_rest_seconds, 90), 1));

  if v_party.mode = 'together' then
    update training_party_members
      set state = 'resting',
          rest_ends_at = v_rest_ends,
          completed_sets = completed_sets + case when user_id = v_user then 1 else 0 end
      where party_id = p_party_id;
    update training_parties
      set starts_at = null, updated_at = now() where id = p_party_id;
    perform broadcast_training_party(p_party_id);
    return get_training_party(p_party_id);
  end if;

  -- 교대: 끝낸 사람이 쉬고, 다음 사람의 휴식은 그 순간 끝난다.
  select user_id into v_next from training_party_members
    where party_id = p_party_id
      and turn_order > (
        select turn_order from training_party_members
        where party_id = p_party_id and user_id = v_user
      )
    order by turn_order limit 1;
  if v_next is null then
    select user_id into v_next from training_party_members
      where party_id = p_party_id order by turn_order limit 1;
  end if;

  update training_party_members
    set state = 'resting', rest_ends_at = v_rest_ends,
        completed_sets = completed_sets + 1
    where party_id = p_party_id and user_id = v_user;
  update training_party_members
    set state = 'lifting', rest_ends_at = null
    where party_id = p_party_id and user_id = v_next;
  update training_parties
    set current_turn_user_id = v_next, starts_at = null, updated_at = now()
    where id = p_party_id;

  perform broadcast_training_party(p_party_id);
  return get_training_party(p_party_id);
end;
$$;

create or replace function public.offer_training_party_routine(
  p_party_id uuid,
  p_name text,
  p_payload jsonb,
  p_sender_name text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1 from training_parties
    where id = p_party_id and auth.uid() = any (member_ids)
  ) then
    raise exception 'not a member';
  end if;

  insert into training_party_routines (party_id, sender_user_id, sender_name, name, payload)
    values (p_party_id, auth.uid(), coalesce(nullif(p_sender_name, ''), '회원'), p_name, p_payload);

  perform broadcast_training_party(p_party_id);
  return get_training_party(p_party_id);
end;
$$;

commit;
