import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ngoen_ku_pai_nai/ui/app_state.dart';
import 'package:ngoen_ku_pai_nai/ui/finance_app.dart';
import 'package:ngoen_ku_pai_nai/ui/local_finance_store.dart';
import 'package:ngoen_ku_pai_nai/ui/theme/app_theme.dart';

void main() {
  Future<({AppState state, List<String> categoryIds})> populatedState() async {
    final store = LocalFinanceStore.memory();
    final account = await store.repository.createAccount(
      name: 'Main',
      type: 'bank',
      openingBalanceSatang: 10000000,
    );
    final ids = <String>[];
    for (final item in <(String, int, int)>[
      ('Over', 100000, 125000),
      ('Critical', 100000, 95000),
      ('Safe', 100000, 30000),
      ('Low', 100000, 10000),
    ]) {
      final category = await store.repository.createCategory(
        name: item.$1,
        type: 'expense',
        iconKey: 'food',
      );
      ids.add(category);
      await store.repository.setCategoryMonthlyBudget(category, item.$2);
      await store.repository.createTransaction(
        accountId: account,
        categoryId: category,
        type: 'expense',
        amountSatang: item.$3,
        occurredAt: DateTime.now(),
      );
    }
    final state = AppState(store: store);
    await state.initialize();
    return (state: state, categoryIds: ids);
  }

  testWidgets(
    'Home keeps the strongest Actual hero and ranks only top 3 gauges',
    (tester) async {
      final fixture = await populatedState();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: DashboardScreen(state: fixture.state),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('เงินจริงที่มี'), findsOneWidget);
      expect(find.text('คาดการณ์สิ้นรอบ'), findsNothing);
      expect(find.byKey(const Key('dashboard-budget-summary')), findsOneWidget);
      expect(
        find.byKey(Key('dashboard-gauge-${fixture.categoryIds[0]}')),
        findsOneWidget,
      );
      expect(
        find.byKey(Key('dashboard-gauge-${fixture.categoryIds[1]}')),
        findsOneWidget,
      );
      expect(
        find.byKey(Key('dashboard-gauge-${fixture.categoryIds[2]}')),
        findsOneWidget,
      );
      expect(
        find.byKey(Key('dashboard-gauge-${fixture.categoryIds[3]}')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Home drill-downs and Quick Add remain reachable', (
    tester,
  ) async {
    final fixture = await populatedState();
    var calendarDestination = -1;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: DashboardScreen(
          state: fixture.state,
          onNavigate: (value) => calendarDestination = value,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('ดูทั้งหมด').first);
    await tester.pumpAndSettle();
    expect(find.text('สถานะงบเดือนนี้'), findsWidgets);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView).first, const Offset(0, -260));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ปฏิทิน'));
    expect(calendarDestination, 1);
    await tester.drag(find.byType(ListView).first, const Offset(0, -360));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dashboard-quick-add')));
    await tester.pumpAndSettle();
    expect(find.text('บันทึกรายการ'), findsOneWidget);
  });

  testWidgets('Home no-budget state is compact and safe', (tester) async {
    final store = LocalFinanceStore.memory();
    await store.repository.createAccount(
      name: 'Main',
      type: 'bank',
      openingBalanceSatang: 100000,
    );
    await store.repository.createCategory(
      name: 'Long Thai category name for budget setup',
      type: 'expense',
      iconKey: 'food',
    );
    final state = AppState(store: store);
    await state.initialize();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: DashboardScreen(state: state),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ยังไม่ได้ตั้งงบรายหมวด'), findsOneWidget);
    expect(find.text('ตั้งงบ'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
