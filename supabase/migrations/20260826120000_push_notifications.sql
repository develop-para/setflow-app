begin;

-- 푸시 알림 — 설정의 두 스위치가 실제로 무언가를 켜게 만든다.
--
-- '코칭 피드백 알림'과 '커뮤니티 반응 알림'은 오래도록 값만 저장하고 보낼 곳이
-- 없었다. 여기서 세 조각을 놓는다: 기기 토큰(어디로), 발신함(무엇을),
-- 트리거(언제). 실제 전송은 엣지 펑션이 한다 — FCM은 외부 API라
-- AGENTS.md 2절이 허용하는 바로 그 경우고, 사용자 핵심 동작 경로가 아니다.
--
-- 트리거가 FCM을 직접 부르지 않고 발신함에 넣는 이유: 남의 서비스가 느리거나
-- 죽었을 때 **댓글 쓰기가 같이 실패하면 안 된다.** 알림은 부수효과지 본 동작이
-- 아니다. 실패는 재시도로 흡수되고, 끝내 못 보내도 원래 동작은 이미 끝나 있다.

-- ── 기기 토큰 ────────────────────────────────────────────────────────────
-- 테이블은 초기 스키마에 이미 있었다(0행). 새로 만들지 않고 쓸 수 있게 보강한다.
alter table public.device_tokens
  add column if not exists updated_at timestamptz not null default now();

-- 같은 토큰이 계정을 옮겨 다닐 수 있다(기기 하나, 사용자 둘). 토큰이 유일해야
-- 이전 소유자에게 남의 알림이 가지 않는다.
delete from public.device_tokens a
  using public.device_tokens b
  where a.token = b.token and a.ctid < b.ctid;
create unique index if not exists device_tokens_token_key
  on public.device_tokens (token);
create index if not exists device_tokens_user_idx
  on public.device_tokens (user_id);

alter table public.device_tokens enable row level security;
revoke all on table public.device_tokens from public, anon;
grant select on table public.device_tokens to authenticated;

drop policy if exists "device_tokens_select_own" on public.device_tokens;
create policy "device_tokens_select_own"
  on public.device_tokens
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

