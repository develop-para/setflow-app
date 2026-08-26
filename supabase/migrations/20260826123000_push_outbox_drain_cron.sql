begin;

-- 발신함을 1분마다 비운다.
--
-- 트리거는 줄만 넣고 끝난다(댓글 쓰기가 FCM을 기다리면 안 된다). 실제 전송은
-- send-push 엣지 펑션이 하고, 그걸 깨우는 것이 여기다.
--
-- URL과 키를 SQL에 박지 않는 이유는 AGENTS.md 2절과 같다 — 주소가 코드에
-- 박히면 서버를 옮길 때 마이그레이션을 고쳐야 한다. Vault에서 읽는다:
--
--   select vault.create_secret('https://<ref>.supabase.co', 'project_url');
--   select vault.create_secret('<service_role_key>', 'service_role_key');
--
-- 둘 중 하나라도 없으면 이 작업은 조용히 아무것도 하지 않는다. 알림이 안 오는
-- 것은 불편이지만, 없는 키로 매분 실패 로그를 쌓는 것은 소음이다.

create extension if not exists pg_net with schema extensions;

create or replace function private.drain_push_outbox()
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_url text;
  v_key text;
begin
  -- 보낼 것이 없으면 남의 서비스를 부르지 않는다.
  if not exists (
    select 1 from push_outbox where sent_at is null and attempts < 5
  ) then
    return;
  end if;

  select decrypted_secret into v_url
    from vault.decrypted_secrets where name = 'project_url';
  select decrypted_secret into v_key
    from vault.decrypted_secrets where name = 'service_role_key';
  if v_url is null or v_key is null then
    return;
  end if;

  perform extensions.net.http_post(
    url := v_url || '/functions/v1/send-push',
    headers := jsonb_build_object(
      'content-type', 'application/json',
      'authorization', 'Bearer ' || v_key
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 20000
  );
end;
$$;

revoke all on function private.drain_push_outbox() from public, anon, authenticated;

select cron.unschedule('setflow-push-drain')
  where exists (select 1 from cron.job where jobname = 'setflow-push-drain');

select cron.schedule(
  'setflow-push-drain',
  '* * * * *',
  $$select private.drain_push_outbox()$$
);

-- 보낸 줄은 오래 둘 이유가 없다. 재시도를 다 쓴 줄은 원인을 볼 수 있게 조금 더
-- 남긴다.
create or replace function private.prune_push_outbox()
returns void
language sql
security definer
set search_path = public
as $$
  delete from push_outbox
  where (sent_at is not null and sent_at < now() - interval '7 days')
     or (sent_at is null and attempts >= 5 and created_at < now() - interval '30 days');
$$;

revoke all on function private.prune_push_outbox() from public, anon, authenticated;

select cron.unschedule('setflow-push-prune')
  where exists (select 1 from cron.job where jobname = 'setflow-push-prune');

select cron.schedule(
  'setflow-push-prune',
  '30 4 * * *',
  $$select private.prune_push_outbox()$$
);

commit;
