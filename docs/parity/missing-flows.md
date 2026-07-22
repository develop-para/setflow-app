# 누락 · 축약 플로우 백로그

React 레퍼런스에는 있으나 Flutter에서 **누락(❌)** 또는 **크게 축약(🟡)** 된 플로우를 이슈 형태로 정리.
우선순위: **P1**(제품 핵심/퍼널) · **P2**(사업자 운영 필수) · **P3**(백오피스 세부).

> 이 문서는 **현황 기록·백로그**이며, 구현 지시가 아니다. 실제 착수 전 각 항목을 코드로 재확인할 것.
> `(확인필요)` 항목은 통합 화면 내부에 이미 있을 수 있음.

---

## P1 — 온보딩/가입 퍼널 (사용자 유입 직결)

### #1 회원 다단계 온보딩 축약
- **React**: `/auth/login` → `/onboarding/goals`(목표) → `/onboarding/body`(신체 프로필) → `/onboarding/auth`(가입)
- **Flutter**: `MemberSetupScreen` 1개로 평탄화
- **누락 요소**: 목표 선택 스텝, 신체 프로필 입력 스텝, 이메일 회원가입 폼
- **영향**: 신규 사용자 온보딩 경험/전환 퍼널이 사실상 생략됨

### #2 사업자(트레이너) 심사 온보딩
- **React**: `/trainer/onboarding/{register, docs, pending, complete, rejected}`
- **Flutter**: `BusinessSetupScreen` 통합, 아래 스텝 **누락(❌)**
  - `docs` 서류 업로드 · `pending` 심사 대기 · `rejected` 반려 안내
- **영향**: 트레이너 자격 심사 라이프사이클(제출→대기→승인/반려) 표현 불가

### #3 사업자(헬스장) 심사 온보딩 + 홈택스
- **React**: `/gym/onboarding/{register, docs, hometax, complete}`
- **Flutter**: `docs`, **`hometax`(홈택스 사업자 인증) 누락(❌)** — 키워드 흔적 0
- **영향**: 헬스장 사업자 등록/세무 인증 플로우 부재

---

## P2 — 사업자 운영 핵심

### #4 회원 상세 드릴다운 (트레이너·헬스장 공통)
- **React**: `/{trainer,gym}/members/:userId` 및 하위
  `/calendar`, `/calendar/:date`, `/library/:date`, `/routines`, `/routines/create`, `/community`
- **Flutter**: `PeoplePage` 목록/요약까지. **회원별 캘린더·라이브러리·루틴·커뮤니티 드릴다운 누락(❌, 확인필요)**
- **영향**: 트레이너/헬스장이 담당 회원의 운동 데이터를 열람·관리하는 핵심 B2B 기능 부재

### #5 상담 리타겟 (Consultation Retarget)
- **React**: `/trainer/consultations/retarget`, `/gym/consultations/retarget`
- **Flutter**: **누락(❌)** — `retarget` 흔적 0
- **영향**: 상담 재타게팅 마케팅 플로우 부재

### #6 워크스페이스(PC 뷰)
- **React**: `/trainer/workspace`, `/gym/workspace` (`*Workspace*Page`)
- **Flutter**: **누락(❌)**
- **영향**: 데스크톱/PC 전용 사업자 작업 화면 부재 (모바일 셸만 존재)

### #7 정산 세부
- **React**: 트레이너/헬스장 `settlement/refunds`, 헬스장 `settlement/trainers`
- **Flutter**: `SettlementPage(role)`로 통합. 환불/트레이너별 정산은 **부분(🟡)** — 세부 화면 확인필요
- **영향**: 정산 드릴다운(환불 내역, 트레이너별 분배) 얕음

### #8 트레이너 성과/루틴 통계
- **React**: `/gym/trainers/:trainerId/performance`, `/gym/trainers/:trainerId/members`, `*/routines/:id/stats`
- **Flutter**: 지표 카드 수준(🟡). 트레이너 개별 성과·소속 회원 상세는 **누락/부분**
- **영향**: 헬스장의 트레이너 관리 심화 기능 축약

### #9 사업자 설정 하위 페이지
- **React**: `/{trainer,gym}/settings/{plan, notifications, withdraw}`, 트레이너 `badge-renew`, 프로필 편집
- **Flutter**: 키워드 흔적은 있으나 개별 화면 **부분(🟡)/확인필요**
- **영향**: 요금제 변경·탈퇴·뱃지 갱신·프로필 편집 진입점 불명확

---

## P3 — 운영자(Admin) 백오피스 세부

### #10 정산 수수료/최종 확정
- **React**: `/admin/settlement/{commission, final}`
- **Flutter**: **`commission` 누락(❌, 흔적 0)**, `final` 확인필요
- **영향**: 운영자 정산 수수료 산정·최종 확정 단계 부재

### #11 시스템 관리 개별 화면
- **React**: `/admin/system/{ranking, ocr, plans, keywords, logs}`
- **Flutter**: 각 키워드 흔적은 존재하나 **개별 관리 화면으로 분리되지 않고 부분(🟡)**
  - `plans`(요금제 관리)는 흔적 약함 → 확인필요
- **영향**: OCR 검수·랭킹·금칙어·로그·요금제 관리의 세분화된 운영 UI 축약

### #12 콘텐츠 심사 세분화
- **React**: `/admin/content/{routines, reports, sanctions, minor-alerts}`
- **Flutter**: `AdminReviewPage` 하나로 통합(🟡)
- **영향**: 루틴/신고/제재이력/미성년 알림의 개별 검수 워크플로 통합됨

### #13 스플래시 화면
- **React**: `/splash` (`SplashPage`)
- **Flutter**: **누락(❌)** — 앱 진입 시 바로 역할 분기
- **영향**: 브랜드 스플래시/초기 로딩 연출 부재 (경미)

---

## 요약 표

| # | 플로우 | 영역 | 상태 | 우선순위 |
|---|---|---|---|---|
| 1 | 회원 다단계 온보딩 | 온보딩 | 🟡 축약 | P1 |
| 2 | 트레이너 심사(docs/pending/rejected) | 온보딩 | ❌ | P1 |
| 3 | 헬스장 심사 + 홈택스 | 온보딩 | ❌ | P1 |
| 4 | 회원 상세 드릴다운 | 사업자 | ❌ | P2 |
| 5 | 상담 리타겟 | 사업자 | ❌ | P2 |
| 6 | 워크스페이스(PC 뷰) | 사업자 | ❌ | P2 |
| 7 | 정산 세부(환불/트레이너별) | 사업자 | 🟡 | P2 |
| 8 | 트레이너 성과/루틴 통계 | 사업자 | 🟡 | P2 |
| 9 | 사업자 설정 하위 | 사업자 | 🟡 | P2 |
| 10 | 정산 수수료/최종 | 운영자 | ❌/🟡 | P3 |
| 11 | 시스템 관리 개별 화면 | 운영자 | 🟡 | P3 |
| 12 | 콘텐츠 심사 세분화 | 운영자 | 🟡 | P3 |
| 13 | 스플래시 | 공용 | ❌ | P3 |

> **정리**: 회원 앱 핵심은 이식 완료. 미착수/축약의 대부분은 **온보딩 퍼널(P1)**과
> **사업자·운영자 백오피스(P2·P3)**에 집중돼 있다.
