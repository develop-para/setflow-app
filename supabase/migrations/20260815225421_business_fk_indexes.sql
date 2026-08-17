-- Cover the remaining business foreign keys reported by the Supabase
-- performance advisor. This migration contains no data or policy changes.
begin;

create index if not exists consultation_messages_sender_id_idx
  on public.consultation_messages (sender_id);
create index if not exists consultations_routine_id_idx
  on public.consultations (routine_id);
create index if not exists gym_applications_reviewer_id_idx
  on public.gym_applications (reviewer_id);
create index if not exists gym_documents_gym_id_idx
  on public.gym_documents (gym_id);
create index if not exists gym_subscriptions_plan_id_idx
  on public.gym_subscriptions (plan_id);
create index if not exists gym_trainers_trainer_user_id_idx
  on public.gym_trainers (trainer_user_id);
create index if not exists trainer_applications_reviewer_id_idx
  on public.trainer_applications (reviewer_id);
create index if not exists trainer_applications_trainer_id_idx
  on public.trainer_applications (trainer_id);
create index if not exists trainer_badges_trainer_id_idx
  on public.trainer_badges (trainer_id);
create index if not exists trainer_documents_trainer_id_idx
  on public.trainer_documents (trainer_id);
create index if not exists trainer_experiences_trainer_id_idx
  on public.trainer_experiences (trainer_id);
create index if not exists trainers_commission_tier_id_idx
  on public.trainers (commission_tier_id);

commit;
