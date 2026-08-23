import 'package:flutter/material.dart';

/// Setflow's colour tokens.
///
/// Monochrome is the *direction*, not a ban: surfaces, type and controls are
/// white / black / grey, and hue is reserved for things that mean something —
/// success, error, warning, info, and the workout categories. A grey that says
/// "error" and a grey that says "success" are the same grey, which is what the
/// fully monochrome pass gave up.
///
/// These constants are the **light-theme** values. Dark needs different ones —
/// no single hue clears 4.5:1 against both white and near-black — so the pairs
/// live in [SetflowSemanticColors] and are reached through
/// `context.setflowColors`. Prefer that over these constants wherever the
/// colour lands on a surface that flips with the theme.
abstract final class SetflowColors {
  /// Setflow lime — the brand. It fills things: the primary CTA, the nav
  /// indicator, the bottom bar's centre disc. Energy is the point, so it stays
  /// the same in light and dark rather than inverting.
  ///
  /// **Never as text or an icon on a light surface.** Lime on white is 1.18:1;
  /// it only works the other way round, carrying [onPrimary] ink on top of it.
  static const brand = Color(0xFFCCFF00);

  /// The accent that fills interactive surfaces. The brand, by definition —
  /// kept as a separate name because plenty of call sites mean "the primary
  /// control colour" rather than "the brand".
  static const primary = brand;

  /// What goes *on* [brand]. Ink at 16:1 — white would be 1.18:1 and vanish.
  static const onBrand = Color(0xFF111113);

  /// Primary text. Pure-ish black, no warm cast.
  static const ink = Color(0xFF111113);

  /// Structural black for inverted blocks and hero fields.
  static const inkBlock = Color(0xFF18181B);

  /// Strong secondary — data labels that still need to read as text.
  static const steel = Color(0xFF52525B);

  static const secondaryText = Color(0xFF71717A);
  static const disabled = Color(0xFFA1A1AA);
  static const surface = Color(0xFFFFFFFF);
  static const soft = Color(0xFFF7F7F8);
  static const elevated = Color(0xFFF1F1F2);

  /// Hairline.
  static const divider = Color(0xFFE4E4E7);

  // --- meaning, not decoration ----------------------------------------------
  // Every one of these clears 4.5:1 on white; the dark counterparts are in
  // SetflowSemanticColors.dark. Checked by test/theme_contrast_test.dart, which
  // is what keeps a hand-picked hex from quietly failing to be readable.
  static const green = Color(0xFF15803D);
  static const red = Color(0xFFDC2626);
  static const warning = Color(0xFFB45309);
  static const info = Color(0xFF2563EB);

  // Workout categories and chart series. Distinct hues, same contrast floor.
  static const teal = Color(0xFF0F766E);
  static const blue = Color(0xFF2563EB);
  static const purple = Color(0xFF7C3AED);
  static const orange = Color(0xFFC2410C);
}

/// The single grey ramp. True neutrals (zero chroma) — the old warm/stone tint
/// is gone along with the yellow it was harmonising with.
abstract final class SetflowNeutral {
  static const n0 = Color(0xFFFFFFFF); // pure surface
  static const n50 = Color(0xFFF7F7F8); // low container
  static const n100 = Color(0xFFF1F1F2); // container
  static const n200 = Color(0xFFE4E4E7); // hairline / high container
  static const n300 = Color(0xFFD4D4D8); // strong border
  static const n400 = Color(0xFFA1A1AA); // disabled / hint
  static const n500 = Color(0xFF8A8A93); // muted label
  static const n600 = Color(0xFF71717A); // secondary text
  static const n700 = Color(0xFF52525B); // strong secondary
  static const n800 = Color(0xFF27272A); // dark elevated
  static const n900 = Color(0xFF111113); // ink block
}

@immutable
class SetflowSemanticColors extends ThemeExtension<SetflowSemanticColors> {
  const SetflowSemanticColors({
    required this.surfaceContainerLow,
    required this.surfaceContainer,
    required this.surfaceContainerHigh,
    required this.disabled,
    required this.success,
    required this.error,
    required this.warning,
    required this.info,
    required this.teal,
    required this.blue,
    required this.purple,
    required this.orange,
  });

  // Neutral surface ramp (light).
  static const light = SetflowSemanticColors(
    surfaceContainerLow: Color(0xFFF7F7F8),
    surfaceContainer: Color(0xFFF1F1F2),
    surfaceContainerHigh: Color(0xFFE9E9EC),
    disabled: Color(0xFFA1A1AA),
    success: Color(0xFF15803D),
    error: Color(0xFFDC2626),
    warning: Color(0xFFB45309),
    info: Color(0xFF2563EB),
    teal: Color(0xFF0F766E),
    blue: Color(0xFF2563EB),
    purple: Color(0xFF7C3AED),
    orange: Color(0xFFC2410C),
  );

