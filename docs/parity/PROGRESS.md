# P1 온보딩 구현 — 하네스 진행 원장

**목표(루프 종료 조건)**: missing-flows P1 (#1~#3) 구현 + 각 `flutter analyze` 통과.
**제약**: 운영 프로젝트. 기존 셸/멤버/사업자 화면 미변경. 온보딩 진입점(`welcome_screen.dart`)만 확장. 신규 화면은 추가.

## 반복 계획

| # | 플로우 | 대상 | 검증 | 상태 |
|---|---|---|---|---|
| 1 | 회원 다단계 온보딩 (신체 프로필 + 가입 단계 추가) | `MemberSetupScreen` | `flutter analyze` ✅ No issues | ✅ 완료 |
| 2 | 트레이너 심사 (서류→대기→반려/승인) | `BusinessSetupScreen(trainer)` | `flutter analyze` ✅ No issues | ✅ 완료 |
| 3 | 헬스장 심사 + 홈택스 | `BusinessSetupScreen(gym)` | `flutter analyze` ✅ No issues | ✅ 완료 |

**🎯 P1 목표 달성** — 세 온보딩 플로우 모두 구현 + analyze 통과. `welcome_screen.dart` 522 → 1305줄.

## 근거 매핑 (React → Flutter)

- #1: `GoalsPage`(있음) + `BodyProfilePage`(추가) + `AuthSignupPage`(추가)
- #2: `TrainerRegisterPage`(있음) + `TrainerDocsUploadPage` + `TrainerPendingPage` + `TrainerRejectedPage` + `TrainerCompletePage`
- #3: `GymRegisterPage`(있음) + `GymOnboardingDocsPage` + `GymOnboardingHometaxPage` + `GymOnboardingCompletePage`

## 로그

- 시작: P1 확정, 하네스 세팅 완료. 반복 1 착수.
- 반복 1 (회원 온보딩): `MemberSetupScreen`에 신체 프로필·가입 단계 추가 → `flutter analyze` No issues ✅
- 반복 2 (트레이너 심사): `BusinessSetupScreen` trainer 경로 `_TrainerStep` 다단계(등록→서류→대기→승인/반려→완료) → analyze No issues ✅
- 반복 3 (헬스장 심사): gym 경로 `_GymStep` 다단계(등록→서류→홈택스→완료) → analyze No issues ✅
- **최종 통합 검증**: `flutter build web` → `√ Built build\web` (exit 0) ✅

## 결과 (P1)

- P1 완료. `welcome_screen.dart` 522 → 1305줄. 기존 셸/멤버/사업자 화면 무변경.
- 커밋 `251204d` → `develop-para/setflow-app` main 푸시 완료.

---

# P2 — 사업자 운영 핵심 (진행 중)

**목표**: missing-flows P2 (#4~#9) 구현 + 각 `flutter analyze` 통과.
**제약**: 기존 사업자 화면 렌더링 로직 보존. 신규 상세 화면 추가 + 기존 리스트에서 진입(onTap) 연결만.
**대부분 `business_screens.dart` 편집 → 순차 실행(충돌 방지).**

| # | 플로우 | 대상 | 상태 |
|---|---|---|---|
| 4 | 회원 상세 드릴다운(캘린더/루틴/커뮤니티) | `PeoplePage._showMember` + `member_detail_screens.dart` | ✅ analyze 통과 |
| 5 | 정산 세부(환불/트레이너별) | `SettlementPage` + `settlement_detail_screens.dart` | ✅ analyze 통과 |
| 6 | 트레이너 성과/루틴 통계 | `RoutineManagerPage`/`TrainerManagementPage` + `stats_detail_screens.dart` | ✅ analyze 통과 |
| 7 | 사업자 설정 하위(요금제/알림/탈퇴/프로필) | `_BusinessHeader` + `business_settings_screens.dart` | ✅ analyze 통과 |
| 8 | 상담 리타겟 | `ConsultationQueuePage` + `consultation_retarget_screen.dart` | ✅ analyze 통과 |
| 9 | 워크스페이스(PC 뷰) | `_BusinessHeader` + `workspace_screen.dart` | ✅ analyze 통과 |

**🎯 P2 목표 달성** — 6개 플로우 모두 구현 + 각 analyze 통과. 신규 파일 6개(member_detail/settlement_detail/stats_detail/business_settings/consultation_retarget/workspace), `business_screens.dart`는 진입점만 추가(기존 렌더링 보존). 웹 빌드 ✅. 커밋 `cea0072` 푸시됨.

---

# P3 — 운영자 백오피스 세부 (진행 중)

**목표**: missing-flows P3 (#10~#13) 구현 + 각 `flutter analyze` 통과.
**제약**: 기존 화면 렌더링 보존. 신규 화면 + 진입점만 추가.

| # | 플로우 | 대상 | 상태 |
|---|---|---|---|
| 10 | 정산 수수료/최종 확정 | `SettlementPage`(admin) + `settlement_detail_screens.dart` | ✅ analyze 통과 |
| 11 | 시스템 관리 개별 화면(랭킹/OCR/요금제/금칙어/로그) | `AdminHome` + `admin_system_screens.dart` | ✅ analyze 통과 |
| 12 | 콘텐츠 심사 세분화(루틴/신고/제재/미성년) | `AdminReviewPage` + `admin_content_screens.dart` | ✅ analyze 통과 |
| 13 | 스플래시 화면 | `main.dart` `RootScreen` + `splash_screen.dart` | ✅ analyze 통과 |

**🎯 P3 목표 달성** — 4개 플로우 구현 + 각 analyze 통과. 신규 파일 3개(admin_system/admin_content/splash), `main.dart`는 스플래시 1회 게이트만 추가(역할 라우팅 보존), `SettlementPage`/`AdminHome`/`AdminReviewPage`는 진입점만 추가.

---

## 최종 요약

| 단계 | 플로우 | 상태 |
|---|---|---|
| P1 | 온보딩 3종 | ✅ 커밋 `251204d` |
| P2 | 사업자 운영 6종 | ✅ 커밋 `cea0072` |
| P3 | 운영자 백오피스 4종 | ✅ (커밋 예정) |

전 구간 하네스 루프: executor 구현 → `flutter analyze` 게이트(13/13 No issues) → 원장 기록. 기존 화면 렌더링 보존, 신규 화면 추가 + 진입점 연결 방식.

---

# 🚀 내일 재개 (2026-07-23 시작 지점)

## 확정된 것
- **목표 확정**: [`GOAL.md`](./GOAL.md) — 실서비스(Airbnb·Uber·Toss급) 품질. **Option C**(프런트 프로덕션 퀄리티 + 교체가능 데이터 어댑터층, Supabase는 나중 단계).
- **디자인 시스템 확정**: [`../design/design-system.md`](../design/design-system.md) — 라이트/다크 semantic 토큰, 타이포/스페이싱/라운드/엘리베이션/모션, 컴포넌트 스펙 전부 숫자로.
- **브랜드 토큰**: primary `#FFCA10`, ink `#241F20` (React `index.css`와 일치, 유지).

## 다음 액션 — **Phase B부터 시작** (여기서 이어서)
1. `lib/theme/tokens.dart` 생성 — design-system.md의 semantic 토큰 코드화 (`SetflowColors` 하위호환 유지).
2. `lib/theme.dart` 재구성 — ColorScheme/TextTheme/컴포넌트 테마를 스펙대로. **기존 클래스명·시그니처 유지, 값/스타일만 업그레이드**(전 화면 일괄 깨짐 방지).
3. `lib/widgets/common.dart` 확장 — `AppButton`/`AppTextField`/`LoadingState`/`EmptyState`/`ErrorState`/`AppSnackbar` 추가.
4. 게이트: `flutter analyze` + `flutter build web`.
그다음 Phase C(데이터 어댑터층 `lib/data/**`) → Phase D(화면군 6개 순차) → Phase E(React UX 이식) → Phase F(테스트).

## 하네스 실행 방식 (그대로 유지)
- 각 반복: executor 위임 → `flutter analyze` 게이트 → 이 원장 기록 → 단계말 웹빌드+커밋/푸시.
- 운영 규칙: 하위호환 유지, 점진 적용, 역할 라우팅 보존.

## 재개 트리거 문장 (내일 붙여넣기용)
> "GOAL.md / design-system.md 기준으로 Phase B(디자인 시스템 파운데이션)부터 루프 이어서 진행해줘"

## 상태 요약
- 저장소: `develop-para/setflow-app` main, 최신 커밋 이 문서 포함 푸시됨.
- 웹 실행: `flutter run -d chrome` 정상. Windows 데스크톱 빌드는 VS `vcruntimed.lib` 손상으로 보류(웹으로 개발).
- React 레퍼런스: `C:\Users\SIMJAE\Downloads\setflow` (src/App.tsx 라우트 112개, src/index.css 토큰).

---

# Phase B · C — 프로덕션 파운데이션 (2026-07-23)

## Phase B 디자인 시스템 ✅

- `lib/theme/tokens.dart`: 라이트/다크 semantic 컬러, 간격, 라운드, 모션, 그림자 토큰 구현.
- `lib/theme.dart`: Material 3 `ColorScheme`, 타이포 스케일, 버튼·입력·카드·칩·내비게이션·시트·다이얼로그 테마 재구성.
- `lib/widgets/common.dart`: 기존 API를 유지하면서 `AppButton`, `AppTextField`, `LoadingState`, `EmptyState`, `ErrorState`, `AppSnackbar` 추가.
- 기존 `SetflowColors`, `SetflowCard`, `PrimaryButton`, `showMessage` 호출부 하위호환 유지.
- 라이트/다크 모바일 뷰포트(432×900) 및 브라우저 콘솔 검증 완료.

## Phase C 데이터 어댑터층 ✅

- `AppRepository` 인터페이스로 앱 상태 저장소 경계 분리.
- `MemoryAppRepository`: 테스트 및 저장소 초기화 실패 시 안전한 폴백.
- `HiveAppRepository`: Android/iOS/Web 로컬 영속 구현. Supabase 전환 시 이 구현만 교체 가능.
- `AppSnapshotCodec`: 역할, 테마, 단위, 휴식 타이머 기본값, 운동 세션·세트 완료 상태, 루틴 JSON 스키마 v1 직렬화.
- `AppState`: 250ms 디바운스 자동 저장 및 앱 시작 시 복원 연결.
- 실제 웹 IndexedDB에서 역할·다크모드 설정 후 새로고침 복원 검증 완료.

## 게이트

- `flutter analyze`: No issues.
- `flutter test`: 7개 통과(스냅샷 왕복·저장소 복원 테스트 포함).
- `flutter build web`: 성공.

## 다음 재개 지점

**Phase D-1 온보딩 화면군 프로덕션 적용**부터 시작한다.

1. Welcome/member setup/business setup/splash에 신규 토큰과 공용 컴포넌트 적용.
2. 폼 검증·인라인 오류, 로딩·성공·실패 상태, 햅틱과 전환 모션 보강.
3. 화면별 위젯 테스트 추가 후 analyze/test/build 게이트.

---

# Phase D-1 — 온보딩 화면군 프로덕션 적용 ✅

_완료일: 2026-07-23_

## 적용 범위

- 스플래시: 디자인 토큰, 접근성 live region, 저장소 초기화 로딩 표시 적용.
- 역할 선택: 기존 역할별 진입 플로우와 카드 인터랙션 회귀 검증.
- 회원 온보딩: 4단계 진행 표시, 단계별 뒤로가기, 신체정보 숫자 입력 제한 및 범위 검증.
- 회원 가입: 소셜·이메일 제출 로딩, 성공 스낵바, 실패 인라인 배너 구조 추가.
- 트레이너 등록: 이름·자격증 번호 검증, 서류 제출 로딩, 승인·반려·재제출 피드백.
- 센터 등록: 사업자번호 10자리 검증, 서류 제출 로딩, 홈택스 인증 상태 및 성공 피드백.
- 공통: 48dp 이상 터치 영역, semantic 진행 단계, 표준 260ms 전환 모션 적용.

## 검증

- `flutter analyze`: No issues.
- `flutter test`: 9개 통과.
- 신규 `onboarding_test.dart`: 회원 신체정보 오류, 센터 사업자번호 오류, 서류 제출 로딩, 홈택스 성공 흐름 검증.
- `flutter build web`: 성공.
- 432×900 모바일 뷰포트에서 회원·센터 온보딩 및 브라우저 콘솔 확인 완료.

## 다음 재개 지점

**Phase D-2 회원 코어 화면군**부터 시작한다.

1. 캘린더·데일리 운동·세트 편집·운동 라이브러리에 신규 토큰과 공용 상태 컴포넌트 적용.
2. 빈 날짜, 로딩, 저장 실패, 운동 삭제 확인, 세트 입력 검증을 실제 흐름으로 구현.
3. 휴식 타이머를 화면 밖에서도 유지되는 전역 오버레이로 보강.
4. 핵심 기록 플로우 위젯 테스트 후 analyze/test/build/모바일 게이트.

---

# Phase D-2 — 회원 코어 화면군 프로덕션 적용 ✅

_완료일: 2026-07-23_

## 적용 범위

- 캘린더: 날짜 기록 삭제 확인, 복사·삭제 성공 피드백 적용.
- 일일 운동: 빈 날짜 CTA, 저장 실패 안내와 재시도, 운동 삭제 확인 적용.
- 운동 라이브러리: 공용 검색 입력, 검색 결과 없음·초기화 상태, 추가 완료 피드백 적용.
- 세트 편집: 무게·횟수 직접 입력, 0~999 범위 검증, 스와이프 삭제 확인, 삭제 후 세트 번호 재정렬 적용.
- 휴식 타이머: 라우트를 이동해도 유지되는 전역 오버레이, 진행률·30초 연장·종료 제어 적용.
- 데이터 상태: 운동·세트 삭제가 저장소 어댑터를 통해 영속되도록 `AppState` 작업 메서드 보강.

## 검증

- `flutter analyze`: No issues.
- `flutter test`: 12개 통과.
- 신규 `workout_core_test.dart`: 라이브러리 빈 검색 복구, 세트 직접 입력 검증·삭제 확인, 라우트 위 전역 휴식 타이머 검증.
- `flutter build web`: 성공, Wasm dry run 성공.
- 432×900 모바일 뷰포트에서 회원 온보딩·캘린더 렌더링 및 브라우저 오류 없음 확인.

## 다음 재개 지점

**Phase D-3 회원 소셜 화면군**부터 시작한다.

1. 동기부여 피드·게시물 상세·작성 흐름에 공용 상태 컴포넌트와 입력 검증 적용.
2. 전문가 루틴 탐색·상세·내 루틴 저장 흐름의 로딩·빈 상태·실패 피드백 보강.
3. 코칭 요청·상담 흐름의 상태 전이와 확인 다이얼로그 구현.
4. 핵심 소셜·루틴 플로우 위젯 테스트 후 analyze/test/build/모바일 게이트.

---

# Phase D-3 — 회원 소셜 화면군 프로덕션 적용 ✅

_완료일: 2026-07-23_

## 적용 범위

- 소셜 데이터: 게시물·댓글·상담 모델을 `AppRepository` 스냅샷에 포함하고 스키마 v2로 확장.
- 하위 호환: 기존 스키마 v1의 역할·운동·루틴 데이터를 그대로 복원하고 새 소셜 데이터만 기본값으로 보강.
- 동기부여: React 기준 3열 피드, 최신·좋아요·댓글 정렬, 게시물 상세, 좋아요, 댓글, 신고 확인 구현.
- 게시물 작성: 사진 상태, 스타일, 날짜·시간·위치·루틴 오버레이, 기록 첨부, 외부 공유 안내, 입력 검증·제출 로딩 구현.
- 내 루틴: 생성 폼 검증, 무료 플랜 4개 한도, 적용 피드백, 삭제 확인 구현.
- 전문가 루틴: 검색·필터·정렬·빈 결과 복구, 별도 상세 화면, 운동 구성·후기, 중복·한도 구분 저장, 상담 진입 구현.
- 코칭: 상담 목록 상태 배지, 트레이너·목표·경험·질문 입력 검증, 답변 대기·상담 완료·코칭 중 상태 전이 구현.
- 결제·피드백: 구매 확인 다이얼로그, 에스크로 안내, 만족도 입력과 영속 저장을 상담 상세에 통합.

## 검증

- `flutter analyze`: No issues.
- `flutter test`: 19개 통과.
- 신규 `member_social_test.dart`: 게시물 검증·저장, 댓글·좋아요, 상담 신청, 코칭 전환, 루틴 검색 복구·중복·저장한도 검증.
- `app_repository_test.dart`: 스키마 v2 소셜 데이터 왕복 및 스키마 v1 하위 호환 검증.
- `flutter build web`: 성공, Wasm dry run 성공.
- 432×900 모바일 뷰포트에서 전문가 루틴·상세, 3열 피드·게시물 상세, 코칭 목록 및 브라우저 오류 없음 확인.

## 다음 재개 지점

**Phase D-4 사업자 셸·홈 화면군**부터 시작한다.

1. 트레이너·센터·운영자 셸과 역할별 홈의 디자인 토큰·정보 위계 정리.
2. KPI·할 일·알림 카드의 로딩·빈 상태·오류·새로고침 피드백 구현.
3. 역할별 주요 상세 화면 진입과 내비게이션 회귀 검증.
4. 핵심 사업자 홈 위젯 테스트 후 analyze/test/build/모바일 게이트.

---

# Phase D-4 — 사업자 셸·홈 화면군 프로덕션 적용 ✅

_완료일: 2026-07-23_

## 적용 범위

- 공통 셸: 트레이너·센터·운영자 역할별 4탭 내비게이션, 선택 아이콘, 햅틱 피드백 적용.
- 공통 헤더: 새로고침·알림·더보기로 동작을 정리하고 운영 메뉴, PC 워크스페이스, 설정 진입을 통합.
- 운영 상태: 새로고침 로딩 표시, 성공 피드백, 저장소 오류 배너와 재시도 동작 구현.
- 알림: 역할 홈에서 확인 가능한 알림 바텀시트, 개별 스와이프 처리, 모두 읽음, 빈 상태 구현.
- 트레이너 홈: 수익·관리 회원·피드백 KPI, 마감 업무, 상담 수신함, 루틴 성과 진입 연결.
- 센터 홈: 회원·매출·트레이너·상담 KPI, 회원 배정, 피드백 이행률, 트레이너 관리 진입 연결.
- 운영자 홈: 사용자·코칭·심사·신고 KPI, 긴급 신고와 사업자 심사 우선 업무, SLA·시스템 상태·관리 진입 연결.
- 반응형: 432px 모바일 폭과 접근성 글자 크기에서도 인증 카드와 알림 문장이 넘치지 않도록 유연한 레이아웃 적용.

## 검증

- `flutter analyze`: No issues.
- `flutter test`: 24개 통과.
- 신규 `business_home_test.dart`: 역할별 셸, 새로고침, 알림 빈 상태, 상담 진입, 역할별 운영 정보, 저장 실패 재시도 검증.
- `flutter build web`: 성공, Wasm dry run 성공.
- 432×900 모바일 뷰포트에서 트레이너 등록부터 홈 진입, 알림 시트, 상담 수신함 이동 및 브라우저 오류 없음 확인.

## 다음 재개 지점

**Phase D-5 사업자 상세 화면군**부터 시작한다.

1. 트레이너 회원 관리·루틴 배포·상담 처리·정산 상세의 실데이터 상태와 작업 완료 피드백 보강.
2. 센터 회원 배정·트레이너 관리·매출·정산 상세의 검색·필터·빈 상태·오류 처리 구현.
3. 운영자 사용자·심사·신고·시스템 관리 상세의 확인 절차와 감사 로그 UX 구현.
4. 역할별 주요 업무 E2E 위젯 테스트 후 analyze/test/build/모바일 게이트.
