-- 함께 방 유통기한 12시간 → 4시간 (2026-09-02).
--
-- 시계는 생성이 아니라 마지막 활동(updated_at) 기준이라, 세트를 보고할 때마다
-- 리셋된다 — 4시간 넘게 운동하는 사람도 세트 사이가 4시간 비지 않는 한 방은
-- 산다. 죽는 건 "4시간 동안 아무 일도 없던 방"뿐이다. 12시간은 처음의 보수적
-- 추정이었는데, 한 세션이 끝나고 반나절 가까이 어제의 방이 남는 쪽이 더 어색했다.
-- 근처 공개방 목록의 2시간 숨김(list_nearby_training_parties)보다는 길게 유지해
-- "목록에서 먼저 사라지고, 한참 뒤 삭제"의 2단계 순서를 지킨다.
--
-- 크론 잡(setflow-party-expiry, 매시 13분)은 그대로 이 함수를 부르므로
-- 함수 본문만 바꾼다.

create or replace function private.cleanup_stale_training_parties()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ids uuid[];
  v_id uuid;
begin
  with gone as (
    delete from public.training_parties
    where greatest(updated_at, created_at) < now() - interval '4 hours'
    returning id
  )
  select coalesce(array_agg(id), '{}') into v_ids from gone;

  -- 앱을 켜 둔 채 방치된 기기에도 소멸을 알린다 — 변경 RPC들이 쓰는 것과
  -- 같은 채널·이벤트, 방 소멸의 약속된 페이로드.
  foreach v_id in array v_ids loop
    perform realtime.send(
      jsonb_build_object('party', null),
      'party',
      'party:' || v_id,
      true
    );
  end loop;

  return coalesce(array_length(v_ids, 1), 0);
end;
$$;

revoke all on function private.cleanup_stale_training_parties()
  from public, anon, authenticated;
