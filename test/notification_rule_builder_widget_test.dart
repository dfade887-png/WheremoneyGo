import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ngoen_ku_pai_nai/domain/notification_capture.dart';
import 'package:ngoen_ku_pai_nai/ui/app_state.dart';
import 'package:ngoen_ku_pai_nai/ui/local_finance_store.dart';
import 'package:ngoen_ku_pai_nai/ui/notification_rule_builder_screen.dart';

void main() {
  testWidgets('builder previews, saves, toggles, and explicitly reprocesses', (
    tester,
  ) async {
    final store = LocalFinanceStore.memory();
    final state = AppState(store: store);
    await state.initialize();
    final account = await store.repository.createAccount(
      name: 'SCB Test',
      type: 'bank',
      openingBalanceSatang: 100000,
    );
    final source = await store.repository.createNotificationSource(
      sourceKind: 'line',
      displayName: 'LINE',
      packageName: 'jp.naver.line.android',
      defaultAccountId: account,
    );
    await store.repository.ingestCapturedNotification(
      CapturedNotification(
        profileId: store.repository.activeProfileId,
        notificationSourceId: source,
        packageName: 'jp.naver.line.android',
        notificationKeyHash: 'synthetic-widget-event',
        capturedAt: DateTime.utc(2026, 8, 27, 12),
        title: 'Synthetic',
        body: 'รายการเงินออก 100.00 บาท',
        senderOrChat: 'SCB Connect',
      ),
    );
    await state.refreshDailyData();
    addTearDown(state.dispose);

    await tester.pumpWidget(
      MaterialApp(home: NotificationRuleBuilderScreen(state: state)),
    );
    await tester.pumpAndSettle();

    expect(find.text('กฎการตรวจจับ'), findsOneWidget);
    expect(find.text('jp.naver.line.android'), findsNothing);
    expect(
      find.byKey(const Key('add-notification-rule')),
      findsOneWidget,
      reason: tester
          .widgetList<Text>(find.byType(Text))
          .map((widget) => widget.data)
          .whereType<String>()
          .join(' | '),
    );
    await tester.tap(find.byKey(const Key('add-notification-rule')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('rule-name')), 'SCB outgoing');
    await tester.enterText(
      find.byKey(const Key('rule-sender-pattern')),
      'SCB Connect',
    );
    await tester.enterText(
      find.byKey(const Key('rule-body-pattern')),
      'รายการเงินออก {amount} บาท',
    );
    await tester.ensureVisible(find.byKey(const Key('pick-raw-sample')));
    await tester.tap(find.byKey(const Key('pick-raw-sample')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SCB Connect').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('preview-rule')));
    await tester.tap(find.byKey(const Key('preview-rule')));
    await tester.pumpAndSettle();
    expect(find.textContaining('฿100.00'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('save-rule')));
    await tester.tap(find.byKey(const Key('save-rule')));
    await tester.pumpAndSettle();
    expect(find.text('SCB outgoing'), findsOneWidget);

    await tester.tap(find.byKey(const Key('reprocess-raw-events')));
    await tester.pumpAndSettle();
    expect(find.text('ตรวจรายการที่เก็บไว้?'), findsOneWidget);
    await tester.tap(find.text('เริ่มตรวจ'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reprocess-summary')), findsOneWidget);
    expect(find.text('ตรวจพบ Candidate ใหม่: 1'), findsOneWidget);
    expect(find.byKey(const Key('go-to-candidate-inbox')), findsOneWidget);

    final toggle = tester.widget<Switch>(find.byType(Switch).first);
    expect(toggle.value, isTrue);
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch).first).value, isFalse);
  });
}
