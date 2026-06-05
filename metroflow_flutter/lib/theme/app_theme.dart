import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const Color primary = Color(0xFF2563EB);
  static const Color primaryLight = Color(0xFF3B82F6);
  static const Color primaryDark = Color(0xFF1D4ED8);
  static const Color primaryBg = Color(0xFFEFF6FF);

  static const Color success = Color(0xFF10B981);
  static const Color successBg = Color(0xFFD1FAE5);

  static const Color warning = Color(0xFFF59E0B);
  static const Color warningBg = Color(0xFFFEF3C7);

  static const Color error = Color(0xFFEF4444);
  static const Color errorBg = Color(0xFFFEE2E2);
}

class ThemeColors {
  final Color primary;
  final Color primaryLight;
  final Color primaryDark;
  final Color primaryBg;
  final Color success;
  final Color successBg;
  final Color warning;
  final Color warningBg;
  final Color error;
  final Color errorBg;
  final Color background;
  final Color surface;
  final Color surfaceVariant;
  final Color text;
  final Color textSecondary;
  final Color border;
  final Color borderVariant;

  ThemeColors({
    required this.primary,
    required this.primaryLight,
    required this.primaryDark,
    required this.primaryBg,
    required this.success,
    required this.successBg,
    required this.warning,
    required this.warningBg,
    required this.error,
    required this.errorBg,
    required this.background,
    required this.surface,
    required this.surfaceVariant,
    required this.text,
    required this.textSecondary,
    required this.border,
    required this.borderVariant,
  });
}

class AppTheme {
  static final lightColors = ThemeColors(
    primary: AppColors.primary,
    primaryLight: AppColors.primaryLight,
    primaryDark: AppColors.primaryDark,
    primaryBg: AppColors.primaryBg,
    success: AppColors.success,
    successBg: AppColors.successBg,
    warning: AppColors.warning,
    warningBg: AppColors.warningBg,
    error: AppColors.error,
    errorBg: AppColors.errorBg,
    background: const Color(0xFFF8FAFC),
    surface: Colors.white,
    surfaceVariant: const Color(0xFFF1F5F9),
    text: const Color(0xFF0F172A),
    textSecondary: const Color(0xFF64748B),
    border: const Color(0xFFE2E8F0),
    borderVariant: const Color(0xFFCBD5E1),
  );

  static final darkColors = ThemeColors(
    primary: AppColors.primary,
    primaryLight: AppColors.primaryLight,
    primaryDark: AppColors.primaryDark,
    primaryBg: AppColors.primaryBg,
    success: AppColors.success,
    successBg: AppColors.successBg,
    warning: AppColors.warning,
    warningBg: AppColors.warningBg,
    error: AppColors.error,
    errorBg: AppColors.errorBg,
    background: const Color(0xFF020617),
    surface: const Color(0xFF0F172A),
    surfaceVariant: const Color(0xFF1E293B),
    text: const Color(0xFFF8FAFC),
    textSecondary: const Color(0xFF94A3B8),
    border: const Color(0xFF1E293B),
    borderVariant: const Color(0xFF334155),
  );

  static ThemeMode _themeMode = ThemeMode.light;

  static void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
  }

  static ThemeColors get colors =>
      _themeMode == ThemeMode.light ? lightColors : darkColors;

  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
    ),
    scaffoldBackgroundColor: lightColors.background,
    cardColor: lightColors.surface,
    dividerColor: lightColors.border,
    textTheme: GoogleFonts.poppinsTextTheme(
      TextTheme(
        displayLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: lightColors.text),
        displayMedium: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: lightColors.text),
        displaySmall: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: lightColors.text),
        headlineMedium: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: lightColors.text),
        headlineSmall: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: lightColors.text),
        titleLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: lightColors.text),
        bodyLarge: TextStyle(fontSize: 16, color: lightColors.text),
        bodyMedium: TextStyle(fontSize: 14, color: lightColors.text),
        bodySmall: TextStyle(fontSize: 12, color: lightColors.textSecondary),
        labelSmall: TextStyle(fontSize: 12, color: lightColors.textSecondary),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: AppColors.primary,
      contentTextStyle: TextStyle(color: Colors.white),
      actionTextColor: Colors.white,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: lightColors.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: lightColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: lightColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: lightColors.error),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
  );

  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.dark,
    ),
    scaffoldBackgroundColor: darkColors.background,
    cardColor: darkColors.surface,
    dividerColor: darkColors.border,
    textTheme: GoogleFonts.poppinsTextTheme(
      TextTheme(
        displayLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: darkColors.text),
        displayMedium: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: darkColors.text),
        displaySmall: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: darkColors.text),
        headlineMedium: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: darkColors.text),
        headlineSmall: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: darkColors.text),
        titleLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: darkColors.text),
        bodyLarge: TextStyle(fontSize: 16, color: darkColors.text),
        bodyMedium: TextStyle(fontSize: 14, color: darkColors.text),
        bodySmall: TextStyle(fontSize: 12, color: darkColors.textSecondary),
        labelSmall: TextStyle(fontSize: 12, color: darkColors.textSecondary),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: AppColors.primary,
      contentTextStyle: TextStyle(color: Colors.white),
      actionTextColor: Colors.white,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: darkColors.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: darkColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: darkColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: darkColors.error),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
  );
}
