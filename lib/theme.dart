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
    final surface = isDark ? const Color(0xFF181719) : SetflowColors.surface;
    final onSurface = isDark ? const Color(0xFFF7F7F7) : SetflowColors.ink;
    final outline = isDark ? const Color(0xFF343236) : SetflowColors.divider;

    final scheme =
        ColorScheme.fromSeed(
          seedColor: SetflowColors.primary,
          brightness: brightness,
        ).copyWith(
          primary: isDark ? const Color(0xFFFFD53D) : SetflowColors.primary,
          onPrimary: SetflowColors.ink,
          primaryContainer: isDark
              ? const Color(0xFF4A3B00)
              : const Color(0xFFFFF1BE),
          onPrimaryContainer: isDark
              ? const Color(0xFFFFE9A0)
              : const Color(0xFF4A3B00),
          secondary: semantic.teal,
          onSecondary: SetflowColors.ink,
          surface: surface,
          surfaceContainerLow: semantic.surfaceContainerLow,
          surfaceContainer: semantic.surfaceContainer,
          surfaceContainerHigh: semantic.surfaceContainerHigh,
          onSurface: onSurface,
          onSurfaceVariant: isDark
              ? const Color(0xFFA1A1AA)
              : SetflowColors.secondaryText,
          outline: outline,
          outlineVariant: isDark
              ? const Color(0xFF2A282C)
              : const Color(0xFFEEF0F2),
          error: SetflowColors.red,
          onError: Colors.white,
        );

    final textTheme = _textTheme(onSurface);
    final radius16 = BorderRadius.circular(SetflowRadii.md);
    final radius20 = BorderRadius.circular(SetflowRadii.lg);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
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
        titleTextStyle: textTheme.headlineMedium,
        toolbarHeight: 60,
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
          minimumSize: const Size(48, 52),
          padding: const EdgeInsets.symmetric(horizontal: SetflowSpacing.xl),
          shape: RoundedRectangleBorder(borderRadius: radius16),
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w800,
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
          minimumSize: const Size(48, 52),
          side: BorderSide(color: scheme.outline),
          padding: const EdgeInsets.symmetric(horizontal: SetflowSpacing.xl),
          shape: RoundedRectangleBorder(borderRadius: radius16),
          textStyle: textTheme.labelLarge,
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
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        backgroundColor: semantic.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primaryContainer,
        elevation: 0,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStatePropertyAll(textTheme.labelMedium),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          return IconThemeData(
            color: states.contains(WidgetState.selected)
                ? scheme.onPrimaryContainer
                : scheme.onSurfaceVariant,
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
    );
  }

  static TextTheme _textTheme(Color color) {
    TextStyle style(double size, FontWeight weight, double height) => TextStyle(
      color: color,
      fontSize: size,
      fontWeight: weight,
      height: height,
      letterSpacing: 0,
    );

    return TextTheme(
      displayLarge: style(32, FontWeight.w900, 1.15),
      displayMedium: style(28, FontWeight.w800, 1.2),
      headlineLarge: style(24, FontWeight.w800, 1.25),
      headlineMedium: style(20, FontWeight.w800, 1.3),
      titleLarge: style(18, FontWeight.w700, 1.3),
      titleMedium: style(16, FontWeight.w700, 1.4),
      bodyLarge: style(15, FontWeight.w500, 1.5),
      bodyMedium: style(14, FontWeight.w500, 1.5),
      labelLarge: style(14, FontWeight.w700, 1.2),
      labelMedium: style(12, FontWeight.w600, 1.3),
      bodySmall: style(11, FontWeight.w500, 1.3),
    );
  }
}
