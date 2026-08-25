import 'package:flutter/material.dart';

import '../models.dart';

/// Curated resistance-training catalog used by routines, search, and the
/// deterministic next-exercise recommender. Keep the first entries stable:
/// starter routines reference their positions for backward compatibility.
const exerciseCatalog = <ExerciseTemplate>[
  ExerciseTemplate(
    id: 'bench',
    name: '바벨 벤치 프레스',
    muscle: '가슴',
    icon: Icons.fitness_center,
  ),
  ExerciseTemplate(
    id: 'incline',
    name: '인클라인 덤벨 프레스',
    muscle: '가슴',
    icon: Icons.sports_gymnastics,
  ),
  ExerciseTemplate(
    id: 'squat',
    name: '스쿼트',
    muscle: '하체',
    icon: Icons.accessibility_new,
  ),
  ExerciseTemplate(
    id: 'legpress',
    name: '레그 프레스',
    muscle: '하체',
    icon: Icons.airline_seat_recline_extra,
  ),
  ExerciseTemplate(
    id: 'latpull',
    name: '렛 풀 다운',
    muscle: '등',
    icon: Icons.vertical_align_bottom,
  ),
  ExerciseTemplate(id: 'row', name: '바벨 로우', muscle: '등', icon: Icons.rowing),
  ExerciseTemplate(
    id: 'ohp',
    name: '오버헤드 프레스',
    muscle: '어깨',
    icon: Icons.upload,
  ),
  ExerciseTemplate(
    id: 'lateral',
    name: '사이드 레터럴 레이즈',
    muscle: '어깨',
    icon: Icons.open_with,
  ),
  ExerciseTemplate(
    id: 'curl',
    name: '덤벨 컬',
    muscle: '팔',
    icon: Icons.fitness_center,
  ),
  ExerciseTemplate(
    id: 'plank',
    name: '플랭크',
    muscle: '복근',
    icon: Icons.timer_outlined,
    measurement: ExerciseMeasurement.duration,
  ),
  ExerciseTemplate(
    id: 'run',
    name: '트레드밀 러닝',
    muscle: '유산소',
    icon: Icons.directions_run,
  ),

  // Chest
  ExerciseTemplate(
    id: 'dumbbell_bench',
    name: '덤벨 벤치 프레스',
    muscle: '가슴',
    icon: Icons.fitness_center,
  ),
  ExerciseTemplate(
    id: 'incline_barbell',
    name: '인클라인 바벨 벤치 프레스',
    muscle: '가슴',
    icon: Icons.fitness_center,
  ),
  ExerciseTemplate(
    id: 'decline_bench',
    name: '디클라인 벤치 프레스',
    muscle: '가슴',
    icon: Icons.fitness_center,
  ),
  ExerciseTemplate(
    id: 'chest_press',
    name: '체스트 프레스 머신',
    muscle: '가슴',
    icon: Icons.sports_gymnastics,
  ),
  ExerciseTemplate(
    id: 'cable_fly',
    name: '케이블 플라이',
    muscle: '가슴',
    icon: Icons.open_with,
  ),
  ExerciseTemplate(
    id: 'pec_deck',
    name: '펙덱 플라이',
    muscle: '가슴',
    icon: Icons.open_with,
  ),
  ExerciseTemplate(
    id: 'pushup',
    name: '푸시업',
    muscle: '가슴',
    icon: Icons.sports_gymnastics,
    measurement: ExerciseMeasurement.repsOnly,
  ),
  ExerciseTemplate(
    id: 'dips',
    name: '딥스',
    muscle: '가슴',
    icon: Icons.sports_gymnastics,
  ),

  // Back
  ExerciseTemplate(
    id: 'pullup',
    name: '풀업',
    muscle: '등',
    icon: Icons.vertical_align_top,
  ),
  ExerciseTemplate(
    id: 'assisted_pullup',
    name: '어시스트 풀업',
    muscle: '등',
    icon: Icons.vertical_align_top,
  ),
  ExerciseTemplate(
    id: 'seated_cable_row',
    name: '시티드 케이블 로우',
    muscle: '등',
    icon: Icons.rowing,
  ),
  ExerciseTemplate(
    id: 'one_arm_dumbbell_row',
    name: '원암 덤벨 로우',
    muscle: '등',
    icon: Icons.rowing,
  ),
  ExerciseTemplate(
    id: 'tbar_row',
    name: '티바 로우',
    muscle: '등',
    icon: Icons.rowing,
  ),
  ExerciseTemplate(
    id: 'chest_supported_row',
    name: '체스트 서포티드 로우',
    muscle: '등',
    icon: Icons.rowing,
  ),
  ExerciseTemplate(
    id: 'straight_arm_pulldown',
    name: '스트레이트 암 풀다운',
    muscle: '등',
    icon: Icons.vertical_align_bottom,
  ),
  ExerciseTemplate(
    id: 'face_pull',
    name: '페이스 풀',
    muscle: '등',
    icon: Icons.open_with,
  ),
  ExerciseTemplate(
    id: 'reverse_fly',
    name: '리버스 덤벨 플라이',
    muscle: '등',
    icon: Icons.open_with,
  ),
  ExerciseTemplate(
    id: 'rack_pull',
    name: '랙 풀',
    muscle: '등',
    icon: Icons.fitness_center,
  ),
  ExerciseTemplate(
    id: 'back_extension',
    name: '백 익스텐션',
    muscle: '등',
    icon: Icons.accessibility_new,
  ),

  // Shoulders
  ExerciseTemplate(
    id: 'dumbbell_shoulder_press',
    name: '덤벨 숄더 프레스',
    muscle: '어깨',
    icon: Icons.upload,
  ),
  ExerciseTemplate(
    id: 'arnold_press',
    name: '아놀드 프레스',
    muscle: '어깨',
    icon: Icons.upload,
  ),
  ExerciseTemplate(
    id: 'front_raise',
    name: '프론트 레이즈',
    muscle: '어깨',
    icon: Icons.trending_up,
  ),
  ExerciseTemplate(
    id: 'rear_delt_raise',
    name: '벤트오버 레터럴 레이즈',
    muscle: '어깨',
    icon: Icons.open_with,
  ),
  ExerciseTemplate(
    id: 'reverse_pec_deck',
    name: '리버스 펙덱 플라이',
    muscle: '어깨',
    icon: Icons.open_with,
  ),
  ExerciseTemplate(
    id: 'upright_row',
    name: '업라이트 로우',
    muscle: '어깨',
    icon: Icons.vertical_align_top,
  ),
  ExerciseTemplate(
    id: 'cable_lateral_raise',
    name: '케이블 레터럴 레이즈',
    muscle: '어깨',
    icon: Icons.open_with,
  ),

  // Lower body
  ExerciseTemplate(
    id: 'deadlift',
    name: '데드리프트',
    muscle: '하체',
    icon: Icons.fitness_center,
  ),
  ExerciseTemplate(
    id: 'romanian_deadlift',
    name: '루마니안 데드리프트',
    muscle: '하체',
    icon: Icons.fitness_center,
  ),
  ExerciseTemplate(
    id: 'hack_squat',
    name: '핵 스쿼트',
    muscle: '하체',
    icon: Icons.accessibility_new,
  ),
  ExerciseTemplate(
    id: 'front_squat',
    name: '프론트 스쿼트',
    muscle: '하체',
    icon: Icons.accessibility_new,
  ),
  ExerciseTemplate(
    id: 'goblet_squat',
    name: '고블릿 스쿼트',
    muscle: '하체',
    icon: Icons.accessibility_new,
  ),
  ExerciseTemplate(
    id: 'bulgarian_split_squat',
    name: '불가리안 스플릿 스쿼트',
    muscle: '하체',
    icon: Icons.accessibility_new,
  ),
  ExerciseTemplate(
    id: 'walking_lunge',
    name: '워킹 런지',
    muscle: '하체',
    icon: Icons.directions_walk,
  ),
  ExerciseTemplate(
    id: 'leg_extension',
    name: '레그 익스텐션',
    muscle: '하체',
    icon: Icons.airline_seat_legroom_extra,
  ),
  ExerciseTemplate(
    id: 'leg_curl',
    name: '라잉 레그 컬',
    muscle: '하체',
    icon: Icons.airline_seat_legroom_reduced,
  ),
  ExerciseTemplate(
    id: 'hip_thrust',
    name: '힙 쓰러스트',
    muscle: '하체',
    icon: Icons.airline_seat_recline_extra,
  ),
  ExerciseTemplate(
    id: 'glute_bridge',
    name: '글루트 브리지',
    muscle: '하체',
    icon: Icons.airline_seat_recline_extra,
  ),
  ExerciseTemplate(
    id: 'calf_raise',
    name: '스탠딩 카프 레이즈',
    muscle: '하체',
    icon: Icons.height,
  ),
  ExerciseTemplate(
    id: 'seated_calf_raise',
    name: '시티드 카프 레이즈',
    muscle: '하체',
    icon: Icons.height,
  ),
  ExerciseTemplate(
    id: 'adductor_machine',
    name: '이너 타이 머신',
    muscle: '하체',
    icon: Icons.compare_arrows,
  ),

  // Arms
  ExerciseTemplate(
    id: 'barbell_curl',
    name: '바벨 컬',
    muscle: '팔',
    icon: Icons.fitness_center,
  ),
  ExerciseTemplate(
    id: 'hammer_curl',
    name: '해머 컬',
    muscle: '팔',
    icon: Icons.fitness_center,
  ),
  ExerciseTemplate(
    id: 'preacher_curl',
    name: '프리처 컬',
    muscle: '팔',
    icon: Icons.fitness_center,
  ),
  ExerciseTemplate(
    id: 'cable_curl',
    name: '케이블 컬',
    muscle: '팔',
    icon: Icons.fitness_center,
  ),
  ExerciseTemplate(
    id: 'triceps_pushdown',
    name: '트라이셉스 푸시다운',
    muscle: '팔',
    icon: Icons.vertical_align_bottom,
  ),
  ExerciseTemplate(
    id: 'skull_crusher',
    name: '라잉 트라이셉스 익스텐션',
    muscle: '팔',
    icon: Icons.fitness_center,
  ),
  ExerciseTemplate(
    id: 'overhead_triceps_extension',
    name: '오버헤드 트라이셉스 익스텐션',
    muscle: '팔',
    icon: Icons.upload,
  ),
  ExerciseTemplate(
    id: 'close_grip_bench',
    name: '클로즈 그립 벤치 프레스',
    muscle: '팔',
    icon: Icons.fitness_center,
  ),
  ExerciseTemplate(
    id: 'bench_dip',
    name: '벤치 딥스',
    muscle: '팔',
    icon: Icons.sports_gymnastics,
  ),
  ExerciseTemplate(
    id: 'reverse_curl',
    name: '리버스 컬',
    muscle: '팔',
    icon: Icons.fitness_center,
  ),

  // Core
  ExerciseTemplate(
    id: 'crunch',
    name: '크런치',
    muscle: '복근',
    icon: Icons.self_improvement,
    measurement: ExerciseMeasurement.repsOnly,
  ),
  ExerciseTemplate(
    id: 'cable_crunch',
    name: '케이블 크런치',
    muscle: '복근',
    icon: Icons.self_improvement,
  ),
  ExerciseTemplate(
    id: 'hanging_leg_raise',
    name: '행잉 레그 레이즈',
    muscle: '복근',
    icon: Icons.vertical_align_top,
    measurement: ExerciseMeasurement.repsOnly,
  ),
  ExerciseTemplate(
    id: 'leg_raise',
    name: '라잉 레그 레이즈',
    muscle: '복근',
    icon: Icons.self_improvement,
    measurement: ExerciseMeasurement.repsOnly,
  ),
  ExerciseTemplate(
    id: 'ab_wheel',
    name: 'AB 롤아웃',
    muscle: '복근',
    icon: Icons.radio_button_unchecked,
    measurement: ExerciseMeasurement.repsOnly,
  ),
  ExerciseTemplate(
    id: 'russian_twist',
    name: '러시안 트위스트',
    muscle: '복근',
    icon: Icons.rotate_right,
  ),
  ExerciseTemplate(
    id: 'dead_bug',
    name: '데드 버그',
    muscle: '복근',
    icon: Icons.accessibility_new,
  ),
  ExerciseTemplate(
    id: 'bird_dog',
    name: '버드 독',
    muscle: '복근',
    icon: Icons.accessibility_new,
  ),

  // Cardio
  ExerciseTemplate(
    id: 'stationary_bike',
    name: '실내 자전거',
    muscle: '유산소',
    icon: Icons.directions_bike,
  ),
  ExerciseTemplate(
    id: 'stair_climber',
    name: '스텝밀',
    muscle: '유산소',
    icon: Icons.stairs,
  ),
  ExerciseTemplate(
    id: 'rowing_machine',
    name: '로잉 머신',
    muscle: '유산소',
    icon: Icons.rowing,
  ),
  ExerciseTemplate(
    id: 'elliptical',
    name: '일립티컬',
    muscle: '유산소',
    icon: Icons.directions_run,
  ),
  ExerciseTemplate(
    id: 'brisk_walk',
    name: '빠르게 걷기',
    muscle: '유산소',
    icon: Icons.directions_walk,
  ),
  ExerciseTemplate(
    id: 'jump_rope',
    name: '줄넘기',
    muscle: '유산소',
    icon: Icons.sports_gymnastics,
  ),
  // Bodyweight — 기구 없이 하는 운동. 무게 다이얼이 없어야 하는 종목들이다.
  ExerciseTemplate(
    id: 'bodyweight_squat',
    name: '맨몸 스쿼트',
    muscle: '하체',
    icon: Icons.accessibility_new,
    measurement: ExerciseMeasurement.repsOnly,
  ),
  ExerciseTemplate(
    id: 'burpee',
    name: '버피',
    muscle: '하체',
    icon: Icons.sports_gymnastics,
    measurement: ExerciseMeasurement.repsOnly,
  ),
  ExerciseTemplate(
    id: 'side_plank',
    name: '사이드 플랭크',
    muscle: '복근',
    icon: Icons.timer_outlined,
    measurement: ExerciseMeasurement.duration,
  ),
  ExerciseTemplate(
    id: 'mountain_climber',
    name: '마운틴 클라이머',
    muscle: '복근',
    icon: Icons.directions_run,
    measurement: ExerciseMeasurement.duration,
  ),
  ExerciseTemplate(
    id: 'wall_sit',
    name: '월싯',
    muscle: '하체',
    icon: Icons.timer_outlined,
    measurement: ExerciseMeasurement.duration,
  ),
];
