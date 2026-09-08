import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ngoen_ku_pai_nai/core/money.dart';
import 'package:ngoen_ku_pai_nai/ui/app_state.dart';
import 'package:ngoen_ku_pai_nai/ui/finance_app.dart';
import 'package:ngoen_ku_pai_nai/ui/local_finance_store.dart';
import 'package:ngoen_ku_pai_nai/ui/theme/app_theme.dart';

void main() {
  Future<AppState> stateWithGauge({required bool budgeted}) async {
    final store = LocalFinanceStore.memory();
    final account = await store.repository.createAccount(
      name: 'Test account',
      type: 'bank',
      openingBalanceSatang: 500000,
    );
    final category = await store.repository.createCategory(
      name: budgeted ? 'Food' : 'Transport',
      type: 'expense',
      iconKey: 'food',
    );
    if (budgeted) {
      await store.repository.setCategoryMonthlyBudget(category, 100000);
    }
    final state = AppState(store: store);
    await state.initialize();
    await state.addDailyTransaction(
      accountId: account,
      categoryId: category,
      type: 'expense',
      amount: Money.fromSatang(budgeted ? 125000 : 12000),
      occurredAt: DateTime.now(),
    );
    return state;
  }

  testWidgets('renders an over-budget gauge without overflow', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = await stateWithGauge(budgeted: true);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: DashboardScreen(state: state),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('สถานะงบเดือนนี้'), 180);

    expect(find.text('Food'), findsWidgets);
    expect(find.textContaining('125%'), findsOneWidget);
    expect(find.textContaining('เกินงบ'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders spending with no budget safely', (tester) async {
    final state = await stateWithGauge(budgeted: false);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: DashboardScreen(state: state),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('สถานะงบเดือนนี้'), 180);

    expect(find.text('Transport'), findsWidgets);
    expect(find.textContaining('ยังไม่ได้ตั้งงบ'), findsWidgets);
    expect(find.text('ตั้งงบ'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
