# 버전 체계

## 두 개의 숫자

Android 앱에는 성격이 다른 버전 값이 두 개 있습니다. 이 둘을 섞으면 "업로드는
됐는데 테스터 폰에 설치가 안 된다"는 증상이 나옵니다.

| | Flutter | Android | 역할 | 누가 정하나 |
|---|---|---|---|---|
| `1.0.0` | build-name | `versionName` | **사람이 읽는 버전.** 화면·스토어에 표시 | 손으로 올림 |
| `30` | build-number | `versionCode` | **기계가 비교하는 정수.** 업데이트 가능 판정 | 자동 계산 |

Android는 `versionCode`가 **현재 설치된 것보다 큰** APK만 덮어쓰기를 허용합니다.
같거나 낮으면 설치가 조용히 거부됩니다. 그래서 이 값은 사람이 관리하면 안 됩니다.

## versionCode = main 커밋 수

```
git rev-list --count HEAD
```

빌드 번호는 `pubspec.yaml`에 적힌 값이 아니라 **커밋 수**입니다.
로컬 스크립트와 GitHub Actions가 똑같은 이 공식을 씁니다.

**왜 이렇게 했나.** 이전에는 `pubspec.yaml`의 `+N`을 배포할 때마다 올렸습니다.
CI가 붙는 순간 이 방식은 깨집니다 — 로컬에서 올린 번호와 CI가 올린 번호가 서로를
모른 채 엇갈리고, 낮은 번호가 나중에 배포되면 테스터는 그 빌드를 받지 못합니다.
커밋 수는 어디서 계산하든 같은 값이 나오고 단조 증가하므로 이 문제가 없습니다.
덤으로 versionCode만 보고 `git log`에서 정확한 커밋을 찾아갈 수 있습니다.

**주의점.** 커밋을 하지 않으면 빌드 번호가 안 올라갑니다. 배포 스크립트가
`dist/*` 태그와 비교해 "이미 배포된 번호"면 빌드 전에 중단시킵니다.
히스토리를 rewrite(rebase/force push)해서 커밋 수가 줄어들면 CI가 에러로 막습니다.

## versionName = pubspec의 x.y.z

`pubspec.yaml`의 `version: 1.0.0+1`에서 **앞부분만** 씁니다. `+1`은
`flutter run`용 placeholder일 뿐이고 배포 빌드는 항상 덮어씁니다.

기능이 쌓여 의미 있는 릴리스가 되면 `1.0.0` → `1.1.0` 처럼 손으로 올리고
커밋하세요. 그 커밋이 곧 새 versionCode를 만듭니다.

## dist/* 태그 = 배포 이력

배포가 성공하면 `dist/<versionCode>` 태그가 찍히고 origin에 푸시됩니다.
이 태그가 두 가지 역할을 합니다:

1. **릴리스 노트의 시작점** — 다음 배포의 노트는 `dist/30..HEAD`의 커밋 제목들로
   자동 생성됩니다 (merge 커밋 제외).
2. **중복 배포 차단** — 마지막 태그보다 크지 않은 번호는 거부됩니다.

```powershell
git tag -l 'dist/*' --sort=-version:refname   # 배포 이력 최신순
git show dist/30                              # 그 빌드가 정확히 어느 커밋인지
git log dist/29..dist/30 --oneline            # 두 배포 사이 변경
```

## 릴리스 노트

기본은 자동 생성입니다. 직접 쓰려면:

```powershell
pwsh tool/distribute-android.ps1 -Notes "휴식 타이머 위젯 수정"
```

자동 생성 결과가 곧 테스터가 읽는 글이므로, **커밋 메시지 제목이 릴리스 노트
품질을 결정합니다.** 커밋 제목을 사용자 관점에서 쓰면 그대로 쓸 만한 노트가
나옵니다.

## 전체 흐름

```
커밋 → main 푸시
        │
        ├─ GitHub Actions: analyze → test → 서명 빌드 → 서명 검증 → 업로드 → dist/N 태그
        │                  (versionCode = 커밋 수, 노트 = dist/이전..HEAD)
        │
        └─ 또는 로컬: pwsh tool/distribute-android.ps1   ← 같은 공식, 같은 태그
```

둘 다 같은 규칙을 쓰므로 섞어 써도 번호가 충돌하지 않습니다.
다만 로컬 배포 후에는 태그를 꼭 푸시해야 CI가 이력을 이어받습니다
(스크립트가 자동으로 푸시하고, 실패하면 경고합니다).
