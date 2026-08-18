begin;

-- The routine catalog is shared by every member. Only verified administrators
-- may change whether a published routine is free or paid.
alter table public.market_routines
  add column if not exists access_tier text not null default 'free',
  add column if not exists author_name text not null default 'Setflow',
  add column if not exists color_hex text not null default '#10CEBD',
  add column if not exists catalog_key text;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'market_routines_access_tier_check'
      and conrelid = 'public.market_routines'::regclass
  ) then
    alter table public.market_routines
      add constraint market_routines_access_tier_check
      check (access_tier in ('free', 'paid'));
  end if;
end
$$;

create unique index if not exists market_routines_catalog_key_uidx
  on public.market_routines (catalog_key)
  where catalog_key is not null;
create index if not exists market_routines_published_created_idx
  on public.market_routines (created_at desc)
  where status = 'published';
create index if not exists coaching_routine_exercises_routine_order_idx
  on public.coaching_routine_exercises (routine_id, order_index);

drop policy if exists admin_update_market_access on public.market_routines;
create policy admin_update_market_access
  on public.market_routines
  for update
  to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

revoke all on table public.market_routines from anon, authenticated;
grant select on table public.market_routines to anon, authenticated;
grant update (access_tier) on table public.market_routines to authenticated;

-- Promote the explicitly nominated account through server-owned tables. The
-- Flutter client only reads this role; it never trusts a local email match.
do $$
declare
  target_user_id uuid;
  target_admin_id uuid;
  super_admin_role_id uuid;
  target_name text;
begin
  select id, coalesce(nullif(nickname, ''), 'Setflow 관리자')
    into target_user_id, target_name
  from public.users
  where lower(email) = 'hsa8275@gmail.com'
  limit 1;

  if target_user_id is null then
    raise exception 'The nominated Setflow administrator account does not exist';
  end if;

  insert into public.admin_users (user_id, display_name, email, status)
  values (target_user_id, target_name, 'hsa8275@gmail.com', 'active')
  on conflict (user_id) do update
    set display_name = excluded.display_name,
        email = excluded.email,
        status = 'active'
  returning id into target_admin_id;

  select id into super_admin_role_id
  from public.admin_roles
  where code = 'super_admin'
  limit 1;

  if super_admin_role_id is null then
    raise exception 'The super_admin role is not configured';
  end if;

  insert into public.admin_user_roles (admin_user_id, role_id)
  values (target_admin_id, super_admin_role_id)
  on conflict (admin_user_id, role_id) do nothing;

  update public.users
  set role = 'admin', updated_at = now()
  where id = target_user_id;
end
$$;

-- Seed a useful catalog without hard-coding generated row identifiers.
do $$
declare
  item record;
  linked_routine_id uuid;
begin
  for item in
    select *
    from (values
      (
        'starter_strength', '초보자 4주 근력 스타트',
        '무리 없이 기초 근력을 만드는 주 3회 프로그램',
        'beginner', '초급', 45, 'free',
        '김코치 · 인증 트레이너', '#10CEBD', 0::numeric,
        array['근력', '입문', '주 3회']::text[]
      ),
      (
        'back_definition', '등 라인 집중 루틴',
        '당기는 힘과 선명한 등 라인을 함께 만드는 루틴',
        'intermediate', '중급', 50, 'paid',
        '모션짐 · 사업자 인증', '#8B5CF6', 4900::numeric,
        array['등', '근비대', '중급']::text[]
      ),
      (
        'after_work_full_body', '퇴근 후 35분 전신',
        '짧은 시간 안에 전신 볼륨을 채우는 고효율 구성',
        'intermediate', '중급', 35, 'free',
        '박트레이너 · 인증 트레이너', '#FFB20C', 0::numeric,
        array['전신', '시간 절약', '주 3회']::text[]
      )
    ) as seed(
      catalog_key, title, description, coaching_difficulty,
      market_difficulty, duration_min, access_tier, author_name,
      color_hex, price, tags
    )
  loop
    select coaching_routine_id
      into linked_routine_id
    from public.market_routines
    where catalog_key = item.catalog_key;

    if linked_routine_id is null then
      insert into public.coaching_routines (
        title, intro, price, difficulty, status
      ) values (
        item.title, item.description, item.price,
        item.coaching_difficulty, 'approved'
      ) returning id into linked_routine_id;
    else
      update public.coaching_routines
      set title = item.title,
          intro = item.description,
          price = item.price,
          difficulty = item.coaching_difficulty,
          status = 'approved',
          updated_at = now()
      where id = linked_routine_id;
    end if;

    insert into public.market_routines (
      coaching_routine_id, title, description, tags, difficulty,
      duration_min, status, access_tier, author_name, color_hex, catalog_key
    ) values (
      linked_routine_id, item.title, item.description, item.tags,
      item.market_difficulty, item.duration_min, 'published',
      item.access_tier, item.author_name, item.color_hex, item.catalog_key
    )
    on conflict (catalog_key) where catalog_key is not null do update
      set coaching_routine_id = excluded.coaching_routine_id,
          title = excluded.title,
          description = excluded.description,
          tags = excluded.tags,
          difficulty = excluded.difficulty,
          duration_min = excluded.duration_min,
          status = excluded.status,
          access_tier = excluded.access_tier,
          author_name = excluded.author_name,
          color_hex = excluded.color_hex;

    delete from public.coaching_routine_exercises
    where routine_id = linked_routine_id;

    if item.catalog_key = 'starter_strength' then
      insert into public.coaching_routine_exercises
        (routine_id, name, target_muscle, order_index)
      values
        (linked_routine_id, '바벨 벤치 프레스', '가슴', 0),
        (linked_routine_id, '스쿼트', '하체', 1),
        (linked_routine_id, '렛 풀 다운', '등', 2);
    elsif item.catalog_key = 'back_definition' then
      insert into public.coaching_routine_exercises
        (routine_id, name, target_muscle, order_index)
      values
        (linked_routine_id, '렛 풀 다운', '등', 0),
        (linked_routine_id, '바벨 로우', '등', 1),
        (linked_routine_id, '덤벨 컬', '팔', 2);
    else
      insert into public.coaching_routine_exercises
        (routine_id, name, target_muscle, order_index)
      values
        (linked_routine_id, '스쿼트', '하체', 0),
        (linked_routine_id, '바벨 벤치 프레스', '가슴', 1),
        (linked_routine_id, '오버헤드 프레스', '어깨', 2);
    end if;
  end loop;
