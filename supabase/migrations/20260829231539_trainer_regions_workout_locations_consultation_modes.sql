-- Location-aware trainer consultation and member workout-place preferences.
-- Regions are deliberately province-level stable codes. Districts can be
-- added to the catalog later without changing any user-owned foreign keys.

begin;

create table public.service_regions (
  code text primary key,
  name text not null unique,
  sort_order smallint not null unique,
  active boolean not null default true,
  constraint service_regions_code_check check (code ~ '^[0-9]{2}$'),
  constraint service_regions_name_check check (
    char_length(btrim(name)) between 2 and 40
  )
);

insert into public.service_regions (code, name, sort_order) values
  ('11', '서울특별시', 1),
  ('26', '부산광역시', 2),
  ('27', '대구광역시', 3),
  ('28', '인천광역시', 4),
  ('29', '광주광역시', 5),
  ('30', '대전광역시', 6),
  ('31', '울산광역시', 7),
  ('36', '세종특별자치시', 8),
  ('41', '경기도', 9),
  ('43', '충청북도', 10),
  ('44', '충청남도', 11),
  ('46', '전라남도', 12),
  ('47', '경상북도', 13),
  ('48', '경상남도', 14),
  ('50', '제주특별자치도', 15),
  ('51', '강원특별자치도', 16),
  ('52', '전북특별자치도', 17)
on conflict (code) do update
set name = excluded.name,
    sort_order = excluded.sort_order,
    active = true;

alter table public.trainers
  add column if not exists accepts_online_consultation boolean not null default true,
  add column if not exists accepts_offline_consultation boolean not null default false;

create table public.trainer_service_areas (
  id uuid primary key default gen_random_uuid(),
  trainer_id uuid not null references public.trainers(id) on delete cascade,
  region_code text not null references public.service_regions(code),
  is_primary boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (trainer_id, region_code)
);

create unique index trainer_service_areas_one_primary_idx
  on public.trainer_service_areas (trainer_id)
  where is_primary;
create index trainer_service_areas_region_trainer_idx
  on public.trainer_service_areas (region_code, trainer_id);

create table public.member_workout_locations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  gym_id uuid not null references public.gyms(id) on delete cascade,
  is_active boolean not null default false,
  last_selected_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, gym_id)
);

create unique index member_workout_locations_one_active_idx
  on public.member_workout_locations (user_id)
  where is_active;
create index member_workout_locations_user_recent_idx
  on public.member_workout_locations (
    user_id,
    is_active desc,
    last_selected_at desc nulls last,
    created_at desc
  );

alter table public.consultations
  add column if not exists consultation_mode text not null default 'online',
  add column if not exists matching_source text not null default 'direct',
  add column if not exists requested_region_code text
    references public.service_regions(code);

do $constraints$
begin
  if not exists (
    select 1 from pg_catalog.pg_constraint
    where conrelid = 'public.consultations'::regclass
      and conname = 'consultations_mode_check'
  ) then
    alter table public.consultations
      add constraint consultations_mode_check
      check (consultation_mode in ('online', 'offline'));
  end if;

  if not exists (
    select 1 from pg_catalog.pg_constraint
    where conrelid = 'public.consultations'::regclass
      and conname = 'consultations_matching_source_check'
  ) then
    alter table public.consultations
      add constraint consultations_matching_source_check
      check (matching_source in ('direct', 'region', 'gym'));
  end if;

  if not exists (
    select 1 from pg_catalog.pg_constraint
    where conrelid = 'public.consultations'::regclass
      and conname = 'consultations_location_request_check'
  ) then
    alter table public.consultations
      add constraint consultations_location_request_check
      check (
        (consultation_mode = 'online'
          and matching_source = 'direct'
          and requested_region_code is null)
        or
        (consultation_mode = 'offline'
          and matching_source = 'region'
          and requested_region_code is not null
          and gym_id is null)
        or
        (consultation_mode = 'offline'
          and matching_source = 'gym'
          and requested_region_code is null
          and gym_id is not null)
      );
  end if;
end
$constraints$;

create index consultations_mode_region_status_idx
  on public.consultations (
    consultation_mode,
    requested_region_code,
    status,
    created_at desc
  );

alter table public.service_regions enable row level security;
alter table public.trainer_service_areas enable row level security;
alter table public.member_workout_locations enable row level security;

