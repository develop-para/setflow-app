import 'package:flutter/material.dart';

/// Brand + neutral tokens. The neutral ramp is deliberately **warm-tinted** to
/// harmonise with the warm Supernova yellow — a warm accent over cool-grey
/// neutrals is the classic "yellow looks cheap" mistake, so every grey here
/// carries a touch of the brand's warmth.
abstract final class SetflowColors {
  /// Supernova yellow (#FFCA10) — the official brand accent. Used as a precise
  /// accent/indicator, never as a large fill (large yellow reads cheap).
  static const primary = Color(0xFFFFCA10);

  /// Kinetic ink — warm near-black primary text (never pure #000).
  static const ink = Color(0xFF17140F);

  /// Structural near-black for hero blocks and inverted CTAs — warm, matched to
  /// the hero gradient so black fields feel intentional, not harsh.
  static const inkBlock = Color(0xFF141210);

  /// Disciplined steel for secondary data, kept muted so ink + yellow lead.
  static const steel = Color(0xFF5F5C57);

  /// Warm secondary text (taupe-grey), not cool slate.
  static const secondaryText = Color(0xFF7A746B);
  static const disabled = Color(0xFFA9A399);
  static const surface = Color(0xFFFFFFFF);
  static const soft = Color(0xFFF7F5F1);
  static const elevated = Color(0xFFF0EDE7);

  /// Warm editorial hairline.
  static const divider = Color(0xFFE8E4DB);
  static const teal = Color(0xFF10CEBD);
  static const orange = Color(0xFFFFB20C);
  static const blue = Color(0xFF3B82F6);
  static const purple = Color(0xFF8B5CF6);
  static const green = Color(0xFF22C55E);
  static const red = Color(0xFFEF4444);
  static const warning = Color(0xFFF59E0B);
  static const info = Color(0xFF3B82F6);
}

/// Warm neutral ramp — the single source of grey for the whole system. Every
/// surface, border, and text grey is drawn from this one warm family so nothing
/// drifts cool against the Supernova yellow. Referenced by the tokens above.
abstract final class SetflowNeutral {
  static const n0 = Color(0xFFFFFFFF); // pure surface
  static const n50 = Color(0xFFF7F5F1); // low container
  static const n100 = Color(0xFFF0EDE7); // container
  static const n200 = Color(0xFFE8E4DB); // hairline / high container
  static const n300 = Color(0xFFD8D2C7); // strong border
  static const n400 = Color(0xFFA9A399); // disabled / hint
  static const n500 = Color(0xFF8A847A); // muted label
  static const n600 = Color(0xFF7A746B); // secondary text
  static const n700 = Color(0xFF57534C); // strong secondary
  static const n800 = Color(0xFF2A2620); // dark elevated
  static const n900 = Color(0xFF141210); // ink block
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

  // Warm-tinted surface ramp (light): stone/sand neutrals, not cool greys.
  static const light = SetflowSemanticColors(
    surfaceContainerLow: Color(0xFFF7F5F1),
    surfaceContainer: Color(0xFFF2EFE9),
    surfaceContainerHigh: Color(0xFFECE8E0),
    disabled: Color(0xFFA9A399),
    success: Color(0xFF22C55E),
    warning: Color(0xFFF59E0B),
    info: Color(0xFF3B82F6),
    teal: Color(0xFF10CEBD),
    blue: Color(0xFF3B82F6),
    purple: Color(0xFF8B5CF6),
    orange: Color(0xFFFFB20C),
  );

  // Warm near-black ramp (dark): matched to the hero gradient so surfaces feel
  // like one warm material rather than a cold slate.
  static const dark = SetflowSemanticColors(
    surfaceContainerLow: Color(0xFF1A1815),
    surfaceContainer: Color(0xFF211E19),
    surfaceContainerHigh: Color(0xFF2A2620),
    disabled: Color(0xFF635E56),
    success: Color(0xFF34D399),
    warning: Color(0xFFF59E0B),
    info: Color(0xFF60A5FA),
    teal: Color(0xFF2DD4BF),
    blue: Color(0xFF60A5FA),
    purple: Color(0xFFA78BFA),
    orange: Color(0xFFFFB020),
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
