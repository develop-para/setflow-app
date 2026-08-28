begin;

-- 크론이 엣지 펑션을 한 번도 못 깨우고 있었다.
--
-- 20260826123000은 `extensions.net.http_post`를 불렀다. pg_net은 `with schema
-- extensions`로 설치해도 함수는 언제나 `net` 스키마에 만들기 때문에, Postgres는
-- 저 세 토막을 `데이터베이스.스키마.함수`로 읽고 "cross-database references are
-- not implemented"로 죽는다. 발신함이 비어 있으면 그 줄에 닿기 전에 return해서
-- 첫 줄이 쌓인 2026-08-28에야 드러났다.
--
-- 같은 실수가 다시 안 나게: pg_net 함수는 `net.`으로만 부른다.

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

  perform net.http_post(
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

commit;
