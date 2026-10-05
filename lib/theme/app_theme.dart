import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Central place for all colors, text styles, and the app's ThemeData.
/// Palette: "Emerald & Electric"
class AppColors {
  static const primary = Color(0xFF22C55E);
  static const primaryDark = Color(0xFF16A34A);
  static const secondary = Color(0xFF2563EB);
  static const background = Color(0xFFF8FAFC);
  static const card = Color(0xFFFFFFFF);
  static const text = Color(0xFF1E293B);
  static const textMuted = Color(0xFF64748B);
  static const success = Color(0xFF16A34A);
  static const warning = Color(0xFFF59E0B);
  static const error = Color(0xFFEF4444);
  static const border = Color(0xFFE2E8F0);
}

class AppTextStyles {
  // Display font (Sora) — used for headings, titles, buttons
  static TextStyle display({
    double size = 20,
    FontWeight weight = FontWeight.w700,
    Color color = AppColors.text,
  }) {
    return GoogleFonts.sora(
      fontSize: size,
      fontWeight: weight,
      color: color,
    );
  }

  // Body font (Inter) — used for regular text, labels
  static TextStyle body({
    double size = 14,
    FontWeight weight = FontWeight.w400,
    Color color = AppColors.text,
  }) {
    return GoogleFonts.inter(
      fontSize: size,
      fontWeight: weight,
      color: color,
    );
  }
}

class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        primary: AppColors.primary,
        secondary: AppColors.secondary,
        surface: AppColors.card,
        error: AppColors.error,
      ),
      textTheme: TextTheme(
        headlineMedium: AppTextStyles.display(size: 24, weight: FontWeight.w800),
        titleLarge: AppTextStyles.display(size: 18, weight: FontWeight.w800),
        titleMedium: AppTextStyles.display(size: 15, weight: FontWeight.w700),
        bodyLarge: AppTextStyles.body(size: 14),
        bodyMedium: AppTextStyles.body(size: 13),
        bodySmall: AppTextStyles.body(size: 12, color: AppColors.textMuted),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: AppTextStyles.display(size: 15, weight: FontWeight.w700, color: Colors.white),
          elevation: 0,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.background,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.text),
        titleTextStyle: AppTextStyles.display(size: 17, weight: FontWeight.w800),
      ),
    );
  }
}