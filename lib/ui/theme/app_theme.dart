import 'package:flutter/material.dart';

enum AppAccent { pink, purple, blue, cyan, green, orange }

extension AppAccentLabel on AppAccent {
  String get label => switch (this) {
    AppAccent.pink => 'Pink',
    AppAccent.purple => 'Purple',
    AppAccent.blue => 'Blue',
    AppAccent.cyan => 'Cyan',
    AppAccent.green => 'Green',
    AppAccent.orange => 'Orange',
  };
}

abstract final class AppColors {
  static const ink = Color(0xFF211723),
      paper = Color(0xFFF6F7F8),
      line = Color(0xFFE1E4E8),
      muted = Color(0xFF65717C);
  static const mint = Color(0xFFFF78AD),
      mintSoft = Color(0xFFFFD9E8),
      orange = Color(0xFFF59E0B),
      red = Color(0xFFE5484D);
  static const blue = Color(0xFF3B82F6),
      violet = Color(0xFF8B5CF6),
      silver = Color(0xFFDCE2F1),
      magenta = Color(0xFFE54BDB),
      gold = Color(0xFFC89B45);
}

abstract final class FinancialColors {
  static const income = Color(0xFF0F9D78),
      expense = Color(0xFFE5484D),
      refund = Color(0xFF14A6A6),
      transfer = Color(0xFF3182CE);
  static const safe = Color(0xFF169C66),
      warning = Color(0xFFE5A50A),
      critical = Color(0xFFF06A22),
      overBudget = Color(0xFFD92D3A);
  static const scheduled = Color(0xFF7067E8),
      pendingReview = Color(0xFFCA8A04),
      confirmed = Color(0xFF4B5563);
}

abstract final class CategoryAccentPalette {
  static const values = <Color>[
    Color(0xFFE95D95),
    Color(0xFFF07818),
    Color(0xFFE5A50A),
    Color(0xFF7AA600),
    Color(0xFF179C67),
    Color(0xFF149B9B),
    Color(0xFF1686C9),
    Color(0xFF4D6FD3),
    Color(0xFF7656C8),
  ];
  static Color resolve({required String stableKey, int? storedValue}) {
    if (storedValue != null) return Color(storedValue);
    var hash = 0;
    for (final unit in stableKey.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return values[hash % values.length];
  }
}

abstract final class AppTheme {
  static Color accent(AppAccent value) => switch (value) {
    AppAccent.pink => const Color(0xFFE85C98),
    AppAccent.purple => const Color(0xFF7A5AF8),
    AppAccent.blue => const Color(0xFF2878D4),
    AppAccent.cyan => const Color(0xFF1498B8),
    AppAccent.green => const Color(0xFF168B59),
    AppAccent.orange => const Color(0xFFE87817),
  };
  static ThemeData lightFor(AppAccent accent) =>
      _build(Brightness.light, accent);
  static ThemeData darkFor(AppAccent accent) => _build(Brightness.dark, accent);
  static ThemeData get light => lightFor(AppAccent.pink);
  static ThemeData _build(Brightness brightness, AppAccent selected) {
    final primary = accent(selected), dark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: brightness,
      surface: dark ? const Color(0xFF1C222B) : AppColors.paper,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: dark ? const Color(0xFF12171E) : AppColors.paper,
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
      cardTheme: CardThemeData(color: scheme.surface, elevation: dark ? 1 : 0),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: primary, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          backgroundColor: primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: scheme.outlineVariant,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          foregroundColor: scheme.onSurface,
          side: BorderSide(color: scheme.outlineVariant),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}
