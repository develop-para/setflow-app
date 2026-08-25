import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'theme/tokens.dart';

export 'theme/tokens.dart';

abstract final class SetflowTheme {
  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final semantic = isDark
        ? SetflowSemanticColors.dark
        : SetflowSemanticColors.light;
    final surface = isDark ? const Color(0xFF0B0B0B) : SetflowColors.surface;
    final onSurface = isDark ? const Color(0xFFF4F4F4) : SetflowColors.ink;
    final outline = isDark ? const Color(0xFF2A2A2A) : SetflowColors.divider;

    // The brand does not invert. Lime is bright enough to sit on either
    // surface, and a brand that changes colour with the theme is not a brand.
    // What must never change is the foreground: ink on lime is 16:1, white on
    // lime is 1.18:1 and disappears.
    const accent = SetflowColors.brand;
    const onAccent = SetflowColors.onBrand;

    final scheme =
        ColorScheme.fromSeed(
          seedColor: SetflowColors.primary,
          brightness: brightness,
        ).copyWith(
          primary: accent,
          onPrimary: onAccent,
          // The container behind a primary action belongs to the brand, not to
          // the grey ramp. A neutral container made every "primary" surface
          // look like every other surface.
          primaryContainer: isDark
              ? const Color(0xFF232A05)
              : SetflowColors.brandSoft,
          onPrimaryContainer: isDark
              ? const Color(0xFFE9F5B8)
              : SetflowColors.ink,
          // Secondary is the brand where it has to be read. It used to be teal,
          // which meant the app's second-most-used accent had nothing to do
          // with the brand.
          secondary: isDark ? const Color(0xFFBFD53A) : SetflowColors.brandDeep,
          onSecondary: isDark ? SetflowColors.onBrand : Colors.white,
          surface: surface,
          surfaceContainerLow: semantic.surfaceContainerLow,
          surfaceContainer: semantic.surfaceContainer,
          surfaceContainerHigh: semantic.surfaceContainerHigh,
          onSurface: onSurface,
          onSurfaceVariant: isDark
              // Was a warm grey left over from the old stone ramp, sitting on a
              // neutral dark surface. Neutral now, like everything else.
              ? const Color(0xFFA3A3A3)
              : SetflowColors.secondaryText,
          outline: outline,
          outlineVariant: isDark
              ? const Color(0xFF1F1F1F)
              : const Color(0xFFEDEDED),
          // The scheme's error has to follow the theme like every other state
          // colour. It was pinned to the light-only constant, so dark surfaces
          // drew errors in a red that does not read there.
          error: semantic.error,
          onError: isDark ? SetflowColors.onBrand : Colors.white,
        );

