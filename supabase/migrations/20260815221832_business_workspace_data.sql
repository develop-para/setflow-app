-- Business workspaces: trainer and gym data, authorization, and bounded RPCs.
-- This migration intentionally alters the existing business tables. It does not
-- create replacement copies of the production tables or seed user-owned data.

begin;

create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated, service_role;

alter table public.coaching_routines
  add column if not exists gym_id uuid;

alter table public.members
  add column if not exists goal text,
  add column if not exists completion_rate numeric(5, 2) not null default 0,
  add column if not exists last_activity_at timestamptz;

alter table public.consultations
  add column if not exists requester_name text,
  add column if not exists specialty text;

alter table public.trainer_certifications
  add column if not exists credential_number text,
  add column if not exists issuer text,
  add column if not exists issued_on date,
  add column if not exists expires_on date,
  add column if not exists verification_status text not null default 'submitted',
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now();

alter table public.trainer_applications
  add column if not exists reviewed_at timestamptz,
  add column if not exists updated_at timestamptz not null default now();

alter table public.gym_applications
  add column if not exists reviewed_at timestamptz,
  add column if not exists updated_at timestamptz not null default now();

do $constraints$
begin
  if not exists (
    select 1
    from pg_catalog.pg_constraint c
    where c.conrelid = 'public.coaching_routines'::regclass
      and c.contype = 'f'
      and c.conkey = array[
        (select a.attnum
         from pg_catalog.pg_attribute a
         where a.attrelid = 'public.coaching_routines'::regclass
           and a.attname = 'gym_id')
      ]::smallint[]
  ) then
    alter table public.coaching_routines
      add constraint coaching_routines_gym_id_fkey
      foreign key (gym_id) references public.gyms(id) on delete cascade;
  end if;

  if not exists (
    select 1 from pg_catalog.pg_constraint
    where conrelid = 'public.coaching_routines'::regclass
      and conname = 'coaching_routines_single_business_author'
  ) then
    alter table public.coaching_routines
      add constraint coaching_routines_single_business_author
      check (num_nonnulls(trainer_id, gym_id) <= 1);
  end if;

  if not exists (
    select 1 from pg_catalog.pg_constraint
    where conrelid = 'public.members'::regclass
      and conname = 'members_completion_rate_range'
  ) then
    alter table public.members
      add constraint members_completion_rate_range
      check (completion_rate between 0 and 100);
  end if;

  if not exists (
    select 1 from pg_catalog.pg_constraint
    where conrelid = 'public.trainer_certifications'::regclass
      and conname = 'trainer_certifications_verification_status_check'
  ) then
    alter table public.trainer_certifications
      add constraint trainer_certifications_verification_status_check
      check (verification_status in ('submitted', 'approved', 'rejected'));
  end if;

  if not exists (
    select 1 from pg_catalog.pg_constraint
    where conrelid = 'public.trainer_certifications'::regclass
      and conname = 'trainer_certifications_date_order'
  ) then
    alter table public.trainer_certifications
      add constraint trainer_certifications_date_order
      check (expires_on is null or issued_on is null or expires_on >= issued_on);
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_constraint c
    where c.conrelid = 'public.gym_applications'::regclass
      and c.contype = 'f'
      and c.conkey = array[
        (select a.attnum
         from pg_catalog.pg_attribute a
         where a.attrelid = 'public.gym_applications'::regclass
           and a.attname = 'owner_user_id')
      ]::smallint[]
  ) then
    alter table public.gym_applications
      add constraint gym_applications_owner_user_id_fkey
      foreign key (owner_user_id) references public.users(id) on delete cascade;
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_constraint c
    where c.conrelid = 'public.consultation_messages'::regclass
      and c.contype = 'f'
      and c.conkey = array[
        (select a.attnum
         from pg_catalog.pg_attribute a
         where a.attrelid = 'public.consultation_messages'::regclass
           and a.attname = 'sender_id')
      ]::smallint[]
  ) then
    alter table public.consultation_messages
      add constraint consultation_messages_sender_id_fkey
      foreign key (sender_id) references public.users(id) on delete cascade;
  end if;
end
$constraints$;

-- The reviewer may be an admin account rather than a public user role row.
do $reviewer_foreign_keys$
begin
  if not exists (
    select 1
    from pg_catalog.pg_constraint c
    where c.conrelid = 'public.trainer_applications'::regclass
      and c.contype = 'f'
      and c.conkey = array[
        (select a.attnum from pg_catalog.pg_attribute a
         where a.attrelid = 'public.trainer_applications'::regclass
           and a.attname = 'reviewer_id')
      ]::smallint[]
  ) then
    alter table public.trainer_applications
      add constraint trainer_applications_reviewer_id_fkey
      foreign key (reviewer_id) references public.admin_users(id) on delete set null;
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_constraint c
    where c.conrelid = 'public.gym_applications'::regclass
      and c.contype = 'f'
      and c.conkey = array[
        (select a.attnum from pg_catalog.pg_attribute a
         where a.attrelid = 'public.gym_applications'::regclass
           and a.attname = 'reviewer_id')
      ]::smallint[]
  ) then
    alter table public.gym_applications
      add constraint gym_applications_reviewer_id_fkey
      foreign key (reviewer_id) references public.admin_users(id) on delete set null;
  end if;
end
$reviewer_foreign_keys$;

-- One live application/assignment per subject. These partial indexes also make
-- the RPC lock/update paths deterministic.
create unique index if not exists trainer_applications_one_pending_per_user
  on public.trainer_applications (user_id)
  where status = 'pending' and user_id is not null;
create unique index if not exists gym_applications_one_pending_per_gym
  on public.gym_applications (gym_id)
  where status = 'pending' and gym_id is not null;
create unique index if not exists member_assignments_one_active_per_member
  on public.member_assignments (member_id)
  where active;

create index if not exists coaching_routines_gym_id_idx
  on public.coaching_routines (gym_id);
create index if not exists trainer_applications_user_status_idx
  on public.trainer_applications (user_id, status);
create index if not exists gym_applications_owner_status_idx
  on public.gym_applications (owner_user_id, status);
create index if not exists trainer_certifications_trainer_id_idx
  on public.trainer_certifications (trainer_id);
create unique index if not exists trainer_certifications_credential_unique
  on public.trainer_certifications (trainer_id, credential_number)
  where credential_number is not null;
create index if not exists trainer_documents_application_id_idx
  on public.trainer_documents (application_id);
create index if not exists gym_documents_application_id_idx
  on public.gym_documents (application_id);
create index if not exists gym_trainers_trainer_id_idx
  on public.gym_trainers (trainer_id);
