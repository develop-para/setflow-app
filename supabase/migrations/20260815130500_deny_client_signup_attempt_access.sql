-- Keep a visible deny policy as defense in depth. Table privileges are also
-- revoked, and service_role bypasses RLS for the Edge Function RPC.

drop policy if exists "auth_signup_attempts_deny_clients"
  on public.auth_signup_attempts;
create policy "auth_signup_attempts_deny_clients"
  on public.auth_signup_attempts
  as restrictive
  for all
  to anon, authenticated
  using (false)
  with check (false);
