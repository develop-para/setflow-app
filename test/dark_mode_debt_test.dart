import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/theme.dart';

/// The colour debt dark mode is carrying, written down so it stops being a
/// rumour.
///
/// `SetflowColors.*` are **light-theme values**. Dark mode is a real switch in
/// settings, and on the dark scaffold most of those constants fall under 4.5:1
/// — `red` at 4.07, `green` at 3.92, `purple` at 3.45. The theme-aware path
/// exists (`context.setflowColors`) and already carries lifted dark variants
/// for most of them.
///
/// What blocks the swap is not the colours, it is `const`: roughly two thirds
/// of the call sites sit inside const data tables that pair an icon, a colour
/// and a label, and those cannot read a BuildContext. Converting them is a
/// restructuring per file, not a find-and-replace, so it has not been done.
///
/// These tests pin the two halves of that: the theme-aware values are correct
/// (so the destination is sound), and the constants are the ones that are not
/// (so nobody re-derives the finding from scratch).
void main() {
  double contrast(Color a, Color b) {
    double lum(Color c) {
      double ch(double v) => v <= 0.03928
          ? v / 12.92
          : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
      return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
    }

    final la = lum(a);
    final lb = lum(b);
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }

  test('the theme-aware colours are the sound destination', () {
    // Whatever else is true, moving a call site to context.setflowColors gets
    // it a value that reads. This is what makes the migration worth doing.
    final dark = SetflowTheme.dark;
    final colors = dark.extension<SetflowSemanticColors>()!;
    final surface = dark.scaffoldBackgroundColor;
    for (final entry in {
      'success': colors.success,
      'error': colors.error,
      'warning': colors.warning,
      'info': colors.info,
      'teal': colors.teal,
      'blue': colors.blue,
      'purple': colors.purple,
      'orange': colors.orange,
    }.entries) {
      expect(
        contrast(entry.value, surface),
        greaterThanOrEqualTo(4.5),
        reason: '${entry.key}의 다크 값이 안 읽힌다 — 옮겨갈 곳이 무너졌다',
      );
    }
  });

  test('the light constants are what fails on the dark surface', () {
    // Not a target to fix here — a record of why the call sites must move.
    // If one of these starts passing, the constant was changed and the note
    // above needs revisiting rather than the test being deleted.
    final surface = SetflowTheme.dark.scaffoldBackgroundColor;
    final failing = <String>[];
    for (final entry in {
      'red': SetflowColors.red,
      'green': SetflowColors.green,
      'orange': SetflowColors.orange,
      'blue': SetflowColors.blue,
      'teal': SetflowColors.teal,
      'purple': SetflowColors.purple,
      'secondaryText': SetflowColors.secondaryText,
    }.entries) {
      if (contrast(entry.value, surface) < 4.5) failing.add(entry.key);
    }
    expect(
      failing,
      hasLength(7),
      reason:
          '라이트 상수의 다크 대비가 바뀌었다. 상수를 손댔다면 '
          'docs/dark-mode-debt.md 의 근거도 같이 고칠 것',
    );
  });

  test('the brand is the one colour that does not need moving', () {
    // Lime is bright in both themes, which is why it stayed a constant while
    // the state colours could not.
    expect(SetflowTheme.light.colorScheme.primary, SetflowColors.brand);
    expect(SetflowTheme.dark.colorScheme.primary, SetflowColors.brand);
    expect(
      contrast(SetflowColors.brand, SetflowTheme.dark.scaffoldBackgroundColor),
      greaterThanOrEqualTo(4.5),
    );
  });
}
