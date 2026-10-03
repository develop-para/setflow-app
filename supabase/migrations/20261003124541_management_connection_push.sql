begin;

-- Connection notifications follow the recipient's settings and identify the
-- other participant. Only enqueue here; the worker delivers while the app is shut.
create or replace function private.request_management_link(p_consultation uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare c public.consultations%rowtype; t public.trainers%rowtype; l public.coaching_management_links%rowtype;
begin
  select * into c from public.consultations where id = p_consultation;
  select * into t from public.trainers where id = coalesce(c.assigned_trainer_id,c.trainer_id) and status = 'approved';
  if c.id is null or t.id is null
    or (select auth.uid()) is null or (select auth.uid()) not in (c.user_id,t.user_id) then
    raise exception 'Consultation participant required' using errcode = '42501';
  end if;
  if c.user_id = t.user_id then
    raise exception 'A trainer cannot manage their own workout records'
      using errcode = '42501', detail = 'management_self_connection';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('management:' || t.id::text || ':' || c.user_id::text,0));
  if exists(select 1 from public.coaching_management_links where trainer_id = t.id
    and member_user_id = c.user_id and status in ('pending','active')) then return; end if;
  insert into public.coaching_management_links(consultation_id,member_user_id,trainer_id,requested_by,member_accepted_at,trainer_accepted_at)
    values(c.id,c.user_id,t.id,(select auth.uid()),
      case when (select auth.uid()) = c.user_id then clock_timestamp() end,
      case when (select auth.uid()) = t.user_id then clock_timestamp() end) returning * into l;
  perform private.enqueue_push(case when (select auth.uid()) = c.user_id then t.user_id else c.user_id end,
    case when (select auth.uid()) = c.user_id then 'business' else 'coaching_feedback' end,
    '운동 관리 연결 신청',
    case when (select auth.uid()) = c.user_id
      then private.display_name_of(c.user_id) || '님이 운동 관리 연결을 신청했어요. 확인 후 수락해주세요.'
      else private.trainer_name(t.id) || ' 트레이너가 운동 관리 연결을 요청했어요. 공유 범위를 확인해주세요.' end,
    jsonb_build_object('event','coaching_management','action','requested','linkId',l.id::text));
end;
$$;

