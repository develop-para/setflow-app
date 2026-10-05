# Setflow 운동 동작 시안

`lib/data/exercise_visuals.dart`에 등록된 정확한 운동 ID에만 연결하는 로컬 GIF다.
수행 방법을 열어 재생한 동안만 반복하고 처음에는 정지 화면으로 보인다.
게스트도 볼 수 있다. 트레이너 검수 전이므로 앱은 `(데모)`를 표시한다.

인체·피부·머리·리그·가중치 원본은 MakeHuman / MPFB의 CC0 그래픽 자산이다.
근육 체형의 추가 조형, 스포츠 브리프, 동작, 기구 메시, 부위 표시와 영상은
Setflow 제작물이다. MPFB 프로그램은 제작 도구로만 사용했고 앱에 포함하지 않는다.
GymVisual 이미지·GIF와 원본 운동 데이터셋의 사진은 포함하지 않는다.

인체 원본·출처·변형 타깃·해시는
`output/exercise_visuals/bodyweight_squat/v5/source-manifest.json`과 같은 폴더의
`README.md`, `third_party/MPFB-LICENSE.md`, `third_party/MPFB-ASSETS-CC0.txt`에 있다.
추가 종목은 `output/exercise_visuals/<exerciseId>/v1/`에 원본 Blender 장면,
관절·접촉·근육 표시 기록과 `media.json`의 파일 해시를 보관한다.
맨몸 스쿼트 `v6`는 기존 `v5` 동작의 384px 앱용 변환본이다.

붉은 부위는 주요 운동 부위를 안내하는 표면 표현이다. 근육 활성도 측정값이나
해부학적 근육 분할 데이터는 아니다. 이름이나 부위가 비슷한 다른 운동에 대체
연결하지 않는다. 기구 제조사별 모델도 별도로 제작·확인해야 한다.

제작·검토·등록 절차는 `docs/exercise-visual-production.md`에 있다.