    final textTheme = _textTheme(onSurface);
    final radius16 = BorderRadius.circular(SetflowRadii.md);
    final radius20 = BorderRadius.circular(SetflowRadii.lg);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: 'Pretendard',
      colorScheme: scheme,
      scaffoldBackgroundColor: surface,
      canvasColor: surface,
      textTheme: textTheme,
      extensions: [semantic],
      dividerColor: outline,
      disabledColor: semantic.disabled,
      splashColor: scheme.primary.withValues(alpha: .12),
      highlightColor: scheme.primary.withValues(alpha: .06),
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: textTheme.headlineLarge,
        // 24px 제목에 64px 바는 제목 위아래로 공기가 20px씩이었다 — 화면마다
        // "헤더 여백이 크다"로 읽힌 주범. 52면 위아래 14px로 여전히 넉넉하다.
        toolbarHeight: 52,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: semantic.surfaceContainer,
        hintStyle: textTheme.bodyLarge?.copyWith(color: semantic.disabled),
        labelStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        errorStyle: textTheme.labelMedium?.copyWith(color: scheme.error),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: SetflowSpacing.lg,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: radius16,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: radius16,
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: radius16,
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: radius16,
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: radius16,
          borderSide: BorderSide(color: scheme.error, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          disabledBackgroundColor: semantic.surfaceContainerHigh,
          disabledForegroundColor: semantic.disabled,
          minimumSize: const Size(48, 56),
          padding: const EdgeInsets.symmetric(horizontal: SetflowSpacing.xl),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SetflowRadii.sm),
          ),
          textStyle: textTheme.labelLarge?.copyWith(
            fontSize: 15,
            fontWeight: FontWeight.w900,
            letterSpacing: .2,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.onSurface,
          minimumSize: const Size(48, 44),
          padding: const EdgeInsets.symmetric(horizontal: SetflowSpacing.md),
          shape: RoundedRectangleBorder(borderRadius: radius16),
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: onSurface,
          minimumSize: const Size(48, 56),
          side: BorderSide(
            color: isDark ? const Color(0xFF3A3D44) : SetflowColors.ink,
            width: 1.5,
          ),
          padding: const EdgeInsets.symmetric(horizontal: SetflowSpacing.xl),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SetflowRadii.sm),
          ),
          textStyle: textTheme.labelLarge?.copyWith(
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      cardTheme: CardThemeData(
        color: semantic.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: radius20,
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      chipTheme: ChipThemeData(
        // M3는 칩의 앞 아이콘을 primary로 칠한다 — 우리 primary는 라임이라
        // 밝은 칩 위에서 사라진다(1.2:1). 아이콘도 글자와 같은 색으로 간다.
        iconTheme: IconThemeData(color: scheme.onSurfaceVariant, size: 18),
        backgroundColor: semantic.surfaceContainerLow,
        selectedColor: scheme.primaryContainer,
        disabledColor: semantic.surfaceContainerHigh,
        labelStyle: textTheme.labelMedium,
        secondaryLabelStyle: textTheme.labelMedium?.copyWith(
          color: scheme.onPrimaryContainer,
        ),
        side: BorderSide(color: scheme.outlineVariant),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: SetflowSpacing.sm),
      ),
      listTileTheme: ListTileThemeData(
        minTileHeight: 56,
        iconColor: scheme.onSurfaceVariant,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: SetflowSpacing.lg,
        ),
        shape: RoundedRectangleBorder(borderRadius: radius16),
        titleTextStyle: textTheme.bodyLarge?.copyWith(
          fontWeight: FontWeight.w700,
        ),
        subtitleTextStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      // Kinetic signature: a solid black bar in BOTH themes with a yellow
      // active pill — the athletic-brand bottom nav (Nike Training / Gymshark).
      navigationBarTheme: NavigationBarThemeData(
        height: 66,
        backgroundColor: SetflowColors.inkBlock,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primary,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SetflowRadii.sm),
        ),
        elevation: 0,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return textTheme.labelSmall?.copyWith(
            color: selected ? Colors.white : Colors.white54,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
            letterSpacing: .2,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          return IconThemeData(
            size: 24,
            color: states.contains(WidgetState.selected)
                ? SetflowColors.ink
                : Colors.white60,
          );
        }),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: semantic.surfaceContainerLow,
        modalBackgroundColor: semantic.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        elevation: 16,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(SetflowRadii.xl),
          ),
        ),
      ),
      // Every dialog in the app is a plain AlertDialog with no styling of its
      // own, so this is the only place their type and spacing are decided.
      // Without the text styles they fell back to Material's headline scale,
      // which is a size the rest of the app never uses.
      dialogTheme: DialogThemeData(
        backgroundColor: semantic.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        elevation: 16,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SetflowRadii.xl),
        ),
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontSize: 18,
          height: 1.4,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.2,
          color: onSurface,
        ),
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          height: 1.65,
          color: isDark ? const Color(0xFF9C968C) : SetflowColors.secondaryText,
        ),
        // A question is not a decoration: the icon slot centres the title in
        // Material 3, which is why the seven dialogs that used it read as a
        // different component from the other thirty-one.
        iconColor: isDark
            ? const Color(0xFF9C968C)
            : SetflowColors.secondaryText,
        actionsPadding: const EdgeInsets.fromLTRB(
          SetflowSpacing.lg,
          SetflowSpacing.sm,
          SetflowSpacing.lg,
          SetflowSpacing.lg,
        ),
        // Phones are 360 wide too; the default inset leaves a dialog almost
        // edge to edge there.
        insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? const Color(0xFFF7F7F7) : SetflowColors.ink,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: isDark ? SetflowColors.ink : Colors.white,
        ),
        actionTextColor: scheme.primary,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SetflowRadii.sm),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        space: 1,
        thickness: 1,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: semantic.surfaceContainerHigh,
        circularTrackColor: semantic.surfaceContainerHigh,
      ),
      // Branded styles for stock widgets so nothing renders with raw
      // Material defaults ("system design").
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SetflowRadii.xs),
        ),
        side: BorderSide(color: scheme.outline, width: 1.6),
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? semantic.teal
              : Colors.transparent,
        ),
        checkColor: const WidgetStatePropertyAll(Colors.white),
        splashRadius: 18,
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.outline,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.primary
              : semantic.surfaceContainerHigh,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: scheme.primary,
        inactiveTrackColor: semantic.surfaceContainerHigh,
        thumbColor: scheme.primary,
        overlayColor: scheme.primary.withValues(alpha: .12),
        trackHeight: 6,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
        valueIndicatorColor: isDark
            ? const Color(0xFFF7F7F7)
            : SetflowColors.ink,
        valueIndicatorTextStyle: textTheme.labelMedium?.copyWith(
          color: isDark ? SetflowColors.ink : Colors.white,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: semantic.surfaceContainer,
          foregroundColor: scheme.onSurfaceVariant,
          selectedBackgroundColor: scheme.primary,
          selectedForegroundColor: scheme.onPrimary,
          side: BorderSide.none,
          shape: RoundedRectangleBorder(borderRadius: radius16),
          textStyle: textTheme.labelLarge,
          padding: const EdgeInsets.symmetric(
            horizontal: SetflowSpacing.lg,
            vertical: SetflowSpacing.md,
          ),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: scheme.onSurface,
        unselectedLabelColor: scheme.onSurfaceVariant,
        labelStyle: textTheme.labelLarge?.copyWith(),
        unselectedLabelStyle: textTheme.labelLarge,
        indicatorColor: scheme.primary,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: Colors.transparent,
        overlayColor: WidgetStatePropertyAll(
          scheme.primary.withValues(alpha: .08),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: semantic.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        elevation: 12,
        shadowColor: const Color(0x33000000),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SetflowRadii.md),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        textStyle: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 500),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFFF7F7F7) : SetflowColors.ink,
          borderRadius: BorderRadius.circular(SetflowRadii.sm),
        ),
        textStyle: textTheme.labelMedium?.copyWith(
          color: isDark ? SetflowColors.ink : Colors.white,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: SetflowSpacing.md,
          vertical: SetflowSpacing.sm,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 4,
        highlightElevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SetflowRadii.lg),
        ),
      ),
    );
  }

  static TextTheme _textTheme(Color color) {
    TextStyle style(
      double size,
      FontWeight weight,
      double height, {
      double letterSpacing = 0,
      bool tabular = false,
    }) => TextStyle(
      fontFamily: 'Pretendard',
      color: color,
      fontSize: size,
      fontWeight: weight,
      height: height,
      letterSpacing: letterSpacing,
      fontFeatures: tabular ? const [FontFeature.tabularFigures()] : null,
    );

    return TextTheme(
      // Kinetic type scale — big confident numerals are the signature, with a
      // sharp jump down to editorial labels. Displays run heavy, tight, and
      // tabular so counters don't jitter; labels are the small-caps kickers.
      displayLarge: style(
        52,
        FontWeight.w900,
        1.02,
        letterSpacing: -2,
        tabular: true,
      ),
      displayMedium: style(
        38,
        FontWeight.w900,
        1.05,
        letterSpacing: -1.2,
        tabular: true,
      ),
      displaySmall: style(
        28,
        FontWeight.w900,
        1.1,
        letterSpacing: -.6,
        tabular: true,
      ),
      headlineLarge: style(
        24,
        FontWeight.w800,
        1.18,
        letterSpacing: -.4,
        tabular: true,
      ),
      headlineMedium: style(
        20,
        FontWeight.w800,
        1.25,
        letterSpacing: -.2,
        tabular: true,
      ),
      titleLarge: style(18, FontWeight.w800, 1.3, letterSpacing: -.2),
      titleMedium: style(16, FontWeight.w700, 1.4),
      bodyLarge: style(15, FontWeight.w500, 1.5),
      bodyMedium: style(14, FontWeight.w500, 1.5),
      labelLarge: style(13.5, FontWeight.w800, 1.2, letterSpacing: .2),
      labelMedium: style(12, FontWeight.w700, 1.3, letterSpacing: .4),
      labelSmall: style(11, FontWeight.w800, 1.2, letterSpacing: 1.0),
      bodySmall: style(11.5, FontWeight.w500, 1.35),
    );
  }
}
