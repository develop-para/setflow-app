begin;

-- The legacy idx_posts_created index already covers this ordering.
drop index if exists public.posts_created_at_idx;

-- Avoid an ALL policy being evaluated alongside the public feed SELECT policy.
drop policy if exists wr_posts on public.posts;
drop policy if exists create_own_posts on public.posts;
drop policy if exists update_own_posts on public.posts;
drop policy if exists delete_own_posts on public.posts;

create policy create_own_posts
  on public.posts for insert to authenticated
  with check (user_id = (select auth.uid()));
create policy update_own_posts
  on public.posts for update to authenticated
  using (
    user_id = (select auth.uid())
    or (select public.is_admin())
  )
  with check (
    user_id = (select auth.uid())
    or (select public.is_admin())
  );
create policy delete_own_posts
  on public.posts for delete to authenticated
  using (
    user_id = (select auth.uid())
    or (select public.is_admin())
  );

-- Subscription mutations remain payment-backend owned; administrators in the
-- client only need the same read access already provided by the SELECT policy.
drop policy if exists admin_manage_subscriptions on public.subscriptions;

commit;
