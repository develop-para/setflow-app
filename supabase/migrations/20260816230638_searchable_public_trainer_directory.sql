-- Server-owned public trainer search for the consultation flow. The RPC keeps
-- private/pending trainer rows out even when the caller is a trainer owner,
-- center owner, or admin whose ordinary directory RLS permits broader reads.

begin;

create extension if not exists pg_trgm with schema extensions;

create index if not exists trainers_public_directory_page_idx
  on public.trainers (rating_avg desc, id asc)
  where status = 'approved' and is_public;

create index if not exists trainers_public_name_prefix_idx
  on public.trainers (lower(display_name) text_pattern_ops)
  where status = 'approved' and is_public;

create index if not exists trainers_public_search_trgm_idx
  on public.trainers using gin (
    (
      coalesce(display_name, '') || ' ' ||
      coalesce(center_name, '') || ' ' ||
      coalesce(keyword, '')
    ) extensions.gin_trgm_ops
  )
  where status = 'approved' and is_public;

create or replace function public.search_public_trainers(
  search_query text default null,
  cursor_rank integer default null,
  cursor_rating numeric default null,
  cursor_id uuid default null,
  page_size integer default 20
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
  match_rank integer
)
language plpgsql
stable
security invoker
set search_path = ''
as $function$
declare
  v_query text := regexp_replace(
    btrim(coalesce(search_query, '')),
    '[[:space:]]+',
    ' ',
    'g'
  );
  v_literal text;
  v_contains_pattern text;
  v_prefix_pattern text;
begin
  if (select auth.uid()) is null then
    raise exception using
      errcode = '42501',
      message = 'Authentication is required.';
  end if;

  if char_length(v_query) > 50 or v_query ~ '[[:cntrl:]]' then
    raise exception using
      errcode = '22023',
      message = 'Search query must be at most 50 characters.';
  end if;

  if page_size is null or page_size < 1 or page_size > 30 then
    raise exception using
      errcode = '22023',
      message = 'Page size must be between 1 and 30.';
  end if;

  if num_nonnulls(cursor_rank, cursor_rating, cursor_id) not in (0, 3) then
    raise exception using
      errcode = '22023',
      message = 'Search cursor is incomplete.';
  end if;

  if cursor_rank is not null and (
    cursor_rank not between 0 and 2
    or cursor_rating < 0
    or cursor_rating::text = 'NaN'
  ) then
    raise exception using
      errcode = '22023',
      message = 'Search cursor is invalid.';
  end if;

  -- Treat %, _, and backslash as ordinary search text rather than allowing a
  -- client to alter the ILIKE pattern.
  v_literal := replace(v_query, chr(92), chr(92) || chr(92));
  v_literal := replace(v_literal, '%', chr(92) || '%');
  v_literal := replace(v_literal, '_', chr(92) || '_');
  v_contains_pattern := '%' || v_literal || '%';
  v_prefix_pattern := v_literal || '%';

  return query
  with eligible as (
    select
      trainer.id as trainer_id,
      trainer.display_name as trainer_display_name,
      trainer.keyword as trainer_keyword,
      trainer.intro as trainer_intro,
      trainer.profile_image_url as trainer_profile_image_url,
      trainer.career_years as trainer_career_years,
      trainer.center_name as trainer_center_name,
      trainer.rating_avg as trainer_rating_avg,
      trainer.post_count as trainer_post_count,
      trainer.coaching_total as trainer_coaching_total,
      trainer.verified_badge as trainer_verified_badge,
      case
        when v_query = '' then 0
        when lower(trainer.display_name) = lower(v_query) then 0
        when lower(trainer.display_name)
          like lower(v_prefix_pattern) escape '\' then 1
        else 2
      end as trainer_match_rank
    from public.trainers as trainer
    where trainer.status = 'approved'
      and trainer.is_public
      and (
        v_query = ''
        or (
          coalesce(trainer.display_name, '') || ' ' ||
          coalesce(trainer.center_name, '') || ' ' ||
          coalesce(trainer.keyword, '')
        ) ilike v_contains_pattern escape '\'
      )
  )
  select
    eligible.trainer_id,
    eligible.trainer_display_name,
    eligible.trainer_keyword,
    eligible.trainer_intro,
    eligible.trainer_profile_image_url,
    eligible.trainer_career_years,
    eligible.trainer_center_name,
    eligible.trainer_rating_avg,
    eligible.trainer_post_count,
    eligible.trainer_coaching_total,
    eligible.trainer_verified_badge,
    eligible.trainer_match_rank
  from eligible
  where cursor_rank is null
    or eligible.trainer_match_rank > cursor_rank
    or (
      eligible.trainer_match_rank = cursor_rank
      and eligible.trainer_rating_avg < cursor_rating
    )
    or (
      eligible.trainer_match_rank = cursor_rank
      and eligible.trainer_rating_avg = cursor_rating
      and eligible.trainer_id > cursor_id
    )
  order by
    eligible.trainer_match_rank asc,
    eligible.trainer_rating_avg desc,
    eligible.trainer_id asc
  limit (page_size + 1);
end;
$function$;

comment on function public.search_public_trainers(
  text,
  integer,
  numeric,
  uuid,
  integer
) is
  'Authenticated, public-approved trainer directory search with bounded keyset pagination.';

revoke all on function public.search_public_trainers(
  text,
  integer,
  numeric,
  uuid,
  integer
) from public, anon, authenticated;

grant execute on function public.search_public_trainers(
  text,
  integer,
  numeric,
  uuid,
  integer
) to authenticated, service_role;

commit;
