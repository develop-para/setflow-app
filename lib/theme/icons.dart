import 'package:flutter/material.dart';

/// The app's icon vocabulary — one name per product concept, one glyph per
/// name.
///
/// Two rules keep it from drifting back into a grab-bag:
/// 1. **One family.** Everything is Material *rounded*; the geometry matches
///    the type's soft terminals and nothing looks borrowed.
/// 2. **Outline = resting, filled = active.** A concept that can be selected
///    exposes both variants, so selection reads without colour — which is the
///    whole point in a monochrome system.
///
/// Add a concept here rather than reaching for `Icons.*` at a call site; that
/// is how the app ended up with a rocket, a barbell and a gavel all meaning
/// "important".
abstract final class SetflowIcons {
  // --- primary navigation ---------------------------------------------------
  /// 홈 — 오늘 요약과 소식이 모이는 곳. 캘린더가 기록 탭으로 옮겨 가면서
  /// "홈 = 훈련 캘린더" 등식이 깨졌으므로 글리프도 집으로 돌아왔다.
  static const home = Icons.home_outlined;
  static const homeActive = Icons.home_rounded;

  /// 홈 왼쪽 위의 전체 메뉴 — 모든 기능으로 가는 바로가기 서랍(OKX의 그리드
  /// 버튼과 같은 자리). 바텀바에 자리가 없는 화면들이 여기서 열린다.
  static const appMenu = Icons.apps_rounded;

  /// 홈 오른쪽 위의 알림함 — 도착한 알림을 다시 보는 곳. 아웃라인=평소,
  /// 채움=안 읽은 것이 있을 때(선택과 같은 문법).
  static const notifications = Icons.notifications_none_rounded;
  static const notificationsActive = Icons.notifications_rounded;

  /// 캘린더 — 날짜를 골라 기록으로 들어가는 판. 기록 탭의 첫 화면이다.
  static const calendar = Icons.calendar_month_outlined;
  static const calendarActive = Icons.calendar_month_rounded;

  /// 통계 — volume trend over time.
  static const stats = Icons.show_chart_rounded;
  static const statsActive = Icons.show_chart_rounded;

  /// 커뮤니티 — people talking, not a generic group.
  static const community = Icons.forum_outlined;
  static const communityActive = Icons.forum_rounded;

  /// 함께 — training with someone who is somewhere else. Two figures, because
  /// the point is the second person, not the group: 커뮤니티 is the crowd you
  /// read, 함께 is the one partner you are mid-set with.
  static const together = Icons.people_alt_outlined;
  static const togetherActive = Icons.people_alt_rounded;

  /// 마이 — the account hub.
  static const my = Icons.person_outline_rounded;
  static const myActive = Icons.person_rounded;

  // --- the core act ---------------------------------------------------------
  /// 기록 — logging the set you are doing right now. This is the one glyph the
  /// product is about, so it gets the loudest slot on the bar.
  static const record = Icons.fitness_center_rounded;

  /// The record disc while its action sheet is open.
  static const close = Icons.close_rounded;

  /// 세트 완료 토글. 글리프는 하나고 상태는 **채움 여부**로 낸다 — 체크가 두 종류면
  /// 완료와 미완료가 둘 다 "체크된 것"처럼 보인다.
  static const setComplete = Icons.check_rounded;

  /// 되돌리기. 완료의 반대가 아니라 **방금 한 일을 취소**하는 별개 개념이라
  /// 체크를 변형해 쓰지 않는다 — 위 규칙대로 완료 글리프는 하나뿐이다.
  static const undo = Icons.undo_rounded;

  /// 종목 수행 방법. '설명'이 아니라 **따라 하는 순서**라 목록 글리프를 쓴다.
  static const guide = Icons.format_list_numbered_rounded;

  // --- 함께 -----------------------------------------------------------------
  /// 방 만들기 / 코드로 참여.
  static const partyCreate = Icons.add_rounded;
  static const partyJoin = Icons.login_rounded;

