# 화면 정밀 비교 — React ↔ Flutter

핵심 화면을 레이아웃·컴포넌트·인터랙션 수준에서 대조한다.
표기: **충실** = 구조·요소 거의 일치 / **부분** = 핵심은 같으나 축약·통합 / **상이** = 접근 방식 자체가 다름.

---

## 1. 캘린더 (`/calendar` → `CalendarScreen`) — **충실**

| 요소 | React `CalendarPage` (399줄) | Flutter `CalendarScreen` |
|---|---|---|
| 헤더 월 선택 | 커스텀 드롭다운(`ChevronDown` + 12개월 그리드 팝오버) | `PopupMenuButton`(`1월`~`12월`) |
| 우측 액션 | `BarChart`→`/dashboard`, `Menu`→`/settings` | 동일 아이콘 액션 |
| 요일 헤더 | 일~토, 일=빨강/토=파랑 | 동일 (일 빨강/토 파랑) |
| 그리드 | `grid-cols-[repeat(7,1fr)_44px]` = 7일 + **주간 컬럼** | 7일 + **'주간' 컬럼** (동일 구성) |
| 주간 합계 | 주별 `weeklyVolume`/`weeklySets` 누적 표시 | 주간 볼륨 표시 |
| 월 전환 | `AnimatePresence` 스와이프(`slideDirection`) | `AnimatedSwitcher`/제스처 |
| 날짜 롱프레스 | 컨텍스트 메뉴 | 팝업 메뉴("오늘 적용/수정") |

**평가**: 레이아웃·정보구조가 사실상 동일. 애니메이션 구현체(프레이머모션↔Flutter)만 프레임워크 관용 차이.

---

## 2. 데일리 운동 (`/calendar/:date` → `DailyWorkoutScreen`) — **충실**

| 요소 | React `DailyWorkoutPage` | Flutter `DailyWorkoutScreen` |
|---|---|---|
| 상단 요약 | 총 볼륨 | '총 볼륨' |
| 운동 목록 | 세트/운동 카드, 완료 체크 | '세트'/'완료'/'완료 세트' |
| 운동 추가 | 추가 버튼(8개 `<button>`) | '세트 추가'/'운동 선택'/'새로운 운동 만들기' |
| 부위 필터 | (라이브러리 연동) | 하체/팔/어깨/복근/유산소/웜업 필터 |

**평가**: 운동 기록의 핵심(세트·볼륨·완료)이 그대로 이식. Flutter 쪽은 부위 필터·운동 생성이 더 명시적.

---

## 3. 세트 편집 + 휴식 타이머 (`/calendar/:date/exercise/:exerciseId` → `ExerciseSetScreen`) — **충실**

| 요소 | React `ExerciseSetPage` | Flutter `ExerciseSetScreen` |
|---|---|---|
| 세트 입력 | kg / reps(회) 편집 | '무게' / '횟수'(회) |
| 세트 유형 | (일반) | '일반'/'웜업'/'실패' 구분 |
| 이전 기록 | "이전 기록" | '이전 최고 기록' |
| 완료 처리 | 완료 토글 | '완료' |
| 휴식 타이머 | `RestTimer` 컴포넌트(전역) | 휴식 타이머 |

**평가**: 세트 편집 UX 충실 이식. Flutter는 세트 유형(웜업/실패) 라벨이 더 풍부.
단, React의 `RestTimer`는 **전역 오버레이**(모든 화면 위에 뜸)인데, Flutter는 화면 내 구현 → 동작 범위 확인 권장.

---

## 4. 루틴 마켓 (`/routines/market` → `MarketScreen`) — **부분**

| 요소 | React `RoutineMarketPage` (193줄) | Flutter `MarketScreen` |
|---|---|---|
| 목록 | 전문가 루틴 카드 목록 | '전문가 루틴' 목록 |
| 상세 | `/routines/market/:id` 별도 라우트(`RoutineMarketDetailPage`) | 상세 화면/시트 |
| 가져오기 | 내 루틴으로 복사 | '내 루틴으로 가져오기' |

**평가**: 목록·가져오기 흐름은 존재. 상세 페이지가 별도 라우트에서 인라인/시트로 축약됐을 가능성(확인필요).

