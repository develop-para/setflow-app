-- 게임방의 상식 셋(docs/plan/09): 방제, 방장 승계, 강퇴.
--
-- 방제는 방의 이름이다 — 없으면 지금처럼 "지훈님의 방"/종목으로 부른다.
-- 방장은 host_user_id 그대로 쓰되, 방장이 나가면 남은 사람 중 turn_order가
-- 가장 빠른 사람이 잇는다(방장이 나가는 순간 강퇴·공개 전환이 죽으면
-- 방이 유령이 된다). 강퇴는 방장만, 자신은 못 한다 — 쫓겨난 쪽 처리(로비로,
-- 안내 한 줄)는 브로드캐스트를 받은 클라이언트의 몫이다.

alter table public.training_parties
  add column if not exists title text;

-- ── 방 JSON에 title ─────────────────────────────────────────────────────
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
    'title', p.title,
    'visibility', p.visibility,
    'starts_at', p.starts_at,
    'current_turn_user_id', p.current_turn_user_id,
    'members', coalesce((
      select jsonb_agg(jsonb_build_object(
        'user_id', m.user_id,
        'display_name', m.display_name,
        'state', m.state,
        'rest_ends_at', m.rest_ends_at,
        'completed_sets', m.completed_sets,
        'turn_order', m.turn_order,
        'current_exercise', m.current_exercise,
        'current_set_number', m.current_set_number,
        'current_set_total', m.current_set_total,
        'total_volume', m.total_volume
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

-- ── 만들기에 방제 ───────────────────────────────────────────────────────
-- 시그니처가 바뀌므로 옛 것을 지운다. 새 인자는 기본값이 있어 옛 클라이언트의
-- 호출도 그대로 제목 없는 방을 만든다.
drop function if exists public.create_training_party(
  text, text, text, double precision, double precision);

create or replace function public.create_training_party(
  p_mode text,
  p_display_name text,
  p_visibility text default 'private',
  p_lat double precision default null,
  p_lng double precision default null,
  p_title text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_code text;
  v_id uuid;
  v_visibility text := case when p_visibility = 'public' then 'public' else 'private' end;
begin
  if v_user is null then
    raise exception 'auth required';
  end if;
  if v_visibility = 'public' and (p_lat is null or p_lng is null) then
    v_visibility := 'private';
  end if;
  loop
    v_code := (
      select string_agg(substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789',
        (floor(random() * 32) + 1)::int, 1), '')
      from generate_series(1, 6)
    );
    exit when not exists (select 1 from training_parties where code = v_code);
  end loop;

  insert into training_parties
    (code, host_user_id, mode, member_ids, visibility, lat, lng, title)
  values (
    v_code, v_user, coalesce(p_mode, 'together'), array[v_user],
    v_visibility,
    case when v_visibility = 'public' then p_lat end,
    case when v_visibility = 'public' then p_lng end,
    left(nullif(trim(coalesce(p_title, '')), ''), 24)
  )
  returning id into v_id;

  insert into training_party_members (party_id, user_id, display_name, turn_order)
  values (v_id, v_user, coalesce(nullif(p_display_name, ''), '회원'), 0);

  return get_training_party(v_id);
end;
$$;

revoke all on function public.create_training_party(
  text, text, text, double precision, double precision, text)
  from public, anon;
grant execute on function public.create_training_party(
  text, text, text, double precision, double precision, text)
  to authenticated;

-- ── 근처 목록에 title ───────────────────────────────────────────────────
create or replace function public.list_nearby_training_parties(
  p_lat double precision,
  p_lng double precision,
  p_radius_m integer default 3000
)
returns jsonb
language sql
security definer
set search_path = public
as $$
  with candidates as (
    select
      p.*,
      2 * 6371000 * asin(sqrt(
        power(sin(radians((p.lat - p_lat) / 2)), 2)
        + cos(radians(p_lat)) * cos(radians(p.lat))
          * power(sin(radians((p.lng - p_lng) / 2)), 2)
      )) as distance_m
    from training_parties p
    where auth.uid() is not null
      and p.visibility = 'public'
      and p.lat is not null and p.lng is not null
      and greatest(p.updated_at, p.created_at) > now() - interval '2 hours'
      and cardinality(p.member_ids) < 6
      and not (auth.uid() = any (p.member_ids))
      and abs(p.lat - p_lat) < p_radius_m / 111000.0 + 0.001
      and abs(p.lng - p_lng) < p_radius_m / (111000.0 * greatest(cos(radians(p_lat)), 0.2)) + 0.001
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', c.id,
    'mode', c.mode,
    'title', c.title,
    'member_count', cardinality(c.member_ids),
    'distance_m', (round(c.distance_m / 10) * 10)::int,
    'created_at', c.created_at,
    'host_name', coalesce((
      select m.display_name from training_party_members m
      where m.party_id = c.id and m.user_id = c.host_user_id
    ), '회원')
  ) order by c.distance_m), '[]'::jsonb)
  from (
    select * from candidates where distance_m <= p_radius_m
    order by distance_m limit 20
  ) c;
$$;

-- ── 방장 승계: 방장이 나가면 남은 사람 중 turn_order 최솟값이 잇는다 ────
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

  select user_id into v_next from training_party_members
    where party_id = p_party_id order by turn_order limit 1;
  update training_parties
    set current_turn_user_id = case
          when current_turn_user_id = v_user then v_next
          else current_turn_user_id end,
        host_user_id = case
          when host_user_id = v_user and v_next is not null then v_next
          else host_user_id end
    where id = p_party_id;

  delete from training_parties
    where id = p_party_id and cardinality(member_ids) = 0;

  perform broadcast_training_party(p_party_id);
end;
$$;

-- ── 강퇴: 방장만, 자신은 제외 ───────────────────────────────────────────
create or replace function public.kick_training_party_member(
  p_party_id uuid,
  p_member uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_next uuid;
begin
  if v_user is null then
    raise exception 'auth required';
  end if;
  if not exists (
    select 1 from training_parties
    where id = p_party_id and host_user_id = v_user
  ) then
    raise exception 'not the host';
  end if;
  if p_member = v_user then
    raise exception 'cannot kick self';
  end if;

  delete from training_party_members
    where party_id = p_party_id and user_id = p_member;
  update training_parties
    set member_ids = array_remove(member_ids, p_member), updated_at = now()
    where id = p_party_id;

  -- 쫓겨난 사람에게 차례가 걸려 있으면 남은 사람에게 넘긴다(나가기와 동일).
  select user_id into v_next from training_party_members
    where party_id = p_party_id order by turn_order limit 1;
  update training_parties
    set current_turn_user_id = case
          when current_turn_user_id = p_member then v_next
          else current_turn_user_id end
    where id = p_party_id;

  perform broadcast_training_party(p_party_id);
  return get_training_party(p_party_id);
end;
$$;

revoke all on function public.kick_training_party_member(uuid, uuid)
  from public, anon;
grant execute on function public.kick_training_party_member(uuid, uuid)
  to authenticated;