revoke all on table public.service_regions
  from public, anon, authenticated;
revoke all on table public.trainer_service_areas
  from public, anon, authenticated;
revoke all on table public.member_workout_locations
  from public, anon, authenticated;

grant select on table public.service_regions to anon, authenticated, service_role;
grant select on table public.trainer_service_areas
  to anon, authenticated, service_role;
grant select on table public.member_workout_locations
  to authenticated, service_role;

grant select (
  accepts_online_consultation,
  accepts_offline_consultation
) on public.trainers to anon, authenticated;
grant select (
  consultation_mode,
  matching_source,
  requested_region_code
) on public.consultations to authenticated;

create policy service_regions_public_read
on public.service_regions
for select
to anon, authenticated
using (active);

create policy trainer_service_areas_public_read
on public.trainer_service_areas
for select
to anon
using (
  exists (
    select 1
    from public.trainers trainer
    where trainer.id = trainer_service_areas.trainer_id
      and trainer.status = 'approved'
      and trainer.is_public
  )
);

create policy trainer_service_areas_authenticated_read
on public.trainer_service_areas
for select
to authenticated
using (
  exists (
    select 1
    from public.trainers trainer
    where trainer.id = trainer_service_areas.trainer_id
      and (
        (trainer.status = 'approved' and trainer.is_public)
        or trainer.user_id = (select auth.uid())
        or (select public.is_admin())
      )
  )
);

create policy member_workout_locations_owner_read
on public.member_workout_locations
for select
to authenticated
using ((select auth.uid()) = user_id);

