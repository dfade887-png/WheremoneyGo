import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ngoen_ku_pai_nai/ui/finance_app.dart';
import 'package:ngoen_ku_pai_nai/ui/app_state.dart';
import 'package:ngoen_ku_pai_nai/ui/local_finance_store.dart';

void main() {
  testWidgets('onboarding reaches dashboard', (tester) async {
    await tester.pumpWidget(
      FinanceApp(state: AppState(store: LocalFinanceStore.memory())),
    );
    await tester.pumpAndSettle();
    expect(find.text('เงินหายไปไหน\nเดี๋ยวหาให้'), findsOneWidget);
    await tester.tap(find.text('เริ่มตั้งค่า'));
    await tester.pumpAndSettle();
    expect(find.text('วันเงินเดือนออก'), findsOneWidget);
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.text('ถัดไป'));
      await tester.pumpAndSettle();
    }
    expect(find.text('วันนี้ยังรอด'), findsOneWidget);
    expect(find.text('DEMO DATA'), findsOneWidget);
  });
  testWidgets('quick add requires amount and category', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: QuickAddSheet())),
    );
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'บันทึก'))
          .onPressed,
      isNull,
    );
    await tester.enterText(find.byType(TextField).first, '120');
    await tester.pump();
    await tester.tap(find.text('เลือกหมวด (Required)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('อาหาร'));
    await tester.pumpAndSettle();
    expect(find.text('บันทึก ฿120'), findsOneWidget);
  });
  testWidgets('statement confirm is blocked while pending', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: StatementPreviewScreen()));
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Confirm ทั้งชุด'),
          )
          .onPressed,
      isNull,
    );
    expect(find.textContaining('Difference'), findsOneWidget);
  });

  testWidgets('dirty quick add warns before discard and keeps editing', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: QuickAddSheet())),
    );
    await tester.enterText(find.byType(TextField).first, '120');
    await tester.pump();
    await tester.tap(find.byTooltip('ปิด'));
    await tester.pumpAndSettle();
    expect(find.text('ทิ้งการเปลี่ยนแปลง?'), findsOneWidget);
    await tester.tap(find.text('แก้ไขต่อ'));
    await tester.pumpAndSettle();
    expect(find.text('120'), findsOneWidget);
  });

  testWidgets('statement matching refund transfer unlock reconciliation', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: StatementPreviewScreen()));

    await tester.tap(find.text('ร้านอาหาร'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('matchExisting'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('เลือก'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('โอนเงิน'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('transfer'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('เงินคืนร้านค้า'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('refund'));
    await tester.pumpAndSettle();

    expect(find.text('Difference ฿0'), findsOneWidget);
    final confirm = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Confirm ทั้งชุด'),
    );
    expect(confirm.onPressed, isNotNull);
  });
}
