alter table public.users
  drop constraint if exists users_id_fkey;

alter table public.users
  alter column id set default gen_random_uuid();

alter table public.users
  add column if not exists last_login_at timestamptz;

create unique index if not exists users_provider_identity_key
  on public.users (provider, provider_uid)
  where provider is not null and provider_uid is not null;

create table if not exists public.user_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  access_token_hash text not null unique,
  refresh_token_hash text not null unique,
  access_expires_at timestamptz not null,
  refresh_expires_at timestamptz not null,
  user_agent text,
  ip text,
  created_at timestamptz not null default now(),
  last_used_at timestamptz not null default now(),
  revoked_at timestamptz,
  constraint user_sessions_access_expiry_check
    check (access_expires_at > created_at),
  constraint user_sessions_refresh_expiry_check
    check (refresh_expires_at > access_expires_at)
);

create index if not exists idx_user_sessions_user_active
  on public.user_sessions (user_id, refresh_expires_at)
  where revoked_at is null;

alter table public.user_sessions enable row level security;

revoke all on table public.user_sessions from anon, authenticated;
grant select, insert, update, delete on table public.user_sessions to service_role;

comment on table public.user_sessions is
  'Custom application sessions. Token values are never stored; only SHA-256 hashes are persisted.';
