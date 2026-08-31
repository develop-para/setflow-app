-- Reproducible importer for the public-domain free-exercise-db snapshot.
-- The JSON itself stays upstream; the importer only accepts the reviewed
-- revision, byte hash, and row count recorded below.

alter table public.master_exercises
  drop constraint if exists master_exercises_equipment_key_check,
  add constraint master_exercises_equipment_key_check
    check (
      equipment_key is null or equipment_key = any (array[
        'body_only', 'bands', 'barbell', 'bench', 'cable', 'dumbbell',
        'ez_curl_bar', 'exercise_ball', 'foam_roll', 'kettlebell',
        'machine', 'medicine_ball', 'squat_rack', 'pullup_bar',
        'dip_bars', 'ab_wheel', 'jump_rope', 'treadmill',
        'stationary_bike', 'stair_climber', 'rowing_machine',
        'elliptical', 'other', 'unspecified'
      ])
    );

create or replace function public.import_free_exercise_db_catalog(
  p_payload jsonb,
  p_revision text,
  p_payload_sha256 text
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
  v_distinct_count integer;
begin
  if p_revision <> 'a859101d633a01c4a1a920d6a8ce41dabba0705f' then
    raise exception 'Unexpected free-exercise-db revision';
  end if;
  if p_payload_sha256 <>
    '5bb747e3fc658f095a60dcbf6d53c96627acdcc6ffb6fffde86f7e26995d40bf'
  then
    raise exception 'Unexpected free-exercise-db payload hash';
  end if;
  if pg_catalog.jsonb_typeof(p_payload) <> 'array' then
    raise exception 'Exercise catalog payload must be a JSON array';
  end if;

  select count(*), count(distinct item ->> 'id')
  into v_count, v_distinct_count
  from pg_catalog.jsonb_array_elements(p_payload) as payload(item);

  if v_count <> 876 or v_distinct_count <> 876 then
    raise exception 'Expected 876 unique exercises, received % rows / % IDs',
      v_count, v_distinct_count;
  end if;
  if exists (
    select 1
    from pg_catalog.jsonb_array_elements(p_payload) as payload(item)
    where nullif(pg_catalog.btrim(item ->> 'id'), '') is null
       or nullif(pg_catalog.btrim(item ->> 'name'), '') is null
  ) then
    raise exception 'Exercise catalog contains an empty ID or name';
  end if;

  update public.master_exercises
  set is_active = false, updated_at = pg_catalog.now()
  where source_name = 'free-exercise-db';

  with raw as (
    select
      item ->> 'id' as source_id,
      pg_catalog.btrim(item ->> 'name') as name_en,
      nullif(pg_catalog.lower(pg_catalog.btrim(item ->> 'equipment')), '')
        as equipment_raw,
      pg_catalog.lower(pg_catalog.btrim(item ->> 'category')) as category,
      nullif(pg_catalog.lower(pg_catalog.btrim(item ->> 'level')), '')
        as difficulty,
      nullif(pg_catalog.lower(pg_catalog.btrim(item ->> 'mechanic')), '')
        as mechanic,
      nullif(pg_catalog.lower(pg_catalog.btrim(item ->> 'force')), '')
        as force_type,
      array(
        select pg_catalog.jsonb_array_elements_text(
          coalesce(item -> 'primaryMuscles', '[]'::jsonb)
        )
      ) as primary_muscles,
      array(
        select pg_catalog.jsonb_array_elements_text(
          coalesce(item -> 'secondaryMuscles', '[]'::jsonb)
        )
      ) as secondary_muscles,
      array(
        select pg_catalog.jsonb_array_elements_text(
          coalesce(item -> 'instructions', '[]'::jsonb)
        )
      ) as instructions
    from pg_catalog.jsonb_array_elements(p_payload) as payload(item)
  ), classified as (
    select
      raw.*,
      case
        when raw.category = 'cardio' then '유산소'
        when raw.primary_muscles[1] = 'chest' then '가슴'
        when raw.primary_muscles[1] = any (
          array['lats', 'lower back', 'middle back', 'traps']
        ) then '등'
        when raw.primary_muscles[1] = 'shoulders' then '어깨'
        when raw.primary_muscles[1] = any (
          array['biceps', 'triceps', 'forearms']
        ) then '팔'
        when raw.primary_muscles[1] = 'abdominals' then '복근'
        when raw.primary_muscles[1] = any (
          array[
            'quadriceps', 'hamstrings', 'glutes', 'calves',
            'adductors', 'abductors'
          ]
        ) then '하체'
        else '기타'
      end as target_muscle,
      case raw.equipment_raw
        when 'body only' then 'body_only'
        when 'e-z curl bar' then 'ez_curl_bar'
        when 'kettlebells' then 'kettlebell'
        when 'exercise ball' then 'exercise_ball'
        when 'foam roll' then 'foam_roll'
        when 'medicine ball' then 'medicine_ball'
        when 'bands' then 'bands'
        when 'barbell' then 'barbell'
        when 'cable' then 'cable'
        when 'dumbbell' then 'dumbbell'
        when 'machine' then 'machine'
        when 'other' then 'other'
        else 'unspecified'
      end as equipment_key,
      case raw.equipment_raw
        when 'body only' then '맨몸'
        when 'e-z curl bar' then '이지바'
        when 'kettlebells' then '케틀벨'
        when 'exercise ball' then '짐볼'
        when 'foam roll' then '폼롤러'
        when 'medicine ball' then '메디신볼'
        when 'bands' then '밴드'
        when 'barbell' then '바벨'
        when 'cable' then '케이블'
        when 'dumbbell' then '덤벨'
        when 'machine' then '머신'
        when 'other' then '기타 기구'
        else '기구 미지정'
      end as equipment_label
    from raw
  ), searchable as (
    select
      classified.*,
      pg_catalog.btrim(
        classified.target_muscle || ' ' ||
        classified.equipment_label || ' ' ||
        case classified.category
          when 'strength' then '근력 웨이트'
          when 'stretching' then '스트레칭 유연성'
          when 'plyometrics' then '플라이오메트릭 점프'
          when 'powerlifting' then '파워리프팅'
          when 'olympic weightlifting' then '역도 올림픽 리프팅'
          when 'strongman' then '스트롱맨'
          when 'cardio' then '유산소 심폐'
          else ''
        end || ' ' ||
        case classified.primary_muscles[1]
          when 'abdominals' then '복부 코어'
          when 'abductors' then '외전근 중둔근'
          when 'adductors' then '내전근'
          when 'biceps' then '이두 바이셉스'
          when 'calves' then '종아리 카프'
          when 'chest' then '흉근 체스트'
          when 'forearms' then '전완근 손목'
          when 'glutes' then '둔근 엉덩이 글루트'
          when 'hamstrings' then '햄스트링 허벅지 뒤'
          when 'lats' then '광배근 랫'
          when 'lower back' then '허리 하부 등'
          when 'middle back' then '등 중앙'
          when 'neck' then '목 넥'
          when 'quadriceps' then '대퇴사두근 허벅지 앞'
          when 'shoulders' then '삼각근 숄더'
          when 'traps' then '승모근 트랩'
          when 'triceps' then '삼두 트라이셉스'
          else ''
        end || ' ' ||
        case when pg_catalog.lower(classified.name_en) like '%incline%'
          then '인클라인 ' else '' end ||
        case when pg_catalog.lower(classified.name_en) like '%decline%'
          then '디클라인 ' else '' end ||
        case when pg_catalog.lower(classified.name_en) like '%bench%'
          then '벤치 ' else '' end ||
        case when pg_catalog.lower(classified.name_en) like '%press%'
          then '프레스 ' else '' end ||
        case when pg_catalog.lower(classified.name_en) like '%squat%'
          then '스쿼트 ' else '' end ||
        case when pg_catalog.lower(classified.name_en) like '%deadlift%'
          then '데드리프트 ' else '' end ||
        case when pg_catalog.lower(classified.name_en) like '%lunge%'
          then '런지 ' else '' end ||
        case when pg_catalog.lower(classified.name_en) like '%curl%'
          then '컬 ' else '' end ||
        case when pg_catalog.lower(classified.name_en) like '%row%'
          then '로우 ' else '' end ||
        case when pg_catalog.lower(classified.name_en) like '%raise%'
          then '레이즈 ' else '' end ||
        case when pg_catalog.lower(classified.name_en) like '%fly%'
          then '플라이 ' else '' end ||
        case when pg_catalog.lower(classified.name_en) like '%pulldown%'
          then '풀다운 ' else '' end ||
        case when pg_catalog.lower(classified.name_en) like '%pull-up%'
          then '풀업 ' else '' end ||
        case when pg_catalog.lower(classified.name_en) like '%push-up%'
          then '푸시업 ' else '' end ||
        case when pg_catalog.lower(classified.name_en) like '%plank%'
          then '플랭크 ' else '' end ||
        case when pg_catalog.lower(classified.name_en) like '%crunch%'
          then '크런치 ' else '' end ||
        case when pg_catalog.lower(classified.name_en) like '%sit-up%'
          then '싯업 ' else '' end ||
        case when pg_catalog.lower(classified.name_en) like '%extension%'
          then '익스텐션 ' else '' end ||
        case when pg_catalog.lower(classified.name_en) like '%bridge%'
          then '브리지 ' else '' end ||
        case when pg_catalog.lower(classified.name_en) like '%stretch%'
          then '스트레칭 ' else '' end ||
        case when pg_catalog.lower(classified.name_en) like '%jump%'
          then '점프 ' else '' end ||
        case when pg_catalog.lower(classified.name_en) like '%swing%'
          then '스윙 ' else '' end
      ) as aliases_text
    from classified
  )
  insert into public.master_exercises (
    id, source_id, name, name_en, name_ko, aliases, aliases_text,
    target_muscle, icon, equipment, equipment_key, input_type,
    primary_muscles, secondary_muscles, difficulty, mechanic, force_type,
    category, instructions, source_name, source_url, source_license,
    source_license_url, source_revision, is_custom, owner_user_id,
    is_active, updated_at
  )
  select
    extensions.uuid_generate_v5(
      '6ba7b811-9dad-11d1-80b4-00c04fd430c8'::uuid,
      'setflow/free-exercise-db/' || searchable.source_id
    ),
    searchable.source_id,
    searchable.name_en,
    searchable.name_en,
    null,
    pg_catalog.regexp_split_to_array(searchable.aliases_text, E'\\s+'),
    searchable.aliases_text,
    searchable.target_muscle,
    null,
    searchable.equipment_label,
    searchable.equipment_key,
    case
      when searchable.category = 'cardio' then 'distance'
      when searchable.category = 'stretching' or
           searchable.equipment_key = 'foam_roll' or
           pg_catalog.lower(searchable.name_en) ~
             '(plank|wall sit|isometric|hold)'
        then 'duration'
      when searchable.equipment_key = 'body_only' then 'reps_only'
      else 'weight_reps'
    end,
    searchable.primary_muscles,
    searchable.secondary_muscles,
    searchable.difficulty,
    searchable.mechanic,
    searchable.force_type,
    searchable.category,
    searchable.instructions,
    'free-exercise-db',
    'https://github.com/yuhonas/free-exercise-db',
    'Unlicense / Public Domain',
    'https://github.com/yuhonas/free-exercise-db/blob/main/LICENSE.md',
    p_revision,
    false,
    null,
    true,
    pg_catalog.now()
  from searchable
  on conflict (source_name, source_id)
    where source_name is not null and source_id is not null
  do update set
    name = excluded.name,
    name_en = excluded.name_en,
    name_ko = excluded.name_ko,
    aliases = excluded.aliases,
    aliases_text = excluded.aliases_text,
    target_muscle = excluded.target_muscle,
    equipment = excluded.equipment,
    equipment_key = excluded.equipment_key,
    input_type = excluded.input_type,
    primary_muscles = excluded.primary_muscles,
    secondary_muscles = excluded.secondary_muscles,
    difficulty = excluded.difficulty,
    mechanic = excluded.mechanic,
    force_type = excluded.force_type,
    category = excluded.category,
    instructions = excluded.instructions,
    source_url = excluded.source_url,
    source_license = excluded.source_license,
    source_license_url = excluded.source_license_url,
    source_revision = excluded.source_revision,
    is_custom = false,
    owner_user_id = null,
    is_active = true,
    updated_at = pg_catalog.now();

  insert into public.exercise_catalog_imports (
    source_name, source_revision, source_url, source_license,
    source_license_url, payload_sha256, item_count
  ) values (
    'free-exercise-db',
    p_revision,
    'https://raw.githubusercontent.com/yuhonas/free-exercise-db/' ||
      p_revision || '/dist/exercises.json',
    'Unlicense / Public Domain',
    'https://github.com/yuhonas/free-exercise-db/blob/main/LICENSE.md',
    p_payload_sha256,
    v_count
  )
  on conflict (source_name, source_revision) do update set
    source_url = excluded.source_url,
    source_license = excluded.source_license,
    source_license_url = excluded.source_license_url,
    payload_sha256 = excluded.payload_sha256,
    item_count = excluded.item_count,
    imported_at = pg_catalog.now();

  return v_count;
end;
$$;

revoke all on function public.import_free_exercise_db_catalog(
  jsonb, text, text
) from public, anon, authenticated;
grant execute on function public.import_free_exercise_db_catalog(
  jsonb, text, text
) to service_role;

comment on function public.import_free_exercise_db_catalog(
  jsonb, text, text
) is 'Imports the verified 876-row free-exercise-db public-domain snapshot.';
