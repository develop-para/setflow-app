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
  static const onBrand = Color(0xFF111111);

  /// The brand where it has to be **read** rather than filled: a lime-olive
  /// deep enough to carry text and icons on white (4.9:1).
  ///
  /// Without this the brand could only ever appear as a block, so anything that
  /// wanted to look like ours *and* be legible reached for an unrelated hue.
  /// That is where the palette started saying nothing.
  static const brandDeep = Color(0xFF627A01);

  /// The brand as a *tint* — a selected row, the container behind a primary
  /// action. Pale enough to carry [ink] at 18:1, so selection can belong to the
  /// brand without a neon block on the page.
  static const brandSoft = Color(0xFFF5FEDA);

  /// Primary text. Pure neutral black — no cast in either direction.
  static const ink = Color(0xFF111111);

  /// Structural black for inverted blocks and hero fields.
  static const inkBlock = Color(0xFF191919);

  /// Strong secondary — data labels that still need to read as text.
  static const steel = Color(0xFF535353);

  static const secondaryText = Color(0xFF696969);
  static const disabled = Color(0xFFA2A2A2);
  static const surface = Color(0xFFFFFFFF);
  static const soft = Color(0xFFF7F7F7);
  static const elevated = Color(0xFFF1F1F1);

  /// Hairline.
  static const divider = Color(0xFFE4E4E4);

  // --- meaning, not decoration ----------------------------------------------
  // Every one of these clears 4.5:1 on white; the dark counterparts are in
  // SetflowSemanticColors.dark. Checked by test/theme_contrast_test.dart, which
  // is what keeps a hand-picked hex from quietly failing to be readable.
  /// 잉크 블록의 그라디언트 양 끝. 통짜 검정이면 판이 죽어 보여서 아주 얕게 기울인다.
  static const inkBlockTop = Color(0xFF1D1D1D);
  static const inkBlockBottom = Color(0xFF0B0B0B);

  /// 시트나 오버레이 뒤를 덮는 막. 아래 화면이 비쳐야 하므로 완전 불투명이 아니다.
  static const scrim = Color(0x59000000);

  // Every hue below is tuned to land on the **same rung of contrast** against
  // white (5.6:1, give or take) — which also leaves it readable on the grey
  // containers these actually sit on, not just on the page. Equal contrast is
  // equal luminance, and that is
  // what makes eight unrelated hues read as one family instead of eight
  // borrowed swatches. The chip row was the tell: a bright red sat next to a
  // nearly-black teal and neither looked chosen.
  static const green = Color(0xFF0F773E);
  static const red = Color(0xFFC23020);
  static const warning = Color(0xFF905D06);
  static const info = Color(0xFF0C6E9F);

  // Workout categories and chart series. Distinct hues, same contrast floor.
  static const teal = Color(0xFF0D756A);
  static const blue = Color(0xFF365DDC);
  static const purple = Color(0xFF9535D6);
  static const orange = Color(0xFFB34414);
}