create or replace function public.register_push_token(
  p_token text,
  p_platform text
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'authentication required';
  end if;
  if coalesce(btrim(p_token), '') = '' then
    raise exception 'token required';
  end if;
  if p_platform not in ('android', 'ios') then
    raise exception 'unsupported platform: %', p_platform;
  end if;

  -- 앱이 처음 뜰 때마다 부르는 자리라 upsert여야 한다. 토큰이 이미 다른
  -- 계정에 붙어 있으면 이쪽으로 옮긴다 — 그 기기의 현재 사용자가 진실이다.
  insert into device_tokens (user_id, token, platform, updated_at)
  values (v_user, btrim(p_token), p_platform, now())
  on conflict (token) do update
    set user_id = excluded.user_id,
        platform = excluded.platform,
        updated_at = now();
end;
$$;

revoke all on function public.register_push_token(text, text) from public, anon;
grant execute on function public.register_push_token(text, text) to authenticated;

create or replace function public.unregister_push_token(p_token text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'authentication required';
  end if;
  delete from device_tokens where token = btrim(p_token) and user_id = v_user;
end;
$$;

revoke all on function public.unregister_push_token(text) from public, anon;
grant execute on function public.unregister_push_token(text) to authenticated;

-- ── 발신함 ──────────────────────────────────────────────────────────────
create table if not exists public.push_outbox (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  -- 설정 스위치와 짝이 되는 이름. 여기 없는 종류는 보내지 않는다.
  kind text not null check (kind in ('coaching_feedback', 'community_reaction')),
  title text not null,
  body text not null,
  data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  sent_at timestamptz,
  attempts integer not null default 0,
  last_error text
);

create index if not exists push_outbox_pending_idx
  on public.push_outbox (created_at)
  where sent_at is null;

alter table public.push_outbox enable row level security;
-- 클라이언트는 발신함을 볼 일이 없다. 엣지 펑션만 service_role로 읽는다.
revoke all on table public.push_outbox from public, anon, authenticated;

-- ── 사용자 설정 확인 ────────────────────────────────────────────────────
-- 설정의 진실은 앱이 쓰는 스냅샷이다. 알림용 설정 테이블을 따로 두면 두 곳이
-- 어긋난다 — 지금 고치고 있는 문제가 바로 그것이다.
create or replace function private.push_enabled(p_user uuid, p_kind text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (
      select case p_kind
        when 'coaching_feedback' then
          (s.payload -> 'preferences' ->> 'pushCoachingFeedback')::boolean
        when 'community_reaction' then
          (s.payload -> 'preferences' ->> 'communityReactionNotifications')::boolean
      end
      from app_state_snapshots s
      where s.user_id = p_user
    ),
    -- 스냅샷이 아직 없는 계정은 앱의 기본값을 따른다.
    case p_kind when 'coaching_feedback' then true else false end
  );
$$;

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
begin
  if p_user is null then return; end if;
  if not private.push_enabled(p_user, p_kind) then return; end if;
  -- 받을 기기가 없으면 줄을 만들지 않는다.
  if not exists (select 1 from device_tokens where user_id = p_user) then
    return;
  end if;
  insert into push_outbox (user_id, kind, title, body, data)
  values (p_user, p_kind, p_title, left(p_body, 200), coalesce(p_data, '{}'::jsonb));
end;
$$;

-- ── 트리거: 트레이너가 상담에 답하면 ────────────────────────────────────
-- 앱의 '코칭 피드백'은 consultation_messages다(reply_business_consultation이
-- 쓴다). coaching_feedbacks 테이블은 초기 스키마의 미사용 잔재라 쓰지 않는다.
create or replace function private.notify_consultation_reply()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_member uuid;
begin
  -- 회원이 쓴 메시지는 회원에게 알리지 않는다.
  if coalesce(new.sender_type, 'member') = 'member' then
    return new;
  end if;
  select user_id into v_member from consultations where id = new.consultation_id;
  perform private.enqueue_push(
    v_member,
    'coaching_feedback',
    '트레이너 답변이 도착했어요',
    coalesce(new.text, '상담에 새 답변이 있어요.'),
    jsonb_build_object('consultationId', new.consultation_id::text)
  );
  return new;
end;
$$;

drop trigger if exists notify_consultation_reply on public.consultation_messages;
create trigger notify_consultation_reply
  after insert on public.consultation_messages
  for each row execute function private.notify_consultation_reply();

-- ── 트리거: 내 글에 좋아요 / 댓글이 달리면 ──────────────────────────────
create or replace function private.notify_post_like()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_author uuid;
begin
  select user_id into v_author from posts where id = new.post_id;
  -- 자기 글에 자기가 누른 것은 알림이 아니다.
  if v_author is null or v_author = new.user_id then return new; end if;
  perform private.enqueue_push(
    v_author,
    'community_reaction',
    '게시글에 좋아요가 눌렸어요',
    '누군가 회원님의 기록에 반응했어요.',
    jsonb_build_object('postId', new.post_id::text)
  );
  return new;
end;
$$;

drop trigger if exists notify_post_like on public.post_likes;
create trigger notify_post_like
  after insert on public.post_likes
  for each row execute function private.notify_post_like();

create or replace function private.notify_post_comment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_author uuid;
begin
  select user_id into v_author from posts where id = new.post_id;
  if v_author is null or v_author = new.user_id then return new; end if;
  perform private.enqueue_push(
    v_author,
    'community_reaction',
    '새 댓글이 달렸어요',
    coalesce(new.text, '회원님의 기록에 댓글이 달렸어요.'),
    jsonb_build_object('postId', new.post_id::text)
  );
  return new;
end;
$$;

drop trigger if exists notify_post_comment on public.comments;
create trigger notify_post_comment
  after insert on public.comments
  for each row execute function private.notify_post_comment();

-- 초기 스키마의 account_withdrawals는 scope_type/scope_id 기반이고 아무도
-- 참조하지 않는다(0행). 탈퇴의 진실은 account_deletion_requests다 —
-- 다음 사람이 실수로 이쪽에 붙이지 않도록 남긴다.
comment on table public.account_withdrawals is
  'DEPRECATED: 미사용 초기 스키마. 회원 탈퇴는 public.account_deletion_requests를 쓴다.';

commit;
