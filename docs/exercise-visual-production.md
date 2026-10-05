# 운동 영상 제작 목록

2026-10-05 공개 `list_master_exercises` 조회를 보관하고, 실제 Flutter 도메인
모델과 `AppState`의 선택 목록 병합 순서로 제작 대상을 내보냈다.

| 범위 | 고유 ID 수 |
| --- | ---: |
| 오프라인 전체 | 367 |
| 자동 추천 검수 목록 | 80 |
| 오프라인 맨몸 추가 | 100 |
| 제조사별 머신 | 187 |
| 활성 공유 서버 목록 | 876 |
| 오프라인·공유 ID 중복 | 156 |
| 병합한 기본 제작 대상 | 1,087 |

직접 추가한 운동과 기기별 내 기구는 이 수치에 포함하지 않는다. 원격 개인
데이터나 로그인 토큰은 읽지 않았다. 사용자가 로컬 JSON을 제공하면 같은
내보내기 도구로 추가할 수 있다.

## 파일과 재현

- `output/exercise_visuals/catalog.json`: 종목 ID와 제작 상태를 담은 manifest.
- `output/exercise_visuals/production/shared_catalog_snapshot.json`: 공개 RPC의
  876개 원본 행. 조회 시각·공개 출처를 보관하며 자격 증명은 저장하지 않는다.
- `tool/export_exercise_visual_catalog.dart`: 순수 Dart CLI. Flutter helper를
  실행해 실제 `ExerciseTemplate`의 이름·기구와 서버 crosswalk를 평가한다.
- `tool/export_exercise_visual_snapshot_test.dart`: 모델 평가 helper. 문자열로
  Dart 소스를 추정하지 않고 앱과 같은 모델·mapper로 병합한다.

공유 snapshot이 이미 있으면 네트워크 없이 재현할 수 있다.

```powershell
dart run tool/export_exercise_visual_catalog.dart --output artifacts/exercise_visuals/catalog/reexport.json
```

공개 목록을 갱신할 때만 다음 옵션을 쓴다. 읽기 전용 공개 RPC 외에 서버 쓰기나
개인 데이터 조회 경로는 없다.

```powershell
dart run tool/export_exercise_visual_catalog.dart --refresh-shared --output artifacts/exercise_visuals/catalog/refreshed.json
```

오프라인 367개만 내보내려면 `--offline-only`를 붙인다. 파일 경로 옵션은
프로젝트 기준 상대 경로와 절대 경로를 모두 받는다. 각 모델 입력 파일과
공유 snapshot의 SHA-256은 manifest의 `provenance.inputSha256`에 남는다.

## 상태와 종목 식별

내보내기는 모든 종목을 `status: queued`, `reviewStatus: not_started`로 시작한다.
`motionKey`와 `visualAssets`는 비워 둔다. 제작 목록에 들어 있다는 사실이
영상 완성을 뜻하지 않는다. 영상 파일과 검토 결과를 확인한 제작 runner만
종목별 상태와 영상 경로를 연결한다.

이미 진행된 상태가 있는 manifest는 exporter가 덮어쓰지 않는다. 새 파일로
내보낸 뒤 `exerciseId`를 기준으로 진행 상태를 병합해야 한다. 렌더됐지만
검수되지 않은 시안과 앱에 연결 가능한 결과는 각각 구분해서 표시한다.

앱의 병합 순서는 오프라인 → 공유 → 맨몸 지원기구 보정 → 개인 입력이다.
서버 DB UUID와 앱의 안정된 `exerciseId`를 함께 남긴다. 예를 들어
`bodyweight_squat`는 맨몸 스쿼트이며 `squat`와 같은 종목으로 임의 연결하지
않는다. 제조사·모델이 다른 머신도 기존 기록의 별도 ID를 유지한다.

`phase`는 주요 운동 → 공유 변형 → 제조사별 머신의 제작 순서를 정하는
메타데이터다. 같은 phase 또는 이름이 비슷하다는 이유로 동작을 자동
공유하지 않는다. 동작 재사용에는 그립·발 위치·기구 접촉·가동 범위를
종목별로 확인한 명시적 연결이 필요하다.

