begin;

-- 기존 앱이 쓰는 일반 댓글은 그대로 두고, 답글만 부모를 저장한다.
alter table public.comments
  add column if not exists parent_comment_id uuid;

-- 부모가 반드시 같은 글에 있어야 한다. 클라이언트의 검사만 믿지 않는다.
alter table public.comments
  add constraint comments_post_id_id_key unique (post_id, id),
  add constraint comments_reply_parent_fkey
    foreign key (post_id, parent_comment_id)
    references public.comments (post_id, id) on delete cascade,
  add constraint comments_reply_not_self_check
    check (parent_comment_id is null or parent_comment_id <> id);

create index comments_reply_parent_idx
  on public.comments (post_id, parent_comment_id, created_at)
  where parent_comment_id is not null;

comment on column public.comments.parent_comment_id is
  '답글의 부모 댓글. 일반 댓글은 NULL이며 같은 게시물의 댓글만 참조한다.';

-- 새 답글도 기존 notify_post_comment -> enqueue_push 관문을 거친다.
-- 기존 공개 읽기와 본인 댓글 쓰기 정책은 그대로 적용한다.
notify pgrst, 'reload schema';

commit;
