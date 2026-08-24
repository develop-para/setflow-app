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

## `secondaryText`와 `ink`도 정리했다

이 둘은 확장에 대응 필드가 없다. 대신 **컬러스킴**이 이미 테마를 따른다.

- `secondaryText` **167곳 전부** -> `theme.colorScheme.onSurfaceVariant`.
  라이트에서 값이 **완전히 같아서**(둘 다 `#71717A`) 화면은 그대로 보이고 다크만 고쳐진다.
- `ink` 31곳은 **거의 다 배경**이다(`backgroundColor`, `BoxDecoration.color`).
  일부러 어두운 판이므로 테마를 따라선 안 된다 — 그대로 뒀다.
  글자색으로 쓰인 곳은 `SetflowWordmark` **하나뿐**이었고, 거기만 `onSurface`로 옮겼다.
  배경 없이 그릴 때 다크에서 **검정 위 검정**이 되던 자리다.

**단일 회색으로는 해결이 불가능하다는 것도 확인했다**: 흰 배경 통과 조건은 `L <= 0.1833`,
다크 통과 조건은 `L >= 0.1902`. 겹치지 않는다. 그래서 상수를 바꾸는 길은 없고 호출부가 옮겨야 했다.

## 이관 방법 — 파일 단위 롤백

`Theme.of(context)`는 **메서드 호출**이라 `const` 안에서 쓸 수 없다. 오류 위치에서 위로 훑어
`const`를 지우는 방식은 엉뚱한 `const`를 지워 **오류가 137 -> 155로 늘었다.**

되돌리고 방식을 바꿨다: **파일 하나씩 적용하고, 그 파일이 컴파일되지 않으면 즉시 되돌린다.**
17개 중 16개가 통과했고 남은 하나(`welcome_screen.dart`)는 지우는 대상을
`const <대문자로 시작하는 위젯>(` 호출로만 좁히니 한 번에 끝났다.
**깨진 상태를 중간에도 남기지 않는 것**이 핵심이다.

회귀: `test/dark_mode_debt_test.dart`