## 직접 추가한 운동

`--personal-json`은 사용자가 내보낸 로컬 JSON 배열을 받는다. 각 행에는
고유한 `exerciseId`와 `name`이 필요하며, 기구와 근육 정보도 함께 적을 수 있다.
개인 목록에 같은 ID가 두 번 나오면 오류로 처리한다. 기존 목록과 같은
ID는 앱의 개인 목록 우선 원칙에 따라 덮어쓰고 두 개로 세지 않는다.

```json
[
  {
    "exerciseId": "my_custom_exercise_id",
    "name": "내 운동",
    "muscle": "하체",
    "equipmentKey": "machine",
    "primaryMuscles": ["quadriceps"],
    "secondaryMuscles": [],
    "metadata": {"notes": "기구 모델과 시작·끝 자세를 확인해야 함"}
  }
]
```

```powershell
dart run tool/export_exercise_visual_catalog.dart --personal-json artifacts/my_exercises.json --output artifacts/exercise_visuals/catalog/with-personal.json
```

## 출처와 표현 범위

공유 운동의 텍스트 메타데이터는 공개 free-exercise-db, 제조사 머신의
제품명·모델·링크는 앱의 검수된 `machineCatalog`에서 가져온다. 원본 운동
사진·GIF·제조사 사진은 manifest나 앱에 가져오지 않는다. GymVisual 이미지의
별도 계약이 없다는 기존 규칙도 유지한다.

시각 모델은 Setflow가 만든 CC0 MakeHuman 인체 기반 보디빌더 시안을 재사용한다.
붉은 표시에는 종목별 근육 영역 제작이 필요하며, 원본 메타데이터의 빈
근육 배열을 임의 부위로 채우지 않는다. 근육 표시는 교육용 부위 안내이며
측정된 근활성 수치가 아니다. 제조사 제품 링크가 있다는 사실이 기구의
정확한 형상·치수나 동작 검수를 대신하지 않는다.

## 사양과 제작 범위

`output/exercise_visuals/production/specifications.json`은 1,087개 원본 ID마다
텍스트 출처, 선택한 변형, 그립·몸통·기구·가동 범위와 부족한 근거를 남긴다.
`tool/exercise_visuals/production_specs.py`로 재현한다. 정확한 `sourceId`로
연결한 free-exercise-db의 텍스트와 라이선스·커밋·입력 해시는 함께 보관하며,
그 저장소의 사진은 내려받지 않는다. 수행 설명이 있어도 기구 모델·접촉·변형이
확정되지 않으면 `needs_reference`다. `specification_ready`도 영상 완성을
뜻하지 않는다. 출처 확인과 사람의 승인은 별도 필드로 기록한다.

2026-10-06 현재 파일 검사와 앱 자산 연결을 마친 **88개 정확한 ID의 영상 시안**이
있다. 나머지 **999개는 `queued`**다. 기본 80종 전체와 공개 카탈로그의
별도 UUID 8종이다. 제조사별 머신·추가 종목은 별도 제작 대상으로 남아 있다.
`coverage.json`과 catalog의 실제 미디어 수가 기준이다. 88종은 파일·시각
제작 검토를 마쳤으며, **트레이너 승인 수는 0**이다.

사양 snapshot은 전체 1,087개 ID를 보존하며 공식 근거로 명시한 사양은
57종, 추가 근거가 필요한 사양은 1,030종이다. 한국어 수행 설명은 79종,
교정 이력은 42종이고 현재 종목별 단계·기구 입력과 모두 일치한다.
사양 수, 실제 렌더 수, 사람의 승인 수를 각각 기록한다. 사양 도구 자체는
영상을 제작하거나 승인하지 않는다.

`motion_registry.py`는 실제로 구현한 ID의 소유 모듈만 등록한다. 이름 검색이나
부위로 다른 영상을 선택하지 않는다. `strength_motions.py`,
`bodyweight_motions.py`, `accessory_motions.py`의 `REFERENCES`와 출력의
`technique-reference.json`에 선택한 변형을 명시한다. 예를 들면 다음과 같다.

