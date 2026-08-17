begin;

-- This is intentionally a post-20260816093402 delta. The routine sharing
-- migration is already deployed, so changing that historical file would not
-- replace its live functions.

create index if not exists business_membership_end_requests_actor_idx
  on private.business_membership_end_requests (ended_by_user_id);

create or replace function private.assert_active_routine_share_targets(
  p_routine_id uuid,
  p_member_ids uuid[]
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_routine public.coaching_routines%rowtype;
  v_member public.members%rowtype;
  v_member_id uuid;
begin
  select routine.* into v_routine
  from public.coaching_routines routine
  where routine.id = p_routine_id
  for share;
  if not found then
    return;
  end if;

  for v_member_id in
    select distinct selected.member_id
    from pg_catalog.unnest(p_member_ids) as selected(member_id)
    where selected.member_id is not null
    order by selected.member_id
  loop
    select member.* into v_member
    from public.members member
    where member.id = v_member_id
      and member.status = 'active'
      and member.user_id is not null
    for key share;
    if not found then
      raise exception using
        errcode = '42501',
        message = 'Every recipient must have an active membership.';
    end if;

    if v_routine.trainer_id is not null then
      if not exists (
        select 1
        from public.member_assignments assignment
        where assignment.member_id = v_member.id
          and assignment.gym_id = v_member.gym_id
          and assignment.trainer_id = v_routine.trainer_id
          and assignment.active
      ) then
        raise exception using
          errcode = '42501',
          message = 'Every recipient must be actively assigned to the trainer.';
      end if;
    elsif v_routine.gym_id is null
       or v_member.gym_id is distinct from v_routine.gym_id then
      raise exception using
        errcode = '42501',
        message = 'Every recipient must be an active member of the routine gym.';
    end if;
  end loop;
end
$function$;

create or replace function private.assert_active_direct_routine_share_recipient(
  p_share_id uuid,
  p_actor_user_id uuid
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_member_id uuid;
begin
  -- This discovery read deliberately does not lock routine_shares. The legacy
  -- responder keeps its canonical routine -> share lock order.
  select share.member_id into v_member_id
  from public.routine_shares share
  where share.id = p_share_id
    and share.share_type = 'direct'
    and share.recipient_user_id = p_actor_user_id;

  if v_member_id is null then
    return;
  end if;

  perform 1
  from public.members member
  where member.id = v_member_id
    and member.user_id = p_actor_user_id
    and member.status = 'active'
  for key share;
  if not found then
    raise exception using
      errcode = '55000',
      message = 'This routine share no longer has an active membership.';
  end if;
end
$function$;

revoke all on function private.assert_active_routine_share_targets(uuid, uuid[])
  from public, anon, authenticated;
revoke all on function private.assert_active_direct_routine_share_recipient(uuid, uuid)
  from public, anon, authenticated;
grant execute on function private.assert_active_routine_share_targets(uuid, uuid[]),
  private.assert_active_direct_routine_share_recipient(uuid, uuid)
  to service_role;

-- Preserve the deployed implementation, including request hash validation and
-- response caching, behind an active-membership precondition.
do $migration$
begin
  if pg_catalog.to_regprocedure(
    'private.share_coaching_routine_before_active_membership(uuid,uuid[],text,timestamp with time zone,uuid)'
  ) is null then
    alter function private.share_coaching_routine(
      uuid, uuid[], text, timestamptz, uuid
    ) rename to share_coaching_routine_before_active_membership;
  end if;

  if pg_catalog.to_regprocedure(
    'private.respond_routine_share_before_active_membership(uuid,text,uuid)'
  ) is null then
    alter function private.respond_routine_share(uuid, text, uuid)
      rename to respond_routine_share_before_active_membership;
  end if;
end
$migration$;

revoke all on function private.share_coaching_routine_before_active_membership(
  uuid, uuid[], text, timestamptz, uuid
) from public, anon, authenticated;
revoke all on function private.respond_routine_share_before_active_membership(
  uuid, text, uuid
) from public, anon, authenticated;
grant execute on function private.share_coaching_routine_before_active_membership(
  uuid, uuid[], text, timestamptz, uuid
), private.respond_routine_share_before_active_membership(uuid, text, uuid)
  to service_role;

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
  v_actor_user_id uuid := (select auth.uid());
begin
  if v_actor_user_id is null then
    raise exception using errcode = '42501', message = 'Authentication is required.';
  end if;
  if p_member_ids is null
     or coalesce(pg_catalog.array_length(p_member_ids, 1), 0) not between 1 and 100 then
    raise exception using
      errcode = '22023',
      message = 'Select between 1 and 100 members.';
  end if;

  -- Avoid disclosing target membership state to a caller who does not own the
  -- source routine; the deployed implementation returns the ownership error.
  if private.user_owns_coaching_routine(p_routine_id, v_actor_user_id) then
    perform private.assert_active_routine_share_targets(
      p_routine_id,
      p_member_ids
    );
  end if;

  return private.share_coaching_routine_before_active_membership(
    p_routine_id,
    p_member_ids,
    p_message,
    p_expires_at,
    p_request_id
  );
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
  v_actor_user_id uuid := (select auth.uid());
begin
  if v_actor_user_id is null then
    raise exception using errcode = '42501', message = 'Authentication is required.';
  end if;

  -- This runs before the deployed responder's idempotency-cache replay, so an
  -- old request cannot accept or replay a direct share after membership ends.
  perform private.assert_active_direct_routine_share_recipient(
    p_share_id,
    v_actor_user_id
  );

  return private.respond_routine_share_before_active_membership(
    p_share_id,
    p_decision,
    p_request_id
  );
end
$function$;

revoke all on function private.share_coaching_routine(
  uuid, uuid[], text, timestamptz, uuid
) from public, anon, authenticated;
revoke all on function private.respond_routine_share(uuid, text, uuid)
  from public, anon, authenticated;
grant execute on function private.share_coaching_routine(
  uuid, uuid[], text, timestamptz, uuid
), private.respond_routine_share(uuid, text, uuid)
  to authenticated, service_role;

-- Rebind exposed wrappers explicitly. This avoids relying on whether an
-- existing SQL-language body retained the renamed private function's OID.
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

revoke all on function public.share_coaching_routine(
  uuid, uuid[], text, timestamptz, uuid
) from public, anon, authenticated;
revoke all on function public.respond_routine_share(uuid, text, uuid)
  from public, anon, authenticated;
grant execute on function public.share_coaching_routine(
  uuid, uuid[], text, timestamptz, uuid
), public.respond_routine_share(uuid, text, uuid)
  to authenticated, service_role;

-- Defense in depth for every writer, including service jobs: a direct share
-- cannot be inserted or moved to accepted/declined for an ended membership.
create or replace function private.enforce_active_direct_routine_share()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if new.share_type = 'direct'
     and new.status in ('pending', 'accepted', 'declined')
     and not exists (
       select 1
       from public.members member
       where member.id = new.member_id
         and member.user_id = new.recipient_user_id
         and member.status = 'active'
     ) then
    raise exception using
      errcode = '23503',
      message = 'A direct routine share requires an active membership.';
  end if;
  return new;
end
$function$;

drop trigger if exists routine_shares_active_membership_guard
  on public.routine_shares;
create trigger routine_shares_active_membership_guard
before insert or update of member_id, recipient_user_id, share_type, status
on public.routine_shares
for each row execute function private.enforce_active_direct_routine_share();

-- Ending a membership invalidates all outstanding direct offers in the same
-- transaction. Expired is used because the relationship became ineligible;
-- revoked remains reserved for an explicit sender action.
create or replace function private.expire_ended_membership_routine_shares()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if old.status = 'active' and new.status = 'ended' then
    update public.routine_shares
    set status = 'expired',
        updated_at = statement_timestamp()
    where member_id = new.id
      and share_type = 'direct'
      and status = 'pending';
  end if;
  return new;
end
$function$;

drop trigger if exists members_expire_pending_routine_shares
  on public.members;
create trigger members_expire_pending_routine_shares
after update of status on public.members
for each row execute function private.expire_ended_membership_routine_shares();

revoke all on function private.enforce_active_direct_routine_share()
  from public, anon, authenticated;
revoke all on function private.expire_ended_membership_routine_shares()
  from public, anon, authenticated;

-- A link share remains portable after acceptance. A direct share is private
-- center/trainer content and therefore remains readable only while the exact
-- member row connected to the recipient is active.
create or replace function private.can_read_active_shared_coaching_routine(
  p_routine_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select (select auth.uid()) is not null
    and p_routine_id is not null
    and exists (
      select 1
      from public.routine_shares share
      where share.coaching_routine_id = p_routine_id
        and share.recipient_user_id = (select auth.uid())
        and share.status in ('pending', 'accepted')
        and (share.status = 'accepted' or share.expires_at > now())
        and (
          share.share_type = 'link'
          or (
            share.share_type = 'direct'
            and exists (
              select 1
              from public.members member
              where member.id = share.member_id
                and member.user_id = (select auth.uid())
                and member.status = 'active'
            )
          )
        )
    );
$function$;

revoke all on function private.can_read_active_shared_coaching_routine(uuid)
  from public, anon, authenticated;
grant execute on function private.can_read_active_shared_coaching_routine(uuid)
  to authenticated, service_role;

drop policy if exists read_coaching_routines_authenticated
  on public.coaching_routines;
create policy read_coaching_routines_authenticated
  on public.coaching_routines for select to authenticated
  using (
    status = 'approved'
    or (select public.owns_trainer(trainer_id))
    or (select public.owns_gym(gym_id))
    or (select public.is_admin())
    or (select private.can_read_active_shared_coaching_routine(id))
  );

drop policy if exists read_coaching_exercises_authenticated
  on public.coaching_routine_exercises;
create policy read_coaching_exercises_authenticated
  on public.coaching_routine_exercises for select to authenticated
  using (
    exists (
      select 1
      from public.coaching_routines routine
      where routine.id = coaching_routine_exercises.routine_id
        and (
          (select public.owns_trainer(routine.trainer_id))
          or (select public.owns_gym(routine.gym_id))
          or (select public.is_admin())
          or (select private.can_read_active_shared_coaching_routine(routine.id))
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

drop policy if exists read_coaching_sets_authenticated
  on public.coaching_routine_sets;
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
          or (select private.can_read_active_shared_coaching_routine(routine.id))
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

comment on function public.share_coaching_routine(
  uuid, uuid[], text, timestamptz, uuid
) is 'Shares a routine only with currently active assigned members.';
comment on function public.respond_routine_share(uuid, text, uuid)
  is 'Accepts or declines a direct share only while its membership remains active.';

commit;
