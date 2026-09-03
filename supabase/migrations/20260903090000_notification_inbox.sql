begin;

-- 알림함 — 앱 안에서 "무슨 알림이었는지" 다시 볼 수 있는 곳.
--
-- WHY: 런처 아이콘의 배지는 시스템 알림창에 남은 우리 알림 수를 세는 것이라,
-- 알림을 밀어 지우거나 놓치면 배지만 남고 앱에는 아무 흔적이 없었다
-- (실기기 보고: "알림 표기가 있는 것 같은데 들어가면 무슨 알림인지 모르겠네").
-- push_outbox는 발신함이지 보관함이 아니다 — 7일 뒤 지워지고 클라이언트가
-- 읽을 수도 없다(service_role 전용). 그래서 사용자가 읽는 표면을 따로 둔다.
--
-- 규칙 두 개:
--  1. 기록은 private.enqueue_push 한 곳에서만 만든다. 28개 호출부가 전부 그
--     관문을 지나므로, 알림을 새로 만들 때 알림함을 잊을 수 없다.
--  2. 설정 스위치(private.push_enabled)를 끈 종류는 알림함에도 안 남는다.
--     "끈다"는 건 이 종류를 나에게 알리지 말라는 뜻이고, 배지가 붙는 안 붙는
--     문제가 아니다. 대신 **기기가 없는 것**은 배달 사정일 뿐이라 알림함에는
--     남는다 — 푸시를 못 받는 기기(권한 거절·iOS)일수록 이 화면이 유일한 통로다.

create table if not exists public.user_notifications (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  -- push_outbox와 같은 어휘. 화면이 사건을 구분해야 하면 data->>'event'를 본다.
  kind text not null check (kind in (
    'coaching_feedback', 'community_reaction', 'together', 'workout_reminder',
    'business', 'business_activity', 'account'
  )),
  title text not null,
  body text not null,
  data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  read_at timestamptz
);

-- 목록은 언제나 "내 것을 최신순으로".
create index if not exists user_notifications_recent_idx
  on public.user_notifications (user_id, created_at desc);

-- 안 읽은 수를 세는 것은 화면을 열 때마다 하는 일이라 부분 인덱스를 둔다.
create index if not exists user_notifications_unread_idx
  on public.user_notifications (user_id)
  where read_at is null;

alter table public.user_notifications enable row level security;

drop policy if exists "read own notifications" on public.user_notifications;
create policy "read own notifications"
  on public.user_notifications for select
  using (auth.uid() = user_id);

-- 사용자가 바꿀 수 있는 것은 "읽었다"뿐이다. 남의 줄로 옮기는 것도 막는다.
drop policy if exists "mark own notifications read" on public.user_notifications;
create policy "mark own notifications read"
  on public.user_notifications for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- 정책은 열려 있어도 GRANT가 닫혀 있으면 안 보인다(커뮤니티 피드에서 겪었다).
revoke all on table public.user_notifications from public, anon, authenticated;
grant select, update on table public.user_notifications to authenticated;

-- ── 관문: 알림을 만들면 알림함에도 남는다 ───────────────────────────────
-- 20260826120000의 정의를 대체한다. 달라진 곳은 하나 — 기기 유무를 보기 전에
-- 알림함 줄을 넣는다. 순서를 뒤집으면 푸시를 못 받는 기기에서 알림함이 늘 빈다.
create or replace function private.enqueue_push(
  p_user uuid,
  p_kind text,
  p_title text,
  p_body text,
  p_data jsonb
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_body text := left(p_body, 200);
  v_data jsonb := coalesce(p_data, '{}'::jsonb);
begin
  if p_user is null then return; end if;
  if not private.push_enabled(p_user, p_kind) then return; end if;

  -- 배달과 무관하게 남는다. 이 줄이 사용자가 나중에 읽는 표면이다.
  insert into user_notifications (user_id, kind, title, body, data)
  values (p_user, p_kind, p_title, v_body, v_data);

  -- 받을 기기가 없으면 발신함 줄은 만들지 않는다.
  if not exists (select 1 from device_tokens where user_id = p_user) then
    return;
  end if;
  insert into push_outbox (user_id, kind, title, body, data)
  values (p_user, p_kind, p_title, v_body, v_data);
end;
$$;

-- ── 오래된 알림은 지운다 ────────────────────────────────────────────────
-- 읽은 것은 30일, 안 읽은 것은 90일. 안 읽은 것을 같이 지우면 오래 앱을 안 켠
-- 사람이 심사 결과 같은 것을 영영 못 본다.
create or replace function private.prune_user_notifications()
returns void
language sql
security definer
set search_path = public
as $$
  delete from user_notifications
  where (read_at is not null and read_at < now() - interval '30 days')
     or (read_at is null and created_at < now() - interval '90 days');
$$;

revoke all on function private.prune_user_notifications() from public, anon, authenticated;

select cron.unschedule('setflow-notification-prune')
  where exists (select 1 from cron.job where jobname = 'setflow-notification-prune');

select cron.schedule(
  'setflow-notification-prune',
  '45 4 * * *',
  $$select private.prune_user_notifications()$$
);

commit;