  /// 같이 시작 — the shared countdown.
  static const partyStart = Icons.play_arrow_rounded;

  /// 방을 열 때 고르는 것들 — 누가 들어오는지, 무엇을 하는지.
  static const publicRoom = Icons.public_rounded;
  static const privateRoom = Icons.lock_outline_rounded;
  static const activityGym = Icons.fitness_center_rounded;
  static const activityCrossfit = Icons.bolt_rounded;
  static const activityAlternate = Icons.swap_horiz_rounded;

  /// 유산소 운동 — 특정 근육을 강조하지 않는 심폐 활동 표식.
  static const cardio = Icons.directions_run_rounded;

  /// 초대 코드를 복사한다.
  static const copyCode = Icons.copy_rounded;

  /// 루틴을 상대에게 건넨다.
  static const handOver = Icons.ios_share_rounded;

  /// 함께 방 초대 링크를 보낸다.
  static const shareInvite = Icons.ios_share_rounded;

  /// 방을 떠난다.
  static const leaveParty = Icons.logout_rounded;

  // --- record surfaces ------------------------------------------------------
  static const routine = Icons.checklist_rounded;
  static const market = Icons.workspace_premium_outlined;
  static const exerciseSearch = Icons.search_rounded;
  static const pastDays = Icons.history_rounded;
  static const addExercise = Icons.add_rounded;

  /// Third-party software and artwork attribution.
  static const openSource = Icons.info_outline_rounded;

  // --- account hub ----------------------------------------------------------
  static const coaching = Icons.forum_outlined;
  static const goal = Icons.flag_outlined;
  static const membership = Icons.confirmation_number_outlined;
  static const location = Icons.location_on_outlined;
  static const locationActive = Icons.location_on_rounded;
  static const gym = Icons.apartment_rounded;
  static const onlineConsultation = Icons.video_call_outlined;
  static const offlineConsultation = Icons.handshake_outlined;
  static const delete = Icons.delete_outline_rounded;
  static const settings = Icons.tune_rounded;
  static const signIn = Icons.login_rounded;
  static const signOut = Icons.logout_rounded;
  static const signUp = Icons.person_add_alt_1_rounded;

  // --- credentials ----------------------------------------------------------
  /// The account itself — sign-in and sign-up headers.
  static const account = Icons.lock_person_rounded;

  /// 비밀번호 — setting, changing or resetting one.
  static const password = Icons.key_rounded;

  /// A mail we sent and are waiting on (confirmation, reset link).
  static const mailSent = Icons.mark_email_unread_rounded;

  static const passwordVisible = Icons.visibility_rounded;
  static const passwordHidden = Icons.visibility_off_rounded;

  // --- feedback -------------------------------------------------------------
  static const error = Icons.error_outline_rounded;
  static const success = Icons.check_circle_outline_rounded;
  static const cloudUnavailable = Icons.cloud_off_outlined;

  // --- pro portal -----------------------------------------------------------
  /// 트레이너 등록 / 승인이 필요한 자격. 포탈 스위처의 프로 쪽도 이 글리프다 —
  /// 트레이너·헬스장·운영은 문 하나를 나눠 쓰는 같은 자격이라 글리프도 하나다.
  static const pro = Icons.badge_outlined;
  static const proActive = Icons.badge_rounded;

  /// 관리자 심사를 기다리는 상태.
  static const pending = Icons.hourglass_top_rounded;

  // --- affordances ----------------------------------------------------------
  static const forward = Icons.chevron_right_rounded;
  static const back = Icons.arrow_back_rounded;

  /// 펼쳐진 것을 접는다 / 접힌 것을 펼친다. 화살표가 가리키는 쪽이 결과다 —
  /// 위로 = 접힌다, 아래로 = 내려온다.
  static const collapse = Icons.keyboard_arrow_up_rounded;
  static const expand = Icons.keyboard_arrow_down_rounded;
}
