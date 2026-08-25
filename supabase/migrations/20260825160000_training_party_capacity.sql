begin;

-- 방 정원: 6명.
--
-- 화면이 멤버 카드를 세로로 쌓는 구조라 그 위로는 방이 명단이 되고, 교대
-- 모드는 인원이 늘수록 대기가 길어져 4~5명을 넘기면 체감이 급격히 나빠진다.
-- 코드가 유출됐을 때 모르는 사람이 무한정 들어오는 것을 막는 벽이기도 하다.
-- 검사는 join에만 있으면 된다 — create는 항상 1명에서 시작한다.

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
    if cardinality(v_party.member_ids) >= 6 then
      raise exception 'party full';
    end if;
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

commit;
