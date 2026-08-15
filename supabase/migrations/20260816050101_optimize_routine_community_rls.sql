begin;

-- One SELECT policy per role avoids evaluating two permissive policies for
-- every row while retaining public approved content and owner/admin access.
drop policy if exists read_published_market_routines on public.market_routines;
drop policy if exists read_all_market_routines_as_admin on public.market_routines;
create policy read_published_market_routines_anon
  on public.market_routines for select to anon
  using (status = 'published');
create policy read_market_routines_authenticated
  on public.market_routines for select to authenticated
  using (status = 'published' or (select public.is_admin()));

drop policy if exists read_approved_coaching_routines on public.coaching_routines;
drop policy if exists read_owned_coaching_routines on public.coaching_routines;
create policy read_approved_coaching_routines_anon
  on public.coaching_routines for select to anon
  using (status = 'approved');
create policy read_coaching_routines_authenticated
  on public.coaching_routines for select to authenticated
  using (
    status = 'approved'
    or public.owns_trainer(trainer_id)
    or (select public.is_admin())
  );

drop policy if exists read_approved_coaching_exercises on public.coaching_routine_exercises;
drop policy if exists read_owned_coaching_exercises on public.coaching_routine_exercises;
create policy read_approved_coaching_exercises_anon
  on public.coaching_routine_exercises for select to anon
  using (
    exists (
      select 1 from public.coaching_routines routine
      where routine.id = coaching_routine_exercises.routine_id
        and routine.status = 'approved'
    )
  );
create policy read_coaching_exercises_authenticated
  on public.coaching_routine_exercises for select to authenticated
  using (
    exists (
      select 1 from public.coaching_routines routine
      where routine.id = coaching_routine_exercises.routine_id
        and (
          routine.status = 'approved'
          or public.owns_trainer(routine.trainer_id)
          or (select public.is_admin())
        )
    )
  );

drop policy if exists read_approved_coaching_sets on public.coaching_routine_sets;
create policy read_approved_coaching_sets_anon
  on public.coaching_routine_sets for select to anon
  using (
    exists (
      select 1
      from public.coaching_routine_exercises exercise
      join public.coaching_routines routine on routine.id = exercise.routine_id
      where exercise.id = coaching_routine_sets.routine_exercise_id
        and routine.status = 'approved'
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
          routine.status = 'approved'
          or public.owns_trainer(routine.trainer_id)
          or (select public.is_admin())
        )
    )
  );

-- Cache auth.uid once per statement in community write policies.
drop policy if exists wr_comments on public.comments;
drop policy if exists del_comments on public.comments;
drop policy if exists create_own_comments on public.comments;
drop policy if exists delete_own_comments on public.comments;
create policy create_own_comments
  on public.comments for insert to authenticated
  with check (user_id = (select auth.uid()));
create policy delete_own_comments
  on public.comments for delete to authenticated
  using (
    user_id = (select auth.uid())
    or (select public.is_admin())
  );

-- Cover foreign keys used by catalog, feed, and subscription joins.
create index if not exists coaching_routine_exercises_base_exercise_idx
  on public.coaching_routine_exercises (base_exercise_id)
  where base_exercise_id is not null;
create index if not exists coaching_routine_sets_exercise_idx
  on public.coaching_routine_sets (routine_exercise_id);
create index if not exists comments_user_idx
  on public.comments (user_id)
  where user_id is not null;
create index if not exists market_routines_trainer_idx
  on public.market_routines (trainer_id)
  where trainer_id is not null;
create index if not exists market_routines_coaching_idx
  on public.market_routines (coaching_routine_id)
  where coaching_routine_id is not null;
create index if not exists subscriptions_plan_idx
  on public.subscriptions (plan_id)
  where plan_id is not null;

commit;