create or replace function private.update_my_trainer_consultation_settings(
  p_accepts_online boolean,
  p_accepts_offline boolean,
  p_region_codes text[]
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := auth.uid();
  v_trainer_id uuid;
  v_region_codes text[];
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;
  if not coalesce(p_accepts_online, false)
     and not coalesce(p_accepts_offline, false) then
    raise exception using errcode = '22023', message = 'At least one consultation mode is required';
  end if;

  select array_agg(region_code order by first_position)
    into v_region_codes
  from (
    select region_code, min(position) as first_position
    from unnest(coalesce(p_region_codes, array[]::text[]))
      with ordinality as requested(region_code, position)
    where region_code is not null
    group by region_code
  ) normalized;

  if coalesce(cardinality(v_region_codes), 0) > 5 then
    raise exception using errcode = '22023', message = 'At most five service regions are allowed';
  end if;
  if coalesce(p_accepts_offline, false)
     and coalesce(cardinality(v_region_codes), 0) = 0 then
    raise exception using errcode = '22023', message = 'Offline consultation requires a service region';
  end if;
  if exists (
    select 1
    from unnest(coalesce(v_region_codes, array[]::text[])) requested(code)
    left join public.service_regions region
      on region.code = requested.code and region.active
    where region.code is null
  ) then
    raise exception using errcode = '22023', message = 'A service region is invalid';
  end if;

  select trainer.id into v_trainer_id
  from public.trainers trainer
  where trainer.user_id = v_user_id
    and trainer.status = 'approved'
  for update;
  if v_trainer_id is null then
    raise exception using errcode = '42501', message = 'An approved trainer profile is required';
  end if;

  update public.trainers
  set accepts_online_consultation = coalesce(p_accepts_online, false),
      accepts_offline_consultation = coalesce(p_accepts_offline, false),
      updated_at = now()
  where id = v_trainer_id;

  delete from public.trainer_service_areas
  where trainer_id = v_trainer_id;

  insert into public.trainer_service_areas (
    trainer_id,
    region_code,
    is_primary
  )
  select
    v_trainer_id,
    requested.region_code,
    requested.position = 1
  from unnest(coalesce(v_region_codes, array[]::text[]))
    with ordinality as requested(region_code, position);

  return jsonb_build_object(
    'trainer_id', v_trainer_id,
    'accepts_online', coalesce(p_accepts_online, false),
    'accepts_offline', coalesce(p_accepts_offline, false),
    'region_codes', coalesce(to_jsonb(v_region_codes), '[]'::jsonb)
  );
end
$function$;

create or replace function public.update_my_trainer_consultation_settings(
  accepts_online boolean,
  accepts_offline boolean,
  region_codes text[]
)
returns jsonb
language sql
set search_path = ''
as $function$
  select private.update_my_trainer_consultation_settings($1, $2, $3);
$function$;

create or replace function private.set_my_workout_location(
  p_gym_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := auth.uid();
  v_location_id uuid;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;
  if not exists (
    select 1 from public.gyms gym
    where gym.id = p_gym_id and gym.status = 'verified'
  ) then
    raise exception using errcode = '22023', message = 'A verified gym is required';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('workout_location:' || v_user_id::text, 0)
  );

  update public.member_workout_locations
  set is_active = false,
      updated_at = now()
  where user_id = v_user_id and is_active;

  insert into public.member_workout_locations (
    user_id,
    gym_id,
    is_active,
    last_selected_at
  ) values (
    v_user_id,
    p_gym_id,
    true,
    now()
  )
  on conflict (user_id, gym_id) do update
  set is_active = true,
      last_selected_at = excluded.last_selected_at,
      updated_at = now()
  returning id into v_location_id;

  return v_location_id;
end
$function$;

create or replace function public.set_my_workout_location(gym_id uuid)
returns uuid
language sql
set search_path = ''
as $function$
  select private.set_my_workout_location($1);
$function$;

create or replace function private.select_my_workout_location(
  p_location_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := auth.uid();
  v_gym_id uuid;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;
  select location.gym_id into v_gym_id
  from public.member_workout_locations location
  where location.id = p_location_id and location.user_id = v_user_id;
  if v_gym_id is null then
    raise exception using errcode = '42501', message = 'Workout location not found';
  end if;
  perform private.set_my_workout_location(v_gym_id);
  return p_location_id;
end
$function$;

create or replace function public.select_my_workout_location(location_id uuid)
returns uuid
language sql
set search_path = ''
as $function$
  select private.select_my_workout_location($1);
$function$;

create or replace function private.remove_my_workout_location(
  p_location_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := auth.uid();
  v_was_active boolean;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('workout_location:' || v_user_id::text, 0)
  );
  delete from public.member_workout_locations location
  where location.id = p_location_id and location.user_id = v_user_id
  returning location.is_active into v_was_active;
  if not found then
    raise exception using errcode = '42501', message = 'Workout location not found';
  end if;
  if v_was_active then
    update public.member_workout_locations
    set is_active = true,
        last_selected_at = now(),
        updated_at = now()
    where id = (
      select location.id
      from public.member_workout_locations location
      where location.user_id = v_user_id
      order by location.last_selected_at desc nulls last,
        location.created_at desc,
        location.id
      limit 1
    );
  end if;
end
$function$;

create or replace function public.remove_my_workout_location(location_id uuid)
returns void
language sql
set search_path = ''
as $function$
  select private.remove_my_workout_location($1);
$function$;

create or replace function private.create_location_aware_consultation(
  p_request_id uuid,
  p_consultation_mode text,
  p_trainer_id uuid,
  p_gym_id uuid,
  p_region_code text,
  p_routine_id uuid,
  p_specialty text,
  p_goal text,
  p_level text,
  p_question text,
  p_recommendation_profile jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := auth.uid();
  v_mode text := lower(btrim(coalesce(p_consultation_mode, '')));
  v_region_code text := nullif(btrim(p_region_code), '');
  v_specialty text := nullif(btrim(p_specialty), '');
  v_goal text := nullif(btrim(p_goal), '');
  v_level text := nullif(btrim(p_level), '');
  v_question text := nullif(btrim(p_question), '');
  v_match_source text;
  v_resolved_trainer_id uuid;
  v_existing public.consultations%rowtype;
  v_existing_profile jsonb;
  v_consultation_id uuid;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;
  if p_request_id is null then
    raise exception using errcode = '22023', message = 'A request ID is required';
  end if;
  if v_mode not in ('online', 'offline') then
    raise exception using errcode = '22023', message = 'Consultation mode is invalid';
  end if;
  if v_question is null or char_length(v_question) > 5000
     or char_length(coalesce(v_specialty, '')) > 200
     or char_length(coalesce(v_goal, '')) > 200
     or char_length(coalesce(v_level, '')) > 100 then
    raise exception using errcode = '22023', message = 'Consultation text is invalid';
  end if;
  if p_recommendation_profile is not null
     and not coalesce(
       private.is_valid_recommendation_profile_snapshot(p_recommendation_profile),
       false
     ) then
    raise exception using errcode = '22023', message = 'Recommendation profile snapshot is invalid';
  end if;

  if v_mode = 'online' then
    if num_nonnulls(p_trainer_id, p_gym_id) <> 1 or v_region_code is not null then
      raise exception using errcode = '22023', message = 'Online consultation requires one trainer or gym';
    end if;
    v_match_source := 'direct';
  elsif p_gym_id is not null then
    if p_trainer_id is not null or v_region_code is not null then
      raise exception using errcode = '22023', message = 'Gym matching accepts only one gym';
    end if;
    v_match_source := 'gym';
  else
    if v_region_code is null then
      raise exception using errcode = '22023', message = 'Offline consultation requires a region or gym';
    end if;
    v_match_source := 'region';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'consultation_create:' || v_user_id::text || ':' || p_request_id::text,
      0
    )
  );

  select consultation.* into v_existing
  from public.consultations consultation
  where consultation.user_id = v_user_id
    and consultation.request_id = p_request_id
  for update;
  if found then
    select profile_share.profile_snapshot into v_existing_profile
    from public.consultation_recommendation_profile_shares profile_share
    where profile_share.consultation_id = v_existing.id;
    if v_existing.consultation_mode is distinct from v_mode
       or v_existing.matching_source is distinct from v_match_source
       or v_existing.gym_id is distinct from p_gym_id
       or v_existing.requested_region_code is distinct from v_region_code
       or (p_trainer_id is not null and v_existing.trainer_id is distinct from p_trainer_id)
       or v_existing.routine_id is distinct from p_routine_id
       or v_existing.specialty is distinct from v_specialty
       or v_existing.goal is distinct from v_goal
       or v_existing.level is distinct from v_level
       or v_existing.question is distinct from v_question
       or v_existing_profile is distinct from p_recommendation_profile then
      raise exception using errcode = '22023', message = 'A consultation request ID cannot be reused with different data';
    end if;
    return jsonb_build_object(
      'consultation_id', v_existing.id,
      'status', v_existing.status,
      'replayed', true
    );
  end if;

  if v_mode = 'online' then
    if p_trainer_id is not null then
      select trainer.id into v_resolved_trainer_id
      from public.trainers trainer
      where trainer.id = p_trainer_id
        and trainer.status = 'approved'
        and trainer.is_public
        and trainer.accepts_online_consultation;
      if v_resolved_trainer_id is null then
        raise exception using errcode = '22023', message = 'Trainer is not accepting online consultations';
      end if;
    elsif not exists (
      select 1 from public.gyms gym
      where gym.id = p_gym_id and gym.status = 'verified'
    ) then
      raise exception using errcode = '22023', message = 'A verified gym is required';
    end if;
  elsif v_match_source = 'gym' then
    if not exists (
      select 1
      from public.member_workout_locations location
      where location.user_id = v_user_id and location.gym_id = p_gym_id
    ) and not exists (
      select 1
      from public.members member
      where member.user_id = v_user_id
        and member.gym_id = p_gym_id
        and member.status = 'active'
    ) then
      raise exception using errcode = '42501', message = 'The gym is not one of your workout locations';
    end if;
    select trainer.id into v_resolved_trainer_id
    from public.gym_trainers gym_trainer
    join public.trainers trainer on trainer.id = gym_trainer.trainer_id
    where gym_trainer.gym_id = p_gym_id
      and gym_trainer.status = 'active'
      and trainer.status = 'approved'
      and trainer.accepts_offline_consultation
    order by (
      select count(*)
      from public.consultations active_consultation
      where active_consultation.assigned_trainer_id = trainer.id
        and active_consultation.status in ('pending', 'assigned')
    ), trainer.rating_avg desc, trainer.id
    limit 1;
    if v_resolved_trainer_id is null then
      raise exception using errcode = 'P0001', message = 'No offline trainer is available at this gym';
    end if;
  else
    if not exists (
      select 1 from public.service_regions region
      where region.code = v_region_code and region.active
    ) then
      raise exception using errcode = '22023', message = 'Region is invalid';
    end if;
    select trainer.id into v_resolved_trainer_id
    from public.trainers trainer
    join public.trainer_service_areas service_area
      on service_area.trainer_id = trainer.id
     and service_area.region_code = v_region_code
    where trainer.status = 'approved'
      and trainer.is_public
      and trainer.accepts_offline_consultation
      and (p_trainer_id is null or trainer.id = p_trainer_id)
    order by service_area.is_primary desc, (
      select count(*)
      from public.consultations active_consultation
      where active_consultation.assigned_trainer_id = trainer.id
        and active_consultation.status in ('pending', 'assigned')
    ), trainer.rating_avg desc, trainer.id
    limit 1;
    if v_resolved_trainer_id is null then
      raise exception using errcode = 'P0001', message = 'No offline trainer is available in this region';
    end if;
  end if;

  if p_routine_id is not null and not exists (
    select 1
    from public.coaching_routines routine
    where routine.id = p_routine_id
      and routine.status = 'approved'
      and (
        routine.trainer_id = v_resolved_trainer_id
        or (p_gym_id is not null and routine.gym_id = p_gym_id)
        or (routine.trainer_id is null and routine.gym_id is null)
      )
  ) then
    raise exception using errcode = '42501', message = 'The routine does not belong to the consultation target';
  end if;

  insert into public.consultations (
    request_id,
    user_id,
    trainer_id,
    gym_id,
    routine_id,
    specialty,
    goal,
    level,
    question,
    status,
    is_read,
    assigned_trainer_id,
    consultation_mode,
    matching_source,
    requested_region_code
  ) values (
    p_request_id,
    v_user_id,
    case when v_match_source = 'gym' then null else v_resolved_trainer_id end,
    p_gym_id,
    p_routine_id,
    v_specialty,
    v_goal,
    v_level,
    v_question,
    case when v_mode = 'offline' then 'assigned' else 'pending' end,
    false,
    case when v_mode = 'offline' then v_resolved_trainer_id else null end,
    v_mode,
    v_match_source,
    v_region_code
  ) returning id into v_consultation_id;

  if p_recommendation_profile is not null then
    insert into public.consultation_recommendation_profile_shares (
      consultation_id,
      user_id,
      schema_version,
      profile_snapshot,
      consented_at
    ) values (
      v_consultation_id,
      v_user_id,
      1,
      p_recommendation_profile,
      now()
    );
  end if;

  return jsonb_build_object(
    'consultation_id', v_consultation_id,
    'trainer_id', v_resolved_trainer_id,
    'status', case when v_mode = 'offline' then 'assigned' else 'pending' end,
    'replayed', false
  );
end
$function$;

create or replace function public.create_location_aware_consultation(
  request_id uuid,
  consultation_mode text,
  trainer_id uuid,
  gym_id uuid,
  region_code text,
  routine_id uuid,
  specialty text,
  goal text,
  level text,
  question text,
  recommendation_profile jsonb
)
returns jsonb
language sql
set search_path = ''
as $function$
  select private.create_location_aware_consultation(
    $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11
  );
$function$;

-- The consultation picker is an online-only directory. Trainers who pause
-- online intake remain visible elsewhere but must not appear as selectable
-- online targets.
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
    raise exception using errcode = '42501', message = 'Authentication is required.';
  end if;
  if char_length(v_query) > 50 or v_query ~ '[[:cntrl:]]' then
    raise exception using errcode = '22023', message = 'Search query must be at most 50 characters.';
  end if;
  if page_size is null or page_size < 1 or page_size > 30 then
    raise exception using errcode = '22023', message = 'Page size must be between 1 and 30.';
  end if;
  if num_nonnulls(cursor_rank, cursor_rating, cursor_id) not in (0, 3) then
    raise exception using errcode = '22023', message = 'Search cursor is incomplete.';
  end if;
  if cursor_rank is not null and (
    cursor_rank not between 0 and 2
    or cursor_rating < 0
    or cursor_rating::text = 'NaN'
  ) then
    raise exception using errcode = '22023', message = 'Search cursor is invalid.';
  end if;

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
      and trainer.accepts_online_consultation
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
  order by eligible.trainer_match_rank,
    eligible.trainer_rating_avg desc,
    eligible.trainer_id
  limit (page_size + 1);
end
$function$;

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
    raise exception using errcode = '42501', message = 'Authentication is required.';
  end if;
  if result_limit is null or result_limit < 1 or result_limit > 3 then
    raise exception using errcode = '22023', message = 'Result limit must be between 1 and 3.';
  end if;

  return query
  with current_coaching_counts as (
    select coaching.trainer_id, count(*) as active_count
    from public.coachings as coaching
    where coaching.status = 'active'
      and (coaching.start_date is null or coaching.start_date <= v_today)
      and (coaching.end_date is null or coaching.end_date >= v_today)
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
  from public.trainers as trainer
  left join current_coaching_counts as coaching_count
    on coaching_count.trainer_id = trainer.id
  where trainer.status = 'approved'
    and trainer.is_public
    and trainer.accepts_online_consultation
  order by coalesce(coaching_count.active_count, 0) desc,
    coalesce(trainer.rating_avg, 0) desc,
    trainer.id
  limit result_limit;
end
$function$;

-- Keep the trainer's owned profile aggregate as the single read used by the
-- repository. Public directory reads still expose only approved public rows.
create or replace function private.get_my_trainer_profile()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $function$
  select to_jsonb(trainer) || jsonb_build_object(
    'certifications',
    coalesce(
      (
        select jsonb_agg(to_jsonb(certification)
          order by certification.created_at desc, certification.id)
        from public.trainer_certifications certification
        where certification.trainer_id = trainer.id
      ),
      '[]'::jsonb
    ),
    'service_areas',
    coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'region_code', service_area.region_code,
            'region_name', region.name,
            'is_primary', service_area.is_primary
          ) order by service_area.is_primary desc, region.sort_order
        )
        from public.trainer_service_areas service_area
        join public.service_regions region
          on region.code = service_area.region_code
        where service_area.trainer_id = trainer.id
      ),
      '[]'::jsonb
    )
  )
  from public.trainers trainer
  where trainer.user_id = (select auth.uid())
  order by trainer.updated_at desc
  limit 1;
