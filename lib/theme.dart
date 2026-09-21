import 'package:flutter/material.dart';

abstract final class AppColors {
  static const ink = Color(0xFF12100E);
  static const wood = Color(0xFF1C1814);
  static const panel = Color(0xFF2A241F);
  static const paper = Color(0xFFF4EFE6);
  static const muted = Color(0xFFB9A992);
  static const stamp = Color(0xFFC23A2B);
  static const stampDark = Color(0xFF9C2E22);
}

ThemeData buildAppTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.stamp,
      brightness: Brightness.dark,
      surface: AppColors.wood,
    ),
    scaffoldBackgroundColor: AppColors.ink,
    fontFamily: 'sans-serif',
  );

  return base.copyWith(
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.wood,
      foregroundColor: AppColors.paper,
      elevation: 0,
      centerTitle: false,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.panel,
      hintStyle: const TextStyle(color: AppColors.muted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.panel,
      contentTextStyle: const TextStyle(color: AppColors.paper),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.wood,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  );
}
