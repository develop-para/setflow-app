begin;

-- Public catalog reads must not execute helper functions that are intentionally
-- unavailable to the anon role.
drop policy if exists rd_market on public.market_routines;
drop policy if exists read_published_market_routines on public.market_routines;
drop policy if exists read_all_market_routines_as_admin on public.market_routines;
create policy read_published_market_routines
  on public.market_routines for select to anon, authenticated
  using (status = 'published');
create policy read_all_market_routines_as_admin
  on public.market_routines for select to authenticated
  using ((select public.is_admin()));

drop policy if exists rd_cr on public.coaching_routines;
drop policy if exists wr_cr on public.coaching_routines;
drop policy if exists read_approved_coaching_routines on public.coaching_routines;
drop policy if exists read_owned_coaching_routines on public.coaching_routines;
drop policy if exists create_owned_coaching_routines on public.coaching_routines;
drop policy if exists update_owned_coaching_routines on public.coaching_routines;
drop policy if exists delete_owned_coaching_routines on public.coaching_routines;

create policy read_approved_coaching_routines
  on public.coaching_routines for select to anon, authenticated
  using (status = 'approved');
create policy read_owned_coaching_routines
  on public.coaching_routines for select to authenticated
  using (public.owns_trainer(trainer_id) or (select public.is_admin()));
create policy create_owned_coaching_routines
  on public.coaching_routines for insert to authenticated
  with check (public.owns_trainer(trainer_id) or (select public.is_admin()));
create policy update_owned_coaching_routines
  on public.coaching_routines for update to authenticated
  using (public.owns_trainer(trainer_id) or (select public.is_admin()))
  with check (public.owns_trainer(trainer_id) or (select public.is_admin()));
create policy delete_owned_coaching_routines
  on public.coaching_routines for delete to authenticated
  using (public.owns_trainer(trainer_id) or (select public.is_admin()));

drop policy if exists rd_cr_ex on public.coaching_routine_exercises;
drop policy if exists wr_cr_ex on public.coaching_routine_exercises;
drop policy if exists read_approved_coaching_exercises on public.coaching_routine_exercises;
drop policy if exists read_owned_coaching_exercises on public.coaching_routine_exercises;
drop policy if exists create_owned_coaching_exercises on public.coaching_routine_exercises;
drop policy if exists update_owned_coaching_exercises on public.coaching_routine_exercises;
drop policy if exists delete_owned_coaching_exercises on public.coaching_routine_exercises;

create policy read_approved_coaching_exercises
  on public.coaching_routine_exercises for select to anon, authenticated
  using (
    exists (
      select 1 from public.coaching_routines routine
      where routine.id = coaching_routine_exercises.routine_id
        and routine.status = 'approved'
    )
  );
create policy read_owned_coaching_exercises
  on public.coaching_routine_exercises for select to authenticated
  using (
    exists (
      select 1 from public.coaching_routines routine
      where routine.id = coaching_routine_exercises.routine_id
        and (
          public.owns_trainer(routine.trainer_id)
          or (select public.is_admin())
        )
    )
  );
create policy create_owned_coaching_exercises
  on public.coaching_routine_exercises for insert to authenticated
  with check (
    exists (
      select 1 from public.coaching_routines routine
      where routine.id = coaching_routine_exercises.routine_id
        and (
          public.owns_trainer(routine.trainer_id)
          or (select public.is_admin())
        )
    )
  );
create policy update_owned_coaching_exercises
  on public.coaching_routine_exercises for update to authenticated
  using (
    exists (
      select 1 from public.coaching_routines routine
      where routine.id = coaching_routine_exercises.routine_id
        and (
          public.owns_trainer(routine.trainer_id)
          or (select public.is_admin())
        )
    )
  )
  with check (
    exists (
      select 1 from public.coaching_routines routine
      where routine.id = coaching_routine_exercises.routine_id
        and (
          public.owns_trainer(routine.trainer_id)
          or (select public.is_admin())
        )
    )
  );
create policy delete_owned_coaching_exercises
  on public.coaching_routine_exercises for delete to authenticated
  using (
    exists (
      select 1 from public.coaching_routines routine
      where routine.id = coaching_routine_exercises.routine_id
        and (
          public.owns_trainer(routine.trainer_id)
          or (select public.is_admin())
        )
    )
  );

drop policy if exists rd_cr_sets on public.coaching_routine_sets;
drop policy if exists wr_cr_sets on public.coaching_routine_sets;
drop policy if exists read_approved_coaching_sets on public.coaching_routine_sets;
drop policy if exists manage_owned_coaching_sets on public.coaching_routine_sets;
drop policy if exists create_owned_coaching_sets on public.coaching_routine_sets;
drop policy if exists update_owned_coaching_sets on public.coaching_routine_sets;
drop policy if exists delete_owned_coaching_sets on public.coaching_routine_sets;

create policy read_approved_coaching_sets
  on public.coaching_routine_sets for select to anon, authenticated
  using (
    exists (
      select 1
      from public.coaching_routine_exercises exercise
      join public.coaching_routines routine on routine.id = exercise.routine_id
      where exercise.id = coaching_routine_sets.routine_exercise_id
        and routine.status = 'approved'
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
        and (
          public.owns_trainer(routine.trainer_id)
          or (select public.is_admin())
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
        and (
          public.owns_trainer(routine.trainer_id)
          or (select public.is_admin())
        )
    )
  )
  with check (
    exists (
      select 1
      from public.coaching_routine_exercises exercise
      join public.coaching_routines routine on routine.id = exercise.routine_id
      where exercise.id = coaching_routine_sets.routine_exercise_id
        and (
          public.owns_trainer(routine.trainer_id)
          or (select public.is_admin())
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
        and (
          public.owns_trainer(routine.trainer_id)
          or (select public.is_admin())
        )
    )
  );

revoke all on table public.coaching_routines from anon, authenticated;
revoke all on table public.coaching_routine_exercises from anon, authenticated;
revoke all on table public.coaching_routine_sets from anon, authenticated;
grant select on table public.coaching_routines to anon, authenticated;
grant select on table public.coaching_routine_exercises to anon, authenticated;
grant select on table public.coaching_routine_sets to anon, authenticated;
grant insert, update, delete on table public.coaching_routines to authenticated;
grant insert, update, delete on table public.coaching_routine_exercises to authenticated;
grant insert, update, delete on table public.coaching_routine_sets to authenticated;

commit;
