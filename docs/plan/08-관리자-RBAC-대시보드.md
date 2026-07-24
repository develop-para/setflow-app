# Setflow 관리자(Platform Admin) — RBAC & 대시보드

> **문서 버전** v1.0 · 2026-07-23
> **범위** **사내 내부 운영팀**(`userType='admin'`)의 세부 권한 체계(RBAC)와 관리자 홈 대시보드. 외부 고객사인 헬스장 대표(`gym`)와는 별개다.
> **목적** ①업무별 관리자 권한 분리(최소 권한 원칙·업무 분리) ②운영자가 처음 진입하는 통합 대시보드 정의. 상위 요구사항 `01 §FR-ADMIN`, 백로그 `02 T10`, 페이지 `03 클러스터5`, 화면ID `07 §2(ADM-*)`.
> **전제** 관리자는 **회원가입이 없다**(내부 초대·발급). 웹 어드민 `admin.setflow.app` 분리 권장(Router v1.0). 앱(모바일) 어드민과 분리 운영.

---

# 1부. 관리자 RBAC (세부 권한)

## 1.1 설계 원칙
1. **최소 권한(Least Privilege)** — 각 운영자는 담당 업무에 필요한 최소 도메인만.
2. **업무 분리(Segregation of Duties, SoD)** — 민감 작업(정산 지급·영구정지·최종정산)은 **작성자(Maker) ≠ 승인자(Checker)** 2인 원칙.
3. **전수 감사(Full Audit)** — 모든 관리자 액션은 `admin_audit_logs`에 (누가·무엇을·전후값·시각) 기록. 예외 없음.
4. **역할 기반(Role-Based)** — 개인이 아닌 **역할(Role)**에 권한을 부여, 인사이동은 역할 재배정으로 처리.
5. **읽기/쓰기 분리** — 열람 권한과 실행(승인/지급/삭제) 권한을 별도 관리.

## 1.2 관리자 역할(Role) 정의

| Role | 코드 | 담당 | 대응 페르소나 |
|---|---|---|---|
| 최고 관리자 | `super_admin` | 전 도메인 + 관리자 계정/역할 관리 | 운영 총괄 |
| 운영/CS | `ops` | 회원 조회·제재(경고~30일)·위험행동 대응 | CS/운영팀 |
| 심사역 | `reviewer` | 트레이너/헬스장 자격·사업자 심사, 배지 | 자격 검증 담당 |
| 콘텐츠 모더레이터 | `moderator` | 키워드 탐지·신고·콘텐츠 삭제·키워드 사전 | 모더레이션 담당 |
| 재무/정산 | `finance` | 코칭 정산·환불·수수료·탈퇴 최종정산 | 재무/정산 담당 |
| 시스템 운영 | `platform` | 랭킹·OCR·플랜·서버 로그·시스템 설정 | 인프라/DevOps |
| 감사자(읽기전용) | `auditor` | 전 도메인 **읽기** + 감사로그 열람 | 내부감사/보안 |

> 한 사람이 복수 역할 보유 가능(예: 소규모 팀에서 `ops`+`reviewer`). 단 SoD 대상 작업은 동일인 Maker/Checker 겸직 금지.

## 1.3 권한 매트릭스 (역할 × 도메인·화면ID)

범례: **F**=전체(열람+실행) · **R**=읽기전용 · **A**=승인권(Checker) · **—**=접근불가

| 도메인 / 화면 | super_admin | ops | reviewer | moderator | finance | platform | auditor |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| **ADM-USR 회원관리**(AdminUsers) | F | F | R | R | — | — | R |
| ├ 트레이너 심사(TrainerQueue) | F | R | **F** | — | — | — | R |
| ├ 헬스장 심사(GymQueue) | F | R | **F** | — | — | — | R |
| ├ 제재 부과(UserSanction) | F | **F**¹ | — | R | — | — | R |
| ├ 제재 이력·리셋(SanctionHistory) | F | F | — | R | — | — | R |
| └ 배지 관리(UserBadges) | F | — | **F** | — | — | — | R |
| **ADM-CMS 콘텐츠관리** | F | R | — | **F** | — | — | R |
| ├ 키워드탐지 검토(ContentRoutines) | F | — | — | **F** | — | — | R |
| ├ 신고 검토(ContentReports) | F | R | — | **F** | — | — | R |
| └ 위험행동(ContentMinorAlerts) | F | **F** | — | F | — | — | R |
| **ADM-PAY 정산관리** | F | — | — | — | **F** | — | R |
| ├ 코칭 정산 지급/보류(Settlement) | F | — | — | — | **F**² | — | R |
| ├ 환불·분쟁 중재(SettlementRefunds) | F | R | — | — | **F** | — | R |
| ├ 수수료 등급(SettlementCommission) | F | — | — | — | **F** | — | R |
| └ 탈퇴 최종정산(SettlementFinal) | F | — | — | — | **F**³ | — | R |
| **ADM-SYS 시스템** | F | — | — | — | — | **F** | R |
| ├ 랭킹 알고리즘(Ranking) | F | — | — | — | — | **F** | R |
| ├ OCR 설정(Ocr) | F | — | — | — | — | **F** | R |
| ├ 구독 플랜/과금(Plans) | F | — | — | — | A⁴ | **F** | R |
| ├ 금지 키워드 사전(Keywords) | F | — | — | **F** | — | F | R |
| └ 서버 상태/로그(Logs) | F | — | — | — | — | **F** | R |
| **관리자 계정·역할 관리** | **F** | — | — | — | — | — | R |
| **감사로그 열람**(admin_audit_logs) | F | R | R | R | R | R | **F** |

