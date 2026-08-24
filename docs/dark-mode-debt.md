# 다크 모드의 색 부채 — 대부분 갚았고, 남은 것은 이것이다

다크 모드는 설정에서 켜지는 실제 기능이다(`themeMode: state.isDarkMode ? dark : light`).
화면들이 쓰던 색 상수는 **라이트 전용 값**이라 다크에서 대비가 무너졌었다.

## 왜 문제였나

`SetflowTheme.dark`의 배경(`#0B0B0C`) 위에서 상수들의 대비:

| 상수 | hex | 다크 대비 | 판정 |
|---|---|---|---|
| `secondaryText` | `#71717A` | 4.07 | 미달 |
| `red` | `#DC2626` | 4.07 | 미달 |
| `green` | `#15803D` | 3.92 | 미달 |
| `orange` | `#C2410C` | 3.80 | 미달 |
| `blue` | `#2563EB` | 3.81 | 미달 |
| `teal` | `#0F766E` | 3.59 | 미달 |
| `purple` | `#7C3AED` | 3.45 | 미달 |

`SetflowSemanticColors`는 라이트·다크 **쌍**을 갖고 있고 다크 값들은 전부 4.5:1을 넘는다.
그러니 `SetflowColors.red` → `context.setflowColors.error` 로 옮기기만 하면 되는 문제였다.

## 무엇이 막고 있었나 — 색이 아니라 `const`

363곳을 치환하니 263개가 컴파일 실패했다. `const` 리터럴은 `BuildContext`를 읽을 수 없다.
갈래는 셋이었고 **성격이 전혀 달랐다**:

1. **인라인 `const` 위젯** (약 260곳) — `const Icon(..., color: ...)`.
   `const`만 떼면 된다. 기계적이다.
2. **`const` 데이터 테이블 3개** — 아이콘·색·제목을 묶은 레코드 리스트.
   빌드 시점 함수로 바꿨다: `List<...> _items(BuildContext context) => [...]`.
3. **`context`가 스코프에 없는 함수** — `_roleConfig(role)`, `_workspaceConfig(role)`,
   `_routineShareStatusColor(status)`. 인자로 `BuildContext`를 받게 했다.

## 결과

**363곳 중 359곳이 테마 대응으로 넘어갔다.** 남은 4곳은 한 자리다.

## 남은 4곳 — 이건 색 문제가 아니다

`_routineFromRecord`가 `RoutineData`에 색을 채워 넣는다. **모델은 `BuildContext`를 모른다.**

제대로 고치려면 **색을 모델에서 빼고**, 화면이 그릴 때 `status → 색`을 정해야 한다.
그건 모델이 무엇을 담는가의 문제지 색을 바꾸는 일이 아니라서 여기서 하지 않았다.
`lib/screens/business_screens.dart`의 해당 자리에 같은 내용을 주석으로 남겼다.

## 아직 남은 다른 것

`secondaryText`(167곳)와 `ink`(31곳)는 확장에 대응 필드가 없다. 다만 이 둘은 이미 테마를 따르는
`theme.colorScheme.onSurfaceVariant` / `onSurface`가 있으므로, 옮길 곳이 확장이 아니라 컬러스킴이다.
화면마다 "이게 본문 글자색인가 고정 잉크인가"를 판단해야 해서 일괄 치환 대상이 아니다.

회귀: `test/dark_mode_debt_test.dart`
