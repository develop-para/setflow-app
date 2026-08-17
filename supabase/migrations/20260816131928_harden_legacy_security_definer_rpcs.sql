-- Move the six legacy public SECURITY DEFINER functions behind checked
-- private implementations. Public signatures stay compatible, but are now
-- SECURITY INVOKER so Supabase's exposed-schema advisor no longer flags them.

create or replace function private.can_access_member(m_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select (select auth.uid()) is not null
    and m_id is not null
    and exists (
      select 1
      from public.members m
      where m.id = m_id
        and m.status = 'active'
        and (
          exists (
            select 1
            from public.gyms g
            where g.id = m.gym_id
              and g.owner_user_id = (select auth.uid())
              and g.status = 'verified'
          )
          or exists (
            select 1
            from public.member_assignments ma
            join public.trainers t
              on t.id = ma.trainer_id
             and t.user_id = (select auth.uid())
             and t.status = 'approved'
            join public.gym_trainers gt
              on gt.gym_id = m.gym_id
             and gt.trainer_id = t.id
             and gt.trainer_user_id = (select auth.uid())
             and gt.status = 'active'
            join public.gyms g
              on g.id = gt.gym_id
             and g.status = 'verified'
            where ma.member_id = m.id
              and ma.gym_id = m.gym_id
              and ma.active
          )
        )
    );
$function$;

create or replace function public.can_access_member(m_id uuid)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $function$
  select private.can_access_member($1);
$function$;

create or replace function private.apply_routine(
  p_routine uuid,
  p_date date
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_session_id uuid;
  v_ex record;
  v_new_exercise_id uuid;
begin
  if v_uid is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;
  if p_routine is null or p_date is null then
    raise exception using errcode = '22023', message = 'Routine and date are required';
  end if;
  if not exists (
    select 1
    from public.routines r
    where r.id = p_routine
      and r.owner_user_id = v_uid
  ) then
    raise exception using errcode = '42501', message = 'An owned routine is required';
  end if;

  insert into public.workout_sessions (user_id, date)
  values (v_uid, p_date)
  on conflict (user_id, date) do nothing;

  select ws.id
    into v_session_id
  from public.workout_sessions ws
  where ws.user_id = v_uid
    and ws.date = p_date;

  for v_ex in
    select re.*
    from public.routine_exercises re
    where re.routine_id = p_routine
    order by re.order_index, re.id
  loop
    insert into public.workout_exercises (
      session_id,
      base_exercise_id,
      name,
      target_muscle,
      order_index
    ) values (
      v_session_id,
      v_ex.base_exercise_id,
      v_ex.name,
      v_ex.target_muscle,
      v_ex.order_index
    )
    returning id into v_new_exercise_id;

    insert into public.workout_sets (
      exercise_id,
      set_no,
      type,
      weight,
      reps,
      completed
    )
    select
      v_new_exercise_id,
      rs.set_no,
      coalesce(rs.type, 'normal'),
      coalesce(rs.target_weight, 0),
      coalesce(rs.target_reps, 0),
      false
    from public.routine_sets rs
    where rs.routine_exercise_id = v_ex.id
    order by rs.set_no;
  end loop;

  return v_session_id;
end
$function$;

create or replace function public.apply_routine(
  p_routine uuid,
  p_date date
)
returns uuid
language sql
volatile
security invoker
set search_path = ''
as $function$
  select private.apply_routine($1, $2);
$function$;

create or replace function private.copy_session(
  p_from date,
  p_to date
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_source_id uuid;
  v_destination_id uuid;
  v_ex record;
  v_new_exercise_id uuid;
begin
  if v_uid is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;
  if p_from is null or p_to is null or p_from = p_to then
    raise exception using errcode = '22023', message = 'Distinct source and target dates are required';
  end if;

  select ws.id
    into v_source_id
  from public.workout_sessions ws
  where ws.user_id = v_uid
    and ws.date = p_from;
  if not found then
    raise exception using errcode = 'P0002', message = 'Owned source session not found';
  end if;

  insert into public.workout_sessions (user_id, date)
  values (v_uid, p_to)
  on conflict (user_id, date) do nothing;
  select ws.id
    into v_destination_id
  from public.workout_sessions ws
  where ws.user_id = v_uid
    and ws.date = p_to;

  for v_ex in
    select we.*
    from public.workout_exercises we
    where we.session_id = v_source_id
    order by we.order_index, we.id
  loop
    insert into public.workout_exercises (
      session_id,
      base_exercise_id,
      name,
      target_muscle,
      order_index
    ) values (
      v_destination_id,
      v_ex.base_exercise_id,
      v_ex.name,
      v_ex.target_muscle,
      v_ex.order_index
    )
    returning id into v_new_exercise_id;

    insert into public.workout_sets (
      exercise_id,
      set_no,
      type,
      weight,
      reps,
      completed
    )
    select
      v_new_exercise_id,
      ws.set_no,
      ws.type,
      ws.weight,
      ws.reps,
      false
    from public.workout_sets ws
    where ws.exercise_id = v_ex.id
    order by ws.set_no;
  end loop;

  return v_destination_id;
end
$function$;

create or replace function public.copy_session(
  p_from date,
  p_to date
)
returns uuid
language sql
volatile
security invoker
set search_path = ''
as $function$
  select private.copy_session($1, $2);
$function$;

create or replace function private.reconcile_ledger(p_date date)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_payments numeric;
  v_ledger numeric;
  v_diff numeric;
  v_run_id uuid;
begin
  if v_uid is null or not private.is_admin() then
    raise exception using errcode = '42501', message = 'Active administrator access required';
  end if;
  if p_date is null or p_date > current_date then
    raise exception using errcode = '22023', message = 'A non-future reconciliation date is required';
  end if;

  select coalesce(sum(p.amount), 0)
    into v_payments
  from public.payments p
  where p.status = 'paid'
    and p.paid_at::date <= p_date;
  select coalesce(sum(le.debit), 0)
    into v_ledger
  from public.ledger_entries le
  join public.ledger_accounts a on a.id = le.account_id
  where a.code = 'CASH'
    and le.ref_type = 'payment'
    and le.entry_date <= p_date;
  v_diff := v_payments - v_ledger;

  insert into public.reconciliation_runs (
    recon_type,
    period_key,
    status,
    total_left,
    total_right,
    diff,
    run_by
  ) values (
    'payment_vs_ledger',
    p_date::text,
    case when v_diff = 0 then 'matched' else 'mismatched' end,
    v_payments,
    v_ledger,
    v_diff,
    v_uid
  )
  returning id into v_run_id;
  return v_run_id;
end
$function$;

create or replace function public.reconcile_ledger(p_date date)
returns uuid
language sql
volatile
security invoker
set search_path = ''
as $function$
  select private.reconcile_ledger($1);
$function$;

create or replace function private.request_approval(
  p_action text,
  p_ttype text,
  p_tid uuid,
  p_payload jsonb
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_action text := nullif(btrim(p_action), '');
  v_target_type text := nullif(btrim(p_ttype), '');
  v_payload jsonb := coalesce(p_payload, '{}'::jsonb);
  v_id uuid;
begin
  if v_uid is null or not private.is_admin() then
    raise exception using errcode = '42501', message = 'Active administrator access required';
  end if;
  if v_action is null
     or char_length(v_action) > 80
     or v_action !~ '^[a-zA-Z0-9_.:-]+$'
     or v_target_type is null
     or char_length(v_target_type) > 80
     or v_target_type !~ '^[a-zA-Z0-9_.:-]+$'
     or jsonb_typeof(v_payload) <> 'object'
     or octet_length(v_payload::text) > 65536 then
    raise exception using errcode = '22023', message = 'Approval request payload is invalid';
  end if;

  insert into public.admin_approvals (
    action_type,
    target_type,
    target_id,
    maker_id,
    payload
  ) values (
    v_action,
    v_target_type,
    p_tid,
    v_uid,
    v_payload
  )
  returning id into v_id;
  return v_id;
end
$function$;

create or replace function public.request_approval(
  p_action text,
  p_ttype text,
  p_tid uuid,
  p_payload jsonb
)
returns uuid
language sql
volatile
security invoker
set search_path = ''
as $function$
  select private.request_approval($1, $2, $3, $4);
$function$;

create or replace function private.resolve_approval(
  p_id uuid,
  p_decision text
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_approval public.admin_approvals%rowtype;
begin
  if v_uid is null or not private.is_admin() then
    raise exception using errcode = '42501', message = 'Active administrator access required';
  end if;
  if p_id is null or p_decision not in ('approved', 'rejected') then
    raise exception using errcode = '22023', message = 'Approval decision is invalid';
  end if;

  select a.*
    into v_approval
  from public.admin_approvals a
  where a.id = p_id
    and a.status = 'pending'
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Pending approval not found';
  end if;
  if v_approval.maker_id = v_uid then
    raise exception using errcode = '42501', message = 'Maker cannot resolve the same approval';
  end if;

  update public.admin_approvals
  set status = p_decision,
      checker_id = v_uid,
      resolved_at = now()
  where id = p_id;
end
$function$;

create or replace function public.resolve_approval(
  p_id uuid,
  p_decision text
)
returns void
language sql
volatile
security invoker
set search_path = ''
as $function$
  select private.resolve_approval($1, $2);
$function$;

-- Explicit privileges avoid PostgreSQL's default EXECUTE-to-PUBLIC behavior.
revoke all on function private.can_access_member(uuid) from public, anon;
revoke all on function private.apply_routine(uuid, date) from public, anon;
revoke all on function private.copy_session(date, date) from public, anon;
revoke all on function private.reconcile_ledger(date) from public, anon;
revoke all on function private.request_approval(text, text, uuid, jsonb)
  from public, anon;
revoke all on function private.resolve_approval(uuid, text) from public, anon;
grant execute on function private.can_access_member(uuid),
  private.apply_routine(uuid, date),
  private.copy_session(date, date),
  private.reconcile_ledger(date),
  private.request_approval(text, text, uuid, jsonb),
  private.resolve_approval(uuid, text)
  to authenticated, service_role;

revoke all on function public.can_access_member(uuid) from public, anon;
revoke all on function public.apply_routine(uuid, date) from public, anon;
revoke all on function public.copy_session(date, date) from public, anon;
revoke all on function public.reconcile_ledger(date) from public, anon;
revoke all on function public.request_approval(text, text, uuid, jsonb)
  from public, anon;
revoke all on function public.resolve_approval(uuid, text) from public, anon;
grant execute on function public.can_access_member(uuid),
  public.apply_routine(uuid, date),
  public.copy_session(date, date),
  public.reconcile_ledger(date),
  public.request_approval(text, text, uuid, jsonb),
  public.resolve_approval(uuid, text)
  to authenticated, service_role;

-- Replace two legacy ALL policies that over-granted consent and contract
-- mutation rights. Members control only their own active membership consent;
-- business participants get the minimum contract/read access they need.
drop policy if exists rw_marketing on public.marketing_consents;
drop policy if exists marketing_consents_participant_read
  on public.marketing_consents;
drop policy if exists marketing_consents_member_insert
  on public.marketing_consents;
drop policy if exists marketing_consents_member_update
  on public.marketing_consents;
drop policy if exists marketing_consents_member_delete
  on public.marketing_consents;

create policy marketing_consents_participant_read
on public.marketing_consents
for select
to authenticated
using (
  exists (
    select 1
    from public.members m
    where m.id = marketing_consents.member_id
      and m.user_id = (select auth.uid())
  )
  or (select public.can_access_member(marketing_consents.member_id))
  or (select private.is_admin())
);

create policy marketing_consents_member_insert
on public.marketing_consents
for insert
to authenticated
with check (
  exists (
    select 1
    from public.members m
    where m.id = marketing_consents.member_id
      and m.user_id = (select auth.uid())
      and m.status = 'active'
  )
);

create policy marketing_consents_member_update
on public.marketing_consents
for update
to authenticated
using (
  exists (
    select 1
    from public.members m
    where m.id = marketing_consents.member_id
      and m.user_id = (select auth.uid())
      and m.status = 'active'
  )
)
with check (
  exists (
    select 1
    from public.members m
    where m.id = marketing_consents.member_id
      and m.user_id = (select auth.uid())
      and m.status = 'active'
  )
);

create policy marketing_consents_member_delete
on public.marketing_consents
for delete
to authenticated
using (
  exists (
    select 1
    from public.members m
    where m.id = marketing_consents.member_id
      and m.user_id = (select auth.uid())
      and m.status = 'active'
  )
);

create or replace function private.set_marketing_consent_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $function$
begin
  new.updated_at := now();
  return new;
end
$function$;

revoke all on function private.set_marketing_consent_updated_at()
  from public, anon, authenticated;
drop trigger if exists marketing_consents_set_updated_at
  on public.marketing_consents;
create trigger marketing_consents_set_updated_at
before insert or update on public.marketing_consents
for each row execute function private.set_marketing_consent_updated_at();

revoke all on table public.marketing_consents from anon, authenticated;
grant select (member_id, opt_in, updated_at)
  on table public.marketing_consents to authenticated;
grant insert (member_id, opt_in)
  on table public.marketing_consents to authenticated;
grant update (opt_in)
  on table public.marketing_consents to authenticated;
grant delete on table public.marketing_consents to authenticated;
grant all on table public.marketing_consents to service_role;

drop policy if exists rw_contracts on public.coaching_contracts;
drop policy if exists coaching_contracts_participant_read
  on public.coaching_contracts;
drop policy if exists coaching_contracts_business_insert
  on public.coaching_contracts;
drop policy if exists coaching_contracts_business_update
  on public.coaching_contracts;
drop policy if exists coaching_contracts_admin_delete
  on public.coaching_contracts;

create policy coaching_contracts_participant_read
on public.coaching_contracts
for select
to authenticated
using (
  exists (
    select 1
    from public.members m
    where m.id = coaching_contracts.member_id
      and m.user_id = (select auth.uid())
  )
  or (select public.can_access_member(coaching_contracts.member_id))
  or (select private.is_admin())
);

create policy coaching_contracts_business_insert
on public.coaching_contracts
for insert
to authenticated
with check (
  (select public.can_access_member(coaching_contracts.member_id))
  or (select private.is_admin())
);

create policy coaching_contracts_business_update
on public.coaching_contracts
for update
to authenticated
using (
  (select public.can_access_member(coaching_contracts.member_id))
  or (select private.is_admin())
)
with check (
  (select public.can_access_member(coaching_contracts.member_id))
  or (select private.is_admin())
);

create policy coaching_contracts_admin_delete
on public.coaching_contracts
for delete
to authenticated
using ((select private.is_admin()));

create index if not exists coaching_contracts_member_id_idx
  on public.coaching_contracts (member_id);

revoke all on table public.coaching_contracts from anon, authenticated;
grant select (id, member_id, product_name, start_date, end_date, created_at)
  on table public.coaching_contracts to authenticated;
grant insert (member_id, product_name, start_date, end_date)
  on table public.coaching_contracts to authenticated;
grant update (product_name, start_date, end_date)
  on table public.coaching_contracts to authenticated;
grant delete on table public.coaching_contracts to authenticated;
grant all on table public.coaching_contracts to service_role;