create index if not exists members_user_id_idx
  on public.members (user_id);
create index if not exists member_assignments_gym_id_idx
  on public.member_assignments (gym_id);
create index if not exists member_assignments_trainer_id_idx
  on public.member_assignments (trainer_id);
create index if not exists consultations_user_created_idx
  on public.consultations (user_id, created_at desc);
create index if not exists consultations_gym_status_created_idx
  on public.consultations (gym_id, status, created_at desc);
create index if not exists consultations_trainer_status_idx
  on public.consultations (trainer_id, status);
create index if not exists consultations_assigned_trainer_status_idx
  on public.consultations (assigned_trainer_id, status);
create index if not exists consultation_messages_consultation_created_idx
  on public.consultation_messages (consultation_id, created_at);

-- Aggregate each one-to-many relation before joining it to the gym. The old
-- view multiplied settlement amounts by member and trainer fan-out.
create or replace view public.v_gym_settlement_summary
with (security_invoker = true)
as
with settlement_totals as (
  select si.gym_id, sum(si.amount) as total_revenue
  from public.settlement_items si
  group by si.gym_id
), member_totals as (
  select m.gym_id, count(*) as member_count
  from public.members m
  group by m.gym_id
), trainer_totals as (
  select gt.gym_id, count(*) as trainer_count
  from public.gym_trainers gt
  group by gt.gym_id
)
select
  g.id as gym_id,
  g.name,
  coalesce(st.total_revenue, 0::numeric) as total_revenue,
  coalesce(mt.member_count, 0::bigint) as member_count,
  coalesce(tt.trainer_count, 0::bigint) as trainer_count
from public.gyms g
left join settlement_totals st on st.gym_id = g.id
left join member_totals mt on mt.gym_id = g.id
left join trainer_totals tt on tt.gym_id = g.id;

create or replace view public.v_trainer_dashboard
with (security_invoker = true)
as
select
  t.id as trainer_id,
  t.user_id,
  t.status,
  (
    select count(*)
    from public.consultations c
    where (c.trainer_id = t.id or c.assigned_trainer_id = t.id)
      and not c.is_read
  ) as unread_consults,
  (
    select count(*)
    from public.member_assignments ma
    where ma.trainer_id = t.id
      and ma.active
  ) as active_members,
  (
    select coalesce(sum(s.net_amount), 0::numeric)
    from public.settlements s
    where s.trainer_id = t.id
      and s.status = 'pending'
  ) as pending_settlement,
  (
    select coalesce(sum(s.net_amount), 0::numeric)
    from public.settlements s
    where s.trainer_id = t.id
      and s.status = 'paid'
      and date_trunc('month', s.settlement_date::timestamptz)
        = date_trunc('month', current_date::timestamptz)
  ) as month_settled,
  (
    select count(*)
    from public.coaching_feedbacks f
    join public.coaching_logs l on l.id = f.log_id
    where f.trainer_id = t.id
      and f.content is null
      and f.due_at < now()
  ) as overdue_feedbacks
from public.trainers t;

revoke all on table public.v_gym_settlement_summary
  from public, anon, authenticated;
revoke all on table public.v_trainer_dashboard
  from public, anon, authenticated;
grant select on table public.v_gym_settlement_summary,
  public.v_trainer_dashboard to authenticated, service_role;

-- Capture a stable requester display name for business workspaces without
-- broadening the users-table RLS policy to expose other members' accounts.
create or replace function private.set_consultation_requester_identity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := auth.uid();
  v_requester_name text;
begin
  -- Trusted server operations may provide their own snapshot. Data API clients
  -- cannot insert anonymously and authenticated requests always have a uid.
  if v_user_id is null then
    return new;
  end if;
  if new.user_id is distinct from v_user_id then
    raise exception using errcode = '42501', message = 'Consultation requester mismatch';
  end if;

  select coalesce(nullif(btrim(u.nickname), ''), '회원')
    into v_requester_name
  from public.users u
  where u.id = v_user_id;
  if not found then
    raise exception using errcode = '23503', message = 'User profile is not ready';
  end if;

  new.requester_name := v_requester_name;
  return new;
end
$function$;

revoke all on function private.set_consultation_requester_identity()
  from public, anon, authenticated;
grant execute on function private.set_consultation_requester_identity()
  to service_role;

drop trigger if exists consultations_set_requester_identity
  on public.consultations;
create trigger consultations_set_requester_identity
before insert on public.consultations
for each row execute function private.set_consultation_requester_identity();

