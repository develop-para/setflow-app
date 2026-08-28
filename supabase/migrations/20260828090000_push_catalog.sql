begin;

-- 푸시 카탈로그 — 앱이 실제로 만드는 사건마다 알림 하나.
--
-- 규칙은 20260826120000과 같다: 트리거는 push_outbox에 줄만 넣고 끝난다.
-- 보낼지 말지는 private.push_enabled가 스냅샷의 설정을 읽어 정하고, 보내는 것은
-- 크론이 깨우는 send-push다. 여기서 정하는 것은 "언제, 누구에게, 무슨 말로"뿐이다.
--
-- kind는 설정 스위치 단위다(알림 하나하나가 아니라). 화면이 어떤 사건인지 알아야
-- 하면 data.event를 본다.
--
--   coaching_feedback   회원 ← 트레이너 (답변·피드백·일정·루틴·담당 배정)   pushCoachingFeedback
--   community_reaction  좋아요·댓글                                        communityReactionNotifications
--   together            함께 운동 방 (입장·시작·루틴 전달)                 pushTogether
--   workout_reminder    오늘 기록 없음·주간 요약                            pushWorkoutReminder + workoutReminderHour
--   business            트레이너·센터 ← 회원 (상담·메시지·배정·초대·종료)  businessNotifications.primary
--   business_activity   루틴 공유 응답·루틴 심사 결과                       businessNotifications.feedback
--   account             심사 결과·계정 삭제 예고 — 끌 수 없다
--
-- 없는 사건은 만들지 않았다. trainer_follows·routine_reviews·user_badges는 앱이
-- 쓰지 않는 테이블이라(0행, 어댑터 참조 없음) 트리거를 붙이지 않는다 — 안 오는
-- 알림을 설정에 올려 두는 것이 "있는 척"이다.

alter table public.push_outbox drop constraint if exists push_outbox_kind_check;
alter table public.push_outbox add constraint push_outbox_kind_check
  check (kind in (
    'coaching_feedback', 'community_reaction', 'together', 'workout_reminder',
    'business', 'business_activity', 'account'
  ));

-- 리마인드는 한 번만. 발신함을 뒤져 중복을 막는 대신 원본 줄에 도장을 찍는다 —
-- 발신함은 7일 뒤 지워지므로 거기엔 진실이 오래 남지 않는다.
alter table public.coaching_schedules
  add column if not exists reminder_sent_at timestamptz;
alter table public.account_deletion_requests
  add column if not exists reminder_sent_at timestamptz;

