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
  /// 홈 — the training calendar, so a calendar, not a house.
  static const home = Icons.calendar_month_outlined;
  static const homeActive = Icons.calendar_month_rounded;

  /// 통계 — volume trend over time.
  static const stats = Icons.show_chart_rounded;
  static const statsActive = Icons.show_chart_rounded;

  /// 커뮤니티 — people talking, not a generic group.
  static const community = Icons.forum_outlined;
  static const communityActive = Icons.forum_rounded;

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

  // --- record surfaces ------------------------------------------------------
  static const routine = Icons.checklist_rounded;
  static const market = Icons.workspace_premium_outlined;
  static const exerciseSearch = Icons.search_rounded;
  static const pastDays = Icons.history_rounded;
  static const addExercise = Icons.add_rounded;

  // --- account hub ----------------------------------------------------------
  static const coaching = Icons.forum_outlined;
  static const goal = Icons.flag_outlined;
  static const membership = Icons.confirmation_number_outlined;
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