-- These helpers keep membership checks out of mutually-referencing RLS
-- policies. They are private, row-scoped, and derive identity from the JWT.
create or replace function private.can_access_business_member(p_member_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select (select auth.uid()) is not null
    and (
      exists (
        select 1
        from public.members m
        where m.id = p_member_id
          and m.user_id = (select auth.uid())
      )
      or exists (
        select 1
        from public.members m
        join public.gyms g on g.id = m.gym_id
        where m.id = p_member_id
          and g.owner_user_id = (select auth.uid())
      )
      or exists (
        select 1
        from public.member_assignments ma
        join public.trainers t on t.id = ma.trainer_id
        where ma.member_id = p_member_id
          and ma.active
          and t.user_id = (select auth.uid())
      )
      or exists (
        select 1
        from public.admin_users au
        where au.user_id = (select auth.uid())
          and au.status = 'active'
      )
    );
$function$;

create or replace function private.can_access_business_consultation(
  p_consultation_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select (select auth.uid()) is not null
    and exists (
      select 1
      from public.consultations c
      where c.id = p_consultation_id
        and (
          c.user_id = (select auth.uid())
          or exists (
            select 1 from public.trainers t
            where t.id in (c.trainer_id, c.assigned_trainer_id)
              and t.user_id = (select auth.uid())
          )
          or exists (
            select 1 from public.gyms g
            where g.id = c.gym_id
              and g.owner_user_id = (select auth.uid())
          )
          or exists (
            select 1 from public.gym_trainers gt
            where gt.gym_id = c.gym_id
              and gt.trainer_user_id = (select auth.uid())
              and gt.status = 'active'
          )
          or exists (
            select 1 from public.admin_users au
            where au.user_id = (select auth.uid())
              and au.status = 'active'
          )
        )
    );
$function$;

revoke all on function private.can_access_business_member(uuid)
  from public, anon;
revoke all on function private.can_access_business_consultation(uuid)
  from public, anon;
grant execute on function private.can_access_business_member(uuid)
  to authenticated, service_role;
grant execute on function private.can_access_business_consultation(uuid)
  to authenticated, service_role;

-- Replace permissive legacy policies in one deterministic pass. The table
-- list is deliberately bounded to the business workspace surface.
do $drop_business_policies$
declare
  policy_row record;
begin
  for policy_row in
    select schemaname, tablename, policyname
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = any (array[
        'trainers', 'trainer_applications', 'trainer_certifications',
        'trainer_documents', 'trainer_experiences', 'trainer_badges',
        'trainer_plans', 'gyms', 'gym_applications', 'gym_documents',
        'gym_subscriptions', 'gym_trainers', 'members',
        'member_assignments', 'consultations', 'consultation_messages',
        'coaching_routines', 'coaching_routine_exercises',
        'coaching_routine_sets'
      ])
  loop
    execute format(
      'drop policy if exists %I on %I.%I',
      policy_row.policyname,
      policy_row.schemaname,
      policy_row.tablename
    );
  end loop;
end
$drop_business_policies$;

alter table public.trainers enable row level security;
alter table public.trainer_applications enable row level security;
alter table public.trainer_certifications enable row level security;
alter table public.trainer_documents enable row level security;
alter table public.trainer_experiences enable row level security;
alter table public.trainer_badges enable row level security;
alter table public.trainer_plans enable row level security;
alter table public.gyms enable row level security;
alter table public.gym_applications enable row level security;
alter table public.gym_documents enable row level security;
alter table public.gym_subscriptions enable row level security;
alter table public.gym_trainers enable row level security;
alter table public.members enable row level security;
alter table public.member_assignments enable row level security;
alter table public.consultations enable row level security;
alter table public.consultation_messages enable row level security;
alter table public.coaching_routines enable row level security;
alter table public.coaching_routine_exercises enable row level security;
alter table public.coaching_routine_sets enable row level security;

-- Explicit Data API privileges. Approval, verification, billing, badge, and
-- document-review fields are omitted from all client write grants.
revoke all on table public.trainers from public, anon, authenticated;
revoke all on table public.trainer_applications from public, anon, authenticated;
revoke all on table public.trainer_certifications from public, anon, authenticated;
revoke all on table public.trainer_documents from public, anon, authenticated;
revoke all on table public.trainer_experiences from public, anon, authenticated;
revoke all on table public.trainer_badges from public, anon, authenticated;
revoke all on table public.trainer_plans from public, anon, authenticated;
revoke all on table public.gyms from public, anon, authenticated;
revoke all on table public.gym_applications from public, anon, authenticated;
revoke all on table public.gym_documents from public, anon, authenticated;
revoke all on table public.gym_subscriptions from public, anon, authenticated;
revoke all on table public.gym_trainers from public, anon, authenticated;
revoke all on table public.members from public, anon, authenticated;
revoke all on table public.member_assignments from public, anon, authenticated;
revoke all on table public.consultations from public, anon, authenticated;
revoke all on table public.consultation_messages from public, anon, authenticated;
revoke all on table public.coaching_routines from public, anon, authenticated;
revoke all on table public.coaching_routine_exercises from public, anon, authenticated;
revoke all on table public.coaching_routine_sets from public, anon, authenticated;

grant select (
  id, display_name, keyword, intro, profile_image_url, career_years,
  center_name, rating_avg, post_count, coaching_total, is_public,
  verified_badge, status, created_at, updated_at
) on public.trainers to anon;
grant select (id, trainer_id, title)
  on public.trainer_certifications to anon;
grant select (id, trainer_id, text, order_index)
  on public.trainer_experiences to anon;
grant select (id, trainer_id, badge_type, name, verified, verified_at)
  on public.trainer_badges to anon;
grant select (
  id, name, rep_name, gym_type, address, description, cover_image_url,
  plan_tier, status, created_at, updated_at
) on public.gyms to anon;
grant select on table public.coaching_routines,
  public.coaching_routine_exercises, public.coaching_routine_sets to anon;

grant select on table public.trainers, public.trainer_applications,
  public.trainer_certifications, public.trainer_documents,
  public.trainer_experiences, public.trainer_badges, public.trainer_plans,
  public.gyms, public.gym_applications, public.gym_documents,
  public.gym_subscriptions, public.gym_trainers, public.members,
  public.member_assignments, public.consultations,
  public.consultation_messages, public.coaching_routines,
  public.coaching_routine_exercises, public.coaching_routine_sets
  to authenticated;

grant update (
  display_name, keyword, intro, profile_image_url, career_years, center_name,
  is_public, updated_at
) on public.trainers to authenticated;
grant insert (trainer_id, title, credential_number, issuer, issued_on, expires_on),
  update (title, credential_number, issuer, issued_on, expires_on, updated_at),
  delete on public.trainer_certifications to authenticated;
grant insert (trainer_id, doc_type, file_path, application_id),
  update (doc_type, file_path), delete
  on public.trainer_documents to authenticated;
grant insert (trainer_id, text, order_index),
  update (text, order_index), delete
  on public.trainer_experiences to authenticated;
grant update (
  name, rep_name, gym_type, address, description, cover_image_url, updated_at
) on public.gyms to authenticated;
grant insert (gym_id, doc_type, file_url, file_size, mime_type, application_id),
  update (doc_type, file_url, file_size, mime_type), delete
  on public.gym_documents to authenticated;
grant insert (
  gym_id, user_id, name, phone, remaining_pt_sessions, goal,
  completion_rate, last_activity_at
), update (
  name, phone, remaining_pt_sessions, goal, completion_rate, last_activity_at
), delete on public.members to authenticated;
grant insert (
  user_id, trainer_id, gym_id, routine_id, specialty,
  goal, level, question, status, is_read
) on public.consultations to authenticated;
grant insert (consultation_id, sender_type, sender_id, text)
  on public.consultation_messages to authenticated;
grant insert (trainer_id, gym_id, title, intro, price, difficulty, status),
  update (title, intro, price, difficulty, status, updated_at), delete
  on public.coaching_routines to authenticated;
grant insert, update, delete on table public.coaching_routine_exercises
  to authenticated;
grant insert, update, delete on table public.coaching_routine_sets
  to authenticated;

grant all on table public.trainers, public.trainer_applications,
  public.trainer_certifications, public.trainer_documents,
  public.trainer_experiences, public.trainer_badges, public.trainer_plans,
  public.gyms, public.gym_applications, public.gym_documents,
  public.gym_subscriptions, public.gym_trainers, public.members,
  public.member_assignments, public.consultations,
  public.consultation_messages, public.coaching_routines,
  public.coaching_routine_exercises, public.coaching_routine_sets
  to service_role;

-- Public business directory. Pending/rejected profiles remain visible only to
-- their owner, associated center, or an active admin.
create policy trainers_public_directory
  on public.trainers for select to anon
  using (status = 'approved' and is_public);
create policy trainers_authenticated_directory
  on public.trainers for select to authenticated
  using (
    (status = 'approved' and is_public)
    or user_id = (select auth.uid())
    or exists (
      select 1 from public.gym_trainers gt
      where gt.trainer_id = trainers.id
        and gt.status = 'active'
        and (select public.owns_gym(gt.gym_id))
    )
    or (select public.is_admin())
  );
create policy trainers_owner_safe_update
  on public.trainers for update to authenticated
  using (user_id = (select auth.uid()) or (select public.is_admin()))
  with check (user_id = (select auth.uid()) or (select public.is_admin()));

create policy gyms_public_directory
  on public.gyms for select to anon
  using (status = 'verified');
create policy gyms_authenticated_directory
  on public.gyms for select to authenticated
  using (
    status = 'verified'
    or owner_user_id = (select auth.uid())
    or exists (
      select 1 from public.gym_trainers gt
      where gt.gym_id = gyms.id
        and gt.trainer_user_id = (select auth.uid())
        and gt.status = 'active'
    )
    or (select public.is_admin())
  );
create policy gyms_owner_safe_update
  on public.gyms for update to authenticated
  using (owner_user_id = (select auth.uid()) or (select public.is_admin()))
  with check (owner_user_id = (select auth.uid()) or (select public.is_admin()));

-- Applications are submitted and reviewed only through bounded RPCs.
create policy trainer_applications_applicant_read
  on public.trainer_applications for select to authenticated
  using (user_id = (select auth.uid()) or (select public.is_admin()));
create policy gym_applications_applicant_read
  on public.gym_applications for select to authenticated
  using (owner_user_id = (select auth.uid()) or (select public.is_admin()));

create policy trainer_certifications_public_read
  on public.trainer_certifications for select to anon
  using (
    verification_status = 'approved'
    and exists (
      select 1 from public.trainers t
      where t.id = trainer_certifications.trainer_id
        and t.status = 'approved'
        and t.is_public
    )
  );
create policy trainer_certifications_authenticated_read
  on public.trainer_certifications for select to authenticated
  using (
    verification_status = 'approved'
    or (select public.owns_trainer(trainer_id))
    or (select public.is_admin())
  );
create policy trainer_certifications_owner_insert
  on public.trainer_certifications for insert to authenticated
  with check (
    (select public.owns_trainer(trainer_id))
    and verification_status = 'submitted'
  );
create policy trainer_certifications_owner_update
  on public.trainer_certifications for update to authenticated
  using (
    ((select public.owns_trainer(trainer_id)) and verification_status = 'submitted')
    or (select public.is_admin())
  )
  with check (
    ((select public.owns_trainer(trainer_id)) and verification_status = 'submitted')
    or (select public.is_admin())
  );
create policy trainer_certifications_owner_delete
  on public.trainer_certifications for delete to authenticated
  using (
    ((select public.owns_trainer(trainer_id)) and verification_status = 'submitted')
    or (select public.is_admin())
  );

create policy trainer_experiences_public_read
  on public.trainer_experiences for select to anon
  using (
    exists (
      select 1 from public.trainers t
      where t.id = trainer_experiences.trainer_id
        and t.status = 'approved'
        and t.is_public
    )
  );
create policy trainer_experiences_authenticated_read
  on public.trainer_experiences for select to authenticated
  using (
    (select public.owns_trainer(trainer_id))
    or exists (
      select 1 from public.trainers t
      where t.id = trainer_experiences.trainer_id
        and t.status = 'approved'
        and t.is_public
    )
    or (select public.is_admin())
  );
create policy trainer_experiences_owner_insert
  on public.trainer_experiences for insert to authenticated
  with check ((select public.owns_trainer(trainer_id)) or (select public.is_admin()));
create policy trainer_experiences_owner_update
  on public.trainer_experiences for update to authenticated
  using ((select public.owns_trainer(trainer_id)) or (select public.is_admin()))
  with check ((select public.owns_trainer(trainer_id)) or (select public.is_admin()));
create policy trainer_experiences_owner_delete
  on public.trainer_experiences for delete to authenticated
  using ((select public.owns_trainer(trainer_id)) or (select public.is_admin()));

create policy trainer_badges_public_read
  on public.trainer_badges for select to anon
  using (
    verified
    and exists (
      select 1 from public.trainers t
      where t.id = trainer_badges.trainer_id
        and t.status = 'approved'
        and t.is_public
    )
  );
create policy trainer_badges_authenticated_read
  on public.trainer_badges for select to authenticated
  using (verified or (select public.owns_trainer(trainer_id)) or (select public.is_admin()));

create policy trainer_documents_owner_read
  on public.trainer_documents for select to authenticated
  using (
    (select public.owns_trainer(trainer_id))
    or exists (
      select 1 from public.trainer_applications a
      where a.id = trainer_documents.application_id
        and a.user_id = (select auth.uid())
    )
    or (select public.is_admin())
  );
create policy trainer_documents_owner_insert
  on public.trainer_documents for insert to authenticated
  with check (
    review_status = 'submitted'
    and (select public.owns_trainer(trainer_id))
    and (
      application_id is null
      or exists (
        select 1 from public.trainer_applications a
        where a.id = trainer_documents.application_id
          and a.user_id = (select auth.uid())
          and a.trainer_id = trainer_documents.trainer_id
      )
    )
  );
create policy trainer_documents_owner_update
  on public.trainer_documents for update to authenticated
  using ((select public.owns_trainer(trainer_id)) and review_status = 'submitted')
  with check ((select public.owns_trainer(trainer_id)) and review_status = 'submitted');
create policy trainer_documents_owner_delete
  on public.trainer_documents for delete to authenticated
  using ((select public.owns_trainer(trainer_id)) and review_status = 'submitted');

create policy trainer_plans_owner_read
  on public.trainer_plans for select to authenticated
  using ((select public.owns_trainer(trainer_id)) or (select public.is_admin()));

create policy gym_documents_owner_read
  on public.gym_documents for select to authenticated
  using ((select public.owns_gym(gym_id)) or (select public.is_admin()));
create policy gym_documents_owner_insert
  on public.gym_documents for insert to authenticated
  with check (
    status = 'submitted'
    and (select public.owns_gym(gym_id))
    and (
      application_id is null
      or exists (
        select 1 from public.gym_applications a
        where a.id = gym_documents.application_id
          and a.owner_user_id = (select auth.uid())
          and a.gym_id = gym_documents.gym_id
      )
    )
  );
create policy gym_documents_owner_update
  on public.gym_documents for update to authenticated
  using ((select public.owns_gym(gym_id)) and status = 'submitted')
  with check ((select public.owns_gym(gym_id)) and status = 'submitted');
create policy gym_documents_owner_delete
  on public.gym_documents for delete to authenticated
  using ((select public.owns_gym(gym_id)) and status = 'submitted');

create policy gym_subscriptions_owner_read
  on public.gym_subscriptions for select to authenticated
  using ((select public.owns_gym(gym_id)) or (select public.is_admin()));
create policy gym_trainers_workspace_read
  on public.gym_trainers for select to authenticated
  using (
    (select public.owns_gym(gym_id))
    or trainer_user_id = (select auth.uid())
    or (select public.owns_trainer(trainer_id))
    or (select public.is_admin())
  );

create policy members_workspace_read
  on public.members for select to authenticated
  using ((select private.can_access_business_member(id)));
create policy members_center_insert
  on public.members for insert to authenticated
  with check ((select public.owns_gym(gym_id)) or (select public.is_admin()));
create policy members_center_update
  on public.members for update to authenticated
  using ((select public.owns_gym(gym_id)) or (select public.is_admin()))
  with check ((select public.owns_gym(gym_id)) or (select public.is_admin()));
create policy members_center_delete
  on public.members for delete to authenticated
  using ((select public.owns_gym(gym_id)) or (select public.is_admin()));
create policy member_assignments_workspace_read
  on public.member_assignments for select to authenticated
  using ((select private.can_access_business_member(member_id)));

create policy consultations_participant_read
  on public.consultations for select to authenticated
  using ((select private.can_access_business_consultation(id)));
create policy consultations_requester_insert
  on public.consultations for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and status = 'pending'
    and assigned_trainer_id is null
    and not is_read
    and num_nonnulls(trainer_id, gym_id) = 1
    and (
      trainer_id is null
      or exists (
        select 1 from public.trainers t
        where t.id = consultations.trainer_id
          and t.status = 'approved'
          and t.is_public
      )
    )
    and (
      gym_id is null
      or exists (
        select 1 from public.gyms g
        where g.id = consultations.gym_id
          and g.status = 'verified'
      )
    )
  );
create policy consultation_messages_participant_read
  on public.consultation_messages for select to authenticated
  using ((select private.can_access_business_consultation(consultation_id)));
create policy consultation_messages_requester_insert
  on public.consultation_messages for insert to authenticated
  with check (
    sender_type = 'user'
    and sender_id = (select auth.uid())
    and exists (
      select 1 from public.consultations c
      where c.id = consultation_messages.consultation_id
        and c.user_id = (select auth.uid())
    )
  );

-- A routine may be trainer-owned, gym-owned, or system-owned (both null).
-- System-owned rows remain readable when approved but are not client-writable.
create policy coaching_routines_public_read
  on public.coaching_routines for select to anon
  using (status = 'approved');
create policy coaching_routines_authenticated_read
  on public.coaching_routines for select to authenticated
  using (
    status = 'approved'
    or (select public.owns_trainer(trainer_id))
    or (select public.owns_gym(gym_id))
    or (select public.is_admin())
  );
create policy coaching_routines_business_insert
  on public.coaching_routines for insert to authenticated
  with check (
    (select public.is_admin())
    or (
      num_nonnulls(trainer_id, gym_id) = 1
      and (
        (select public.owns_trainer(trainer_id))
        or (select public.owns_gym(gym_id))
      )
      and status in ('draft', 'review')
    )
  );
create policy coaching_routines_business_update
  on public.coaching_routines for update to authenticated
  using (
    (select public.owns_trainer(trainer_id))
    or (select public.owns_gym(gym_id))
    or (select public.is_admin())
  )
  with check (
    (select public.is_admin())
    or (
      num_nonnulls(trainer_id, gym_id) = 1
      and (
        (select public.owns_trainer(trainer_id))
        or (select public.owns_gym(gym_id))
      )
      and status in ('draft', 'review')
    )
  );
create policy coaching_routines_business_delete
  on public.coaching_routines for delete to authenticated
  using (
    (select public.owns_trainer(trainer_id))
    or (select public.owns_gym(gym_id))
    or (select public.is_admin())
  );

create policy coaching_exercises_public_read
  on public.coaching_routine_exercises for select to anon
  using (
    exists (
      select 1 from public.coaching_routines r
      where r.id = coaching_routine_exercises.routine_id
        and r.status = 'approved'
    )
  );
create policy coaching_exercises_authenticated_read
  on public.coaching_routine_exercises for select to authenticated
  using (
    exists (
      select 1 from public.coaching_routines r
      where r.id = coaching_routine_exercises.routine_id
        and (
          r.status = 'approved'
          or (select public.owns_trainer(r.trainer_id))
          or (select public.owns_gym(r.gym_id))
          or (select public.is_admin())
        )
    )
  );
create policy coaching_exercises_business_insert
  on public.coaching_routine_exercises for insert to authenticated
  with check (
    exists (
      select 1 from public.coaching_routines r
      where r.id = coaching_routine_exercises.routine_id
        and (
          (select public.is_admin())
          or (
            r.status in ('draft', 'review')
            and (
              (select public.owns_trainer(r.trainer_id))
              or (select public.owns_gym(r.gym_id))
            )
          )
        )
    )
  );
create policy coaching_exercises_business_update
  on public.coaching_routine_exercises for update to authenticated
  using (
    exists (
      select 1 from public.coaching_routines r
      where r.id = coaching_routine_exercises.routine_id
        and (
          (select public.is_admin())
          or (
            r.status in ('draft', 'review')
            and (
              (select public.owns_trainer(r.trainer_id))
              or (select public.owns_gym(r.gym_id))
            )
          )
        )
    )
  )
  with check (
    exists (
      select 1 from public.coaching_routines r
      where r.id = coaching_routine_exercises.routine_id
        and (
          (select public.is_admin())
          or (
            r.status in ('draft', 'review')
            and (
              (select public.owns_trainer(r.trainer_id))
              or (select public.owns_gym(r.gym_id))
            )
          )
        )
    )
  );
create policy coaching_exercises_business_delete
  on public.coaching_routine_exercises for delete to authenticated
  using (
    exists (
      select 1 from public.coaching_routines r
      where r.id = coaching_routine_exercises.routine_id
        and (
          (select public.is_admin())
          or (
            r.status in ('draft', 'review')
            and (
              (select public.owns_trainer(r.trainer_id))
              or (select public.owns_gym(r.gym_id))
            )
          )
        )
    )
  );

create policy coaching_sets_public_read
  on public.coaching_routine_sets for select to anon
  using (
    exists (
      select 1
      from public.coaching_routine_exercises e
      join public.coaching_routines r on r.id = e.routine_id
      where e.id = coaching_routine_sets.routine_exercise_id
        and r.status = 'approved'
    )
  );
create policy coaching_sets_authenticated_read
  on public.coaching_routine_sets for select to authenticated
  using (
    exists (
      select 1
      from public.coaching_routine_exercises e
      join public.coaching_routines r on r.id = e.routine_id
      where e.id = coaching_routine_sets.routine_exercise_id
        and (
          r.status = 'approved'
          or (select public.owns_trainer(r.trainer_id))
          or (select public.owns_gym(r.gym_id))
          or (select public.is_admin())
        )
    )
  );
create policy coaching_sets_business_insert
  on public.coaching_routine_sets for insert to authenticated
  with check (
    exists (
      select 1
      from public.coaching_routine_exercises e
      join public.coaching_routines r on r.id = e.routine_id
      where e.id = coaching_routine_sets.routine_exercise_id
        and (
          (select public.is_admin())
          or (
            r.status in ('draft', 'review')
            and (
              (select public.owns_trainer(r.trainer_id))
              or (select public.owns_gym(r.gym_id))
            )
          )
        )
    )
  );
create policy coaching_sets_business_update
  on public.coaching_routine_sets for update to authenticated
  using (
    exists (
      select 1
      from public.coaching_routine_exercises e
      join public.coaching_routines r on r.id = e.routine_id
      where e.id = coaching_routine_sets.routine_exercise_id
        and (
          (select public.is_admin())
          or (
            r.status in ('draft', 'review')
            and (
              (select public.owns_trainer(r.trainer_id))
              or (select public.owns_gym(r.gym_id))
            )
          )
        )
    )
  )
  with check (
    exists (
      select 1
      from public.coaching_routine_exercises e
      join public.coaching_routines r on r.id = e.routine_id
      where e.id = coaching_routine_sets.routine_exercise_id
        and (
          (select public.is_admin())
          or (
            r.status in ('draft', 'review')
            and (
              (select public.owns_trainer(r.trainer_id))
              or (select public.owns_gym(r.gym_id))
            )
          )
        )
    )
  );
create policy coaching_sets_business_delete
  on public.coaching_routine_sets for delete to authenticated
  using (
    exists (
      select 1
      from public.coaching_routine_exercises e
      join public.coaching_routines r on r.id = e.routine_id
      where e.id = coaching_routine_sets.routine_exercise_id
        and (
          (select public.is_admin())
          or (
            r.status in ('draft', 'review')
            and (
              (select public.owns_trainer(r.trainer_id))
              or (select public.owns_gym(r.gym_id))
            )
          )
        )
    )
  );

-- -------------------------------------------------------------------------
-- Private business mutations. Every function has an empty search_path and
-- independently verifies the JWT user, ownership, and/or active admin row.
-- -------------------------------------------------------------------------

create or replace function private.submit_trainer_application(
  p_name text,
  p_certification_number text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := auth.uid();
  v_name text := nullif(btrim(p_name), '');
  v_certification_number text := nullif(btrim(p_certification_number), '');
  v_trainer_id uuid;
  v_application_id uuid;
  v_status text;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;
  if v_name is null or char_length(v_name) > 100 then
    raise exception using errcode = '22023', message = 'A valid trainer name is required';
  end if;
  if v_certification_number is null or char_length(v_certification_number) > 100 then
    raise exception using errcode = '22023', message = 'A valid certification number is required';
  end if;
  if not exists (select 1 from public.users u where u.id = v_user_id) then
    raise exception using errcode = '23503', message = 'User profile is not ready';
  end if;

  select t.id, t.status
    into v_trainer_id, v_status
  from public.trainers t
  where t.user_id = v_user_id
  for update;

  if v_status = 'approved' then
    raise exception using errcode = '23514', message = 'Trainer profile is already approved';
  elsif v_status in ('suspended', 'grace_period') then
    raise exception using errcode = '42501', message = 'Trainer profile cannot be resubmitted in its current state';
  end if;

  if v_trainer_id is null then
    insert into public.trainers (
      user_id, display_name, status, is_public, verified_badge
    ) values (
      v_user_id, v_name, 'pending', false, false
    )
    returning id into v_trainer_id;
  else
    update public.trainers
    set display_name = v_name,
        status = 'pending',
        is_public = false,
        verified_badge = false,
        updated_at = now()
    where id = v_trainer_id;
  end if;

  insert into public.trainer_applications (
    trainer_id, user_id, name, submitted_at, sla_due_at, status,
    reject_reason, reviewer_id, reviewed_at, updated_at
  ) values (
    v_trainer_id, v_user_id, v_name, now(), now() + interval '3 days',
    'pending', null, null, null, now()
  )
  on conflict (user_id)
    where status = 'pending' and user_id is not null
  do update
    set trainer_id = excluded.trainer_id,
        name = excluded.name,
        submitted_at = excluded.submitted_at,
        sla_due_at = excluded.sla_due_at,
        reject_reason = null,
        reviewer_id = null,
        reviewed_at = null,
        updated_at = now()
  returning id into v_application_id;

  insert into public.trainer_certifications (
    trainer_id, title, credential_number, verification_status,
    created_at, updated_at
  ) values (
    v_trainer_id, 'Professional certification',
    v_certification_number, 'submitted', now(), now()
  )
  on conflict (trainer_id, credential_number)
    where credential_number is not null
  do update
    set verification_status = 'submitted',
        updated_at = now();

  return jsonb_build_object(
    'application_id', v_application_id,
    'trainer_id', v_trainer_id,
    'status', 'pending'
  );
end
$function$;

create or replace function private.submit_gym_application(
  p_name text,
  p_business_number text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := auth.uid();
  v_name text := nullif(btrim(p_name), '');
  v_business_number text := regexp_replace(coalesce(p_business_number, ''), '[^0-9]', '', 'g');
  v_owner_name text;
  v_gym_id uuid;
  v_existing_owner_id uuid;
  v_application_id uuid;
  v_status text;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;
  if v_name is null or char_length(v_name) > 150 then
    raise exception using errcode = '22023', message = 'A valid gym name is required';
  end if;
  if v_business_number !~ '^[0-9]{10}$' then
    raise exception using errcode = '22023', message = 'Business number must contain 10 digits';
  end if;

  select coalesce(nullif(btrim(u.nickname), ''), nullif(btrim(u.email), ''), v_name)
    into v_owner_name
  from public.users u
  where u.id = v_user_id;
  if not found then
    raise exception using errcode = '23503', message = 'User profile is not ready';
  end if;

  select g.id, g.owner_user_id, g.status
    into v_gym_id, v_existing_owner_id, v_status
  from public.gyms g
  where g.business_number = v_business_number
  for update;

  if v_gym_id is not null and v_existing_owner_id is distinct from v_user_id then
    raise exception using errcode = '23505', message = 'Business number is already registered';
  end if;
  if v_status = 'verified' then
    raise exception using errcode = '23514', message = 'Gym profile is already verified';
  elsif v_status in ('suspended', 'withdraw_pending') then
    raise exception using errcode = '42501', message = 'Gym profile cannot be resubmitted in its current state';
  end if;

  if v_gym_id is null then
    insert into public.gyms (
      owner_user_id, name, rep_name, business_number, status
    ) values (
      v_user_id, v_name, v_owner_name, v_business_number, 'pending'
    )
    returning id into v_gym_id;
  else
    update public.gyms
    set name = v_name,
        rep_name = v_owner_name,
        business_number = v_business_number,
        status = 'pending',
        updated_at = now()
    where id = v_gym_id;
  end if;

  insert into public.gym_applications (
    gym_id, gym_name, owner_name, owner_user_id, biz_reg_no,
    submitted_at, sla_due_at, status, reject_reason, reviewer_id,
    reviewed_at, updated_at
  ) values (
    v_gym_id, v_name, v_owner_name, v_user_id, v_business_number,
    now(), now() + interval '3 days', 'pending', null, null, null, now()
  )
  on conflict (gym_id)
    where status = 'pending' and gym_id is not null
  do update
    set gym_name = excluded.gym_name,
        owner_name = excluded.owner_name,
        owner_user_id = excluded.owner_user_id,
        biz_reg_no = excluded.biz_reg_no,
        submitted_at = excluded.submitted_at,
        sla_due_at = excluded.sla_due_at,
        reject_reason = null,
        reviewer_id = null,
        reviewed_at = null,
        updated_at = now()
  returning id into v_application_id;

  return jsonb_build_object(
    'application_id', v_application_id,
    'gym_id', v_gym_id,
    'status', 'pending'
  );
end
$function$;

create or replace function private.review_business_application(
  p_kind text,
  p_application_id uuid,
  p_decision text,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := auth.uid();
  v_admin_id uuid;
  v_kind text := lower(nullif(btrim(p_kind), ''));
  v_decision text := lower(nullif(btrim(p_decision), ''));
  v_reason text := nullif(btrim(p_reason), '');
  v_profile_id uuid;
  v_applicant_user_id uuid;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;

  select au.id
    into v_admin_id
  from public.admin_users au
  where au.user_id = v_user_id
    and au.status = 'active';
  if v_admin_id is null then
    raise exception using errcode = '42501', message = 'Active admin access required';
  end if;
  if v_kind is null or v_kind not in ('trainer', 'gym') then
    raise exception using errcode = '22023', message = 'Application kind must be trainer or gym';
  end if;
  if v_decision is null or v_decision not in ('approved', 'rejected') then
    raise exception using errcode = '22023', message = 'Decision must be approved or rejected';
  end if;
  if v_decision = 'rejected' and v_reason is null then
    raise exception using errcode = '22023', message = 'A rejection reason is required';
  end if;

  if v_kind = 'trainer' then
    select a.trainer_id, a.user_id
      into v_profile_id, v_applicant_user_id
    from public.trainer_applications a
    where a.id = p_application_id
      and a.status = 'pending'
    for update;

    if not found or v_profile_id is null or v_applicant_user_id is null then
      raise exception using errcode = 'P0002', message = 'Pending trainer application not found';
    end if;

    update public.trainer_applications
    set status = v_decision,
        reject_reason = case when v_decision = 'rejected' then v_reason else null end,
        reviewer_id = v_admin_id,
        reviewed_at = now(),
        updated_at = now()
    where id = p_application_id;

    update public.trainers
    set status = v_decision,
        verified_badge = (v_decision = 'approved'),
        is_public = (v_decision = 'approved'),
        updated_at = now()
    where id = v_profile_id
      and user_id = v_applicant_user_id;
    if not found then
      raise exception using errcode = '23503', message = 'Trainer profile ownership mismatch';
    end if;

    update public.trainer_certifications
    set verification_status = v_decision,
        updated_at = now()
    where trainer_id = v_profile_id
      and verification_status = 'submitted';

    update public.trainer_documents
    set review_status = v_decision
    where trainer_id = v_profile_id
      and coalesce(review_status, 'submitted') = 'submitted';

    if v_decision = 'approved' then
      update public.users
      set role = case when role in ('admin', 'gym') then role else 'trainer' end,
          updated_at = now()
      where id = v_applicant_user_id;
    end if;
  else
    select a.gym_id, a.owner_user_id
      into v_profile_id, v_applicant_user_id
    from public.gym_applications a
    where a.id = p_application_id
      and a.status = 'pending'
    for update;

    if not found or v_profile_id is null or v_applicant_user_id is null then
      raise exception using errcode = 'P0002', message = 'Pending gym application not found';
    end if;

    update public.gym_applications
    set status = v_decision,
        reject_reason = case when v_decision = 'rejected' then v_reason else null end,
        reviewer_id = v_admin_id,
        reviewed_at = now(),
        updated_at = now()
    where id = p_application_id;

    update public.gyms
    set status = case when v_decision = 'approved' then 'verified' else 'pending' end,
        updated_at = now()
    where id = v_profile_id
      and owner_user_id = v_applicant_user_id;
    if not found then
      raise exception using errcode = '23503', message = 'Gym profile ownership mismatch';
    end if;

    update public.gym_documents
    set status = v_decision,
        reviewed_by = v_admin_id
    where gym_id = v_profile_id
      and coalesce(status, 'submitted') = 'submitted';

    if v_decision = 'approved' then
      update public.users
      set role = case when role = 'admin' then role else 'gym' end,
          updated_at = now()
      where id = v_applicant_user_id;
    end if;
  end if;

  return jsonb_build_object(
    'kind', v_kind,
    'application_id', p_application_id,
    'decision', v_decision,
    'profile_id', v_profile_id
  );
end
$function$;

create or replace function private.assign_gym_member(
  p_member_id uuid,
  p_trainer_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := auth.uid();
  v_gym_id uuid;
  v_assignment_id uuid;
  v_is_admin boolean;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;

  select m.gym_id
    into v_gym_id
  from public.members m
  where m.id = p_member_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Member not found';
  end if;

  select exists (
    select 1 from public.admin_users au
    where au.user_id = v_user_id and au.status = 'active'
  ) into v_is_admin;

  if not v_is_admin and not exists (
    select 1 from public.gyms g
    where g.id = v_gym_id and g.owner_user_id = v_user_id
  ) then
    raise exception using errcode = '42501', message = 'Gym owner access required';
  end if;

  if p_trainer_id is not null and not exists (
    select 1
    from public.gym_trainers gt
    join public.trainers t on t.id = gt.trainer_id
    where gt.gym_id = v_gym_id
      and gt.trainer_id = p_trainer_id
      and gt.status = 'active'
      and t.status = 'approved'
  ) then
    raise exception using errcode = '23503', message = 'Trainer is not active at this gym';
  end if;

  update public.member_assignments
  set active = false
  where member_id = p_member_id
    and active;

  if p_trainer_id is not null then
    insert into public.member_assignments (
      gym_id, member_id, trainer_id, assigned_at, active
    ) values (
      v_gym_id, p_member_id, p_trainer_id, now(), true
    )
    returning id into v_assignment_id;
  end if;

  update public.members
  set last_activity_at = now()
  where id = p_member_id;

  return jsonb_build_object(
    'assignment_id', v_assignment_id,
    'gym_id', v_gym_id,
    'member_id', p_member_id,
    'trainer_id', p_trainer_id,
    'active', p_trainer_id is not null
  );
end
$function$;

create or replace function private.reply_business_consultation(
  p_consultation_id uuid,
  p_text text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := auth.uid();
  v_text text := nullif(btrim(p_text), '');
  v_trainer_id uuid;
  v_assigned_trainer_id uuid;
  v_gym_id uuid;
  v_is_admin boolean;
  v_is_trainer boolean;
  v_is_gym boolean;
  v_sender_type text;
  v_message_id uuid;
  v_created_at timestamptz;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;
  if v_text is null or char_length(v_text) > 5000 then
    raise exception using errcode = '22023', message = 'Reply text must be between 1 and 5000 characters';
  end if;

  select c.trainer_id, c.assigned_trainer_id, c.gym_id
    into v_trainer_id, v_assigned_trainer_id, v_gym_id
  from public.consultations c
  where c.id = p_consultation_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Consultation not found';
  end if;

  select exists (
    select 1 from public.admin_users au
    where au.user_id = v_user_id and au.status = 'active'
  ) into v_is_admin;
  select exists (
    select 1 from public.trainers t
    where t.id in (v_trainer_id, v_assigned_trainer_id)
      and t.user_id = v_user_id
  ) or exists (
    select 1 from public.gym_trainers gt
    where gt.gym_id = v_gym_id
      and gt.trainer_id in (v_trainer_id, v_assigned_trainer_id)
      and gt.trainer_user_id = v_user_id
      and gt.status = 'active'
  ) into v_is_trainer;
  select exists (
    select 1 from public.gyms g
    where g.id = v_gym_id and g.owner_user_id = v_user_id
  ) into v_is_gym;

  if not (v_is_admin or v_is_trainer or v_is_gym) then
    raise exception using errcode = '42501', message = 'Business participant access required';
  end if;

  v_sender_type := case
    when v_is_trainer then 'trainer'
    when v_is_gym then 'gym'
    when v_gym_id is not null then 'gym'
    else 'trainer'
  end;

  insert into public.consultation_messages (
    consultation_id, sender_type, sender_id, text, created_at
  ) values (
    p_consultation_id, v_sender_type, v_user_id, v_text, now()
  )
  returning id, created_at into v_message_id, v_created_at;

  update public.consultations
  set status = 'replied',
      is_read = true
  where id = p_consultation_id;

  return jsonb_build_object(
    'message_id', v_message_id,
    'consultation_id', p_consultation_id,
    'status', 'replied',
    'sender_type', v_sender_type,
    'created_at', v_created_at
  );
end
$function$;

revoke all on function private.submit_trainer_application(text, text)
  from public, anon;
revoke all on function private.submit_gym_application(text, text)
  from public, anon;
revoke all on function private.review_business_application(text, uuid, text, text)
  from public, anon;
revoke all on function private.assign_gym_member(uuid, uuid)
  from public, anon;
revoke all on function private.reply_business_consultation(uuid, text)
  from public, anon;
grant execute on function private.submit_trainer_application(text, text),
  private.submit_gym_application(text, text),
  private.review_business_application(text, uuid, text, text),
  private.assign_gym_member(uuid, uuid),
  private.reply_business_consultation(uuid, text)
  to authenticated, service_role;

-- Public Data API entrypoints deliberately remain SECURITY INVOKER. The
-- mutation privilege lives only in the checked private implementation.
create or replace function public.submit_trainer_application(
  name text,
  certification_number text
)
returns jsonb
language sql
volatile
security invoker
set search_path = ''
as $function$
  select private.submit_trainer_application($1, $2);
$function$;

create or replace function public.submit_gym_application(
  name text,
  business_number text
)
returns jsonb
language sql
volatile
security invoker
set search_path = ''
as $function$
  select private.submit_gym_application($1, $2);
$function$;

create or replace function public.review_business_application(
  kind text,
  application_id uuid,
  decision text,
  reason text default null
)
returns jsonb
language sql
volatile
security invoker
set search_path = ''
as $function$
  select private.review_business_application($1, $2, $3, $4);
$function$;

create or replace function public.assign_gym_member(
  member_id uuid,
  trainer_id uuid
)
returns jsonb
language sql
volatile
security invoker
set search_path = ''
as $function$
  select private.assign_gym_member($1, $2);
$function$;

create or replace function public.reply_business_consultation(
  consultation_id uuid,
  "text" text
)
returns jsonb
language sql
volatile
security invoker
set search_path = ''
as $function$
  select private.reply_business_consultation($1, $2);
$function$;

revoke all on function public.submit_trainer_application(text, text)
  from public, anon;
revoke all on function public.submit_gym_application(text, text)
  from public, anon;
revoke all on function public.review_business_application(text, uuid, text, text)
  from public, anon;
revoke all on function public.assign_gym_member(uuid, uuid)
  from public, anon;
revoke all on function public.reply_business_consultation(uuid, text)
  from public, anon;
grant execute on function public.submit_trainer_application(text, text),
  public.submit_gym_application(text, text),
  public.review_business_application(text, uuid, text, text),
  public.assign_gym_member(uuid, uuid),
  public.reply_business_consultation(uuid, text)
  to authenticated, service_role;

commit;
