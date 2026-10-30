import 'package:flutter/material.dart';

/// Eski Kotlin uygulamasının renkleri (çam yeşili + krem zemin).
class AppColors {
  static const emerald = Color(0xFF0E5A4A);
  static const emeraldDark = Color(0xFF074336);
  static const emeraldLight = Color(0xFF166B58);
  static const emeraldContainer = Color(0xFFE2EFEA);
  static const background = Color(0xFFF7FAF8);
  static const white = Color(0xFFFFFFFF);
  static const cardBorder = Color(0xFFE2EBE6);
  static const segmentInactive = Color(0xFFD6E3DE);
  static const textPrimary = Color(0xFF142421);
  static const textSecondary = Color(0xFF5B6E67);
  static const textMuted = Color(0xFF7D918A);
  static const missed = Color(0xFFDC2626);
  static const prayedMint = Color(0xFF86EFAC);
  static const missedCoral = Color(0xFFFCA5A5);
  static const gold = Color(0xFFD97706);
  static const goldContainer = Color(0xFFFEF3C7);
}

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: AppColors.emerald).copyWith(
    primary: AppColors.emerald,
    onPrimary: AppColors.white,
    primaryContainer: AppColors.emeraldContainer,
    onPrimaryContainer: AppColors.emerald,
    secondary: AppColors.gold,
    onSecondary: AppColors.white,
    secondaryContainer: AppColors.goldContainer,
    surface: AppColors.white,
    onSurface: AppColors.textPrimary,
    onSurfaceVariant: AppColors.textSecondary,
    outline: AppColors.cardBorder,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.emerald,
      foregroundColor: AppColors.white,
      elevation: 3,
      surfaceTintColor: Colors.transparent,
    ),
  );
}
