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
