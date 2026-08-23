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

우리 카탈로그는 74종, 데이터셋은 1,324종이고 이름이 한국어 대 영어라 손으로 이었다.
`tool/build_exercise_guides.dart`가 그 표를 들고 있고, 갱신할 때 다시 돌리면 된다.

**68종이 연결됐고 6종은 데이터셋에 대응 항목이 없다** — 펙덱 플라이, 페이스 풀, 힙 쓰러스트,
버드 독, 로잉 머신, 줄넘기. 이건 직접 쓰거나 빈 채로 둔다. 없는 걸 억지로 비슷한 종목에
이으면 초보자에게 **틀린 동작을 가르치게 된다.**
