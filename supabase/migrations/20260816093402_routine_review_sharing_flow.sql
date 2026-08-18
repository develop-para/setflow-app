-- Trainer/gym routine authoring, review, publication, and member sharing.
-- Public RPCs remain SECURITY INVOKER entrypoints. Checked mutations live in
-- private SECURITY DEFINER implementations with an empty search_path.

begin;

create extension if not exists pgcrypto with schema extensions;

alter table public.coaching_routines
  add column if not exists submitted_at timestamptz,
  add column if not exists submitted_by_user_id uuid
    references public.users(id) on delete set null,
  add column if not exists reviewed_at timestamptz,
  add column if not exists reviewed_by_user_id uuid
    references public.users(id) on delete set null;

alter table public.coaching_routine_sets
  add column if not exists rest_seconds integer not null default 90;

alter table public.routine_sets
  add column if not exists rest_seconds integer not null default 90;

do $constraints$
begin
  -- Source rows are accepted only through the checked authoring RPC. Keep the
  -- same invariants at the storage boundary so service-side writes cannot
  -- publish a malformed routine by accident.
  alter table public.coaching_routine_exercises
    alter column name set not null,
    alter column target_muscle set not null,
    alter column order_index set not null;

  alter table public.coaching_routine_sets
    alter column set_no set not null,
    alter column type set not null,
    alter column target_reps set not null;

  if not exists (
    select 1
    from pg_catalog.pg_constraint
    where conrelid = 'public.coaching_routine_exercises'::regclass
      and conname = 'coaching_routine_exercises_content_valid'
  ) then
    alter table public.coaching_routine_exercises
      add constraint coaching_routine_exercises_content_valid
      check (
        char_length(pg_catalog.btrim(name)) between 1 and 120
        and char_length(pg_catalog.btrim(target_muscle)) between 1 and 80
        and order_index >= 0
      );
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_constraint
    where conrelid = 'public.coaching_routine_sets'::regclass
      and conname = 'coaching_routine_sets_content_valid'
  ) then
    alter table public.coaching_routine_sets
      add constraint coaching_routine_sets_content_valid
      check (
        set_no >= 1
        and type in ('normal', 'warmup', 'drop', 'failure')
        and (target_weight is null or target_weight between 0 and 5000)
        and target_reps between 1 and 1000
      );
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_constraint
    where conrelid = 'public.coaching_routine_sets'::regclass
      and conname = 'coaching_routine_sets_rest_seconds_range'
  ) then
    alter table public.coaching_routine_sets
      add constraint coaching_routine_sets_rest_seconds_range
      check (rest_seconds between 0 and 3600);
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_constraint
    where conrelid = 'public.routine_sets'::regclass
      and conname = 'routine_sets_rest_seconds_range'
  ) then
    alter table public.routine_sets
      add constraint routine_sets_rest_seconds_range
      check (rest_seconds between 0 and 3600);
  end if;
end
$constraints$;

-- Legacy published expert routines predate structured set prescriptions. Give
-- only wholly empty exercises a conservative, editable default plan; exercises
-- with even one authored set are left untouched.
insert into public.coaching_routine_sets (
  routine_exercise_id, set_no, type,
  target_weight, target_reps, rest_seconds
)
select
  exercise.id,
  generated_set.set_no,
  'normal',
  null,
  10,
  90
from public.coaching_routine_exercises exercise
join public.coaching_routines routine on routine.id = exercise.routine_id
cross join pg_catalog.generate_series(1, 3) as generated_set(set_no)
where routine.status = 'approved'
  and exists (
    select 1
    from public.market_routines market
    where market.coaching_routine_id = routine.id
      and market.status = 'published'
  )
  and not exists (
    select 1
    from public.coaching_routine_sets existing_set
    where existing_set.routine_exercise_id = exercise.id
  );

-- A reviewed source has exactly one market listing. Gym-authored routines use
-- gym_id while trainer-authored routines retain the existing trainer_id.
alter table public.market_routines
  add column if not exists gym_id uuid
    references public.gyms(id) on delete set null;

do $market_constraints$
begin
  if not exists (
    select 1
    from pg_catalog.pg_constraint
    where conrelid = 'public.market_routines'::regclass
      and conname = 'market_routines_single_business_author'
  ) then
    alter table public.market_routines
      add constraint market_routines_single_business_author
      check (num_nonnulls(trainer_id, gym_id) <= 1);
  end if;
end
$market_constraints$;

create unique index if not exists market_routines_coaching_routine_uidx
  on public.market_routines (coaching_routine_id)
  where coaching_routine_id is not null;
create index if not exists market_routines_gym_idx
  on public.market_routines (gym_id)
  where gym_id is not null;
create index if not exists coaching_routines_submitted_by_idx
  on public.coaching_routines (submitted_by_user_id)
  where submitted_by_user_id is not null;
create index if not exists coaching_routines_reviewed_by_idx
  on public.coaching_routines (reviewed_by_user_id)
  where reviewed_by_user_id is not null;
create unique index if not exists coaching_routine_sets_number_uidx
  on public.coaching_routine_sets (routine_exercise_id, set_no)
  where set_no is not null;
create unique index if not exists routine_sets_number_uidx
  on public.routine_sets (routine_exercise_id, set_no);

create table if not exists public.routine_review_events (
  id uuid primary key default gen_random_uuid(),
  routine_id uuid not null
    references public.coaching_routines(id) on delete cascade,
  action text not null
    check (action in ('submitted', 'approved', 'rejected')),
  actor_user_id uuid references public.users(id) on delete set null,
  from_status text not null,
  to_status text not null,
  note text,
  market_routine_id uuid
    references public.market_routines(id) on delete set null,
  request_id uuid,
  created_at timestamptz not null default now(),
  constraint routine_review_events_note_length
    check (note is null or char_length(note) <= 2000)
);

create table if not exists public.routine_shares (
  id uuid primary key default gen_random_uuid(),
  coaching_routine_id uuid not null
    references public.coaching_routines(id) on delete cascade,
  share_type text not null
    check (share_type in ('direct', 'link')),
  sender_user_id uuid not null
    references public.users(id) on delete cascade,
  sender_trainer_id uuid
    references public.trainers(id) on delete cascade,
  sender_gym_id uuid
    references public.gyms(id) on delete cascade,
  member_id uuid references public.members(id) on delete cascade,
  recipient_user_id uuid references public.users(id) on delete cascade,
  message text,
  token_hash bytea,
  status text not null default 'pending'
    check (status in (
      'pending', 'accepted', 'declined', 'revoked', 'expired'
    )),
  expires_at timestamptz not null,
  responded_by_user_id uuid references public.users(id) on delete set null,
  accepted_routine_id uuid references public.routines(id) on delete set null,
  request_id uuid,
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  updated_at timestamptz not null default now(),
  constraint routine_shares_single_business_sender
    check (num_nonnulls(sender_trainer_id, sender_gym_id) = 1),
  constraint routine_shares_message_length
    check (message is null or char_length(message) <= 1000),
  constraint routine_shares_shape
    check (
      (
        share_type = 'direct'
        and member_id is not null
        and recipient_user_id is not null
        and token_hash is null
      )
      or
      (
        share_type = 'link'
        and member_id is null
        and token_hash is not null
      )
    ),
  constraint routine_shares_response_shape
    check (
      (
        status = 'accepted'
        and responded_by_user_id is not null
        and accepted_routine_id is not null
        and responded_at is not null
      )
      or
      (
        status = 'declined'
        and responded_by_user_id is not null
        and accepted_routine_id is null
        and responded_at is not null
      )
      or
      (
        status in ('pending', 'revoked', 'expired')
        and accepted_routine_id is null
      )
    )
);

alter table public.routines
  add column if not exists source_coaching_routine_id uuid
    references public.coaching_routines(id) on delete set null,
  add column if not exists source_routine_share_id uuid
    references public.routine_shares(id) on delete set null;

do $routine_market_foreign_key$
begin
  if not exists (
    select 1
    from pg_catalog.pg_constraint constraint_row
    where constraint_row.conrelid = 'public.routines'::regclass
      and constraint_row.contype = 'f'
      and constraint_row.conkey = array[
        (
          select attribute.attnum
          from pg_catalog.pg_attribute attribute
          where attribute.attrelid = 'public.routines'::regclass
            and attribute.attname = 'market_routine_id'
        )
      ]::smallint[]
  ) then
    alter table public.routines
      add constraint routines_market_routine_id_fkey
      foreign key (market_routine_id)
      references public.market_routines(id) on delete set null;
  end if;
end
$routine_market_foreign_key$;

-- Every request ID is scoped to an authenticated actor and operation. The
-- payload hash prevents accidentally reusing a key for a different request.
create table if not exists public.routine_rpc_requests (
  actor_user_id uuid not null
    references public.users(id) on delete cascade,
  operation text not null,
  request_id uuid not null,
  request_hash text not null,
  response jsonb not null,
  created_at timestamptz not null default now(),
  primary key (actor_user_id, operation, request_id),
  constraint routine_rpc_requests_operation_length
    check (char_length(operation) between 1 and 80),
  constraint routine_rpc_requests_hash_format
    check (request_hash ~ '^[0-9a-f]{64}$')
);

create index if not exists routine_review_events_routine_created_idx
  on public.routine_review_events (routine_id, created_at desc);
create index if not exists routine_review_events_actor_idx
  on public.routine_review_events (actor_user_id)
  where actor_user_id is not null;
create unique index if not exists routine_review_events_request_uidx
  on public.routine_review_events (actor_user_id, action, request_id)
  where actor_user_id is not null and request_id is not null;
create index if not exists routine_review_events_market_idx
  on public.routine_review_events (market_routine_id)
  where market_routine_id is not null;

create index if not exists routine_shares_source_created_idx
  on public.routine_shares (coaching_routine_id, created_at desc);
create index if not exists routine_shares_sender_user_created_idx
  on public.routine_shares (sender_user_id, created_at desc);
create index if not exists routine_shares_sender_trainer_idx
  on public.routine_shares (sender_trainer_id)
  where sender_trainer_id is not null;
create index if not exists routine_shares_sender_gym_idx
  on public.routine_shares (sender_gym_id)
  where sender_gym_id is not null;
create index if not exists routine_shares_member_idx
  on public.routine_shares (member_id)
  where member_id is not null;
create index if not exists routine_shares_recipient_status_created_idx
  on public.routine_shares (recipient_user_id, status, created_at desc)
  where recipient_user_id is not null;
create index if not exists routine_shares_responded_by_idx
  on public.routine_shares (responded_by_user_id)
  where responded_by_user_id is not null;
