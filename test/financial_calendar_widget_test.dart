import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ngoen_ku_pai_nai/domain/models/scheduled_financial_event.dart';
import 'package:ngoen_ku_pai_nai/ui/app_state.dart';
import 'package:ngoen_ku_pai_nai/ui/finance_app.dart';
import 'package:ngoen_ku_pai_nai/ui/local_finance_store.dart';

void main() {
  testWidgets('calendar fits a small screen with large Thai text scaling', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = LocalFinanceStore.memory();
    final account = await store.repository.createAccount(
      name: 'บัญชีเงินเดือนและค่าใช้จ่ายประจำเดือน',
      type: 'bank',
      openingBalanceSatang: 123456789,
    );
    final destination = await store.repository.createAccount(
      name: 'บัญชีสำรอง',
      type: 'bank',
      openingBalanceSatang: 0,
    );
    final expense = await store.repository.createCategory(
      name: 'ค่าใช้จ่ายด้านสุขภาพและการรักษาพยาบาล',
      type: 'expense',
      iconKey: 'health',
    );
    final income = await store.repository.createCategory(
      name: 'รายรับประจำเดือน',
      type: 'income',
      iconKey: 'income',
    );
    final now = DateTime.now();
    await store.repository.createScheduledEvent(
      eventType: ScheduledEventType.expense,
      amountSatang: 242000,
      title: 'ค่าใช้จ่ายด้านสุขภาพและการรักษาพยาบาล',
      accountId: account,
      categoryId: expense,
      scheduledAt: now.toUtc(),
    );
    await store.repository.createScheduledEvent(
      eventType: ScheduledEventType.income,
      amountSatang: 43900,
      title: 'รายรับประจำเดือน',
      accountId: account,
      categoryId: income,
      scheduledAt: now.toUtc(),
    );
    await store.repository.createScheduledEvent(
      eventType: ScheduledEventType.transfer,
      amountSatang: 123456789,
      title: 'โอนระหว่างบัญชี',
      accountId: account,
      destinationAccountId: destination,
      scheduledAt: now.toUtc(),
    );
    final state = AppState(store: store);
    await state.initialize();
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
        child: FinanceApp(state: state),
      ),
    );
    state.go(AppStep.calendar);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('calendar-month-title')), findsOneWidget);
  });
  testWidgets('calendar renders month, balances and empty states', (
    tester,
  ) async {
    final state = AppState(store: LocalFinanceStore.memory());
    await tester.pumpWidget(FinanceApp(state: state));
    await tester.pumpAndSettle();
    state.go(AppStep.calendar);
    await tester.pumpAndSettle();

    expect(find.text('ปฏิทินการเงิน'), findsOneWidget);
    expect(find.byKey(const Key('calendar-month-title')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('เงินจริงตอนนี้'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('เงินจริงตอนนี้'), findsOneWidget);
    expect(find.text('คาดการณ์ ณ วันที่เลือก'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('empty-day')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('empty-day')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('empty-month')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('empty-month')), findsOneWidget);
  });

  testWidgets('due activity exposes label and explicit confirmation action', (
    tester,
  ) async {
    final store = LocalFinanceStore.memory();
    final account = await store.repository.createAccount(
      name: 'SCB',
      type: 'bank',
      openingBalanceSatang: 1000000,
    );
    final category = await store.repository.createCategory(
      name: 'สุขภาพ',
      type: 'expense',
      iconKey: 'health',
    );
    final now = DateTime.now();
    await store.repository.createScheduledEvent(
      eventType: ScheduledEventType.expense,
      amountSatang: 150000,
      title: 'ทำฟัน',
      accountId: account,
      categoryId: category,
      scheduledAt: DateTime(now.year, now.month, 1).toUtc(),
    );
    final state = AppState(store: store);
    await tester.pumpWidget(FinanceApp(state: state));
    await tester.pumpAndSettle();
    state.go(AppStep.calendar);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('calendar-day-1')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('ทำฟัน'),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('ทำฟัน'), findsOneWidget);
    expect(find.byKey(const Key('due-label')), findsOneWidget);
    expect(find.text('ยืนยันการจ่าย'), findsOneWidget);
    expect(await store.repository.ledgerTransactionCount(), 0);
  });
}
