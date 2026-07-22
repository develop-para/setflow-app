# 🎯 확정 목표 (Definition of Done) — 실서비스 전환

> 이 문서가 **루프의 최종 목표이자 종료 조건**이다. PoC/MVP가 아니라 **Airbnb·Uber·Toss급 실제 서비스** 품질을 기준으로 한다.

## 확정된 범위 (사용자 결정 2026-07-22)

**Option C — 프런트 프로덕션 퀄리티 + 교체가능 데이터 어댑터층**
- 지금: 백엔드 없이 "실제 서비스처럼 보이고 작동"하는 수준까지 완성
- 데이터는 `Repository/Service` 추상화 뒤의 **Mock 구현** → 나중에 **Supabase로 교체만** 하면 되게 설계
- Supabase 실연동은 **별도 단계**(이 목표의 종료 조건에는 미포함)

## 페이지별 "완료(Done)" 5대 기준 — 전부 충족해야 완료

1. **디자인**: 2026 디자인 시스템(토큰/타이포/스페이싱/라운드/엘리베이션/모션) 100% 적용. placeholder·러프 레이아웃 0. 라이트/다크 완전 대응.
2. **인터랙션**: 모든 버튼/액션 동작 · 올바른 네비게이션 · **폼 검증+인라인 에러** · **로딩/빈/에러/성공 상태** · 피드백(스낵바·햅틱) · 마이크로 애니메이션/전환.
3. **데이터**: 현실적 콘텐츠 + **상태 지속성**. 모든 데이터 접근은 Repository 경유(Mock). 앱 재시작해도 로컬 지속(hive/shared_preferences).
4. **품질**: 접근성(대비 WCAG AA, 터치타깃 ≥48dp) · 반응형 · `flutter analyze` 0 · 웹 빌드 통과 · 핵심 플로우 위젯 테스트.
5. **패리티**: React 원본의 UX/유저플로우/버튼 액션/인터랙션 **전부** 반영.

## 품질 바 (레퍼런스)
- **Toss**: 극단적으로 명확한 정보위계, 큰 숫자/타이포, 부드러운 모션, 즉각 피드백, 빈/에러 상태까지 정성.
- **Airbnb**: 일관된 컴포넌트 시스템, 넉넉한 여백, 사진/카드 중심, 검색·필터 UX.
- **Uber**: 상태 기반 실시간 피드백, 명확한 CTA, 지도/리스트 전환.

## 실행 단계 (하네스 루프) — 내일 여기서 시작

| Phase | 내용 | 산출물 | 게이트 |
|---|---|---|---|
| **B. 디자인 시스템** | 토큰(라이트/다크 semantic) + 타이포/스페이싱/라운드/엘리베이션/모션 + 컴포넌트 | `lib/theme/tokens.dart`, `theme.dart` 재작성, `widgets/common.dart` 확장 | analyze+build |
| **C. 데이터 어댑터층** | Repository/Service 인터페이스 + Mock 구현, `AppState`가 repo 경유, 로컬 영속 | `lib/data/**` | analyze+build |
| **D. 화면 적용** | 화면군별 디자인시스템+프로덕션 상태(로딩/빈/에러/검증/애니/피드백) | 화면군당 1반복 | analyze+build |
| **E. React UX 이식** | 화면별 버튼 동작/플로우/인터랙션 누락분 | 패리티 체크 | analyze+build |
| **F. 테스트·마감** | 핵심 플로우 위젯 테스트 + 최종 빌드 | `test/**` | test+build |

### D 화면군 (각각 1반복, 순차)
1. 온보딩(welcome/member setup/business setup/splash)
2. 회원 코어(캘린더/데일리/세트/라이브러리)
3. 회원 소셜(루틴/마켓/대시보드/체성분/커뮤니티/코칭/설정)
4. 사업자 셸/홈(business_screens: shell/header/homes)
5. 사업자 상세(people/routine/consult/settlement/stats/settings/workspace/detail)
6. 운영자(admin users/review/system/content)

## 상세 디자인 스펙
→ [`../design/design-system.md`](../design/design-system.md) (구현용 토큰·컴포넌트 스펙 확정본)

## 진행 상황
→ [`PROGRESS.md`](./PROGRESS.md) 하단 "내일 재개" 섹션 참조

_확정일: 2026-07-22_
