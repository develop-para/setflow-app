# 백엔드 이식성 — Supabase에서 자체 서버(EC2)로 옮길 때

앱은 나중에 자체 서버로 이전할 계획이다. 이 문서는 **지금 어디까지 격리해 뒀고, 그때 무엇을
갈아끼우면 되는지**를 적는다. 목표는 "이전 = 어댑터 교체"이지 "이전 = 전면 재작성"이 아니게 두는 것.

## 규칙 하나

> **벤더 SDK 타입은 어댑터 밖으로 나가지 않는다.**

`lib/screens/**`와 `lib/widgets/**`에서 `package:supabase`를 import하거나 `SupabaseAuthService`를
직접 부르면 규칙 위반이다. 현재 위반 **0건**.

### 이 문서는 설명이고, 강제는 테스트가 한다

읽고 지키는 규칙은 지켜지지 않는다. 아래 규칙들은 **`test/architecture_test.dart`에 실행 가능한 형태로**
들어 있고, PR마다 CI(`.github/workflows/verify.yml`)가 돌린다. 위반하면 머지 전에 막힌다.

```sh
flutter test test/architecture_test.dart
```

현재 강제되는 규칙 5개:

| 규칙 | 잡는 것 |
| --- | --- |
| 벤더 SDK는 어댑터 밖으로 안 나간다 | 허용 목록 밖 파일의 `import 'package:supabase...'` |
| 화면은 벤더 클래스 이름을 모른다 | screens/widgets/app_state의 `SupabaseClient`·`RealtimeChannel`·`AuthResponse` 등 |
| 백엔드 주소를 코드에 안 박는다 | `SupabaseConfig` 밖의 `supabase.co` |
| 스토리지 URL은 읽는 시점에 만든다 | 레포지토리 밖의 `getPublicUrl`·`createSignedUrl` |
| 엣지 펑션은 의도적으로만 늘린다 | 새로 생긴 `functions.invoke` |

실패 메시지는 **위반 위치 + 왜 그 규칙이 있는지 + 대신 무엇을 할지**를 같이 출력한다.
규칙이 정말 막고 있는 일을 해야 한다면 그건 규칙이 작동한 것이다 — 테스트의 `allow` 목록에
파일을 추가하고 **그 커밋에 이유를 남긴다**. 그러면 예외가 새는 게 아니라 기록된 결정이 된다.

새 제약이 생기면 문서에만 적지 말고 `_rules` 리스트에 한 줄 추가할 것.

## 지금의 경계

Supabase를 아는 파일은 **6개뿐**이고 전부 포트 뒤에 있다.

| 포트(앱 소유 인터페이스) | 현재 어댑터 | 정의 위치 |
| --- | --- | --- |
| `AuthService` | `SupabaseAuthService` | `lib/services/auth_service.dart` |
| `AppRepository` | `SupabaseAppRepository`, `HiveAppRepository` | `lib/data/app_repository.dart` |
| `BusinessRepository` | `SupabaseBusinessRepository` | `lib/data/business_repository.dart` |
| `CommunityRepository` | `SupabaseCommunityRepository` | `lib/data/community_repository.dart` |
| `RoutineCatalogRepository` | `SupabaseRoutineCatalogRepository` | `lib/data/routine_catalog_repository.dart` |

나머지 하나는 `lib/main.dart` — **컴포지션 루트**다. 여기서만 구현체를 고르고 묶는다.
`Auth.use(SupabaseAuthService.instance)` 한 줄이 인증 바인딩 지점이다.

포트를 넘나드는 타입도 전부 앱 소유다: `AuthUser`, `AuthChange`, `AuthEvent`, `AuthSignUpResult`,
`AuthFailure`, `SocialLoginProvider`. Supabase의 `User`/`AuthState`/`AuthResponse`는 앱에 안 들어온다.

## 이전할 때 하는 일

1. `AuthService`를 구현하는 `ApiAuthService`(가칭)를 새 서버에 맞춰 작성한다.
2. 레포지토리 4종을 같은 방식으로 구현한다.
3. `main.dart`에서 바인딩을 새 구현체로 바꾼다. **화면 코드는 안 건드린다.**
4. 위젯 테스트는 `Auth.use(FakeAuthService())`로 인증 상태를 주입할 수 있다
   (`Auth.reset()`으로 로그아웃 상태 복원).

## RLS는 이전 시 걷어낸다 — 단 순서를 지킨다

**결론: 걷어낸다.** RLS가 존재하는 이유는 *클라이언트가 Postgres에 직접 붙기 때문*이다. EC2에 API
서버가 생기면 그 전제가 사라지고, 인가는 원래 있어야 할 API 계층으로 간다.

