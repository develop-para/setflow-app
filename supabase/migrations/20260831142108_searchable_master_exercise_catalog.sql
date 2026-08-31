-- The app used to ship an 80-row Dart constant while this table stayed empty.
-- Turn master_exercises into the shared, searchable source of truth without
-- changing its UUID primary key (workout/routine records already reference it).

alter table public.master_exercises
  add column if not exists source_id text,
  add column if not exists name_en text,
  add column if not exists name_ko text,
  add column if not exists aliases text[] not null default '{}'::text[],
  add column if not exists aliases_text text not null default '',
  add column if not exists equipment_key text,
  add column if not exists primary_muscles text[] not null default '{}'::text[],
  add column if not exists secondary_muscles text[] not null default '{}'::text[],
  add column if not exists difficulty text,
  add column if not exists mechanic text,
  add column if not exists force_type text,
  add column if not exists category text,
  add column if not exists instructions text[] not null default '{}'::text[],
  add column if not exists source_name text,
  add column if not exists source_url text,
  add column if not exists source_license text,
  add column if not exists source_license_url text,
  add column if not exists source_revision text,
  add column if not exists is_active boolean not null default true,
  add column if not exists updated_at timestamptz not null default now();

alter table public.master_exercises
  add column if not exists search_text text generated always as (
    lower(
      coalesce(name, '') || ' ' ||
      coalesce(name_ko, '') || ' ' ||
      coalesce(name_en, '') || ' ' ||
      coalesce(target_muscle, '') || ' ' ||
      coalesce(equipment, '') || ' ' ||
      coalesce(equipment_key, '') || ' ' ||
      coalesce(category, '') || ' ' ||
      coalesce(aliases_text, '')
    )
  ) stored,
  add column if not exists search_document tsvector generated always as (
    to_tsvector(
      'simple',
      lower(
        coalesce(name, '') || ' ' ||
        coalesce(name_ko, '') || ' ' ||
        coalesce(name_en, '') || ' ' ||
        coalesce(target_muscle, '') || ' ' ||
        coalesce(equipment, '') || ' ' ||
        coalesce(equipment_key, '') || ' ' ||
        coalesce(category, '') || ' ' ||
        coalesce(aliases_text, '')
      )
    )
  ) stored;

alter table public.master_exercises
  drop constraint if exists master_exercises_input_type_check,
  add constraint master_exercises_input_type_check
    check (input_type = any (array[
      'weight_reps', 'reps_only', 'duration', 'time', 'distance',
      'weight_time'
    ])),
  drop constraint if exists master_exercises_source_identity_check,
  add constraint master_exercises_source_identity_check
    check (
      (source_name is null and source_id is null) or
      (nullif(btrim(source_name), '') is not null and
       nullif(btrim(source_id), '') is not null)
    ),
  drop constraint if exists master_exercises_equipment_key_check,
  add constraint master_exercises_equipment_key_check
    check (
      equipment_key is null or equipment_key = any (array[
        'body_only', 'bands', 'barbell', 'cable', 'dumbbell',
        'ez_curl_bar', 'exercise_ball', 'foam_roll', 'kettlebell',
        'machine', 'medicine_ball', 'other', 'unspecified'
      ])
    ),
  drop constraint if exists master_exercises_difficulty_check,
  add constraint master_exercises_difficulty_check
    check (
      difficulty is null or difficulty = any (array[
        'beginner', 'intermediate', 'expert'
      ])
    ),
  drop constraint if exists master_exercises_row_kind_check,
  add constraint master_exercises_row_kind_check
    check (
      (
        not is_custom and owner_user_id is null and
        nullif(btrim(source_name), '') is not null and
        nullif(btrim(source_id), '') is not null
      ) or (
        is_custom and owner_user_id is not null and
        source_name is null and source_id is null
      )
    ),
  drop constraint if exists master_exercises_metadata_size_check,
  add constraint master_exercises_metadata_size_check
    check (
      char_length(name) between 1 and 160 and
      coalesce(char_length(name_en), 0) <= 160 and
      coalesce(char_length(name_ko), 0) <= 160 and
      coalesce(char_length(equipment), 0) <= 80 and
      cardinality(aliases) <= 40 and
      cardinality(primary_muscles) <= 20 and
      cardinality(secondary_muscles) <= 20 and
      cardinality(instructions) <= 30
    );

create unique index if not exists master_exercises_source_identity_uidx
  on public.master_exercises (source_name, source_id)
  where source_name is not null and source_id is not null;

create index if not exists master_exercises_owner_user_id_idx
  on public.master_exercises (owner_user_id)
  where owner_user_id is not null;

