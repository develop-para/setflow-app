-- 함께 방 유통기한: 마지막 활동(updated_at) 후 12시간이 지나면 서버가 지운다.
--
-- 방을 닫는 길이 "모두 나가기"뿐이라, 운동을 마치고 나가기를 안 누른 방이
-- 영원히 남았다 — 다음 날 앱을 열면 어제 방의 "돌아가기" 배너가 그대로 있고
-- 전광판 세트 수도 어제 것이다(실기기 보고: "운동 안 하고 6시간 지났는데도
-- 방 들어가기가 있네"). 유휴 방 자체는 행 하나라 부하는 없지만 — 웹소켓은
-- 앱이 떠 있을 때만 연결되고 브로드캐스트는 변경 RPC 때만 나간다 — 어제의
-- 방으로 돌아가는 문이 남는 것이 문제다.
--
-- 12시간인 이유: 한 세션은 길어야 몇 시간이고, 근처 공개방 목록은 이미
-- 2시간 조용한 방을 숨긴다(list_nearby_training_parties). 지우기는 그보다
-- 훨씬 보수적으로 잡아 "잠깐 쉬었다 오는 방"을 오살하지 않는다.
--
-- 클라이언트는 이미 준비돼 있다: 기억한 방을 fetchParty가 null로 돌려주면
-- 기억을 지우고 로비를 보여주고(_resumeRemembered), 열려 있는 구독은
-- {"party": null} 소멸 페이로드로 닫힌다(watchParty 계약). 자식 행은
-- FK cascade가 지운다.

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
    where greatest(updated_at, created_at) < now() - interval '12 hours'
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

select cron.unschedule('setflow-party-expiry')
  where exists (select 1 from cron.job where jobname = 'setflow-party-expiry');

select cron.schedule(
  'setflow-party-expiry',
  '13 * * * *',
  $$select private.cleanup_stale_training_parties()$$
);
