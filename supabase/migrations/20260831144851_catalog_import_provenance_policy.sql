-- The provenance ledger is never client-readable. A service-role policy makes
-- that intent explicit to the database advisor while grants still enforce the
-- same boundary for PostgREST callers.
drop policy if exists exercise_catalog_imports_service_only
  on public.exercise_catalog_imports;
create policy exercise_catalog_imports_service_only
  on public.exercise_catalog_imports
  for all
  to service_role
  using (true)
  with check (true);
