import 'package:flutter/material.dart';

/// Monochrome tokens. The system is white / black / grey only — no hue
/// anywhere. Meaning that used to be carried by colour (danger red, success
/// green, brand yellow) is now carried by **weight**: the darker the grey, the
/// louder the signal. Token *names* are unchanged on purpose so every screen
/// re-skins without being rewritten.
abstract final class SetflowColors {
  /// The accent. Black, not a hue: it fills the primary CTA, the nav
  /// indicator and the bottom bar's center disc.
  static const primary = Color(0xFF111113);

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

  // Former accent slots. They survive as greys so existing call sites keep
  // compiling and simply render monochrome. Pick by loudness, not by hue.
  static const teal = Color(0xFF71717A);
  static const orange = Color(0xFF71717A);
  static const blue = Color(0xFF52525B);
  static const purple = Color(0xFF71717A);
  static const green = Color(0xFF3F3F46);

  /// Danger is the loudest grey there is — black — because destructive actions
  /// can no longer shout in red.
  static const red = Color(0xFF18181B);
  static const warning = Color(0xFF52525B);
  static const info = Color(0xFF52525B);
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
    success: Color(0xFF3F3F46),
    warning: Color(0xFF52525B),
    info: Color(0xFF52525B),
    teal: Color(0xFF71717A),
    blue: Color(0xFF52525B),
    purple: Color(0xFF71717A),
    orange: Color(0xFF71717A),
  );

  // Neutral near-black ramp (dark).
  static const dark = SetflowSemanticColors(
    surfaceContainerLow: Color(0xFF161618),
    surfaceContainer: Color(0xFF1C1C1F),
    surfaceContainerHigh: Color(0xFF27272A),
    disabled: Color(0xFF5C5C63),
    success: Color(0xFFD4D4D8),
    warning: Color(0xFFA1A1AA),
    info: Color(0xFFA1A1AA),
    teal: Color(0xFF8A8A93),
    blue: Color(0xFFA1A1AA),
    purple: Color(0xFF8A8A93),
    orange: Color(0xFF8A8A93),
  );

  final Color surfaceContainerLow;
  final Color surfaceContainer;
  final Color surfaceContainerHigh;
  final Color disabled;
  final Color success;
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
