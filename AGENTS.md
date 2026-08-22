# Setflow — 코딩 에이전트 지침

이 파일은 사람이 아니라 **코딩 에이전트(Claude Code · Codex)가 읽는 규칙**이다.
Codex는 이 파일을, Claude Code는 `CLAUDE.md`가 이 파일을 임포트해서 읽는다.
짧게 유지할 것. 길어지면 읽히지 않는다. 배경 설명은 링크로 넘기고 여기엔 **지켜야 할 것만** 둔다.

파일을 고친 직후 (2초, 아키텍처 규칙만):

```sh
dart run tool/check_architecture.dart
```

작업을 마치기 전에 반드시:

```sh
dart format lib test && flutter analyze && flutter test
```

아래 규칙을 어기면 위 둘 다 **실패한다**. 실패 메시지에 위반 위치·이유·대안이 같이 나오므로
그대로 읽고 고칠 것. 규칙 정의는 `tool/architecture_rules.dart` 한 곳에 있다.

---

## 1. 벤더(Supabase) 격리 — 가장 자주 어기는 규칙

이 앱은 나중에 자체 서버(AWS)로 옮긴다. 그래서 **Supabase 타입은 어댑터 밖으로 나가면 안 된다.**

```dart
// ❌ 절대 금지 — screens/ widgets/ app_state.dart 에서
import 'package:supabase_flutter/supabase_flutter.dart';
final user = Supabase.instance.client.auth.currentUser;

// ✅ 포트를 통해서만
import '../services/auth_service.dart';
final signedIn = Auth.instance.hasAuthenticatedUser;
```

- 인증은 `Auth.instance` (`AuthService` 포트). `SupabaseAuthService`를 직접 부르지 말 것.
- 데이터는 `AppRepository` / `BusinessRepository` / `CommunityRepository` /
  `RoutineCatalogRepository` 포트를 통해서만.
- 새 기능은 **포트에 도메인 동사로 먼저 선언**하고 (`createConsultation()`,
  `listMyConsultations()`) 그 다음 어댑터에 구현한다. 화면이 테이블·컬럼을 알면 안 된다.
- `package:supabase`를 import해도 되는 파일은 `lib/main.dart`와 `lib/data/supabase_*.dart`,
  `lib/services/supabase_auth_service.dart` 뿐이다.

배경: `docs/backend-portability.md`

## 2. 서버 작업은 RPC가 기본, 엣지 펑션은 예외

- 조회·저장 → 레포지토리에서 PostgREST 직접
- 트랜잭션·비즈니스 규칙 → **Postgres 함수(RPC)** (`supabase/migrations/`에 SQL로)
- 엣지 펑션 → 외부 API 호출(결제·SMS·푸시)이나 웹훅처럼 **다른 방법이 없을 때만**.
  사용자 핵심 동작(로그인·기록 저장 등)의 경로에 두지 말 것. 과거에 회원가입을 엣지 펑션 뒤에
  뒀다가 통째로 막힌 적이 있다.

## 3. 스토리지는 경로만 저장

```dart
// ❌ DB에 렌더링된 URL을 넣지 말 것 — 버킷 이전이 데이터 마이그레이션이 된다
'image_url': bucket.getPublicUrl(path)

// ✅ 경로를 저장하고, 읽을 때 URL로 바꾼다
'image_url': storagePath
```

`getPublicUrl` / `createSignedUrl`은 레포지토리(어댑터) 안에서 **읽는 시점에만** 호출한다.

## 4. 인증은 게스트 우선 — 로그인 벽을 세우지 말 것

앱은 계정 없이도 전부 쓸 수 있어야 한다. **운동 기록·루틴·캘린더·통계는 절대 로그인 뒤로 숨기지 않는다.**
서버가 필요한 행동에만, **그 행동을 하는 순간** 로그인을 요청한다.

```dart
if (!await requireSignIn(context, reason: AuthReason.community)) return;
if (!context.mounted) return;
// ... 여기서부터 계정이 필요한 작업
```

새 이유가 필요하면 `AuthReason`에 항목을 추가한다(제목 + 왜 필요한지 한 줄).

**회원과 트레이너는 정책이 다르다.**
- 일반 회원: 가입 즉시 사용. 심사 없음.
- 트레이너: 가입은 즉시 되지만 **관리자 승인 후에야** 트레이너 화면이 열린다.
  승인 여부의 진실은 서버의 `BusinessAccess.availableRoles`에 `UserRole.trainer`가 있느냐다
  (신청서 상태가 아니다). 트레이너 기능 앞에서는 `requireSignIn`이 아니라
  **`requireProAccess(context)`** 를 쓴다 — 미신청·심사중·반려를 각각 안내한다.

