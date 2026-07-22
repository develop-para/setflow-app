# 커버리지 맵 — React 라우트 112개 → Flutter 대응

**범례**: ✅ 충실 이식 · 🟡 부분/통합(다른 화면에 흡수·간소화) · ❌ 누락 · ⏹️ React에서도 스텁(미구현)

상태는 라우트·셸 구조·키워드·표본 대조 기반. `(확인필요)`는 코드 육안 재확인 권장.

---

## 1. 공용 · 온보딩 (7)

| React 라우트 | React 페이지 | Flutter 대응 | 상태 |
|---|---|---|---|
| `/welcome` | WelcomePage | `WelcomeScreen` | ✅ |
| `/splash` | SplashPage | (없음 — 스플래시 화면 미이식) | ❌ (경미) |
| `/auth/login` | LoginPage | `WelcomeScreen`/`MemberSetupScreen`(역할 선택) | 🟡 로그인 폼 대신 역할선택 |
| `/onboarding/goals` | GoalsPage | `MemberSetupScreen`(통합) | 🟡 다단계→1화면 |
| `/onboarding/body` | BodyProfilePage | `MemberSetupScreen`(통합) | 🟡 |
| `/onboarding/auth` | AuthSignupPage | `MemberSetupScreen`(통합) | 🟡 |
| `/auth/signup` | (인라인 "준비중") | — | ⏹️ React도 스텁 |

## 2. 회원(Member) 핵심 (22)

| React 라우트 | React 페이지 | Flutter 대응 | 상태 |
|---|---|---|---|
| `/` → `/calendar` | (redirect) | `MemberShell` 기본 탭 | ✅ |
| `/calendar` | CalendarPage (399줄) | `CalendarScreen` | ✅ 충실(월선택·7일+주간 그리드·주간볼륨) |
| `/calendar/:date` | DailyWorkoutPage | `DailyWorkoutScreen` | ✅ |
| `/calendar/:date/exercise/:exerciseId` | ExerciseSetPage | `ExerciseSetScreen` | ✅ |
| `/library/:date` | ExerciseLibraryPage | `ExerciseLibraryScreen` | ✅ |
| `/routines` | RoutinesPage | `RoutinesScreen` | ✅ |
| `/routines/create` | RoutineCreatePage | 루틴 생성("새 루틴 만들기") | 🟡 (확인필요) |
| `/routines/market` | RoutineMarketPage | `MarketScreen` | ✅ |
| `/routines/market/:routineId` | RoutineMarketDetailPage | Market 상세("가져오기") | 🟡 (확인필요) |
| `/dashboard` | DashboardPage | `DashboardScreen` | ✅ |
| `/dashboard/body` | BodyCompositionPage | `BodyCompositionScreen` | ✅ |
| `/community` | CommunityPage | `CommunityScreen` | ✅ |
| `/community/post/create` | PostCreatePage | `PostComposerScreen` | ✅ |
| `/community/post/:id` | PostDetailPage | (상세 — 인라인/미확인) | 🟡 (확인필요) |
| `/coaching` | CoachingPage | `CoachingScreen` | ✅ |
| `/coaching/consult/new` | ConsultCreatePage | "새 상담 신청" | 🟡 |
| `/coaching/consult/:id` | ConsultDetailPage | `CoachingDetailScreen` | ✅ |
| `/coaching/payment/:id` | CoachingPaymentPage | (payment 흔적 소수) | 🟡 부분 |
| `/coaching/feedback/:id` | CoachingFeedbackPage | (feedback 흔적) | 🟡 부분 |
| `/settings` | SettingsPage | `SettingsScreen` | ✅ |
| `/settings/account` | AccountSettingsPage | `SettingDetailScreen`(통합) | 🟡 |
| `/settings/{workout,notifications,privacy,display}` | 각 설정 페이지 | `SettingDetailScreen`(통합) | 🟡 흔적 존재 |

## 3. 트레이너(Trainer) (30)

Flutter: `BusinessShell(role: trainer)` = [`BusinessToolScreen`(홈) · `PeoplePage` · `RoutineManagerPage` · `ConsultationQueuePage`] + `BusinessSetupScreen`(온보딩)

