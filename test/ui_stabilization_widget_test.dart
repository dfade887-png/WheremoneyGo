import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ngoen_ku_pai_nai/core/money.dart';
import 'package:ngoen_ku_pai_nai/ui/app_state.dart';
import 'package:ngoen_ku_pai_nai/ui/daily_driver_screen.dart';
import 'package:ngoen_ku_pai_nai/ui/finance_app.dart';
import 'package:ngoen_ku_pai_nai/ui/local_finance_store.dart';
import 'package:ngoen_ku_pai_nai/ui/theme/app_theme.dart';

void main() {
  Future<AppState> populatedState() async {
    final store = LocalFinanceStore.memory();
    final account = await store.repository.createAccount(
      name: 'บัญชีเงินเดือนและค่าใช้จ่ายประจำเดือน',
      type: 'bank',
      openingBalanceSatang: 123456789,
    );
    final category = await store.repository.createCategory(
      name: 'ค่าใช้จ่ายด้านสุขภาพและการรักษาพยาบาล',
      type: 'expense',
      iconKey: 'health',
    );
    final state = AppState(store: store);
    await state.initialize();
    await state.addDailyTransaction(
      accountId: account,
      categoryId: category,
      type: 'expense',
      amount: const Money.fromSatang(123456789),
      note: 'รายละเอียดภาษาไทยที่ยาวมากเพื่อทดสอบการตัดข้อความ',
    );
    return state;
  }

  testWidgets(
    'production Quick Add shows nearby validation and disabled save',
    (tester) async {
      final state = await populatedState();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(body: DailyQuickAdd(state: state)),
        ),
      );

      expect(find.text('รายจ่าย'), findsOneWidget);
      expect(find.textContaining('บัญชีต้นทาง'), findsWidgets);
      expect(find.textContaining('หมวดหมู่'), findsWidgets);
      final save = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'บันทึก'),
      );
      expect(save.onPressed, isNull);

      await tester.enterText(find.byType(TextField).first, '0');
      await tester.pump();
      expect(find.text('กรุณากรอกจำนวนเงินมากกว่า 0'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'บันทึก'))
            .onPressed,
        isNull,
      );
    },
  );

  testWidgets('accounts and activity fit narrow large-text viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = await populatedState();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: DailyDriverScreen(state: state),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('รายการ').last);
    await tester.pumpAndSettle();
    expect(find.text('ประวัติทั้งหมด'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dashboard fits narrow large-text viewport with large money', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = await populatedState();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: DashboardScreen(state: state),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('เงินจริงที่มี'), findsOneWidget);
    expect(find.text('สถานะงบเดือนนี้'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('candidate inbox is reachable from the user-facing navigation', (
    tester,
  ) async {
    final state = await populatedState();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: DailyDriverScreen(state: state),
      ),
    );
    await tester.tap(find.text('ข้อมูล'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('รายการรอตรวจ'));
    await tester.pumpAndSettle();

    expect(find.text('รายการรอตรวจ'), findsOneWidget);
    expect(find.textContaining('ต้องให้คุณตรวจสอบ'), findsOneWidget);
  });
}