create unique index if not exists routine_shares_token_hash_uidx
  on public.routine_shares (token_hash)
  where token_hash is not null;
create unique index if not exists routine_shares_sender_request_uidx
  on public.routine_shares (sender_user_id, request_id, member_id)
  where request_id is not null and member_id is not null;
create unique index if not exists routine_shares_one_pending_direct_uidx
  on public.routine_shares (
    coaching_routine_id, member_id, sender_user_id
  )
  where share_type = 'direct' and status = 'pending';
create index if not exists routine_shares_pending_expiry_idx
  on public.routine_shares (expires_at)
  where status = 'pending';
create unique index if not exists routine_shares_accepted_routine_uidx
  on public.routine_shares (accepted_routine_id)
  where accepted_routine_id is not null;

create index if not exists routines_source_coaching_idx
  on public.routines (source_coaching_routine_id)
  where source_coaching_routine_id is not null;
create unique index if not exists routines_source_share_uidx
  on public.routines (source_routine_share_id)
  where source_routine_share_id is not null;
create unique index if not exists routines_owner_market_uidx
  on public.routines (owner_user_id, market_routine_id)
  where market_routine_id is not null;
create index if not exists routines_market_routine_idx
  on public.routines (market_routine_id)
  where market_routine_id is not null;
create index if not exists routine_rpc_requests_created_idx
  on public.routine_rpc_requests (created_at);

alter table public.routine_review_events enable row level security;
alter table public.routine_shares enable row level security;
alter table public.routine_rpc_requests enable row level security;

revoke all on table public.routine_review_events
  from public, anon, authenticated;
revoke all on table public.routine_shares
  from public, anon, authenticated;
revoke all on table public.routine_rpc_requests
  from public, anon, authenticated;

grant select on table public.routine_review_events to authenticated;
grant select (
  id, coaching_routine_id, share_type, sender_user_id,
  sender_trainer_id, sender_gym_id, member_id, recipient_user_id,
  message, status, expires_at, responded_by_user_id,
  accepted_routine_id, request_id, created_at, responded_at, updated_at
) on public.routine_shares to authenticated;
grant all on table public.routine_review_events,
  public.routine_shares, public.routine_rpc_requests
  to service_role;

drop policy if exists read_visible_routine_review_events
  on public.routine_review_events;
create policy read_visible_routine_review_events
  on public.routine_review_events
  for select
  to authenticated
  using (
    (select public.is_admin())
    or exists (
      select 1
      from public.coaching_routines routine
      where routine.id = routine_review_events.routine_id
        and (
          (select public.owns_trainer(routine.trainer_id))
          or (select public.owns_gym(routine.gym_id))
        )
    )
  );

drop policy if exists read_visible_routine_shares on public.routine_shares;
create policy read_visible_routine_shares
  on public.routine_shares
  for select
  to authenticated
  using (
    sender_user_id = (select auth.uid())
    or recipient_user_id = (select auth.uid())
    or (select public.is_admin())
  );

-- A member receiving a private trainer routine may read that trainer's safe
-- directory columns even when the trainer has not enabled global discovery.
drop policy if exists trainers_authenticated_directory on public.trainers;
create policy trainers_authenticated_directory
  on public.trainers for select to authenticated
  using (
    (status = 'approved' and is_public)
    or user_id = (select auth.uid())
    or exists (
      select 1 from public.gym_trainers gym_trainer
      where gym_trainer.trainer_id = trainers.id
        and gym_trainer.status = 'active'
        and (select public.owns_gym(gym_trainer.gym_id))
    )
    or exists (
      select 1 from public.routine_shares share
      where share.sender_trainer_id = trainers.id
        and share.recipient_user_id = (select auth.uid())
        and share.status in ('pending', 'accepted')
        and (
          share.status = 'accepted'
          or share.expires_at > now()
        )
    )
    or (select public.is_admin())
  );

-- Rebuild authoring policies so owners may edit only draft/rejected content.
-- Status submission and moderation therefore cannot be bypassed with table DML.
drop policy if exists read_approved_coaching_routines_anon
  on public.coaching_routines;
drop policy if exists read_coaching_routines_authenticated
  on public.coaching_routines;
drop policy if exists coaching_routines_public_read
  on public.coaching_routines;
drop policy if exists coaching_routines_authenticated_read
  on public.coaching_routines;
drop policy if exists coaching_routines_business_insert
  on public.coaching_routines;
drop policy if exists coaching_routines_business_update
  on public.coaching_routines;
drop policy if exists coaching_routines_business_delete
  on public.coaching_routines;
drop policy if exists rd_cr on public.coaching_routines;
drop policy if exists wr_cr on public.coaching_routines;
drop policy if exists read_approved_coaching_routines
  on public.coaching_routines;
drop policy if exists read_owned_coaching_routines
  on public.coaching_routines;
drop policy if exists create_owned_coaching_routines
  on public.coaching_routines;
drop policy if exists update_owned_coaching_routines
  on public.coaching_routines;
drop policy if exists delete_owned_coaching_routines
  on public.coaching_routines;

create policy read_approved_coaching_routines_anon
  on public.coaching_routines for select to anon
  using (status = 'approved');
create policy read_coaching_routines_authenticated
  on public.coaching_routines for select to authenticated
  using (
    status = 'approved'
    or (select public.owns_trainer(trainer_id))
    or (select public.owns_gym(gym_id))
    or (select public.is_admin())
    or exists (
      select 1
      from public.routine_shares share
      where share.coaching_routine_id = coaching_routines.id
        and share.recipient_user_id = (select auth.uid())
        and share.status in ('pending', 'accepted')
        and (
          share.status = 'accepted'
          or share.expires_at > now()
        )
    )
  );
create policy create_owned_coaching_routines
  on public.coaching_routines for insert to authenticated
  with check (
    status = 'draft'
    and (
      (select public.owns_trainer(trainer_id))
      or (select public.owns_gym(gym_id))
    )
  );
create policy update_owned_coaching_routines
  on public.coaching_routines for update to authenticated
  using (
    status in ('draft', 'rejected')
    and (
      (select public.owns_trainer(trainer_id))
      or (select public.owns_gym(gym_id))
    )
  )
  with check (
    status = 'draft'
    and (
      (select public.owns_trainer(trainer_id))
      or (select public.owns_gym(gym_id))
    )
  );
create policy delete_owned_coaching_routines
  on public.coaching_routines for delete to authenticated
  using (
    status in ('draft', 'rejected')
    and (
      (select public.owns_trainer(trainer_id))
      or (select public.owns_gym(gym_id))
    )
  );

drop policy if exists read_approved_coaching_exercises_anon
  on public.coaching_routine_exercises;
drop policy if exists read_coaching_exercises_authenticated
  on public.coaching_routine_exercises;
drop policy if exists coaching_exercises_public_read
  on public.coaching_routine_exercises;
drop policy if exists coaching_exercises_authenticated_read
  on public.coaching_routine_exercises;
drop policy if exists coaching_exercises_business_insert
  on public.coaching_routine_exercises;
drop policy if exists coaching_exercises_business_update
  on public.coaching_routine_exercises;
drop policy if exists coaching_exercises_business_delete
  on public.coaching_routine_exercises;
drop policy if exists rd_cr_ex on public.coaching_routine_exercises;
drop policy if exists wr_cr_ex on public.coaching_routine_exercises;
drop policy if exists read_approved_coaching_exercises
  on public.coaching_routine_exercises;
drop policy if exists read_owned_coaching_exercises
  on public.coaching_routine_exercises;
drop policy if exists create_owned_coaching_exercises
  on public.coaching_routine_exercises;
drop policy if exists update_owned_coaching_exercises
  on public.coaching_routine_exercises;
drop policy if exists delete_owned_coaching_exercises
  on public.coaching_routine_exercises;

create policy read_approved_coaching_exercises_anon
  on public.coaching_routine_exercises for select to anon
  using (
    exists (
      select 1
      from public.coaching_routines routine
      join public.market_routines market
        on market.coaching_routine_id = routine.id
      where routine.id = coaching_routine_exercises.routine_id
        and routine.status = 'approved'
        and market.status = 'published'
        and market.access_tier = 'free'
    )
  );
create policy read_coaching_exercises_authenticated
  on public.coaching_routine_exercises for select to authenticated
  using (
    exists (
      select 1 from public.coaching_routines routine
      where routine.id = coaching_routine_exercises.routine_id
        and (
          (select public.owns_trainer(routine.trainer_id))
          or (select public.owns_gym(routine.gym_id))
          or (select public.is_admin())
          or exists (
            select 1
            from public.routine_shares share
            where share.coaching_routine_id = routine.id
              and share.recipient_user_id = (select auth.uid())
              and share.status in ('pending', 'accepted')
              and (
                share.status = 'accepted'
                or share.expires_at > now()
              )
          )
          or (
            routine.status = 'approved'
            and exists (
              select 1
              from public.market_routines market
              where market.coaching_routine_id = routine.id
                and market.status = 'published'
                and (
                  market.access_tier = 'free'
                  or (
                    market.access_tier = 'paid'
                    and exists (
                      select 1
                      from public.subscriptions subscription
                      join public.plans plan on plan.id = subscription.plan_id
                      where subscription.user_id = (select auth.uid())
                        and subscription.status = 'active'
                        and (
                          subscription.current_period_end is null
                          or subscription.current_period_end > now()
                        )
                        and plan.audience = 'b2c'
                        and plan.price > 0
                    )
                  )
                )
            )
          )
        )
    )
  );
create policy create_owned_coaching_exercises
  on public.coaching_routine_exercises for insert to authenticated
  with check (
    exists (
      select 1 from public.coaching_routines routine
      where routine.id = coaching_routine_exercises.routine_id
        and routine.status in ('draft', 'rejected')
        and (
          (select public.owns_trainer(routine.trainer_id))
          or (select public.owns_gym(routine.gym_id))
        )
    )
  );
create policy update_owned_coaching_exercises
  on public.coaching_routine_exercises for update to authenticated
  using (
    exists (
      select 1 from public.coaching_routines routine
      where routine.id = coaching_routine_exercises.routine_id
        and routine.status in ('draft', 'rejected')
        and (
          (select public.owns_trainer(routine.trainer_id))
          or (select public.owns_gym(routine.gym_id))
        )
    )
  )
  with check (
    exists (
      select 1 from public.coaching_routines routine
      where routine.id = coaching_routine_exercises.routine_id
        and routine.status in ('draft', 'rejected')
        and (
          (select public.owns_trainer(routine.trainer_id))
          or (select public.owns_gym(routine.gym_id))
        )
    )
  );