| 정확한 ID | 이번에 선택한 변형 |
| --- | --- |
| `squat` / `front_squat` | 하이바 백 스쿼트 / 앞어깨에 바를 지지하고 팔꿈치를 높인 클린 프런트 랙 스쿼트 |
| `goblet_squat` | 케틀벨의 양쪽 손잡이를 잡는 고블릿 스쿼트 |
| `ohp` / `dumbbell_shoulder_press` | 서서 하는 바벨 프레스 / 등받이 벤치에 앉은 덤벨 프레스 |
| `incline` / `incline_barbell` | 45도 벤치의 덤벨 프레스 / 바벨 프레스 |
| `hip_thrust` / `glute_bridge` | 벤치에 등을 지지한 바벨 힙 스러스트 / 바닥 바벨 브리지 |
| `hammer_curl` / `reverse_curl` | 중립 그립 덤벨 컬 / 오버핸드 스트레이트 바 컬 |
| `seated_cable_row` / `latpull` | 어깨 너비 오버핸드 스트레이트 바 로우 / 가슴 앞으로 당기는 오버핸드 풀다운 |
| `bench_dip` / `leg_raise` | 무릎을 굽힌 벤치 딥 / 플랫 벤치에 누운 레그 레이즈 |
| `arnold_press` | 등받이 벤치에 앉아 위팔·전완을 함께 회전하는 덤벨 프레스 |
| `one_arm_dumbbell_row` | 왼손·왼무릎을 벤치에 지지하고 오른발은 바닥에 둔 오른팔 덤벨 로우 |
| `close_grip_bench` | 어깨선의 오버핸드 그립으로 팔꿈치를 몸 가까이 두는 바벨 벤치 프레스 |
| `face_pull` | 얼굴 쪽으로 당기는 로프 케이블 페이스 풀 |
| `wall_sit` / `mountain_climber` / `russian_twist` | 벽을 지지한 정적 홀드 / 손을 지지한 무릎 당기기 / 발을 들고 무부하 몸통 회전 |
| `896189fc-30d9-51df-aa19-fd5ea7fa76eb` | `Sumo_Deadlift`의 넓은 스탠스·다리 안쪽 오버핸드 그립 |
| `58acf002-4e6d-5e95-b252-cae16252cef8` | `Stiff-Legged_Barbell_Deadlift`의 작은 무릎 굽힘을 유지한 힙 힌지 |

공유 운동의 UUID도 원본 ID 그대로 제작한다. 한쪽씩 하는 런지·스텝업·버드독·
데드버그·사이드 플랭크는 영상에서 보여 주는 쪽과 반대쪽 반복 안내를 기록한다.
선택 변형이 앱 설명·사양과 다르면 트레이너에게 그 차이를 보여 주며 승인된
일반 동작으로 자동 취급하지 않는다. 머신 외형은 자체 제작한 일반형으로,
제조사의 특정 모델 형상·링크 구조를 복제하거나 검증한 결과가 아니다.

## 공통 제작과 검사

첫 배치의 명시적 동작은 맨몸 스쿼트, 푸시업, 바벨·덤벨 벤치 프레스,
데드리프트, 루마니안 데드리프트, 바벨 로우, 덤벨 컬, 덤벨 숄더 프레스,
사이드 레터럴 레이즈, 스탠딩 카프 레이즈, 플랭크, 크런치다.
ID는 `tool/exercise_visuals/run_batch.py`의 `FIRST_BATCH`에 있다.
실제 완료 수와 남은 수는 `output/exercise_visuals/coverage.json`에서 확인한다.

공통 인체는 `bodyweight_squat/v5/squat.blend`에 보관한 연속 피부 메시와
53개 뼈의 가중 리그다. 기본 관절·근육·기구는 `motions.py`, `anatomy.py`,
`equipment.py`에 있고, 추가 모듈도 같은 인체와 렌더 경로를 사용한다.
Blender 장면과 공통 내보내기 전 검사는 `render_exercise.py`에서 정한다.