  // Neutral near-black ramp (dark).
  static const dark = SetflowSemanticColors(
    surfaceContainerLow: Color(0xFF161618),
    surfaceContainer: Color(0xFF1C1C1F),
    surfaceContainerHigh: Color(0xFF27272A),
    disabled: Color(0xFF5C5C63),
    // Lifted, not the light values: a hue dark enough to read on white is too
    // dark to read on near-black, and the other way round.
    success: Color(0xFF22C55E),
    error: Color(0xFFF87171),
    warning: Color(0xFFF59E0B),
    info: Color(0xFF60A5FA),
    teal: Color(0xFF2DD4BF),
    blue: Color(0xFF60A5FA),
    purple: Color(0xFFA78BFA),
    orange: Color(0xFFFB923C),
  );

  final Color surfaceContainerLow;
  final Color surfaceContainer;
  final Color surfaceContainerHigh;
  final Color disabled;
  final Color success;
  final Color error;
  final Color warning;
  final Color info;
  final Color teal;
  final Color blue;
  final Color purple;
  final Color orange;

  @override
  SetflowSemanticColors copyWith({
    Color? surfaceContainerLow,
    Color? surfaceContainer,
    Color? surfaceContainerHigh,
    Color? disabled,
    Color? success,
    Color? error,
    Color? warning,
    Color? info,
    Color? teal,
    Color? blue,
    Color? purple,
    Color? orange,
  }) {
    return SetflowSemanticColors(
      surfaceContainerLow: surfaceContainerLow ?? this.surfaceContainerLow,
      surfaceContainer: surfaceContainer ?? this.surfaceContainer,
      surfaceContainerHigh: surfaceContainerHigh ?? this.surfaceContainerHigh,
      disabled: disabled ?? this.disabled,
      success: success ?? this.success,
      error: error ?? this.error,
      warning: warning ?? this.warning,
      info: info ?? this.info,
      teal: teal ?? this.teal,
      blue: blue ?? this.blue,
      purple: purple ?? this.purple,
      orange: orange ?? this.orange,
    );
  }

  @override
  SetflowSemanticColors lerp(covariant SetflowSemanticColors? other, double t) {
    if (other == null) return this;
    return SetflowSemanticColors(
      surfaceContainerLow: Color.lerp(
        surfaceContainerLow,
        other.surfaceContainerLow,
        t,
      )!,
      surfaceContainer: Color.lerp(
        surfaceContainer,
        other.surfaceContainer,
        t,
      )!,
      surfaceContainerHigh: Color.lerp(
        surfaceContainerHigh,
        other.surfaceContainerHigh,
        t,
      )!,
      disabled: Color.lerp(disabled, other.disabled, t)!,
      success: Color.lerp(success, other.success, t)!,
      error: Color.lerp(error, other.error, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      info: Color.lerp(info, other.info, t)!,
      teal: Color.lerp(teal, other.teal, t)!,
      blue: Color.lerp(blue, other.blue, t)!,
      purple: Color.lerp(purple, other.purple, t)!,
      orange: Color.lerp(orange, other.orange, t)!,
    );
  }
}

extension SetflowThemeContext on BuildContext {
  SetflowSemanticColors get setflowColors =>
      Theme.of(this).extension<SetflowSemanticColors>() ??
      (Theme.of(this).brightness == Brightness.dark
          ? SetflowSemanticColors.dark
          : SetflowSemanticColors.light);
}

abstract final class SetflowSpacing {
  static const xxs = 2.0;
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 24.0;
  static const section = 32.0;
  static const huge = 40.0;
  static const page = 48.0;
}

abstract final class SetflowInsets {
  static const pageList = EdgeInsets.fromLTRB(24, 6, 24, 28);
  static const pageListTight = EdgeInsets.fromLTRB(24, 4, 24, 28);
  static const pageHeader = EdgeInsets.fromLTRB(24, 4, 24, 12);
  static const pageForm = EdgeInsets.fromLTRB(24, 12, 24, 28);
  static const bottomAction = EdgeInsets.fromLTRB(24, 10, 24, 16);
}

abstract final class SetflowRadii {
  // Kinetic runs tighter than stock Material — corners read as "printed"
  // panels, not soft bubbles. Pills stay full-round for chips/toggles.
  static const xs = 6.0;
  static const sm = 10.0;
  static const md = 14.0;
  static const lg = 18.0;
  static const xl = 24.0;
  static const full = 999.0;
}

abstract final class SetflowMotion {
  // Kinetic motion snaps — quick, confident, slight overshoot on emphasis.
  static const micro = Duration(milliseconds: 130);
  static const standard = Duration(milliseconds: 240);
  static const page = Duration(milliseconds: 300);
  static const standardCurve = Curves.easeOutCubic;
  static const emphasisCurve = Curves.easeOutBack;
  // Number counters and stat reveals use a fast expo settle.
  static const kineticCurve = Cubic(0.16, 1, 0.3, 1); // easeOutExpo-ish
}

abstract final class SetflowShadows {
  // Editorial = mostly flat. Shadows are tight and low-spread, reserved for
  // genuinely floating elements (sheets, FABs, the rest-timer chip).
  static const level1 = [
    BoxShadow(color: Color(0x0F000000), blurRadius: 8, offset: Offset(0, 2)),
  ];
  static const level2 = [
    BoxShadow(color: Color(0x16000000), blurRadius: 18, offset: Offset(0, 6)),
  ];
  static const level3 = [
    BoxShadow(color: Color(0x20000000), blurRadius: 32, offset: Offset(0, 12)),
  ];
}
