begin;

-- 회원 탈퇴 — 앱 안에서 끝나야 하는 경로.
--
-- 스토어 심사는 "계정을 만든 곳에서 지울 수 있는가"를 본다. 그래서 메일 문의로
-- 넘기지 않고 여기서 요청을 받는다. 즉시 삭제가 아니라 **30일 유예**인 이유는
-- 둘이다: 실수로 누른 사람에게 되돌릴 시간을 주고, 트레이너에게 붙어 있는
-- 상담·정산 같은 남의 기록을 갑자기 끊지 않기 위해서다. 화면에 적은 30일과
-- 여기 적힌 30일은 같은 숫자여야 한다.
--
-- 실제 파기는 이 테이블을 읽는 운영 배치의 몫이고, 앱은 요청과 취소만 한다.
-- 앱이 직접 auth.users를 지우지 않는 이유: 그 순간 세션이 죽어 취소할 방법이
-- 사라지고, 유예 기간이라는 약속이 거짓말이 된다.

create table if not exists public.account_deletion_requests (
  user_id uuid primary key references auth.users(id) on delete cascade,
  reason text check (reason is null or char_length(reason) <= 500),
  requested_at timestamptz not null default now(),
  purge_after timestamptz not null,
  cancelled_at timestamptz,
  -- 파기 배치가 처리한 시각. 이 값이 차면 되돌릴 수 없다.
  purged_at timestamptz
);

create index if not exists account_deletion_requests_due_idx
  on public.account_deletion_requests (purge_after)
  where cancelled_at is null and purged_at is null;

alter table public.account_deletion_requests enable row level security;

revoke all on table public.account_deletion_requests from public, anon;
-- 읽기만 직접 허용한다. 쓰기는 아래 RPC를 통해서만 — 유예 기간 계산이 한 곳에
-- 있어야 화면과 서버가 다른 날짜를 말하지 않는다.
grant select on table public.account_deletion_requests to authenticated;

drop policy if exists "account_deletion_requests_select_own"
  on public.account_deletion_requests;
create policy "account_deletion_requests_select_own"
  on public.account_deletion_requests
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

create or replace function public.request_account_deletion(
  p_reason text default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_row account_deletion_requests;
begin
  if v_user is null then
    raise exception 'authentication required';
  end if;

  insert into account_deletion_requests as target
    (user_id, reason, requested_at, purge_after, cancelled_at, purged_at)
  values
    (v_user, nullif(btrim(coalesce(p_reason, '')), ''), now(), now() + interval '30 days', null, null)
  on conflict (user_id) do update
    -- 이미 파기된 계정은 다시 열지 않는다.
    set reason = excluded.reason,
        requested_at = excluded.requested_at,
        purge_after = excluded.purge_after,
        cancelled_at = null
    where target.purged_at is null
  returning * into v_row;

  if v_row is null then
    raise exception 'account already purged';
  end if;

  return jsonb_build_object(
    'requestedAt', v_row.requested_at,
    'purgeAfter', v_row.purge_after,
    'reason', v_row.reason
  );
end;
$$;

revoke all on function public.request_account_deletion(text) from public, anon;
grant execute on function public.request_account_deletion(text) to authenticated;

create or replace function public.cancel_account_deletion()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_row account_deletion_requests;
begin
  if v_user is null then
    raise exception 'authentication required';
  end if;

  update account_deletion_requests
    set cancelled_at = now()
    where user_id = v_user and purged_at is null and cancelled_at is null
    returning * into v_row;

  -- 취소할 것이 없는 것은 오류가 아니다 — 이미 원하는 상태다.
  return jsonb_build_object('cancelled', v_row is not null);
end;
$$;

revoke all on function public.cancel_account_deletion() from public, anon;
grant execute on function public.cancel_account_deletion() to authenticated;

commit;
