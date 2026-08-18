-- Complete the typed coaching calendar model after the relationship/RLS
-- migration. Members and gym owners remain read-only; the owning trainer is
-- the only authenticated role allowed to mutate a schedule.

alter table public.coaching_schedules
  add column if not exists completed_at timestamptz;

update public.coaching_schedules
set title = coalesce(nullif(btrim(title), ''), '코칭 일정'),
    date = coalesce(date, current_date),
    start_time = coalesce(start_time, time '09:00'),
    end_time = coalesce(end_time, start_time + interval '1 hour', time '10:00')
where title is null
   or btrim(title) = ''
   or date is null
   or start_time is null
   or end_time is null;

alter table public.coaching_schedules
  alter column title set not null,
  alter column date set not null,
  alter column start_time set not null,
  alter column end_time set not null;

alter table public.coaching_schedules
  drop constraint if exists coaching_schedules_title_check;

alter table public.coaching_schedules
  add constraint coaching_schedules_title_check
  check (char_length(btrim(title)) between 1 and 120);

alter table public.coaching_schedules
  drop constraint if exists coaching_schedules_time_order_check;

alter table public.coaching_schedules
  add constraint coaching_schedules_time_order_check
  check (start_time < end_time);

create index if not exists coaching_schedules_trainer_date_idx
  on public.coaching_schedules (trainer_id, date, start_time);

create index if not exists coaching_schedules_member_date_idx
  on public.coaching_schedules (member_user_id, date, start_time)
  where member_user_id is not null;

comment on column public.coaching_schedules.completed_at is
  'Set by the owning trainer when the coaching schedule is completed.';