create index if not exists master_exercises_public_facets_idx
  on public.master_exercises (target_muscle, equipment_key, name)
  where is_active and not is_custom;

create index if not exists master_exercises_search_document_idx
  on public.master_exercises using gin (search_document)
  where is_active and not is_custom;

create index if not exists master_exercises_search_text_trgm_idx
  on public.master_exercises using gin (search_text extensions.gin_trgm_ops)
  where is_active and not is_custom;

create table if not exists public.exercise_catalog_imports (
  id uuid primary key default gen_random_uuid(),
  source_name text not null,
  source_revision text not null,
  source_url text not null,
  source_license text not null,
  source_license_url text not null,
  payload_sha256 text not null check (payload_sha256 ~ '^[0-9a-f]{64}$'),
  item_count integer not null check (item_count > 0),
  imported_at timestamptz not null default now(),
  unique (source_name, source_revision)
);

alter table public.exercise_catalog_imports enable row level security;

-- Search is an RPC so the app can later page tens of thousands of rows without
-- learning table details. Empty query + null facets means the complete catalog.
create or replace function public.search_master_exercises(
  p_query text default '',
  p_muscle text default null,
  p_equipment text default null,
  p_limit integer default 100,
  p_offset integer default 0
)
returns table (
  id uuid,
  name text,
  name_ko text,
  name_en text,
  target_muscle text,
  equipment text,
  equipment_key text,
  input_type text,
  aliases text[],
  difficulty text,
  category text,
  source_name text,
  total_count bigint
)
language sql
stable
security invoker
set search_path = ''
as $$
  with input as (
    select lower(btrim(coalesce(p_query, ''))) as query
  ), filtered as (
    select exercise.*
    from public.master_exercises exercise
    cross join input
    where exercise.is_active
      and not exercise.is_custom
      and (
        nullif(btrim(coalesce(p_muscle, '')), '') is null or
        p_muscle = '전체' or
        exercise.target_muscle = p_muscle
      )
      and (
        nullif(btrim(coalesce(p_equipment, '')), '') is null or
        p_equipment = 'all' or
        exercise.equipment_key = p_equipment
      )
      and (
        input.query = '' or
        exercise.search_document @@
          pg_catalog.websearch_to_tsquery('simple', input.query) or
        exercise.search_text like '%' || input.query || '%'
      )
  )
  select
    filtered.id,
    filtered.name,
    filtered.name_ko,
    filtered.name_en,
    filtered.target_muscle,
    filtered.equipment,
    filtered.equipment_key,
    filtered.input_type,
    filtered.aliases,
    filtered.difficulty,
    filtered.category,
    filtered.source_name,
    count(*) over () as total_count
  from filtered
  cross join input
  order by
    case
      when input.query = '' then 4
      when lower(filtered.name) = input.query then 0
      when lower(filtered.name) like input.query || '%' then 1
      when filtered.search_document @@
        pg_catalog.websearch_to_tsquery('simple', input.query) then 2
      else 3
    end,
    case
      when input.query = '' then 0
      else extensions.similarity(filtered.search_text, input.query)
    end desc,
    filtered.name,
    filtered.id
  limit greatest(1, least(coalesce(p_limit, 100), 500))
  offset greatest(coalesce(p_offset, 0), 0);
$$;

alter table public.master_exercises enable row level security;

drop policy if exists rd_master on public.master_exercises;
drop policy if exists wr_master on public.master_exercises;
drop policy if exists master_exercises_public_read on public.master_exercises;
create policy master_exercises_public_read
  on public.master_exercises
  for select
  to anon, authenticated
  using (is_active and not is_custom);

revoke all on table public.master_exercises
  from public, anon, authenticated;
grant select on table public.master_exercises to anon, authenticated;
grant all on table public.master_exercises to service_role;

revoke all on table public.exercise_catalog_imports
  from public, anon, authenticated;
grant all on table public.exercise_catalog_imports to service_role;

revoke all on function public.search_master_exercises(
  text, text, text, integer, integer
) from public;
grant execute on function public.search_master_exercises(
  text, text, text, integer, integer
) to anon, authenticated, service_role;

comment on table public.master_exercises is
  'Shared and custom exercise definitions. Public clients can only read active shared rows.';
comment on table public.exercise_catalog_imports is
  'Immutable provenance records for externally sourced exercise catalog imports.';
comment on function public.search_master_exercises(
  text, text, text, integer, integer
) is 'Searches active shared exercises by Korean/English text, body part, and equipment.';
