# Android 테스트 배포 (Firebase App Distribution)

Setflow의 백엔드는 Supabase입니다. Firebase는 푸시와 APK 테스트 배포에 사용합니다.
테스터 빌드는 공식 App Distribution Android SDK로 앱 안에서 새 버전을 확인하고 설치합니다.
화면은 `AppUpdateService` 포트만 사용하고 SDK 호출은 네이티브 어댑터에 격리합니다.

## 앱 안에서 업데이트

1. 최초 한 번 [Firebase App Testers API](https://console.cloud.google.com/apis/library/firebaseapptesters.googleapis.com?project=setflow-18eeb)를 활성화합니다.
2. 이 기능이 포함된 첫 APK는 기존 Firebase 초대 링크로 설치합니다. 이전 APK에 기능이 소급 적용되지는 않습니다.
3. 앱의 **설정 → 앱 업데이트 → 계정 연결하고 확인**에서 초대받은 Google 계정으로 연결합니다.
   앱의 회원 로그인과는 별개이며 게스트도 사용할 수 있습니다.
4. 이후 앱 실행/복귀 시 새 버전을 조용히 확인합니다(5분 간격 제한).
   새 버전이 있으면 홈에 안내가 나오며, 설정에서도 직접 확인할 수 있습니다.
5. **업데이트**를 누르면 SDK가 다운로드하고 Android 설치 화면으로 이어집니다.
   기기에 따라 출처를 알 수 없는 앱 설치 허용이 필요합니다. 설치 취소 시 기존 앱을 계속 씁니다.

운동 중에는 업데이트 팝업을 자동으로 열지 않습니다. 설치는 기록을 마친 뒤 진행합니다.
현재 계정에 공개된 새 빌드만 조회하며, 실패를 "최신 버전"으로 표시하지 않습니다.

설정의 **앱 업데이트** 항목과 상세 화면에는 **현재 설치 버전과 빌드 번호**가 함께 표시됩니다.
이 값은 설치 패키지에서 읽으므로 CI가 지정한 배포 빌드 번호도 그대로 보이며, Google 계정
연결 없이 확인할 수 있습니다. 새 버전이 있으면 현재 버전과 구분해 함께 표시합니다.
자체 업데이트를 지원하지 않는 일반/스토어 빌드에서는 **앱 버전** 항목으로 확인합니다.

CI와 `tool/distribute-android.ps1`은 `--dart-define=APP_DISTRIBUTION_UPDATES=true`를 전달합니다.
일반 `flutter build apk`/`appbundle`은 기본적으로 자체 업데이트 SDK를 포함하지 않습니다.
**Google Play 빌드에는 이 플래그를 넣지 않습니다.** Flutter와 Gradle이 동일한 플래그를 읽어
메뉴 노출과 SDK 포함 여부가 일치합니다.

검증: `flutter test test/app_update_test.dart`와
`flutter build apk --debug --dart-define=APP_DISTRIBUTION_UPDATES=true`.
실제 설치 검증은 같은 배포 서명 키로 서명한 빌드 A/B를 Firebase에 배포하고,
A에서 연결한 뒤 더 높은 versionCode의 B를 설치하여 기록 유지까지 확인합니다.
디버그 서명 APK로는 기존 Firebase 배포본을 덮어쓸 수 없습니다.

공식 문서: [App Distribution 앱 내 업데이트](https://firebase.google.com/docs/app-distribution/set-up-alerts?platform=android).

## 최초 1회 세팅

### 1. 계정 연결 (이 프로젝트 전용)

Firebase CLI는 **PC 전체에 계정 하나**를 전역 기본값으로 캐시합니다
(`~/.config/configstore/firebase-tools.json`). 다른 프로젝트에서 쓰던 계정이
남아 있을 수 있으므로, setflow 전용 계정을 따로 추가해 씁니다.

```powershell
firebase login:add admin@teampara.co.kr   # 브라우저 로그인, 전역 기본값은 안 건드림
firebase login:use admin@teampara.co.kr   # 이 저장소 디렉터리의 기본 계정으로 지정
```

`login:use`의 디렉터리 매핑은 절대경로 기준이라 다른 PC에 클론하면 따라오지
않습니다. 그래서 [tool/firebase-distribution.json](../tool/firebase-distribution.json)의
`account` 값으로도 계정을 박아 두었고, 배포 스크립트가 `--account`로 명시 전달합니다.
둘 중 하나만 있어도 동작하지만, 둘 다 있으면 어느 PC에서든 계정이 헷갈리지 않습니다.

현재 상태 확인은 `firebase login:list`.

### 2. Firebase 프로젝트와 Android 앱 등록

프로젝트 `setflow-18eeb`, 앱 `com.teampara.setflow`는 이미 등록되어 있습니다.
새로 만들어야 한다면:

```powershell
firebase projects:create <project-id>
firebase apps:create android com.teampara.setflow --project <project-id>
```

출력에 나오는 App ID(`1:1234567890:android:abcdef...`)를
`firebase-distribution.json`의 `appId`에 넣습니다.
App ID와 계정 이메일은 비밀값이 아니라서 커밋해도 됩니다.

`android/app/google-services.json`과 Google Services Gradle 플러그인은 이미
푸시 알림을 위해 연결되어 있고, 앱 내 업데이트 SDK도 같은 프로젝트 설정을 사용합니다.

### 3. 테스터 그룹 만들기

Firebase 콘솔 → App Distribution → Testers & Groups에서 그룹을 만들고
(기본값 `testers`) 테스터 이메일을 추가합니다. 그룹 별칭이
`firebase-distribution.json`의 `groups` 값과 같아야 합니다.

### 4. 서명 키

`android/key.properties` + `android/app/upload-keystore.jks`가 서명을 담당합니다.
둘 다 **gitignore 대상**이라 저장소에 없습니다.

> ⚠️ **keystore를 잃어버리면 기존 테스터는 업데이트를 설치할 수 없습니다.**
> 서명이 다른 APK는 Android가 덮어쓰기를 거부하므로, 테스터가 앱을 지우고
> 다시 깔아야 합니다(= 로컬 데이터 손실). Play 스토어에 올린 뒤라면 아예 같은
> 앱으로 업데이트할 수 없습니다. keystore 파일과 비밀번호는 반드시 별도
> 안전한 곳(비밀번호 관리자 등)에 백업하세요.

`android/key.properties`가 없으면 릴리스 빌드는 debug 키로 폴백합니다
([android/app/build.gradle.kts](../android/app/build.gradle.kts)). 로컬
`flutter run --release`는 계속 되지만, 배포 스크립트는 이 경우 빌드를 거부합니다.

## 배포하기 — 자동 (기본)

**main에 푸시하면 GitHub Actions가 자동 배포합니다.**
[.github/workflows/android-distribute.yml](../.github/workflows/android-distribute.yml)

```
main 푸시 → analyze → test → 서명 빌드 → 서명 검증 → 업로드 → dist/N 태그 푸시
```

- `.md`·`docs/`·`.fry/`만 바뀐 푸시는 러너를 쓰지 않고 건너뜁니다
- 동시 실행은 `concurrency`로 직렬화됩니다 (태그 경합 방지)
- Actions 탭에서 **Run workflow**로 수동 실행도 가능하고, 이때 릴리스 노트를
  직접 입력할 수 있습니다

버전 번호와 릴리스 노트가 어떻게 정해지는지는 [versioning.md](versioning.md) 참고.

### GitHub Secrets (서명용, 4개)

| 이름 | 값 |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | `android/app/upload-keystore.jks`를 base64 인코딩한 문자열 |
| `ANDROID_KEYSTORE_PASSWORD` | keystore 비밀번호 |
| `ANDROID_KEY_PASSWORD` | 키 비밀번호 (여기서는 keystore와 동일) |
| `ANDROID_KEY_ALIAS` | `upload` |

```powershell
$b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes("android\app\upload-keystore.jks"))
gh secret set ANDROID_KEYSTORE_BASE64 --repo develop-para/setflow-app --body $b64
```

> Secrets는 암호화되지만 저장소에 write 권한이 있는 사람은 워크플로를 통해
> 꺼내 쓸 수 있습니다. 서명 키를 GitHub에 맡긴다는 뜻이므로 저장소 접근 권한을
> 좁게 유지하고, 협업자가 생기면 main 브랜치 보호 규칙을 거세요.

### Google 인증 — Workload Identity Federation (키 없음)

Firebase 업로드 인증에는 **서비스 계정 키를 쓰지 않습니다.** GitHub이 발급한
OIDC 토큰을 Google이 검증해 단기 자격증명을 내주는 방식이라, GitHub에 저장되는
Google 자격증명이 없습니다.

이 선택은 보안 취향이 아니라 필수였습니다 — `teampara.co.kr` 조직에
`constraints/iam.disableServiceAccountKeyCreation` 정책이 걸려 있어 애초에
서비스 계정 키를 발급할 수 없습니다. WIF는 그 정책과 싸우지 않고 우회합니다.

구성된 리소스 (프로젝트 `setflow-18eeb`, 번호 `587270655673`):

| 항목 | 값 |
|---|---|
| 서비스 계정 | `github-actions-distributor@setflow-18eeb.iam.gserviceaccount.com` |
| 역할 | `roles/firebaseappdistro.admin` |
| WIF 풀 | `github` |
| 제공자 | `github-actions` (issuer `token.actions.githubusercontent.com`) |
| 접근 조건 | `assertion.repository == 'develop-para/setflow-app'` |
| 바인딩 | 위 저장소의 워크플로만 `roles/iam.workloadIdentityUser`로 서비스 계정 가장 가능 |

제공자 리소스 이름과 서비스 계정 주소는 비밀값이 아니라 워크플로 `env`에
그대로 적혀 있습니다. 저장소 이름 조건 때문에 다른 저장소가 이 값을 알아도
자격증명을 받을 수 없습니다.

저장소를 다른 조직/이름으로 옮기면 **조건과 바인딩을 함께 고쳐야 합니다.**
안 고치면 인증 단계에서 실패합니다:

```powershell
gcloud iam workload-identity-pools providers update-oidc github-actions `
  --location=global --workload-identity-pool=github `
  --attribute-condition="assertion.repository=='<new-owner>/<new-repo>'" `
  --project setflow-18eeb
```

## 배포하기 — 수동

CI 없이 지금 당장 보내야 할 때:

```powershell
pwsh tool/distribute-android.ps1
```

스크립트가 하는 일:

1. `android/key.properties` 존재 확인 (없으면 중단)
2. 버전 계산 — versionName은 pubspec, versionCode는 커밋 수.
   마지막 `dist/*` 태그보다 크지 않으면 **빌드 전에** 중단
3. 릴리스 노트 생성 (마지막 태그 이후 커밋 제목, `-Notes`로 덮어쓰기 가능)
4. `flutter build apk --release --build-name --build-number`
   — 루트에 `dart-defines.json`이 있으면 `--dart-define-from-file`로 전달
5. `firebase appdistribution:distribute`로 업로드 (`--account` 명시)
6. `dist/<versionCode>` 태그 생성 후 origin에 푸시

주요 옵션: `-NoUpload`(빌드만), `-Arm64Only`(용량 절반), `-NoTag`, `-Force`(같은
번호 재업로드 — Android가 설치를 거부하므로 깨진 아티팩트 교체용).

## 빌드 타임 설정 (소셜 로그인)

[lib/services/supabase_config.dart](../lib/services/supabase_config.dart)의
OAuth 플래그는 `bool.fromEnvironment` 기본값이 `false`라 **소셜 로그인 버튼이
기본적으로 숨겨집니다.** 부분적으로만 설정된 provider가 깨진 로그인 버튼으로
노출되는 걸 막기 위한 의도된 동작입니다.

테스터에게 소셜 로그인을 열어주려면:

1. `tool/dart-defines.example.json`을 루트의 `dart-defines.json`으로 복사
   (gitignore 대상)
2. 켤 provider를 `true`로 변경
3. Supabase 대시보드 → Authentication에서 해당 provider를 실제로 활성화
4. Supabase Auth의 Redirect URL 허용목록에
   `com.teampara.setflow://login-callback` 추가
   — 이 스킴은 [AndroidManifest.xml](../android/app/src/main/AndroidManifest.xml)에
   이미 등록되어 있습니다 (`login-callback`, `routine-share`, `business-invite`)

Supabase URL과 publishable key는 소스에 기본값이 박혀 있어서
`dart-defines.json` 없이도 앱은 정상 동작합니다.

## 테스터 쪽 절차

1. Firebase가 보낸 초대 메일에서 초대 수락
2. 안드로이드 기기에서 App Tester 앱 설치 (또는 웹에서 바로 APK 다운로드)
3. 이후 새 버전이 올라올 때마다 알림 수신

Google Play 스토어를 거치지 않으므로 "출처를 알 수 없는 앱 설치" 허용이
필요할 수 있습니다.
