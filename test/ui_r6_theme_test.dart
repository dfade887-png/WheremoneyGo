import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ngoen_ku_pai_nai/domain/spending_gauge.dart';
import 'package:ngoen_ku_pai_nai/ui/theme/app_theme.dart';

void main() {
  group('UI-R6 visual tokens', () {
    test('light, dark, and system-safe theme data render', () {
      final light = AppTheme.lightFor(AppAccent.blue);
      final dark = AppTheme.darkFor(AppAccent.blue);

      expect(light.brightness, Brightness.light);
      expect(dark.brightness, Brightness.dark);
      expect(light.colorScheme.primary, isNot(Colors.transparent));
      expect(dark.colorScheme.primary, isNot(Colors.transparent));
      expect(ThemeMode.system, isNotNull);
    });

    test('each accent changes primary UI color', () {
      final colors = AppAccent.values
          .map((accent) => AppTheme.lightFor(accent).colorScheme.primary)
          .toSet();

      expect(colors.length, AppAccent.values.length);
    });

    test('theme accent never changes financial warning colors', () {
      final pink = AppTheme.lightFor(AppAccent.pink).colorScheme.primary;
      final orange = AppTheme.lightFor(AppAccent.orange).colorScheme.primary;

      expect(pink, isNot(FinancialColors.warning));
      expect(orange, isNot(FinancialColors.warning));
      expect(FinancialColors.warning, const Color(0xFFE5A50A));
      expect(FinancialColors.overBudget, const Color(0xFFD92D3A));
    });

    test('financial transaction semantics have distinct token families', () {
      expect(FinancialColors.income, isNot(FinancialColors.expense));
      expect(FinancialColors.refund, isNot(FinancialColors.transfer));
      expect(FinancialColors.transfer, isNot(FinancialColors.expense));
    });

    test('category fallback is deterministic and honors custom color', () {
      final first = CategoryAccentPalette.resolve(stableKey: 'food-id');
      final second = CategoryAccentPalette.resolve(stableKey: 'food-id');
      const custom = Color(0xFF123456);

      expect(first, second);
      expect(
        CategoryAccentPalette.resolve(
          stableKey: 'food-id',
          storedValue: custom.toARGB32(),
        ),
        custom,
      );
    });

    test('different category keys can resolve to different accents', () {
      final colors = <Color>{
        CategoryAccentPalette.resolve(stableKey: 'food'),
        CategoryAccentPalette.resolve(stableKey: 'transport'),
        CategoryAccentPalette.resolve(stableKey: 'health'),
      };
      expect(colors.length, greaterThan(1));
    });

    test('budget state thresholds preserve financial meaning', () {
      SpendingGauge gauge(double ratio) => SpendingGauge(
        categoryId: 'cat',
        name: 'งบทดสอบ',
        usedSatang: (ratio * 10000).round(),
        budgetSatang: 10000,
      );

      expect(gauge(.69).state, SpendingGaugeState.safe);
      expect(gauge(.70).state, SpendingGaugeState.warning);
      expect(gauge(.90).state, SpendingGaugeState.critical);
      expect(gauge(1.00).state, SpendingGaugeState.over);
    });
  });

  testWidgets('dark theme keeps long Thai currency text readable', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightFor(AppAccent.purple),
        darkTheme: AppTheme.darkFor(AppAccent.purple),
        themeMode: ThemeMode.dark,
        home: const Scaffold(
          body: Padding(
            padding: EdgeInsets.all(16),
            child: Text('เงินใช้ได้วันนี้ ฿123,456,789.00 — สถานะงบ: ใกล้เต็ม'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('เงินใช้ได้วันนี้'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
