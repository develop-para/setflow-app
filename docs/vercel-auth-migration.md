# Vercel 자체 인증 이전

## 목표와 현재 상태

가입 시 인증 메일·SNS 인증을 요구하지 않고 이메일을 아이디로 사용한다.
이는 현재 운영에서도 실제 가입 검증을 통과했다. 사용자명이 별도로 필요한 정책은
추가 결정 사항이다. 인증 절차를 생략하는 것과 로그인 서버를 없애는 것은 다르다.

자체 인증은 Vercel의 Node.js API에서 비밀번호와 세션을 확인하고, 앱 소유 PostgreSQL
테이블에서 계정·자격 증명·SNS 식별자·세션을 관리하는 구조다. Vercel 함수의 메모리나
파일시스템은 영구 계정 저장소로 쓰지 않는다.

현재 완료된 것은 계정 프로필 포트와 앱 소유 이메일·SNS 식별자·생년월일 저장 경계다.
Vercel 인증 API, 자체 비밀번호 발급, 기존 계정의 인증 이전은 아직 구현·배포되지 않았다.
`supabase/functions/custom-auth`는 과거 프로토타입이며 활성화해서 대체하지 않는다.

## 구현 계약

- 가입·로그인: 이메일 정규화와 중복 제어, 비밀번호 해시, 지속 저장소를 이용한 요청 제한.
  비밀번호 해시는 검증된 인증 라이브러리의 Argon2id/scrypt 구현을 사용한다.
- 비밀번호: 평문·복호화 가능한 값·Google 비밀번호를 저장하지 않는다. 기존 bcrypt 해시는
  형식을 검증한 전용 이전 절차에서만 다룬다. 로그와 API 응답에 내보내지 않는다.
- 세션: 서버에서 폐기할 수 있는 세션, 만료와 갱신, 로그아웃·정지·비밀번호 변경 시 폐기.
  웹은 HttpOnly/Secure 쿠키와 CSRF 검사, 모바일은 보안 저장소를 사용한다.
- Google: 공식 OAuth/OIDC 흐름의 state·nonce·PKCE와 토큰 서명·issuer·audience·만료를 검증한다.
  `(provider, subject)`로 식별하며 미인증 이메일이 같다는 이유로 기존 계정에 연결하지 않는다.
  별도 비밀번호 설정은 최근 본인 인증 후 사용자가 직접 한다.
- 생년월일: 기본 Google ID 토큰에 없으므로 사용자에게 직접 받는다. 입력값은 본인 진술이며
  신원·연령 인증으로 취급하지 않는다. 선택 정보로 시작하고 삭제 통로를 제공한다.
- 복구: 가입의 이메일 인증 생략과 별개로 비밀번호 재설정에는 소유권 확인이 필요하다.
  재설정 메일 제공자와 만료되는 단일 사용 토큰, 계정 존재 여부를 노출하지 않는 응답을 준비한다.

## 기존 데이터 접근을 먼저 연결한다

현재 데이터 어댑터는 Supabase 클라이언트의 사용자·토큰을 사용하며, RLS와
`private.has_active_app_session()`은 `auth.users` / `auth.sessions`를 검사한다.
여러 테이블의 FK도 `auth.users`에 연결돼 있다. `Auth.use` 한 줄만 바꾸면 데이터 요청이 실패한다.

전환은 다음 순서를 따른다.

1. 운영 Vercel 팀에서 API 배포 권한과 서버 전용 DB 연결을 준비한다.
2. 검증된 인증 라이브러리로 API를 구현하고 격리 DB에서 가입·로그인·로그아웃·갱신·복구를 검증한다.
3. 현재 UUID와 데이터 소유권을 유지하는 계정 이전을 검증한다. 기존 사용자의 계정을 새 UUID로
   만들거나 이메일 문자열만으로 병합하지 않는다.
4. 데이터 API·Storage·Realtime이 새 세션을 검증하도록 이관한다. 앱이 DB에 직접 접근하는 동안
   RLS는 유지한다. 서비스 키로 모든 요청을 대신 실행해 권한 검사를 우회하지 않는다.
5. `AuthService` 어댑터와 데이터 어댑터를 함께 전환하고, 실제 운영 계정의 읽기·쓰기와
   권한 취소를 확인한다. 실패 시 이전 인증으로 되돌릴 수 있는 배포를 유지한다.

## 확인된 배포 선행 조건

2026-09-20 점검:

- 운영 Vercel 프로젝트: `setflow-app`, 팀 `para` (`develop-para1`). 기존 GitHub 자동 배포는 정상이다.
- 로컬 Vercel CLI: `abroadnbroad`, 소속은 `abroadnbroad's projects`뿐이다. 운영 팀의 비밀 설정을
  바꿀 권한이 있는 계정으로 연결해야 한다. 다른 계정에 새 프로젝트를 임의 생성하지 않는다.
- 서버용 `DATABASE_URL`과 Google OAuth 클라이언트는 현재 환경에 없다.
- 기존 Supabase 관리 토큰의 Auth 설정 API는 HTTP 403을 반환했다. 현재 연결로 인증 신뢰 설정을
  바꿀 수 있다고 가정하지 않는다. 공개 설정 조회는 가능하며 이메일 자동 확인은 이미 켜져 있다.

비밀키는 채팅이나 저장소에 넣지 않고 운영 환경 변수에 설정한다. 새 인증 서버가 준비되기 전에
기존 인증·RLS·계정 FK를 제거하지 않는다.

## 근거

- [Google OpenID Connect](https://developers.google.com/identity/openid-connect/openid-connect)
- [Supabase JWT 서명 키](https://supabase.com/docs/guides/auth/signing-keys)
- [Supabase 외부 인증 연동](https://supabase.com/docs/guides/auth/third-party/overview)
