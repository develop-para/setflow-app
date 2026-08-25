begin;

-- 세 번째 모드 '각자(free)'.
--
-- 락스텝(같이 시작·공유 휴식)은 같은 공간이나 맨몸 운동에서만 현실적이다.
-- 떨어져서 각자 헬스장에 있으면 기구가 사용 중일 수도, 종목이 다를 수도
-- 있어서 같은 시계로 묶을 수 없다 — 그때의 "함께"는 타이머가 아니라
-- 전광판이다. free에서는 세트 보고가 **보고자 본인만** 휴식에 들어가게 하고,
-- 나머지는 건드리지 않는다. 차례도 없다.

alter table public.training_parties
  drop constraint if exists training_parties_mode_check;
alter table public.training_parties
  add constraint training_parties_mode_check
  check (mode in ('together', 'alternating', 'free'));

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

  if v_party.mode = 'free' then
    -- 각자: 내 휴식만 시작된다. 남의 시계는 남의 것이다.
    update training_party_members
      set state = 'resting', rest_ends_at = v_rest_ends,
          completed_sets = completed_sets + 1
      where party_id = p_party_id and user_id = v_user;
    update training_parties
      set updated_at = now() where id = p_party_id;
    perform broadcast_training_party(p_party_id);
    return get_training_party(p_party_id);
  end if;

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

commit;