`auth.uid()`를 살리는 쪽은 성가시다. 그 함수는 PostgREST가 요청마다 넣어주는
`request.jwt.claims`를 읽으므로, 자체 서버 + 커넥션 풀에서는 **트랜잭션마다 `SET LOCAL`로 흉내내야**
한다. 필요 없어진 2중 방어를 위해 영구적으로 떠안는 배관이다.

비용은 정책 수(198)가 주는 인상보다 낮다. 실제로는 **패턴 3개**뿐이고 복잡한 것이 없다.

| 패턴 | 개수 | API에서의 대응 |
| --- | --- | --- |
| 단순 소유권 (`auth.uid() = user_id`) | 63 | `WHERE user_id = $me` |
| `is_admin()` 균일 검사 | 111 | 미들웨어 한 곳 |
| 인증 무관 (공개 읽기) | 59 | 공개 엔드포인트 |
| 서브쿼리 낀 복잡한 정책 | **0** | — |

### 순서를 뒤집지 말 것

```
① EC2에 API 서버 구축 → ② 앱을 API로 이관(레포지토리 4종 교체) → ③ 그때 RLS 은퇴
```

②가 끝나기 전까지 **RLS는 남의 데이터와 사이에 있는 유일한 방어선**이다. ① 전에 지우면 열린 DB다.
지금 지켜야 할 것은 하나: **새 테이블도 위 3패턴 밖으로 나가지 않기.** 서브쿼리 낀 정책이 0개인 건
운이 아니라 지킬 가치가 있는 상태고, 하나 늘 때마다 ③의 비용이 비선형으로 는다.

마이그레이션 SQL은 `supabase/migrations/`(38개)에 있으므로 스키마 자체는 그대로 옮길 수 있다.

## Supabase에서 작업할 때 — 새 기능은 어디에 두나

**엣지 펑션으로 다 만들면 안 된다. 그게 가장 이전하기 나쁜 선택지다.**
Deno 런타임 + `SUPABASE_SERVICE_ROLE_KEY` + jsr import에 묶여 있어서 EC2로 가면 통째로 다시 써야 한다.
게다가 실제로 사고가 났던 지점이다(`email-signup`이 500으로 죽어 회원가입이 통째로 막혔다).

판단 기준은 "Supabase 기능을 얼마나 쓰냐"가 아니라 **"EC2에서 이 코드가 살아남느냐"**다.

| 하려는 일 | 어디에 | 이전 시 |
| --- | --- | --- |
| 단순 조회·저장 | 레포지토리에서 PostgREST 직접 | `SELECT`/`INSERT`로 그대로 |
| 여러 테이블을 한 트랜잭션으로 | **Postgres 함수(RPC)** | 순수 SQL이라 그대로 옮겨짐 |
| 비즈니스 규칙·집계 | **Postgres 함수(RPC)** | 그대로 옮기거나 서버 코드로 승격 |
| 외부 API 호출(결제·SMS·푸시) | 엣지 펑션 (다른 방법 없음) | 재작성 — 그래서 최소로 |
| 웹훅 수신 | 엣지 펑션 | 재작성 |

즉 **기본값은 RPC**, 엣지 펑션은 "비밀키를 들고 외부와 통신해야 할 때"만. 그리고 엣지 펑션을 쓰더라도
**사용자 핵심 동작의 크리티컬 패스에 두지 않는다** — 회원가입이 그 실수였다.

현재 상태: 앱이 호출하는 엣지 펑션 **0개**, 호출하는 RPC **4개**
(`is_admin`, `get_my_trainer_profile`, `get_my_gym_profile`, `list_my_business_memberships`).
넷 다 도메인 모양이라 그대로 엔드포인트가 된다. `supabase/functions/`의 `email-signup`·`custom-auth`는
**앱에서 안 쓰는 죽은 코드**이므로 정리해도 된다.

### 진짜 중요한 건 계약의 모양

로직을 DB에 두든 서버에 두든, 이전 비용을 결정하는 건 **앱이 서버와 맺은 계약이 도메인 모양이냐**다.
`loadAccess()` / `listMyConsultations()` / `createConsultation()`처럼 이미 엔드포인트처럼 생겼으면
구현이 무엇이든 갈아끼울 수 있다. 반대로 화면이 테이블·컬럼을 직접 알기 시작하면 그때부터 비싸진다.
새 기능을 붙일 때 **포트에 도메인 동사로 먼저 적고** 구현을 고르는 순서를 지킬 것.