| React 라우트 | React 페이지 | Flutter 대응 | 상태 |
|---|---|---|---|
| `/trainer/onboarding/register` | TrainerRegisterPage | `BusinessSetupScreen`(통합) | 🟡 |
| `/trainer/onboarding/docs` | TrainerDocsUploadPage | — | ❌ |
| `/trainer/onboarding/pending` | TrainerPendingPage | — | ❌ |
| `/trainer/onboarding/complete` | TrainerCompletePage | `BusinessSetupScreen` 내 | 🟡 |
| `/trainer/onboarding/rejected` | TrainerRejectedPage | — | ❌ |
| `/trainer/home` | TrainerHomePage | `BusinessToolScreen`(대시보드) | ✅ |
| `/trainer/profile/edit` | TrainerProfileEditPage | — | ❌ (확인필요) |
| `/trainer/routines` | TrainerRoutinesPage | `RoutineManagerPage` | ✅ |
| `/trainer/routines/create` | TrainerRoutineCreatePage | RoutineManager 내 생성 | 🟡 |
| `/trainer/routines/:id/edit` | TrainerRoutineEditPage | RoutineManager 내 수정 | 🟡 |
| `/trainer/routines/:id/stats` | TrainerRoutineStatsPage | "루틴 조회수" 지표 | 🟡 부분 |
| `/trainer/calendar` | TrainerCalendarPage | (회원 캘린더 재사용/미확인) | 🟡 (확인필요) |
| `/trainer/consultations` | TrainerConsultationsPage | `ConsultationQueuePage` | ✅ |
| `/trainer/consultations/:id` | TrainerConsultationDetailPage | ConsultationQueue 상세 | 🟡 |
| `/trainer/consultations/retarget` | TrainerConsultationRetargetPage | — | ❌ (retarget 흔적 0) |
| `/trainer/members` | TrainerMembersPage | `PeoplePage` | ✅ |
| `/trainer/members/:userId` | TrainerMemberDetailPage | People 상세 | 🟡 |
| `/trainer/members/:userId/calendar` | TrainerMemberCalendarPage | — | 🟡/❌ |
| `/trainer/members/:userId/calendar/:date` | GymMemberDailyWorkoutPage | — | ❌ (확인필요) |
| `/trainer/members/:userId/library/:date` | GymMemberLibraryPage | — | ❌ (확인필요) |
| `/trainer/members/:userId/routines` | GymMemberRoutinesPage | — | ❌ (확인필요) |
| `/trainer/members/:userId/routines/create` | GymMemberRoutineCreatePage | — | ❌ (확인필요) |
| `/trainer/members/:userId/community` | GymMemberCommunityPage | — | ❌ (확인필요) |
| `/trainer/settlement` | TrainerSettlementPage | `SettlementPage(role: trainer)` | 🟡 |
| `/trainer/settlement/refunds` | TrainerRefundsPage | Settlement 내(refund 흔적) | 🟡 |
| `/trainer/settings/plan` | TrainerSettingsPlanPage | — | 🟡/❌ |
| `/trainer/settings/badge-renew` | TrainerBadgeRenewPage | (badge 흔적) | 🟡 부분 |
| `/trainer/settings/notifications` | TrainerSettingsNotificationsPage | (notification 흔적) | 🟡 |
| `/trainer/settings/withdraw` | TrainerWithdrawPage | (withdraw 흔적) | 🟡 |
| `/trainer/workspace` | TrainerWorkspacePage | — | ❌ (PC 워크스페이스 뷰) |

## 4. 헬스장(Gym) (28)

Flutter: `BusinessShell(role: gym)` = [홈 · `PeoplePage` · `RoutineManagerPage` · `SettlementPage`] + `TrainerManagementPage`

| React 라우트 | React 페이지 | Flutter 대응 | 상태 |
|---|---|---|---|
| `/gym/onboarding/register` | GymRegisterPage | `BusinessSetupScreen` | 🟡 |
| `/gym/onboarding/docs` | GymOnboardingDocsPage | — | ❌ |
| `/gym/onboarding/hometax` | GymOnboardingHometaxPage | — | ❌ (hometax 흔적 0) |
| `/gym/onboarding/complete` | GymOnboardingCompletePage | `BusinessSetupScreen` 내 | 🟡 |
| `/gym/home` | GymHomePage | `BusinessToolScreen` | ✅ |
| `/gym/profile/edit` | GymProfileEditPage | — | ❌ (확인필요) |
| `/gym/trainers` | GymTrainersPage | `TrainerManagementPage` | ✅ |
| `/gym/members` | GymMembersPage | `PeoplePage(role: gym)` | ✅ |
| `/gym/members/:userId` | GymMemberDetailPage | People 상세 | 🟡 |
| `/gym/members/:userId/calendar` | GymMemberCalendarPage | — | ❌ (확인필요) |
| `/gym/members/:userId/calendar/:date` | GymMemberDailyWorkoutPage | — | ❌ (확인필요) |
| `/gym/members/:userId/library/:date` | GymMemberLibraryPage | — | ❌ (확인필요) |
| `/gym/members/:userId/routines` | GymMemberRoutinesPage | — | ❌ (확인필요) |
| `/gym/members/:userId/routines/create` | GymMemberRoutineCreatePage | — | ❌ (확인필요) |
| `/gym/members/:userId/community` | GymMemberCommunityPage | — | ❌ (확인필요) |
| `/gym/settlement` | GymSettlementPage | `SettlementPage(role: gym)` | 🟡 |
| `/gym/settlement/trainers` | GymSettlementTrainersPage | Settlement 내 | 🟡 |
| `/gym/settlement/refunds` | GymSettlementRefundsPage | Settlement 내(refund 흔적) | 🟡 |
| `/gym/settings/plan` | GymSettingsPlanPage | — | 🟡/❌ |
| `/gym/settings/notifications` | GymSettingsNotificationsPage | (notification 흔적) | 🟡 |
| `/gym/settings/withdraw` | GymSettingsWithdrawPage | (withdraw 흔적) | 🟡 |
| `/gym/workspace` | GymWorkspacePage | — | ❌ (PC 워크스페이스 뷰) |
| `/gym/routines` | GymRoutinesPage | `RoutineManagerPage(role: gym)` | ✅ |
| `/gym/routines/create` | GymRoutineCreatePage | RoutineManager 내 | 🟡 |
| `/gym/routines/:id/stats` | GymRoutineStatsPage | 지표 카드 | 🟡 부분 |
| `/gym/consultations` | GymConsultationsPage | `ConsultationQueuePage`(gym) | 🟡 |
| `/gym/consultations/retarget` | GymConsultationRetargetPage | — | ❌ (retarget 흔적 0) |
| `/gym/consultations/:id` | GymConsultationDetailPage | Consultation 상세 | 🟡 |
| `/gym/trainers/:trainerId/members` | GymTrainerMembersPage | — | ❌ (확인필요) |
| `/gym/trainers/:trainerId/performance` | GymTrainerPerformancePage | (performance 흔적) | 🟡 부분 |

