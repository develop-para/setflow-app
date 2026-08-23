import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setflow/theme.dart';

/// Colour that means something has to be readable, or it means nothing.
///
/// The fully monochrome pass collapsed every state onto the grey ramp, so
/// "saved" and "failed" were the same colour. Hue is back for meaning — and the
/// trap that comes with it is that no single hex clears 4.5:1 against both white
/// and near-black, so each role needs a light value and a lifted dark one. This
/// is what stops a hand-picked colour from looking fine in the editor and
/// vanishing on a phone.
double _relativeLuminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

double contrast(Color a, Color b) {
  final la = _relativeLuminance(a);
  final lb = _relativeLuminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  /// WCAG AA for body text. Deliberately the text floor and not the 3:1 one for
  /// large text: these colours label numbers on a set row.
  const floor = 4.5;

  Map<String, Color> rolesOf(ThemeData theme) {
    final c = theme.extension<SetflowSemanticColors>()!;
    return {
      'success': c.success,
      'error': c.error,
      'warning': c.warning,
      'info': c.info,
      'teal': c.teal,
      'blue': c.blue,
      'purple': c.purple,
      'orange': c.orange,
    };
  }

  test('every state colour is readable on its own theme surface', () {
    final failures = <String>[];
    for (final entry in {
      'light': SetflowTheme.light,
      'dark': SetflowTheme.dark,
    }.entries) {
      final surface = entry.value.scaffoldBackgroundColor;
      rolesOf(entry.value).forEach((role, color) {
        final ratio = contrast(color, surface);
        if (ratio < floor) {
          failures.add(
            '${entry.key}.$role ${ratio.toStringAsFixed(2)}:1 on '
            '${surface.toARGB32().toRadixString(16)}',
          );
        }
      });
    }
    expect(failures, isEmpty, reason: '이 상태색들이 자기 배경에서 안 읽힌다');
  });

  test('a state colour is not repeated for a different meaning', () {
    for (final theme in [SetflowTheme.light, SetflowTheme.dark]) {
      final roles = rolesOf(theme);
      // blue and info share a hue on purpose — info *is* the blue one. The rest
      // must stay apart, or the palette is back to saying nothing.
      final meanings = Map.of(roles)..remove('blue');
      final distinct = meanings.values.map((c) => c.toARGB32()).toSet();
      expect(
        distinct.length,
        meanings.length,
        reason: '서로 다른 의미가 같은 색을 쓰고 있다: $meanings',
      );
    }
  });

  test('the brand does not change with the theme', () {
    expect(SetflowTheme.light.colorScheme.primary, SetflowColors.brand);
    expect(SetflowTheme.dark.colorScheme.primary, SetflowColors.brand);
    // A brand that inverts is not a brand. Ink is what flips onto it — and it
    // is the same ink either way, because lime is light in both themes.
    expect(SetflowTheme.light.colorScheme.onPrimary, SetflowColors.onBrand);
    expect(SetflowTheme.dark.colorScheme.onPrimary, SetflowColors.onBrand);
  });

  test('nothing white is ever put on the brand', () {
    // Lime carries white at 1.18:1. This is the mistake the yellow brand made
    // before, so it is worth a test rather than a comment.
    for (final theme in [SetflowTheme.light, SetflowTheme.dark]) {
      expect(theme.colorScheme.onPrimary, isNot(Colors.white));
    }
    expect(
      contrast(SetflowColors.brand, Colors.white),
      lessThan(floor),
      reason: '라임이 흰 배경에서 읽힌다면 이 규칙의 전제가 틀린 것이다',
    );
  });

  test('the brand cannot be a foreground on a light surface', () {
    // Where the trap actually is. On the dark theme lime reads fine (16.7:1),
    // which is exactly why "lime as a glyph" looked reasonable while it was
    // being written — and then the completed tick and the swipe label came out
    // invisible on the light theme, which is the one people use in a gym.
    expect(
      contrast(SetflowColors.brand, SetflowTheme.light.scaffoldBackgroundColor),
      lessThan(3),
      reason: '라임을 밝은 면 위 글자색으로 쓸 수 있다는 전제는 틀렸다 — 채우는 색이다',
    );
    // What rides on the brand is ink, by a margin that leaves no argument.
    expect(
      contrast(SetflowColors.brand, SetflowColors.onBrand),
      greaterThan(12),
    );
  });

  test('the brand is not mistaken for a state', () {
    for (final theme in [SetflowTheme.light, SetflowTheme.dark]) {
      final brand = theme.colorScheme.primary.toARGB32();
      rolesOf(theme).forEach((role, color) {
        expect(
          color.toARGB32(),
          isNot(brand),
          reason: '브랜드가 $role 과 같은 색이다 — 채운 것이 "성공"으로 읽힌다',
        );
      });
    }
  });

  test('the primary control colour stays readable against its foreground', () {
    for (final theme in [SetflowTheme.light, SetflowTheme.dark]) {
      final scheme = theme.colorScheme;
      expect(
        contrast(scheme.primary, scheme.onPrimary),
        greaterThanOrEqualTo(floor),
        reason: 'primary 위의 onPrimary가 안 읽힌다',
      );
    }
  });
}
