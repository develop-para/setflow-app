-- Cover relationship foreign keys used by schedule and workout projections.
-- These are safe on existing installations and remove advisor findings.

create index if not exists coaching_schedules_member_user_id_idx
  on public.coaching_schedules (member_user_id);

create index if not exists coaching_schedules_trainer_id_idx
  on public.coaching_schedules (trainer_id);

create index if not exists workout_exercises_base_exercise_id_idx
  on public.workout_exercises (base_exercise_id)
  where base_exercise_id is not null;
