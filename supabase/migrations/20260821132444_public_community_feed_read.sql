begin;

-- 비회원도 동기부여 피드를 읽는다.
--
-- `rd_posts` / `rd_comments` 는 이미 `to public using (true)` 라서 RLS 는 익명을
-- 막고 있지 않았다. 막고 있던 것은 커뮤니티 미디어 마이그레이션
-- (20260816044421) 의 `revoke all ... from anon` 이다. 테이블 권한이 없으면
-- 정책이 평가되기도 전에 permission denied 가 나므로, 앱에서는 로그인 전 피드가
-- 통째로 비어 보였다.
--
-- 되돌리는 것은 읽기뿐이다. 작성/좋아요/댓글은 그대로 authenticated 전용이고,
-- post_likes 는 "내가 누른 것"만 담기므로 익명에게 열지 않는다.
grant select on table public.posts to anon;
grant select on table public.comments to anon;

commit;
