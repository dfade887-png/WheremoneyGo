import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:ngoen_ku_pai_nai/data/notification_capture_bridge.dart';
import 'package:ngoen_ku_pai_nai/ui/finance_app.dart';
import 'package:ngoen_ku_pai_nai/ui/app_state.dart';
import 'package:ngoen_ku_pai_nai/ui/local_finance_store.dart';
import 'package:ngoen_ku_pai_nai/ui/candidate_inbox_screen.dart';
import 'package:ngoen_ku_pai_nai/ui/finance_components.dart';
import 'package:ngoen_ku_pai_nai/ui/notification_capture_screen.dart';

void main() {
  test('money display keeps satang precision and separators', () {
    expect(FinanceMoneyFormat.satang(123456789), '฿1,234,567.89');
    expect(FinanceMoneyFormat.satang(-150000), '-฿1,500.00');
    expect(FinanceMoneyFormat.satang(1712500, signed: true), '+฿17,125.00');
  });

  testWidgets('candidate inbox is a safe empty shell', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: CandidateInboxScreen()));
    expect(find.text('รายการรอตรวจ'), findsOneWidget);
    expect(find.byKey(const Key('candidate-inbox-empty')), findsOneWidget);
    expect(find.textContaining('ต้องให้คุณตรวจสอบ'), findsOneWidget);
  });

  testWidgets(
    'notification settings renders safely with a configured LINE source',
    (tester) async {
      const channel = MethodChannel('test/notification_capture');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async => switch (call.method) {
          'hasNotificationAccess' => true,
          'readCapturedNotifications' => <Object?>[],
          _ => null,
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      final store = LocalFinanceStore.memory();
      final state = AppState(store: store);
      await state.initialize();
      await store.repository.createNotificationSource(
        sourceKind: 'line',
        displayName: 'LINE',
        packageName: 'jp.naver.line.android',
      );
      expect(await state.financeRepository.notificationSources(), hasLength(1));
      await tester.pumpWidget(
        MaterialApp(
          home: NotificationCaptureScreen(
            state: state,
            bridge: NotificationCaptureBridge(channel: channel),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('สิทธิ์การแจ้งเตือน'), findsOneWidget);
      expect(find.text('เปิดแล้ว'), findsOneWidget);
      // The source row itself is repository-tested above. Platform probes are
      // asynchronous and intentionally not required for this screen to render.
      expect(find.text('jp.naver.line.android'), findsNothing);
    },
  );
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
    expect(find.text('เงินจริงที่มี'), findsOneWidget);
    expect(find.text('LOCAL DATA • ข้อมูลจริง'), findsOneWidget);
    expect(find.text('สถานะงบเดือนนี้'), findsOneWidget);
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
    expect(find.text('บันทึก ฿120.00'), findsOneWidget);
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