/// The single grey ramp — **actually** neutral: R = G = B on every rung.
///
/// It used to be zinc, which is cool: `#71717A` carries more blue than red.
/// Next to a yellow-green brand a cool grey reads as faintly violet, and the
/// page looks like two palettes that met by accident. That was the "colours are
/// a bit off" complaint, and it lived in the greys — the part nobody thinks of
/// as colour.
///
/// Each rung keeps the luminance of the zinc value it replaced, so every
/// contrast ratio ever measured against this ramp still holds.
abstract final class SetflowNeutral {
  static const n0 = Color(0xFFFFFFFF); // pure surface
  static const n50 = Color(0xFFF7F7F7); // low container
  static const n100 = Color(0xFFF1F1F1); // container
  static const n200 = Color(0xFFE4E4E4); // hairline / high container
  static const n300 = Color(0xFFD4D4D4); // strong border
  static const n400 = Color(0xFFA2A2A2); // disabled / hint
  static const n500 = Color(0xFF8B8B8B); // muted label
  static const n600 = Color(0xFF696969); // secondary text
  static const n700 = Color(0xFF535353); // strong secondary
  static const n800 = Color(0xFF272727); // dark elevated
  static const n900 = Color(0xFF111111); // ink block
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
    surfaceContainerLow: Color(0xFFF7F7F7),
    surfaceContainer: Color(0xFFF1F1F1),
    surfaceContainerHigh: Color(0xFFE9E9E9),
    disabled: Color(0xFFA2A2A2),
    success: Color(0xFF0F773E),
    error: Color(0xFFC23020),
    warning: Color(0xFF905D06),
    // info used to *be* blue — the same hex under two names, which is a palette
    // with a hole in it: an informational chip and a chart series could not be
    // told apart. It is its own cyan-leaning blue now.
    info: Color(0xFF0C6E9F),
    teal: Color(0xFF0D756A),
    blue: Color(0xFF365DDC),
    purple: Color(0xFF9535D6),
    orange: Color(0xFFB34414),
  );

  // Neutral near-black ramp (dark).
  static const dark = SetflowSemanticColors(
    surfaceContainerLow: Color(0xFF161616),
    surfaceContainer: Color(0xFF1D1D1D),
    surfaceContainerHigh: Color(0xFF272727),
    disabled: Color(0xFF5D5D5D),
    // Lifted, not the light values: a hue dark enough to read on white is too
    // dark to read on near-black, and the other way round.
    // Same idea as light, one rung higher: all eight land near 6.8:1 on the
    // dark scaffold, so the set holds together there too.
    success: Color(0xFF21AE60),
    error: Color(0xFFE7776B),
    warning: Color(0xFFCD8A17),
    info: Color(0xFF1DA1E3),
    teal: Color(0xFF1FAD9F),
    blue: Color(0xFF7C95E4),
    purple: Color(0xFFBC7EE5),
    orange: Color(0xFFE57B4E),
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

/// 글자 크기의 사다리. `theme.textTheme`의 역할들과 같은 값이고, 역할 하나로
/// 딱 떨어지지 않는 자리(세트 행의 촘촘한 캡션 같은)를 위해 이름으로도 꺼내 쓴다.
///
/// 이게 생기기 전엔 화면에 fontSize가 307군데 박혀 있었고 **서로 다른 값이 25종**이었다.
/// 13과 13.5, 17과 18, 25·26·27이 한 앱 안에 같이 있었다 — 눈에는 "안 맞는다"로만 보이는
/// 종류의 어긋남이다. 새 숫자를 만들지 말고 여기서 고를 것.
/// 달력 칸 **채움 전용** 부위 색. 상태색(`SetflowColors.red` 등)은 글자용이라 5.6:1에
/// 맞춘 어두운 값이고, 그걸 배경에 옅게 깔면 탁하다("색상이 완전 별로"). 여기 값은
/// 면으로 쓰는 밝고 선명한 색이고 위에는 언제나 잉크 글자다(전부 4.5:1 이상). 면 자체가
/// 색이라 라이트·다크에서 뒤집지 않는다. 글자·점·아이콘에는 쓰지 말 것 — 흰 배경 위에서
/// 대비가 안 나온다.
abstract final class SetflowMuscleFill {
  static const chest = Color(0xFFFF6B6B);
  static const back = Color(0xFF4D8DFF);
  static const shoulders = Color(0xFF2EC4B6);
  static const legs = Color(0xFF34C759);
  static const arms = Color(0xFFFF9F43);
  static const core = Color(0xFFA66CFF);
  static const cardio = Color(0xFF4CC9F0);
}

abstract final class SetflowFontSize {
  /// 달력 칸의 볼륨, 세트 행의 보조 캡션. 이보다 작게 쓰지 않는다.
  static const micro = 9.0;
  static const tiny = 10.0;
  static const small = 11.0;
  static const caption = 12.0;
  static const label = 13.5;
  static const body = 14.0;
  static const bodyLarge = 15.0;
  static const title = 16.0;
  static const titleLarge = 18.0;
  static const headline = 20.0;
  static const headlineLarge = 24.0;
  static const display = 28.0;
  static const displayLarge = 38.0;
  static const hero = 52.0;
}

/// 여백의 사다리. **전부 짝수다** — 화면이 촘촘해서 작은 쪽은 2씩, 20 위로는 4씩 오른다.
///
/// 홀수가 보이면 그리드를 벗어난 것이다. 실제로 5·7·9·11·13·15가 65군데 섞여 있었고,
/// 그렇게 1px씩 어긋난 여백은 "레이아웃이 안 맞는다"로만 보인다. 아키텍처 규칙이 막는다.
/// 글자 굵기의 사다리. 위계는 크기만으로 나지 않는다 — 굵기가 같으면 다 같은 소리로 들린다.
///
/// 세어 봤더니 473군데 중 **63%가 w900**이었다. 전부가 최대 굵기면 강조는 없는 것과 같다.
/// `theme.textTheme`의 역할이 이미 굵기를 정해 두므로, 역할을 쓰면 이 사다리는 자동으로 지켜진다.
/// 굵기를 직접 적어야 할 때만 여기서 고를 것.
abstract final class SetflowWeight {
  /// 화면에서 가장 큰 숫자에만 — 볼륨·1RM·타이머.
  static const display = FontWeight.w900;

  /// 제목·강조. 프리텐다드 한글은 Bold(700)에서 가장 또렷하다 — 800은 뭉갠다.
  static const strong = FontWeight.w700;

  /// 본문 안의 강조, 라벨.
  static const medium = FontWeight.w600;

  /// 본문.
  static const regular = FontWeight.w400;
}

abstract final class SetflowSpacing {
  static const xxs = 2.0;
  static const xs = 4.0;
  static const xs2 = 6.0;
  static const sm = 8.0;
  static const sm2 = 10.0;
  static const md = 12.0;
  static const md2 = 14.0;
  static const lg = 16.0;

  /// 페이지의 좌우 여백. 앱에서 가장 많이 쓰이는 값이라 이름을 갖는다.
  static const gutter = 18.0;

  static const xl = 20.0;
  static const xxl = 24.0;
  static const xxl2 = 28.0;
  static const section = 32.0;
  static const huge = 40.0;
  static const page = 48.0;
}

/// 페이지의 테두리 여백. **좌우는 전부 `gutter`(18)로 같다** — 화면마다 다르면
/// 탭을 옮길 때 본문이 좌우로 흔들린다.
///
/// 세어 봤을 때 회원 쪽은 18, 트레이너·온보딩 쪽은 24, 일부는 16이었다. 작성자별로 갈린
/// 것이지 화면의 성격 때문이 아니었다. 세트 행에 숫자 상자가 셋 들어가는 이 앱에서는
/// 좁은 쪽이 맞아서 18로 모았다.
abstract final class SetflowInsets {
  static const _side = SetflowSpacing.gutter;

  static const pageList = EdgeInsets.fromLTRB(_side, 6, _side, 28);
  static const pageListTight = EdgeInsets.fromLTRB(_side, 4, _side, 28);
  static const pageHeader = EdgeInsets.fromLTRB(_side, 4, _side, 12);
  static const pageForm = EdgeInsets.fromLTRB(_side, 12, _side, 28);
  static const bottomAction = EdgeInsets.fromLTRB(_side, 10, _side, 16);
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
