# 다크 모드의 색 부채

다크 모드는 설정에서 켜지는 **실제 기능**이다(`themeMode: state.isDarkMode ? dark : light`).
그런데 화면들이 쓰는 색 상수는 대부분 **라이트 전용 값**이라, 다크에서 대비가 무너진다.

## 측정

`SetflowTheme.dark`의 배경(`#0B0B0C`) 위에서, 화면이 실제로 쓰는 상수들의 대비:

| 상수 | hex | 다크 배경 대비 | 판정 | 사용처 |
|---|---|---|---|---|
| `secondaryText` | `#71717A` | 4.07 | 미달 | 167 |
| `red` | `#DC2626` | 4.07 | 미달 | 97 |
| `green` | `#15803D` | 3.92 | 미달 | 76 |
| `orange` | `#C2410C` | 3.80 | 미달 | 67 |
| `blue` | `#2563EB` | 3.81 | 미달 | 55 |
| `teal` | `#0F766E` | 3.59 | 미달 | 36 |
| `purple` | `#7C3AED` | 3.45 | 미달 | 32 |
| `ink` | `#111113` | 1.04 | 미달 | 31 |
| `disabled` | `#A1A1AA` | 7.68 | 통과 | 9 |

합계 **563곳**. 다만 이 숫자는 **상한**이다 — 상당수는 `withValues(alpha: .12)` 틴트 배경이거나
이미 어두운 잉크 블록 위라, 본문 대비 기준(4.5:1)이 그대로 적용되지 않는다.

## 고칠 곳은 이미 있다

`SetflowSemanticColors`가 **라이트·다크 쌍**을 갖고 있고, 그 다크 값들은 전부 4.5:1을 넘는다
(`test/dark_mode_debt_test.dart`가 확인한다). 즉 `SetflowColors.red` → `context.setflowColors.error`
로 옮기기만 하면 되는 자리가 **363곳**이다.

## 막고 있는 것은 색이 아니라 `const`

실제로 전부 치환해 봤다. **364곳을 바꾸니 263개가 컴파일 실패**했다. 형태는 이렇다:

```dart
static const _tools = [
  (Icons.block_outlined, SetflowColors.red, '금칙어 관리', '자동 블라인드 키워드 목록'),
  ...
];
```

아이콘·색·제목을 묶은 **`const` 데이터 테이블**이라 `BuildContext`를 읽을 수 없다. 고치려면
테이블을 빌드 시점 함수로 바꿔야 하고, 그건 **파일마다 구조를 바꾸는 작업**이지 치환이 아니다.

**부분 치환은 하지 않았다.** 되는 곳(약 100군데)만 바꾸면 같은 화면 안에 두 패턴이 섞여
다음 사람이 어느 쪽을 따라야 할지 알 수 없게 된다. 문서화된 결함이 그보다 낫다.

## 하려면 이 순서로

1. 한 파일씩 잡는다. `const` 테이블을 `List<X> _toolsOf(BuildContext)` 같은 함수로 바꾼다.
2. 그 파일의 `SetflowColors.*`를 `context.setflowColors.*`로 옮긴다.
3. `secondaryText`와 `ink`는 확장에 대응 필드가 없다 — `theme.colorScheme.onSurfaceVariant`와
   `onSurface`가 이미 테마를 따르므로 그쪽으로 보낸다.
4. 화면 하나가 끝날 때마다 다크로 열어 눈으로 확인한다. 숫자만으로는 틴트 배경을 구분 못 한다.