runner의 기본 설정은 480×480·12fps·48프레임·4초다. 현재 88종은 각각
24fps·96프레임·4초의 전체 MP4를 내보내고 모든 구간을 실제 열어 확인했다.
실제 해상도·프레임 수는 각 버전의 `media.json`에 기록하며, 이전 렌더 설정을
완성 수로 세지 않는다. 앱 GIF는 384×384다.
프레임 수는 fps의 4배, 최소 3fps여야 한다. 시작·끝 관절 위치와 뼈 길이,
선택한 고정 접촉점의 이동, 팔꿈치·손목 등 연결 관절의 틈, 손·기구 정렬,
직선 손잡이와 그립 축, 기구의 바닥 관통을 검사한다. 움직이는 발을 고정
접촉점으로 잘못 검사하지 않도록 종목별 접촉을 등록한다. 모든 프레임의
변형된 인체 피부가 바닥을 관통하는지도 검사하며, 푸시업의 손과 플랭크의
전완은 지지면이 바닥에서 뜨는 경우에도 실패한다. 적용한 종목의 바벨은
손의 의도된 그립 접촉을 구분해 실제 피부와 중앙 샤프트의 겹침을 검사한다.

종목별 추가 검사는 중립 손목, 회내·회외 그립, 팔꿈치 가동 범위, 몸통 고정,
지지점과 선택한 동작 범위를 확인한다. 수치는 이 리그와 선택 변형의 제작
오류를 막는 기준이다. 그립 중심의 오차가 0이어도 손가락 접촉이나 모든 기구의
피부 충돌이 검증된 것은 아니다. 피부·손가락·벤치 받침·장비 프레이밍·앞뒤
근육 표시는 세 자세와 전체 반복을 실제 열어 확인한다. 수치 통과, 정지 이미지
검토, 전체 영상 검토, 트레이너 승인을 각각 구분한다.

```powershell
python tool/exercise_visuals/run_batch.py --list
python tool/exercise_visuals/run_batch.py --ids curl bench --mode poses
python tool/exercise_visuals/run_batch.py --ids curl bench --fps 24 --frame-count 96 --resolution 480 --gif-size 384 --resume
```

`--resume`은 소스·설정·완성 파일 해시가 모두 같을 때만 출력을 건너뛴다.
새 제작의 `production/source-snapshots/<fingerprint>/source-manifest.json`에는
공통 렌더 코드, 선택한 동작·기구 코드와 로컬 의존 모듈의 불변 사본 및 SHA를
남긴다. 같은 실행 중 코드가 달라지면 완료 상태를 저장하지 않는다. 스냅샷이 있는
영상은 당시 코드 사본으로 재현하며 새 소스가 있다는 이유로 검수된 파일을 바꾸지 않는다.
스냅샷 도입 전 첫 55종은 검수한 Blender 원본·미디어·검사 결과의 해시를 보관하지만
당시 제작 코드 전체는 보관하지 않았다. 현재 도구 코드를 그 55종의 제작 시점 코드로 취급하지 않는다.
전진하는 워킹 런지의 반복은 선언한 실제 이동량을 뺀 관절 위치로 검사하고,
카메라와 조명이 몸을 따라가되 바닥은 그대로 둔다. 실제로 전진하지 않는 런지로
대체하지 않는다. 버피의 바닥 동작·점프처럼 종목별로 고른 주요 자세 시각도 저장한다.
손상되거나 중단된 상태 파일은 다시 생성한다. Blender는 순차로 실행하고
프레임·로그는 무시되는 `artifacts/exercise_visuals/`에 둔다. FFmpeg는 PATH나
현재 환경의 BlueStacks 설치본을 찾고 `--ffmpeg`로 지정할 수 있다.
MP4는 독립 프레임 H.264로 만들어 잔상을 피한다. 필요 도구는 Blender 4.4.1,
Python 3 + Pillow, FFmpeg다. Flutter 패키지는 추가하지 않았으며 GIF를
표준 Image/TickerMode로 재생한다.

```powershell
python tool/exercise_visuals/build_preview.py
python tool/exercise_visuals/sync_catalog.py --checked-demos curl bench --install
```

