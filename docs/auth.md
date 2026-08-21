# 인증 플로우

정책은 `AGENTS.md` 4절에 있다. 이 문서는 **화면이 실제로 어떤 순서로 도는지**와
**Supabase 대시보드에서 무엇을 켜야 하는지**를 적는다.

앱 코드는 전부 `AuthService` 포트를 통한다(`lib/services/auth_service.dart`).
Supabase를 아는 건 어댑터 한 개(`supabase_auth_service.dart`)뿐이다.

## 계정이 없어도 앱은 다 쓸 수 있다

기록·루틴·캘린더·통계는 로컬 저장소에서 돈다. 서버가 필요한 행동에 닿는 순간에만
`requireSignIn(context, reason: ...)`이 이유를 설명하고 로그인을 청한다.

## 이메일 가입

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