## 5. 운영자(Admin) (18)

Flutter: `BusinessShell(role: admin)` = [홈 · `AdminUsersPage` · `AdminReviewPage` · `SettlementPage`]

| React 라우트 | React 페이지 | Flutter 대응 | 상태 |
|---|---|---|---|
| `/admin/users` | AdminUsersPage | `AdminUsersPage` | ✅ |
| `/admin/users/trainer-queue` | AdminTrainerQueuePage | AdminUsers 내 큐 | 🟡 |
| `/admin/users/gym-queue` | AdminGymQueuePage | AdminUsers 내 큐 | 🟡 |
| `/admin/users/:userId/sanction` | AdminUserSanctionPage | (sanction 흔적) | 🟡 부분 |
| `/admin/users/badges` | AdminUserBadgesPage | (badge 흔적) | 🟡 부분 |
| `/admin/content/routines` | AdminContentRoutinesPage | `AdminReviewPage` | 🟡 |
| `/admin/content/reports` | AdminContentReportsPage | AdminReview("신고 큐") | 🟡 |
| `/admin/content/sanctions` | AdminUserSanctionHistoryPage | (sanction 흔적) | 🟡 |
| `/admin/content/minor-alerts` | AdminContentMinorAlertsPage | (minor 흔적) | 🟡 부분 |
| `/admin/settlement` | AdminSettlementPage | `SettlementPage(role: admin)` | 🟡 |
| `/admin/settlement/refunds` | AdminSettlementRefundsPage | Settlement 내(refund) | 🟡 |
| `/admin/settlement/commission` | AdminSettlementCommissionPage | — | ❌ (commission 흔적 0) |
| `/admin/settlement/final` | AdminSettlementFinalPage | — | 🟡/❌ (확인필요) |
| `/admin/system/ranking` | AdminSystemRankingPage | (ranking 흔적) | 🟡 부분 |
| `/admin/system/ocr` | AdminSystemOcrPage | (ocr 흔적 다수) | 🟡 부분 |
| `/admin/system/plans` | AdminSystemPlansPage | (plans) | 🟡/❌ (확인필요) |
| `/admin/system/keywords` | AdminSystemKeywordsPage | (keyword 흔적) | 🟡 부분 |
| `/admin/system/logs` | AdminSystemLogsPage | (logs 흔적 다수) | 🟡 부분 |

## 6. 폴백 (2)

| React 라우트 | Flutter | 상태 |
|---|---|---|
| `/routine` | (인라인 "곧 추가") | ⏹️ React도 스텁 |
| `*` → `/` | RootScreen 기본 | n/a |

---

## 영역별 집계 (추정)

| 영역 | React 라우트 | ✅ 충실 | 🟡 부분/통합 | ❌ 누락 | 대략 커버리지 |
|---|---|---|---|---|---|
| 공용·온보딩 | 7 | 1 | 4 | 1 (+스텁1) | 중 |
| 회원 핵심 | 22 | 14 | 8 | 0 | **높음(~85%)** |
| 트레이너 | 30 | 5 | 12 | 13 | 낮음(~40%) |
| 헬스장 | 28 | 4 | 12 | 12 | 낮음(~40%) |
| 운영자 | 18 | 1 | 14 | 3 | 중(~55%, 대부분 통합) |
| **합계** | **~107**(+스텁/폴백) | **~25** | **~50** | **~29** | **전체 ~45–55%** |

> 회원 앱으로서의 핵심 경험은 대부분 살아있고, 사업자(B2B)·운영자 백오피스 영역이 크게 통합·축소됐다.
> 세부 판정은 [`missing-flows.md`](./missing-flows.md)의 우선순위 목록 참고.