$function$;

revoke all on function private.update_my_trainer_consultation_settings(
  boolean, boolean, text[]
) from public, anon, authenticated;
grant execute on function private.update_my_trainer_consultation_settings(
  boolean, boolean, text[]
) to authenticated, service_role;
revoke all on function public.update_my_trainer_consultation_settings(
  boolean, boolean, text[]
) from public, anon, authenticated;
grant execute on function public.update_my_trainer_consultation_settings(
  boolean, boolean, text[]
) to authenticated, service_role;

revoke all on function private.set_my_workout_location(uuid)
  from public, anon, authenticated;
revoke all on function private.select_my_workout_location(uuid)
  from public, anon, authenticated;
revoke all on function private.remove_my_workout_location(uuid)
  from public, anon, authenticated;
grant execute on function private.set_my_workout_location(uuid),
  private.select_my_workout_location(uuid),
  private.remove_my_workout_location(uuid)
  to authenticated, service_role;

revoke all on function public.set_my_workout_location(uuid)
  from public, anon, authenticated;
revoke all on function public.select_my_workout_location(uuid)
  from public, anon, authenticated;
revoke all on function public.remove_my_workout_location(uuid)
  from public, anon, authenticated;
grant execute on function public.set_my_workout_location(uuid),
  public.select_my_workout_location(uuid),
  public.remove_my_workout_location(uuid)
  to authenticated, service_role;

revoke all on function private.create_location_aware_consultation(
  uuid, text, uuid, uuid, text, uuid, text, text, text, text, jsonb
) from public, anon, authenticated;
grant execute on function private.create_location_aware_consultation(
  uuid, text, uuid, uuid, text, uuid, text, text, text, text, jsonb
) to authenticated, service_role;
revoke all on function public.create_location_aware_consultation(
  uuid, text, uuid, uuid, text, uuid, text, text, text, text, jsonb
) from public, anon, authenticated;
grant execute on function public.create_location_aware_consultation(
  uuid, text, uuid, uuid, text, uuid, text, text, text, text, jsonb
) to authenticated, service_role;

comment on table public.service_regions is
  'Stable Korean province-level region catalog for offline consultation matching.';
comment on table public.trainer_service_areas is
  'Public service areas configured by approved trainers; one area may be primary.';
comment on table public.member_workout_locations is
  'Private member-selected gyms, separate from verified center memberships.';
comment on function public.create_location_aware_consultation(
  uuid, text, uuid, uuid, text, uuid, text, text, text, text, jsonb
) is
  'Creates online consultations or atomically matches offline requests by saved gym or service region.';

commit;
