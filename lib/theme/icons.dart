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

  // --- affordances ----------------------------------------------------------
  static const forward = Icons.chevron_right_rounded;
  static const back = Icons.arrow_back_rounded;
}