create policy delete_owned_coaching_exercises
  on public.coaching_routine_exercises for delete to authenticated
  using (
    exists (
      select 1 from public.coaching_routines routine
      where routine.id = coaching_routine_exercises.routine_id
        and routine.status in ('draft', 'rejected')
        and (
          (select public.owns_trainer(routine.trainer_id))
          or (select public.owns_gym(routine.gym_id))
        )
    )
  );

drop policy if exists read_approved_coaching_sets_anon
  on public.coaching_routine_sets;
drop policy if exists read_coaching_sets_authenticated
  on public.coaching_routine_sets;
drop policy if exists coaching_sets_public_read
  on public.coaching_routine_sets;
drop policy if exists coaching_sets_authenticated_read
  on public.coaching_routine_sets;
drop policy if exists coaching_sets_business_insert
  on public.coaching_routine_sets;
drop policy if exists coaching_sets_business_update
  on public.coaching_routine_sets;
drop policy if exists coaching_sets_business_delete
  on public.coaching_routine_sets;
drop policy if exists rd_cr_sets on public.coaching_routine_sets;
drop policy if exists wr_cr_sets on public.coaching_routine_sets;
drop policy if exists read_approved_coaching_sets
  on public.coaching_routine_sets;
drop policy if exists manage_owned_coaching_sets
  on public.coaching_routine_sets;
drop policy if exists create_owned_coaching_sets
  on public.coaching_routine_sets;
drop policy if exists update_owned_coaching_sets
  on public.coaching_routine_sets;
drop policy if exists delete_owned_coaching_sets
  on public.coaching_routine_sets;

create policy read_approved_coaching_sets_anon
  on public.coaching_routine_sets for select to anon
  using (
    exists (
      select 1
      from public.coaching_routine_exercises exercise
      join public.coaching_routines routine on routine.id = exercise.routine_id
      join public.market_routines market
        on market.coaching_routine_id = routine.id
      where exercise.id = coaching_routine_sets.routine_exercise_id
        and routine.status = 'approved'
        and market.status = 'published'
        and market.access_tier = 'free'
    )
  );
create policy read_coaching_sets_authenticated
  on public.coaching_routine_sets for select to authenticated
  using (
    exists (
      select 1
      from public.coaching_routine_exercises exercise
      join public.coaching_routines routine on routine.id = exercise.routine_id
      where exercise.id = coaching_routine_sets.routine_exercise_id
        and (
          (select public.owns_trainer(routine.trainer_id))
          or (select public.owns_gym(routine.gym_id))
          or (select public.is_admin())
          or exists (
            select 1
            from public.routine_shares share
            where share.coaching_routine_id = routine.id
              and share.recipient_user_id = (select auth.uid())
              and share.status in ('pending', 'accepted')
              and (
                share.status = 'accepted'
                or share.expires_at > now()
              )
          )
          or (
            routine.status = 'approved'
            and exists (
              select 1
              from public.market_routines market
              where market.coaching_routine_id = routine.id
                and market.status = 'published'
                and (
                  market.access_tier = 'free'
                  or (
                    market.access_tier = 'paid'
                    and exists (
                      select 1
                      from public.subscriptions subscription
                      join public.plans plan on plan.id = subscription.plan_id
                      where subscription.user_id = (select auth.uid())
                        and subscription.status = 'active'
                        and (
                          subscription.current_period_end is null
                          or subscription.current_period_end > now()
                        )
                        and plan.audience = 'b2c'
                        and plan.price > 0
                    )
                  )
                )
            )
          )
        )
    )
  );
create policy create_owned_coaching_sets
  on public.coaching_routine_sets for insert to authenticated
  with check (
    exists (
      select 1
      from public.coaching_routine_exercises exercise
      join public.coaching_routines routine on routine.id = exercise.routine_id
      where exercise.id = coaching_routine_sets.routine_exercise_id
        and routine.status in ('draft', 'rejected')
        and (
          (select public.owns_trainer(routine.trainer_id))
          or (select public.owns_gym(routine.gym_id))
        )
    )
  );
create policy update_owned_coaching_sets
  on public.coaching_routine_sets for update to authenticated
  using (
    exists (
      select 1
      from public.coaching_routine_exercises exercise
      join public.coaching_routines routine on routine.id = exercise.routine_id
      where exercise.id = coaching_routine_sets.routine_exercise_id
        and routine.status in ('draft', 'rejected')
        and (
          (select public.owns_trainer(routine.trainer_id))
          or (select public.owns_gym(routine.gym_id))
        )
    )
  )
  with check (
    exists (
      select 1
      from public.coaching_routine_exercises exercise
      join public.coaching_routines routine on routine.id = exercise.routine_id
      where exercise.id = coaching_routine_sets.routine_exercise_id
        and routine.status in ('draft', 'rejected')
        and (
          (select public.owns_trainer(routine.trainer_id))
          or (select public.owns_gym(routine.gym_id))
        )
    )
  );
create policy delete_owned_coaching_sets
  on public.coaching_routine_sets for delete to authenticated
  using (
    exists (
      select 1
      from public.coaching_routine_exercises exercise
      join public.coaching_routines routine on routine.id = exercise.routine_id
      where exercise.id = coaching_routine_sets.routine_exercise_id
        and routine.status in ('draft', 'rejected')
        and (
          (select public.owns_trainer(routine.trainer_id))
          or (select public.owns_gym(routine.gym_id))
        )
    )
  );

-- All routine writes pass through checked SECURITY DEFINER implementations.
-- Revoking table DML also prevents clients from forging review/provenance
-- columns even if a future permissive RLS policy is added accidentally.
revoke insert, update, delete on table public.coaching_routines,
  public.coaching_routine_exercises, public.coaching_routine_sets,
  public.routines, public.routine_exercises, public.routine_sets
  from anon, authenticated;

-- Older deployments granted several coaching_routines columns explicitly.
-- Table-level REVOKE does not clear pg_attribute.attacl, so remove INSERT and
-- UPDATE from every current column on all six RPC-owned tables as well.
do $revoke_routine_column_dml$
declare
  target_relation regclass;
  column_list text;
begin
  foreach target_relation in array array[
    'public.coaching_routines'::regclass,
    'public.coaching_routine_exercises'::regclass,
    'public.coaching_routine_sets'::regclass,
    'public.routines'::regclass,
    'public.routine_exercises'::regclass,
    'public.routine_sets'::regclass
  ]
  loop
    select pg_catalog.string_agg(
      pg_catalog.format('%I', attribute.attname), ', '
      order by attribute.attnum
    ) into column_list
    from pg_catalog.pg_attribute attribute
    where attribute.attrelid = target_relation
      and attribute.attnum > 0
      and not attribute.attisdropped;

    execute pg_catalog.format(
      'revoke insert (%1$s), update (%1$s) on table %2$s from anon, authenticated',
      column_list,
      target_relation
    );
  end loop;
end
$revoke_routine_column_dml$;

grant select on table public.coaching_routines,
  public.coaching_routine_exercises, public.coaching_routine_sets,
  public.routines, public.routine_exercises, public.routine_sets
  to authenticated;

create or replace function private.routine_request_hash(p_payload jsonb)
returns text
language sql
immutable
security invoker
set search_path = ''
as $function$
  select encode(extensions.digest(p_payload::text, 'sha256'), 'hex');
$function$;

create or replace function private.begin_routine_rpc_request(
  p_actor_user_id uuid,
  p_operation text,
  p_request_id uuid,
  p_request_hash text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  stored_hash text;
  stored_response jsonb;
begin
  if p_request_id is null then
    return null;
  end if;

  if p_actor_user_id is null then
    raise exception using
      errcode = '42501',
      message = 'Authentication is required.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      p_actor_user_id::text || ':' || p_operation || ':' || p_request_id::text,
      0
    )
  );

  select request_hash, response
    into stored_hash, stored_response
  from public.routine_rpc_requests
  where actor_user_id = p_actor_user_id
    and operation = p_operation
    and request_id = p_request_id;

  if found then
    if stored_hash <> p_request_hash then
      raise exception using
        errcode = '22023',
        message = 'The request ID was already used with different data.';
    end if;
    return stored_response;
  end if;

  return null;
end
$function$;

create or replace function private.finish_routine_rpc_request(
  p_actor_user_id uuid,
  p_operation text,
  p_request_id uuid,
  p_request_hash text,
  p_response jsonb
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
begin
  if p_request_id is not null then
    insert into public.routine_rpc_requests (
      actor_user_id, operation, request_id, request_hash, response
    ) values (
      p_actor_user_id, p_operation, p_request_id, p_request_hash, p_response
    )
    on conflict (actor_user_id, operation, request_id) do update
      set response = excluded.response
      where public.routine_rpc_requests.request_hash = excluded.request_hash;

    if not found then
      raise exception using
        errcode = '22023',
        message = 'The request ID was already used with different data.';
    end if;
  end if;

  return p_response;
end
$function$;

create or replace function private.user_owns_coaching_routine(
  p_routine_id uuid,
  p_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select p_user_id is not null and exists (
    select 1
    from public.coaching_routines routine
    left join public.trainers trainer on trainer.id = routine.trainer_id
    left join public.gyms gym on gym.id = routine.gym_id
    where routine.id = p_routine_id
      and (
        (trainer.user_id = p_user_id and trainer.status = 'approved')
        or (gym.owner_user_id = p_user_id and gym.status = 'verified')
      )
  );
$function$;

create or replace function private.coaching_routine_json(p_routine_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $function$
  select jsonb_build_object(
    'id', routine.id,
    'trainer_id', routine.trainer_id,
    'gym_id', routine.gym_id,
    'title', routine.title,
    'intro', routine.intro,
    'price', routine.price,
    'difficulty', routine.difficulty,
    'status', routine.status,
    'reject_reason', routine.reject_reason,
    'cumulative_users', routine.cumulative_users,
    'submitted_at', routine.submitted_at,
    'submitted_by_user_id', routine.submitted_by_user_id,
    'reviewed_at', routine.reviewed_at,
    'reviewed_by_user_id', routine.reviewed_by_user_id,
    'created_at', routine.created_at,
    'updated_at', routine.updated_at,
    'exercises', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', exercise.id,
          'base_exercise_id', exercise.base_exercise_id,
          'name', exercise.name,
          'target_muscle', exercise.target_muscle,
          'order_index', exercise.order_index,
          'sets', coalesce((
            select jsonb_agg(
              jsonb_build_object(
                'id', routine_set.id,
                'set_no', routine_set.set_no,
                'type', routine_set.type,
                'target_weight', routine_set.target_weight,
                'target_reps', routine_set.target_reps,
                'rest_seconds', routine_set.rest_seconds
              ) order by routine_set.set_no, routine_set.id
            )
            from public.coaching_routine_sets routine_set
            where routine_set.routine_exercise_id = exercise.id
          ), '[]'::jsonb)
        ) order by exercise.order_index, exercise.id
      )
      from public.coaching_routine_exercises exercise
      where exercise.routine_id = routine.id
    ), '[]'::jsonb)
  )
  from public.coaching_routines routine
  where routine.id = p_routine_id;
