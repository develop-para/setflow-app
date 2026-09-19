# 인증 플로우

정책은 `AGENTS.md` 4절에 있다. 이 문서는 **화면이 실제로 어떤 순서로 도는지**와
**Supabase 대시보드에서 무엇을 켜야 하는지**를 적는다.

앱 코드는 전부 `AuthService` 포트를 통한다(`lib/services/auth_service.dart`).
Supabase를 아는 건 어댑터 한 개(`supabase_auth_service.dart`)뿐이다.

## 계정이 없어도 앱은 다 쓸 수 있다

기록·루틴·캘린더·통계는 로컬 저장소에서 돈다. 서버가 필요한 행동에 닿는 순간에만
`requireSignIn(context, reason: ...)`이 이유를 설명하고 로그인을 청한다.

## 이메일 가입

운영 정책은 인증 메일 없이 즉시 가입이다. 2026-09-20 공개 Auth 설정의
`mailer_autoconfirm=true`를 확인했고, 임시 계정의 실제 가입에서 세션 발급과
회원 권한 RPC의 HTTP 200을 확인한 뒤 임시 계정을 삭제했다. 이메일은 로그인
아이디이며, 이 설정만으로 그 메일함을 소유한 사람이라고 증명되지는 않는다.

```
회원가입 → (프로젝트 설정에 따라)
  ├─ 확인 메일 OFF → 세션 발급, 즉시 사용
  └─ 확인 메일 ON  → 세션 없음 → "메일 확인" 안내 + 60초 쿨다운 재전송 버튼
```

재전송이 없으면 **계정이 영구히 잠긴다.** 계정은 이미 존재해서 재가입이 막히고,
미확인이라 로그인도 막히기 때문이다. 그래서 재전송은 선택 기능이 아니다.

## 비밀번호 재설정

```
로그인 화면 "비밀번호를 잊으셨나요?"
  → 이메일 입력 → resetPasswordForEmail
  → (메일의 링크) → AuthEvent.passwordRecovery
  → main.dart가 NewPasswordScreen을 push → updatePassword
```

두 가지가 의도적이다.

- **계정 존재 여부를 알려주지 않는다.** 없는 주소여도 성공처럼 응답하고 문구는
  "가입된 계정이 있다면 보냈어요"다. 아니면 이 폼이 회원 조회 도구가 된다.
- **`passwordRecovery`를 `signedIn`으로 취급하지 않는다.** 복구 세션은 비밀번호를
  바꾸라고 준 것이다. 홈으로 보내면 로그인에 성공한 것처럼 보이지만 비밀번호는
  여전히 기억 못 하는 그 비밀번호다. 재설정 화면을 닫으면 세션을 정리한다.

## 비밀번호 변경 (로그인 상태)

마이 > 비밀번호 변경. **현재 비밀번호를 반드시 다시 묻는다** — 세션이 살아 있다는 건
본인이라는 증명이 아니다. 잠금 해제된 폰만으로 계정을 빼앗을 수 있으면 안 된다.

소셜 계정에는 이 항목이 **뜨지 않는다**(`currentUser.email`이 없다). 비밀번호가
제공자 쪽에 있어서 여기서는 바꿀 수 없다.

## 트레이너는 승인이 따로다

가입은 회원과 똑같이 즉시 된다. 트레이너 화면만 관리자 승인 후 열린다.
진실은 서버의 `BusinessAccess.availableRoles`이고, 게이트는 `requireProAccess()`다.
신청서 상태(`applicationStatus`)를 진실로 쓰지 말 것 — 승인이 취소돼도 상태는 남는다.

## 우리 DB의 계정 정보

`AccountProfileRepository` 포트로 본인의 이메일·생년월일을 조회하고 저장한다.
마이 > 계정 정보에서 생년월일을 입력하거나 지울 수 있다. 날짜는 선택 정보이고
공개 프로필·운동 스냅샷·트레이너 공유 데이터에 넣지 않는다.

- 이메일: 기존 `public.users.email`에 보관하며 인증 서비스에서 변경되면 동기화한다.
- SNS 연결: `private.account_identity_links`에 제공자와 고유 subject를 보관한다.
  클라이언트 메타데이터와 이메일 문자열로 계정을 연결하지 않는다.