`build_preview.py`는 파일 해시와 완료 상태가 맞는 출력만 시안으로 표시한다.
`sync_catalog.py --checked-demos`는 실제 열어 확인한 ID의 시각 검토를 기록하며
트레이너 승인으로 바꾸지 않는다. `--install`은 해당 GIF를 로컬 Flutter
자산에 복사한다. `lib/data/exercise_visuals.dart`의 정확한 ID와 실제 표시
근육명도 함께 등록해야 앱에 나온다. 제작 목록 전체를 앱에 묶지 않고 실제
시안만 포함한다. 이 명령은 서버에 쓰거나 앱을 배포하지 않는다.

바벨 로우(`row`)는 오버핸드 벤트오버 로우의 시작 자세·손목·바 경로를 수정해
`row/v2`에 보관한다. 중간 렌더 프레임도 `artifacts/exercise_visuals/row/v2/frames`에
분리해 이전 `v1`과 섞이지 않는다. 다른 종목도 자체 수정 버전을
`run_batch.py`의 `OUTPUT_VERSIONS`에서 선택한다. 미리보기와 자산 설치는
완료 상태·파일 해시가 유효한 최신 버전을 선택하므로
완성된 `row/v2`가 기존 `row/v1`을 대체한다. 렌더나 파일 검사를 통과했다는 사실은
트레이너 검수 완료를 뜻하지 않으며, 로우 수정본도 검수 전 데모다.

클로즈그립 벤치는 `close_grip_bench/v2`가 현재 검수 대상이다. 기존 `v1`의
하강 끝점이 가슴에서 떨어져 보이는 문제를 보존한 뒤 새 버전에서 더 낮췄다.
현재 전체 프레임 검사에서 바와 몸 표면의 최소 간격은 약 2.43mm다.
이 수치는 해당 인체·바의 가장 가까운 표면이며 바 중앙의 간격이나 실제 하중
접촉을 뜻하지 않는다. 자체 27cm 벤치 패드·머리 받침과 약 146.5도 최대 팔꿈치
굽힘도 모델 선택이다. ACE가 요구하는 기구 치수나 보편적인 관절 각도가 아니다.
ACE 지침의 하강 문구는 가슴 쪽으로 내리는 것으로, 반드시 피부에 닿으라고
표기하지 않는다. 편안한 가동 범위·목·상부 등·엉덩이 지지는 트레이너가 확인한다.

프런트 랙의 손목 약 88도도 해당 시안의 모델 한계이며 모든 사람에게 권장하는
각도가 아니다. 바는 앞어깨에 지지하고, 팔꿈치를 전방으로 높이며 발바닥 전체를
지지하는 선택 변형과 NSCA 근거를 함께 기록했다. 버드독의 이전 지지팔 각도
문제와 클로즈그립 `v1` 지적은 원본 보고서에 남기고 교정본 검토로 대체했다.

로우는 `technique.py`의 별도 검사도 통과해야 내보낸다. 실제 관절에서 시작 팔꿈치
폄·전완과 손 축 정렬·무릎 및 몸통 고정·회내 그립을 측정하고, 모든 렌더 프레임에서
스킨 가중치로 변형된 몸 표면과 실제 샤프트 반경의 겹침을 검사한다. 손과 손가락의
의도된 그립 접촉은 가중치로 구분하며, 허벅지·복부·전완은 검사에서 빼지 않는다.
열린 손목 경계의 법선으로 몸 내부를 추정하지 않고 전체 메시의 표면 판정과
손을 제외한 몸의 근접 거리를 함께 쓴다. 이는 제작 오류를 막는 국소 충돌 검사이며
임상적 자세 판정이나 모든 인체에 적용되는 각도 기준이 아니다.

`row/v2/review.html`에는 수정 전 비교 영상과 수정본의 측면 검수 이미지를 둔다.
측면 이미지는 손목과 바를 볼 수 있도록 원판·슬리브·칼라만 숨긴다.
앱 자산과 실제 동작 영상에는 기구 전체가 보인다. `technique-reference.json`은
선택한 변형·제작 각도·견갑을 쇄골로 근사한 리그 한계를 기록한다.