$function$;

create or replace function private.personal_routine_json(p_routine_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $function$
  select jsonb_build_object(
    'id', routine.id,
    'owner_user_id', routine.owner_user_id,
    'name', routine.name,
    'description', routine.description,
    'color', routine.color,
    'source', routine.source,
    'market_routine_id', routine.market_routine_id,
    'source_coaching_routine_id', routine.source_coaching_routine_id,
    'source_routine_share_id', routine.source_routine_share_id,
    'created_at', routine.created_at,
    'updated_at', routine.updated_at,
    'exercises', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', exercise.id,
          'base_exercise_id', exercise.base_exercise_id,
          'name', exercise.name,
          'target_muscle', exercise.target_muscle,
          'order_index', exercise.order_index,
          'sets', coalesce((
            select jsonb_agg(
              jsonb_build_object(
                'id', routine_set.id,
                'set_no', routine_set.set_no,
                'type', routine_set.type,
                'target_weight', routine_set.target_weight,
                'target_reps', routine_set.target_reps,
                'rest_seconds', routine_set.rest_seconds
              ) order by routine_set.set_no, routine_set.id
            )
            from public.routine_sets routine_set
            where routine_set.routine_exercise_id = exercise.id
          ), '[]'::jsonb)
        ) order by exercise.order_index, exercise.id
      )
      from public.routine_exercises exercise
      where exercise.routine_id = routine.id
    ), '[]'::jsonb)
  )
  from public.routines routine
  where routine.id = p_routine_id;
$function$;

