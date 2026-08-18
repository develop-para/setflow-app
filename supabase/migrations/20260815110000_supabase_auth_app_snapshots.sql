-- Move the Flutter client to Supabase Auth and a user-owned cloud snapshot.
-- Existing normalized domain tables remain available for gradual feature migration.

create table if not exists public.app_state_snapshots (
  user_id uuid primary key references auth.users(id) on delete cascade,
  schema_version smallint not null check (schema_version > 0),
  payload jsonb not null default '{}'::jsonb
    check (jsonb_typeof(payload) = 'object'),
  updated_at timestamptz not null default now()
);

alter table public.app_state_snapshots enable row level security;

revoke all on table public.app_state_snapshots from public, anon;
grant select, insert, update, delete
  on table public.app_state_snapshots to authenticated;

drop policy if exists "app_state_snapshots_select_own"
  on public.app_state_snapshots;
create policy "app_state_snapshots_select_own"
  on public.app_state_snapshots
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists "app_state_snapshots_insert_own"
  on public.app_state_snapshots;
create policy "app_state_snapshots_insert_own"
  on public.app_state_snapshots
  for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

drop policy if exists "app_state_snapshots_update_own"
  on public.app_state_snapshots;
create policy "app_state_snapshots_update_own"
  on public.app_state_snapshots
  for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists "app_state_snapshots_delete_own"
  on public.app_state_snapshots;
create policy "app_state_snapshots_delete_own"
  on public.app_state_snapshots
  for delete
  to authenticated
  using ((select auth.uid()) = user_id);

-- The previous custom-auth prototype removed this relationship. Supabase Auth is
-- authoritative again, so public profile rows follow the auth user lifecycle.
do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.users'::regclass
      and contype = 'f'
      and confrelid = 'auth.users'::regclass
  ) then
    alter table public.users
      add constraint users_id_auth_users_fkey
      foreign key (id) references auth.users(id) on delete cascade;
  end if;
end
$$;

-- Provision public profile records for email and OAuth users. Display metadata is
-- copied for convenience only; authorization never trusts user metadata.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.users (
    id,
    email,
    provider,
    provider_uid,
    nickname,
    avatar_url,
    last_login_at
  )
  values (
    new.id,
    new.email,
    coalesce(new.raw_app_meta_data ->> 'provider', 'email'),
    new.raw_app_meta_data ->> 'provider_id',
    nullif(
      coalesce(
        new.raw_user_meta_data ->> 'nickname',
        new.raw_user_meta_data ->> 'full_name',
        new.raw_user_meta_data ->> 'name'
      ),
      ''
    ),
    nullif(new.raw_user_meta_data ->> 'avatar_url', ''),
    now()
  )
  on conflict (id) do update
  set email = excluded.email,
      provider = excluded.provider,
      provider_uid = excluded.provider_uid,
      nickname = coalesce(public.users.nickname, excluded.nickname),
      avatar_url = coalesce(public.users.avatar_url, excluded.avatar_url),
      last_login_at = excluded.last_login_at,
      updated_at = now();

  insert into public.user_settings(user_id)
  values (new.id)
  on conflict (user_id) do nothing;

  insert into public.user_profiles(user_id)
  values (new.id)
  on conflict (user_id) do nothing;

  insert into public.user_consents(user_id)
  values (new.id)
  on conflict (user_id) do nothing;

  return new;
end;
$$;

revoke all on function public.handle_new_user() from public, anon, authenticated;

-- Tighten the user-owned profile tables used by the Flutter client.
drop policy if exists "own_users" on public.users;
drop policy if exists "upd_users" on public.users;
create policy "users_select_own_or_admin"
  on public.users
  for select
  to authenticated
  using (
    id = (select auth.uid())
    or (select public.is_admin())
  );
create policy "users_update_own"
  on public.users
  for update
  to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

revoke all on table public.users from anon;
revoke insert, update, delete on table public.users from authenticated;
grant select on table public.users to authenticated;
grant update (nickname, avatar_url, is_first_run, last_login_at, updated_at)
  on table public.users to authenticated;

do $policy$
declare
  target_table text;
begin
  foreach target_table in array array[
    'user_settings',
    'user_profiles',
    'user_consents'
  ]
  loop
    execute format('drop policy if exists %I on public.%I',
      'own_' || replace(target_table, 'user_', ''), target_table);
    execute format(
      'create policy %I on public.%I for all to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()))',
      target_table || '_own',
      target_table
    );
    execute format('revoke all on table public.%I from anon', target_table);
    execute format(
      'grant select, insert, update, delete on table public.%I to authenticated',
      target_table
    );
  end loop;
end
$policy$;
