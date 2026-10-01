begin;

create index if not exists consultation_messages_chat_cursor_idx
  on public.consultation_messages (consultation_id, created_at, id);

-- 회원과 담당 사업자가 같은 대화에서 질문과 답변을 이어간다.
-- 신원/역할은 클라이언트가 아니라 현재 계정과 상담 담당 관계로 결정한다.
create or replace function private.send_consultation_message(
  p_request_id uuid,
  p_consultation_id uuid,
  p_text text,
  p_business_only boolean
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := auth.uid();
  v_text text := nullif(btrim(p_text), '');
  v_consultation public.consultations%rowtype;
  v_existing public.consultation_messages%rowtype;
  v_is_member boolean;
  v_is_trainer boolean;
  v_is_gym boolean;
  v_sender_type text;
  v_status text;
  v_message_id uuid;
  v_created_at timestamptz;
begin
  if v_user_id is null or not private.has_active_app_session() then
    raise exception using errcode = '42501', message = 'An active account session is required';
  end if;
  if p_request_id is null or p_consultation_id is null or p_business_only is null or v_text is null
     or char_length(v_text) > 5000 then
    raise exception using errcode = '22023', message = 'Consultation message input is invalid';
  end if;

  -- 기존 답변 RPC와 같은 잠금/키를 사용하므로 구버전 재전송도 한 번만 쓴다.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'consultation_reply:' || v_user_id::text || ':' || p_request_id::text, 0
  ));
  select c.* into v_consultation
  from public.consultations c where c.id = p_consultation_id for update;
  if not found then
    raise exception using errcode = '42501', message = 'Consultation participant access required';
  end if;

  v_is_member := coalesce(v_consultation.user_id = v_user_id, false) and not p_business_only;
  select exists (
    select 1 from public.trainers t
    where t.id = coalesce(v_consultation.assigned_trainer_id, v_consultation.trainer_id)
      and t.user_id = v_user_id and t.status = 'approved'
      and (v_consultation.gym_id is null or exists (
        select 1 from public.gym_trainers gt
        join public.gyms g on g.id = gt.gym_id and g.status = 'verified'
        where gt.gym_id = v_consultation.gym_id and gt.trainer_id = t.id
          and gt.trainer_user_id = v_user_id and gt.status = 'active'
      ))
  ) into v_is_trainer;
  select exists (
    select 1 from public.gyms g
    where g.id = v_consultation.gym_id and g.owner_user_id = v_user_id
      and g.status = 'verified'
  ) into v_is_gym;
  if not (v_is_member or v_is_trainer or v_is_gym) then
    raise exception using errcode = '42501', message = 'Consultation participant access required';
  end if;
  v_sender_type := case when v_is_member then 'user'
    when v_is_trainer then 'trainer' else 'gym' end;

  -- 권한을 먼저 확인한다. 담당 해제 뒤에는 과거 요청 재시도도 거부한다.
  select cm.* into v_existing from public.consultation_messages cm
  where cm.sender_id = v_user_id and cm.request_id = p_request_id for update;
  if found then
    if v_existing.consultation_id <> p_consultation_id
       or v_existing.text <> v_text or v_existing.sender_type <> v_sender_type then
      raise exception using errcode = '22023', message = 'A message request ID cannot be reused with different data';
    end if;
    return jsonb_build_object('consultation_id', p_consultation_id,
      'message_id', v_existing.id, 'sender_type', v_existing.sender_type,
      'status', v_consultation.status, 'created_at', v_existing.created_at, 'replayed', true);
  end if;

  insert into public.consultation_messages
    (request_id, consultation_id, sender_type, sender_id, text, created_at)
  values (p_request_id, p_consultation_id, v_sender_type, v_user_id, v_text, clock_timestamp())
  returning id, created_at into v_message_id, v_created_at;

  -- 이미 답한 상담도 회원이 다시 질문하면 담당 수신함의 미답변으로 돌아간다.
  v_status := case when v_is_member then
    case when v_consultation.assigned_trainer_id is null then 'pending' else 'assigned' end
    else 'replied' end;
  update public.consultations set status = v_status, is_read = not v_is_member
  where id = p_consultation_id;
  return jsonb_build_object('consultation_id', p_consultation_id,
    'message_id', v_message_id, 'sender_type', v_sender_type,
    'status', v_status, 'created_at', v_created_at, 'replayed', false);
