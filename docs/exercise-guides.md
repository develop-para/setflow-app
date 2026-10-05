# 종목 수행 방법 — 출처와 라이선스 경계

`lib/data/exercise_guides.dart`의 기존 한국어 단계별 설명은
[hasaneyldrm/exercises-dataset](https://github.com/hasaneyldrm/exercises-dataset)에서 왔다.
종목·그립·기구가 잘못 연결된 문장은 정확한 원본 텍스트와 수행 지침을 대조해
Setflow가 수정했고, 직접 쓴 단계는 아래에 따로 기록한다.

## 텍스트는 써도 되고, 이미지는 안 된다

그 저장소는 **라이선스가 두 겹**이다. 한 줄로 요약하면:

| 부분 | 라이선스 | 우리가 쓸 수 있나 |
|---|---|---|
| 코드·데이터 구조·**설명 텍스트와 번역** | MIT | **가능** |
| `images/`·`videos/` (썸네일·애니메이션 GIF) | MIT 아님 | **불가** |

미디어는 **Gym visual**(https://gymvisual.com/) 소유다. 저장소 저자가 **자기 앞으로 받은
별도 서면 허가**로 재배포하고 있을 뿐이고, `NOTICE.md`가 이렇게 적고 있다:

> If you use this media in your own project, review those terms and, where required,
> obtain permission.

**그 허가는 그쪽 것이지 우리 것이 아니다.** 상용 배포되는 앱에 GIF나 썸네일을 넣으려면
Gym visual과 별도로 계약해야 한다. 지금은 **텍스트만** 가져왔다.

이미지를 넣기로 결정한다면 그 전에:
1. Gym visual 이용약관 확인 — https://gymvisual.com/content/3-terms-and-conditions-of-use
2. 재배포·상용 이용 허가를 **우리 이름으로** 받을 것
3. 180×180 해상도 제한과 `© Gym visual` 저작권 표시 유지

## 매핑

우리 카탈로그는 80종, 데이터셋은 1,324종이고 이름이 한국어 대 영어라 손으로 이었다.
매핑 결과는 `lib/data/exercise_guides.dart`에 직접 들어 있다(별도 생성 도구는 없다 —
데이터셋 갱신 시 이 문서의 대응표를 기준으로 손으로 맞춘다).

**71종이 연결됐고 9종은 데이터셋에 대응 항목이 없다** — 페이스 풀, 힙 쓰러스트,
버드 독, 로잉 머신, 그리고 맨몸운동 추가분(맨몸 스쿼트, 버피, 사이드 플랭크,
마운틴 클라이머, 월싯). 이 중 힙 쓰러스트·버드 독·사이드 플랭크는 공식 설명을
확인하고 직접 작성했다. 이후 페이스 풀·마운틴 클라이머·월싯도 공식 설명으로
직접 작성했다. 버피도 NASM의 푸시업·수직 점프 포함 변형을 확인해 직접
작성했고, 로잉 머신은 Concept2의 스트로크 순서를 직접 설명했다. 이후 정확한
[ACE Bodyweight Squat 본문](https://www.acefitness.org/resources/everyone/exercise-library/135/bodyweight-squat/)과
자체 맨몸 시안을 대조하여 맨몸 스쿼트도 직접 작성했다. 현재 기본 80종과 아래
공유 UUID 8종, 총 **88종**에 수행 단계를 제공한다.
없는 걸 억지로 비슷한 종목에
이으면 초보자에게 **틀린 동작을 가르치게 된다.** 처음에 빠졌던 셋은 나중에 정확한
항목을 찾아 이었다: 바벨 로우 ← `barbell bent over row`, 펙덱 플라이 ← `lever
seated fly`(lever가 머신이라는 뜻이다), 줄넘기 ← `jump rope`.

억지 매핑의 경계가 실제로 어디였는지 남긴다: 페이스 풀은 `cable standing rear delt
row (with rope)`가 기계적으로 가장 가깝지만 당기는 목표 지점(얼굴 vs 가슴)이 달라서
잇지 않았고, 힙 쓰러스트는 `barbell glute bridge`가 등을 벤치에 올리지 않는 바닥
동작이라 잇지 않았다.

플랭크(`plank`)의 기존 단계는 팔을 들어 몸통을 회전하는 하이 플랭크 변형으로
잘못 연결되어 있었다. 앱의 시간 기록·팔꿈치 정적 플랭크 동작에 맞춰 Setflow가
한국어 3단계를 다시 작성했다. 팔꿈치·어깨의 위치, 몸통 정렬, 정적 유지와 호흡은
[ACE Front Plank 설명](https://www.acefitness.org/resources/everyone/exercise-library/32/front-plank/)을
확인했다. 이 3단계는 기존 데이터셋의 번역 문장이 아니다.

바벨 로우(`row`)는 자체 시안 v2와 설명이 같은 **오버핸드 벤트오버 로우**를
가리키도록 Setflow가 한국어 5단계를 다시 작성했다.
[ACE Bent-over Row](https://www.acefitness.org/resources/everyone/exercise-library/12/bent-over-row/)의
엉덩이 힌지·약간 굽힌 무릎·팔을 편 시작·고정된 등·배꼽 방향 당기기를 기준으로 했다.
기존의 모호한 손 방향과 아래 가슴 목표 문장은 이 변형과 맞지 않아 교체했다.
각도 수치는 인체 모델에 맞춘 제작 값이며 모든 사용자의 필수 각도라는 뜻이 아니다.
설명 확인과 영상의 자세 검수는 별개이며, 영상은 트레이너 승인 전 데모다.

힙 쓰러스트는 [ACE Elevated Glute Bridge](https://www.acefitness.org/resources/everyone/exercise-library/367/elevated-glute-bridge/)와
[NSCA 둔근 훈련 설명](https://www.nsca.com/education/articles/ptq/program-design-strength-hypertrophy-glute/)을
참고해 등 위쪽 벤치 지지·골반의 바벨 보호 패드·고정된 발·허리 과신전 없이
골반을 펴는 바벨 변형을 직접 작성했다. 바닥 바벨 브리지 설명을 대신 붙이지 않는다.
버드 독은 [ACE Bird-dog](https://www.acefitness.org/resources/everyone/exercise-library/14/bird-dog/)의
반대쪽 팔·다리와 몸통 고정을, 사이드 플랭크는
[NASM Side Plank](https://www.nasm.org/resource-center/exercise-library/side-plank)의
전완 지지·곧은 몸통·앞뒤로 놓은 발 변형을 직접 설명했다.

페이스 풀은 [NASM Face Pull](https://www.nasm.org/resource-center/exercise-library/face-pull)의
눈높이 풀리·로프·얼굴 방향 당기기를, 마운틴 클라이머는
[ACE Mountain Climbers](https://www.acefitness.org/resources/everyone/exercise-library/258/mountain-climbers/)의
양손 고정·앞뒤 다리 교체를, 월싯은
[NASM Wall Sits](https://www.nasm.org/resource-center/blog/training/wall-sits)의
양발 바닥·등 벽 지지 정적 자세를 한국어 단계로 직접 작성했다. 이 세 가지도
데이터셋 번역이 아니며 해당 기관의 사진이나 영상은 가져오지 않았다.

2026-10-06 동작 제작 과정에서 해머 컬의 중립 그립, 워킹 런지의 전진,
케틀벨 고블릿 스쿼트, 덤벨 후면 레이즈, 레그 컬·익스텐션의 패드 위치,
시티드 카프의 앞발 지지, 랜드마인 티바 로우, 평지 빠른 걷기와 트레드밀
러닝 설명을 수정했다. 오버헤드 프레스는 영상과 같은 **스탠딩 바벨 프레스**로
선택 변형을 명시했다. 이는 [ACE Standing Shoulder Press](https://www.acefitness.org/resources/everyone/exercise-library/71/standing-shoulder-press/)를
참고한 자체 설명이며, 반동 없는 반복은 우리가 선택한 strict 변형의 제약이다.
세부 교정 이력과 아직 남은 원본·변형 차이는
`output/exercise_visuals/production/specifications.json`에 보관한다.

원암 덤벨 로우는 [ACE Single-arm Row](https://www.acefitness.org/resources/everyone/exercise-library/126/single-arm-row/)의
한 손·같은 쪽 무릎을 벤치에 지지하는 변형으로 정정했다. 클로즈그립 벤치는
[ACE Close-grip Bench Press](https://www.acefitness.org/resources/everyone/exercise-library/311/close-grip-bench-press/)에
따라 손 위치를 어깨와 나란하게 명시했다. 아놀드 프레스는
[ACE의 Arnold Press 설명](https://www.acefitness.org/resources/pros/expert-articles/6467/fast-and-efficient-upper-body-training/)에
맞춰 손목만 비트는 문장을 팔의 회전으로 수정했다. 앉은 등받이 지지는 우리가
선택한 원본 텍스트의 변형이며, 해당 ACE 글이 앉은 자세를 지정한 것은 아니다.

프런트 스쿼트는 [NSCA Coach 10.1의 프런트 랙 점검표](https://www.nsca.com/globalassets/education/nsca-coach/nsca-coach-10.1.pdf)의
어깨 바깥 그립·수평 위팔·전면 삼각근 지지에 따라 clean rack 변형을 명시했다.
영상 모델의 그립 폭과 손목 각도는 그 체형에 맞춘 값이며 개인의 가동 범위를
대신 판단하지 않는다. 트레이너는 앞어깨 지지와 손목·팔꿈치의 경로를 검수한다.

## 직접 제작한 동작 예시

케이블 크런치는 [ACE Certified News 2009년 8/9월호](https://contentcdn.eacefitness.com/cp/pdfs/CertifiedNews/AugSept09Cert.pdf)의
높은 풀리를 바라보는 무릎 로프 변형으로 정정했고, 편측 케이블 레이즈는 같은 자료의
낮은 풀리·반대 골반 시작·어깨 높이 끝점을 명시했다. 케이블 플라이는 중립 그립을
명시하되, NASM Crossover의 손 교차 경로와 가슴 앞에서 만나는 자체 변형을 구분한다.
AB 휠은 [NSCA TSAC Report 55](https://www.nsca.com/globalassets/education/tsac-report/tsac-report-55.pdf)의
허리 제어 원칙을 참고해 끝까지 몸을 펴도록 강제하는 문구를 삭제했다.

어시스트 풀업은 무릎 보조 패드, 펙덱은 세로 손잡이 중립 그립을
[Life Fitness의 공식 수행 설명](https://kb.cybexintl.com/Owners_Manuals/Strength/Life_Fitness_Insignia_Series_Owners_Manual_9481201_Rev_BE.pdf)과
대조했다. 리버스 펙덱의 엄지가 위인 중립 그립과 가슴 패드 지지는
[Schoenfeld 등의 원논문 동작 설명](https://bretcontreras.com/wp-content/uploads/Effect-of-hand-position-on-EMG-activity-of-the-posterior-shoulder-musculature-during-a-horizontal-abduction-exercise.pdf)에
따라 정정했다. 세 기구의 실제 앱 메타데이터도 머신으로 명시한다. 제조사 기구 치수나 이미지는 가져오지 않았다.

로잉 머신의 한국어 6단계는 [Concept2 Rowing Technique](https://www.concept2.com/training/rowing-technique)의
스트로크 순서와 지지점을 바탕으로 Setflow가 작성했다. 버피도
[NASM Burpees](https://www.nasm.org/resource-center/exercise-library/squat-thrust-burpees)의
푸시업·점프·굽힌 무릎 착지를 바탕으로 직접 작성한 단계다. 두 설명 모두 기존 MIT 번역을 붙인 것이 아니다.

프리처 컬과 라잉 익스텐션은 [EZ바 프리처 컬](https://www.muscleandstrength.com/exercises/ez-bar-preacher-curl.html)과
[EZ바 스컬 크러셔](https://www.muscleandstrength.com/exercises/ez-bar-skullcrusher.html)의 안쪽 손잡이 변형을 명시했다.
체스트 서포티드 로우는 [45도 중립 그립 덤벨 변형](https://www.muscleandstrength.com/node/48713),
디클라인 프레스는 [발을 고정하는 바벨 변형](https://www.muscleandstrength.com/exercises/decline-bench-press.html),
오버헤드 익스텐션은 [서서 한 팔로 하는 덤벨 변형](https://www.muscleandstrength.com/exercises/one-arm-dumbbell-extension.html)을 대조했다.
영상의 오른팔 시연과 자체 벤치 치수·각도는 개별 제작 선택이다.
백 익스텐션은 [NSCA의 45도 고관절 신전 분석](https://bretcontreras.com/wp-content/uploads/Are-All-Hip-Extension-Exercises-Created-Equal.pdf)의
중립 척추 변형을 선택했다. 해크 스쿼트는 [Fortis 공식 매뉴얼 25쪽](https://assets.kogan.com/files/usermanuals/FSLEGHCKSQA_UG_V1.1.pdf#page=25)의
등·어깨 패드와 발판 지지를 대조했다. 특정 제조사 형상이나 모두에게 같은 깊이를 지정하지 않는다.

줄넘기는 [Jump Rope Institute의 Basic Bounce](https://jumpropeinstitute.com/howto-htm/)에 맞춰 두 발을 가까이 두고,
손목으로 작은 원을 그리며 낮게 뛰고 발 앞부분으로 부드럽게 착지하도록 교정했다.

실내 자전거는 [Life Fitness의 안장 조절](https://support.lifefitness.com/hc/en-us/articles/42862231037335-How-to-Adjust-the-Seat-on-Your-Life-Fitness-Atmos-Upright-Bike)과
[페달 스트랩 안내](https://support.lifefitness.com/hc/en-us/articles/42862246498199-How-to-Adjust-the-Pedal-Straps-on-Your-Atmos-Cardio-Series-Bike)에 따라
내려서 조절하는 안장, 최대 다리 신전에서 남는 무릎 굽힘, 운동화와 발 앞부분 지지를 명시했다.
일립티컬은 [CSX 공식 매뉴얼](https://kb.cybexintl.com/Owners_Manuals/Cross_Trainer/OM_CSX_Club_Series_Cross_Trainer.pdf)의
전방 페달링·움직이는 양팔과 [고정 손잡이를 사용하는 승하차](https://support.lifefitness.com/hc/en-us/articles/42861901438359-How-to-Mount-and-Dismount-Your-Atmos-Elliptical-Safely)를 구분했다.
스텝밀은 [제조사 8G 매뉴얼의 유통사 미러](https://fitnessengros.dk/media/c8/82/f7/1670237019/Owners%20Manual%20G8.pdf?ts=1727943233)를 읽어
전방 사용·운동화·완전히 멈춘 뒤 하차를 명시했다. 회전 계단은 원본 Stairmaster의 두 페달 변형과 구분하며,
선택한 기구와 가벼운 손잡이 지지를 트레이너에게 검수받는다.

2026-10-06 설명과 실제 시안의 추가 대조에서 백 스쿼트는
[ACE Back Squat](https://www.acefitness.org/resources/everyone/exercise-library/11/back-squat/)의 등 위쪽 바 지지를 참고해
현재 하이바 변형·발바닥 전체 지지·고관절과 무릎의 움직임을 명시했다.
[RDL](https://www.acefitness.org/resources/everyone/exercise-library/317/romanian-deadlift/)은
허리에서 굽히는 대신 엉덩이를 뒤로 보내는 힌지와 서 있는 시작 자세 복귀를 설명한다.
바벨 바닥 브리지는 [ACE Hip Bridge](https://www.acefitness.org/resources/everyone/exercise-library/318/hip-bridge/)와
원본 `Barbell_Glute_Bridge`의 패드 설명을 대조해 바를 허리가 아닌 골반 앞에 두고
골반을 올리고 내리도록 수정했다. 기존 가슴 딥스는 원본 `Dips_-_Chest_Version`의
앞으로 기울이는 변형으로, 아래 공유 트라이셉스 딥스와 구분했다.

벤치 딥스는 [NASM Bench Dips](https://www.nasm.org/resource-center/exercise-library/bench-dips)의
굽힌 무릎 선택지에 맞춰 양발 바닥 지지와 벤치 가까운 엉덩이를 명시했다.
스트레이트암 풀다운은 [ACE의 케이블 설명](https://www.acefitness.org/resources/pros/expert-articles/5565/4-moves-to-help-you-master-the-pull-up/)을
참고해 팔꿈치를 반복해서 굽히는 로우가 아닌 어깨에서 당기는 경로로 설명한다.
작고 고정된 팔꿈치 굽힘과 직바는 현재 시안의 선택이며 모든 사람에게 같은 각도를 요구하지 않는다.

시티드 케이블 로우는 [ACE Certified News 인쇄 10쪽](https://contentcdn.eacefitness.com/cp/pdfs/CertifiedNews/AugSept09Cert.pdf#page=9)의
직바·벤치 선택지를 바탕으로 현재 **낮은 풀리·회내 직바** 변형을 명시해 직접 작성했다.
회내 그립과 발판 지지는 Setflow의 선택이다. 해당 ACE 글이 그립까지 지정했다고
표기하지 않고, 원본의 중립 V핸들과 ACE 48의 좁은 손잡이는 별도 변형으로 남긴다.
리버스 플라이도 [Muscle & Strength의 직접 수행 설명](https://www.muscleandstrength.com/exercises/bent-over-dumbbell-reverse-fly.html)을
읽어 현재 **서서 하는 중립 그립 덤벨 힌지**로 직접 작성했다. Mayo의 앉은 설명이나
원본 `Reverse_Flyes`의 인클라인 벤치 설명을 서서 하는 변형의 근거로 쓰지 않는다.
과거 파일의 검토 메모는 보존하고, 새로운 근거와 문장별 입력 해시는 제작 사양의
`guideCorrections`에 기록한다. 출처 차이 해결은 트레이너의 영상 승인과 별개다.

## 공유 카탈로그의 개별 수행 설명

공유 운동은 이름이나 별칭으로 기존 가이드를 재사용하지 않고 다음 exact UUID에
각각 한국어 4단계를 직접 작성했다. 원본 텍스트는
[free-exercise-db의 고정 커밋](https://github.com/yuhonas/free-exercise-db/tree/a859101d633a01c4a1a920d6a8ce41dabba0705f/exercises)에서
읽었고 공개 도메인 텍스트 출처를 별도로 표시한다. 기존 MIT 번역 문장이나 원본 미디어를
가져온 것이 아니다. 원본 텍스트만으로 확인한 리어 런지·트라이셉스 딥스를
공식 전문가 검수로 표시하지 않는다.

| Exact UUID | 선택한 수행법 | 직접 읽은 근거 |
|---|---|---|
| `bff7dff4-2b99-5357-b365-f10e1187cbb3` | 덤벨을 들고 앞으로 내딛은 뒤 서 있는 제자리로 복귀 | `Dumbbell_Lunges` · [ACE Forward Lunge](https://www.acefitness.org/resources/everyone/exercise-library/94/forward-lunge/)의 전진·복귀 경로 |
| `d1ecb818-0235-5e2f-9113-39be506aa98a` | 덤벨을 들고 뒤로 내딛은 뒤 제자리로 복귀 | `Dumbbell_Rear_Lunge` 원본의 정확한 후진 변형 |
| `823846f5-2414-58b7-911e-2d9397a28f49` | 앞발 전체를 플랫폼에 둔 시작·앞다리 지지로 올라서기·반대 발부터 내려오기 | `Dumbbell_Step_Ups` · [NSCA Module 3.2-5 Step-Up](https://www.nsca.com/contentassets/24f7e187e9aa4a588439c9612231c7fd/tsac-module-3.0--3.3.pdf#page=18) |
| `0f177240-029b-543a-be27-2e8ed0526bca` | 양손 덤벨·뒷발 벤치 지지 스플릿 스쿼트 | `Split_Squat_with_Dumbbells` · [NASM의 벤치·양손 덤벨 선택지](https://www.nasm.org/resource-center/exercise-library/bulgarian-split-squat) |
| `896189fc-30d9-51df-aa19-fd5ea7fa76eb` | 넓은 발·무릎 안쪽 양손 오버핸드 스모 데드리프트 | `Sumo_Deadlift` · [NSCA의 가까운 바 경로·무릎 추적 설명](https://www.nsca.com/education/articles/tsac-report/the-deadlift-and-its-application-to-overall-performance/) |
| `58acf002-4e6d-5e95-b252-cae16252cef8` | 작고 고정된 무릎 굽힘의 스티프레그 바벨 힌지 | `Stiff-Legged_Barbell_Deadlift` · [NSCA Module의 작은 무릎 굽힘](https://www.nsca.com/contentassets/24f7e187e9aa4a588439c9612231c7fd/tsac-module-3.0--3.3.pdf#page=18) |
| `3c358477-aeb3-5d78-a6aa-91c9fb6c81db` | 얼굴을 향하는 언더핸드 그립·반동 없는 친업 | [ACE Chin-ups](https://www.acefitness.org/resources/everyone/exercise-library/190/chin-ups/) |
| `dd9ea4cf-1bc9-56f6-b8e0-06b6ef5f7ebe` | 상체를 세우고 팔꿈치를 가까이 둔 평행봉 트라이셉스 딥스 | `Dips_-_Triceps_Version` 원본의 정확한 직립 변형 |

스텝업은 NSCA와 정확한 원본의 앞다리 지지 경로를 선택했다. ACE 28은 발·무릎 정렬과
반대 발부터 내려오는 순서에만 참고하며, 뒷발로 밀어 올라가는 해당 문장은 현재 시안의
추진 지침으로 채택하지 않았다. 스티프레그는 무릎을 억지로 잠그지 않고 RDL과 별도 ID로
유지한다. 런지 원본의 임의 보폭·무조건 무릎이 발끝을 넘지 않는 조건도 그대로 옮기지 않았다.
일측 시연은 각 설명에서 반대쪽도 반복하도록 안내한다.

Gym visual 미디어와 별개로 CC0 MakeHuman 인체에 자체 리그 동작·재질·근육 강조를
적용한 로컬 GIF를 `assets/exercise_visuals/<운동 ID>.gif`에 둔다. 제작 원본과 라이선스
근거는 `output/exercise_visuals/`에 보관한다. MPFB는 제작 도구이고 앱에 코드를 넣지 않는다.

`lib/data/exercise_visuals.dart`에 실제 완성 자산이 있는 정확한 ID만 등록한다.
같은 운동 부위·비슷한 이름으로 다른 동작을 대신 보여주지 않는다.
운동 선택 목록의 `수행 방법`, 일반·코칭·함께 운동의 각 운동 헤더에 있는 `수행 방법`,
기록 화면의 운동 메뉴에서도 현재 선택한 종목의 단계와 예시를 함께 연다.
검수 중인 예시는 `(데모)`로 표시한다. 붉은색은 운동 부위 안내이지 측정된 활성도가 아니다.

첫 배치는 정확한 ID 13개를 연결했다: `bodyweight_squat`, `pushup`, `bench`,
`dumbbell_bench`, `deadlift`, `romanian_deadlift`, `row`, `curl`,
`dumbbell_shoulder_press`, `lateral`, `calf_raise`, `plank`, `crunch`.
`calf_raise`는 기존 설명과 같은 어깨 패드 머신 동작이며, `plank`는 팔꿈치 정적
유지 자세다. 플랭크는 `isStaticPose: true`로 표시해 재생 버튼을 두지 않고
"자세를 유지하는 동작이에요"라고 안내한다.

2026-10-06 현재 같은 원칙으로 **88개 정확한 ID**까지 앱 자산을 연결했다.
기본 80종 전체와 공개 카탈로그의 별도 UUID 8종이다. 제조사별 머신·추가 종목
999개는 제작 대기 상태다. 플랭크·사이드 플랭크·월싯은
정적 유지 자세이고, 편측 운동에는 시연한 쪽과 지지하는 쪽을 표시한다.
영상·원본·시작/중간/정점 및 제작 검토 메모를 함께 담은 검수 자료의 경로와
생성 방법은 [운동 영상 제작 문서](exercise-visual-production.md)에 있다.
모든 시안은 별도 트레이너 검수 대기이며 파일 검사 통과가 승인을 대신하지 않는다.

뷰어는 첫 프레임으로 열리고 사용자가 재생을 눌러야 움직인다. 일시정지는 현재 프레임을
유지하며, 앱이 백그라운드로 가면 멈춘다. 애니메이션 줄이기를 켠 경우에도 정지 화면은
보이고, 명시적으로 누른 재생만 허용한다. 네트워크와 로그인은 필요 없다.
