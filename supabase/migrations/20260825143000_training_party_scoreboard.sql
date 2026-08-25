begin;

-- 전광판: "몇 세트 했나"만으로는 같이 뛰는 느낌이 안 난다. 각자 지금 무슨
-- 종목의 몇 세트째인지, 오늘 볼륨이 얼마인지를 방이 알아야 순위판이 된다.
-- 값은 세트를 보고할 때 클라이언트가 자기 오늘 기록에서 같이 실어 보낸다 —
-- 전광판용 수치이지 장부가 아니므로, 진실은 여전히 각자의 기록에 있다.

alter table public.training_party_members
  add column if not exists current_exercise text,
  add column if not exists current_set_number integer,
  add column if not exists current_set_total integer,
  add column if not exists total_volume numeric not null default 0;

-- 방 JSON에 전광판 필드를 싣는다.
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

-- 세트 보고가 전광판 정보를 같이 받는다. 인자가 늘면 create or replace는
-- 대체가 아니라 **오버로드**를 만들고, default 때문에 2-인자 호출이 양쪽에
-- 걸려 PostgREST가 함수를 못 고른다 — 옛 시그니처를 먼저 지운다. 새 인자는
-- 전부 default null이라 옛 클라이언트의 2-인자 호출도 그대로 동작한다.
drop function if exists public.report_training_party_set(uuid, integer);
create or replace function public.report_training_party_set(
  p_party_id uuid,
  p_rest_seconds integer,
  p_exercise text default null,
  p_set_number integer default null,
  p_set_total integer default null,
  p_volume numeric default null
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

  -- 보고자의 전광판 줄을 먼저 갱신한다 — 모드와 무관하게 같다.
  update training_party_members
    set current_exercise = coalesce(p_exercise, current_exercise),
        current_set_number = coalesce(p_set_number, current_set_number),
        current_set_total = coalesce(p_set_total, current_set_total),
        total_volume = coalesce(p_volume, total_volume)
    where party_id = p_party_id and user_id = v_user;

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

grant execute on function
  public.report_training_party_set(uuid, integer, text, integer, integer, numeric)
  to authenticated;
revoke execute on function
  public.report_training_party_set(uuid, integer, text, integer, integer, numeric)
  from public, anon;

commit;