end
$function$;

create or replace function public.send_consultation_message(
  request_id uuid, consultation_id uuid, "text" text
)
returns jsonb language sql volatile security invoker set search_path = ''
as $function$
  select private.send_consultation_message($1, $2, $3, false);
$function$;

-- 기존 클라이언트의 답변도 같은 저장/검증/중복 방지 경로를 사용한다.
create or replace function private.reply_business_consultation(
  p_request_id uuid, p_consultation_id uuid, p_text text
)
returns jsonb language sql volatile security invoker set search_path = ''
as $function$
  select private.send_consultation_message($1, $2, $3, true);
$function$;

revoke all on function private.send_consultation_message(uuid, uuid, text, boolean)
  from public, anon;
grant execute on function private.send_consultation_message(uuid, uuid, text, boolean)
  to authenticated, service_role;
revoke all on function public.send_consultation_message(uuid, uuid, text)
  from public, anon;
grant execute on function public.send_consultation_message(uuid, uuid, text)
  to authenticated, service_role;

-- 직접 INSERT하면 request_id/수신함 상태/권한 검증을 우회할 수 있다.
revoke insert, update, delete on table public.consultation_messages from authenticated;
drop policy if exists consultation_messages_requester_insert on public.consultation_messages;

-- 기존 카탈로그는 회원 sender_type을 'member'로 검사했지만 실제 값은 'user'다.
-- 트리거는 알림함/발신함에만 쓴다. FCM 전송은 기존 비동기 크론이 맡는다.
create or replace function private.notify_consultation_reply()
returns trigger language plpgsql security definer set search_path = ''
as $function$
declare
  v_consultation public.consultations%rowtype;
  v_target uuid;
begin
  select c.* into v_consultation from public.consultations c
  where c.id = new.consultation_id;
  if not found then return new; end if;
  if new.sender_type in ('user', 'member') then
    select t.user_id into v_target from public.trainers t
    where t.id = coalesce(v_consultation.assigned_trainer_id, v_consultation.trainer_id)
      and t.status = 'approved'
      and (v_consultation.gym_id is null or exists (
        select 1 from public.gym_trainers gt
        join public.gyms g on g.id = gt.gym_id and g.status = 'verified'
        where gt.gym_id = v_consultation.gym_id and gt.trainer_id = t.id
          and gt.trainer_user_id = t.user_id and gt.status = 'active'
      ));
    if v_target is null then
      select g.owner_user_id into v_target from public.gyms g
      where g.id = v_consultation.gym_id and g.status = 'verified';
    end if;
    if v_target is null or v_target = new.sender_id then return new; end if;
    perform private.enqueue_push(v_target, 'business', '회원 메시지가 도착했어요',
      coalesce(nullif(v_consultation.requester_name, ''), private.display_name_of(v_consultation.user_id))
        || '님 · ' || new.text,
      jsonb_build_object('event', 'consultation_message', 'consultationId', new.consultation_id::text));
  elsif new.sender_type in ('trainer', 'gym') then
    if v_consultation.user_id = new.sender_id then return new; end if;
    perform private.enqueue_push(v_consultation.user_id, 'coaching_feedback', '상담 답변이 도착했어요', new.text,
      jsonb_build_object('event', 'consultation_reply', 'consultationId', new.consultation_id::text));
  end if;
  return new;
end
$function$;
revoke all on function private.notify_consultation_reply() from public, anon, authenticated;

-- 이벤트 구독에도 기존 참가자 RLS와 활성 세션 정책이 그대로 적용된다.
do $block$
begin
  if exists (select 1 from pg_catalog.pg_publication where pubname = 'supabase_realtime') then
    if not exists (select 1 from pg_catalog.pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'consultations') then
      alter publication supabase_realtime add table public.consultations;
    end if;
    if not exists (select 1 from pg_catalog.pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'consultation_messages') then
      alter publication supabase_realtime add table public.consultation_messages;
    end if;
  end if;
end
$block$;

commit;
