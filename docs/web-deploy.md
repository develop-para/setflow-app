# 웹 배포 (Vercel)

같은 Flutter 코드베이스를 웹으로도 빌드해 Vercel에 올린다. 안드로이드는
`android-distribute.yml`이 Firebase App Distribution으로 보내고, 웹은 Vercel이 저장소를 보고
직접 빌드한다 — 두 경로가 **같은 커밋, 같은 Flutter 버전**을 쓴다.

## Vercel에서 한 번만 하는 설정

1. Vercel에서 **New Project → develop-para/setflow-app 임포트**
2. Framework Preset: **Other** (자동 감지에 맡기지 말 것 — Flutter는 목록에 없다)
3. 나머지는 건드리지 않는다. `vercel.json`이 빌드 명령·출력 경로·라우팅을 다 지정한다.
4. 배포

환경 변수는 **선택**이다. 없으면 `SupabaseConfig`의 기본값(운영 프로젝트)을 쓴다.
프리뷰를 다른 Supabase 프로젝트에 붙이고 싶을 때만 넣는다:

| 이름 | 설명 |
| --- | --- |
| `SUPABASE_URL` | 프로젝트 URL |
| `SUPABASE_PUBLISHABLE_KEY` | publishable(anon) 키. **service role 키를 넣지 말 것** |

## 어떻게 빌드되나

Vercel 빌더에는 Flutter가 없다. `tool/vercel_build.sh`가 매 빌드마다 SDK를 가져온다.

- **버전을 핀으로 고정**했다(`3.44.7`). CI·릴리스 빌드와 같은 값이어야 한다 —
  웹 번들만 다른 SDK로 컴파일되면 재현 안 되는 버그의 원인이 된다.
  Flutter를 올릴 때 `tool/vercel_build.sh`와 `.github/workflows/*.yml`을 **같이** 고칠 것.
- `--depth 1 --branch <version>`으로 받는다. 전체 이력은 1GB가 넘고 쓸 일이 없다.

## vercel.json이 하는 일

- **SPA 리라이트** — 모든 경로를 `index.html`로 보낸다. 이게 없으면 새로고침이나 딥링크가
  404가 된다. Flutter 라우팅은 클라이언트에서 일어나므로 서버는 항상 같은 문서를 줘야 한다.
- **캐시 헤더** — `assets/`·`canvaskit/`은 해시가 박힌 불변 파일이라 1년 캐시.
  `index.html`·`flutter_bootstrap.js`·`flutter_service_worker.js`·`version.json`은 `no-cache` —
  이 넷이 캐시되면 **새 배포가 사용자에게 영원히 안 닿는다.**

## 초대 링크 착지 페이지와 앱링크 검증 파일도 여기서 나간다

`web/` 아래 파일은 Flutter 웹 빌드가 그대로 `build/web`으로 복사하므로 Vercel이 정적으로
서빙한다. 앱 밖(메신저)에서 열리는 것들이 여기 산다:

- `web/join.html` — 함께 방 초대 링크의 착지 페이지. `vercel.json`이 `/together/join`을 이
  파일로 보낸다(SPA 폴백보다 **앞에** 있어야 한다). 열리면 커스텀 스킴으로 앱을 부르고,
  앱이 없으면 코드를 보여 준다. 앱은 `SetflowWeb.togetherJoin(code)`로 이 주소를 만든다.
- `web/.well-known/assetlinks.json` — 안드로이드 앱링크 검증. 업로드 키의 SHA-256이 들어
  있고, 매니페스트의 `autoVerify` 인텐트 필터와 짝이다. 검증이 되면 링크가 브라우저 없이
  앱으로 바로 간다. **서명 키를 바꾸면 이 파일도 바꿔야 한다**
  (`keytool -list -v -keystore android/app/upload-keystore.jks -alias upload`).
- iOS(`apple-app-site-association`)는 아직 없다 — Apple Team ID가 정해지면 같은 자리에 둔다.
  그때까지 iOS는 Safari가 `join.html`을 열고 "앱에서 열기"로 넘어간다.

도메인은 **`setflow-app.vercel.app`** 이다. `setflow.app`은 우리 것이 아니다(남의 DJ 사이트).
도메인을 바꾸면 `lib/services/setflow_web.dart`, `AndroidManifest.xml`의 https host,
`supabase/functions/join`(리다이렉트 예비 주소) 셋을 같이 바꾼다.

Supabase 엣지 펑션에 페이지를 두지 못하는 이유: 기본 도메인의 HTML 응답을 게이트웨이가
`text/plain` + sandbox CSP로 바꾼다. 커스텀 도메인 애드온이 있어야 풀린다.

## 인증은 웹에서 그대로 동작한다

`signInWithSocial`이 모바일에서만 커스텀 스킴 리다이렉트를 쓰고 웹에서는 현재 origin을 쓴다
(`kIsWeb ? null : SupabaseConfig.mobileAuthRedirect`). 소셜 로그인을 켤 때 Supabase의
Redirect URL 허용목록에 **Vercel 도메인을 추가**해야 한다(프리뷰 도메인 포함하려면 와일드카드).

## PR에서 웹 빌드도 검사한다

`verify.yml`에 `flutter build web --release`가 들어 있다. 모바일에서는 컴파일되는데
웹에서 깨지는 코드(`dart:io`, 플랫폼 채널)를 **Vercel이 아니라 PR에서** 잡기 위한 것이다.

## 로컬에서 확인

```sh
flutter build web --release
# build/web 을 아무 정적 서버로 열어본다 (SPA 폴백 필요)
```
