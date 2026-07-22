import 'package:flutter/material.dart';

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
}

abstract final class SetflowTheme {
  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: SetflowColors.primary,
      brightness: brightness,
      primary: SetflowColors.primary,
      onPrimary: SetflowColors.ink,
      surface: dark ? const Color(0xFF181719) : SetflowColors.surface,
      onSurface: dark ? const Color(0xFFF7F7F7) : SetflowColors.ink,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: dark
          ? const Color(0xFF181719)
          : SetflowColors.surface,
      fontFamily: 'sans-serif',
      textTheme: ThemeData(brightness: brightness).textTheme.apply(
        bodyColor: scheme.onSurface,
        displayColor: scheme.onSurface,
      ),
      dividerColor: dark ? const Color(0xFF343236) : SetflowColors.divider,
      splashColor: SetflowColors.primary.withValues(alpha: .12),
      highlightColor: SetflowColors.primary.withValues(alpha: .06),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w900,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? const Color(0xFF29272B) : SetflowColors.elevated,
        hintStyle: const TextStyle(color: SetflowColors.disabled),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: SetflowColors.primary, width: 2),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: dark ? Colors.white : SetflowColors.ink,
        contentTextStyle: TextStyle(
          color: dark ? SetflowColors.ink : Colors.white,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}
