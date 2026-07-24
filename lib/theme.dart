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
    final surface = isDark ? const Color(0xFF100F0D) : SetflowColors.surface;
    final onSurface = isDark ? const Color(0xFFF6F5F2) : SetflowColors.ink;
    final outline = isDark ? const Color(0xFF302C26) : SetflowColors.divider;

    final scheme =
        ColorScheme.fromSeed(
          seedColor: SetflowColors.primary,
          brightness: brightness,
        ).copyWith(
          primary: SetflowColors.primary,
          onPrimary: const Color(0xFF111214),
          primaryContainer: isDark
              ? const Color(0xFF3D3400)
              : const Color(0xFFFFF1BE),
          onPrimaryContainer: isDark
              ? const Color(0xFFFFE566)
              : const Color(0xFF4A3B00),
          secondary: semantic.teal,
          onSecondary: SetflowColors.ink,
          surface: surface,
          surfaceContainerLow: semantic.surfaceContainerLow,
          surfaceContainer: semantic.surfaceContainer,
          surfaceContainerHigh: semantic.surfaceContainerHigh,
          onSurface: onSurface,
          onSurfaceVariant: isDark
              ? const Color(0xFF9C968C)
              : SetflowColors.secondaryText,
          outline: outline,
          outlineVariant: isDark
              ? const Color(0xFF242019)
              : const Color(0xFFEDE9E1),
          error: SetflowColors.red,
          onError: Colors.white,
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
        toolbarHeight: 64,
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
          vertical: 15,
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
          foregroundColor: isDark ? scheme.primary : const Color(0xFF7A5C00),
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
        indicatorColor: SetflowColors.primary,
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
      dialogTheme: DialogThemeData(
        backgroundColor: semantic.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        elevation: 16,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SetflowRadii.xl),
        ),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
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
        valueIndicatorColor: isDark ? const Color(0xFFF7F7F7) : SetflowColors.ink,
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
        labelStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
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
      displayLarge: style(52, FontWeight.w900, 1.02, letterSpacing: -2, tabular: true),
      displayMedium: style(38, FontWeight.w900, 1.05, letterSpacing: -1.2, tabular: true),
      displaySmall: style(28, FontWeight.w900, 1.1, letterSpacing: -.6, tabular: true),
      headlineLarge: style(24, FontWeight.w800, 1.18, letterSpacing: -.4, tabular: true),
      headlineMedium: style(20, FontWeight.w800, 1.25, letterSpacing: -.2, tabular: true),
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