-- ── 설정 읽기 ───────────────────────────────────────────────────────────
create or replace function private.push_enabled(p_user uuid, p_kind text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select case p_kind
    when 'account' then true
    else coalesce(
      (
        select case p_kind
          when 'coaching_feedback' then
            (s.payload -> 'preferences' ->> 'pushCoachingFeedback')::boolean
          when 'community_reaction' then
            (s.payload -> 'preferences' ->> 'communityReactionNotifications')::boolean
          when 'together' then
            (s.payload -> 'preferences' ->> 'pushTogether')::boolean
          when 'workout_reminder' then
            (s.payload -> 'preferences' ->> 'pushWorkoutReminder')::boolean
          when 'business' then
            (s.payload -> 'preferences' -> 'businessNotifications' ->> 'primary')::boolean
          when 'business_activity' then
            (s.payload -> 'preferences' -> 'businessNotifications' ->> 'feedback')::boolean
        end
        from app_state_snapshots s
        where s.user_id = p_user
      ),
      -- 스냅샷이 아직 없거나 키가 없는 계정은 앱의 기본값을 따른다.
      case p_kind
        when 'community_reaction' then false
        when 'workout_reminder' then false
        else true
      end
    )
  end;
$$;

-- ── 이름·대상 찾기 ──────────────────────────────────────────────────────
-- 알림 문구에 들어갈 이름. 스냅샷의 닉네임이 사용자가 고른 이름이고, 없으면
-- 가입 때 이름, 그것도 없으면 '회원'.
create or replace function private.display_name_of(p_user uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    nullif(btrim((
      select s.payload -> 'profile' ->> 'nickname'
      from app_state_snapshots s where s.user_id = p_user
    )), ''),
    nullif(btrim((select u.nickname from users u where u.id = p_user)), ''),
    '회원'
  );
$$;

create or replace function private.trainer_user(p_trainer_id uuid)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select t.user_id from trainers t where t.id = p_trainer_id;
$$;

create or replace function private.trainer_name(p_trainer_id uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    nullif(btrim(t.display_name), ''),
    private.display_name_of(t.user_id)
  )
  from trainers t where t.id = p_trainer_id;
$$;

create or replace function private.gym_owner(p_gym_id uuid)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select g.owner_user_id from gyms g where g.id = p_gym_id;
$$;

-- '8월 30일 (토) 10:00' — 알림 한 줄에 들어갈 일정 표기.
create or replace function private.schedule_label(p_date date, p_start time)
returns text
language sql
stable
as $$
  select to_char(p_date, 'FMMM월 FMDD일')
    || ' (' || (array['일','월','화','수','목','금','토'])[extract(dow from p_date)::int + 1] || ')'
    || coalesce(' ' || to_char(p_start, 'HH24:MI'), '');
$$;

revoke all on function private.display_name_of(uuid) from public, anon, authenticated;
revoke all on function private.trainer_user(uuid) from public, anon, authenticated;
revoke all on function private.trainer_name(uuid) from public, anon, authenticated;
revoke all on function private.gym_owner(uuid) from public, anon, authenticated;

-- ── 상담: 회원 → 트레이너/센터 ─────────────────────────────────────────
create or replace function private.notify_consultation_created()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_target uuid;
begin
  v_target := coalesce(
    private.trainer_user(new.trainer_id),
    private.gym_owner(new.gym_id)
  );
  if v_target is null or v_target = new.user_id then return new; end if;
  perform private.enqueue_push(
    v_target,
    'business',
    '새 상담 요청이 왔어요',
    coalesce(nullif(new.requester_name, ''), private.display_name_of(new.user_id))
      || '님 · ' || coalesce(new.question, '상담을 요청했어요.'),
    jsonb_build_object(
      'event', 'consultation_created',
      'consultationId', new.id::text
    )
  );
  return new;
end;
$$;

drop trigger if exists notify_consultation_created on public.consultations;
create trigger notify_consultation_created
  after insert on public.consultations
  for each row execute function private.notify_consultation_created();

-- 답변은 양방향이다. 트레이너의 답은 회원에게(기존), 회원의 메시지는 담당
-- 트레이너에게 — 배정된 사람이 우선이고, 없으면 상담 대상, 그것도 없으면 센터장.
create or replace function private.notify_consultation_reply()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_consultation consultations%rowtype;
  v_target uuid;
begin
  select * into v_consultation from consultations where id = new.consultation_id;
  if not found then return new; end if;

  if coalesce(new.sender_type, 'member') = 'member' then
    v_target := coalesce(
      private.trainer_user(v_consultation.assigned_trainer_id),
      private.trainer_user(v_consultation.trainer_id),
      private.gym_owner(v_consultation.gym_id)
    );
    if v_target is null or v_target = v_consultation.user_id then return new; end if;
    perform private.enqueue_push(
      v_target,
      'business',
      '회원 메시지가 도착했어요',
      coalesce(nullif(v_consultation.requester_name, ''),
               private.display_name_of(v_consultation.user_id))
        || '님 · ' || coalesce(new.text, '상담에 새 메시지가 있어요.'),
      jsonb_build_object(
        'event', 'consultation_message',
        'consultationId', new.consultation_id::text
      )
    );
    return new;
  end if;

  perform private.enqueue_push(
    v_consultation.user_id,
    'coaching_feedback',
    '트레이너 답변이 도착했어요',
    coalesce(new.text, '상담에 새 답변이 있어요.'),
    jsonb_build_object(
      'event', 'consultation_reply',
      'consultationId', new.consultation_id::text
    )
  );
  return new;
end;
$$;

create or replace function private.notify_consultation_assigned()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_target uuid;
begin
  if new.assigned_trainer_id is null
     or new.assigned_trainer_id is not distinct from old.assigned_trainer_id then
    return new;
  end if;
  v_target := private.trainer_user(new.assigned_trainer_id);
  -- 자기에게 배정한 것은 알림이 아니다.
  if v_target is null or v_target = auth.uid() then return new; end if;
  perform private.enqueue_push(
    v_target,
    'business',
    '상담이 배정됐어요',
    coalesce(nullif(new.requester_name, ''), private.display_name_of(new.user_id))
      || '님 · ' || coalesce(new.question, '상담을 맡게 됐어요.'),
    jsonb_build_object(
      'event', 'consultation_assigned',
      'consultationId', new.id::text
    )
  );
  return new;
end;
$$;

drop trigger if exists notify_consultation_assigned on public.consultations;
create trigger notify_consultation_assigned
  after update of assigned_trainer_id on public.consultations
  for each row execute function private.notify_consultation_assigned();

-- ── 코칭: 트레이너 → 회원 ──────────────────────────────────────────────
create or replace function private.notify_session_feedback()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_member uuid;
  v_date date;
begin
  select user_id, date into v_member, v_date
    from workout_sessions where id = new.session_id;
  if v_member is null then return new; end if;
  perform private.enqueue_push(
    v_member,
    'coaching_feedback',
    '운동 피드백이 도착했어요',
    coalesce(private.trainer_name(new.trainer_id), '트레이너') || ' · '
      || coalesce(new.text, '기록에 피드백이 달렸어요.'),
    jsonb_build_object(
      'event', 'session_feedback',
      'sessionDate', v_date::text
    )
  );
  return new;
end;
$$;

drop trigger if exists notify_session_feedback on public.session_feedback;
create trigger notify_session_feedback
  after insert on public.session_feedback
  for each row execute function private.notify_session_feedback();

create or replace function private.notify_coaching_schedule()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.member_user_id is null then return new; end if;
  perform private.enqueue_push(
    new.member_user_id,
    'coaching_feedback',
    '코칭 일정이 잡혔어요',
    private.schedule_label(new.date, new.start_time) || ' · '
      || coalesce(nullif(new.title, ''), '코칭')
      || coalesce(' · ' || private.trainer_name(new.trainer_id), ''),
    jsonb_build_object(
      'event', 'coaching_schedule',
      'scheduleId', new.id::text,
      'date', new.date::text
    )
  );
  return new;
end;
$$;

drop trigger if exists notify_coaching_schedule on public.coaching_schedules;
create trigger notify_coaching_schedule
  after insert on public.coaching_schedules
  for each row execute function private.notify_coaching_schedule();

-- 1시간 전 리마인드. 10분마다 돌며 [50분, 70분) 앞의 일정을 잡는다 — 창이 크론
-- 간격보다 넓어야 한 번도 안 놓치고, 도장(reminder_sent_at)이 두 번을 막는다.
-- 일정의 시각은 벽시계(KST)다.
create or replace function private.remind_coaching_schedules()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  v_label text;
begin
  for r in
    select s.*, private.trainer_user(s.trainer_id) as trainer_user
    from coaching_schedules s
    where s.completed_at is null
      and s.reminder_sent_at is null
      and s.start_time is not null
      and ((s.date + s.start_time) at time zone 'Asia/Seoul')
            >= now() + interval '50 minutes'
      and ((s.date + s.start_time) at time zone 'Asia/Seoul')
            <  now() + interval '70 minutes'
  loop
    v_label := to_char(r.start_time, 'HH24:MI') || ' '
      || coalesce(nullif(r.title, ''), '코칭');
    perform private.enqueue_push(
      r.member_user_id,
      'coaching_feedback',
      '1시간 뒤 코칭이에요',
      v_label || coalesce(' · ' || private.trainer_name(r.trainer_id), ''),
      jsonb_build_object(
        'event', 'coaching_schedule_reminder',
        'scheduleId', r.id::text,
        'date', r.date::text
      )
    );
    perform private.enqueue_push(
      r.trainer_user,
      'business',
      '1시간 뒤 코칭이에요',
      v_label || ' · ' || private.display_name_of(r.member_user_id) || ' 회원',
      jsonb_build_object(
        'event', 'coaching_schedule_reminder',
        'scheduleId', r.id::text,
        'date', r.date::text
      )
    );
    update coaching_schedules set reminder_sent_at = now() where id = r.id;
  end loop;
end;
$$;

revoke all on function private.remind_coaching_schedules() from public, anon, authenticated;

-- ── 루틴 공유 ───────────────────────────────────────────────────────────
create or replace function private.notify_routine_share()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_recipient uuid;
  v_sender text;
  v_title text;
begin
  if coalesce(new.status, 'pending') <> 'pending' then return new; end if;
  v_recipient := coalesce(
    new.recipient_user_id,
    (select m.user_id from members m where m.id = new.member_id)
  );
  -- 링크 공유는 받는 사람이 정해지지 않았다.
  if v_recipient is null or v_recipient = new.sender_user_id then return new; end if;
  v_sender := coalesce(
    private.trainer_name(new.sender_trainer_id),
    (select nullif(btrim(g.name), '') from gyms g where g.id = new.sender_gym_id),
    private.display_name_of(new.sender_user_id)
  );
  select nullif(btrim(title), '') into v_title
    from coaching_routines where id = new.coaching_routine_id;
  perform private.enqueue_push(
    v_recipient,
    'coaching_feedback',
    '새 루틴이 도착했어요',
    v_sender || '님 · ' || coalesce(nullif(new.message, ''), coalesce(v_title, '루틴')),
    jsonb_build_object(
      'event', 'routine_share',
      'shareId', new.id::text
    )
  );
  return new;
end;
$$;

drop trigger if exists notify_routine_share on public.routine_shares;
create trigger notify_routine_share
  after insert on public.routine_shares
  for each row execute function private.notify_routine_share();

create or replace function private.notify_routine_share_response()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_responder uuid;
  v_title text;
begin
  if old.status is distinct from 'pending'
     or new.status not in ('accepted', 'declined') then
    return new;
  end if;
  if new.sender_user_id is null then return new; end if;
  v_responder := coalesce(
    new.responded_by_user_id,
    new.recipient_user_id,
    (select m.user_id from members m where m.id = new.member_id)
  );
  if v_responder = new.sender_user_id then return new; end if;
  select nullif(btrim(title), '') into v_title
    from coaching_routines where id = new.coaching_routine_id;
  perform private.enqueue_push(
    new.sender_user_id,
    'business_activity',
    case new.status
      when 'accepted' then '루틴을 받았어요'
      else '루틴을 거절했어요'
    end,
    private.display_name_of(v_responder) || '님 · ' || coalesce(v_title, '루틴'),
    jsonb_build_object(
      'event', 'routine_share_' || new.status,
      'shareId', new.id::text
    )
  );
  return new;
end;
$$;

drop trigger if exists notify_routine_share_response on public.routine_shares;
create trigger notify_routine_share_response
  after update of status on public.routine_shares
  for each row execute function private.notify_routine_share_response();

-- ── 담당 배정·초대·회원 관계 ────────────────────────────────────────────
create or replace function private.notify_member_assigned()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_member_user uuid;
  v_member_name text;
  v_trainer_user uuid;
  v_trainer_name text;
begin
  if not new.active then return new; end if;
  select m.user_id, nullif(btrim(m.name), '')
    into v_member_user, v_member_name
    from members m where m.id = new.member_id;
  v_trainer_user := private.trainer_user(new.trainer_id);
  v_trainer_name := coalesce(private.trainer_name(new.trainer_id), '트레이너');
  if v_member_user is not null and v_member_user <> v_trainer_user then
    perform private.enqueue_push(
      v_member_user,
      'coaching_feedback',
      '담당 트레이너가 정해졌어요',
      v_trainer_name || ' 트레이너가 회원님을 담당해요.',
      jsonb_build_object('event', 'member_assigned')
    );
  end if;
  if v_trainer_user is not null and v_trainer_user <> auth.uid() then
    perform private.enqueue_push(
      v_trainer_user,
      'business',
      '새 회원이 배정됐어요',
      coalesce(v_member_name, private.display_name_of(v_member_user), '회원')
        || ' 회원을 담당하게 됐어요.',
      jsonb_build_object('event', 'member_assigned', 'memberId', new.member_id::text)
    );
  end if;
  return new;
end;
$$;

drop trigger if exists notify_member_assigned on public.member_assignments;
create trigger notify_member_assigned
  after insert on public.member_assignments
  for each row execute function private.notify_member_assigned();

create or replace function private.notify_business_invite_accepted()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status <> 'accepted' or old.status is not distinct from 'accepted' then
    return new;
  end if;
  if new.created_by_user_id is null
     or new.created_by_user_id = new.accepted_by_user_id then
    return new;
  end if;
  perform private.enqueue_push(
    new.created_by_user_id,
    'business',
    '초대를 수락했어요',
    coalesce(nullif(new.recipient_name, ''),
             private.display_name_of(new.accepted_by_user_id))
      || '님이 ' || case new.invite_kind when 'trainer' then '트레이너로' else '회원으로' end
      || ' 합류했어요.',
    jsonb_build_object('event', 'invite_accepted', 'inviteId', new.id::text)
  );
  return new;
end;
$$;

drop trigger if exists notify_business_invite_accepted on public.business_invites;
create trigger notify_business_invite_accepted
  after update of status on public.business_invites
  for each row execute function private.notify_business_invite_accepted();

-- 회원 관계 종료는 상대에게 간다. 센터가 끝냈으면 회원에게(계정 알림 —
-- 이용권과 직결된 일이라 끌 수 없다), 회원이 끝냈으면 센터장에게.
create or replace function private.notify_membership_ended()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_gym_name text;
  v_owner uuid;
begin
  if new.status <> 'ended' or old.status is not distinct from 'ended' then
    return new;
  end if;
  select nullif(btrim(g.name), ''), g.owner_user_id
    into v_gym_name, v_owner
    from gyms g where g.id = new.gym_id;
  if new.user_id is not null and new.ended_by_user_id is distinct from new.user_id then
    perform private.enqueue_push(
      new.user_id,
      'account',
      '센터 등록이 종료됐어요',
      coalesce(v_gym_name, '센터') || '와의 회원 관계가 끝났어요.',
      jsonb_build_object('event', 'membership_ended', 'memberId', new.id::text)
    );
  end if;
  if v_owner is not null and new.ended_by_user_id = new.user_id then
    perform private.enqueue_push(
      v_owner,
      'business',
      '회원이 등록을 종료했어요',
      coalesce(nullif(new.name, ''), private.display_name_of(new.user_id))
        || '님 · ' || coalesce(v_gym_name, '센터'),
      jsonb_build_object('event', 'membership_ended', 'memberId', new.id::text)
    );
  end if;
  return new;
end;
$$;

drop trigger if exists notify_membership_ended on public.members;
create trigger notify_membership_ended
  after update of status on public.members
  for each row execute function private.notify_membership_ended();

-- ── 심사 결과: 계정 알림 ────────────────────────────────────────────────
-- 트레이너 화면은 승인 뒤에야 열린다(AGENTS.md 4절). 그 순간을 알려주지 않으면
-- 신청자는 앱을 다시 열어 볼 이유가 없다.
create or replace function private.notify_trainer_application_reviewed()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status not in ('approved', 'rejected')
     or new.status is not distinct from old.status then
    return new;
  end if;
  if new.user_id is null then return new; end if;
  perform private.enqueue_push(
    new.user_id,
    'account',
    case new.status
      when 'approved' then '트레이너 승인이 완료됐어요'
      else '트레이너 신청이 반려됐어요'
    end,
    case new.status
      when 'approved' then '이제 트레이너 화면을 쓸 수 있어요.'
      else coalesce(new.reject_reason, '자세한 내용은 신청 내역에서 확인하세요.')
    end,
    jsonb_build_object(
      'event', 'trainer_application_' || new.status,
      'applicationId', new.id::text
    )
  );
  return new;
end;
$$;

drop trigger if exists notify_trainer_application_reviewed on public.trainer_applications;
create trigger notify_trainer_application_reviewed
  after update of status on public.trainer_applications
  for each row execute function private.notify_trainer_application_reviewed();

create or replace function private.notify_gym_application_reviewed()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status not in ('approved', 'rejected')
     or new.status is not distinct from old.status then
    return new;
  end if;
  if new.owner_user_id is null then return new; end if;
  perform private.enqueue_push(
    new.owner_user_id,
    'account',
    case new.status
      when 'approved' then '센터 인증이 완료됐어요'
      else '센터 신청이 반려됐어요'
    end,
    case new.status
      when 'approved' then coalesce(nullif(new.gym_name, ''), '센터') || ' · 이제 센터 화면을 쓸 수 있어요.'
      else coalesce(new.reject_reason, '자세한 내용은 신청 내역에서 확인하세요.')
    end,
    jsonb_build_object(
      'event', 'gym_application_' || new.status,
      'applicationId', new.id::text
    )
  );
  return new;
end;
$$;

drop trigger if exists notify_gym_application_reviewed on public.gym_applications;
create trigger notify_gym_application_reviewed
  after update of status on public.gym_applications
  for each row execute function private.notify_gym_application_reviewed();

-- 루틴 심사 결과는 만든 사람(트레이너/센터)의 업무 알림이다.
create or replace function private.notify_coaching_routine_reviewed()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid;
begin
  if old.status is distinct from 'review'
     or new.status not in ('approved', 'rejected') then
    return new;
  end if;
  v_owner := coalesce(
    private.trainer_user(new.trainer_id),
    private.gym_owner(new.gym_id),
    new.submitted_by_user_id
  );
  if v_owner is null then return new; end if;
  perform private.enqueue_push(
    v_owner,
    'business_activity',
    case new.status
      when 'approved' then '루틴이 승인됐어요'
      else '루틴이 반려됐어요'
    end,
    coalesce(nullif(new.title, ''), '루틴') || ' · '
      || case new.status
           when 'approved' then '마켓에 올라갔어요.'
           else coalesce(new.reject_reason, '사유는 루틴 관리에서 확인하세요.')
         end,
    jsonb_build_object(
      'event', 'routine_review_' || new.status,
      'routineId', new.id::text
    )
  );
  return new;
end;
$$;

drop trigger if exists notify_coaching_routine_reviewed on public.coaching_routines;
create trigger notify_coaching_routine_reviewed
  after update of status on public.coaching_routines
  for each row execute function private.notify_coaching_routine_reviewed();

-- ── 함께 운동 ───────────────────────────────────────────────────────────
-- 방에 있는 사람은 Realtime으로 이미 본다. 푸시는 방을 열어 두고 다른 앱에 간
-- 사람을 위한 것이다 — FCM은 앱이 앞에 떠 있으면 시스템 알림을 띄우지 않는다.
create or replace function private.notify_party_joined()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_host uuid;
begin
  select host_user_id into v_host from training_parties where id = new.party_id;
  if v_host is null or v_host = new.user_id then return new; end if;
  perform private.enqueue_push(
    v_host,
    'together',
    coalesce(nullif(new.display_name, ''), '회원') || '님이 방에 들어왔어요',
    '함께 운동을 시작할 준비가 됐어요.',
    jsonb_build_object('event', 'party_joined', 'partyId', new.party_id::text)
  );
  return new;
end;
$$;

drop trigger if exists notify_party_joined on public.training_party_members;
create trigger notify_party_joined
  after insert on public.training_party_members
  for each row execute function private.notify_party_joined();

create or replace function private.notify_party_started()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_member uuid;
begin
  if new.starts_at is null or new.starts_at is not distinct from old.starts_at then
    return new;
  end if;
  foreach v_member in array coalesce(new.member_ids, '{}'::uuid[]) loop
    if v_member = auth.uid() then continue; end if;
    perform private.enqueue_push(
      v_member,
      'together',
      '함께 운동이 시작돼요',
      '방으로 돌아와 첫 세트를 준비하세요.',
      jsonb_build_object('event', 'party_started', 'partyId', new.id::text)
    );
  end loop;
  return new;
end;
$$;

drop trigger if exists notify_party_started on public.training_parties;
create trigger notify_party_started
  after update of starts_at on public.training_parties
  for each row execute function private.notify_party_started();

create or replace function private.notify_party_routine()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_member uuid;
  v_members uuid[];
begin
  select member_ids into v_members from training_parties where id = new.party_id;
  foreach v_member in array coalesce(v_members, '{}'::uuid[]) loop
    if v_member = new.sender_user_id then continue; end if;
    perform private.enqueue_push(
      v_member,
      'together',
      coalesce(nullif(new.sender_name, ''), '회원') || '님이 루틴을 보냈어요',
      coalesce(nullif(new.name, ''), '루틴') || ' · 방에서 받을 수 있어요.',
      jsonb_build_object('event', 'party_routine', 'partyId', new.party_id::text)
    );
  end loop;
  return new;
end;
$$;

drop trigger if exists notify_party_routine on public.training_party_routines;
create trigger notify_party_routine
  after insert on public.training_party_routines
  for each row execute function private.notify_party_routine();

-- ── 운동 리마인더 (크론) ────────────────────────────────────────────────
-- 사용자가 고른 시각(KST)에, 오늘 기록이 없으면 한 번. workout_sessions는
-- 스냅샷 저장 때 sync_my_workout_snapshot이 날짜마다 한 줄씩 맞춰 두므로
-- "오늘 운동했는가"의 진실이다.
create or replace function private.remind_workouts()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamp := now() at time zone 'Asia/Seoul';
  v_today date := (now() at time zone 'Asia/Seoul')::date;
  v_hour int := extract(hour from (now() at time zone 'Asia/Seoul'))::int;
  r record;
  v_last date;
  v_body text;
begin
  for r in
    select s.user_id
    from app_state_snapshots s
    where coalesce((s.payload -> 'preferences' ->> 'pushWorkoutReminder')::boolean, false)
      and coalesce((s.payload -> 'preferences' ->> 'workoutReminderHour')::int, 19) = v_hour
      and exists (select 1 from device_tokens d where d.user_id = s.user_id)
      and not exists (
        select 1 from workout_sessions w
        where w.user_id = s.user_id and w.date = v_today
      )
  loop
    select max(w.date) into v_last from workout_sessions w where w.user_id = r.user_id;
    v_body := case
      when v_last is null then '첫 세트를 기록해 보세요. 30초면 돼요.'
      when v_today - v_last = 1 then '어제 운동했어요. 오늘도 이어 가요.'
      else (v_today - v_last)::text || '일 쉬었어요. 가볍게라도 시작해요.'
    end;
    perform private.enqueue_push(
      r.user_id,
      'workout_reminder',
      '오늘 운동은 아직이에요',
      v_body,
      jsonb_build_object('event', 'workout_reminder', 'date', v_today::text)
    );
  end loop;
end;
$$;

-- 월요일 아침의 지난주 요약. 리마인더를 켠 사람에게만 — 같은 스위치다.
create or replace function private.send_weekly_summaries()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_week_end date := date_trunc('week', (now() at time zone 'Asia/Seoul')::date)::date;
  v_week_start date;
  r record;
  v_days int;
  v_volume numeric;
  v_body text;
begin
  v_week_start := v_week_end - 7;
  for r in
    select s.user_id
    from app_state_snapshots s
    where coalesce((s.payload -> 'preferences' ->> 'pushWorkoutReminder')::boolean, false)
      and exists (select 1 from device_tokens d where d.user_id = s.user_id)
  loop
    select count(distinct w.date),
           coalesce(sum(coalesce(ws.weight, 0) * coalesce(ws.reps, 0)), 0)
      into v_days, v_volume
      from workout_sessions w
      left join workout_exercises we on we.session_id = w.id
      left join workout_sets ws on ws.exercise_id = we.id and coalesce(ws.completed, true)
     where w.user_id = r.user_id
       and w.date >= v_week_start and w.date < v_week_end;
    v_body := case
      when v_days = 0 then '지난주는 쉬어 갔어요. 이번 주 첫 세트부터 다시 시작해요.'
      when v_volume > 0 then
        v_days::text || '일 운동 · 볼륨 ' || to_char(round(v_volume), 'FM999,999,999') || 'kg'
      else v_days::text || '일 운동했어요. 이번 주도 이어 가요.'
    end;
    perform private.enqueue_push(
      r.user_id,
      'workout_reminder',
      '지난주 운동 요약',
      v_body,
      jsonb_build_object('event', 'weekly_summary', 'weekStart', v_week_start::text)
    );
  end loop;
end;
$$;

-- 삭제 3일 전 예고. 30일 유예의 약속은 잊은 사람에게도 지켜져야 한다.
create or replace function private.remind_account_deletions()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
begin
  for r in
    select user_id
    from account_deletion_requests
    where cancelled_at is null
      and purged_at is null
      and reminder_sent_at is null
      and purge_after > now()
      and purge_after <= now() + interval '3 days'
  loop
    perform private.enqueue_push(
      r.user_id,
      'account',
      '3일 뒤 계정이 삭제돼요',
      '계속 쓰려면 설정 > 계정에서 삭제 신청을 취소하세요.',
      jsonb_build_object('event', 'account_deletion_reminder')
    );
    update account_deletion_requests set reminder_sent_at = now() where user_id = r.user_id;
  end loop;
end;
$$;

revoke all on function private.remind_workouts() from public, anon, authenticated;
revoke all on function private.send_weekly_summaries() from public, anon, authenticated;
revoke all on function private.remind_account_deletions() from public, anon, authenticated;

-- ── 크론 ────────────────────────────────────────────────────────────────
select cron.unschedule('setflow-push-schedule-reminders')
  where exists (select 1 from cron.job where jobname = 'setflow-push-schedule-reminders');
select cron.schedule(
  'setflow-push-schedule-reminders',
  '*/10 * * * *',
  $$select private.remind_coaching_schedules()$$
);

select cron.unschedule('setflow-push-workout-reminders')
  where exists (select 1 from cron.job where jobname = 'setflow-push-workout-reminders');
select cron.schedule(
  'setflow-push-workout-reminders',
  '0 * * * *',
  $$select private.remind_workouts()$$
);

-- 월요일 00:00 UTC = 09:00 KST
select cron.unschedule('setflow-push-weekly-summary')
  where exists (select 1 from cron.job where jobname = 'setflow-push-weekly-summary');
select cron.schedule(
  'setflow-push-weekly-summary',
  '0 0 * * 1',
  $$select private.send_weekly_summaries()$$
);

-- 매일 01:00 UTC = 10:00 KST
select cron.unschedule('setflow-push-deletion-reminders')
  where exists (select 1 from cron.job where jobname = 'setflow-push-deletion-reminders');
select cron.schedule(
  'setflow-push-deletion-reminders',
  '0 1 * * *',
  $$select private.remind_account_deletions()$$
);

commit;