- 생년월일: `private.account_personal_details`에 보관한다. 테이블 직접 접근은 막고,
  유효한 현재 세션에 대해 본인 조회·저장 RPC만 허용한다.

`20260919231805_portable_account_profiles.sql`을 2026-09-20 운영 서버에 적용했다.
기존 SNS/이메일 식별자 복사 수가 원본과 일치하고, 익명 RPC 호출·인증 사용자의
테이블 직접 접근·이메일 직접 변경 권한이 없음을 확인했다. 두 private 테이블은
RLS 정책을 만들지 않아 기본 거부로 유지하고, 서버 함수만 접근하도록 설계했다.
브라우저에서 임시 계정의 즉시 가입 → 생년월일 저장 → 재조회 → 삭제를 확인했으며,
DB 저장값도 함께 검사했다. 임시 계정과 연결된 개인정보는 검증 후 삭제했다.

Google 기본 로그인은 생년월일이나 Google 비밀번호를 주지 않는다. SNS를 활성화할 때
생년월일 입력 단계를 연결하고, 자체 비밀번호는 사용자가 별도로 정하도록 한다.
현재 운영의 Google·Kakao·Apple 로그인은 비활성이다. 이 변경은 계정 데이터 분리이며
**Supabase Auth를 대체하는 자체 로그인 서버가 완성됐다는 뜻은 아니다.**

자체 인증 서버 전환의 계약과 선행 설정은 [Vercel 인증 이전](vercel-auth-migration.md)을 따른다.

## 시작할 화면 선택

한 로그인 계정에 연결된 역할을 선택한다. 서로 다른 이메일 계정을 병합하거나
선택으로 새 권한을 주는 기능은 아니다.

```
앱 로딩 / 로그인 완료
  ├─ 게스트 → 개인 운동 화면
  └─ 서버 get_my_business_access로 현재 세션·계정·역할 확인
       ├─ 회원만 → 개인 운동 화면
       ├─ 여러 역할 → 회원 / 트레이너 / 사업장 / 운영 관리자 중 보유한 역할 선택
       └─ 확인 실패 → 다시 확인 / 개인 운동 기록으로 계속 / 로그아웃
```

선택을 누를 때 서버 권한을 다시 조회한다. 선택은 실행 중에만 기억하고 다음 실행이나
다른 계정 로그인 때 다시 묻는다. 일반 새로고침이나 운동 도중 추가 승인을 받은 경우에는
선택 화면을 자동으로 띄우지 않는다. 게스트와 오프라인 개인 기록은 계속 사용할 수 있다.

`BusinessRepository.loadAccess()`의 Supabase 구현은 `get_my_business_access` RPC를
사용한다. 회원·트레이너·사업장·관리자 권한을 클라이언트가 신청서나 저장된 역할로
조합하지 않는다. 서버가 돌려준 `available_roles`가 유일한 입장 기준이다.

## 서버 세션과 변조 앱 대응

`20260919163342_server_managed_workspace_access.sql`은 다음을 추가한다.

- JWT의 `session_id`와 `sub`가 실제 `auth.sessions`의 같은 사용자에 속해야 한다.
  만료된 `not_after`, 삭제된 세션, 삭제·차단된 Auth 사용자, 익명 Auth 사용자는 거절한다.
- `public.users.status`가 `active`여야 한다. 클라이언트가 수정 가능한 사용자
  메타데이터나 저장된 역할은 이 판정에 사용하지 않는다.
- PostgREST의 `private.check_app_session` 사전 요청 검사로 테이블·뷰·RPC 호출을
  보호한다. 기존 사전 요청 훅이 있으면 덮어쓰지 않고 마이그레이션을 중단한다.
- 현재의 public RLS 테이블 및 `storage.objects`에 제한 정책을 **추가**한다.
  기존 행 소유권 정책과 AND로 결합되며 새로운 조회·수정 권한을 부여하지 않는다.
  새 테이블을 추가할 때도 `app_active_session` 제한 정책을 함께 추가해야 한다.
- 트레이너·사업장의 코칭 루틴 직접 쓰기는 소유권에 더해 현재 승인을 검사한다.
  승인 서류 제출에 쓰이는 소유권 함수 자체는 승인 전에도 사용 가능하다.

