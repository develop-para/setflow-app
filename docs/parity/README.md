# Setflow — React 레퍼런스 ↔ Flutter 이식본 패리티 문서

이 폴더는 **React UX 레퍼런스**(`C:\Users\SIMJAE\Downloads\setflow`)와 **Flutter 이식본**(이 저장소)의
화면·플로우 일치도를 정리한 문서 모음입니다.

## 문서 목록

| 문서 | 내용 |
|---|---|
| [`coverage-map.md`](./coverage-map.md) | React 라우트 112개 전체 → Flutter 대응/상태 매핑 표 |
| [`screen-comparison.md`](./screen-comparison.md) | 핵심 화면 정밀 비교 (레이아웃·컴포넌트·인터랙션) |
| [`missing-flows.md`](./missing-flows.md) | 누락·간소화된 플로우 백로그(이슈 형식) |

## 한 줄 결론

> **"그대로 가져온 것"은 아니다.**
> **회원(Member) 핵심 플로우는 충실히 이식**됐으나, 네비게이션 구조가 URL 라우팅 → **역할 기반 셸(role shell)**로 재설계됐고,
> **트레이너·헬스장·운영자(사업자/관리) 영역은 다수 화면이 하나의 대시보드형 화면으로 통합**되면서
> 온보딩 다단계, 정산 세부(수수료 등), 상담 리타겟, 각종 설정 하위 페이지 등이 **누락되거나 축약**됐다.

## 규모 비교

| | React 레퍼런스 | Flutter 이식본 |
|---|---|---|
| 페이지/화면 파일 | `src/pages/*.tsx` **103개** | `lib/screens/*.dart` **6개 파일 / 27개 화면 클래스** |
| 라우트 | react-router **112개 `<Route>`** | URL 라우트 없음 — **역할 셸 + 탭 + `Navigator.push`** |
| 코드량(대략) | pages 합계 **~20,900줄** | `lib` 합계 **~7,235줄** (약 1/3) |
| 네비게이션 | `HashRouter` / `BottomNav` | `RootScreen`가 `state.role`로 셸 분기 |

## 아키텍처 차이 (핵심)

**React** — URL 중심. 화면 1개 = 페이지 파일 1개 = 라우트 1개.

```
HashRouter
 └─ RouteGuard
     ├─ /calendar            → CalendarPage
     ├─ /trainer/settlement  → TrainerSettlementPage
     ├─ /gym/settlement      → GymSettlementPage
     └─ /admin/settlement    → AdminSettlementPage      (역할마다 별도 페이지)
```

**Flutter** — 역할(role) 중심. 하나의 화면이 role 파라미터로 내용 분기.

```
RootScreen  (state.role 로 분기)
 ├─ guest   → WelcomeScreen
 ├─ member  → MemberShell   (탭: 캘린더 · 루틴 · 커뮤니티 · 코칭 · 대시보드/설정)
 ├─ trainer → BusinessShell(role: trainer)  → [홈·People·RoutineManager·ConsultationQueue]
 ├─ gym     → BusinessShell(role: gym)       → [홈·People·RoutineManager·Settlement]
 └─ admin   → BusinessShell(role: admin)     → [홈·AdminUsers·AdminReview·Settlement]
```

→ React에서 `TrainerSettlementPage` / `GymSettlementPage` / `AdminSettlementPage` **3개**가
Flutter에서는 `SettlementPage(role: ...)` **1개**로 합쳐지는 식.

## 두 앱 나란히 실행해서 확인하기

```powershell
# React 레퍼런스
cd C:\Users\SIMJAE\Downloads\setflow
npm install
npm run dev        # http://localhost:5173 (Vite)

# Flutter 이식본
cd C:\Users\SIMJAE\Desktop\pluck\setflow
flutter run -d chrome
```

> 참고: Windows 데스크톱 빌드(`flutter run -d windows`)는 현재 로컬 Visual Studio C++ 툴체인 손상
> (`vcruntimed.lib` 누락)으로 막혀 있음. 웹(크롬)은 정상. 자세한 내용은 팀 내 트러블슈팅 기록 참조.

## 문서 작성 방법(근거)

이 문서의 상태 판정은 다음 근거를 종합한 것이다.

- React `src/App.tsx`의 라우트 표 전수 추출 (112개)
- Flutter `lib/main.dart`, `lib/screens/*.dart` 구조·탭·화면 클래스 추출
- 핵심 화면(캘린더 등) 양쪽 코드 직접 대조
- 기능 키워드 존재 여부 스캔(ocr/ranking/refund/hometax/commission/retarget 등)

**한계**: 상태값(충실/부분/누락)은 라우트·셸 구조·키워드·표본 코드 대조에 기반한다.
"픽셀·인터랙션까지 동일한가"는 두 앱을 화면별로 나란히 띄워 육안 확인해야 확정된다.
불확실한 항목은 표에 `(확인필요)`로 표기했다.

_최종 업데이트: 2026-07-22_
