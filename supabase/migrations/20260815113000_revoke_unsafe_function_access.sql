-- SECURITY DEFINER functions must not inherit PostgreSQL's default PUBLIC
-- execute privilege. Keep user-context helpers available only after sign-in;
-- scheduled/admin/trigger functions are service-only.

revoke execute on function public.can_access_member(uuid)
  from public, anon;
revoke execute on function public.can_access_member_workout(uuid)
  from public, anon;
revoke execute on function public.is_admin()
  from public, anon;
revoke execute on function public.owns_gym(uuid)
  from public, anon;
revoke execute on function public.owns_trainer(uuid)
  from public, anon;

grant execute on function public.can_access_member(uuid)
  to authenticated, service_role;
grant execute on function public.can_access_member_workout(uuid)
  to authenticated, service_role;
grant execute on function public.is_admin()
  to authenticated, service_role;
grant execute on function public.owns_gym(uuid)
  to authenticated, service_role;
grant execute on function public.owns_trainer(uuid)
  to authenticated, service_role;

revoke execute on function public.fn_daily_close()
  from public, anon, authenticated;
revoke execute on function public.fn_recompute_rankings()
  from public, anon, authenticated;
revoke execute on function public.fn_sla_scan()
  from public, anon, authenticated;
revoke execute on function public.grant_admin(uuid, text)
  from public, anon, authenticated;
revoke execute on function public.tg_feedback_due()
  from public, anon, authenticated;
revoke execute on function public.tg_ledger_on_payment()
  from public, anon, authenticated;
revoke execute on function public.tg_ledger_on_refund()
  from public, anon, authenticated;
revoke execute on function public.tg_ledger_on_settlement()
  from public, anon, authenticated;
revoke execute on function public.tg_market_counter()
  from public, anon, authenticated;
revoke execute on function public.tg_review_agg()
  from public, anon, authenticated;
revoke execute on function public.tg_routine_limit()
  from public, anon, authenticated;
revoke execute on function public.tg_scan_post()
  from public, anon, authenticated;
revoke execute on function public.tg_scan_routine()
  from public, anon, authenticated;
revoke execute on function public.tg_settlement_on_payment()
  from public, anon, authenticated;

grant execute on function public.fn_daily_close() to service_role;
grant execute on function public.fn_recompute_rankings() to service_role;
grant execute on function public.fn_sla_scan() to service_role;
grant execute on function public.grant_admin(uuid, text) to service_role;
grant execute on function public.tg_feedback_due() to service_role;
grant execute on function public.tg_ledger_on_payment() to service_role;
grant execute on function public.tg_ledger_on_refund() to service_role;
grant execute on function public.tg_ledger_on_settlement() to service_role;
grant execute on function public.tg_market_counter() to service_role;
grant execute on function public.tg_review_agg() to service_role;
grant execute on function public.tg_routine_limit() to service_role;
grant execute on function public.tg_scan_post() to service_role;
grant execute on function public.tg_scan_routine() to service_role;
grant execute on function public.tg_settlement_on_payment() to service_role;
