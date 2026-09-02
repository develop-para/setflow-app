-- Localize the pinned free-exercise-db snapshot without losing its English
-- source names, and expose detailed muscle metadata through the catalog port.

create or replace function public.normalize_imported_exercise_aliases()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_aliases text[];
begin
  if new.source_name = 'free-exercise-db' and
     nullif(pg_catalog.btrim(new.aliases_text), '') is not null
  then
    select coalesce(
      pg_catalog.array_agg(
        distinct candidate.alias
        order by candidate.alias
      ),
      '{}'::text[]
    )
    into v_aliases
    from (
      select split.alias
      from pg_catalog.unnest(
        pg_catalog.regexp_split_to_array(
          pg_catalog.btrim(new.aliases_text),
          E'\\s+'
        )
      ) as split(alias)
      union all
      select pg_catalog.btrim(new.name_ko)
      where nullif(pg_catalog.btrim(new.name_ko), '') is not null
    ) as candidate
    where nullif(pg_catalog.btrim(candidate.alias), '') is not null;
    new.aliases := v_aliases;
  end if;
  return new;
end;
$$;

revoke all on function public.normalize_imported_exercise_aliases()
  from public, anon, authenticated;

create or replace function public.apply_free_exercise_db_korean_names(
  p_korean_names jsonb,
  p_revision text
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_mapping_count integer;
  v_distinct_name_count integer;
  v_active_count integer;
  v_updated_count integer;
begin
  if p_revision is distinct from
     'a859101d633a01c4a1a920d6a8ce41dabba0705f'
  then
    raise exception 'Unexpected free-exercise-db revision';
  end if;

  if pg_catalog.jsonb_typeof(p_korean_names) is distinct from 'object' then
    raise exception 'Korean exercise names must be a JSON object';
  end if;

  select pg_catalog.count(*)
  into v_mapping_count
  from pg_catalog.jsonb_object_keys(p_korean_names) as mapping(source_id);

  if v_mapping_count <> 876 then
    raise exception 'Expected 876 Korean exercise names, received %',
      v_mapping_count;
  end if;

  if exists (
    select 1
    from pg_catalog.jsonb_each(p_korean_names) as mapping(source_id, name_value)
    where pg_catalog.jsonb_typeof(mapping.name_value) is distinct from 'string'
  ) then
    raise exception 'Every Korean exercise name must be a JSON string';
  end if;

  if exists (
    select 1
    from pg_catalog.jsonb_each_text(p_korean_names) as mapping(source_id, name_ko)
    where nullif(pg_catalog.btrim(mapping.source_id), '') is null
       or nullif(pg_catalog.btrim(mapping.name_ko), '') is null
       or pg_catalog.char_length(pg_catalog.btrim(mapping.name_ko)) > 160
       or mapping.name_ko ~ '[A-Za-z]'
       or mapping.name_ko !~ '[가-힣]'
  ) then
    raise exception 'Korean exercise names contain an empty, overlong, Latin, or non-Hangul value';
  end if;

  select pg_catalog.count(
    distinct pg_catalog.regexp_replace(
      pg_catalog.lower(pg_catalog.btrim(mapping.name_ko)),
      E'\\s+',
      ' ',
      'g'
    )
  )
  into v_distinct_name_count
  from pg_catalog.jsonb_each_text(p_korean_names) as mapping(source_id, name_ko);

  if v_distinct_name_count <> v_mapping_count then
    raise exception 'Korean exercise names must be unique after normalization';
  end if;

  select pg_catalog.count(*)
  into v_active_count
  from public.master_exercises as exercise
  where exercise.source_name = 'free-exercise-db'
    and exercise.is_active;

  if v_active_count <> 876 then
    raise exception 'Expected 876 active free-exercise-db rows, received %',
      v_active_count;
  end if;

  if exists (
    select exercise.source_id
    from public.master_exercises as exercise
    where exercise.source_name = 'free-exercise-db'
      and exercise.is_active
    except
    select mapping.source_id
    from pg_catalog.jsonb_object_keys(p_korean_names) as mapping(source_id)
  ) or exists (
    select mapping.source_id
    from pg_catalog.jsonb_object_keys(p_korean_names) as mapping(source_id)
    except
    select exercise.source_id
    from public.master_exercises as exercise
    where exercise.source_name = 'free-exercise-db'
      and exercise.is_active
  ) then
    raise exception 'Korean exercise name IDs do not match the active source IDs';
  end if;

  if exists (
    select 1
    from public.master_exercises as exercise
    where exercise.source_name = 'free-exercise-db'
      and exercise.is_active
      and exercise.source_revision is distinct from p_revision
  ) then
    raise exception 'Active free-exercise-db rows use an unexpected revision';
  end if;

  with mapping as (
    select
      names.source_id,
      pg_catalog.btrim(names.name_ko) as name_ko
    from pg_catalog.jsonb_each_text(p_korean_names)
      as names(source_id, name_ko)
  )
  update public.master_exercises as exercise
  set
    name = mapping.name_ko,
    name_ko = mapping.name_ko,
    aliases_text = case
      when pg_catalog.strpos(exercise.aliases_text, mapping.name_ko) > 0
        then exercise.aliases_text
      else pg_catalog.btrim(
        exercise.aliases_text || ' ' || mapping.name_ko
      )
    end,
    aliases = case
      when mapping.name_ko = any(exercise.aliases) then exercise.aliases
      else pg_catalog.array_append(exercise.aliases, mapping.name_ko)
    end,
    updated_at = pg_catalog.now()
  from mapping
  where exercise.source_name = 'free-exercise-db'
    and exercise.source_id = mapping.source_id
    and exercise.is_active;

  get diagnostics v_updated_count = row_count;
  if v_updated_count <> 876 then
    raise exception 'Expected to localize 876 rows, updated %', v_updated_count;
  end if;

  if exists (
    select 1
    from public.master_exercises as exercise
    join pg_catalog.jsonb_each_text(p_korean_names)
      as mapping(source_id, name_ko)
      on mapping.source_id = exercise.source_id
    where exercise.source_name = 'free-exercise-db'
      and exercise.is_active
      and (
        exercise.name is distinct from pg_catalog.btrim(mapping.name_ko) or
        exercise.name_ko is distinct from pg_catalog.btrim(mapping.name_ko) or
        pg_catalog.strpos(
          exercise.aliases_text,
          pg_catalog.btrim(mapping.name_ko)
        ) = 0 or
        not (pg_catalog.btrim(mapping.name_ko) = any(exercise.aliases))
      )
  ) then
    raise exception 'Korean exercise name postcondition failed';
  end if;

  return v_updated_count;
end;
$$;

revoke all on function public.apply_free_exercise_db_korean_names(jsonb, text)
  from public, anon, authenticated, service_role;

comment on function public.apply_free_exercise_db_korean_names(jsonb, text) is
  'Validates and applies the complete Korean name map for the pinned free-exercise-db snapshot.';

create or replace function public.import_localized_free_exercise_db_catalog(
  p_payload jsonb,
  p_revision text,
  p_payload_sha256 text,
  p_korean_names jsonb
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_imported_count integer;
  v_localized_count integer;
begin
  v_imported_count := public.import_free_exercise_db_catalog(
    p_payload,
    p_revision,
    p_payload_sha256
  );
  v_localized_count := public.apply_free_exercise_db_korean_names(
    p_korean_names,
    p_revision
  );

  if v_imported_count <> v_localized_count then
    raise exception 'Import/localization count mismatch: % / %',
      v_imported_count, v_localized_count;
  end if;

  return v_localized_count;
end;
$$;

revoke all on function public.import_localized_free_exercise_db_catalog(
  jsonb, text, text, jsonb
) from public, anon, authenticated;
grant execute on function public.import_localized_free_exercise_db_catalog(
  jsonb, text, text, jsonb
) to service_role;

comment on function public.import_localized_free_exercise_db_catalog(
  jsonb, text, text, jsonb
) is 'Atomically imports and localizes the pinned 876-row free-exercise-db snapshot.';

-- The legacy importer resets name/name_ko to English/null. Keep it callable by
-- this SECURITY DEFINER wrapper's owner, but close the direct service-role path
-- so every future import is localized in the same transaction.
revoke execute on function public.import_free_exercise_db_catalog(
  jsonb, text, text
) from service_role;

do $migration$
declare
  v_mapping_count integer;
  v_distinct_name_count integer;
  v_active_count integer;
  v_korean_names jsonb :=
    $part_a$
{
  "3_4_Sit-Up": "3/4 싯업",
  "90_90_Hamstring": "90/90 햄스트링 스트레칭",
  "Ab_Crunch_Machine": "복근 크런치 머신",
  "Ab_Roller": "복근 롤러",
  "Adductor": "내전근 폼롤링",
  "Adductor_Groin": "내전근·서혜부 파트너 스트레칭",
  "Advanced_Kettlebell_Windmill": "어드밴스드 케틀벨 윈드밀",
  "Air_Bike": "바이시클 크런치",
  "All_Fours_Quad_Stretch": "네발 지지 대퇴사두근 스트레칭",
  "Alternate_Hammer_Curl": "얼터네이팅 해머 컬",
  "Alternate_Heel_Touchers": "얼터네이팅 힐 터치",
  "Alternate_Incline_Dumbbell_Curl": "얼터네이팅 인클라인 덤벨 컬",
  "Alternate_Leg_Diagonal_Bound": "얼터네이팅 레그 대각선 바운드",
  "Alternating_Cable_Shoulder_Press": "얼터네이팅 케이블 숄더 프레스",
  "Alternating_Deltoid_Raise": "프론트·사이드 얼터네이팅 덤벨 레이즈",
  "Alternating_Floor_Press": "얼터네이팅 케틀벨 플로어 프레스",
  "Alternating_Hang_Clean": "얼터네이팅 케틀벨 행 클린",
  "Alternating_Kettlebell_Press": "얼터네이팅 케틀벨 프레스",
  "Alternating_Kettlebell_Row": "얼터네이팅 케틀벨 로우",
  "Alternating_Renegade_Row": "얼터네이팅 케틀벨 레니게이드 로우",
  "Ankle_Circles": "발목 돌리기",
  "Ankle_On_The_Knee": "누워서 4자 둔근 스트레칭",
  "Anterior_Tibialis-SMR": "전경골근 자가근막이완",
  "Anti-Gravity_Press": "바벨 안티 그래비티 프레스",
  "Arm_Circles": "암 서클",
  "Arnold_Dumbbell_Press": "아놀드 덤벨 프레스",
  "Around_The_Worlds": "덤벨 어라운드 더 월드",
  "Atlas_Stone_Trainer": "아틀라스 스톤 트레이너 리프트",
  "Atlas_Stones": "아틀라스 스톤 리프트",
  "Axle_Deadlift": "액슬 데드리프트",
  "Back_Flyes_-_With_Bands": "밴드 리버스 플라이",
  "Backward_Drag": "백워드 슬레드 드래그",
  "Backward_Medicine_Ball_Throw": "백워드 메디신볼 오버헤드 스로",
  "Balance_Board": "밸런스 보드 스탠딩",
  "Ball_Leg_Curl": "짐볼 레그 컬",
  "Band_Assisted_Pull-Up": "밴드 어시스트 풀업",
  "Band_Good_Morning": "밴드 굿모닝",
  "Band_Good_Morning_Pull_Through": "앵커드 밴드 굿모닝(풀 스루)",
  "Band_Hip_Adductions": "밴드 힙 어덕션",
  "Band_Pull_Apart": "밴드 풀 어파트",
  "Band_Skull_Crusher": "밴드 스컬 크러셔",
  "Barbell_Ab_Rollout": "바벨 복근 롤아웃",
  "Barbell_Ab_Rollout_-_On_Knees": "니링 바벨 복근 롤아웃",
  "Barbell_Bench_Press_-_Medium_Grip": "바벨 벤치 프레스(미디엄 그립)",
  "Barbell_Curl": "바벨 컬",
  "Barbell_Curls_Lying_Against_An_Incline": "인클라인 벤치 엎드린 바벨 컬",
  "Barbell_Deadlift": "바벨 데드리프트",
  "Barbell_Full_Squat": "바벨 풀 스쿼트",
  "Barbell_Glute_Bridge": "바벨 글루트 브리지",
  "Barbell_Guillotine_Bench_Press": "바벨 길로틴 벤치 프레스",
  "Barbell_Hack_Squat": "바벨 핵 스쿼트",
  "Barbell_Hip_Thrust": "바벨 힙 쓰러스트",
  "Barbell_Incline_Bench_Press_-_Medium_Grip": "인클라인 바벨 벤치 프레스(미디엄 그립)",
  "Barbell_Incline_Shoulder_Raise": "인클라인 바벨 숄더 레이즈",
  "Barbell_Lunge": "바벨 런지",
  "Barbell_Rear_Delt_Row": "바벨 리어 델트 로우",
  "Barbell_Rollout_from_Bench": "벤치 니링 바벨 복근 롤아웃",
  "Barbell_Seated_Calf_Raise": "바벨 시티드 카프 레이즈",
  "Barbell_Shoulder_Press": "바벨 숄더 프레스",
  "Barbell_Shrug": "바벨 슈러그",
  "Barbell_Shrug_Behind_The_Back": "비하인드 백 바벨 슈러그",
  "Barbell_Side_Bend": "바벨 사이드 벤드",
  "Barbell_Side_Split_Squat": "바벨 사이드 스플릿 스쿼트",
  "Barbell_Squat": "바벨 백 스쿼트",
  "Barbell_Squat_To_A_Bench": "벤치 터치 바벨 스쿼트",
  "Barbell_Step_Ups": "바벨 스텝업",
  "Barbell_Walking_Lunge": "바벨 워킹 런지",
  "Battling_Ropes": "배틀 로프",
  "Bear_Crawl_Sled_Drags": "베어 크롤 슬레드 드래그",
  "Behind_Head_Chest_Stretch": "비하인드 헤드 파트너 가슴 스트레칭",
  "Bench_Dips": "벤치 딥스",
  "Bench_Jump": "벤치 점프",
  "Bench_Press_-_Powerlifting": "파워리프팅 벤치 프레스",
  "Bench_Press_-_With_Bands": "밴드 저항 벤치 프레스",
  "Bench_Press_with_Chains": "체인 벤치 프레스",
  "Bench_Sprint": "벤치 스프린트",
  "Bent-Arm_Barbell_Pullover": "벤트암 바벨 풀오버",
  "Bent-Arm_Dumbbell_Pullover": "벤트암 덤벨 풀오버",
  "Bent-Knee_Hip_Raise": "벤트니 힙 레이즈",
  "Bent_Over_Barbell_Row": "벤트오버 바벨 로우",
  "Bent_Over_Dumbbell_Rear_Delt_Raise_With_Head_On_Bench": "벤치에 머리 대고 벤트오버 덤벨 리어 델트 레이즈",
  "Bent_Over_Low-Pulley_Side_Lateral": "벤트오버 원암 로우 풀리 레터럴 레이즈",
  "Bent_Over_One-Arm_Long_Bar_Row": "벤트오버 원암 랜드마인 로우",
  "Bent_Over_Two-Arm_Long_Bar_Row": "벤트오버 투암 랜드마인 로우",
  "Bent_Over_Two-Dumbbell_Row": "벤트오버 투 덤벨 로우",
  "Bent_Over_Two-Dumbbell_Row_With_Palms_In": "벤트오버 투 덤벨 로우(뉴트럴 그립)",
  "Bent_Press": "케틀벨 벤트 프레스",
  "Bicycling": "야외 사이클링",
  "Bicycling_Stationary": "실내 자전거",
  "Board_Press": "바벨 보드 프레스",
  "Body-Up": "업다운 플랭크",
  "Body_Tricep_Press": "바디웨이트 트라이셉스 프레스",
  "Bodyweight_Flyes": "롤링 이지바 바디웨이트 플라이",
  "Bodyweight_Mid_Row": "바디웨이트 미드 로우",
  "Bodyweight_Squat": "맨몸 스쿼트",
  "Bodyweight_Walking_Lunge": "맨몸 워킹 런지",
  "Bosu_Ball_Cable_Crunch_With_Side_Bends": "보수볼 케이블 크런치 앤 사이드 벤드",
  "Bottoms-Up_Clean_From_The_Hang_Position": "케틀벨 보텀업 행 클린",
  "Bottoms_Up": "보텀업 리버스 크런치",
  "Box_Jump_Multiple_Response": "멀티 리스폰스 박스 점프",
  "Box_Skip": "박스 스킵 바운드",
  "Box_Squat": "바벨 박스 스쿼트",
  "Box_Squat_with_Bands": "밴드 저항 바벨 박스 스쿼트",
  "Box_Squat_with_Chains": "체인 바벨 박스 스쿼트",
  "Brachialis-SMR": "상완근 폼롤링",
  "Bradford_Rocky_Presses": "브래드퍼드·로키 프레스",
  "Butt-Ups": "포어암 플랭크 힙 레이즈",
  "Butt_Lift_Bridge": "힙 리프트 브리지",
  "Butterfly": "펙덱 플라이",
  "Cable_Chest_Press": "케이블 체스트 프레스",
  "Cable_Crossover": "케이블 크로스오버",
  "Cable_Crunch": "케이블 크런치",
  "Cable_Deadlifts": "케이블 데드리프트",
  "Cable_Hammer_Curls_-_Rope_Attachment": "로프 케이블 해머 컬",
  "Cable_Hip_Adduction": "케이블 힙 어덕션",
  "Cable_Incline_Pushdown": "인클라인 케이블 랫 푸시다운",
  "Cable_Incline_Triceps_Extension": "인클라인 케이블 트라이셉스 익스텐션",
  "Cable_Internal_Rotation": "케이블 내회전",
  "Cable_Iron_Cross": "케이블 아이언 크로스",
  "Cable_Judo_Flip": "케이블 유도 플립",
  "Cable_Lying_Triceps_Extension": "라잉 케이블 트라이셉스 익스텐션",
  "Cable_One_Arm_Tricep_Extension": "원암 케이블 트라이셉스 익스텐션",
  "Cable_Preacher_Curl": "케이블 프리처 컬",
  "Cable_Rear_Delt_Fly": "케이블 리어 델트 플라이",
  "Cable_Reverse_Crunch": "케이블 리버스 크런치",
  "Cable_Rope_Overhead_Triceps_Extension": "로프 케이블 오버헤드 트라이셉스 익스텐션",
  "Cable_Rope_Rear-Delt_Rows": "로프 케이블 리어 델트 로우",
  "Cable_Russian_Twists": "케이블 러시안 트위스트",
  "Cable_Seated_Crunch": "시티드 케이블 크런치",
  "Cable_Seated_Lateral_Raise": "시티드 케이블 레터럴 레이즈",
  "Cable_Shoulder_Press": "케이블 숄더 프레스",
  "Cable_Shrugs": "케이블 슈러그",
  "Cable_Wrist_Curl": "케이블 리스트 컬",
  "Calf-Machine_Shoulder_Shrug": "카프 머신 숄더 슈러그",
  "Calf_Press": "머신 카프 프레스",
  "Calf_Press_On_The_Leg_Press_Machine": "레그 프레스 머신 카프 프레스",
  "Calf_Raise_On_A_Dumbbell": "덤벨 핸들 밸런스 카프 레이즈",
  "Calf_Raises_-_With_Bands": "밴드 카프 레이즈",
  "Calf_Stretch_Elbows_Against_Wall": "팔꿈치 벽 지지 종아리 스트레칭",
  "Calf_Stretch_Hands_Against_Wall": "손 벽 지지 종아리 스트레칭",
  "Calves-SMR": "종아리 폼롤링",
  "Car_Deadlift": "카 데드리프트",
  "Car_Drivers": "플레이트 카 드라이버",
  "Carioca_Quick_Step": "카리오카 퀵 스텝",
  "Cat_Stretch": "고양이 자세 허리 스트레칭",
  "Catch_and_Overhead_Throw": "메디신볼 캐치 앤 오버헤드 스로",
  "Chain_Handle_Extension": "라잉 체인 핸들 트라이셉스 익스텐션",
  "Chain_Press": "라잉 체인 프레스",
  "Chair_Leg_Extended_Stretch": "의자 햄스트링 스트레칭",
  "Chair_Lower_Back_Stretch": "의자 광배근·허리 스트레칭",
  "Chair_Squat": "스미스 머신 체어 스쿼트",
  "Chair_Upper_Body_Stretch": "의자 상체 스트레칭",
  "Chest_And_Front_Of_Shoulder_Stretch": "가슴·전면 어깨 스트레칭",
  "Chest_Push_from_3_point_stance": "3점 스탠스 메디신볼 체스트 패스",
  "Chest_Push_multiple_response": "연속 반응 메디신볼 체스트 패스",
  "Chest_Push_single_response": "단발 반응 메디신볼 체스트 패스",
  "Chest_Push_with_Run_Release": "런 릴리스 메디신볼 체스트 패스",
  "Chest_Stretch_on_Stability_Ball": "짐볼 가슴 스트레칭",
  "Childs_Pose": "아기 자세",
  "Chin-Up": "친업",
  "Chin_To_Chest_Stretch": "턱 당기기 목 스트레칭",
  "Circus_Bell": "서커스 벨 클린 앤 프레스",
  "Clean": "바벨 클린",
  "Clean_Deadlift": "클린 데드리프트",
  "Clean_Pull": "클린 풀",
  "Clean_Shrug": "클린 슈러그",
  "Clean_and_Jerk": "클린 앤 저크",
  "Clean_and_Press": "클린 앤 프레스",
  "Clean_from_Blocks": "블록 클린",
  "Clock_Push-Up": "시계 방향 플라이오 푸시업",
  "Close-Grip_Barbell_Bench_Press": "클로즈 그립 바벨 벤치 프레스",
  "Close-Grip_Dumbbell_Press": "클로즈 그립 덤벨 프레스",
  "Close-Grip_EZ-Bar_Curl_with_Band": "밴드 저항 클로즈 그립 이지바 컬",
  "Close-Grip_EZ-Bar_Press": "클로즈 그립 이지바 프레스",
  "Close-Grip_EZ_Bar_Curl": "클로즈 그립 이지바 컬",
  "Close-Grip_Front_Lat_Pulldown": "클로즈 그립 프론트 랫 풀다운",
  "Close-Grip_Push-Up_off_of_a_Dumbbell": "덤벨 지지 클로즈 그립 푸시업",
  "Close-Grip_Standing_Barbell_Curl": "스탠딩 클로즈 그립 바벨 컬",
  "Cocoons": "코쿤 크런치",
  "Conans_Wheel": "코난스 휠",
  "Concentration_Curls": "컨센트레이션 컬",
  "Cross-Body_Crunch": "크로스 바디 크런치",
  "Cross_Body_Hammer_Curl": "크로스 바디 해머 컬",
  "Cross_Over_-_With_Bands": "밴드 크로스오버",
  "Crossover_Reverse_Lunge": "크로스오버 리버스 런지 스트레칭",
  "Crucifix": "크루시픽스 홀드",
  "Crunch_-_Hands_Overhead": "핸즈 오버헤드 크런치",
  "Crunch_-_Legs_On_Exercise_Ball": "짐볼에 다리 올린 크런치",
  "Crunches": "크런치",
  "Cuban_Press": "쿠반 프레스",
  "Dancers_Stretch": "댄서 스트레칭",
  "Dead_Bug": "데드 버그",
  "Deadlift_with_Bands": "밴드 저항 바벨 데드리프트",
  "Deadlift_with_Chains": "체인 바벨 데드리프트",
  "Decline_Barbell_Bench_Press": "디클라인 바벨 벤치 프레스",
  "Decline_Close-Grip_Bench_To_Skull_Crusher": "디클라인 클로즈 그립 벤치 프레스 투 스컬 크러셔",
  "Decline_Crunch": "디클라인 크런치",
  "Decline_Dumbbell_Bench_Press": "디클라인 덤벨 벤치 프레스",
  "Decline_Dumbbell_Flyes": "디클라인 덤벨 플라이",
  "Decline_Dumbbell_Triceps_Extension": "디클라인 덤벨 트라이셉스 익스텐션",
  "Decline_EZ_Bar_Triceps_Extension": "디클라인 이지바 트라이셉스 익스텐션",
  "Decline_Oblique_Crunch": "디클라인 오블리크 크런치",
  "Decline_Push-Up": "디클라인 푸시업",
  "Decline_Reverse_Crunch": "디클라인 리버스 크런치",
  "Decline_Smith_Press": "디클라인 스미스 머신 프레스",
  "Deficit_Deadlift": "디피싯 데드리프트",
  "Depth_Jump_Leap": "데프스 점프 투 박스",
  "Dip_Machine": "딥 머신",
  "Dips_-_Chest_Version": "체스트 딥스",
  "Dips_-_Triceps_Version": "트라이셉스 딥스",
  "Donkey_Calf_Raises": "동키 카프 레이즈",
  "Double_Kettlebell_Alternating_Hang_Clean": "더블 케틀벨 얼터네이팅 행 클린",
  "Double_Kettlebell_Jerk": "더블 케틀벨 저크",
  "Double_Kettlebell_Push_Press": "더블 케틀벨 푸시 프레스",
  "Double_Kettlebell_Snatch": "더블 케틀벨 스내치",
  "Double_Kettlebell_Windmill": "더블 케틀벨 윈드밀",
  "Double_Leg_Butt_Kick": "더블 레그 버트 킥 점프",
  "Downward_Facing_Balance": "짐볼 엎드린 밸런스",
  "Drag_Curl": "드래그 컬",
  "Drop_Push": "플랫폼 드롭 푸시업",
  "Dumbbell_Alternate_Bicep_Curl": "얼터네이팅 덤벨 컬",
  "Dumbbell_Bench_Press": "덤벨 벤치 프레스",
  "Dumbbell_Bench_Press_with_Neutral_Grip": "덤벨 벤치 프레스(뉴트럴 그립)",
  "Dumbbell_Bicep_Curl": "덤벨 컬",
  "Dumbbell_Clean": "덤벨 클린",
  "Dumbbell_Floor_Press": "덤벨 플로어 프레스",
  "Dumbbell_Flyes": "덤벨 플라이",
  "Dumbbell_Incline_Row": "인클라인 덤벨 로우",
  "Dumbbell_Incline_Shoulder_Raise": "인클라인 덤벨 숄더 레이즈",
  "Dumbbell_Lunges": "덤벨 런지",
  "Dumbbell_Lying_One-Arm_Rear_Lateral_Raise": "라잉 원암 덤벨 리어 레터럴 레이즈",
  "Dumbbell_Lying_Pronation": "엎드린 덤벨 어깨 외회전",
  "Dumbbell_Lying_Rear_Lateral_Raise": "라잉 덤벨 리어 레터럴 레이즈",
  "Dumbbell_Lying_Supination": "사이드 라잉 덤벨 어깨 외회전",
  "Dumbbell_One-Arm_Shoulder_Press": "원암 덤벨 숄더 프레스",
  "Dumbbell_One-Arm_Triceps_Extension": "원암 덤벨 트라이셉스 익스텐션",
  "Dumbbell_One-Arm_Upright_Row": "원암 덤벨 업라이트 로우",
  "Dumbbell_Prone_Incline_Curl": "프론 인클라인 덤벨 컬",
  "Dumbbell_Raise": "덤벨 레이즈",
  "Dumbbell_Rear_Lunge": "덤벨 리어 런지",
  "Dumbbell_Scaption": "덤벨 스캡션",
  "Dumbbell_Seated_Box_Jump": "덤벨 시티드 박스 점프",
  "Dumbbell_Seated_One-Leg_Calf_Raise": "덤벨 시티드 원 레그 카프 레이즈",
  "Dumbbell_Shoulder_Press": "덤벨 숄더 프레스",
  "Dumbbell_Shrug": "덤벨 슈러그",
  "Dumbbell_Side_Bend": "덤벨 사이드 벤드",
  "Dumbbell_Squat": "덤벨 스쿼트",
  "Dumbbell_Squat_To_A_Bench": "벤치 터치 덤벨 스쿼트",
  "Dumbbell_Step_Ups": "덤벨 스텝업",
  "Dumbbell_Tricep_Extension_-Pronated_Grip": "라잉 덤벨 트라이셉스 익스텐션(오버핸드 그립)",
  "Dynamic_Back_Stretch": "다이내믹 등 스트레칭",
  "Dynamic_Chest_Stretch": "다이내믹 가슴 스트레칭",
  "EZ-Bar_Curl": "이지바 컬",
  "EZ-Bar_Skullcrusher": "이지바 스컬 크러셔",
  "Elbow_Circles": "팔꿈치 돌리기",
  "Elbow_to_Knee": "엘보 투 니 크런치",
  "Elbows_Back": "양팔 뒤로 당기기 가슴 스트레칭",
  "Elevated_Back_Lunge": "플랫폼 바벨 리버스 런지",
  "Elevated_Cable_Rows": "엘리베이티드 시티드 케이블 로우",
  "Elliptical_Trainer": "일립티컬 트레이너",
  "Exercise_Ball_Crunch": "짐볼 크런치",
  "Exercise_Ball_Pull-In": "짐볼 풀인",
  "Extended_Range_One-Arm_Kettlebell_Floor_Press": "확장 가동범위 원암 케틀벨 플로어 프레스",
  "External_Rotation": "덤벨 외회전",
  "External_Rotation_with_Band": "밴드 외회전",
  "External_Rotation_with_Cable": "케이블 외회전",
  "Face_Pull": "페이스 풀",
  "Farmers_Walk": "파머스 워크",
  "Fast_Skipping": "패스트 스키핑",
  "Finger_Curls": "바벨 핑거 컬",
  "Flat_Bench_Cable_Flyes": "플랫 벤치 케이블 플라이",
  "Flat_Bench_Leg_Pull-In": "플랫 벤치 레그 풀인",
  "Flat_Bench_Lying_Leg_Raise": "플랫 벤치 라잉 레그 레이즈",
  "Flexor_Incline_Dumbbell_Curls": "플렉서 인클라인 덤벨 컬",
  "Floor_Glute-Ham_Raise": "플로어 글루트햄 레이즈",
  "Floor_Press": "바벨 플로어 프레스",
  "Floor_Press_with_Chains": "체인 바벨 플로어 프레스",
  "Flutter_Kicks": "엎드린 벤치 플러터 킥",
  "Foot-SMR": "발바닥 자가근막이완",
  "Forward_Drag_with_Press": "포워드 슬레드 드래그 앤 프레스",
  "Frankenstein_Squat": "프랑켄슈타인 스쿼트",
  "Freehand_Jump_Squat": "맨몸 점프 스쿼트",
  "Frog_Hops": "프로그 홉",
  "Frog_Sit-Ups": "프로그 싯업",
  "Front_Barbell_Squat": "바벨 프론트 스쿼트",
  "Front_Barbell_Squat_To_A_Bench": "벤치 터치 바벨 프론트 스쿼트",
  "Front_Box_Jump": "프론트 박스 점프",
  "Front_Cable_Raise": "케이블 프론트 레이즈",
  "Front_Cone_Hops_or_hurdle_hops": "프론트 콘 홉(허들 홉)",
  "Front_Dumbbell_Raise": "덤벨 프론트 레이즈",
  "Front_Incline_Dumbbell_Raise": "인클라인 덤벨 프론트 레이즈",
  "Front_Leg_Raises": "프론트 레그 스윙 스트레칭"
}

    $part_a$::jsonb ||
    $part_b$
{
  "Front_Plate_Raise": "플레이트 프론트 레이즈",
  "Front_Raise_And_Pullover": "프론트 레이즈 앤 풀오버",
  "Front_Squat_Clean_Grip": "클린 그립 프론트 스쿼트",
  "Front_Squats_With_Two_Kettlebells": "더블 케틀벨 프론트 스쿼트",
  "Front_Two-Dumbbell_Raise": "양손 덤벨 프론트 레이즈",
  "Full_Range-Of-Motion_Lat_Pulldown": "전체 가동 범위 랫 풀다운",
  "Gironda_Sternum_Chins": "지론다 흉골 친업",
  "Glute_Ham_Raise": "글루트 햄 레이즈",
  "Glute_Kickback": "글루트 킥백",
  "Goblet_Squat": "고블릿 스쿼트",
  "Good_Morning": "굿모닝",
  "Good_Morning_off_Pins": "핀 시작 굿모닝",
  "Gorilla_Chin_Crunch": "고릴라 친업 크런치",
  "Groin_and_Back_Stretch": "사타구니·등 스트레칭",
  "Groiners": "그로이너",
  "Hack_Squat": "핵 스쿼트",
  "Hammer_Curls": "해머 컬",
  "Hammer_Grip_Incline_DB_Bench_Press": "해머 그립 인클라인 덤벨 벤치프레스",
  "Hamstring-SMR": "햄스트링 자가 근막 이완",
  "Hamstring_Stretch": "햄스트링 스트레칭",
  "Handstand_Push-Ups": "핸드스탠드 푸시업",
  "Hang_Clean": "행 클린",
  "Hang_Clean_-_Below_the_Knees": "무릎 아래 행 클린",
  "Hang_Snatch": "행 스내치",
  "Hang_Snatch_-_Below_Knees": "무릎 아래 행 스내치",
  "Hanging_Bar_Good_Morning": "서스펜션 바 굿모닝",
  "Hanging_Leg_Raise": "행잉 레그 레이즈",
  "Hanging_Pike": "행잉 파이크",
  "Heaving_Snatch_Balance": "히빙 스내치 밸런스",
  "Heavy_Bag_Thrust": "헤비백 회전 밀어내기",
  "High_Cable_Curls": "하이 케이블 컬",
  "Hip_Circles_prone": "엎드린 힙 서클",
  "Hip_Extension_with_Bands": "밴드 힙 익스텐션",
  "Hip_Flexion_with_Band": "밴드 힙 플렉션",
  "Hip_Lift_with_Band": "밴드 힙 리프트",
  "Hug_A_Ball": "짐볼 허그 스트레칭",
  "Hug_Knees_To_Chest": "양쪽 무릎 가슴 당기기",
  "Hurdle_Hops": "허들 홉",
  "Hyperextensions_Back_Extensions": "하이퍼익스텐션 백 익스텐션",
  "Hyperextensions_With_No_Hyperextension_Bench": "플랫 벤치 파트너 보조 하이퍼익스텐션",
  "IT_Band_and_Glute_Stretch": "장경인대·둔근 스트레칭",
  "Iliotibial_Tract-SMR": "장경인대 자가 근막 이완",
  "Inchworm": "인치웜",
  "Incline_Barbell_Triceps_Extension": "인클라인 바벨 트라이셉스 익스텐션",
  "Incline_Bench_Pull": "인클라인 벤치 풀",
  "Incline_Cable_Chest_Press": "인클라인 케이블 체스트 프레스",
  "Incline_Cable_Flye": "인클라인 케이블 플라이",
  "Incline_Dumbbell_Bench_With_Palms_Facing_In": "손바닥 마주보기 인클라인 덤벨 벤치프레스",
  "Incline_Dumbbell_Curl": "인클라인 덤벨 컬",
  "Incline_Dumbbell_Flyes": "인클라인 덤벨 플라이",
  "Incline_Dumbbell_Flyes_-_With_A_Twist": "트위스트 인클라인 덤벨 플라이",
  "Incline_Dumbbell_Press": "인클라인 덤벨 프레스",
  "Incline_Hammer_Curls": "인클라인 해머 컬",
  "Incline_Inner_Biceps_Curl": "인클라인 내측 이두근 컬",
  "Incline_Push-Up": "인클라인 푸시업",
  "Incline_Push-Up_Close-Grip": "클로즈 그립 인클라인 푸시업",
  "Incline_Push-Up_Depth_Jump": "발 올린 뎁스 점프 푸시업",
  "Incline_Push-Up_Medium": "미디엄 그립 인클라인 푸시업",
  "Incline_Push-Up_Reverse_Grip": "리버스 그립 인클라인 푸시업",
  "Incline_Push-Up_Wide": "와이드 그립 인클라인 푸시업",
  "Intermediate_Groin_Stretch": "중급 사타구니 스트레칭",
  "Intermediate_Hip_Flexor_and_Quad_Stretch": "중급 고관절 굴곡근·대퇴사두근 스트레칭",
  "Internal_Rotation_with_Band": "밴드 어깨 내회전",
  "Inverted_Row": "인버티드 로우",
  "Inverted_Row_with_Straps": "스트랩 인버티드 로우",
  "Iron_Cross": "덤벨 아이언 크로스",
  "Iron_Crosses_stretch": "아이언 크로스 스트레칭",
  "Isometric_Chest_Squeezes": "등척성 가슴 조이기",
  "Isometric_Neck_Exercise_-_Front_And_Back": "등척성 목 앞뒤 운동",
  "Isometric_Neck_Exercise_-_Sides": "등척성 목 좌우 운동",
  "Isometric_Wipers": "좌우 이동 와이퍼 푸시업",
  "JM_Press": "제이엠 프레스",
  "Jackknife_Sit-Up": "잭나이프 싯업",
  "Janda_Sit-Up": "얀다 싯업",
  "Jefferson_Squats": "제퍼슨 스쿼트",
  "Jerk_Balance": "저크 밸런스",
  "Jerk_Dip_Squat": "저크 딥 스쿼트",
  "Jogging_Treadmill": "트레드밀 조깅",
  "Keg_Load": "케그 운반·플랫폼 적재",
  "Kettlebell_Arnold_Press": "케틀벨 아놀드 프레스",
  "Kettlebell_Dead_Clean": "케틀벨 데드 클린",
  "Kettlebell_Figure_8": "케틀벨 피겨 에이트",
  "Kettlebell_Halo": "케틀벨 헤일로",
  "Kettlebell_Halo_With_Overhead_Extension": "오버헤드 익스텐션 케틀벨 헤일로",
  "Kettlebell_Hang_Clean": "케틀벨 행 클린",
  "Kettlebell_One-Legged_Deadlift": "원 레그 케틀벨 데드리프트",
  "Kettlebell_Overhead_Triceps_Extension": "케틀벨 오버헤드 트라이셉스 익스텐션",
  "Kettlebell_Pass_Between_The_Legs": "다리 사이 케틀벨 패스",
  "Kettlebell_Pirate_Ships": "케틀벨 파이럿 십 스윙",
  "Kettlebell_Pistol_Squat": "케틀벨 피스톨 스쿼트",
  "Kettlebell_Seated_Press": "시티드 케틀벨 프레스",
  "Kettlebell_Seesaw_Press": "케틀벨 시소 프레스",
  "Kettlebell_Sumo_High_Pull": "케틀벨 스모 하이 풀",
  "Kettlebell_Thruster": "케틀벨 스러스터",
  "Kettlebell_Turkish_Get-Up_Lunge_style": "런지형 케틀벨 터키시 겟업",
  "Kettlebell_Turkish_Get-Up_Squat_style": "스쿼트형 케틀벨 터키시 겟업",
  "Kettlebell_Windmill": "케틀벨 윈드밀",
  "Kipping_Muscle_Up": "키핑 머슬업",
  "Knee_Across_The_Body": "무릎 몸통 가로지르기 스트레칭",
  "Knee_Circles": "니 서클",
  "Knee_Hip_Raise_On_Parallel_Bars": "평행봉 니·힙 레이즈",
  "Knee_Tuck_Jump": "니 턱 점프",
  "Kneeling_Arm_Drill": "무릎 꿇고 팔 동작 드릴",
  "Kneeling_Cable_Crunch_With_Alternating_Oblique_Twists": "교차 오블리크 트위스트 닐링 케이블 크런치",
  "Kneeling_Cable_Triceps_Extension": "닐링 케이블 트라이셉스 익스텐션",
  "Kneeling_Forearm_Stretch": "닐링 전완근 스트레칭",
  "Kneeling_High_Pulley_Row": "닐링 하이 풀리 로우",
  "Kneeling_Hip_Flexor": "닐링 고관절 굴곡근 스트레칭",
  "Kneeling_Jump_Squat": "닐링 점프 스쿼트",
  "Kneeling_Single-Arm_High_Pulley_Row": "원 암 닐링 하이 풀리 로우",
  "Kneeling_Squat": "닐링 스쿼트",
  "Landmine_180s": "랜드마인 180도 회전",
  "Landmine_Linear_Jammer": "랜드마인 리니어 재머",
  "Lateral_Bound": "레터럴 바운드",
  "Lateral_Box_Jump": "레터럴 박스 점프",
  "Lateral_Cone_Hops": "레터럴 콘 홉",
  "Lateral_Raise_-_With_Bands": "밴드 레터럴 레이즈",
  "Latissimus_Dorsi-SMR": "광배근 자가 근막 이완",
  "Leg-Over_Floor_Press": "다리 교차 케틀벨 플로어 프레스",
  "Leg-Up_Hamstring_Stretch": "다리 올린 햄스트링 스트레칭",
  "Leg_Extensions": "레그 익스텐션",
  "Leg_Lift": "스탠딩 리어 레그 리프트",
  "Leg_Press": "레그 프레스",
  "Leg_Pull-In": "레그 풀인",
  "Leverage_Chest_Press": "레버리지 체스트 프레스",
  "Leverage_Deadlift": "레버리지 데드리프트",
  "Leverage_Decline_Chest_Press": "레버리지 디클라인 체스트 프레스",
  "Leverage_High_Row": "레버리지 하이 로우",
  "Leverage_Incline_Chest_Press": "레버리지 인클라인 체스트 프레스",
  "Leverage_Iso_Row": "레버리지 아이소 로우",
  "Leverage_Shoulder_Press": "레버리지 숄더 프레스",
  "Leverage_Shrug": "레버리지 슈러그",
  "Linear_3-Part_Start_Technique": "직선 3단계 스타트 드릴",
  "Linear_Acceleration_Wall_Drill": "벽 짚고 직선 가속 드릴",
  "Linear_Depth_Jump": "리니어 뎁스 점프",
  "Log_Lift": "로그 리프트",
  "London_Bridges": "로프 런던 브리지",
  "Looking_At_Ceiling": "천장 보기 대퇴사두근 스트레칭",
  "Low_Cable_Crossover": "로우 케이블 크로스오버",
  "Low_Cable_Triceps_Extension": "로우 케이블 트라이셉스 익스텐션",
  "Low_Pulley_Row_To_Neck": "로우 풀리 넥 로우",
  "Lower_Back-SMR": "허리 자가 근막 이완",
  "Lower_Back_Curl": "엎드린 백 익스텐션",
  "Lunge_Pass_Through": "케틀벨 패스스루 런지",
  "Lunge_Sprint": "스미스머신 런지 스프린트",
  "Lying_Bent_Leg_Groin": "누워서 무릎 굽힌 사타구니 스트레칭",
  "Lying_Cable_Curl": "라잉 케이블 컬",
  "Lying_Cambered_Barbell_Row": "라잉 캠버드 바벨 로우",
  "Lying_Close-Grip_Bar_Curl_On_High_Pulley": "하이 풀리 라잉 클로즈 그립 바 컬",
  "Lying_Close-Grip_Barbell_Triceps_Extension_Behind_The_Head": "머리 뒤 라잉 클로즈 그립 바벨 트라이셉스 익스텐션",
  "Lying_Close-Grip_Barbell_Triceps_Press_To_Chin": "턱 방향 라잉 클로즈 그립 바벨 트라이셉스 프레스",
  "Lying_Crossover": "라잉 크로스오버 스트레칭",
  "Lying_Dumbbell_Tricep_Extension": "라잉 덤벨 트라이셉스 익스텐션",
  "Lying_Face_Down_Plate_Neck_Resistance": "엎드린 플레이트 목 저항 운동",
  "Lying_Face_Up_Plate_Neck_Resistance": "바로 누운 플레이트 목 저항 운동",
  "Lying_Glute": "라잉 둔근 파트너 스트레칭",
  "Lying_Hamstring": "라잉 햄스트링 파트너 스트레칭",
  "Lying_High_Bench_Barbell_Curl": "라잉 하이 벤치 바벨 컬",
  "Lying_Leg_Curls": "라잉 레그 컬",
  "Lying_Machine_Squat": "라잉 머신 스쿼트",
  "Lying_One-Arm_Lateral_Raise": "라잉 원 암 레터럴 레이즈",
  "Lying_Prone_Quadriceps": "엎드린 대퇴사두근 파트너 스트레칭",
  "Lying_Rear_Delt_Raise": "라잉 리어 델트 레이즈",
  "Lying_Supine_Dumbbell_Curl": "바로 누운 덤벨 컬",
  "Lying_T-Bar_Row": "라잉 티바 로우",
  "Lying_Triceps_Press": "라잉 트라이셉스 프레스",
  "Machine_Bench_Press": "머신 벤치프레스",
  "Machine_Bicep_Curl": "머신 바이셉스 컬",
  "Machine_Preacher_Curls": "머신 프리처 컬",
  "Machine_Shoulder_Military_Press": "머신 밀리터리 숄더 프레스",
  "Machine_Triceps_Extension": "머신 트라이셉스 익스텐션",
  "Medicine_Ball_Chest_Pass": "메디신볼 체스트 패스",
  "Medicine_Ball_Full_Twist": "메디신볼 풀 트위스트",
  "Medicine_Ball_Scoop_Throw": "메디신볼 스쿱 스로",
  "Middle_Back_Shrug": "인클라인 벤치 미들 백 슈러그",
  "Middle_Back_Stretch": "등 중앙부 스트레칭",
  "Mixed_Grip_Chin": "믹스 그립 친업",
  "Monster_Walk": "몬스터 워크",
  "Mountain_Climbers": "마운틴 클라이머",
  "Moving_Claw_Series": "무빙 클로 러닝 드릴",
  "Muscle_Snatch": "머슬 스내치",
  "Muscle_Up": "머슬업",
  "Narrow_Stance_Hack_Squats": "내로우 스탠스 핵 스쿼트",
  "Narrow_Stance_Leg_Press": "내로우 스탠스 레그 프레스",
  "Narrow_Stance_Squats": "내로우 스탠스 스쿼트",
  "Natural_Glute_Ham_Raise": "내추럴 글루트 햄 레이즈",
  "Neck-SMR": "목 자가 근막 이완",
  "Neck_Press": "바벨 넥 프레스",
  "Oblique_Crunches": "오블리크 크런치",
  "Oblique_Crunches_-_On_The_Floor": "바닥 오블리크 크런치",
  "Olympic_Squat": "올림픽 스쿼트",
  "On-Your-Back_Quad_Stretch": "바로 누운 대퇴사두근 스트레칭",
  "On_Your_Side_Quad_Stretch": "옆으로 누운 대퇴사두근 스트레칭",
  "One-Arm_Dumbbell_Row": "원 암 덤벨 로우",
  "One-Arm_Flat_Bench_Dumbbell_Flye": "원 암 플랫 벤치 덤벨 플라이",
  "One-Arm_High-Pulley_Cable_Side_Bends": "원 암 하이 풀리 케이블 사이드 벤드",
  "One-Arm_Incline_Lateral_Raise": "원 암 인클라인 레터럴 레이즈",
  "One-Arm_Kettlebell_Clean": "원 암 케틀벨 클린",
  "One-Arm_Kettlebell_Clean_and_Jerk": "원 암 케틀벨 클린 앤 저크",
  "One-Arm_Kettlebell_Floor_Press": "원 암 케틀벨 플로어 프레스",
  "One-Arm_Kettlebell_Jerk": "원 암 케틀벨 저크",
  "One-Arm_Kettlebell_Military_Press_To_The_Side": "측면 원 암 케틀벨 밀리터리 프레스",
  "One-Arm_Kettlebell_Para_Press": "원 암 케틀벨 파라 프레스",
  "One-Arm_Kettlebell_Push_Press": "원 암 케틀벨 푸시 프레스",
  "One-Arm_Kettlebell_Row": "원 암 케틀벨 로우",
  "One-Arm_Kettlebell_Snatch": "원 암 케틀벨 스내치",
  "One-Arm_Kettlebell_Split_Jerk": "원 암 케틀벨 스플릿 저크",
  "One-Arm_Kettlebell_Split_Snatch": "원 암 케틀벨 스플릿 스내치",
  "One-Arm_Kettlebell_Swings": "원 암 케틀벨 스윙",
  "One-Arm_Long_Bar_Row": "원 암 롱바 로우",
  "One-Arm_Medicine_Ball_Slam": "원 암 메디신볼 슬램",
  "One-Arm_Open_Palm_Kettlebell_Clean": "오픈 팜 원 암 케틀벨 클린",
  "One-Arm_Overhead_Kettlebell_Squats": "원 암 오버헤드 케틀벨 스쿼트",
  "One-Arm_Side_Deadlift": "원 암 사이드 데드리프트",
  "One-Arm_Side_Laterals": "원 암 사이드 레터럴 레이즈",
  "One-Legged_Cable_Kickback": "싱글 레그 케이블 킥백",
  "One_Arm_Against_Wall": "벽 짚고 원 암 광배근 스트레칭",
  "One_Arm_Chin-Up": "원 암 친업",
  "One_Arm_Dumbbell_Bench_Press": "원 암 덤벨 벤치프레스",
  "One_Arm_Dumbbell_Preacher_Curl": "원 암 덤벨 프리처 컬",
  "One_Arm_Floor_Press": "원 암 바벨 플로어 프레스",
  "One_Arm_Lat_Pulldown": "원 암 랫 풀다운",
  "One_Arm_Pronated_Dumbbell_Triceps_Extension": "원 암 오버핸드 덤벨 트라이셉스 익스텐션",
  "One_Arm_Supinated_Dumbbell_Triceps_Extension": "원 암 언더핸드 덤벨 트라이셉스 익스텐션",
  "One_Half_Locust": "하프 로커스트 자세",
  "One_Handed_Hang": "원 핸드 행",
  "One_Knee_To_Chest": "한쪽 무릎 가슴 당기기",
  "One_Leg_Barbell_Squat": "싱글 레그 바벨 스쿼트",
  "Open_Palm_Kettlebell_Clean": "오픈 팜 케틀벨 클린",
  "Otis-Up": "오티스 업",
  "Overhead_Cable_Curl": "오버헤드 케이블 컬",
  "Overhead_Lat": "파트너 오버헤드 광배근 수축·이완 스트레칭",
  "Overhead_Slam": "메디신볼 오버헤드 슬램",
  "Overhead_Squat": "오버헤드 스쿼트",
  "Overhead_Stretch": "오버헤드 스트레칭",
  "Overhead_Triceps": "파트너 오버헤드 삼두근 수축·이완 스트레칭",
  "Pallof_Press": "팔로프 프레스",
  "Pallof_Press_With_Rotation": "회전 팔로프 프레스",
  "Palms-Down_Dumbbell_Wrist_Curl_Over_A_Bench": "벤치 위 오버핸드 덤벨 리스트 컬",
  "Palms-Down_Wrist_Curl_Over_A_Bench": "벤치 위 오버핸드 바벨 리스트 컬",
  "Palms-Up_Barbell_Wrist_Curl_Over_A_Bench": "벤치 위 언더핸드 바벨 리스트 컬",
  "Palms-Up_Dumbbell_Wrist_Curl_Over_A_Bench": "벤치 위 언더핸드 덤벨 리스트 컬",
  "Parallel_Bar_Dip": "평행봉 딥",
  "Pelvic_Tilt_Into_Bridge": "골반 기울이기 브리지",
  "Peroneals-SMR": "비골근 자가 근막 이완",
  "Peroneals_Stretch": "비골근 스트레칭",
  "Physioball_Hip_Bridge": "짐볼 힙 브리지",
  "Pin_Presses": "핀 프레스",
  "Piriformis-SMR": "이상근 자가 근막 이완",
  "Plank": "플랭크",
  "Plate_Pinch": "플레이트 핀치 그립",
  "Plate_Twist": "플레이트 트위스트",
  "Platform_Hamstring_Slides": "수건 햄스트링 힐 슬라이드",
  "Plie_Dumbbell_Squat": "플리에 덤벨 스쿼트",
  "Plyo_Kettlebell_Pushups": "플라이오 케틀벨 푸시업",
  "Plyo_Push-up": "플라이오 푸시업",
  "Posterior_Tibialis_Stretch": "후경골근 스트레칭",
  "Power_Clean": "파워 클린",
  "Power_Clean_from_Blocks": "블록 파워 클린",
  "Power_Jerk": "파워 저크",
  "Power_Partials": "파워 파셜 레터럴 레이즈",
  "Power_Snatch": "파워 스내치",
  "Power_Snatch_from_Blocks": "블록 파워 스내치",
  "Power_Stairs": "중량물 계단 올리기",
  "Preacher_Curl": "프리처 컬",
  "Preacher_Hammer_Dumbbell_Curl": "프리처 해머 덤벨 컬",
  "Press_Sit-Up": "프레스 싯업",
  "Prone_Manual_Hamstring": "엎드린 햄스트링 파트너 저항 운동",
  "Prowler_Sprint": "프로울러 스프린트",
  "Pull_Through": "케이블 풀스루",
  "Pullups": "풀업",
  "Push-Up_Wide": "와이드 푸시업",
  "Push-Ups_-_Close_Triceps_Position": "클로즈 그립 트라이셉스 푸시업",
  "Push-Ups_With_Feet_Elevated": "발 올린 푸시업",
  "Push-Ups_With_Feet_On_An_Exercise_Ball": "짐볼에 발 올린 푸시업",
  "Push_Press": "푸시 프레스",
  "Push_Press_-_Behind_the_Neck": "비하인드 넥 푸시 프레스",
  "Push_Up_to_Side_Plank": "푸시업 투 사이드 플랭크",
  "Pushups": "기본 푸시업",
  "Pushups_Close_and_Wide_Hand_Positions": "클로즈·와이드 교대 푸시업",
  "Pyramid": "짐볼 피라미드",
  "Quad_Stretch": "대퇴사두근 스트레칭",
  "Quadriceps-SMR": "대퇴사두근 자가 근막 이완",
  "Quick_Leap": "퀵 리프 박스 점프",
  "Rack_Delivery": "랙 딜리버리 드릴",
  "Rack_Pull_with_Bands": "밴드 랙 풀",
  "Rack_Pulls": "랙 풀",
  "Rear_Leg_Raises": "네발 기기 리어 레그 레이즈",
  "Recumbent_Bike": "리컴번트 바이크",
  "Return_Push_from_Stance": "스탠스 메디신볼 리턴 푸시",
  "Reverse_Band_Bench_Press": "리버스 밴드 벤치프레스",
  "Reverse_Band_Box_Squat": "리버스 밴드 박스 스쿼트"
}

    $part_b$::jsonb ||
    $part_c$
{
  "Reverse_Band_Deadlift": "리버스 밴드 데드리프트",
  "Reverse_Band_Power_Squat": "리버스 밴드 파워 스쿼트",
  "Reverse_Band_Sumo_Deadlift": "리버스 밴드 스모 데드리프트",
  "Reverse_Barbell_Curl": "리버스 바벨 컬",
  "Reverse_Barbell_Preacher_Curls": "리버스 그립 이지바 프리처 컬",
  "Reverse_Cable_Curl": "리버스 케이블 컬",
  "Reverse_Crunch": "리버스 크런치",
  "Reverse_Flyes": "덤벨 리버스 플라이",
  "Reverse_Flyes_With_External_Rotation": "외회전 덤벨 리버스 플라이",
  "Reverse_Grip_Bent-Over_Rows": "언더핸드 바벨 벤트오버 로우",
  "Reverse_Grip_Triceps_Pushdown": "언더핸드 케이블 트라이셉스 푸시다운",
  "Reverse_Hyperextension": "머신 리버스 하이퍼익스텐션",
  "Reverse_Machine_Flyes": "머신 리버스 플라이",
  "Reverse_Plate_Curls": "플레이트 리버스 컬",
  "Reverse_Triceps_Bench_Press": "리버스 그립 트라이셉스 벤치프레스",
  "Rhomboids-SMR": "능형근 폼롤러 근막 이완",
  "Rickshaw_Carry": "릭쇼 캐리",
  "Rickshaw_Deadlift": "릭쇼 데드리프트",
  "Ring_Dips": "링 딥스",
  "Rocket_Jump": "로켓 점프",
  "Rocking_Standing_Calf_Raise": "록킹 스탠딩 카프 레이즈",
  "Rocky_Pull-Ups_Pulldowns": "로키 프런트·비하인드 넥 풀업",
  "Romanian_Deadlift": "바벨 루마니안 데드리프트",
  "Romanian_Deadlift_from_Deficit": "디피싯 바벨 루마니안 데드리프트",
  "Rope_Climb": "로프 클라임",
  "Rope_Crunch": "케이블 로프 크런치",
  "Rope_Jumping": "줄넘기",
  "Rope_Straight-Arm_Pulldown": "케이블 로프 스트레이트암 풀다운",
  "Round_The_World_Shoulder_Stretch": "라운드 더 월드 어깨 스트레칭",
  "Rowing_Stationary": "실내 로잉 머신",
  "Runners_Stretch": "러너 햄스트링 스트레칭",
  "Running_Treadmill": "트레드밀 달리기",
  "Russian_Twist": "러시안 트위스트",
  "Sandbag_Load": "샌드백 로딩",
  "Scapular_Pull-Up": "스캐풀러 풀업",
  "Scissor_Kick": "시저 킥",
  "Scissors_Jump": "시저스 점프",
  "Seated_Band_Hamstring_Curl": "시티드 밴드 레그 컬",
  "Seated_Barbell_Military_Press": "시티드 바벨 밀리터리 프레스",
  "Seated_Barbell_Twist": "시티드 바벨 트위스트",
  "Seated_Bent-Over_One-Arm_Dumbbell_Triceps_Extension": "시티드 벤트오버 원암 덤벨 트라이셉스 익스텐션",
  "Seated_Bent-Over_Rear_Delt_Raise": "시티드 벤트오버 덤벨 리어 델트 레이즈",
  "Seated_Bent-Over_Two-Arm_Dumbbell_Triceps_Extension": "시티드 벤트오버 투암 덤벨 트라이셉스 익스텐션",
  "Seated_Biceps": "앉아서 파트너 이두근 스트레칭",
  "Seated_Cable_Rows": "시티드 케이블 로우",
  "Seated_Cable_Shoulder_Press": "시티드 케이블 숄더 프레스",
  "Seated_Calf_Raise": "머신 시티드 카프 레이즈",
  "Seated_Calf_Stretch": "시티드 종아리 스트레칭",
  "Seated_Close-Grip_Concentration_Barbell_Curl": "시티드 클로즈그립 컨센트레이션 바벨 컬",
  "Seated_Dumbbell_Curl": "시티드 덤벨 컬",
  "Seated_Dumbbell_Inner_Biceps_Curl": "시티드 덤벨 이너 바이셉스 컬",
  "Seated_Dumbbell_Palms-Down_Wrist_Curl": "시티드 덤벨 오버핸드 리스트 컬",
  "Seated_Dumbbell_Palms-Up_Wrist_Curl": "시티드 덤벨 언더핸드 리스트 컬",
  "Seated_Dumbbell_Press": "시티드 덤벨 숄더 프레스",
  "Seated_Flat_Bench_Leg_Pull-In": "플랫 벤치 시티드 니 턱",
  "Seated_Floor_Hamstring_Stretch": "바닥에 앉아 햄스트링 스트레칭",
  "Seated_Front_Deltoid": "앉아서 파트너 전면 삼각근 스트레칭",
  "Seated_Glute": "앉아서 파트너 둔근 스트레칭",
  "Seated_Good_Mornings": "시티드 바벨 굿모닝",
  "Seated_Hamstring": "앉아서 파트너 햄스트링 스트레칭",
  "Seated_Hamstring_and_Calf_Stretch": "시티드 햄스트링·종아리 스트레칭",
  "Seated_Head_Harness_Neck_Resistance": "시티드 헤드 하네스 목 저항 운동",
  "Seated_Leg_Curl": "머신 시티드 레그 컬",
  "Seated_Leg_Tucks": "시티드 레그 턱",
  "Seated_One-Arm_Dumbbell_Palms-Down_Wrist_Curl": "시티드 원암 덤벨 오버핸드 리스트 컬",
  "Seated_One-Arm_Dumbbell_Palms-Up_Wrist_Curl": "시티드 원암 덤벨 언더핸드 리스트 컬",
  "Seated_One-arm_Cable_Pulley_Rows": "시티드 원암 케이블 로우",
  "Seated_Overhead_Stretch": "시티드 오버헤드 옆구리 스트레칭",
  "Seated_Palm-Up_Barbell_Wrist_Curl": "시티드 바벨 언더핸드 리스트 컬",
  "Seated_Palms-Down_Barbell_Wrist_Curl": "시티드 바벨 오버핸드 리스트 컬",
  "Seated_Side_Lateral_Raise": "시티드 덤벨 레터럴 레이즈",
  "Seated_Triceps_Press": "시티드 덤벨 오버헤드 트라이셉스 익스텐션",
  "Seated_Two-Arm_Palms-Up_Low-Pulley_Wrist_Curl": "시티드 투암 로우 풀리 언더핸드 리스트 컬",
  "See-Saw_Press_Alternating_Side_Press": "얼터네이팅 시소 덤벨 프레스",
  "Shotgun_Row": "샷건 원암 케이블 로우",
  "Shoulder_Circles": "어깨 돌리기",
  "Shoulder_Press_-_With_Bands": "밴드 숄더 프레스",
  "Shoulder_Raise": "맨몸 숄더 슈러그",
  "Shoulder_Stretch": "어깨 스트레칭",
  "Side-Lying_Floor_Stretch": "옆으로 누워 광배근 스트레칭",
  "Side_Bridge": "사이드 브리지",
  "Side_Hop-Sprint": "사이드 홉 스프린트",
  "Side_Jackknife": "사이드 잭나이프",
  "Side_Lateral_Raise": "덤벨 사이드 레터럴 레이즈",
  "Side_Laterals_to_Front_Raise": "덤벨 레터럴 투 프런트 레이즈",
  "Side_Leg_Raises": "스탠딩 사이드 레그 레이즈",
  "Side_Lying_Groin_Stretch": "옆으로 누워 내전근 스트레칭",
  "Side_Neck_Stretch": "목 옆면 스트레칭",
  "Side_Standing_Long_Jump": "옆 방향 제자리 멀리뛰기",
  "Side_To_Side_Chins": "사이드 투 사이드 친업",
  "Side_Wrist_Pull": "손목 당겨 등 옆면 스트레칭",
  "Side_to_Side_Box_Shuffle": "박스 사이드 셔플",
  "Single-Arm_Cable_Crossover": "싱글암 케이블 크로스오버",
  "Single-Arm_Linear_Jammer": "싱글암 랜드마인 리니어 재머",
  "Single-Arm_Push-Up": "원암 푸시업",
  "Single-Cone_Sprint_Drill": "싱글 콘 스프린트 드릴",
  "Single-Leg_High_Box_Squat": "싱글 레그 하이 박스 스쿼트",
  "Single-Leg_Hop_Progression": "싱글 레그 홉 단계 훈련",
  "Single-Leg_Lateral_Hop": "싱글 레그 사이드 홉",
  "Single-Leg_Leg_Extension": "머신 싱글 레그 익스텐션",
  "Single-Leg_Stride_Jump": "싱글 레그 스트라이드 점프",
  "Single_Dumbbell_Raise": "투핸드 싱글 덤벨 프런트 레이즈",
  "Single_Leg_Butt_Kick": "싱글 레그 버트 킥",
  "Single_Leg_Glute_Bridge": "싱글 레그 글루트 브리지",
  "Single_Leg_Push-off": "박스 싱글 레그 푸시오프",
  "Sit-Up": "싯업",
  "Sit_Squats": "싯 스쿼트",
  "Skating": "롤러스케이팅",
  "Sled_Drag_-_Harness": "하네스 썰매 끌기",
  "Sled_Overhead_Backward_Walk": "오버헤드 썰매 뒤로 걷기",
  "Sled_Overhead_Triceps_Extension": "썰매 오버헤드 트라이셉스 익스텐션",
  "Sled_Push": "썰매 밀기",
  "Sled_Reverse_Flye": "썰매 리버스 플라이",
  "Sled_Row": "썰매 로우",
  "Sledgehammer_Swings": "슬레지해머 스윙",
  "Smith_Incline_Shoulder_Raise": "스미스 인클라인 숄더 레이즈",
  "Smith_Machine_Behind_the_Back_Shrug": "스미스 머신 비하인드 백 슈러그",
  "Smith_Machine_Bench_Press": "스미스 머신 벤치프레스",
  "Smith_Machine_Bent_Over_Row": "스미스 머신 벤트오버 로우",
  "Smith_Machine_Calf_Raise": "스미스 머신 카프 레이즈",
  "Smith_Machine_Close-Grip_Bench_Press": "스미스 머신 클로즈그립 벤치프레스",
  "Smith_Machine_Decline_Press": "스미스 머신 디클라인 벤치프레스",
  "Smith_Machine_Hang_Power_Clean": "스미스 머신 행 파워 클린",
  "Smith_Machine_Hip_Raise": "스미스 머신 힙 레이즈",
  "Smith_Machine_Incline_Bench_Press": "스미스 머신 인클라인 벤치프레스",
  "Smith_Machine_Leg_Press": "스미스 머신 수직 레그프레스",
  "Smith_Machine_One-Arm_Upright_Row": "스미스 머신 원암 업라이트 로우",
  "Smith_Machine_Overhead_Shoulder_Press": "스미스 머신 오버헤드 숄더 프레스",
  "Smith_Machine_Pistol_Squat": "스미스 머신 피스톨 스쿼트",
  "Smith_Machine_Reverse_Calf_Raises": "스미스 머신 리버스 카프 레이즈",
  "Smith_Machine_Squat": "스미스 머신 스쿼트",
  "Smith_Machine_Stiff-Legged_Deadlift": "스미스 머신 스티프 레그 데드리프트",
  "Smith_Machine_Upright_Row": "스미스 머신 업라이트 로우",
  "Smith_Single-Leg_Split_Squat": "스미스 머신 싱글 레그 스플릿 스쿼트",
  "Snatch": "바벨 스내치",
  "Snatch_Balance": "바벨 스내치 밸런스",
  "Snatch_Deadlift": "바벨 스내치 데드리프트",
  "Snatch_Pull": "바벨 스내치 풀",
  "Snatch_Shrug": "바벨 스내치 슈러그",
  "Snatch_from_Blocks": "블록 바벨 스내치",
  "Speed_Band_Overhead_Triceps": "스피드 밴드 오버헤드 트라이셉스 익스텐션",
  "Speed_Box_Squat": "밴드 저항 스피드 박스 스쿼트",
  "Speed_Squats": "스피드 바벨 스쿼트",
  "Spell_Caster": "덤벨 좌우 회전 스윙",
  "Spider_Crawl": "스파이더 크롤",
  "Spider_Curl": "이지바 스파이더 컬",
  "Spinal_Stretch": "척추 스트레칭",
  "Split_Clean": "바벨 스플릿 클린",
  "Split_Jerk": "바벨 스플릿 저크",
  "Split_Jump": "스플릿 점프",
  "Split_Snatch": "바벨 스플릿 스내치",
  "Split_Squat_with_Dumbbells": "덤벨 스플릿 스쿼트",
  "Split_Squats": "점핑 얼터네이팅 스플릿 스쿼트",
  "Squat_Jerk": "바벨 스쿼트 저크",
  "Squat_with_Bands": "밴드 저항 바벨 스쿼트",
  "Squat_with_Chains": "체인 바벨 스쿼트",
  "Squat_with_Plate_Movers": "플레이트 옮기기 바벨 스쿼트",
  "Squats_-_With_Bands": "밴드 스쿼트",
  "Stairmaster": "계단 오르기 머신",
  "Standing_Alternating_Dumbbell_Press": "스탠딩 얼터네이팅 덤벨 숄더 프레스",
  "Standing_Barbell_Calf_Raise": "스탠딩 바벨 카프 레이즈",
  "Standing_Barbell_Press_Behind_Neck": "스탠딩 비하인드 넥 바벨 프레스",
  "Standing_Bent-Over_One-Arm_Dumbbell_Triceps_Extension": "스탠딩 벤트오버 원암 덤벨 트라이셉스 익스텐션",
  "Standing_Bent-Over_Two-Arm_Dumbbell_Triceps_Extension": "스탠딩 벤트오버 투암 덤벨 트라이셉스 익스텐션",
  "Standing_Biceps_Cable_Curl": "스탠딩 케이블 바이셉스 컬",
  "Standing_Biceps_Stretch": "스탠딩 이두근 스트레칭",
  "Standing_Bradford_Press": "스탠딩 브래드퍼드 바벨 프레스",
  "Standing_Cable_Chest_Press": "스탠딩 케이블 체스트 프레스",
  "Standing_Cable_Lift": "스탠딩 로우 투 하이 케이블 리프트",
  "Standing_Cable_Wood_Chop": "스탠딩 케이블 우드촙",
  "Standing_Calf_Raises": "머신 스탠딩 카프 레이즈",
  "Standing_Concentration_Curl": "스탠딩 컨센트레이션 덤벨 컬",
  "Standing_Dumbbell_Calf_Raise": "스탠딩 덤벨 카프 레이즈",
  "Standing_Dumbbell_Press": "스탠딩 덤벨 숄더 프레스",
  "Standing_Dumbbell_Reverse_Curl": "스탠딩 덤벨 리버스 컬",
  "Standing_Dumbbell_Straight-Arm_Front_Delt_Raise_Above_Head": "스탠딩 덤벨 스트레이트암 오버헤드 프런트 레이즈",
  "Standing_Dumbbell_Triceps_Extension": "스탠딩 덤벨 오버헤드 트라이셉스 익스텐션",
  "Standing_Dumbbell_Upright_Row": "스탠딩 덤벨 업라이트 로우",
  "Standing_Elevated_Quad_Stretch": "스탠딩 발 올린 대퇴사두근 스트레칭",
  "Standing_Front_Barbell_Raise_Over_Head": "스탠딩 바벨 오버헤드 프런트 레이즈",
  "Standing_Gastrocnemius_Calf_Stretch": "스탠딩 비복근 스트레칭",
  "Standing_Hamstring_and_Calf_Stretch": "스탠딩 햄스트링·종아리 스트레칭",
  "Standing_Hip_Circles": "스탠딩 힙 서클",
  "Standing_Hip_Flexors": "스탠딩 고관절 굴곡근 스트레칭",
  "Standing_Inner-Biceps_Curl": "스탠딩 덤벨 이너 바이셉스 컬",
  "Standing_Lateral_Stretch": "스탠딩 옆구리 스트레칭",
  "Standing_Leg_Curl": "머신 스탠딩 레그 컬",
  "Standing_Long_Jump": "제자리 멀리뛰기",
  "Standing_Low-Pulley_Deltoid_Raise": "스탠딩 로우 풀리 원암 델토이드 레이즈",
  "Standing_Low-Pulley_One-Arm_Triceps_Extension": "스탠딩 로우 풀리 원암 오버헤드 트라이셉스 익스텐션",
  "Standing_Military_Press": "스탠딩 바벨 밀리터리 프레스",
  "Standing_Olympic_Plate_Hand_Squeeze": "스탠딩 올림픽 플레이트 손가락 쥐기",
  "Standing_One-Arm_Cable_Curl": "스탠딩 원암 케이블 컬",
  "Standing_One-Arm_Dumbbell_Curl_Over_Incline_Bench": "인클라인 벤치 스탠딩 원암 덤벨 컬",
  "Standing_One-Arm_Dumbbell_Triceps_Extension": "스탠딩 원암 덤벨 트라이셉스 익스텐션",
  "Standing_Overhead_Barbell_Triceps_Extension": "스탠딩 오버헤드 바벨 트라이셉스 익스텐션",
  "Standing_Palm-In_One-Arm_Dumbbell_Press": "스탠딩 뉴트럴 그립 원암 덤벨 프레스",
  "Standing_Palms-In_Dumbbell_Press": "스탠딩 뉴트럴 그립 덤벨 프레스",
  "Standing_Palms-Up_Barbell_Behind_The_Back_Wrist_Curl": "스탠딩 비하인드 백 바벨 언더핸드 리스트 컬",
  "Standing_Pelvic_Tilt": "스탠딩 골반 기울이기",
  "Standing_Rope_Crunch": "스탠딩 케이블 로프 크런치",
  "Standing_Soleus_And_Achilles_Stretch": "스탠딩 가자미근·아킬레스건 스트레칭",
  "Standing_Toe_Touches": "스탠딩 토 터치",
  "Standing_Towel_Triceps_Extension": "스탠딩 타월 트라이셉스 익스텐션",
  "Standing_Two-Arm_Overhead_Throw": "스탠딩 메디신볼 투암 오버헤드 스로",
  "Star_Jump": "스타 점프",
  "Step-up_with_Knee_Raise": "니 레이즈 스텝업",
  "Step_Mill": "스텝밀",
  "Stiff-Legged_Barbell_Deadlift": "바벨 스티프 레그 데드리프트",
  "Stiff-Legged_Dumbbell_Deadlift": "덤벨 스티프 레그 데드리프트",
  "Stiff_Leg_Barbell_Good_Morning": "바벨 스티프 레그 굿모닝",
  "Stomach_Vacuum": "복부 배큠",
  "Straight-Arm_Dumbbell_Pullover": "덤벨 스트레이트암 풀오버",
  "Straight-Arm_Pulldown": "케이블 스트레이트암 풀다운",
  "Straight_Bar_Bench_Mid_Rows": "벤치 스탠딩 바벨 미드 로우",
  "Straight_Raises_on_Incline_Bench": "인클라인 벤치 엎드린 스트레이트암 바벨 레이즈",
  "Stride_Jump_Crossover": "박스 스트라이드 점프 크로스오버",
  "Sumo_Deadlift": "바벨 스모 데드리프트",
  "Sumo_Deadlift_with_Bands": "밴드 저항 바벨 스모 데드리프트",
  "Sumo_Deadlift_with_Chains": "체인 바벨 스모 데드리프트",
  "Superman": "슈퍼맨",
  "Supine_Chest_Throw": "누워서 메디신볼 체스트 스로",
  "Supine_One-Arm_Overhead_Throw": "누워서 원암 메디신볼 오버헤드 스로",
  "Supine_Two-Arm_Overhead_Throw": "누워서 투암 메디신볼 오버헤드 스로",
  "Suspended_Fallout": "서스펜션 폴아웃",
  "Suspended_Push-Up": "서스펜션 푸시업",
  "Suspended_Reverse_Crunch": "서스펜션 리버스 크런치",
  "Suspended_Row": "서스펜션 로우",
  "Suspended_Split_Squat": "서스펜션 스플릿 스쿼트",
  "Svend_Press": "플레이트 스벤드 프레스",
  "T-Bar_Row_with_Handle": "핸들 티바 로우",
  "Tate_Press": "덤벨 테이트 프레스",
  "The_Straddle": "시티드 스트래들 햄스트링 스트레칭",
  "Thigh_Abductor": "머신 힙 어브덕션",
  "Thigh_Adductor": "머신 힙 어덕션",
  "Tire_Flip": "타이어 플립",
  "Toe_Touchers": "누워서 토 터처 크런치",
  "Torso_Rotation": "짐볼 토르소 로테이션",
  "Trail_Running_Walking": "트레일 러닝·걷기",
  "Trap_Bar_Deadlift": "트랩바 데드리프트",
  "Tricep_Dumbbell_Kickback": "덤벨 트라이셉스 킥백",
  "Tricep_Side_Stretch": "트라이셉스 사이드 스트레칭",
  "Triceps_Overhead_Extension_with_Rope": "케이블 로프 오버헤드 트라이셉스 익스텐션",
  "Triceps_Pushdown": "케이블 트라이셉스 푸시다운",
  "Triceps_Pushdown_-_Rope_Attachment": "케이블 로프 트라이셉스 푸시다운",
  "Triceps_Pushdown_-_V-Bar_Attachment": "케이블 브이바 트라이셉스 푸시다운",
  "Triceps_Stretch": "트라이셉스 스트레칭",
  "Tuck_Crunch": "턱 크런치",
  "Two-Arm_Dumbbell_Preacher_Curl": "투암 덤벨 프리처 컬",
  "Two-Arm_Kettlebell_Clean": "투암 케틀벨 클린",
  "Two-Arm_Kettlebell_Jerk": "투암 케틀벨 저크",
  "Two-Arm_Kettlebell_Military_Press": "투암 케틀벨 밀리터리 프레스",
  "Two-Arm_Kettlebell_Row": "투암 케틀벨 로우",
  "Underhand_Cable_Pulldowns": "언더핸드 케이블 랫 풀다운",
  "Upper_Back-Leg_Grab": "앉아서 등 상부 끌어안기 스트레칭",
  "Upper_Back_Stretch": "등 상부 스트레칭",
  "Upright_Barbell_Row": "바벨 업라이트 로우",
  "Upright_Cable_Row": "케이블 업라이트 로우",
  "Upright_Row_-_With_Bands": "밴드 업라이트 로우",
  "Upward_Stretch": "팔 위로 뻗기 어깨 스트레칭",
  "V-Bar_Pulldown": "케이블 브이바 랫 풀다운",
  "V-Bar_Pullup": "브이바 뉴트럴 그립 풀업",
  "Vertical_Swing": "투핸드 덤벨 버티컬 스윙",
  "Walking_Treadmill": "트레드밀 걷기",
  "Weighted_Ball_Hyperextension": "플레이트 짐볼 하이퍼익스텐션",
  "Weighted_Ball_Side_Bend": "플레이트 짐볼 사이드 벤드",
  "Weighted_Bench_Dip": "중량 벤치 딥스",
  "Weighted_Crunches": "메디신볼 웨이티드 크런치",
  "Weighted_Jump_Squat": "바벨 웨이티드 점프 스쿼트",
  "Weighted_Pull_Ups": "중량 풀업",
  "Weighted_Sissy_Squat": "플레이트 웨이티드 시시 스쿼트",
  "Weighted_Sit-Ups_-_With_Bands": "밴드 저항 웨이티드 싯업",
  "Weighted_Squat": "딥 벨트 웨이티드 스쿼트",
  "Wide-Grip_Barbell_Bench_Press": "와이드그립 바벨 벤치프레스",
  "Wide-Grip_Decline_Barbell_Bench_Press": "와이드그립 디클라인 바벨 벤치프레스",
  "Wide-Grip_Decline_Barbell_Pullover": "와이드그립 디클라인 바벨 풀오버",
  "Wide-Grip_Lat_Pulldown": "와이드그립 케이블 랫 풀다운",
  "Wide-Grip_Pulldown_Behind_The_Neck": "와이드그립 비하인드 넥 랫 풀다운",
  "Wide-Grip_Rear_Pull-Up": "와이드그립 비하인드 넥 풀업",
  "Wide-Grip_Standing_Barbell_Curl": "스탠딩 와이드그립 바벨 컬",
  "Wide_Stance_Barbell_Squat": "와이드 스탠스 바벨 스쿼트",
  "Wide_Stance_Stiff_Legs": "와이드 스탠스 스티프 레그 바벨 데드리프트",
  "Wind_Sprints": "행잉 얼터네이팅 니 레이즈",
  "Windmills": "누워서 윈드밀 힙 스트레칭",
  "Worlds_Greatest_Stretch": "월드 그레이티스트 스트레칭",
  "Wrist_Circles": "손목 돌리기",
  "Wrist_Roller": "리스트 롤러",
  "Wrist_Rotations_with_Straight_Bar": "스트레이트 바 손목 회전",
  "Yoke_Walk": "요크 워크",
  "Zercher_Squats": "저처 바벨 스쿼트",
  "Zottman_Curl": "덤벨 조트만 컬",
  "Zottman_Preacher_Curl": "덤벨 조트만 프리처 컬"
}

    $part_c$::jsonb;
begin
  if pg_catalog.jsonb_typeof(v_korean_names) is distinct from 'object' then
    raise exception 'Embedded Korean exercise names must be a JSON object';
  end if;

  select pg_catalog.count(*)
  into v_mapping_count
  from pg_catalog.jsonb_object_keys(v_korean_names) as mapping(source_id);

  if v_mapping_count <> 876 then
    raise exception 'Expected 876 embedded Korean exercise names, received %',
      v_mapping_count;
  end if;

  if exists (
    select 1
    from pg_catalog.jsonb_each(v_korean_names) as mapping(source_id, name_value)
    where pg_catalog.jsonb_typeof(mapping.name_value) is distinct from 'string'
  ) then
    raise exception 'Every embedded Korean exercise name must be a JSON string';
  end if;

  if exists (
    select 1
    from pg_catalog.jsonb_each_text(v_korean_names)
      as mapping(source_id, name_ko)
    where nullif(pg_catalog.btrim(mapping.source_id), '') is null
       or nullif(pg_catalog.btrim(mapping.name_ko), '') is null
       or pg_catalog.char_length(pg_catalog.btrim(mapping.name_ko)) > 160
       or mapping.name_ko ~ '[A-Za-z]'
       or mapping.name_ko !~ '[가-힣]'
  ) then
    raise exception 'Embedded Korean exercise names contain an invalid value';
  end if;

  select pg_catalog.count(
    distinct pg_catalog.regexp_replace(
      pg_catalog.lower(pg_catalog.btrim(mapping.name_ko)),
      E'\\s+',
      ' ',
      'g'
    )
  )
  into v_distinct_name_count
  from pg_catalog.jsonb_each_text(v_korean_names)
    as mapping(source_id, name_ko);

  if v_distinct_name_count <> v_mapping_count then
    raise exception 'Embedded Korean exercise names must be unique';
  end if;

  select pg_catalog.count(*)
  into v_active_count
  from public.master_exercises as exercise
  where exercise.source_name = 'free-exercise-db'
    and exercise.is_active;

  if v_active_count = 876 then
    perform public.apply_free_exercise_db_korean_names(
      v_korean_names,
      'a859101d633a01c4a1a920d6a8ce41dabba0705f'
    );
  elsif v_active_count <> 0 then
    raise exception 'Expected 0 or 876 active free-exercise-db rows, received %',
      v_active_count;
  end if;
end;
$migration$;

drop function if exists public.list_master_exercises(text, uuid, integer);

create function public.list_master_exercises(
  p_after_name text default null,
  p_after_id uuid default null,
  p_limit integer default 500
)
returns table (
  id uuid,
  source_id text,
  name text,
  name_ko text,
  name_en text,
  target_muscle text,
  equipment text,
  equipment_key text,
  input_type text,
  aliases text[],
  primary_muscles text[],
  secondary_muscles text[],
  difficulty text,
  category text,
  source_name text
)
language sql
stable
security invoker
set search_path = ''
as $$
  select
    exercise.id,
    exercise.source_id,
    exercise.name,
    exercise.name_ko,
    exercise.name_en,
    exercise.target_muscle,
    exercise.equipment,
    exercise.equipment_key,
    exercise.input_type,
    exercise.aliases,
    exercise.primary_muscles,
    exercise.secondary_muscles,
    exercise.difficulty,
    exercise.category,
    exercise.source_name
  from public.master_exercises as exercise
  where exercise.is_active
    and not exercise.is_custom
    and (
      p_after_name is null or
      p_after_id is null or
      (exercise.name, exercise.id) > (p_after_name, p_after_id)
    )
  order by exercise.name, exercise.id
  limit greatest(1, least(coalesce(p_limit, 500), 500));
$$;

revoke all on function public.list_master_exercises(text, uuid, integer)
  from public;
grant execute on function public.list_master_exercises(text, uuid, integer)
  to anon, authenticated, service_role;

comment on function public.list_master_exercises(text, uuid, integer) is
  'Pages active shared exercises by the stable (name, id) cursor.';
