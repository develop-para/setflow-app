# 종목 수행 방법 — 출처와 라이선스 경계

`lib/data/exercise_guides.dart`의 한국어 단계별 설명은
[hasaneyldrm/exercises-dataset](https://github.com/hasaneyldrm/exercises-dataset)에서 왔다.

## 텍스트는 써도 되고, 이미지는 안 된다

그 저장소는 **라이선스가 두 겹**이다. 한 줄로 요약하면:

| 부분 | 라이선스 | 우리가 쓸 수 있나 |
|---|---|---|
| 코드·데이터 구조·**설명 텍스트와 번역** | MIT | **가능** |
| `images/`·`videos/` (썸네일·애니메이션 GIF) | MIT 아님 | **불가** |

미디어는 **Gym visual**(https://gymvisual.com/) 소유다. 저장소 저자가 **자기 앞으로 받은
별도 서면 허가**로 재배포하고 있을 뿐이고, `NOTICE.md`가 이렇게 적고 있다:

> If you use this media in your own project, review those terms and, where required,
> obtain permission.

**그 허가는 그쪽 것이지 우리 것이 아니다.** 상용 배포되는 앱에 GIF나 썸네일을 넣으려면
Gym visual과 별도로 계약해야 한다. 지금은 **텍스트만** 가져왔다.

이미지를 넣기로 결정한다면 그 전에:
1. Gym visual 이용약관 확인 — https://gymvisual.com/content/3-terms-and-conditions-of-use
2. 재배포·상용 이용 허가를 **우리 이름으로** 받을 것
3. 180×180 해상도 제한과 `© Gym visual` 저작권 표시 유지

## 매핑

우리 카탈로그는 80종, 데이터셋은 1,324종이고 이름이 한국어 대 영어라 손으로 이었다.
매핑 결과는 `lib/data/exercise_guides.dart`에 직접 들어 있다(별도 생성 도구는 없다 —
데이터셋 갱신 시 이 문서의 대응표를 기준으로 손으로 맞춘다).

**71종이 연결됐고 9종은 데이터셋에 대응 항목이 없다** — 페이스 풀, 힙 쓰러스트,
버드 독, 로잉 머신, 그리고 맨몸운동 추가분(맨몸 스쿼트, 버피, 사이드 플랭크,
마운틴 클라이머, 월싯). 이건 직접 쓰거나 빈 채로 둔다. 없는 걸 억지로 비슷한 종목에
이으면 초보자에게 **틀린 동작을 가르치게 된다.** 처음에 빠졌던 셋은 나중에 정확한
항목을 찾아 이었다: 바벨 로우 ← `barbell bent over row`, 펙덱 플라이 ← `lever
seated fly`(lever가 머신이라는 뜻이다), 줄넘기 ← `jump rope`.

억지 매핑의 경계가 실제로 어디였는지 남긴다: 페이스 풀은 `cable standing rear delt
row (with rope)`가 기계적으로 가장 가깝지만 당기는 목표 지점(얼굴 vs 가슴)이 달라서
잇지 않았고, 힙 쓰러스트는 `barbell glute bridge`가 등을 벤치에 올리지 않는 바닥
동작이라 잇지 않았다.