create or replace function private.routine_share_json(p_share_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $function$
  select jsonb_build_object(
    'id', share.id,
    'coaching_routine_id', share.coaching_routine_id,
    'routine_title', routine.title,
    'share_type', share.share_type,
    'sender_user_id', share.sender_user_id,
    'sender_trainer_id', share.sender_trainer_id,
    'sender_gym_id', share.sender_gym_id,
    'member_id', share.member_id,
    'recipient_user_id', share.recipient_user_id,
    'message', share.message,
    'status', case
      when share.status = 'pending' and share.expires_at <= now()
        then 'expired'
      else share.status
    end,
    'expires_at', share.expires_at,
    'responded_by_user_id', share.responded_by_user_id,
    'accepted_routine_id', share.accepted_routine_id,
    'request_id', share.request_id,
    'created_at', share.created_at,
    'responded_at', share.responded_at,
    'updated_at', share.updated_at
  )
  from public.routine_shares share
  join public.coaching_routines routine
    on routine.id = share.coaching_routine_id
  where share.id = p_share_id;
$function$;

create or replace function private.clone_coaching_routine(
  p_source_routine_id uuid,
  p_owner_user_id uuid,
  p_market_routine_id uuid default null,
  p_share_id uuid default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  source_row public.coaching_routines%rowtype;
  source_exercise record;
  new_routine_id uuid;
  new_exercise_id uuid;
  existing_routine_id uuid;
  routine_color text := '#10CEBD';
begin
  if p_owner_user_id is null then
    raise exception using
      errcode = '42501',
      message = 'Authentication is required.';
  end if;

  if p_market_routine_id is not null and p_share_id is not null then
    raise exception using
      errcode = '22023',
      message = 'A routine copy cannot have two import sources.';
  end if;

  if p_share_id is not null then
    select id into existing_routine_id
    from public.routines
    where owner_user_id = p_owner_user_id
      and source_routine_share_id = p_share_id;
  elsif p_market_routine_id is not null then
    select id into existing_routine_id
    from public.routines
    where owner_user_id = p_owner_user_id
      and market_routine_id = p_market_routine_id;
  end if;

  if existing_routine_id is not null then
    return private.personal_routine_json(existing_routine_id);
  end if;

  select * into source_row
  from public.coaching_routines
  where id = p_source_routine_id
  for update;

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'The source routine was not found.';
  end if;

  if p_market_routine_id is not null then
    select coalesce(color_hex, '#10CEBD') into routine_color
    from public.market_routines
    where id = p_market_routine_id
      and coaching_routine_id = p_source_routine_id;

    if not found then
      raise exception using
        errcode = '22023',
        message = 'The market routine does not match its source.';
    end if;
  end if;

  insert into public.routines (
    owner_user_id, name, description, color, source,
    market_routine_id, source_coaching_routine_id,
    source_routine_share_id
  ) values (
    p_owner_user_id,
    source_row.title,
    source_row.intro,
    routine_color,
    case when p_market_routine_id is null then 'copy' else 'market' end,
    p_market_routine_id,
    p_source_routine_id,
    p_share_id
  )
  returning id into new_routine_id;

  for source_exercise in
    select *
    from public.coaching_routine_exercises
    where routine_id = p_source_routine_id
    order by order_index, id
  loop
    insert into public.routine_exercises (
      routine_id, base_exercise_id, name, target_muscle, order_index
    ) values (
      new_routine_id,
      source_exercise.base_exercise_id,
      coalesce(nullif(pg_catalog.btrim(source_exercise.name), ''), '운동'),
      source_exercise.target_muscle,
      coalesce(source_exercise.order_index, 0)
    )
    returning id into new_exercise_id;

    insert into public.routine_sets (
      routine_exercise_id, set_no, type,
      target_weight, target_reps, rest_seconds
    )
    select
      new_exercise_id,
      coalesce(routine_set.set_no, (row_number() over (
        order by routine_set.id
      ))::integer),
      coalesce(routine_set.type, 'normal'),
      routine_set.target_weight,
      routine_set.target_reps,
      routine_set.rest_seconds
    from public.coaching_routine_sets routine_set
    where routine_set.routine_exercise_id = source_exercise.id
    order by routine_set.set_no, routine_set.id;
  end loop;

  update public.coaching_routines
  set cumulative_users = cumulative_users + 1,
      updated_at = now()
  where id = p_source_routine_id;

  if p_market_routine_id is not null then
    update public.market_routines
    set coaching_count = coaching_count + 1
    where id = p_market_routine_id;
  end if;

  return private.personal_routine_json(new_routine_id);
end
$function$;

create or replace function private.save_coaching_routine(
  p_routine_id uuid,
  p_owner_role text,
  p_title text,
  p_intro text,
  p_difficulty text,
  p_price numeric,
  p_exercises jsonb,
  p_request_id uuid default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  actor_user_id uuid := auth.uid();
  normalized_owner_role text := pg_catalog.lower(pg_catalog.btrim(
    coalesce(p_owner_role, '')
  ));
  normalized_title text := pg_catalog.btrim(coalesce(p_title, ''));
  normalized_intro text := nullif(pg_catalog.btrim(coalesce(p_intro, '')), '');
  normalized_difficulty text := pg_catalog.lower(pg_catalog.btrim(
    coalesce(p_difficulty, '')
  ));
  normalized_price numeric := coalesce(p_price, 0);
  owner_trainer_id uuid;
  owner_gym_id uuid;
  current_row public.coaching_routines%rowtype;
  saved_routine_id uuid;
  exercise_item jsonb;
  exercise_number bigint;
  exercise_name text;
  exercise_target text;
  base_exercise_text text;
  new_exercise_id uuid;
  sets_value jsonb;
  set_item jsonb;
  set_number bigint;
  set_type text;
  target_weight_value numeric;
  target_reps_value integer;
  rest_seconds_value integer;
  request_hash text;
  cached_response jsonb;
  response_value jsonb;
begin
  if actor_user_id is null then
    raise exception using
      errcode = '42501',
      message = 'Authentication is required.';
  end if;

  if normalized_owner_role not in ('trainer', 'gym') then
    raise exception using
      errcode = '22023',
      message = 'owner_role must be trainer or gym.';
  end if;

  if char_length(normalized_title) not between 1 and 120 then
    raise exception using
      errcode = '22023',
      message = 'Routine title must contain 1 to 120 characters.';
  end if;

  if normalized_intro is not null and char_length(normalized_intro) > 2000 then
    raise exception using
      errcode = '22023',
      message = 'Routine introduction is too long.';
  end if;

  if normalized_difficulty not in ('beginner', 'intermediate', 'advanced') then
    raise exception using
      errcode = '22023',
      message = 'Unknown routine difficulty.';
  end if;

  if normalized_price < 0 or normalized_price > 100000000 then
    raise exception using
      errcode = '22023',
      message = 'Routine price is outside the supported range.';
  end if;

  if p_exercises is null
     or jsonb_typeof(p_exercises) <> 'array'
     or jsonb_array_length(p_exercises) not between 1 and 50 then
    raise exception using
      errcode = '22023',
      message = 'A routine requires between 1 and 50 exercises.';
  end if;

  if normalized_owner_role = 'trainer' then
    select id into owner_trainer_id
    from public.trainers
    where user_id = actor_user_id
      and status = 'approved'
    limit 1;

    if owner_trainer_id is null then
      raise exception using
        errcode = '42501',
        message = 'An approved trainer profile is required.';
    end if;
  else
    select id into owner_gym_id
    from public.gyms
    where owner_user_id = actor_user_id
      and status = 'verified'
    order by created_at
    limit 1;

    if owner_gym_id is null then
      raise exception using
        errcode = '42501',
        message = 'A verified gym profile is required.';
    end if;
  end if;

  request_hash := private.routine_request_hash(jsonb_build_object(
    'routine_id', p_routine_id,
    'owner_role', normalized_owner_role,
    'title', normalized_title,
    'intro', normalized_intro,
    'difficulty', normalized_difficulty,
    'price', normalized_price,
    'exercises', p_exercises
  ));
  cached_response := private.begin_routine_rpc_request(
    actor_user_id, 'save_coaching_routine', p_request_id, request_hash
  );
  if cached_response is not null then
    return cached_response;
  end if;

  if p_routine_id is null then
    insert into public.coaching_routines (
      trainer_id, gym_id, title, intro, price, difficulty, status,
      reject_reason, submitted_at, submitted_by_user_id,
      reviewed_at, reviewed_by_user_id
    ) values (
      owner_trainer_id, owner_gym_id, normalized_title, normalized_intro,
      normalized_price, normalized_difficulty, 'draft',
      null, null, null, null, null
    )
    returning id into saved_routine_id;
  else
    select * into current_row
    from public.coaching_routines
    where id = p_routine_id
    for update;

    if not found then
      raise exception using
        errcode = 'P0002',
        message = 'The routine was not found.';
    end if;

    if current_row.status not in ('draft', 'rejected') then
      raise exception using
        errcode = '55000',
        message = 'Only draft or rejected routines can be edited.';
    end if;

    if current_row.trainer_id is distinct from owner_trainer_id
       or current_row.gym_id is distinct from owner_gym_id then
      raise exception using
        errcode = '42501',
        message = 'The routine belongs to a different workspace.';
    end if;

    update public.coaching_routines
    set title = normalized_title,
        intro = normalized_intro,
        price = normalized_price,
        difficulty = normalized_difficulty,
        status = 'draft',
        reject_reason = null,
        submitted_at = null,
        submitted_by_user_id = null,
        reviewed_at = null,
        reviewed_by_user_id = null,
        updated_at = now()
    where id = current_row.id
    returning id into saved_routine_id;

    delete from public.coaching_routine_exercises
    where routine_id = saved_routine_id;
  end if;

  for exercise_item, exercise_number in
    select value, ordinality
    from jsonb_array_elements(p_exercises) with ordinality
  loop
    if jsonb_typeof(exercise_item) <> 'object' then
      raise exception using
        errcode = '22023',
        message = 'Every exercise must be a JSON object.';
    end if;

    exercise_name := pg_catalog.btrim(coalesce(exercise_item->>'name', ''));
    exercise_target := pg_catalog.btrim(coalesce(
      exercise_item->>'target_muscle',
      exercise_item->>'targetMuscle',
      ''
    ));
    base_exercise_text := nullif(pg_catalog.btrim(coalesce(
      exercise_item->>'base_exercise_id',
      exercise_item->>'baseExerciseId',
      ''
    )), '');

    if char_length(exercise_name) not between 1 and 120 then
      raise exception using
        errcode = '22023',
        message = 'Every exercise requires a name of 1 to 120 characters.';
    end if;
    if char_length(exercise_target) not between 1 and 80 then
      raise exception using
        errcode = '22023',
        message = 'Every exercise requires a target muscle.';
    end if;

    sets_value := coalesce(exercise_item->'sets', '[]'::jsonb);
    if jsonb_typeof(sets_value) <> 'array'
       or jsonb_array_length(sets_value) not between 1 and 20 then
      raise exception using
        errcode = '22023',
        message = 'Every exercise requires between 1 and 20 sets.';
    end if;

    insert into public.coaching_routine_exercises (
      routine_id, base_exercise_id, name, target_muscle, order_index
    ) values (
      saved_routine_id,
      case when base_exercise_text is null
        then null else base_exercise_text::uuid end,
      exercise_name,
      exercise_target,
      (exercise_number - 1)::integer
    )
    returning id into new_exercise_id;

    for set_item, set_number in
      select value, ordinality
      from jsonb_array_elements(sets_value) with ordinality
    loop
      if jsonb_typeof(set_item) <> 'object' then
        raise exception using
          errcode = '22023',
          message = 'Every set must be a JSON object.';
      end if;

      set_type := pg_catalog.lower(pg_catalog.btrim(coalesce(
        set_item->>'type', 'normal'
      )));
      if set_type not in ('normal', 'warmup', 'drop', 'failure') then
        raise exception using
          errcode = '22023',
          message = 'Unknown routine set type.';
      end if;

      if coalesce(set_item->>'target_weight', set_item->>'targetWeight') is null
         or nullif(pg_catalog.btrim(coalesce(
           set_item->>'target_weight', set_item->>'targetWeight', ''
         )), '') is null then
        target_weight_value := null;
      else
        target_weight_value := coalesce(
          set_item->>'target_weight', set_item->>'targetWeight'
        )::numeric;
      end if;

      target_reps_value := nullif(pg_catalog.btrim(coalesce(
        set_item->>'target_reps', set_item->>'targetReps', ''
      )), '')::integer;
      rest_seconds_value := coalesce(nullif(pg_catalog.btrim(coalesce(
        set_item->>'rest_seconds', set_item->>'restSeconds', ''
      )), '')::integer, 90);

      if target_weight_value is not null
         and (target_weight_value < 0 or target_weight_value > 5000) then
        raise exception using
          errcode = '22023',
          message = 'Target weight is outside the supported range.';
      end if;
      if target_reps_value is null
         or target_reps_value not between 1 and 1000 then
        raise exception using
          errcode = '22023',
          message = 'Target repetitions must be between 1 and 1000.';
      end if;
      if rest_seconds_value not between 0 and 3600 then
        raise exception using
          errcode = '22023',
          message = 'Rest time must be between 0 and 3600 seconds.';
      end if;

      insert into public.coaching_routine_sets (
        routine_exercise_id, set_no, type,
        target_weight, target_reps, rest_seconds
      ) values (
        new_exercise_id,
        set_number::integer,
        set_type,
        target_weight_value,
        target_reps_value,
        rest_seconds_value
      );
    end loop;
  end loop;

  response_value := private.coaching_routine_json(saved_routine_id);
  return private.finish_routine_rpc_request(
    actor_user_id, 'save_coaching_routine', p_request_id,
    request_hash, response_value
  );
end
$function$;

create or replace function private.submit_coaching_routine_review(
  p_routine_id uuid,
  p_request_id uuid default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  actor_user_id uuid := auth.uid();
  routine_row public.coaching_routines%rowtype;
  request_hash text;
  cached_response jsonb;
  response_value jsonb;
begin
  if actor_user_id is null then
    raise exception using errcode = '42501', message = 'Authentication is required.';
  end if;

  select * into routine_row
  from public.coaching_routines
  where id = p_routine_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'The routine was not found.';
  end if;
  if not private.user_owns_coaching_routine(p_routine_id, actor_user_id) then
    raise exception using errcode = '42501', message = 'Routine ownership is required.';
  end if;

  request_hash := private.routine_request_hash(jsonb_build_object(
    'routine_id', p_routine_id
  ));
  cached_response := private.begin_routine_rpc_request(
    actor_user_id, 'submit_coaching_routine_review',
    p_request_id, request_hash
  );
  if cached_response is not null then
    return cached_response;
  end if;

  if routine_row.status = 'review' then
    response_value := private.coaching_routine_json(p_routine_id);
    return private.finish_routine_rpc_request(
      actor_user_id, 'submit_coaching_routine_review',
      p_request_id, request_hash, response_value
    );
  end if;

  if routine_row.status <> 'draft' then
    raise exception using
      errcode = '55000',
      message = 'Only a draft routine can be submitted for review.';
  end if;

  if not exists (
    select 1
    from public.coaching_routine_exercises exercise
    where exercise.routine_id = p_routine_id
  ) or exists (
    select 1
    from public.coaching_routine_exercises exercise
    where exercise.routine_id = p_routine_id
      and not exists (
        select 1
        from public.coaching_routine_sets routine_set
        where routine_set.routine_exercise_id = exercise.id
      )
  ) then
    raise exception using
      errcode = '23514',
      message = 'Every submitted exercise requires at least one set.';
  end if;

  update public.coaching_routines
  set status = 'review',
      reject_reason = null,
      submitted_at = now(),
      submitted_by_user_id = actor_user_id,
      reviewed_at = null,
      reviewed_by_user_id = null,
      updated_at = now()
  where id = p_routine_id;

  insert into public.routine_review_events (
    routine_id, action, actor_user_id, from_status, to_status, request_id
  ) values (
    p_routine_id, 'submitted', actor_user_id,
    routine_row.status, 'review', p_request_id
  );

  response_value := private.coaching_routine_json(p_routine_id);
  return private.finish_routine_rpc_request(
    actor_user_id, 'submit_coaching_routine_review',
    p_request_id, request_hash, response_value
  );
end
$function$;

create or replace function private.review_coaching_routine(
  p_routine_id uuid,
  p_decision text,
  p_reason text default null,
  p_access_tier text default 'free',
  p_request_id uuid default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  actor_user_id uuid := auth.uid();
  normalized_decision text := pg_catalog.lower(pg_catalog.btrim(
    coalesce(p_decision, '')
  ));
  normalized_reason text := nullif(pg_catalog.btrim(coalesce(p_reason, '')), '');
  normalized_access_tier text := pg_catalog.lower(pg_catalog.btrim(
    coalesce(p_access_tier, 'free')
  ));
  routine_row public.coaching_routines%rowtype;
  author_name_value text;
  market_routine_id_value uuid;
  duration_minutes_value integer;
  request_hash text;
  cached_response jsonb;
  response_value jsonb;
begin
  if actor_user_id is null or not private.is_admin() then
    raise exception using
      errcode = '42501',
      message = 'Active administrator access is required.';
  end if;

  if normalized_decision not in ('approve', 'reject') then
    raise exception using
      errcode = '22023',
      message = 'decision must be approve or reject.';
  end if;
  if normalized_decision = 'reject' and normalized_reason is null then
    raise exception using
      errcode = '22023',
      message = 'A rejection reason is required.';
  end if;
  if normalized_reason is not null and char_length(normalized_reason) > 2000 then
    raise exception using
      errcode = '22023',
      message = 'The review reason is too long.';
  end if;
  if normalized_access_tier not in ('free', 'paid') then
    raise exception using
      errcode = '22023',
      message = 'access_tier must be free or paid.';
  end if;

  request_hash := private.routine_request_hash(jsonb_build_object(
    'routine_id', p_routine_id,
    'decision', normalized_decision,
    'reason', normalized_reason,
    'access_tier', normalized_access_tier
  ));
  cached_response := private.begin_routine_rpc_request(
    actor_user_id, 'review_coaching_routine', p_request_id, request_hash
  );
  if cached_response is not null then
    return cached_response;
  end if;

  select * into routine_row
  from public.coaching_routines
  where id = p_routine_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'The routine was not found.';
  end if;

  -- Repeating the same completed decision is safe; reversing it requires a
  -- new author revision and review submission.
  if routine_row.status = 'approved' and normalized_decision = 'approve' then
    select id into market_routine_id_value
    from public.market_routines
    where coaching_routine_id = p_routine_id;
    response_value := jsonb_build_object(
      'routine', private.coaching_routine_json(p_routine_id),
      'market_routine_id', market_routine_id_value,
      'decision', 'approve'
    );
    return private.finish_routine_rpc_request(
      actor_user_id, 'review_coaching_routine', p_request_id,
      request_hash, response_value
    );
  elsif routine_row.status = 'rejected' and normalized_decision = 'reject' then
    response_value := jsonb_build_object(
      'routine', private.coaching_routine_json(p_routine_id),
      'market_routine_id', null,
      'decision', 'reject'
    );
    return private.finish_routine_rpc_request(
      actor_user_id, 'review_coaching_routine', p_request_id,
      request_hash, response_value
    );
  elsif routine_row.status <> 'review' then
    raise exception using
      errcode = '55000',
      message = 'Only a routine under review can be moderated.';
  end if;

  if normalized_decision = 'reject' then
    update public.coaching_routines
    set status = 'rejected',
        reject_reason = normalized_reason,
        reviewed_at = now(),
        reviewed_by_user_id = actor_user_id,
        updated_at = now()
    where id = p_routine_id;

    update public.market_routines
    set status = 'draft'
    where coaching_routine_id = p_routine_id;

    insert into public.routine_review_events (
      routine_id, action, actor_user_id, from_status, to_status,
      note, request_id
    ) values (
      p_routine_id, 'rejected', actor_user_id,
      routine_row.status, 'rejected', normalized_reason, p_request_id
    );

    response_value := jsonb_build_object(
      'routine', private.coaching_routine_json(p_routine_id),
      'market_routine_id', null,
      'decision', 'reject'
    );
    return private.finish_routine_rpc_request(
      actor_user_id, 'review_coaching_routine', p_request_id,
      request_hash, response_value
    );
  end if;

  if not exists (
    select 1
    from public.coaching_routine_exercises exercise
    where exercise.routine_id = p_routine_id
  ) or exists (
    select 1
    from public.coaching_routine_exercises exercise
    where exercise.routine_id = p_routine_id
      and not exists (
        select 1
        from public.coaching_routine_sets routine_set
        where routine_set.routine_exercise_id = exercise.id
      )
  ) then
    raise exception using
      errcode = '23514',
      message = 'Every approved exercise requires at least one set.';
  end if;

  select coalesce(
    nullif(pg_catalog.btrim(trainer.display_name), ''),
    nullif(pg_catalog.btrim(gym.name), ''),
    'Setflow 전문가'
  ) into author_name_value
  from public.coaching_routines routine
  left join public.trainers trainer on trainer.id = routine.trainer_id
  left join public.gyms gym on gym.id = routine.gym_id
  where routine.id = p_routine_id;

  select greatest(20, count(*)::integer * 10)
    into duration_minutes_value
  from public.coaching_routine_exercises
  where routine_id = p_routine_id;

  update public.coaching_routines
  set status = 'approved',
      reject_reason = null,
      reviewed_at = now(),
      reviewed_by_user_id = actor_user_id,
      updated_at = now()
  where id = p_routine_id;

  insert into public.market_routines (
    coaching_routine_id, trainer_id, gym_id, title, description,
    tags, difficulty, duration_min, status, access_tier,
    author_name, color_hex
  ) values (
    p_routine_id,
    routine_row.trainer_id,
    routine_row.gym_id,
    routine_row.title,
    routine_row.intro,
    array[routine_row.difficulty, '전문가 루틴']::text[],
    routine_row.difficulty,
    duration_minutes_value,
    'published',
    normalized_access_tier,
    author_name_value,
    case when routine_row.gym_id is null then '#10CEBD' else '#8B5CF6' end
  )
  on conflict (coaching_routine_id)
    where coaching_routine_id is not null
  do update set
    trainer_id = excluded.trainer_id,
    gym_id = excluded.gym_id,
    title = excluded.title,
    description = excluded.description,
    tags = excluded.tags,
    difficulty = excluded.difficulty,
    duration_min = excluded.duration_min,
    status = 'published',
    access_tier = excluded.access_tier,
    author_name = excluded.author_name
  returning id into market_routine_id_value;

  insert into public.routine_review_events (
    routine_id, action, actor_user_id, from_status, to_status,
    market_routine_id, request_id
  ) values (
    p_routine_id, 'approved', actor_user_id,
    routine_row.status, 'approved', market_routine_id_value, p_request_id
  );

  response_value := jsonb_build_object(
    'routine', private.coaching_routine_json(p_routine_id),
    'market_routine_id', market_routine_id_value,
    'decision', 'approve'
  );
  return private.finish_routine_rpc_request(
    actor_user_id, 'review_coaching_routine', p_request_id,
    request_hash, response_value
  );
end
$function$;

create or replace function private.share_coaching_routine(
  p_routine_id uuid,
  p_member_ids uuid[],
  p_message text default null,
  p_expires_at timestamptz default null,
  p_request_id uuid default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  actor_user_id uuid := auth.uid();
  routine_row public.coaching_routines%rowtype;
  normalized_message text := nullif(pg_catalog.btrim(coalesce(p_message, '')), '');
  effective_expires_at timestamptz := coalesce(p_expires_at, now() + interval '30 days');
  member_id_value uuid;
  recipient_user_id_value uuid;
  share_id_value uuid;
  share_ids uuid[] := '{}'::uuid[];
  request_hash text;
  cached_response jsonb;
  response_value jsonb;
begin
  if actor_user_id is null then
    raise exception using errcode = '42501', message = 'Authentication is required.';
  end if;
  if p_member_ids is null
     or coalesce(pg_catalog.array_length(p_member_ids, 1), 0) not between 1 and 100 then
    raise exception using
      errcode = '22023',
      message = 'Select between 1 and 100 members.';
  end if;
  if normalized_message is not null and char_length(normalized_message) > 1000 then
    raise exception using errcode = '22023', message = 'The share message is too long.';
  end if;

  request_hash := private.routine_request_hash(jsonb_build_object(
    'routine_id', p_routine_id,
    'member_ids', to_jsonb(p_member_ids),
    'message', normalized_message,
    'expires_at', p_expires_at
  ));
  cached_response := private.begin_routine_rpc_request(
    actor_user_id, 'share_coaching_routine', p_request_id, request_hash
  );
  if cached_response is not null then
    return cached_response;
  end if;

  if effective_expires_at <= now() + interval '5 minutes'
     or effective_expires_at > now() + interval '90 days' then
    raise exception using
      errcode = '22023',
      message = 'Direct shares must expire between 5 minutes and 90 days.';
  end if;

  select * into routine_row
  from public.coaching_routines
  where id = p_routine_id
  for share;

  if not found then
    raise exception using errcode = 'P0002', message = 'The routine was not found.';
  end if;
  if not private.user_owns_coaching_routine(p_routine_id, actor_user_id) then
    raise exception using errcode = '42501', message = 'Routine ownership is required.';
  end if;
  if routine_row.status not in ('draft', 'approved') then
    raise exception using
      errcode = '55000',
      message = 'Only draft or approved routines can be shared with assigned members.';
  end if;
  if not exists (
    select 1
    from public.coaching_routine_exercises exercise
    where exercise.routine_id = p_routine_id
  ) or exists (
    select 1
    from public.coaching_routine_exercises exercise
    where exercise.routine_id = p_routine_id
      and not exists (
        select 1
        from public.coaching_routine_sets routine_set
        where routine_set.routine_exercise_id = exercise.id
      )
  ) then
    raise exception using
      errcode = '23514',
      message = 'Every shared exercise requires at least one set.';
  end if;

  for member_id_value in
    select distinct selected.member_id
    from unnest(p_member_ids) as selected(member_id)
    where selected.member_id is not null
    order by selected.member_id
  loop
    recipient_user_id_value := null;

    if routine_row.trainer_id is not null then
      select member.user_id into recipient_user_id_value
      from public.members member
      join public.member_assignments assignment
        on assignment.member_id = member.id
       and assignment.active
       and assignment.trainer_id = routine_row.trainer_id
      where member.id = member_id_value
      limit 1;
    else
      select member.user_id into recipient_user_id_value
      from public.members member
      where member.id = member_id_value
        and member.gym_id = routine_row.gym_id
      limit 1;
    end if;

    if recipient_user_id_value is null then
      raise exception using
        errcode = '42501',
        message = 'Every recipient must be an assigned member with a login account.';
    end if;

    update public.routine_shares
    set status = 'expired',
        updated_at = now()
    where coaching_routine_id = p_routine_id
      and member_id = member_id_value
      and sender_user_id = actor_user_id
      and share_type = 'direct'
      and status = 'pending'
      and expires_at <= now();

    select id into share_id_value
    from public.routine_shares
    where coaching_routine_id = p_routine_id
      and member_id = member_id_value
      and sender_user_id = actor_user_id
      and share_type = 'direct'
      and status = 'pending'
    for update;

    if share_id_value is null then
      insert into public.routine_shares (
        coaching_routine_id, share_type, sender_user_id,
        sender_trainer_id, sender_gym_id,
        member_id, recipient_user_id, message, status,
        expires_at, request_id
      ) values (
        p_routine_id, 'direct', actor_user_id,
        routine_row.trainer_id, routine_row.gym_id,
        member_id_value, recipient_user_id_value, normalized_message,
        'pending', effective_expires_at, p_request_id
      )
      returning id into share_id_value;
    end if;

    share_ids := pg_catalog.array_append(share_ids, share_id_value);
  end loop;

  if coalesce(pg_catalog.array_length(share_ids, 1), 0) = 0 then
    raise exception using errcode = '22023', message = 'No valid member was selected.';
  end if;

  select coalesce(
    jsonb_agg(
      private.routine_share_json(selected.share_id)
      order by selected.share_id
    ),
    '[]'::jsonb
  ) into response_value
  from unnest(share_ids) as selected(share_id);

  return private.finish_routine_rpc_request(
    actor_user_id, 'share_coaching_routine', p_request_id,
    request_hash, response_value
  );
end
$function$;

create or replace function private.create_routine_share_link(
  p_routine_id uuid,
  p_expires_at timestamptz default null,
  p_request_id uuid default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  actor_user_id uuid := auth.uid();
  routine_row public.coaching_routines%rowtype;
  effective_expires_at timestamptz := coalesce(p_expires_at, now() + interval '7 days');
  raw_token text;
  token_hash_value bytea;
  share_id_value uuid;
  response_value jsonb;
  attempt integer;
begin
  if actor_user_id is null then
    raise exception using errcode = '42501', message = 'Authentication is required.';
  end if;

  if effective_expires_at <= now() + interval '5 minutes'
     or effective_expires_at > now() + interval '30 days' then
    raise exception using
      errcode = '22023',
      message = 'Share links must expire between 5 minutes and 30 days.';
  end if;

  select * into routine_row
  from public.coaching_routines
  where id = p_routine_id
  for share;

  if not found then
    raise exception using errcode = 'P0002', message = 'The routine was not found.';
  end if;
  if not private.user_owns_coaching_routine(p_routine_id, actor_user_id) then
    raise exception using errcode = '42501', message = 'Routine ownership is required.';
  end if;
  if routine_row.status <> 'approved' then
    raise exception using
      errcode = '55000',
      message = 'Only an approved routine can be shared by link.';
  end if;
  if not exists (
    select 1
    from public.coaching_routine_exercises exercise
    where exercise.routine_id = p_routine_id
  ) or exists (
    select 1
    from public.coaching_routine_exercises exercise
    where exercise.routine_id = p_routine_id
      and not exists (
        select 1
        from public.coaching_routine_sets routine_set
        where routine_set.routine_exercise_id = exercise.id
      )
  ) then
    raise exception using
      errcode = '23514',
      message = 'Every shared exercise requires at least one set.';
  end if;

  for attempt in 1..3 loop
    raw_token := pg_catalog.translate(
      pg_catalog.encode(extensions.gen_random_bytes(32), 'base64'),
      '+/=',
      '-_'
    );
    token_hash_value := extensions.digest(raw_token, 'sha256');

    begin
      insert into public.routine_shares (
        coaching_routine_id, share_type, sender_user_id,
        sender_trainer_id, sender_gym_id,
        token_hash, status, expires_at, request_id
      ) values (
        p_routine_id, 'link', actor_user_id,
        routine_row.trainer_id, routine_row.gym_id,
        token_hash_value, 'pending', effective_expires_at, p_request_id
      )
      returning id into share_id_value;
      exit;
    exception
      when unique_violation then
        if attempt = 3 then
          raise;
        end if;
    end;
  end loop;

  response_value := private.routine_share_json(share_id_value)
    || jsonb_build_object('token', raw_token);
  -- A raw bearer token is returned exactly once and is never persisted in the
  -- idempotency cache. Only its SHA-256 digest remains in routine_shares.
  return response_value;
end
$function$;

create or replace function private.respond_routine_share(
  p_share_id uuid,
  p_decision text,
  p_request_id uuid default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  actor_user_id uuid := auth.uid();
  normalized_decision text := pg_catalog.lower(pg_catalog.btrim(
    coalesce(p_decision, '')
  ));
  source_routine_id uuid;
  source_routine_row public.coaching_routines%rowtype;
  share_row public.routine_shares%rowtype;
  copied_routine jsonb;
  request_hash text;
  cached_response jsonb;
  response_value jsonb;
begin
  if actor_user_id is null then
    raise exception using errcode = '42501', message = 'Authentication is required.';
  end if;
  if normalized_decision not in ('accept', 'decline') then
    raise exception using
      errcode = '22023',
      message = 'decision must be accept or decline.';
  end if;

  request_hash := private.routine_request_hash(jsonb_build_object(
    'share_id', p_share_id,
    'decision', normalized_decision
  ));
  cached_response := private.begin_routine_rpc_request(
    actor_user_id, 'respond_routine_share', p_request_id, request_hash
  );
  if cached_response is not null then
    return cached_response;
  end if;

  -- Discover without locking, then acquire every mutable row in the canonical
  -- routine -> share order. Re-read the share after both locks are held.
  select share.coaching_routine_id into source_routine_id
  from public.routine_shares share
  where share.id = p_share_id
    and share.share_type = 'direct';

  if source_routine_id is null then
    raise exception using errcode = 'P0002', message = 'The direct share was not found.';
  end if;

  select * into source_routine_row
  from public.coaching_routines
  where id = source_routine_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'The shared routine was not found.';
  end if;

  select * into share_row
  from public.routine_shares
  where id = p_share_id
    and coaching_routine_id = source_routine_id
    and share_type = 'direct'
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'The direct share was not found.';
  end if;
  if share_row.recipient_user_id <> actor_user_id then
    raise exception using errcode = '42501', message = 'This routine was shared with another member.';
  end if;

  if share_row.status = 'accepted' and normalized_decision = 'accept'
     and share_row.responded_by_user_id = actor_user_id then
    response_value := jsonb_build_object(
      'share', private.routine_share_json(p_share_id),
      'routine', private.personal_routine_json(share_row.accepted_routine_id)
    );
    return private.finish_routine_rpc_request(
      actor_user_id, 'respond_routine_share', p_request_id,
      request_hash, response_value
    );
  elsif share_row.status = 'declined' and normalized_decision = 'decline'
        and share_row.responded_by_user_id = actor_user_id then
    response_value := jsonb_build_object(
      'share', private.routine_share_json(p_share_id),
      'routine', null
    );
    return private.finish_routine_rpc_request(
      actor_user_id, 'respond_routine_share', p_request_id,
      request_hash, response_value
    );
  elsif share_row.status <> 'pending' then
    raise exception using
      errcode = '55000',
      message = 'The share has already received a different response.';
  end if;

  if share_row.expires_at <= now() then
    update public.routine_shares
    set status = 'expired', updated_at = now()
    where id = p_share_id;

    response_value := jsonb_build_object(
      'share', private.routine_share_json(p_share_id),
      'routine', null
    );
    return private.finish_routine_rpc_request(
      actor_user_id, 'respond_routine_share', p_request_id,
      request_hash, response_value
    );
  end if;

  if normalized_decision = 'decline' then
    update public.routine_shares
    set status = 'declined',
        responded_by_user_id = actor_user_id,
        responded_at = now(),
        updated_at = now()
    where id = p_share_id;

    response_value := jsonb_build_object(
      'share', private.routine_share_json(p_share_id),
      'routine', null
    );
    return private.finish_routine_rpc_request(
      actor_user_id, 'respond_routine_share', p_request_id,
      request_hash, response_value
    );
  end if;

  if source_routine_row.status not in ('draft', 'approved') then
    raise exception using
      errcode = '55000',
      message = 'The shared routine cannot currently be accepted.';
  end if;
  if not exists (
    select 1
    from public.coaching_routine_exercises exercise
    where exercise.routine_id = share_row.coaching_routine_id
  ) or exists (
    select 1
    from public.coaching_routine_exercises exercise
    where exercise.routine_id = share_row.coaching_routine_id
      and not exists (
        select 1
        from public.coaching_routine_sets routine_set
        where routine_set.routine_exercise_id = exercise.id
      )
  ) then
    raise exception using
      errcode = '23514',
      message = 'The shared routine is incomplete.';
  end if;

  copied_routine := private.clone_coaching_routine(
    share_row.coaching_routine_id,
    actor_user_id,
    null,
    share_row.id
  );

  update public.routine_shares
  set status = 'accepted',
      responded_by_user_id = actor_user_id,
      accepted_routine_id = (copied_routine->>'id')::uuid,
      responded_at = now(),
      updated_at = now()
  where id = p_share_id;

  response_value := jsonb_build_object(
    'share', private.routine_share_json(p_share_id),
    'routine', copied_routine
  );
  return private.finish_routine_rpc_request(
    actor_user_id, 'respond_routine_share', p_request_id,
    request_hash, response_value
  );
end
$function$;

create or replace function private.accept_routine_share_token(
  p_token text,
  p_request_id uuid default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  actor_user_id uuid := auth.uid();
  normalized_token text := pg_catalog.btrim(coalesce(p_token, ''));
  token_hash_value bytea;
  source_routine_id uuid;
  source_routine_row public.coaching_routines%rowtype;
  share_row public.routine_shares%rowtype;
  copied_routine jsonb;
  request_hash text;
  cached_response jsonb;
  response_value jsonb;
begin
  if actor_user_id is null then
    raise exception using errcode = '42501', message = 'Authentication is required.';
  end if;
  if char_length(normalized_token) not between 40 and 200 then
    raise exception using errcode = '22023', message = 'The share token is invalid.';
  end if;

  request_hash := private.routine_request_hash(jsonb_build_object(
    'token_hash', encode(extensions.digest(normalized_token, 'sha256'), 'hex')
  ));
  cached_response := private.begin_routine_rpc_request(
    actor_user_id, 'accept_routine_share_token', p_request_id, request_hash
  );
  if cached_response is not null then
    return cached_response;
  end if;

  token_hash_value := extensions.digest(normalized_token, 'sha256');
  select share.coaching_routine_id into source_routine_id
  from public.routine_shares share
  where share.token_hash = token_hash_value
    and share.share_type = 'link';

  if source_routine_id is null then
    raise exception using errcode = 'P0002', message = 'The share token is invalid or expired.';
  end if;

  -- Match direct acceptance's routine -> share lock order. The routine lock
  -- also freezes its child revision for the duration of the atomic clone.
  select * into source_routine_row
  from public.coaching_routines
  where id = source_routine_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'The share token is invalid or expired.';
  end if;

  select * into share_row
  from public.routine_shares
  where token_hash = token_hash_value
    and share_type = 'link'
    and coaching_routine_id = source_routine_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'The share token is invalid or expired.';
  end if;

  if share_row.status = 'accepted'
     and share_row.responded_by_user_id = actor_user_id then
    response_value := jsonb_build_object(
      'share', private.routine_share_json(share_row.id),
      'routine', private.personal_routine_json(share_row.accepted_routine_id)
    );
    return private.finish_routine_rpc_request(
      actor_user_id, 'accept_routine_share_token', p_request_id,
      request_hash, response_value
    );
  elsif share_row.status <> 'pending' then
    raise exception using
      errcode = '55000',
      message = 'The share token is invalid or expired.';
  end if;

  if share_row.expires_at <= now() then
    update public.routine_shares
    set status = 'expired', updated_at = now()
    where id = share_row.id;

    response_value := jsonb_build_object(
      'share', private.routine_share_json(share_row.id),
      'routine', null
    );
    return private.finish_routine_rpc_request(
      actor_user_id, 'accept_routine_share_token', p_request_id,
      request_hash, response_value
    );
  end if;

  if source_routine_row.status <> 'approved' then
    raise exception using
      errcode = '55000',
      message = 'The linked routine is no longer approved.';
  end if;
  if not exists (
    select 1
    from public.coaching_routine_exercises exercise
    where exercise.routine_id = share_row.coaching_routine_id
  ) or exists (
    select 1
    from public.coaching_routine_exercises exercise
    where exercise.routine_id = share_row.coaching_routine_id
      and not exists (
        select 1
        from public.coaching_routine_sets routine_set
        where routine_set.routine_exercise_id = exercise.id
      )
  ) then
    raise exception using
      errcode = '23514',
      message = 'The linked routine is incomplete.';
  end if;

  copied_routine := private.clone_coaching_routine(
    share_row.coaching_routine_id,
    actor_user_id,
    null,
    share_row.id
  );

  update public.routine_shares
  set status = 'accepted',
      recipient_user_id = actor_user_id,
      responded_by_user_id = actor_user_id,
      accepted_routine_id = (copied_routine->>'id')::uuid,
      responded_at = now(),
      updated_at = now()
  where id = share_row.id;

  response_value := jsonb_build_object(
    'share', private.routine_share_json(share_row.id),
    'routine', copied_routine
  );
  return private.finish_routine_rpc_request(
    actor_user_id, 'accept_routine_share_token', p_request_id,
    request_hash, response_value
  );
end
$function$;

create or replace function private.import_market_routine(
  p_market_routine_id uuid,
  p_request_id uuid default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  actor_user_id uuid := auth.uid();
  source_routine_id uuid;
  source_routine_row public.coaching_routines%rowtype;
  market_row public.market_routines%rowtype;
  existing_routine_id uuid;
  request_hash text;
  cached_response jsonb;
  response_value jsonb;
begin
  if actor_user_id is null then
    raise exception using errcode = '42501', message = 'Authentication is required.';
  end if;

  request_hash := private.routine_request_hash(jsonb_build_object(
    'market_routine_id', p_market_routine_id
  ));
  cached_response := private.begin_routine_rpc_request(
    actor_user_id, 'import_market_routine', p_request_id, request_hash
  );
  if cached_response is not null then
    return cached_response;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      actor_user_id::text || ':market:' || p_market_routine_id::text,
      0
    )
  );

  -- Review acquires routine -> market locks. Discover the source first, then
  -- follow that same order and re-read the market row under lock.
  select market.coaching_routine_id into source_routine_id
  from public.market_routines market
  where market.id = p_market_routine_id
    and market.status = 'published';

  if source_routine_id is null then
    raise exception using errcode = 'P0002', message = 'The market routine was not found.';
  end if;

  select * into source_routine_row
  from public.coaching_routines
  where id = source_routine_id
  for update;

  if not found or source_routine_row.status <> 'approved' then
    raise exception using
      errcode = '55000',
      message = 'The market routine source is not approved.';
  end if;

  select * into market_row
  from public.market_routines
  where id = p_market_routine_id
    and status = 'published'
    and coaching_routine_id = source_routine_id
  for share;

  if not found then
    raise exception using errcode = 'P0002', message = 'The market routine was not found.';
  end if;

  if market_row.access_tier = 'paid'
     and not private.is_admin()
     and not exists (
       select 1
       from public.subscriptions subscription
       join public.plans plan on plan.id = subscription.plan_id
       where subscription.user_id = actor_user_id
         and subscription.status = 'active'
         and (
           subscription.current_period_end is null
           or subscription.current_period_end > now()
         )
         and plan.audience = 'b2c'
         and plan.price > 0
     ) then
    raise exception using
      errcode = '42501',
      message = 'An active paid plan is required for this routine.';
  end if;

  select id into existing_routine_id
  from public.routines
  where owner_user_id = actor_user_id
    and market_routine_id = p_market_routine_id;

  if existing_routine_id is not null then
    response_value := private.personal_routine_json(existing_routine_id);
  else
    response_value := private.clone_coaching_routine(
      market_row.coaching_routine_id,
      actor_user_id,
      p_market_routine_id,
      null
    );
  end if;

  return private.finish_routine_rpc_request(
    actor_user_id, 'import_market_routine', p_request_id,
    request_hash, response_value
  );
end
$function$;

-- Keep internal helpers inaccessible to Data API roles. Authenticated callers
-- may execute only the checked mutation implementations used by wrappers.
revoke all on function private.routine_request_hash(jsonb)
  from public, anon, authenticated;
revoke all on function private.begin_routine_rpc_request(uuid, text, uuid, text)
  from public, anon, authenticated;
revoke all on function private.finish_routine_rpc_request(uuid, text, uuid, text, jsonb)
  from public, anon, authenticated;
revoke all on function private.user_owns_coaching_routine(uuid, uuid)
  from public, anon, authenticated;
revoke all on function private.coaching_routine_json(uuid)
  from public, anon, authenticated;
revoke all on function private.personal_routine_json(uuid)
  from public, anon, authenticated;
revoke all on function private.routine_share_json(uuid)
  from public, anon, authenticated;
revoke all on function private.clone_coaching_routine(uuid, uuid, uuid, uuid)
  from public, anon, authenticated;

revoke all on function private.save_coaching_routine(
  uuid, text, text, text, text, numeric, jsonb, uuid
) from public, anon;
revoke all on function private.submit_coaching_routine_review(uuid, uuid)
  from public, anon;
revoke all on function private.review_coaching_routine(
  uuid, text, text, text, uuid
) from public, anon;
revoke all on function private.share_coaching_routine(
  uuid, uuid[], text, timestamptz, uuid
) from public, anon;
revoke all on function private.create_routine_share_link(
  uuid, timestamptz, uuid
) from public, anon;
revoke all on function private.respond_routine_share(uuid, text, uuid)
  from public, anon;
revoke all on function private.accept_routine_share_token(text, uuid)
  from public, anon;
revoke all on function private.import_market_routine(uuid, uuid)
  from public, anon;

grant execute on function private.save_coaching_routine(
  uuid, text, text, text, text, numeric, jsonb, uuid
), private.submit_coaching_routine_review(uuid, uuid),
  private.review_coaching_routine(uuid, text, text, text, uuid),
  private.share_coaching_routine(uuid, uuid[], text, timestamptz, uuid),
  private.create_routine_share_link(uuid, timestamptz, uuid),
  private.respond_routine_share(uuid, text, uuid),
  private.accept_routine_share_token(text, uuid),
  private.import_market_routine(uuid, uuid)
  to authenticated, service_role;

grant execute on function private.routine_request_hash(jsonb),
  private.begin_routine_rpc_request(uuid, text, uuid, text),
  private.finish_routine_rpc_request(uuid, text, uuid, text, jsonb),
  private.user_owns_coaching_routine(uuid, uuid),
  private.coaching_routine_json(uuid),
  private.personal_routine_json(uuid),
  private.routine_share_json(uuid),
  private.clone_coaching_routine(uuid, uuid, uuid, uuid)
  to service_role;

create or replace function public.save_coaching_routine(
  routine_id uuid,
  owner_role text,
  title text,
  intro text,
  difficulty text,
  price numeric,
  exercises jsonb,
  request_id uuid default null
)
returns jsonb
language sql
volatile
security invoker
set search_path = ''
as $function$
  select private.save_coaching_routine($1, $2, $3, $4, $5, $6, $7, $8);
$function$;

create or replace function public.submit_coaching_routine_review(
  routine_id uuid,
  request_id uuid default null
)
returns jsonb
language sql
volatile
security invoker
set search_path = ''
as $function$
  select private.submit_coaching_routine_review($1, $2);
$function$;

create or replace function public.review_coaching_routine(
  routine_id uuid,
  decision text,
  reason text default null,
  access_tier text default 'free',
  request_id uuid default null
)
returns jsonb
language sql
volatile
security invoker
set search_path = ''
as $function$
  select private.review_coaching_routine($1, $2, $3, $4, $5);
$function$;

create or replace function public.share_coaching_routine(
  routine_id uuid,
  member_ids uuid[],
  message text default null,
  expires_at timestamptz default null,
  request_id uuid default null
)
returns jsonb
language sql
volatile
security invoker
set search_path = ''
as $function$
  select private.share_coaching_routine($1, $2, $3, $4, $5);
$function$;

create or replace function public.create_routine_share_link(
  routine_id uuid,
  expires_at timestamptz default null,
  request_id uuid default null
)
returns jsonb
language sql
volatile
security invoker
set search_path = ''
as $function$
  select private.create_routine_share_link($1, $2, $3);
$function$;

create or replace function public.respond_routine_share(
  share_id uuid,
  decision text,
  request_id uuid default null
)
returns jsonb
language sql
volatile
security invoker
set search_path = ''
as $function$
  select private.respond_routine_share($1, $2, $3);
$function$;

create or replace function public.accept_routine_share_token(
  token text,
  request_id uuid default null
)
returns jsonb
language sql
volatile
security invoker
set search_path = ''
as $function$
  select private.accept_routine_share_token($1, $2);
$function$;

create or replace function public.import_market_routine(
  market_routine_id uuid,
  request_id uuid default null
)
returns jsonb
language sql
volatile
security invoker
set search_path = ''
as $function$
  select private.import_market_routine($1, $2);
$function$;

revoke all on function public.save_coaching_routine(
  uuid, text, text, text, text, numeric, jsonb, uuid
) from public, anon, authenticated;
revoke all on function public.submit_coaching_routine_review(uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.review_coaching_routine(
  uuid, text, text, text, uuid
) from public, anon, authenticated;
revoke all on function public.share_coaching_routine(
  uuid, uuid[], text, timestamptz, uuid
) from public, anon, authenticated;
revoke all on function public.create_routine_share_link(
  uuid, timestamptz, uuid
) from public, anon, authenticated;
revoke all on function public.respond_routine_share(uuid, text, uuid)
  from public, anon, authenticated;
revoke all on function public.accept_routine_share_token(text, uuid)
  from public, anon, authenticated;
revoke all on function public.import_market_routine(uuid, uuid)
  from public, anon, authenticated;

grant execute on function public.save_coaching_routine(
  uuid, text, text, text, text, numeric, jsonb, uuid
), public.submit_coaching_routine_review(uuid, uuid),
  public.review_coaching_routine(uuid, text, text, text, uuid),
  public.share_coaching_routine(uuid, uuid[], text, timestamptz, uuid),
  public.create_routine_share_link(uuid, timestamptz, uuid),
  public.respond_routine_share(uuid, text, uuid),
  public.accept_routine_share_token(text, uuid),
  public.import_market_routine(uuid, uuid)
  to authenticated, service_role;

comment on function public.save_coaching_routine(
  uuid, text, text, text, text, numeric, jsonb, uuid
) is 'Atomically creates or replaces an owned draft routine and all exercises/sets.';
comment on function public.submit_coaching_routine_review(uuid, uuid)
  is 'Moves an owned complete draft into review with idempotent request support.';
comment on function public.review_coaching_routine(
  uuid, text, text, text, uuid
) is 'Admin-only approval/rejection; approval atomically publishes market_routines.';
comment on function public.share_coaching_routine(
  uuid, uuid[], text, timestamptz, uuid
) is 'Shares a draft/approved routine with actively assigned members.';
comment on function public.create_routine_share_link(
  uuid, timestamptz, uuid
) is 'Creates an expiring approved-routine link; raw token is returned only by this RPC.';
comment on function public.respond_routine_share(uuid, text, uuid)
  is 'Accepts/declines a direct share; acceptance atomically copies all child sets.';
comment on function public.accept_routine_share_token(text, uuid)
  is 'Consumes an expiring hashed link token and atomically copies its routine.';
comment on function public.import_market_routine(uuid, uuid)
  is 'Idempotently imports a published market routine with all exercises and sets.';

commit;