---

## 5. 로그인 · 온보딩 — **상이 (가장 큰 차이)**

**React**: 다단계 라우트 플로우
```
/welcome → /auth/login → /onboarding/goals → /onboarding/body → /onboarding/auth → /calendar
                          (목표 선택)        (신체 프로필)      (가입)
```
역할별로도 별도 다단계: `/trainer/onboarding/{register,docs,pending,complete,rejected}`,
`/gym/onboarding/{register,docs,hometax,complete}`.

**Flutter**: 단일 화면으로 평탄화
```
WelcomeScreen(역할 선택) → MemberSetupScreen / BusinessSetupScreen → 각 셸
```

**평가**: **상이**. 목표 선택·신체 프로필 입력·서류 업로드·심사 대기/반려·홈택스 인증 등
**다단계 온보딩 스텝이 1개 셋업 화면으로 축약**됨. 회원 가입 퍼널과 사업자 심사 플로우가 사실상 생략.
→ 백로그 최상위 항목 (`missing-flows.md` P1).

---

## 6. 사업자·운영자 대시보드 — **부분 (통합의 대표 사례)**

React는 역할·기능별로 페이지가 분리돼 있으나, Flutter는 **역할 파라미터를 받는 공통 화면**으로 통합.

| React (분리) | Flutter (통합) |
|---|---|
| `TrainerHomePage` / `GymHomePage` | `BusinessToolScreen` (role 분기 대시보드) |
| `TrainerMembersPage` / `GymMembersPage` | `PeoplePage(role)` |
| `TrainerRoutinesPage` / `GymRoutinesPage` | `RoutineManagerPage(role)` |
| `TrainerSettlementPage` / `GymSettlementPage` / `AdminSettlementPage` | `SettlementPage(role)` |
| `AdminUsersPage`(+큐/제재/뱃지) | `AdminUsersPage` (하위 큐·제재를 탭/섹션으로 흡수) |
| `AdminContent*`(routines/reports/sanctions/minor) | `AdminReviewPage` |

Flutter `BusinessToolScreen` 대시보드는 지표 카드로 요약:
`관리 회원`·`피드백 대기`(트레이너), `전체 회원`·`이번 달 매출`·`소속 트레이너`·`신규 상담`(헬스장),
`전체 사용자`·`활성 코칭`·`심사 대기`·`신고 큐`(운영자).

**평가**: 정보는 대부분 살아있으나 **드릴다운(회원 상세→캘린더/루틴/커뮤니티, 정산 세부, 시스템 관리 개별 화면)이 얕거나 없음**.

---

## 7. 테마 · 색상 — **부분(재구현)**

| | React | Flutter |
|---|---|---|
| 정의 | CSS 변수(`--color-surface-bg`, `--color-divider` 등) + `dark` 클래스 토글 | `lib/theme.dart` (`SetflowTheme.light`/`dark`, `SetflowColors`) |
| 다크모드 | `isDarkMode` → `documentElement.dark` | `state.isDarkMode` → `ThemeMode` |
| 컨테이너 | `max-w-md`(모바일 폭) 중앙 정렬 | `maxWidth: 432` `ConstrainedBox` 중앙 정렬 |

**평가**: 색 토큰·다크모드·모바일 목업 폭 개념은 이식됨. 다만 Material 위젯으로 **재구현**된 것이라
버튼/입력/카드의 미세 스타일(라운드, 그림자, 여백)은 픽셀 단위로 다를 수 있음.
원본 색 가이드는 `share/Setflow_컬러_가이드_내부문서.pdf` 참조.

---

## 종합

| 화면군 | 판정 |
|---|---|
| 캘린더 · 데일리운동 · 세트편집 · 라이브러리 | **충실** |
| 루틴 · 마켓 · 대시보드 · 커뮤니티 · 코칭 | **부분(핵심 OK, 세부 축약)** |
| 로그인 · 온보딩(회원/사업자 심사) | **상이(대폭 축약)** |
| 사업자·운영자 백오피스 | **부분(통합, 드릴다운 얕음)** |
| 테마·색상 | **부분(재구현, 픽셀 비동일)** |
