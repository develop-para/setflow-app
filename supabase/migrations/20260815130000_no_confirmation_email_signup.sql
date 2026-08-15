-- Rate-limit the public no-confirmation email signup Edge Function.
-- Only the service role can access this table or reserve a signup attempt.

create table if not exists public.auth_signup_attempts (
  id bigint generated always as identity primary key,
  ip_hash text not null check (length(ip_hash) = 64),
  email_hash text not null check (length(email_hash) = 64),
  attempted_at timestamptz not null default now()
);

create index if not exists auth_signup_attempts_ip_time_idx
  on public.auth_signup_attempts (ip_hash, attempted_at desc);
create index if not exists auth_signup_attempts_email_time_idx
  on public.auth_signup_attempts (email_hash, attempted_at desc);

alter table public.auth_signup_attempts enable row level security;

revoke all on table public.auth_signup_attempts
  from public, anon, authenticated;
grant select, insert, delete on table public.auth_signup_attempts
  to service_role;

create or replace function public.reserve_email_signup_attempt(
  p_ip_hash text,
  p_email_hash text
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  recent_email_attempts integer;
  recent_ip_attempts integer;
begin
  if length(p_ip_hash) <> 64 or length(p_email_hash) <> 64 then
    raise exception 'Invalid signup rate-limit key';
  end if;

  -- Serialize requests that share an email or IP so concurrent requests cannot
  -- race past either quota.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('email:' || p_email_hash, 0)
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('ip:' || p_ip_hash, 0)
  );

  delete from public.auth_signup_attempts
  where attempted_at < pg_catalog.now() - interval '24 hours';

  select count(*)
  into recent_email_attempts
  from public.auth_signup_attempts
  where email_hash = p_email_hash
    and attempted_at >= pg_catalog.now() - interval '1 hour';

  if recent_email_attempts >= 3 then
    return 'email_limit';
  end if;

  select count(*)
  into recent_ip_attempts
  from public.auth_signup_attempts
  where ip_hash = p_ip_hash
    and attempted_at >= pg_catalog.now() - interval '1 hour';

  if recent_ip_attempts >= 10 then
    return 'ip_limit';
  end if;

  insert into public.auth_signup_attempts (ip_hash, email_hash)
  values (p_ip_hash, p_email_hash);

  return 'allowed';
end;
$$;

revoke all on function public.reserve_email_signup_attempt(text, text)
  from public, anon, authenticated;
grant execute on function public.reserve_email_signup_attempt(text, text)
  to service_role;
