begin;

-- 함께 운동: 초대 코드로 모이는 방.
--
-- 설계에서 지킨 것 두 가지.
--
-- 1) **시각으로 저장한다.** `starts_at` / `rest_ends_at` 은 절대 시각이다.
--    "90초 남음" 같은 잔여 시간을 저장하면 기기마다 받은 시점이 달라 세트를
--    거듭할수록 벌어진다. 시각으로 두면 늦게 받은 기기도 같은 순간을 향해 센다.
--
-- 2) **RLS에 서브쿼리를 넣지 않는다.** `docs/backend-portability.md` 기준으로
--    현재 서브쿼리 낀 정책은 0개이고, 그 상태가 EC2 이전 비용을 선형으로 묶어
--    준다. 그래서 "이 방의 멤버인가"를 서브쿼리로 묻는 대신 방 행에
--    `member_ids uuid[]` 를 비정규화해 두고 `auth.uid() = any(member_ids)` 로
--    끝낸다. 배열은 아래 RPC들이 유일한 갱신 주체다.

create table if not exists public.training_parties (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  host_user_id uuid not null,
  mode text not null default 'together' check (mode in ('together', 'alternating')),
  member_ids uuid[] not null default '{}',
  starts_at timestamptz,
  current_turn_user_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.training_party_members (
  party_id uuid not null references public.training_parties(id) on delete cascade,
  user_id uuid not null,
  display_name text not null default '회원',
  state text not null default 'waiting' check (state in ('waiting', 'lifting', 'resting')),
  rest_ends_at timestamptz,
  completed_sets integer not null default 0,
  turn_order integer not null default 0,
  joined_at timestamptz not null default now(),
  primary key (party_id, user_id)
);

create table if not exists public.training_party_routines (
  id uuid primary key default gen_random_uuid(),
  party_id uuid not null references public.training_parties(id) on delete cascade,
  sender_user_id uuid not null,
  sender_name text not null default '회원',
  name text not null,
  payload jsonb not null,
  created_at timestamptz not null default now()
);

create index if not exists training_party_members_party_idx
  on public.training_party_members (party_id);
create index if not exists training_party_routines_party_idx
  on public.training_party_routines (party_id, created_at desc);

alter table public.training_parties enable row level security;
alter table public.training_party_members enable row level security;
alter table public.training_party_routines enable row level security;

-- 읽기는 멤버 배열 한 번의 비교로 끝난다. 쓰기는 아래 RPC(SECURITY DEFINER)만
-- 하므로 테이블에는 select 정책만 둔다 — 클라이언트가 직접 turn 을 쓰지 못하게
-- 막는 것이 곧 "차례는 서버가 정한다"를 강제하는 방법이다.
drop policy if exists training_parties_member_read on public.training_parties;
create policy training_parties_member_read on public.training_parties
  for select to authenticated
  using (auth.uid() = any (member_ids));

-- 자식 테이블 둘에는 정책을 **일부러 두지 않는다**(= 직접 접근 전면 거부).
-- 앱이 읽는 경로는 `get_training_party` 하나뿐이고 그 함수는 SECURITY DEFINER라
-- RLS를 지나간다. 여기에 정책을 쓰면 "이 방의 멤버인가"를 물어야 해서 서브쿼리가
-- 생기는데, 위에 적은 대로 그 숫자를 0으로 유지하는 것이 이전 비용을 묶어 준다.
-- (어드바이저의 "RLS Enabled No Policy"는 이 경우 의도된 상태다.)

-- 방 하나를 통째로 돌려준다. 화면이 테이블 세 개를 알 필요가 없다.
create or replace function public.get_training_party(p_party_id uuid)
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
  where p.id = p_party_id and auth.uid() = any (p.member_ids);
$$;

create or replace function public.create_training_party(
  p_mode text,
  p_display_name text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_code text;
  v_id uuid;
begin
  if v_user is null then
    raise exception 'auth required';
  end if;
  -- 헷갈리는 글자(0/O, 1/I)는 알파벳에서 빼 둔다. 전화로 불러 줄 코드다.
  loop
    v_code := (
      select string_agg(substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789',
        (floor(random() * 32) + 1)::int, 1), '')
      from generate_series(1, 6)
    );
    exit when not exists (select 1 from training_parties where code = v_code);
  end loop;

  insert into training_parties (code, host_user_id, mode, member_ids)
  values (v_code, v_user, coalesce(p_mode, 'together'), array[v_user])
  returning id into v_id;

  insert into training_party_members (party_id, user_id, display_name, turn_order)
  values (v_id, v_user, coalesce(nullif(p_display_name, ''), '회원'), 0);

  return get_training_party(v_id);
end;
$$;

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

  -- 규칙을 바꾸면 이전 규칙이 정한 차례는 무효다. 남겨 두면 새 규칙이 고르지
  -- 않은 사람에게 차례가 붙은 채로 시작된다.
  update training_parties
    set mode = p_mode, current_turn_user_id = null, starts_at = null,
        updated_at = now()
    where id = p_party_id;
  update training_party_members
    set state = 'waiting', rest_ends_at = null
    where party_id = p_party_id;

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

  return get_training_party(p_party_id);
end;
$$;

-- 이 기능이 도는 단 하나의 동사. 모드에 따라 뜻이 달라지는 결정을 서버에 둔다
-- — 두 기기가 각자 판단하면 둘 다 자기 차례라고 믿는 순간이 생긴다.
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

  return get_training_party(p_party_id);
end;
$$;

grant execute on function public.get_training_party(uuid) to authenticated;
grant execute on function public.create_training_party(text, text) to authenticated;
grant execute on function public.join_training_party(text, text) to authenticated;
grant execute on function public.leave_training_party(uuid) to authenticated;
grant execute on function public.set_training_party_mode(uuid, text) to authenticated;
grant execute on function public.start_training_party(uuid, integer) to authenticated;
grant execute on function public.report_training_party_set(uuid, integer) to authenticated;
grant execute on function public.offer_training_party_routine(uuid, text, jsonb, text) to authenticated;

-- 함수는 만들 때 PUBLIC 실행권이 딸려 나온다. 이 프로젝트의 하드닝 규칙대로
-- 익명 실행은 회수한다 — auth.uid() 검사로도 막히지만, 권한에서 막는 것이 먼저다.
revoke execute on function public.get_training_party(uuid) from public, anon;
revoke execute on function public.create_training_party(text, text) from public, anon;
revoke execute on function public.join_training_party(text, text) from public, anon;
revoke execute on function public.leave_training_party(uuid) from public, anon;
revoke execute on function public.set_training_party_mode(uuid, text) from public, anon;
revoke execute on function public.start_training_party(uuid, integer) from public, anon;
revoke execute on function public.report_training_party_set(uuid, integer) from public, anon;
revoke execute on function public.offer_training_party_routine(uuid, text, jsonb, text) from public, anon;

commit;
