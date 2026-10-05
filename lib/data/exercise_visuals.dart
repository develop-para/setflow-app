/// 직접 제작하고 확인한 동작만 정확한 종목 ID에 연결한다.
/// 비슷한 이름·운동 부위·기구로 다른 종목의 영상을 대신 보여주지 않는다.
class ExerciseVisual {
  const ExerciseVisual({
    required this.assetPath,
    required this.highlightedMuscles,
    this.isStaticPose = false,
    this.variantDescription,
    this.demonstratedSide,
  });

  final String assetPath;
  final String highlightedMuscles;
  final bool isStaticPose;
  final String? variantDescription;
  final String? demonstratedSide;
}

/// CC0 MakeHuman 인체를 바탕으로 만든 Setflow 동작 예시.
/// 트레이너 검수가 끝나기 전까지 뷰어에 '(데모)'를 표시한다.
const exerciseVisuals = <String, ExerciseVisual>{
  'ab_wheel': ExerciseVisual(
    assetPath: 'assets/exercise_visuals/ab_wheel.gif',
    highlightedMuscles: '복근 · 척추기립근',
    variantDescription: '무릎을 바닥에 두고 허리 처짐 없이 제어하는 AB 휠 롤아웃',
  ),
  'adductor_machine': ExerciseVisual(
    assetPath: 'assets/exercise_visuals/adductor_machine.gif',
    highlightedMuscles: '내전근',
    variantDescription: '안쪽 무릎 패드를 모으는 시티드 내전근 머신',
  ),
  'arnold_press': ExerciseVisual(
    assetPath: 'assets/exercise_visuals/arnold_press.gif',
    highlightedMuscles: '삼각근 · 삼두근',
    variantDescription: '등받이에 지지하고 팔을 돌리며 밀어 올리는 덤벨 아놀드 프레스',
  ),
  'assisted_pullup': ExerciseVisual(
    assetPath: 'assets/exercise_visuals/assisted_pullup.gif',
    highlightedMuscles: '광배근 · 상부 등 · 이두근',
    variantDescription: '양 무릎을 움직이는 보조 패드에 지지하는 오버핸드 어시스트 풀업',
  ),
  'back_extension': ExerciseVisual(
    assetPath: 'assets/exercise_visuals/back_extension.gif',
    highlightedMuscles: '척추기립근 · 둔근 · 햄스트링',
    variantDescription: '45도 로만 체어 · 팔 교차 · 엉덩이 관절 중심 백 익스텐션',
  ),
  'barbell_curl': ExerciseVisual(
    assetPath: 'assets/exercise_visuals/barbell_curl.gif',
    highlightedMuscles: '이두근',
    variantDescription: '선 자세에서 손바닥이 앞을 향하는 바벨 컬',
  ),
  'bench': ExerciseVisual(
    assetPath: 'assets/exercise_visuals/bench.gif',
    highlightedMuscles: '대흉근 · 삼두근 · 삼각근',
    variantDescription: '플랫 벤치 바벨 프레스',
  ),
  'bench_dip': ExerciseVisual(
    assetPath: 'assets/exercise_visuals/bench_dip.gif',
    highlightedMuscles: '삼두근',
    variantDescription: '무릎을 굽히고 손을 벤치 가장자리에 둔 벤치 딥스',
  ),
  'bird_dog': ExerciseVisual(
    assetPath: 'assets/exercise_visuals/bird_dog.gif',
    highlightedMuscles: '복근 · 척추기립근 · 둔근',
    variantDescription: '네발 자세에서 반대쪽 팔과 다리 뻗기',
    demonstratedSide: '왼팔과 오른다리를 뻗는',
  ),
  'bodyweight_squat': ExerciseVisual(
    assetPath: 'assets/exercise_visuals/bodyweight_squat.gif',
    highlightedMuscles: '대퇴사두근 · 둔근',
    variantDescription: '양발을 지지하는 맨몸 스쿼트',
  ),
  'brisk_walk': ExerciseVisual(
    assetPath: 'assets/exercise_visuals/brisk_walk.gif',
    highlightedMuscles: '대퇴사두근 · 둔근 · 종아리',
    variantDescription: '지면을 앞으로 이동하며 발뒤꿈치부터 굴려 딛는 빠른 걷기',
  ),
  'bulgarian_split_squat': ExerciseVisual(
    assetPath: 'assets/exercise_visuals/bulgarian_split_squat.gif',
    highlightedMuscles: '대퇴사두근 · 둔근 · 햄스트링',
    variantDescription: '양손 덤벨을 들고 뒷발을 벤치에 지지하는 스플릿 스쿼트',
    demonstratedSide: '왼다리가 앞인',
  ),
  'burpee': ExerciseVisual(
    assetPath: 'assets/exercise_visuals/burpee.gif',
    highlightedMuscles: '대퇴사두근 · 둔근 · 대흉근 · 삼두근',
    variantDescription: '푸시업과 수직 점프를 포함한 버피',
  ),
  'cable_crunch': ExerciseVisual(
    assetPath: 'assets/exercise_visuals/cable_crunch.gif',
    highlightedMuscles: '복근',
    variantDescription: '높은 풀리를 바라보며 무릎을 꿇고 하는 로프 케이블 크런치',
  ),
  'cable_curl': ExerciseVisual(
    assetPath: 'assets/exercise_visuals/cable_curl.gif',
    highlightedMuscles: '이두근',
    variantDescription: '낮은 풀리 · 직선 바 · 언더핸드 그립 케이블 컬',
  ),
  'cable_fly': ExerciseVisual(
    assetPath: 'assets/exercise_visuals/cable_fly.gif',
    highlightedMuscles: '대흉근 · 삼각근',
    variantDescription: '가슴 높이 풀리 · 중립 그립 · 손을 가슴 앞에서 모으는 스탠딩 케이블 플라이',
  ),
  'cable_lateral_raise': ExerciseVisual(
    assetPath: 'assets/exercise_visuals/cable_lateral_raise.gif',
    highlightedMuscles: '삼각근',
    variantDescription: '낮은 풀리에서 반대 골반 앞을 지나 옆으로 드는 편측 케이블 레이즈',
    demonstratedSide: '왼팔로 드는',
  ),
  'calf_raise': ExerciseVisual(
    assetPath: 'assets/exercise_visuals/calf_raise.gif',
    highlightedMuscles: '종아리',
    variantDescription: '어깨 패드 머신에서 하는 스탠딩 카프 레이즈',
  ),
  'chest_press': ExerciseVisual(
    assetPath: 'assets/exercise_visuals/chest_press.gif',
    highlightedMuscles: '대흉근 · 삼두근 · 삼각근',
    variantDescription: '등과 양발을 지지하고 가슴 중간 손잡이를 미는 머신 체스트 프레스',
  ),
  'chest_supported_row': ExerciseVisual(
    assetPath: 'assets/exercise_visuals/chest_supported_row.gif',
    highlightedMuscles: '광배근 · 승모근 · 이두근 · 후면 삼각근',
    variantDescription: '45도 벤치 가슴 지지 · 양손 중립 그립 덤벨 로우',
  ),
  'close_grip_bench': ExerciseVisual(
    assetPath: 'assets/exercise_visuals/close_grip_bench.gif',
    highlightedMuscles: '삼두근 · 대흉근 · 삼각근',
    variantDescription: '손을 어깨선에 두는 플랫 바벨 클로즈그립 벤치 프레스',
  ),
  'crunch': ExerciseVisual(
    assetPath: 'assets/exercise_visuals/crunch.gif',
    highlightedMuscles: '복근',
    variantDescription: '발을 바닥에 두고 손을 머리 옆에 둔 바닥 크런치',
  ),
  'curl': ExerciseVisual(
    assetPath: 'assets/exercise_visuals/curl.gif',
    highlightedMuscles: '이두근',
    variantDescription: '선 자세에서 손바닥이 앞을 향하는 덤벨 컬',
  ),
  'dead_bug': ExerciseVisual(
    assetPath: 'assets/exercise_visuals/dead_bug.gif',
    highlightedMuscles: '복근',
    variantDescription: '누운 자세에서 반대쪽 팔과 다리 뻗기',
    demonstratedSide: '오른팔과 왼다리를 뻗는',
  ),
  'deadlift': ExerciseVisual(
    assetPath: 'assets/exercise_visuals/deadlift.gif',
    highlightedMuscles: '둔근 · 햄스트링 · 척추기립근 · 대퇴사두근',
    variantDescription: '바닥에서 시작하는 오버핸드 바벨 데드리프트',
  ),
  'decline_bench': ExerciseVisual(
    assetPath: 'assets/exercise_visuals/decline_bench.gif',
    highlightedMuscles: '대흉근 · 삼두근 · 삼각근',
    variantDescription: '15도 디클라인 벤치 · 발 고정 · 낮은 흉골 쪽 바벨 프레스',
  ),
  'dips': ExerciseVisual(
    assetPath: 'assets/exercise_visuals/dips.gif',
    highlightedMuscles: '대흉근 · 삼두근 · 삼각근',
    variantDescription: '상체를 앞으로 기울이는 평행봉 딥스',
  ),
  'dumbbell_bench': ExerciseVisual(
    assetPath: 'assets/exercise_visuals/dumbbell_bench.gif',
    highlightedMuscles: '대흉근 · 삼두근 · 삼각근',
    variantDescription: '플랫 벤치 덤벨 프레스',
  ),
  'dumbbell_shoulder_press': ExerciseVisual(
    assetPath: 'assets/exercise_visuals/dumbbell_shoulder_press.gif',
    highlightedMuscles: '삼각근 · 삼두근',
    variantDescription: '등받이에 지지하고 앉아서 하는 덤벨 숄더 프레스',
  ),
  'elliptical': ExerciseVisual(
    assetPath: 'assets/exercise_visuals/elliptical.gif',
    highlightedMuscles: '대퇴사두근 · 둔근 · 햄스트링 · 종아리 · 삼각근',
    variantDescription: '페달과 움직이는 양팔 손잡이가 연결된 전방 일립티컬 페달링',
  ),
  'face_pull': ExerciseVisual(
    assetPath: 'assets/exercise_visuals/face_pull.gif',
    highlightedMuscles: '후면 삼각근 · 상부 등 · 이두근',
    variantDescription: '눈높이 풀리 · 로프 양끝을 얼굴 방향으로 당기는 페이스 풀',
  ),
  'front_raise': ExerciseVisual(
    assetPath: 'assets/exercise_visuals/front_raise.gif',
    highlightedMuscles: '삼각근',
    variantDescription: '양손 덤벨을 어깨 높이까지 앞으로 드는 프런트 레이즈',
  ),
  'front_squat': ExerciseVisual(
    assetPath: 'assets/exercise_visuals/front_squat.gif',
    highlightedMuscles: '대퇴사두근 · 둔근 · 복근',
    variantDescription: '어깨 바깥 그립과 높은 팔꿈치로 바벨을 앞어깨에 지지하는 프런트 스쿼트',
  ),
  'glute_bridge': ExerciseVisual(
    assetPath: 'assets/exercise_visuals/glute_bridge.gif',
    highlightedMuscles: '둔근 · 햄스트링',
    variantDescription: '바닥에서 하는 바벨 글루트 브리지',
  ),
  'goblet_squat': ExerciseVisual(
    assetPath: 'assets/exercise_visuals/goblet_squat.gif',
    highlightedMuscles: '대퇴사두근 · 둔근 · 복근',
    variantDescription: '케틀벨 손잡이를 가슴 앞에 잡는 고블릿 스쿼트',
  ),
  'hack_squat': ExerciseVisual(
    assetPath: 'assets/exercise_visuals/hack_squat.gif',
    highlightedMuscles: '대퇴사두근 · 둔근',
    variantDescription: '등과 양어깨 패드 · 고정 발판 지지 슬래드 핵 스쿼트',
  ),
  'hammer_curl': ExerciseVisual(
    assetPath: 'assets/exercise_visuals/hammer_curl.gif',
    highlightedMuscles: '이두근 · 전완근',
    variantDescription: '손바닥이 서로 마주보는 그립을 유지하는 덤벨 해머 컬',
  ),
  'hanging_leg_raise': ExerciseVisual(
    assetPath: 'assets/exercise_visuals/hanging_leg_raise.gif',
    highlightedMuscles: '복근',
    variantDescription: '반동 없이 편 다리를 수평까지 드는 행잉 레그 레이즈',
  ),
  'hip_thrust': ExerciseVisual(
    assetPath: 'assets/exercise_visuals/hip_thrust.gif',
    highlightedMuscles: '둔근 · 햄스트링',
    variantDescription: '등 위쪽을 벤치에 지지하는 바벨 힙 쓰러스트',
  ),
  'incline': ExerciseVisual(
    assetPath: 'assets/exercise_visuals/incline.gif',
    highlightedMuscles: '대흉근 · 삼각근 · 삼두근',
    variantDescription: '45도 인클라인 덤벨 프레스',
  ),
  'incline_barbell': ExerciseVisual(
    assetPath: 'assets/exercise_visuals/incline_barbell.gif',
    highlightedMuscles: '대흉근 · 삼각근 · 삼두근',
    variantDescription: '45도 인클라인 바벨 프레스',
  ),
  'jump_rope': ExerciseVisual(
    assetPath: 'assets/exercise_visuals/jump_rope.gif',
    highlightedMuscles: '종아리 · 대퇴사두근 · 복근',
    variantDescription: '발을 가까이 두고 손목으로 줄을 돌리는 낮은 두 발 기본 바운스',
  ),
  'lateral': ExerciseVisual(
    assetPath: 'assets/exercise_visuals/lateral.gif',
    highlightedMuscles: '삼각근',
    variantDescription: '선 자세에서 양팔을 옆으로 드는 덤벨 레터럴 레이즈',
  ),
  'latpull': ExerciseVisual(
    assetPath: 'assets/exercise_visuals/latpull.gif',
    highlightedMuscles: '광배근 · 이두근',
    variantDescription: '바를 머리 앞에서 가슴 쪽으로 당기는 오버핸드 랫 풀다운',
  ),
  'leg_curl': ExerciseVisual(
    assetPath: 'assets/exercise_visuals/leg_curl.gif',
    highlightedMuscles: '햄스트링',
    variantDescription: '골반과 허벅지를 패드에 지지하는 엎드린 머신 레그 컬',
  ),
  'leg_extension': ExerciseVisual(
    assetPath: 'assets/exercise_visuals/leg_extension.gif',
    highlightedMuscles: '대퇴사두근',
    variantDescription: '등과 허벅지를 지지하고 정강이 패드를 드는 머신 레그 익스텐션',
  ),
  'leg_raise': ExerciseVisual(
    assetPath: 'assets/exercise_visuals/leg_raise.gif',
    highlightedMuscles: '복근',
    variantDescription: '등을 플랫 벤치에 지지하고 편 다리를 드는 레그 레이즈',
  ),
  'legpress': ExerciseVisual(
    assetPath: 'assets/exercise_visuals/legpress.gif',
    highlightedMuscles: '대퇴사두근 · 둔근',
    variantDescription: '고정 시트 · 움직이는 발판 · 양발을 지지하는 레그 프레스',
  ),
  'mountain_climber': ExerciseVisual(
    assetPath: 'assets/exercise_visuals/mountain_climber.gif',
    highlightedMuscles: '복근 · 대퇴사두근 · 삼각근',
    variantDescription: '양손을 바닥에 고정하고 앞뒤 다리를 교체하는 마운틴 클라이머',
  ),
  'ohp': ExerciseVisual(
    assetPath: 'assets/exercise_visuals/ohp.gif',
    highlightedMuscles: '삼각근 · 삼두근',
    variantDescription: '스탠딩 바벨 프레스 · 다리 반동 없이',
  ),
  'one_arm_dumbbell_row': ExerciseVisual(
    assetPath: 'assets/exercise_visuals/one_arm_dumbbell_row.gif',
    highlightedMuscles: '광배근 · 상부 등 · 이두근',
    variantDescription: '왼손과 왼쪽 무릎을 벤치에 지지하는 원암 덤벨 로우',
    demonstratedSide: '오른팔로 당기는',
  ),
  'overhead_triceps_extension': ExerciseVisual(
    assetPath: 'assets/exercise_visuals/overhead_triceps_extension.gif',
    highlightedMuscles: '오른쪽 삼두근',
    variantDescription: '선 자세 · 한 손 덤벨 · 손바닥이 앞을 향하는 오버헤드 익스텐션',
    demonstratedSide: '오른팔로 드는',
  ),
  'pec_deck': ExerciseVisual(
    assetPath: 'assets/exercise_visuals/pec_deck.gif',
    highlightedMuscles: '대흉근',
    variantDescription: '세로 손잡이 · 중립 그립으로 하는 시티드 펙덱 플라이',
  ),
  'plank': ExerciseVisual(
    assetPath: 'assets/exercise_visuals/plank.gif',
    highlightedMuscles: '복근',
    variantDescription: '팔꿈치를 어깨 아래에 둔 전완 플랭크',
    isStaticPose: true,
  ),
  'preacher_curl': ExerciseVisual(
    assetPath: 'assets/exercise_visuals/preacher_curl.gif',
    highlightedMuscles: '이두근',
    variantDescription: '팔 패드 지지 · 좁은 안쪽 EZ바 그립으로 하는 프리처 컬',
  ),
  'pullup': ExerciseVisual(
    assetPath: 'assets/exercise_visuals/pullup.gif',
    highlightedMuscles: '광배근 · 상부 등 · 이두근',
    variantDescription: '오버핸드 그립 · 반동 없이 하는 풀업',
  ),
  'pushup': ExerciseVisual(
    assetPath: 'assets/exercise_visuals/pushup.gif',
    highlightedMuscles: '대흉근 · 삼두근 · 삼각근',
    variantDescription: '손바닥과 발끝으로 지지하는 바닥 푸시업',
  ),
  'rack_pull': ExerciseVisual(
    assetPath: 'assets/exercise_visuals/rack_pull.gif',
    highlightedMuscles: '둔근 · 햄스트링 · 척추기립근 · 승모근',
    variantDescription: '무릎 높이 안전 받침에서 시작하는 오버핸드 바벨 랙 풀',
  ),
  'rear_delt_raise': ExerciseVisual(
    assetPath: 'assets/exercise_visuals/rear_delt_raise.gif',
    highlightedMuscles: '후면 삼각근 · 상부 등',
    variantDescription: '상체를 숙여 양손 덤벨을 옆으로 드는 후면 레이즈',
  ),
  'reverse_curl': ExerciseVisual(
    assetPath: 'assets/exercise_visuals/reverse_curl.gif',
    highlightedMuscles: '전완근 · 이두근',
    variantDescription: '오버핸드 그립으로 하는 바벨 리버스 컬',
  ),
  'reverse_fly': ExerciseVisual(
    assetPath: 'assets/exercise_visuals/reverse_fly.gif',
    highlightedMuscles: '후면 삼각근 · 상부 등',
    variantDescription: '상체를 숙여 양손 덤벨을 옆으로 벌리는 리버스 플라이',
  ),
  'reverse_pec_deck': ExerciseVisual(
    assetPath: 'assets/exercise_visuals/reverse_pec_deck.gif',
    highlightedMuscles: '후면 삼각근 · 상부 등',
    variantDescription: '가슴 패드 지지 · 엄지가 위인 중립 그립 리버스 펙덱 플라이',
  ),
  'romanian_deadlift': ExerciseVisual(
    assetPath: 'assets/exercise_visuals/romanian_deadlift.gif',
    highlightedMuscles: '둔근 · 햄스트링 · 척추기립근',
    variantDescription: '선 자세에서 시작하는 바벨 루마니안 데드리프트',
  ),
  'row': ExerciseVisual(
    assetPath: 'assets/exercise_visuals/row.gif',
    highlightedMuscles: '광배근 · 상부 등 · 이두근',
    variantDescription: '오버핸드 그립으로 복부 방향에 당기는 벤트오버 바벨 로우',
  ),
  'rowing_machine': ExerciseVisual(
    assetPath: 'assets/exercise_visuals/rowing_machine.gif',
    highlightedMuscles: '대퇴사두근 · 둔근 · 햄스트링 · 광배근 · 이두근 · 척추기립근',
    variantDescription: '발 스트랩과 이동 시트 · 다리·몸통·팔 순서로 당기는 로잉 머신',
  ),
  'run': ExerciseVisual(
    assetPath: 'assets/exercise_visuals/run.gif',
    highlightedMuscles: '대퇴사두근 · 둔근 · 햄스트링 · 종아리',
    variantDescription: '움직이는 수평 트레드밀 벨트 · 안전 정지 줄 연결 · 편안한 달리기',
  ),
  'russian_twist': ExerciseVisual(
    assetPath: 'assets/exercise_visuals/russian_twist.gif',
    highlightedMuscles: '복근',
    variantDescription: '발을 들고 양손을 모아 좌우로 회전하는 맨몸 러시안 트위스트',
  ),
  'seated_cable_row': ExerciseVisual(
    assetPath: 'assets/exercise_visuals/seated_cable_row.gif',
    highlightedMuscles: '광배근 · 상부 등 · 이두근',
    variantDescription: '낮은 풀리 · 직선 바 · 오버핸드 그립 시티드 로우',
  ),
  'seated_calf_raise': ExerciseVisual(
    assetPath: 'assets/exercise_visuals/seated_calf_raise.gif',
    highlightedMuscles: '종아리',
    variantDescription: '허벅지 패드 · 앞발 발판 지지 · 고정 옆 손잡이 시티드 카프 레이즈',
  ),
  'side_plank': ExerciseVisual(
    assetPath: 'assets/exercise_visuals/side_plank.gif',
    highlightedMuscles: '복근',
    variantDescription: '발을 앞뒤로 놓고 전완으로 지지하는 사이드 플랭크',
    demonstratedSide: '오른쪽 전완으로 지지하는',
    isStaticPose: true,
  ),
  'skull_crusher': ExerciseVisual(
    assetPath: 'assets/exercise_visuals/skull_crusher.gif',
    highlightedMuscles: '삼두근',
    variantDescription: '플랫 벤치 · EZ바 · 위팔을 고정하고 이마 위에서 멈추는 스컬 크러셔',
  ),
  'squat': ExerciseVisual(
    assetPath: 'assets/exercise_visuals/squat.gif',
    highlightedMuscles: '대퇴사두근 · 둔근',
    variantDescription: '바벨을 등 위쪽에 지지하는 하이바 백 스쿼트',
  ),
  'stair_climber': ExerciseVisual(
    assetPath: 'assets/exercise_visuals/stair_climber.gif',
    highlightedMuscles: '대퇴사두근 · 둔근 · 종아리',
    variantDescription: '회전하는 계단 · 발판 전체 지지 · 가볍게 손잡이를 잡는 스텝밀',
  ),
  'stationary_bike': ExerciseVisual(
    assetPath: 'assets/exercise_visuals/stationary_bike.gif',
    highlightedMuscles: '대퇴사두근 · 둔근 · 햄스트링 · 종아리',
    variantDescription: '안장 지지 · 페달 스트랩 · 앞쪽 고정 손잡이 · 전방 페달링',
  ),
  'straight_arm_pulldown': ExerciseVisual(
    assetPath: 'assets/exercise_visuals/straight_arm_pulldown.gif',
    highlightedMuscles: '광배근 · 상부 등',
    variantDescription: '높은 풀리 · 직선 바 · 팔꿈치 굽힘을 작게 유지하는 스트레이트암 풀다운',
  ),
  'tbar_row': ExerciseVisual(
    assetPath: 'assets/exercise_visuals/tbar_row.gif',
    highlightedMuscles: '광배근 · 승모근 · 이두근 · 척추기립근',
    variantDescription: '한쪽이 고정된 바벨과 중립 그립 손잡이로 하는 랜드마인 T바 로우',
  ),
  'triceps_pushdown': ExerciseVisual(
    assetPath: 'assets/exercise_visuals/triceps_pushdown.gif',
    highlightedMuscles: '삼두근',
    variantDescription: '높은 풀리 · 직선 바 · 오버핸드 그립 푸시다운',
  ),
  'upright_row': ExerciseVisual(
    assetPath: 'assets/exercise_visuals/upright_row.gif',
    highlightedMuscles: '삼각근 · 승모근',
    variantDescription: '넓은 오버핸드 그립 · 팔꿈치를 옆으로 이끌고 어깨 아래에서 멈추는 업라이트 로우',
  ),
  'walking_lunge': ExerciseVisual(
    assetPath: 'assets/exercise_visuals/walking_lunge.gif',
    highlightedMuscles: '대퇴사두근 · 둔근 · 햄스트링',
    variantDescription: '양손 덤벨을 들고 한 발씩 앞으로 이동하는 워킹 런지',
  ),
  'wall_sit': ExerciseVisual(
    assetPath: 'assets/exercise_visuals/wall_sit.gif',
    highlightedMuscles: '대퇴사두근 · 둔근 · 종아리',
    variantDescription: '양발을 바닥에 두고 등과 엉덩이를 벽에 지지하는 월싯',
    isStaticPose: true,
  ),
  '0f177240-029b-543a-be27-2e8ed0526bca': ExerciseVisual(
    assetPath:
        'assets/exercise_visuals/0f177240-029b-543a-be27-2e8ed0526bca.gif',
    highlightedMuscles: '대퇴사두근 · 둔근 · 햄스트링',
    variantDescription: '원본 설명에 따른 뒷발 벤치 지지 덤벨 스플릿 스쿼트',
    demonstratedSide: '왼다리가 앞인',
  ),
  '3c358477-aeb3-5d78-a6aa-91c9fb6c81db': ExerciseVisual(
    assetPath:
        'assets/exercise_visuals/3c358477-aeb3-5d78-a6aa-91c9fb6c81db.gif',
    highlightedMuscles: '광배근 · 이두근',
    variantDescription: '손바닥이 얼굴을 향하는 그립 · 반동 없이 하는 친업',
  ),
  '58acf002-4e6d-5e95-b252-cae16252cef8': ExerciseVisual(
    assetPath:
        'assets/exercise_visuals/58acf002-4e6d-5e95-b252-cae16252cef8.gif',
    highlightedMuscles: '햄스트링 · 둔근 · 척추기립근',
    variantDescription: '무릎 굽힘을 작게 유지하는 바벨 스티프레그 데드리프트',
  ),
  '823846f5-2414-58b7-911e-2d9397a28f49': ExerciseVisual(
    assetPath:
        'assets/exercise_visuals/823846f5-2414-58b7-911e-2d9397a28f49.gif',
    highlightedMuscles: '대퇴사두근 · 둔근 · 햄스트링',
    variantDescription: '앞발을 플랫폼에 둔 자세에서 시작하는 덤벨 스텝업',
    demonstratedSide: '왼다리로 올라서는',
  ),
  '896189fc-30d9-51df-aa19-fd5ea7fa76eb': ExerciseVisual(
    assetPath:
        'assets/exercise_visuals/896189fc-30d9-51df-aa19-fd5ea7fa76eb.gif',
    highlightedMuscles: '둔근 · 대퇴사두근 · 햄스트링 · 척추기립근',
    variantDescription: '발을 넓게 벌리고 무릎 안쪽에서 바를 잡는 스모 데드리프트',
  ),
  'bff7dff4-2b99-5357-b365-f10e1187cbb3': ExerciseVisual(
    assetPath:
        'assets/exercise_visuals/bff7dff4-2b99-5357-b365-f10e1187cbb3.gif',
    highlightedMuscles: '대퇴사두근 · 둔근 · 햄스트링',
    variantDescription: '덤벨을 들고 앞으로 내디딘 뒤 제자리로 돌아오는 런지',
    demonstratedSide: '왼다리를 앞으로 내딛는',
  ),
  'd1ecb818-0235-5e2f-9113-39be506aa98a': ExerciseVisual(
    assetPath:
        'assets/exercise_visuals/d1ecb818-0235-5e2f-9113-39be506aa98a.gif',
    highlightedMuscles: '대퇴사두근 · 둔근 · 햄스트링',
    variantDescription: '덤벨을 들고 뒤로 내디딘 뒤 제자리로 돌아오는 런지',
    demonstratedSide: '오른다리를 뒤로 내딛는',
  ),
  'dd9ea4cf-1bc9-56f6-b8e0-06b6ef5f7ebe': ExerciseVisual(
    assetPath:
        'assets/exercise_visuals/dd9ea4cf-1bc9-56f6-b8e0-06b6ef5f7ebe.gif',
    highlightedMuscles: '삼두근 · 대흉근 · 삼각근',
    variantDescription: '상체를 세우고 팔꿈치를 가까이 둔 평행봉 딥스',
  ),
};