create or replace function private.respond_management_link(p_link uuid,p_accept boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare l public.coaching_management_links%rowtype; v_coaching uuid; v_ready boolean; v_trainer_user uuid;
begin
  if p_accept is null then raise exception 'Decision required' using errcode = '22023'; end if;
  select * into l from public.coaching_management_links where id = p_link;
  perform 1 from public.users where id = l.member_user_id for update;
  select * into l from public.coaching_management_links where id = p_link for update;
  if l.id is null or private.management_role(l) not in ('member','trainer')
    or private.management_role(l) is null then
    raise exception 'Only the receiving participant can respond' using errcode = '42501';
  end if;
  if l.status <> 'pending' then return; end if;
  if (private.management_role(l) = 'member' and l.member_accepted_at is not null)
    or (private.management_role(l) = 'trainer' and l.trainer_accepted_at is not null) then
    raise exception 'This participant already consented' using errcode = '42501'; end if;
  select user_id into v_trainer_user from public.trainers where id = l.trainer_id and status = 'approved';
  if v_trainer_user is null then
    raise exception 'Approved trainer required' using errcode = '42501'; end if;
  if p_accept then
    if l.source_link_id is not null and not exists (
      select 1 from public.coaching_management_links source
      join public.members m on m.user_id = source.member_user_id and m.gym_id = source.gym_id and m.status = 'active'
      join public.gym_trainers gt on gt.gym_id = source.gym_id and gt.trainer_id = l.trainer_id and gt.status = 'active'
      where source.id = l.source_link_id and source.gym_id = l.gym_id and private.management_active(source)
    ) then raise exception 'Trainer change is no longer available' using errcode = '42501'; end if;
    update public.coaching_management_links set
      member_accepted_at = case when private.management_role(l) = 'member' then clock_timestamp() else member_accepted_at end,
      trainer_accepted_at = case when private.management_role(l) = 'trainer' then clock_timestamp() else trainer_accepted_at end
      where id = l.id returning * into l;
    v_ready := l.member_accepted_at is not null and l.trainer_accepted_at is not null;
    if not v_ready then return; end if;
    perform pg_advisory_xact_lock(hashtextextended('coaching-connection:' || l.trainer_id::text || ':' || l.member_user_id::text,0));
    select id into v_coaching from public.coachings where trainer_id = l.trainer_id
      and user_id = l.member_user_id and status = 'active';
    if v_coaching is null then
      insert into public.coachings(user_id,trainer_id,program_name,start_date,status)
        values(l.member_user_id,l.trainer_id,'운동 기록 관리',current_date,'active') returning id into v_coaching;
    end if;
  end if;
  update public.coaching_management_links set status = case when p_accept then 'active' else 'rejected' end,
    accepted_at = case when p_accept then clock_timestamp() end, coaching_id = v_coaching where id = l.id;
  if p_accept and l.source_link_id is not null then
    update public.coaching_management_links set status = 'ended',ended_at = clock_timestamp()
      where source_link_id = l.source_link_id and status = 'pending';
    update public.coaching_management_links set status = 'ended',gym_id = null,ended_at = clock_timestamp() where id = l.source_link_id;
    update public.workout_corrections set status = 'cancelled',resolved_at = clock_timestamp(),resolved_by = (select auth.uid())
      where link_id = l.source_link_id and status = 'pending';
  end if;
  if p_accept then
    perform private.enqueue_push(l.member_user_id,'coaching_feedback','트레이너 연결 완료',
      private.trainer_name(l.trainer_id) || ' 트레이너와 운동 관리가 연결됐어요.',
      jsonb_build_object('event','coaching_management','action','accepted','linkId',l.id::text));
    perform private.enqueue_push(v_trainer_user,'business','회원 연결 완료',
      private.display_name_of(l.member_user_id) || '님과 운동 관리가 연결됐어요.',
      jsonb_build_object('event','coaching_management','action','accepted','linkId',l.id::text));
  end if;
  -- A gym can initiate a trainer transfer and also needs its final result.
  if not p_accept or l.requested_by not in (l.member_user_id,v_trainer_user) then
    perform private.enqueue_push(l.requested_by,
      case when l.requested_by = l.member_user_id then 'coaching_feedback' else 'business' end,
      case when p_accept then '운동 관리 연결 완료' else '운동 관리 연결 거절' end,
      case when p_accept then '회원과 트레이너가 연결을 모두 수락했어요.'
        else private.display_name_of((select auth.uid())) || '님이 운동 관리 연결을 거절했어요.' end,
      jsonb_build_object('event','coaching_management','action',case when p_accept then 'accepted' else 'rejected' end,'linkId',l.id::text));
  end if;
end;
$$;

create or replace function private.request_management_trainer_change(p_link uuid,p_trainer uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare l public.coaching_management_links%rowtype; t public.trainers%rowtype; v_new uuid;
begin
  select * into l from public.coaching_management_links where id = p_link;
  if l.id is null or private.management_role(l) is distinct from 'gym' then
    raise exception 'Sharing gym required' using errcode = '42501'; end if;
  perform 1 from public.users where id = l.member_user_id for update;
  select * into l from public.coaching_management_links where id = p_link for update;
  if not private.management_active(l) or private.management_role(l) is distinct from 'gym' then
    raise exception 'Active management consent required' using errcode = '42501'; end if;
  select t1.* into t from public.trainers t1 join public.gym_trainers gt on gt.trainer_id = t1.id
    where t1.id = p_trainer and t1.status = 'approved' and gt.gym_id = l.gym_id and gt.status = 'active';
  if t.id is null or t.id = l.trainer_id or t.user_id = l.member_user_id then
    raise exception 'Another approved gym trainer required' using errcode = '22023'; end if;
  if exists(select 1 from public.coaching_management_links where source_link_id = l.id and trainer_id = t.id and status = 'pending') then return; end if;
  if exists(select 1 from public.coaching_management_links where trainer_id = t.id and member_user_id = l.member_user_id and status in ('pending','active')) then
    raise exception 'A management request already exists for this trainer' using errcode = '22023'; end if;
  insert into public.coaching_management_links(consultation_id,member_user_id,trainer_id,requested_by,gym_id,source_link_id)
    values(l.consultation_id,l.member_user_id,t.id,(select auth.uid()),l.gym_id,l.id) returning id into v_new;
  perform private.enqueue_push(l.member_user_id,'coaching_feedback','담당 트레이너 변경 요청',
    private.trainer_name(t.id) || ' 트레이너로 변경하려면 동의가 필요해요.',
    jsonb_build_object('event','coaching_management','action','requested','linkId',v_new::text));
  perform private.enqueue_push(t.user_id,'business','회원 관리 연결 신청',
    private.display_name_of(l.member_user_id) || '님의 담당 트레이너 변경 요청이 도착했어요. 확인 후 수락해주세요.',
    jsonb_build_object('event','coaching_management','action','requested','linkId',v_new::text));
end;
$$;

commit;