end
$$;

-- Shared community metadata. Display names are copied at write time so public
-- feeds never need access to private email-bearing user profiles.
alter table public.posts
  add column if not exists author_name text not null default '회원',
  add column if not exists metric text not null default '일상 기록',
  add column if not exists visual_key text not null default 'strength',
  add column if not exists likes_count integer not null default 0;
alter table public.comments
  add column if not exists author_name text not null default '회원';

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'posts_likes_count_check'
      and conrelid = 'public.posts'::regclass
  ) then
    alter table public.posts
      add constraint posts_likes_count_check check (likes_count >= 0);
  end if;
end
$$;

create index if not exists posts_created_at_idx
  on public.posts (created_at desc);
create index if not exists posts_user_created_idx
  on public.posts (user_id, created_at desc);
create index if not exists comments_post_created_idx
  on public.comments (post_id, created_at);
create index if not exists post_likes_user_idx
  on public.post_likes (user_id, created_at desc);

create or replace function public.sync_post_likes_count()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  affected_post_id uuid;
begin
  affected_post_id := case when tg_op = 'DELETE' then old.post_id else new.post_id end;
  update public.posts
  set likes_count = (
    select count(*)::integer
    from public.post_likes
    where post_id = affected_post_id
  )
  where id = affected_post_id;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end
$$;

revoke execute on function public.sync_post_likes_count() from public, anon, authenticated;
drop trigger if exists sync_post_likes_count_after_change on public.post_likes;
create trigger sync_post_likes_count_after_change
after insert or delete on public.post_likes
for each row execute function public.sync_post_likes_count();

drop policy if exists own_likes on public.post_likes;
create policy read_own_likes
  on public.post_likes for select to authenticated
  using (user_id = (select auth.uid()));
create policy create_own_likes
  on public.post_likes for insert to authenticated
  with check (user_id = (select auth.uid()));
create policy delete_own_likes
  on public.post_likes for delete to authenticated
  using (user_id = (select auth.uid()));

revoke all on table public.posts from anon, authenticated;
revoke all on table public.comments from anon, authenticated;
revoke all on table public.post_likes from anon, authenticated;
grant select, insert, update, delete on table public.posts to authenticated;
grant select, insert, delete on table public.comments to authenticated;
grant select, insert, delete on table public.post_likes to authenticated;

-- Subscription state is payment-system owned. Members may read their own row,
-- but cannot grant themselves a paid plan.
drop policy if exists own_subs on public.subscriptions;
drop policy if exists read_own_subscriptions on public.subscriptions;
drop policy if exists admin_manage_subscriptions on public.subscriptions;
create policy read_own_subscriptions
  on public.subscriptions for select to authenticated
  using (
    user_id = (select auth.uid())
    or (select public.is_admin())
  );
create policy admin_manage_subscriptions
  on public.subscriptions for all to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

revoke all on table public.subscriptions from anon, authenticated;
grant select on table public.subscriptions to authenticated;

-- Keep all existing image buckets working while requiring an authenticated
-- owner folder for every write and for path-changing updates.
update storage.buckets
set public = true,
    file_size_limit = 6291456,
    allowed_mime_types = array[
      'image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif'
    ]::text[]
where id = 'post-images';

drop policy if exists pub_write_images on storage.objects;
drop policy if exists pub_update_images on storage.objects;
drop policy if exists pub_delete_images on storage.objects;

create policy pub_write_images
  on storage.objects for insert to authenticated
  with check (
    bucket_id = any (array['post-images', 'profile-images', 'gym-covers'])
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );
create policy pub_update_images
  on storage.objects for update to authenticated
  using (
    bucket_id = any (array['post-images', 'profile-images', 'gym-covers'])
    and (storage.foldername(name))[1] = (select auth.uid())::text
  )
  with check (
    bucket_id = any (array['post-images', 'profile-images', 'gym-covers'])
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );
create policy pub_delete_images
  on storage.objects for delete to authenticated
  using (
    bucket_id = any (array['post-images', 'profile-images', 'gym-covers'])
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

commit;
