import 'package:flutter/material.dart';

/// Backward-compatible brand constants used throughout the existing screens.
abstract final class SetflowColors {
  static const primary = Color(0xFFFFCA10);
  static const ink = Color(0xFF241F20);
  static const secondaryText = Color(0xFF6B7280);
  static const disabled = Color(0xFF9CA3AF);
  static const surface = Color(0xFFFFFFFF);
  static const soft = Color(0xFFF7F8FA);
  static const elevated = Color(0xFFF1F3F6);
  static const divider = Color(0xFFE3E5E5);
  static const teal = Color(0xFF10CEBD);
  static const orange = Color(0xFFFFB20C);
  static const blue = Color(0xFF3B82F6);
  static const purple = Color(0xFF8B5CF6);
  static const green = Color(0xFF22C55E);
  static const red = Color(0xFFEF4444);
  static const warning = Color(0xFFF59E0B);
  static const info = Color(0xFF3B82F6);
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

  static const light = SetflowSemanticColors(
    surfaceContainerLow: Color(0xFFF7F8FA),
    surfaceContainer: Color(0xFFF4F6F9),
    surfaceContainerHigh: Color(0xFFEEF1F5),
    disabled: Color(0xFF9CA3AF),
    success: Color(0xFF22C55E),
    warning: Color(0xFFF59E0B),
    info: Color(0xFF3B82F6),
    teal: Color(0xFF10CEBD),
    blue: Color(0xFF3B82F6),
    purple: Color(0xFF8B5CF6),
    orange: Color(0xFFFFB20C),
  );

  static const dark = SetflowSemanticColors(
    surfaceContainerLow: Color(0xFF1E1D20),
    surfaceContainer: Color(0xFF232227),
    surfaceContainerHigh: Color(0xFF2A2930),
    disabled: Color(0xFF6B7280),
    success: Color(0xFF22C55E),
    warning: Color(0xFFF59E0B),
    info: Color(0xFF60A5FA),
    teal: Color(0xFF2DD4BF),
    blue: Color(0xFF60A5FA),
    purple: Color(0xFFA78BFA),
    orange: Color(0xFFFBBF24),
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
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 20.0;
  static const xl = 28.0;
  static const full = 999.0;
}

abstract final class SetflowMotion {
  static const micro = Duration(milliseconds: 150);
  static const standard = Duration(milliseconds: 260);
  static const page = Duration(milliseconds: 320);
  static const standardCurve = Curves.easeOutCubic;
  static const emphasisCurve = Curves.easeOutBack;
}

abstract final class SetflowShadows {
  static const level1 = [
    BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, 4)),
  ];
  static const level2 = [
    BoxShadow(color: Color(0x1A000000), blurRadius: 24, offset: Offset(0, 8)),
  ];
  static const level3 = [
    BoxShadow(color: Color(0x24000000), blurRadius: 40, offset: Offset(0, 16)),
  ];
}