세션 폐기 후에도 JWT 서명은 유효할 수 있어 DB의 현재 세션을 확인한다.
[Supabase 세션 문서](https://supabase.com/docs/guides/auth/sessions#how-to-ensure-an-access-token-jwt-cannot-be-used-after-a-user-signs-out)
참고. 사전 요청 훅은 PostgREST에만 적용되므로 Storage·Realtime에는 RLS 검사도 필요하다.
[Data API 보안 문서](https://supabase.com/docs/guides/api/securing-your-api#pre-request-checks)
참고. 이미 발급한 파일 URL의 유효기간, 이미 전달된 데이터, 별도 Edge Function의 인증은
별도로 관리해야 한다.

이 정책은 권한 없는 서버 이용을 막는다. 정상 계정으로 자기 권한 안에서 접속하는
변조 앱을 식별하거나, 기기 안의 오프라인 기능 실행을 막는 앱 무결성 검증은 포함하지 않는다.

**배포 순서:** 서버 마이그레이션 → 앱 배포. RPC가 없거나 실패하면 앱에서 예전 방식으로
권한을 추측해 우회하지 않는다. 운영 서버 적용 전 아래 격리 테스트를 실행한다.

```sh
npm install --prefix .dart_tool/workspace-security --no-audit --no-fund @electric-sql/pglite@0.5.8
node tool/test_workspace_access.mjs
node tool/test_account_profiles.mjs
```

이 테스트는 일회성 메모리 Postgres에서 마이그레이션 원문을 실행한다. 계정 정지·세션
폐기·다른 계정의 세션·메타데이터 권한 위조·승인 취소·게스트 경로·스토리지 행 격리를
검증하며 운영 서버에는 접속하지 않는다. 실제 Supabase 서비스까지의 검증은 배포 후 별도다.
`Verify` CI도 세션·역할 18개와 계정 정보 보호 10개 검사를 실행한다.

2026-09-20 운영 서버에 적용했다. 기존 로그인 세션의 권한 조회, 세션 없는 요청 거부,
게스트 운동 카탈로그의 실제 HTTP 응답을 확인했다. RLS 제한 정책은 143개 테이블에 적용됐다.

2026-09-20 운영 서버 점검에서 유출 비밀번호 차단이 꺼져 있는 것도 확인했다.
배포와 별도로 프로젝트 플랜/설정에서 활성화 가능 여부를 확인해야 한다.
[비밀번호 보호 설정](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection)
참고. 기존 RPC/함수에 대한 Advisor 경고까지 전부 해결한 보안 감사로 해석하지 않는다.

## Supabase 대시보드에서 켜야 하는 것

| 항목 | 위치 | 비고 |
| --- | --- | --- |
| Confirm email | Authentication > Providers > Email | 끄면 가입 즉시 로그인 |
| Site URL | Authentication > URL Configuration | 웹 재설정 링크가 돌아올 곳 |
| Redirect URLs | 같은 화면 | `com.teampara.setflow://login-callback` **필수**, Vercel 도메인(프리뷰는 와일드카드) |
| SMTP | Authentication > Emails | 기본 SMTP는 **시간당 한 자리 수**로 제한된다. 실사용 전에 반드시 교체할 것 |

리다이렉트 스킴은 `AndroidManifest.xml`과 `ios/Runner/Info.plist`에 이미 등록돼 있다.
허용목록에 빠지면 **메일 링크를 눌러도 앱이 안 열린다** — 코드는 멀쩡한데 안 되는 대표적인 경우다.

소셜 로그인은 `SupabaseConfig`의 `--dart-define` 플래그로 켜기 전까지 버튼 자체가 안 보인다
(`isConfigured`). 대시보드에서 provider를 켜는 것과 빌드 플래그를 **둘 다** 해야 한다.

## 테스트

`test/auth_flows_test.dart`가 위 규칙들을 잠근다 — 존재 여부 비노출, 재전송 쿨다운,
현재 비밀번호 검증, 소셜 계정 항목 숨김, 실패 시 성공 패널을 띄우지 않기.
백엔드 없이 도는 이유는 `Auth.use(FakeAuthService())`로 포트를 갈아끼울 수 있어서다.
