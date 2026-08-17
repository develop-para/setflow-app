-- Keep the trainer dashboard usable under the hardened column grants. The
-- previous security-invoker view projected trainers.user_id even though the
-- authenticated role intentionally cannot read that private identifier.
-- Dashboard consumers only need the trainer id and aggregate metrics.

begin;

revoke all on table public.v_trainer_dashboard
  from public, anon, authenticated;

drop view public.v_trainer_dashboard;

create view public.v_trainer_dashboard
with (security_invoker = true)
as
select
  t.id as trainer_id,
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

comment on view public.v_trainer_dashboard is
  'Trainer dashboard aggregates without exposing private trainer account identifiers.';

revoke all on table public.v_trainer_dashboard
  from public, anon, authenticated;
grant select on table public.v_trainer_dashboard
  to authenticated, service_role;

commit;
