import "jsr:@supabase/functions-js/edge-runtime.d.ts";

// 함께 방 초대 링크의 **예비** 주소 — 진짜 착지 페이지는 웹(`web/join.html`,
// https://setflow-app.vercel.app/together/join?code=CODE)이다. 여기는 그리로
// 302만 보낸다.
//
// 처음엔 이 펑션이 HTML 착지 페이지였는데, Supabase 게이트웨이가 기본 도메인
// (*.supabase.co)의 HTML 응답을 text/plain + sandbox CSP로 바꿔 버린다(피싱 방지
// — 커스텀 도메인을 붙여야 풀린다). 그래서 페이지는 Vercel로 갔고, 이미 배포된
// 이 주소는 죽은 텍스트 대신 리다이렉트로 남긴다. 앱은 이 주소를 만들지 않는다
// (`SetflowWeb.togetherJoin`). 웹 도메인이 바뀌면 여기도 바꿀 것.
//
// 인증 없음(verify_jwt=false): 초대받는 사람은 아직 계정이 없을 수 있다.

const WEB_JOIN = "https://setflow-app.vercel.app/together/join";
const CODE = /^[A-Z0-9]{4,8}$/;

Deno.serve((req: Request) => {
  if (req.method !== "GET" && req.method !== "HEAD") {
    return new Response("method not allowed", { status: 405 });
  }
  const raw = new URL(req.url).searchParams.get("code")?.trim().toUpperCase() ?? "";
  const target = new URL(WEB_JOIN);
  if (CODE.test(raw)) target.searchParams.set("code", raw);
  return Response.redirect(target.toString(), 302);
});
