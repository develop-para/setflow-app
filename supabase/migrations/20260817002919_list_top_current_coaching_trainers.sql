-- Authenticated consultation discovery ranked by actual, currently active
-- coaching relationships. The private helper is deliberately read-only and
-- exposes only the same public-approved trainer projection as the directory.

begin;

create index if not exists coachings_active_trainer_dates_idx
  on public.coachings (trainer_id, start_date, end_date)
  where status = 'active';

create index if not exists consultations_user_created_id_idx
  on public.consultations (user_id, created_at desc, id desc);

create or replace function private.list_top_current_coaching_trainers(
  result_limit integer default 3
)
returns table (
  id uuid,
  display_name text,
  keyword text,
  intro text,
  profile_image_url text,
  career_years integer,
  center_name text,
  rating_avg numeric,
  post_count integer,
  coaching_total integer,
  verified_badge boolean,
  active_coaching_count bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_today date := (now() at time zone 'Asia/Seoul')::date;
begin
  if (select auth.uid()) is null then
    raise exception using
      errcode = '42501',
      message = 'Authentication is required.';
  end if;

  if result_limit is null or result_limit < 1 or result_limit > 3 then
    raise exception using
      errcode = '22023',
      message = 'Result limit must be between 1 and 3.';
  end if;

  return query
  with current_coaching_counts as (
    select
      coaching.trainer_id,
      count(*) as active_count
    from public.coachings as coaching
    where coaching.status = 'active'
      and (
        coaching.start_date is null
        or coaching.start_date <= v_today
      )
      and (
        coaching.end_date is null
        or coaching.end_date >= v_today
      )
    group by coaching.trainer_id
  )
  select
    trainer.id,
    trainer.display_name,
    trainer.keyword,
    trainer.intro,
    trainer.profile_image_url,
    trainer.career_years,
    trainer.center_name,
    trainer.rating_avg,
    trainer.post_count,
    trainer.coaching_total,
    trainer.verified_badge,
    coalesce(coaching_count.active_count, 0)::bigint
      as active_coaching_count
  from public.trainers as trainer
  left join current_coaching_counts as coaching_count
    on coaching_count.trainer_id = trainer.id
  where trainer.status = 'approved'
    and trainer.is_public
  order by
    coalesce(coaching_count.active_count, 0) desc,
    coalesce(trainer.rating_avg, 0) desc,
    trainer.id asc
  limit result_limit;
end;
$function$;

comment on function private.list_top_current_coaching_trainers(integer) is
  'Authenticated helper returning up to three public-approved trainers ranked by current active coaching count.';

revoke all on function private.list_top_current_coaching_trainers(integer)
  from public, anon, authenticated;
grant execute on function private.list_top_current_coaching_trainers(integer)
  to authenticated, service_role;

create or replace function public.list_top_current_coaching_trainers(
  result_limit integer default 3
)
returns table (
  id uuid,
  display_name text,
  keyword text,
  intro text,
  profile_image_url text,
  career_years integer,
  center_name text,
  rating_avg numeric,
  post_count integer,
  coaching_total integer,
  verified_badge boolean,
  active_coaching_count bigint
)
language sql
stable
security invoker
set search_path = ''
as $function$
  select *
  from private.list_top_current_coaching_trainers(result_limit);
$function$;

comment on function public.list_top_current_coaching_trainers(integer) is
  'Authenticated TOP coaching trainer directory endpoint with a minimal public profile projection.';

revoke all on function public.list_top_current_coaching_trainers(integer)
  from public, anon, authenticated;
grant execute on function public.list_top_current_coaching_trainers(integer)
  to authenticated, service_role;

commit;
