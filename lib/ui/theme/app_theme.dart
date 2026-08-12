import 'package:flutter/material.dart';

abstract final class AppColors {
  // Rose Angel preset — sampled from the user's Remielle references.
  // The copyrighted artwork itself is intentionally not bundled in the APK.
  static const ink = Color(0xFF211723);
  static const paper = Color(0xFFFFF7FA);
  static const mint = Color(0xFFFF8FBE);
  static const mintSoft = Color(0xFFFFD9E8);
  static const line = Color(0xFFE8D6E1);
  static const muted = Color(0xFF776772);
  static const orange = Color(0xFFD59A43);
  static const red = Color(0xFFD94E72);
  static const blue = Color(0xFF8496D8);
  static const violet = Color(0xFFA94BCB);
  static const silver = Color(0xFFDCE2F1);
  static const magenta = Color(0xFFE54BDB);
  static const gold = Color(0xFFC89B45);
}

abstract final class AppTheme {
  static ThemeData get light => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.mint,
      surface: AppColors.paper,
    ),
    scaffoldBackgroundColor: AppColors.paper,
    fontFamily: 'IBM Plex Sans Thai',
    fontFamilyFallback: const ['Noto Sans Thai', 'Tahoma', 'sans-serif'],
    textTheme: const TextTheme(
      displaySmall: TextStyle(
        fontSize: 42,
        height: .98,
        fontWeight: FontWeight.w700,
      ),
      headlineMedium: TextStyle(
        fontSize: 28,
        height: 1.1,
        fontWeight: FontWeight.w700,
      ),
      titleLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
      titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.magenta, width: 2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        backgroundColor: AppColors.mint,
        foregroundColor: AppColors.ink,
        disabledBackgroundColor: AppColors.line,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        foregroundColor: AppColors.ink,
        side: const BorderSide(color: AppColors.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
  );
}
