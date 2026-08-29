-- Cover the gym foreign key and speed up offline consultation matching by gym.
create index member_workout_locations_gym_user_idx
  on public.member_workout_locations (gym_id, user_id);