오프라인 검토 화면은 `output/exercise_visuals/index.html`이며 검색·부위 필터,
제작 목록, 영상 재생·일시정지·0.5배속·세 자세 비교를 제공한다.
제작 목록만 있는 종목은 영상 버튼이 생기지 않는다.

## 트레이너에게 검수 전달하기

```powershell
python tool/exercise_visuals/production_specs.py
python tool/exercise_visuals/build_trainer_review.py --evidence output/exercise_visuals/production/current-review-evidence.json
python tool/exercise_visuals/build_trainer_review.py --self-test
```

`output/exercise_visuals/trainer-review.html`을 로컬 브라우저에서 연다.
1,087개 ID를 검색할 수 있으며 제작 대기 종목에는 대체 영상이나 승인 폼이
나타나지 않는다. `build_preview.load_exports`가 완료 상태·필수 파일·해시를
확인한 실제 미디어만 재생한다. 최신 native 초안이 아직 내보내지지 않았으면
현재 검토할 영상 버전과 새 초안의 대기 상태를 함께 표시한다.

`current-review-evidence.json`은 88종의 현재 native·영상·세 자세·기록된 QA
파일을 정확한 SHA로 연결한 제작 검사 증거다. 각 전체 MP4의 96프레임과
주요 자세 3개를 확인한 범위를 기록한다. 빌더는 catalog 해시, 실제 미디어와
제작 원본 해시, 기록된 파일·보고서 해시를 다시 확인한다. 바뀐 파일, 알 수
없는 ID, 실제 시안과 다른 coverage, 자동 승인 상태는 거부한다.

페이지의 **제작 검토 메모**에는 각 종목의 보고서, 확인한 프레임·자세 수,
전체 지적 사항과 트레이너에게 요청할 판단을 펼친 본문으로 표시한다.
`reverse_fly`의 앉은 출처와 서 있는 시안 범위 차이, `seated_cable_row`의
오버핸드 바 설명과 원본 중립 V핸들 설명 차이는 중간 심각도의 출처 질문으로
남겼다. `stair_climber`의 원본 2페달 설명과 선택한 회전 계단식 기구의 차이도
트레이너가 판단할 출처 질문이다. 이 세 건을 삭제하거나 낮춰 승인된 자세로 만들지 않는다. 현재 파일의
미해결 중간 이상 기하 오류는 없지만, 손가락 가림·지지 압력·모델별 가동 범위
등 낮은 심각도의 한계도 모두 표시한다. 출처 확인은 트레이너 승인과 별개다.

제작 검사 증거를 다시 모을 때는 교정 보고서를 이전 보고서 다음에 지정한다.
같은 정확한 ID의 최신 보고서가 현재 버전에 적용되고 이전 보고서는 보존된다.

```powershell
$exerciseReviewReports = @(
  "artifacts/exercise_visuals/expansion-accessory/final-independent-review.json"
  "artifacts/exercise_visuals/final-remaining-17/independent-review.json"
  "artifacts/exercise_visuals/final-expansion-14/independent-review.json"
  "artifacts/exercise_visuals/bird-dog-correction-review/independent-review.json"
  "artifacts/exercise_visuals/final-four-independent/independent-review.json"
  "artifacts/exercise_visuals/close-grip-correction-review/independent-review.json"
  "artifacts/exercise_visuals/remaining33-independent/machines-first-four-review.json"
  "artifacts/exercise_visuals/remaining33-independent/strength-first-two-review.json"
  "artifacts/exercise_visuals/remaining33-independent/cable-final-four-review.json"
  "artifacts/exercise_visuals/remaining33-independent/body-final-three-review.json"
  "artifacts/exercise_visuals/remaining33-independent/machine-extra-final-three-review.json"
  "artifacts/exercise_visuals/remaining33-independent/strength-extra-first-four-review.json"
  "artifacts/exercise_visuals/remaining33-independent/strength-extra-last-three-review.json"
  "artifacts/exercise_visuals/remaining33-independent/machine-sled-final-three-review.json"
  "artifacts/exercise_visuals/remaining33-independent/cardio-final-four-review.json"
  "artifacts/exercise_visuals/remaining33-independent/cardio-extra-final-three-review.json"
)
python tool/exercise_visuals/collect_review_evidence.py --reports $exerciseReviewReports --output output/exercise_visuals/production/current-review-evidence.json
```

