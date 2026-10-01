-- Keep participant authorization and the prohibition on managing one's own
-- records, but distinguish this business rule from expired or missing access.
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
    'coaching_feedback','운동 관리 연결 요청','공유 범위를 확인하고 연결을 수락해주세요.',
    jsonb_build_object('event','coaching_management','linkId',l.id::text));
end;
$$;