¹ `ops`의 제재는 경고~30일까지. **영구정지(banned)는 `super_admin` 승인 필요**(SoD).
² 코칭 정산 **지급 실행**은 `finance`가 작성 → **`super_admin` 또는 finance 리드가 Checker 승인**(2인). 보류는 단독 가능.
³ 탈퇴 최종정산 **완료 확정(비가역)**은 반드시 Checker 승인.
⁴ 플랜 가격 변경은 `platform`이 설정하되 `finance` 승인(A) 필요.

## 1.4 업무 분리(SoD) — Maker/Checker 대상 작업

| 민감 작업 | Maker | Checker(승인) | 근거 |
|---|---|---|---|
| 영구정지(banned) 제재 | ops | super_admin | 회복 불가·재가입 3년 차단 |
| 코칭 정산 지급 실행 | finance | finance 리드/super_admin | 자금 이체 |
| 탈퇴 최종정산 완료 확정 | finance | finance 리드/super_admin | 비가역·법정 10영업일 |
| 수수료 등급 변경 | finance | super_admin | 정산 수익 직접 영향 |
| 구독 플랜 가격 변경 | platform | finance | 매출 영향·기존 구독자 소급 |
| 랭킹 가중치 변경 | platform | super_admin | 노출·수익 영향 |
| 관리자 역할 부여/회수 | super_admin | (2차 super_admin 권장) | 권한 상승 |

> Maker가 요청 → Checker 승인 전까지 `status='pending_approval'`. 동일인 겸직 시 시스템이 승인 차단.

## 1.5 데이터 모델
```
admin_users(id, user_id FK, display_name, email, status[active|suspended], created_at, invited_by)
admin_roles(id, code[super_admin|ops|reviewer|moderator|finance|platform|auditor], name, description)
admin_user_roles(admin_user_id, role_id, granted_by, granted_at)        -- 다대다(복수 역할)
admin_permissions(id, resource, action[read|write|approve|delete], description)
admin_role_permissions(role_id, permission_id)                          -- 역할→권한
admin_approvals(id, action_type, target_type, target_id, maker_id, checker_id, status[pending|approved|rejected], payload(json), created_at, resolved_at)  -- SoD 승인 워크플로
admin_audit_logs(id, actor_admin_id, action, target_type, target_id, before(json), after(json), ip, created_at)  -- 전 액션 필수
```

## 1.6 인가 규칙 (Enforcement)
- **서버 강제**: 모든 `/admin/*` API는 미들웨어에서 `admin_user_roles → admin_role_permissions`로 `resource:action` 검사(클라 가드는 UX 보조일 뿐).
- **비관리자 접근**: 401. **권한 없는 도메인**: 403. (Router v1.0 부록 A 가드 정책)
- **웹 어드민 분리**: `admin.setflow.app` 별도 도메인 + IP 허용목록·2FA 권장.
- **세션**: 짧은 만료 + 재인증(민감 작업 전 재인증 챌린지).
- **감사**: 읽기 제외 모든 write/approve/delete는 `admin_audit_logs` 기록(before/after).

---

# 2부. 관리자 대시보드 (홈)

## 2.1 개요
- **라우트/화면ID**: `/admin` (또는 `/admin/dashboard`) · `ADM-HOME` (신규 — 기존 문서 미정의분 추가).
- **목적**: 운영자가 로그인 직후 진입하는 **통합 관제 화면**. 처리 대기 큐·SLA 위반·플랫폼 지표를 한눈에 보고 각 관리 화면으로 딥링크.
- **역할 인지(Role-aware)**: 로그인한 관리자의 역할에 따라 **자신이 처리 가능한 위젯만** 노출(권한 없는 카드는 숨김/비활성).

## 2.2 대시보드 구성 (위젯)