검토자는 선택한 변형, 사양·텍스트 출처, 수치 검사와 한계를 읽고 시작·중간·
정점 이미지와 전체 MP4를 확인한다. 0.5배속 버튼과 영상 재생 컨트롤을 제공한다.
한국어 가이드 입력 해시가 사양 snapshot과 다르면 화면에 갱신 필요를 표시한다.
입력 catalog나 사양·영상이 바뀐 후에는 위 빌더를 다시 실행해야 한다.

검토자 실명은 필수다. 승인하려면 세 자세와 전체 영상을 봤다는 항목을 직접
체크하고, 수정 요청에는 코멘트를 적는다. 제출 버튼은 브라우저 `Blob`으로
검수 JSON 파일을 실제 다운로드한다. 결과에는 정확한 `exerciseId`, 선택 변형,
각 미디어와 native 파일의 SHA-256, QA·catalog·사양·제작 검토 증거 해시, 검토 시각, 검토자,
승인 또는 수정 요청, 코멘트를 담는다. 검수는 그 해시의 파일에만 적용된다.

다운로드한 JSON을 트레이너가 작업자에게 전달해야 한다. 외부 업로드나 서버
저장, 앱 승인 상태의 자동 변경은 없다. 모든 시안은 실제 검수 결과를 별도로
확인할 때까지 `trainer_pending`, `trainerApproved: false`로 유지한다.
공식 자료를 읽었거나 수치 검사를 통과했다는 이유로 전문가 승인 문구를
자동 표시하지 않으며, 목록 전체를 한 번에 승인하는 기능도 없다.

다른 컴퓨터로 전달할 때는 HTML 한 파일만 보내지 않고 검수 ZIP을 만든다.
catalog 상태와 미디어 연결을 갱신한 다음 현재 증거 수집 → 사양 생성 → 검수
HTML 생성 → 패키지 생성 순서로 실행한다. 패키지 도구는 현재 입력과 실제
미디어·native 해시를 검사하고 파일별 해시를 `bundle-manifest.json`에 남긴다.

```powershell
python tool/exercise_visuals/package_trainer_review.py --evidence output/exercise_visuals/production/current-review-evidence.json --output artifacts/exercise_visuals/trainer-review-package.zip
```

트레이너는 ZIP을 전부 압축 해제한 뒤 `trainer-review.html`을 Chrome 또는
Edge에서 연다. 이름을 적고 세 자세·전체 영상·제작 검토 메모를 확인한 다음
승인 또는 수정 요청 JSON을 내려받아 작업자에게 전달한다. 로컬 재생과
다운로드에는 외부 업로드가 없으며, 공식 출처 링크를 여는 경우 인터넷이 필요하다.
패키지에는 현재 검수 화면의 실제 미디어와 연결한 제작 원본·QA, 제작 대기 상태, 출처·제작
소스 및 현재 검사 증거를 넣는다. 교정 전 보고서를 함께 전달할 때도 현재
보고서에 적용되는 파일 해시와 과거 수정 이력을 구분한다.
기구 표면 검사 원본·검증 요약과 내보내기 메타데이터도 파일 해시를 확인해 포함한다.
읽기 전용으로 확인한 제조사·교육기관 PDF는 재배포하지 않고 출처 링크만 남긴다.

첫 55종의 보존 ZIP은 `artifacts/exercise_visuals/trainer-review-55.zip`이며 현재 패키지와
구분한다. SHA-256은 `22ee7cb99a13b32d014902228532445c136b58a9e518425d34cbe854c5d37793`이다.
새 종목을 추가해도 이 이전 검수 묶음을 덮어쓰지 않는다.

## 동작 확인 자료

