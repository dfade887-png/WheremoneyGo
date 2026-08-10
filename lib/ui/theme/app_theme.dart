import 'package:flutter/material.dart';

abstract final class AppColors {
  static const ink = Color(0xFF07131D);
  static const paper = Color(0xFFF4F6F4);
  static const mint = Color(0xFFBAFF63);
  static const mintSoft = Color(0xFFDFFFC0);
  static const line = Color(0xFFD8DDD8);
  static const muted = Color(0xFF66726D);
  static const orange = Color(0xFFFF9F43);
  static const red = Color(0xFFED574F);
  static const blue = Color(0xFF4B8BDB);
  static const violet = Color(0xFF7C6CD1);
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
        borderSide: const BorderSide(color: AppColors.ink, width: 2),
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