## Postgres · Realtime · Storage를 쓰면서 AWS로 가기

이 셋은 **쓸 예정이고, 이전 난이도가 서로 다르다.** 하나씩 규칙이 다르므로 섞어서 생각하지 말 것.

### 1. Postgres DB — 위험 거의 없음

같은 Postgres다. Supabase → RDS/Aurora는 덤프·복원이고 스키마는 `supabase/migrations/`(38개)에 있다.
지켜야 할 것 하나뿐:

- **`auth.users`를 FK로 참조하지 않기.** 그 테이블은 Supabase Auth의 것이라 같이 안 따라온다.
  현재 참조 **0건** — 이미 깨끗하니 유지할 것. 사용자 식별은 `user_id uuid`를 우리 테이블에 두고
  값만 넣는다.
- Supabase 전용 확장(`pgsodium`/Vault, `pg_graphql`)에 로직을 얹지 않기.

### 2. Realtime — 아직 0건, 지금이 규칙 세울 타이밍

`supabase_realtime` publication에 등록된 테이블 **0개**, 앱의 채널 구독 **0건**. 아무것도 안 샌 상태다.

AWS에는 드롭인 대체가 없다. 선택지는 (a) 오픈소스 `supabase/realtime`을 EC2에 직접 띄우거나
(b) 자체 WebSocket 서버 + Postgres `LISTEN/NOTIFY`로 갈아타는 것. **어느 쪽이든 서버는 바뀐다.**

그래서 규칙은 하나: **구독은 레포지토리 안에만 두고, 포트는 도메인 스트림만 노출한다.**

```dart
// 포트 — 좋음. 구현이 무엇이든 화면은 이것만 안다.
Stream<BusinessConsultation> watchConsultation(String id);

// 화면이 RealtimeChannel / PostgresChangeEvent를 아는 순간 결합이다.
```

`RealtimeChannel`, `PostgresChangeEvent` 같은 타입이 `lib/screens/**`에 나타나면 위반이다.
(인증에 쓴 것과 같은 규칙이고, 같은 grep으로 잡힌다.)

### 3. Storage — 이미 사용 중, 함정은 코드가 아니라 **데이터**

버킷 7개가 살아 있고 호출은 전부 `lib/data/supabase_*_repository.dart`(어댑터) 안에만 있다.
즉 **코드는 안 샌다.** S3로 옮기는 것도 객체 복사 + 어댑터 교체다.

진짜 위험은 다른 데 있었다: **렌더링된 URL을 DB에 저장하는 것.**

```
❌ posts.image_url = 'https://<project>.supabase.co/storage/v1/object/public/post-images/...'
✅ posts.image_url = 'user-id/1755750000_1.webp'   ← 경로만
```

전체 URL을 저장하면 버킷을 옮기는 순간 **데이터 마이그레이션**이 된다. 스키마 변경보다 비싸고
되돌리기도 어렵다. 규칙:

> **DB에는 버킷 경로만 저장하고, URL은 읽는 시점에 만든다.**

현재 상태(고침 완료):

| 컬럼 | 저장 형태 |
| --- | --- |
| `trainer_documents.file_path` | 경로 ✅ (원래부터 올바름) |
| `posts.image_url` | 경로 ✅ (`getPublicUrl` 결과를 넣던 것을 수정) |

`SupabaseCommunityRepository._resolveImageUrl`이 읽는 시점에 경로 → URL로 바꾼다. 규칙 이전에
쓰인 행은 `http`로 시작하므로 그대로 통과시켜서, **데이터 재작성 없이** 양쪽을 함께 지원한다.
새 이미지 컬럼(`gyms.cover_image_url`, `users.avatar_url`, `coaching_logs.media_url` 등)을 채우기
시작할 때도 같은 규칙을 적용할 것 — 지금은 전부 비어 있어 공짜다.

## 의도적으로 안 한 것

- **엣지 함수 의존 제거 완료.** 앱이 호출하는 Edge Function은 현재 **0개**다.
  (회원가입이 `email-signup` 함수를 거치다 500으로 죽던 것을 클라이언트 `auth.signUp`으로 되돌렸다.)
  이전 대상이 하나 줄었으므로 새 함수를 추가할 땐 이 문서를 먼저 볼 것.
- **Realtime은 아직 미사용.** 첫 기능을 붙일 때 포트(도메인 스트림)를 먼저 만들 것.
- **Storage는 사용 중이지만 어댑터 안에만 있다.** 경로-저장 규칙만 지키면 이전 비용은 객체 복사뿐이다.
