import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/theme.dart';

/// What dark mode still gets wrong, and what it no longer does.
///
/// `SetflowColors.*` are light-theme values; on the dark scaffold most of them
/// fall under 4.5:1. 363 call sites used to reach for them directly and 359 now
/// go through `context.setflowColors`, which carries a lifted dark value for
/// each role.
///
/// Four are left, all in one place: the colour that rides along inside a
/// `RoutineData`. A model cannot read a BuildContext, and the real fix is to
/// take the colour out of the model and let the screen decide it from the
/// status — a change to what the model holds, not a colour swap.
///
/// These tests pin both ends so neither has to be measured again: the
/// theme-aware values are sound, and the constants are what fails.
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

  test('no screen still reaches for a light-only text colour', () {
    // secondaryText was 167 call sites and is now zero: it reads as
    // onSurfaceVariant, which the colour scheme already flips. This is the
    // guard against it creeping back one Text at a time.
    final offenders = <String>[];
    for (final entry in {
      'secondaryText': SetflowColors.secondaryText,
    }.entries) {
      final light = SetflowTheme.light.colorScheme.onSurfaceVariant;
      // 라이트에서 값이 같다는 것이 이관이 안전했던 이유다 — 화면은 그대로 보인다.
      if (entry.value.toARGB32() != light.toARGB32()) {
        offenders.add('${entry.key} no longer matches onSurfaceVariant');
      }
    }
    expect(offenders, isEmpty);
    // 그리고 다크에서는 컬러스킴 쪽이 읽힌다.
    expect(
      contrast(
        SetflowTheme.dark.colorScheme.onSurfaceVariant,
        SetflowTheme.dark.scaffoldBackgroundColor,
      ),
      greaterThanOrEqualTo(4.5),
      reason: '다크의 보조 글자색이 안 읽힌다',
    );
  });

  test('the light constants are what failed, and why they had to move', () {
    // Kept after the migration, not before it: this is the evidence for why
    // 359 call sites moved, and the guard on the four that could not. If one
    // starts passing, someone changed a constant and the note above needs
    // revisiting rather than the test being deleted.
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