비밀번호는 `AuthPasswordPolicy` 한 곳에서만 검증한다(화면마다 `length < 8`을 새로 쓰지 말 것).
재설정·재전송·변경 플로우와 대시보드 설정: `docs/auth.md`

**게스트가 기록한 것은 기기에 남는다.** 로그인 안 한 상태의 저장을 건너뛰지 말 것 —
`saveUnclaimed`/`loadUnclaimed`로 소유자 없이 보관하고, 계정에 넣는 건 사용자가 "가져오기"를
누를 때만(`adoptGuestSnapshot`). 먼저 로그인했다는 사실은 소유의 증거가 아니다.

## 5. 숫자는 그 자리에서 타이핑하지 않는다

세트의 무게·횟수·휴식(유산소는 시간·거리·RPE)은 **다이얼 시트로만** 고친다. 박스 자체가
버튼이다 — `_DialValueField`(읽기 전용, 포커스를 받지 않음)를 탭하면 `_showNumberDial`이 열리고
시트의 "적용"이 유일한 저장 지점이다. 값 옆에 별도 버튼을 달지 말 것.

인라인 편집을 막는 이유: 운동 중에는 화면 잠김·시스템 백·라우트 pop으로 편집이 끝나서,
컨트롤러에 남은 숫자가 저장된 것처럼 보이고 실제로는 사라진다. 그래도 그 자리에서 타이핑해야
하는 필드라면 `onSubmitted`만으로 끝내지 말고 포커스를 잃을 때 커밋하는 리스너를
**`initState`에서** 붙일 것.

## 6. 디자인 — 옐로우 브랜드와 상태색

- 브랜드 기본은 **Supernova 옐로우 `#FFCA10` + 웜 잉크 + 화이트**다. 성공·경고·오류·안내와
  역할/운동 카테고리는 `SetflowColors` · `SetflowSemanticColors`의 상태색을 쓴다. 화면에 임의의
  색상 상수를 흩뿌리지 말고 먼저 토큰에서 고른다.
- `theme.colorScheme.primary`는 라이트·다크 모두 브랜드 옐로우다. 그 위 전경색은 반드시
  `onPrimary`를 쓴다. **옐로우 위 흰색 텍스트는 대비가 부족하므로 금지**한다.
- 설치 아이콘과 OS 스플래시는 `SetflowMark`의 3단 Rep Stack을 쓴다. 원본 PNG는
  `test/tools/generate_brand_assets_test.dart`로 생성하고 launcher/splash 생성기를 이어서 실행한다.
- 일반 기능 아이콘에는 장식 목적의 배경을 남발하지 않는다. 의미·상태를 전달하거나 브랜드
  진입점을 표시할 때만 토큰 색상의 배경을 쓴다.
- 아이콘은 `SetflowIcons`에서 고른다. `Icons.*`를 직접 쓰지 말고, 없으면 `theme/icons.dart`에
  개념을 추가한다(한 패밀리: Material rounded, 아웃라인=평소 / 채움=선택).
- **전역 메시지는 화면 위쪽에 띄운다.** 하단은 엄지·기록 디스크·세트 행의 자리라 거기 뜬 메시지는
  방금 고친 행을 가린다. 토스트는 `AppSnackbar`(상단 30%)로만, `ScaffoldMessenger`를 직접 부르지 말 것.
  휴식 타이머도 헤더 아래 슬림 바다.

## 7. 테스트

- 화면·흐름을 바꾸면 해당 위젯 테스트도 같이 고친다. 테스트를 지우거나 `skip` 하지 말 것.
- 무한 반복 애니메이션이 떠 있으면 `pumpAndSettle()`이 영원히 안 끝난다. 명시적 `pump(duration)`을 쓸 것.
- 규칙을 새로 만들면 `tool/architecture_rules.dart`의 `architectureRules`에 한 줄 추가한다.
  문서에만 적으면 지켜지지 않는다. (테스트와 CLI가 그 목록을 함께 읽는다.)

---

규칙이 정말 막고 있는 일을 해야 한다면 그건 규칙이 작동한 것이다.
`tool/architecture_rules.dart`의 `allow` 목록에 파일을 추가하되 **그 커밋 메시지에 이유를 남길 것.**
