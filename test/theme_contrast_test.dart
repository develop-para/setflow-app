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
      // info and blue used to be the same hex under two names, so an
      // informational chip and a chart series were the same colour. Every role
      // now has its own, or the palette is back to saying nothing.
      final distinct = roles.values.map((c) => c.toARGB32()).toSet();
      expect(
        distinct.length,
        roles.length,
        reason: '서로 다른 의미가 같은 색을 쓰고 있다: $roles',
      );
    }
  });

  test('a state colour reads on the container it sits on, not just the page', () {
    // Where this last broke: a dialog is a raised grey panel, so a label that
    // clears 4.5:1 against the white page can still fail by the time it is
    // drawn inside one. The floor has to be measured against the surface the
    // colour actually lands on.
    final failures = <String>[];
    for (final entry in {
      'light': SetflowTheme.light,
      'dark': SetflowTheme.dark,
    }.entries) {
      final c = entry.value.extension<SetflowSemanticColors>()!;
      final containers = {
        'containerLow': c.surfaceContainerLow,
        'container': c.surfaceContainer,
        'containerHigh': c.surfaceContainerHigh,
      };
      rolesOf(entry.value).forEach((role, color) {
        containers.forEach((name, bg) {
          final ratio = contrast(color, bg);
          if (ratio < floor) {
            failures.add(
              '${entry.key}.$role on $name ${ratio.toStringAsFixed(2)}:1',
            );
          }
        });
      });
      // 보조 글자색도 같은 판 위에 놓인다.
      containers.forEach((name, bg) {
        final ratio = contrast(entry.value.colorScheme.onSurfaceVariant, bg);
        if (ratio < floor) {
          failures.add(
            '${entry.key}.onSurfaceVariant on $name ${ratio.toStringAsFixed(2)}:1',
          );
        }
      });
    }
    expect(failures, isEmpty, reason: '이 색들이 자기가 놓이는 판 위에서 안 읽힌다');
  });

  test('the state colours sit on one rung, so they read as a set', () {
    // Readable is the floor; *belonging together* is the part that makes the
    // palette look chosen. Equal contrast is equal luminance, which is why
    // eight different hues can share a weight on the page. When they drifted —
    // a bright red beside a near-black teal — every chip row looked like
    // swatches borrowed from different apps.
    for (final entry in {
      'light': SetflowTheme.light,
      'dark': SetflowTheme.dark,
    }.entries) {
      final surface = entry.value.scaffoldBackgroundColor;
      final ratios = rolesOf(
        entry.value,
      ).map((role, c) => MapEntry(role, contrast(c, surface)));
      final spread =
          ratios.values.reduce(math.max) - ratios.values.reduce(math.min);
      expect(
        spread,
        lessThan(1.0),
        reason: '${entry.key}의 상태색 대비가 흩어져 있다 — 같은 세트로 안 보인다: $ratios',
      );
    }
  });

  test('the grey ramp is grey, not a cool one pretending', () {
    // A zinc ramp (#71717A — more blue than red) beside a yellow-green brand
    // reads faintly violet, and the page looks like two palettes that met by
    // accident. Neutral means R = G = B, on every rung.
    final offenders = <String>[];
    for (final entry in {
      'n50': SetflowNeutral.n50,
      'n100': SetflowNeutral.n100,
      'n200': SetflowNeutral.n200,
      'n300': SetflowNeutral.n300,
      'n400': SetflowNeutral.n400,
      'n500': SetflowNeutral.n500,
      'n600': SetflowNeutral.n600,
      'n700': SetflowNeutral.n700,
      'n800': SetflowNeutral.n800,
      'n900': SetflowNeutral.n900,
    }.entries) {
      final c = entry.value;
      if (c.r != c.g || c.g != c.b) offenders.add(entry.key);
    }
    expect(offenders, isEmpty, reason: '이 회색들이 색을 띠고 있다');
  });

  test('the brand can be read as well as filled', () {
    // Lime is a fill and only a fill. Without a readable counterpart the brand
    // simply could not appear as text or an icon, so anything that wanted to
    // look like ours reached for an unrelated hue — which is how the palette
    // spread in the first place.
    expect(
      contrast(SetflowColors.brandDeep, Colors.white),
      greaterThanOrEqualTo(floor),
      reason: '브랜드를 밝은 면 위 글자색으로 쓸 수 없다',
    );
    // And the pale tint has to carry ink, or "selected" becomes unreadable.
    expect(
      contrast(SetflowColors.brandSoft, SetflowColors.ink),
      greaterThanOrEqualTo(floor),
    );
    // All three have to be recognisably the same hue family.
    double hueOf(Color c) => HSLColor.fromColor(c).hue;
    for (final c in [SetflowColors.brandDeep, SetflowColors.brandSoft]) {
      expect(
        (hueOf(c) - hueOf(SetflowColors.brand)).abs(),
        lessThan(20),
        reason: '브랜드 계열이 아니다',
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
