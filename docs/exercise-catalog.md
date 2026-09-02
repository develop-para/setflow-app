# 운동 카탈로그

## 현재 구성

- 앱 번들에는 오프라인·첫 실행용 검수 목록 80개가 남아 있다.
- 공용 원본은 Supabase `public.master_exercises`다.
- 앱은 기기 캐시를 먼저 합친 뒤 서버의 `list_master_exercises` RPC를 안정적인
  `(name, id)` 커서로 500개씩 끝까지 읽는다. 이 네트워크 작업은 계정 스냅샷이나
  시작 화면을 막지 않는다.
- 서버 오류나 오프라인 상태에서는 마지막 성공 캐시와 번들 80개를 계속 쓴다.
- 자동 추천은 안전 특성이 검수된 번들 목록만 사용한다. DB 운동은 사용자가 직접
  선택할 수 있지만 특성이 없는 종목을 앱이 임의로 추천하지 않는다.

## 공개 데이터 출처

2026-08-31에 `yuhonas/free-exercise-db`의 아래 고정 스냅샷을 적재했다.

- revision: `a859101d633a01c4a1a920d6a8ce41dabba0705f`
- JSON SHA-256: `5bb747e3fc658f095a60dcbf6d53c96627acdcc6ffb6fffde86f7e26995d40bf`
- 고유 운동: 876개
- 라이선스: Unlicense / Public Domain
- 원본: <https://github.com/yuhonas/free-exercise-db>
- 라이선스: <https://github.com/yuhonas/free-exercise-db/blob/main/LICENSE.md>

운동 이미지 경로는 데이터에 있지만 개별 이미지 권리 출처가 충분히 명확하지 않아
가져오지 않았다. 텍스트 메타데이터(이름, 부위, 기구, 난이도, 수행 단계)만 DB에
저장한다.

원본 876개에는 원본 ID와 동작 설명을 대조해 정리한 한글 표시명을 모두 붙인다. 번역 원본은
`tool/data/free_exercise_db_names_ko_part_*.json` 세 파일이며, DB의 `name`과
`name_ko`에는 한글명, `name_en`에는 검색·대조용 원문을 보존한다. import 도구는
원본 ID와 한글명 ID가 정확히 일치하고 한글명이 876개 모두 고유한지 확인한 뒤에만
DB를 바꾼다.

## 근육 그림 출처

운동 사진·GIF는 출처 저장소의 메타데이터만으로 개별 저작권을 확정할 수 없어
사용하지 않는다. 대신 `flutter_body_atlas` 0.2.1의 인체 앞·뒤 SVG에서 원본의
`primaryMuscles`에 해당하는 주동근을 강조하고 보조근은 바로 옆 한글 문구로 알린다.
목·능형근·척추기립근처럼 SVG에 정확한 경로가 없는 부위는 비슷한 근육을 임의로
칠하지 않고 글자로만 알린다. 유산소도 원본에 근육 정보가 있으면 같은 원칙으로
표시하고, 정보가 없는 번들 유산소만 일반 유산소 아이콘을 쓴다.

- 패키지 코드: BSD-3-Clause, <https://github.com/kit-g/flutter-body-atlas>
- 인체 SVG 원작: Ryan Graves, Human Anatomy Component System
- 원작: <https://www.figma.com/community/file/1320468164820924031/human-anatomy-component-system>
- SVG 라이선스: CC BY 4.0, <https://creativecommons.org/licenses/by/4.0/>
- 패키지 변경 사항: SVG 구조·element ID를 근육 선택용으로 수정·최적화
- Setflow 변경 사항: 원본 SVG 파일은 바꾸지 않고 주동근 경로의 색만 바꿈

이 귀속 문구는 앱의 `설정 > 오픈소스 및 이미지 출처`에서도 확인할 수 있다.

## 검색과 분류

- 원본의 13개 기구 값을 안정된 `equipment_key`로 정규화한다.
- 기구 값이 없는 77개는 맨몸으로 추측하지 않고 `unspecified`로 둔다.
- 목 운동 8개는 등이나 어깨로 잘못 합치지 않고 `기타` 부위로 둔다.
- 영문 이름과 함께 부위·기구·주요 동작의 검증 가능한 한국어 별칭을 생성한다.
  완성된 한국어 운동명을 기계 번역해 사실처럼 저장하지 않는다.
- DB 검색은 `simple` FTS GIN과 trigram GIN을 함께 갖고, 앱 검색은 여러 단어가
  이름·부위·기구에 나뉘어 있어도 모두 일치시킨다.
- 번들 운동과 확실히 같은 56개 원본 행은 crosswalk로 기존 앱 ID를 유지한다.
  따라서 과거 기록은 이어지고, UI에는 같은 운동의 한글/영문 중복이 나타나지
  않으며, DB UUID는 루틴 외래 키용 별도 값으로 보존한다.

따라서 현재 값은 “876개 실제 DB 운동”이며, 번들 전용 운동과 중복을 합친 앱
선택 목록은 900개다. 운동 개수를 수천 개로 부풀려 표시하지 않는다. 대신
한·영문과 기구·부위 별칭을 합친 검색어는 수천 개이고, 스키마는 다음 공개
소스를 권리·귀속 검토 후 같은 방식으로 추가할 수 있다.

## 재적재

스키마 migration은 외부 네트워크 상태에 의존하면 안 되므로 JSON 다운로드는
migration 트랜잭션 밖에서 한다. `import_free_exercise_db_catalog` 함수가 revision,
SHA-256, 876개 고유 ID를 다시 확인한 뒤 결정적 UUID로 일괄 upsert하고 누락 행은
비활성화한다.

운영자는 service-role 또는 Supabase secret key를 환경 변수로만 전달하고 버전 관리된
import 도구를 실행한다. 도구는 원본 **raw bytes**의 SHA-256, 행 수, 고유 ID를 먼저
확인하므로 다른 payload에 고정 해시 문자열만 붙여 넣을 수 없다.

```powershell
$env:SUPABASE_URL='https://<project-ref>.supabase.co'
$env:SUPABASE_SERVICE_ROLE_KEY='<service-role-key>'
dart run tool/import_exercise_catalog.dart
```

DB를 변경하지 않고 고정 원본의 hash와 행 수만 다시 확인하려면
`dart run tool/import_exercise_catalog.dart --verify-only`를 사용한다.

도구는 다음 순서로 동작한다.

1. 고정 revision의 `dist/exercises.json`을 다운로드한다.
2. 위 SHA-256과 행 수를 로컬에서 확인한다.
3. 검증한 JSON payload, revision, SHA-256과 버전 관리된 한글명 876개를
   `public.import_localized_free_exercise_db_catalog(...)`에 전달한다. 원본 적재와
   한글명 적용은 같은 트랜잭션이라 중간 영문 상태가 노출되지 않는다.
4. 응답 뒤 `master_exercises`의 활성 876개 `source_id`, 한글 표시명, 영문 원문,
   alias와 주동근·보조근 배열까지 다시 읽어 검증한다. DB provenance는
   `exercise_catalog_imports`에 남는다.

이 import 함수는 `service_role`에만 실행 권한이 있고, 앱의 anon/authenticated
키는 공용 활성 행 조회만 가능하다.
