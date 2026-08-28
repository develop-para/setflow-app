# 푸시 알림

설정의 **코칭 피드백 알림**과 **커뮤니티 반응 알림** 두 스위치가 실제로
무언가를 켜게 만든 구조. 규칙은 `AGENTS.md`에 있고, 여기엔 **왜 이렇게 나눴는지**와
**사람이 직접 해야 하는 것**만 적는다.

## 왜 발신함(outbox)을 거치는가

트리거가 FCM을 직접 부르면 **남의 서비스가 느릴 때 댓글 쓰기가 같이 느려진다.**
알림은 부수효과지 본 동작이 아니다. 그래서 트리거는 `push_outbox`에 줄만 넣고
곧바로 끝나고, 실제 전송은 1분마다 도는 크론이 엣지 펑션을 깨워서 한다.
실패는 `attempts`로 흡수되고(5회), 끝내 못 보내도 원래 동작은 이미 끝나 있다.

엣지 펑션을 쓴 이유는 하나다 — FCM은 외부 API고 Postgres 안에서 OAuth2 토큰을
서명해 부를 방법이 없다. `AGENTS.md` 2절이 허용하는 바로 그 경우이며,
사용자 핵심 동작 경로에는 없다.

## 조각들

| 무엇 | 어디 |
|---|---|
| 기기 토큰 | `public.device_tokens` + `register_push_token` / `unregister_push_token` RPC |
| 발신함 | `public.push_outbox` (클라이언트는 못 읽는다 — service_role 전용) |
| 언제 보낼지 | `private.notify_consultation_reply` / `notify_post_like` / `notify_post_comment` |
| 보낼지 말지 | `private.push_enabled` — 설정의 진실은 `app_state_snapshots.payload`다 |
| 실제 전송 | `supabase/functions/send-push` (FCM HTTP v1) |
| 깨우기 | `cron.job` `setflow-push-drain`(매분) · `setflow-push-prune`(매일 04:30) |
| 앱 포트 | `lib/services/push_service.dart` (`Push.instance`) |
| 앱 어댑터 | `lib/services/firebase_push_service.dart` — Firebase를 아는 유일한 파일 |

**알림용 설정 테이블을 따로 두지 않았다.** 스냅샷이 이미 사용자의 선택을 들고
있는데 별도 테이블을 만들면 두 곳이 어긋난다 — 설정 화면에서 고친 값과 서버가
보는 값이 달라지는 것이 정확히 지금 걷어낸 문제다.

**초기 스키마의 `coaching_feedbacks`는 쓰지 않는다.** 앱이 만드는 코칭 피드백은
`consultation_messages`다(`reply_business_consultation`이 쓴다). `coaching_feedbacks`는
아무도 쓰지 않는 잔재다.

## 함정

- **토큰은 계정이 아니라 기기에 붙는다.** 같은 폰을 두 사람이 쓰면 토큰이 계정을
  옮겨 다녀야 한다. 그래서 `device_tokens.token`이 unique이고 `register_push_token`이
  upsert로 소유자를 갈아탄다. 로그아웃할 때 **세션이 살아 있는 동안** 떼어야 하므로
  `AppState.logout()`이 가장 먼저 `_releasePushToken()`을 부른다.
- **토큰은 조용히 바뀐다.** 재설치·복원·주기적 회전. 한 번 등록하고 끝내면
  언젠가 배달이 멈추는데 아무도 모른다. `tokenChanges`를 구독하는 이유다.
- **FCM 404/403은 죽은 토큰이라는 뜻이다.** 안 지우면 영원히 재시도한다.
  `send-push`가 그 자리에서 지운다.
- **iOS는 APNs 키가 있어야 토큰이 나온다.** 없으면 `getToken()`이 던지는데,
  그건 실패가 아니라 "아직"이다 — 다음 실행에 다시 시도한다.
- **초기화 실패로 앱이 죽으면 안 된다.** 설정 파일이 없는 플랫폼에서
  `Firebase.initializeApp()`이 던지면 스플래시에서 앱이 통째로 죽는다.
  `FirebasePushService.create()`가 그걸 잡아 `DisabledPushService`로 떨어진다.
  알림이 안 오는 것과 앱이 안 켜지는 것은 등급이 다른 실패다.

## 사람이 직접 해야 하는 것

코드와 마이그레이션·엣지 펑션은 배포돼 있다. 아래 셋이 채워지기 전까지는
**발신함에 줄은 쌓이지만 전송은 되지 않는다**(크론이 조용히 아무것도 안 한다).

**1·2번은 2026-08-28에 끝났다** (프로덕션 프로젝트 `fblrtxnpgftrtplqmsqe`). 새 프로젝트로
옮기거나 키를 돌릴 때만 다시 한다. 3번(iOS)은 아직이다.

### 1. FCM 서비스 계정 키 (필수)

Firebase 콘솔 → 프로젝트 `setflow-18eeb` → 프로젝트 설정 → 서비스 계정 →
**새 비공개 키 생성**. 받은 JSON 전체를 Supabase 엣지 펑션 시크릿에 넣는다:

```sh
supabase secrets set FCM_SERVICE_ACCOUNT="$(cat setflow-fcm.json)"
```

(대시보드에서는 Edge Functions → Secrets.) 이 키는 저장소에 넣지 말 것.

### 2. 크론이 엣지 펑션을 부를 수 있게 (필수)

`private.drain_push_outbox()`는 주소와 키를 SQL에 박지 않고 Vault에서 읽는다.
둘 중 하나라도 없으면 조용히 아무것도 하지 않는다:

```sql
select vault.create_secret('https://<project-ref>.supabase.co', 'project_url');
select vault.create_secret('<service_role_key>', 'service_role_key');
```

### 3. iOS (iOS 배포를 시작할 때)

- Apple Developer 계정에서 **APNs 인증 키(.p8)** 를 만들어 Firebase 콘솔의
  iOS 앱에 올린다.
- Firebase 콘솔에서 iOS 앱을 등록하고 `GoogleService-Info.plist`를
  `ios/Runner/`에 넣는다.
- Xcode에서 **Push Notifications**와 **Background Modes > Remote notifications**
  capability를 켠다.

그전까지 iOS에서는 `FirebasePushService.create()`가 실패해 푸시가 꺼진 채로
동작한다 — 앱은 정상이고, 알림 설정에는 "푸시 알림을 쓸 수 없는 기기예요"가 뜬다.

## 확인하는 법

```sql
-- 줄이 쌓이는가 (트리거가 도는가)
select id, kind, user_id, created_at, sent_at, attempts, last_error
from push_outbox order by created_at desc limit 20;

-- 크론이 도는가
select * from cron.job_run_details
where jobid = (select jobid from cron.job where jobname = 'setflow-push-drain')
order by start_time desc limit 5;
```

`sent_at`이 계속 null이고 `attempts`가 오르면 `last_error`를 본다.
`attempts`가 0인 채 그대로면 크론이 못 부르는 것이다 — 위 2번 Vault 시크릿을 확인하고,
`cron.job_run_details`의 `status`가 `failed`면 `return_message`를 본다. pg_net 함수는
`net.http_post`다(`extensions.net.`이 아니다 — 20260828070000이 그 실수를 고쳤다).
