begin;

-- 공개방 — 같은 헬스장의 모르는 사람과도 전광판 하나로 겨룬다.
--
-- 방은 둘 중 하나다. 비밀(기본): 코드를 아는 사람만. 공개: 근처에서 열린
-- 방 목록에 뜨고 누구나 들어온다. 위치는 **공개방을 열 때만** 남기고, 목록은
-- 좌표가 아니라 **거리**만 돌려준다 — 남의 좌표가 앱에 닿을 일이 없다.
-- 2시간 넘게 조용한 방과 꽉 찬 방은 목록에서 빠진다.

alter table public.training_parties
  add column if not exists visibility text not null default 'private'
    check (visibility in ('public', 'private')),
  add column if not exists lat double precision,
  add column if not exists lng double precision;

create index if not exists training_parties_public_idx
  on public.training_parties (updated_at)
  where visibility = 'public';

-- ── 방 JSON에 visibility ────────────────────────────────────────────────
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

-- ── 만들기: 공개/비밀 + 좌표 ────────────────────────────────────────────
-- 시그니처가 바뀌므로 옛 것을 지운다. 새 인자는 기본값이 있어 옛 클라이언트의
-- 두 인자 호출도 그대로 비밀방을 만든다.
drop function if exists public.create_training_party(text, text);

create or replace function public.create_training_party(
  p_mode text,
  p_display_name text,
  p_visibility text default 'private',
  p_lat double precision default null,
  p_lng double precision default null
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
  -- 공개방은 좌표가 있어야 목록에 뜬다. 없으면 비밀방으로 연다 — 앱이 이미
  -- 그렇게 안내한다.
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

  insert into training_parties (code, host_user_id, mode, member_ids, visibility, lat, lng)
  values (
    v_code, v_user, coalesce(p_mode, 'together'), array[v_user],
    v_visibility,
    case when v_visibility = 'public' then p_lat end,
    case when v_visibility = 'public' then p_lng end
  )
  returning id into v_id;

  insert into training_party_members (party_id, user_id, display_name, turn_order)
  values (v_id, v_user, coalesce(nullif(p_display_name, ''), '회원'), 0);

  return get_training_party(v_id);
end;
$$;

revoke all on function public.create_training_party(text, text, text, double precision, double precision)
  from public, anon;
grant execute on function public.create_training_party(text, text, text, double precision, double precision)
  to authenticated;

-- ── 공개/비밀 전환 (방장만) ─────────────────────────────────────────────
create or replace function public.set_training_party_visibility(
  p_party_id uuid,
  p_visibility text,
  p_lat double precision default null,
  p_lng double precision default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_visibility text := case when p_visibility = 'public' then 'public' else 'private' end;
begin
  if v_user is null then
    raise exception 'auth required';
  end if;
  if v_visibility = 'public' and (p_lat is null or p_lng is null) then
    raise exception 'location required';
  end if;
  update training_parties
    set visibility = v_visibility,
        lat = case when v_visibility = 'public' then p_lat end,
        lng = case when v_visibility = 'public' then p_lng end,
        updated_at = now()
    where id = p_party_id and host_user_id = v_user;
  if not found then
    raise exception 'not the host';
  end if;
  perform broadcast_training_party(p_party_id);
  return get_training_party(p_party_id);
end;
$$;

revoke all on function public.set_training_party_visibility(uuid, text, double precision, double precision)
  from public, anon;
grant execute on function public.set_training_party_visibility(uuid, text, double precision, double precision)
  to authenticated;

-- ── 근처 공개방 ─────────────────────────────────────────────────────────
-- 좌표는 나가지 않는다. 거리(10m 단위)와 사람이 판단할 것만 — 누가 열었는지,
-- 어떤 방식인지, 몇 명인지, 언제 열렸는지.
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
      -- 대략의 상자로 먼저 거른다(위도 1도 ≈ 111km).
      and abs(p.lat - p_lat) < p_radius_m / 111000.0 + 0.001
      and abs(p.lng - p_lng) < p_radius_m / (111000.0 * greatest(cos(radians(p_lat)), 0.2)) + 0.001
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', c.id,
    'mode', c.mode,
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

revoke all on function public.list_nearby_training_parties(double precision, double precision, integer)
  from public, anon;
grant execute on function public.list_nearby_training_parties(double precision, double precision, integer)
  to authenticated;

-- ── 공개방 참가 (코드 없이) ─────────────────────────────────────────────
create or replace function public.join_public_training_party(
  p_party_id uuid,
  p_display_name text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text;
begin
  if auth.uid() is null then
    raise exception 'auth required';
  end if;
  select code into v_code from training_parties
    where id = p_party_id and visibility = 'public';
  if v_code is null then
    raise exception 'party not found';
  end if;
  return join_training_party(v_code, p_display_name);
end;
$$;

revoke all on function public.join_public_training_party(uuid, text) from public, anon;
grant execute on function public.join_public_training_party(uuid, text) to authenticated;

commit;
