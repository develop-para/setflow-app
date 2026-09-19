-- Only for the disposable in-memory database in test_workspace_access.mjs.
-- The production migration is tested unchanged against this minimal schema.
create role anon;
create role authenticated;
create role service_role bypassrls;
create role authenticator;
create schema auth;
create schema private;
create schema storage;
grant usage on schema public, auth, storage to anon, authenticated, service_role;

create function auth.jwt() returns jsonb language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb;
$$;
create function auth.uid() returns uuid language sql stable as $$
  select nullif(auth.jwt() ->> 'sub', '')::uuid;
$$;
create table auth.users (
  id uuid primary key, banned_until timestamptz, deleted_at timestamptz,
  is_anonymous boolean default false
);
create table auth.sessions (
  id uuid primary key, user_id uuid references auth.users, not_after timestamptz
);
create table public.users (
  id uuid primary key references auth.users, email text, role text, status text
);
create table public.trainers (
  id uuid primary key, user_id uuid references auth.users, status text
);
create table public.gyms (
  id uuid primary key, owner_user_id uuid references auth.users, status text
);
create table public.admin_users (user_id uuid references auth.users, status text);
create table public.trainer_applications (
  id uuid primary key, user_id uuid references auth.users,
  submitted_at timestamptz, status text
);
create table public.gym_applications (
  id uuid primary key, owner_user_id uuid references auth.users,
  submitted_at timestamptz, status text
);
create table public.coaching_routines (
  id uuid primary key, trainer_id uuid references public.trainers,
  gym_id uuid references public.gyms, status text default 'draft'
);
create table storage.objects (id uuid primary key, owner_id uuid);
create table public.rpc_only (id int);

create function private.get_my_trainer_profile() returns jsonb
language sql security definer set search_path = '' as $$
  select to_jsonb(t) from public.trainers t where user_id = auth.uid() limit 1;
$$;
create function private.get_my_gym_profile() returns jsonb
language sql security definer set search_path = '' as $$
  select to_jsonb(g) from public.gyms g where owner_user_id = auth.uid() limit 1;
$$;
create function private.is_admin() returns boolean
language sql security definer set search_path = '' as $$
  select exists(select 1 from public.admin_users where user_id = auth.uid() and status = 'active');
$$;

alter table public.users enable row level security;
alter table public.coaching_routines enable row level security;
alter table public.rpc_only enable row level security;
alter table storage.objects enable row level security;
grant select on public.users, public.rpc_only to authenticated;
grant select, insert, update, delete on public.coaching_routines, storage.objects to authenticated;
grant select on public.coaching_routines to anon;
create policy own_user on public.users for select to authenticated using (id = auth.uid());
create policy public_routines on public.coaching_routines for select to anon using (status = 'approved');
-- Deliberately permissive ownership policy: the new restrictive policy must
-- enforce approval independently, including for crafted direct table requests.
create policy own_routines on public.coaching_routines for all to authenticated
using (exists(select 1 from public.trainers t where t.id = trainer_id and t.user_id = auth.uid()))
with check (exists(select 1 from public.trainers t where t.id = trainer_id and t.user_id = auth.uid()));
grant select on public.trainers to authenticated;
create policy own_storage on storage.objects for all to authenticated
using (owner_id = auth.uid()) with check (owner_id = auth.uid());

insert into auth.users(id) values
  ('10000000-0000-4000-8000-000000000001'),
  ('10000000-0000-4000-8000-000000000002');
insert into auth.sessions(id,user_id) values
  ('20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001'),
  ('20000000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000002');
insert into public.users values
  ('10000000-0000-4000-8000-000000000001','a@example.test','general','active'),
  ('10000000-0000-4000-8000-000000000002','b@example.test','general','active');
insert into public.trainers values
  ('30000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','approved');
insert into public.gyms values
  ('40000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','verified');
insert into public.trainer_applications values
  ('50000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001',now(),'approved');
insert into storage.objects values
  ('60000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001'),
  ('60000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000002');
insert into public.rpc_only values (1);
