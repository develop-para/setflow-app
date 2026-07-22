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

## 결과

- P1 완료. `welcome_screen.dart` 522 → 1305줄. 기존 셸/멤버/사업자 화면 무변경.
- 다음 단계(선택): P2(사업자 운영 핵심 #4~#9) 진행 여부는 사용자 결정 대기.
