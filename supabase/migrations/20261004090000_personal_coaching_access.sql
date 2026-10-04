-- Feature ownership belongs to the payment backend, never the client snapshot.
create table private.personal_coaching_plans (
  plan_id uuid primary key references public.plans(id) on delete cascade
);
alter table private.personal_coaching_plans enable row level security;
revoke all on table private.personal_coaching_plans from public, anon, authenticated;
grant select, insert, update, delete on table private.personal_coaching_plans to service_role;

create or replace function public.get_my_personal_coaching_access()
returns jsonb
language sql stable security definer
set search_path = ''
as $$
  select jsonb_build_object('user_id', subscription.user_id,
                           'expires_at', subscription.current_period_end)
    from public.subscriptions subscription
    join public.plans plan on plan.id = subscription.plan_id
    join private.personal_coaching_plans feature on feature.plan_id = plan.id
   where subscription.user_id = (select auth.uid())
     and subscription.status = 'active'
     and subscription.current_period_end > now()
     and plan.audience = 'b2c'
     and plan.price > 0
   order by subscription.current_period_end desc
   limit 1;
$$;

revoke all on function public.get_my_personal_coaching_access() from public, anon;
grant execute on function public.get_my_personal_coaching_access() to authenticated;