### A. 처리 대기 큐 (Action Queues) — SLA 임박순 정렬
| 위젯 | 표시 | 대상 역할 | 딥링크 |
|---|---|---|---|
| 트레이너 심사 대기 | 건수 + SLA 초과(D+n 빨강) | reviewer, super_admin | `/admin/users/trainer-queue` |
| 헬스장 인증 대기 | 건수 + 홈택스 상태 | reviewer, super_admin | `/admin/users/gym-queue` |
| 신고 검토 대기 | 건수 + 등급(Red/Orange/Yellow)별 | moderator | `/admin/content/reports` |
| 키워드 탐지 대기 | 건수 | moderator | `/admin/content/routines` |
| 위험행동 감지 | 신규 건수 + 심각도(High/Med/Low) | ops, moderator | `/admin/content/minor-alerts` |
| 환불·분쟁 대기 | 건수 + 금액 | finance | `/admin/settlement/refunds` |
| 정산 지급 대기 | 건수 + 지급 예정 총액 | finance | `/admin/settlement` |
| 탈퇴 최종정산 | 건수 + 법정기한 D-day | finance | `/admin/settlement/final` |

### B. SLA·경보 (Alerts)
- **SLA 위반 배너**: 심사 3영업일 초과, 신고 등급별 SLA(Red 1h/Orange 24h/Yellow 72h) 초과, 최종정산 법정 10영업일 임박 건 상단 경고.
- **시스템 경보**: 서버 업타임 SLA(99.5%) 미달, 장애 발생(연동: `/admin/system/logs`) — 대상 `platform`.

### C. 플랫폼 KPI (요약 지표, 기간 토글: 오늘/7일/30일)
| 지표 | 소스 | 대상 역할 |
|---|---|---|
| 신규 가입(회원/트레이너/헬스장) | users | ops, super_admin |
| 활성 사용자(DAU/WAU) | sessions | super_admin, platform |
| 코칭 결제·거래액(GMV) | payments | finance, super_admin |
| 정산 지급/보류 총액 | settlements | finance |
| 신고·제재 발생 추이 | reports/sanctions | moderator, ops |
| 콘텐츠·게시물 수 | posts | moderator |
| OCR 사용량/한도 | ocr_usage | platform |

### D. 빠른 실행 (Quick Actions) — 권한 필터
- 유저 검색(제재·배지) / 키워드 추가 / 랭킹·플랜 설정 / 감사로그 검색. (역할에 따라 노출)

## 2.3 UX 흐름
```
관리자 로그인(admin.setflow.app, 2FA) → /admin(대시보드)
  → [처리 대기 큐 카드] 클릭 → 해당 관리 화면(딥링크)에서 처리
  → [SLA 경보] 클릭 → 임박 건 필터된 목록
  → [KPI 기간 토글] → 추세 확인
  → 처리 완료 시 대시보드 큐 카운트 자동 갱신
```

## 2.4 데이터·API 요구사항
- `GET /admin/dashboard` → 역할 필터된 위젯 데이터 일괄(각 큐 건수·SLA 위반 수·KPI 요약). **역할별로 응답 필드 제한**(권한 없는 지표 미포함).
- 각 큐 카운트는 해당 도메인 집계(트레이너 심사=`trainer_applications WHERE pending`, 신고=`report_targets WHERE pending` 등).
- KPI는 서버 집계(머티리얼라이즈드 뷰/배치) — 대시보드 진입 성능 확보.
- **실시간성**: 큐·경보는 폴링 또는 서버푸시(운영 중 신규 유입 반영).

## 2.5 백로그 반영 (02 기획서 T10 보강)
- **T10-E0. 관리자 기반(신규)**
  - T10-E0-1 [BE] RBAC 모델(`admin_roles/permissions/user_roles/role_permissions`) + `/admin/*` 인가 미들웨어.
  - T10-E0-2 [BE] SoD 승인 워크플로(`admin_approvals`, Maker/Checker) — 영구정지·정산지급·최종정산·수수료·플랜·랭킹·역할부여.
  - T10-E0-3 [BE] `admin_audit_logs` 전 액션 기록 + 감사자 열람 API.
  - T10-E0-4 [INFRA] 웹 어드민 분리(`admin.setflow.app`)·IP 허용목록·2FA·짧은 세션·재인증.
  - T10-E0-5 [FE/BE] **관리자 대시보드(ADM-HOME)** `GET /admin/dashboard`(역할 필터 위젯) + 큐·SLA·KPI·빠른실행.
  - T10-E0-6 [BE] 관리자 계정 초대·역할 부여/회수(super_admin 전용).

## 2.6 리스크·주의
- **권한 상승(Privilege Escalation)**: 역할 부여는 super_admin만, 2차 승인 권장. 감사자(auditor)는 절대 write 불가.
- **감사 무결성**: `admin_audit_logs`는 append-only(수정·삭제 불가), 별도 보존.
- **최소 인원 SoD**: 소규모 팀에서 Maker/Checker 2인 확보 어려우면 최소 super_admin 1인을 Checker로 상시 지정.
- **계좌·개인정보 접근**: 최종정산 계좌·인바디 등 민감정보 접근은 별도 감사 + 마스킹 기본.