2026-10-06 앱 적용본은 완성한 정확 ID 88종 모두에 수행 단계와 자체 동작 예시를
제공한다. 설명은 기본 80종과 공유 UUID 변형 8종을 각각 연결하며, 같은 이름이나
부위라는 이유로 다른 영상을 대신 쓰지 않는다. 수행 방법은 운동 선택 목록,
개인 세트 기록, 코칭 운동, 함께 운동의 현재 종목에서 사용자가 직접 열 수 있다.
선택·세트 완료·휴식·코칭 저장·방 진행은 설명을 열기만 해서는 바뀌지 않는다.
예시는 첫 프레임에서 멈춰 열리고, 트레이너 승인 전 `(데모)` 표기를 유지한다.

카탈로그에서 기구가 미지정이었던 불가리안 스플릿 스쿼트·프런트 레이즈·후면
레이즈는 덤벨, 리버스 컬은 바벨, 렛 풀 다운은 머신, 버드 독·빠른 걷기는
맨몸으로 명시했다. 기록 방식과 운동 ID는 유지하며 기구 필터와 검색에 반영한다.

최초 88종 검수 ZIP(`trainer-review-package.zip`)도 보존한다. 최신 수행 설명과
앱 적용 상태는 `artifacts/exercise_visuals/trainer-review-applied-88.zip`으로 별도
묶어 전달한다. 기존 미디어와 제작 원본은 그대로이고, 설명 교정은 영상에 대한
트레이너 승인이나 새 버전의 영상 제작으로 간주하지 않는다.

시작 자세·가동 범위·접촉을 아래 공식 자료로 확인했다. 자료의 사진·영상은
가져오지 않고 자체 관절·장면을 제작했다. 링크는 우리의 시안에 대한 승인을
뜻하지 않는다.

- [ACE 맨몸 스쿼트](https://www.acefitness.org/resources/everyone/exercise-library/135/bodyweight-squat/)
- [ACE 푸시업](https://www.acefitness.org/resources/everyone/exercise-library/41/push-up/)
- [ACE 바벨 벤치 프레스](https://www.acefitness.org/resources/everyone/exercise-library/5/chest-press/), [덤벨 벤치 프레스](https://www.acefitness.org/resources/everyone/exercise-library/19/chest-press/)
- [ACE 데드리프트](https://www.acefitness.org/resources/everyone/exercise-library/6/deadlift/), [NSCA 루마니안 데드리프트](https://www.nsca.com/education/articles/kinetic-select/romanian-deadlift-rdl/)
- [ACE 오버핸드 벤트오버 로우](https://www.acefitness.org/resources/everyone/exercise-library/12/bent-over-row/), [NSCA 로우의 중립 척추·상복부 목표](https://www.nsca.com/contentassets/24f7e187e9aa4a588439c9612231c7fd/tsac-module-3.0--3.3.pdf#page=19)
- [ACE 컬의 팔·손목 위치](https://www.acefitness.org/resources/everyone/exercise-library/44/seated-biceps-curl/), [정지한 상체·팔꿈치](https://www.acefitness.org/resources/everyone/exercise-library/70/bicep-curl/)
- [ACE 레터럴 레이즈](https://www.acefitness.org/resources/everyone/exercise-library/26/lateral-raise/), [숄더 프레스 동작 연구](https://www.acefitness.org/certifiednews/images/article/pdfs/ACEShoulderStudy.pdf)
- [ACE 팔꿈치 플랭크](https://www.acefitness.org/resources/everyone/exercise-library/32/front-plank/)
- [NSCA 프런트 스쿼트 클린 랙·발 지지, NSCA Coach 10.1의 Table 2](https://www.nsca.com/globalassets/education/nsca-coach/nsca-coach-10.1.pdf#page=10)
- [ACE 원암 로우](https://www.acefitness.org/resources/everyone/exercise-library/126/single-arm-row/), [클로즈그립 벤치 프레스](https://www.acefitness.org/resources/everyone/exercise-library/311/close-grip-bench-press/), [아놀드 프레스의 팔 회전](https://www.acefitness.org/resources/pros/expert-articles/6467/fast-and-efficient-upper-body-training/)

```powershell
python -m unittest discover -s tool/exercise_visuals -p "test_*.py"
dart run tool/check_architecture.dart
dart format lib test
flutter analyze
flutter test
```
