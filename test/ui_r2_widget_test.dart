import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ngoen_ku_pai_nai/ui/app_state.dart';
import 'package:ngoen_ku_pai_nai/ui/local_finance_store.dart';
import 'package:ngoen_ku_pai_nai/ui/production_shell.dart';
import 'package:ngoen_ku_pai_nai/ui/theme/app_theme.dart';

void main() {
  Future<AppState> stateWithMoney() async {
    final store = LocalFinanceStore.memory();
    await store.repository.createAccount(
      name: 'บัญชีหลักที่ชื่อยาวสำหรับหน้าจอแคบ',
      type: 'bank',
      openingBalanceSatang: 123456789,
    );
    final state = AppState(store: store);
    await state.initialize();
    return state;
  }

  testWidgets('UI-R2 dashboard has daily-use hierarchy and bounded sections', (
    tester,
  ) async {
    final state = await stateWithMoney();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: ProductionShell(state: state),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('เงินจริงตอนนี้'), findsOneWidget);
    expect(
      find.byKey(const Key('dashboard-account-distribution')),
      findsOneWidget,
    );
    expect(find.text('คาดการณ์สิ้นรอบ'), findsOneWidget);
    expect(find.byKey(const Key('dashboard-upcoming')), findsOneWidget);
    expect(find.byKey(const Key('dashboard-recent-activity')), findsOneWidget);
    expect(find.text('รายการรอตรวจ 0'), findsNothing);
  });

  testWidgets('UI-R2 bottom navigation reaches all primary destinations', (
    tester,
  ) async {
    final state = await stateWithMoney();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: ProductionShell(state: state),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('หน้าหลัก'), findsOneWidget);
    await tester.tap(find.text('ปฏิทิน'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('calendar-month-title')), findsOneWidget);

    await tester.tap(find.text('รอตรวจ'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('candidate-inbox-empty')), findsOneWidget);

    await tester.tap(find.text('เพิ่มเติม'));
    await tester.pumpAndSettle();
    expect(find.text('การตรวจจับรายการ'), findsOneWidget);

    await tester.tap(find.text('เพิ่ม'));
    await tester.pumpAndSettle();
    expect(find.text('บันทึกรายการ'), findsOneWidget);
    expect(find.byKey(const Key('quick-add-save')), findsOneWidget);
  });

  testWidgets('UI-R2 survives 360x640 at 1.3 text scale', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = await stateWithMoney();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: ProductionShell(state: state),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('เงินจริงตอนนี้'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
