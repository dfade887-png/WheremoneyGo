import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ngoen_ku_pai_nai/data/repositories/sqlite_finance_repository.dart';
import 'package:ngoen_ku_pai_nai/domain/models/scheduled_financial_event.dart';
import 'package:ngoen_ku_pai_nai/ui/scheduled_event_editor_screen.dart';
import 'package:ngoen_ku_pai_nai/ui/theme/app_theme.dart';

void main() {
  late SqliteFinanceRepository repository;
  late String scb;
  late String krungthai;
  late String expenseCategory;
  late String incomeCategory;

  setUp(() async {
    repository = SqliteFinanceRepository.memory();
    scb = await repository.createAccount(
      name: 'SCB บัญชีหลัก',
      type: 'bank',
      openingBalanceSatang: 1000000,
    );
    krungthai = await repository.createAccount(
      name: 'Krungthai บัญชีออม',
      type: 'bank',
      openingBalanceSatang: 500000,
    );
    expenseCategory = await repository.createCategory(
      name: 'สุขภาพ',
      type: 'expense',
      iconKey: 'health',
    );
    incomeCategory = await repository.createCategory(
      name: 'เงินเดือน',
      type: 'income',
      iconKey: 'salary',
    );
  });

  tearDown(() => repository.dispose());

  Future<void> pumpEditor(
    WidgetTester tester, {
    ScheduledFinancialEvent? existing,
  }) async {
    final accounts = await repository.accounts();
    final categories = await repository.categories();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                key: const Key('launch-editor'),
                onPressed: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ScheduledEventEditorScreen(
                      repository: repository,
                      accounts: accounts,
                      categories: categories,
                      initialScheduledAt: DateTime(2026, 9, 24, 9),
                      existing: existing,
                      now: () => DateTime(2026, 8, 29),
                    ),
                  ),
                ),
                child: const Text('เปิด'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('launch-editor')));
    await tester.pumpAndSettle();
  }

  Future<void> revealSave(WidgetTester tester) async {
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('scheduled-save')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
  }

  testWidgets('creates future expense as schedule only', (tester) async {
    await pumpEditor(tester);
    await tester.enterText(find.byKey(const Key('scheduled-title')), 'ทำฟัน');
    await tester.enterText(find.byKey(const Key('scheduled-amount')), '2,500');
    await tester.tap(find.byKey(const Key('scheduled-category')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('สุขภาพ').last);
    await tester.pumpAndSettle();

    await revealSave(tester);
    expect(find.textContaining('กระทบเฉพาะ Forecast'), findsOneWidget);
    await tester.tap(find.byKey(const Key('scheduled-save')));
    await tester.pumpAndSettle();

    final events = await repository.scheduledEvents();
    expect(events, hasLength(1));
    expect(events.single.title, 'ทำฟัน');
    expect(events.single.amountSatang, 250000);
    expect(events.single.categoryId, expenseCategory);
    expect(await repository.ledgerTransactionCount(), 0);
  });

  testWidgets('creates transfer with two different accounts and no category', (
    tester,
  ) async {
    await pumpEditor(tester);
    await tester.tap(find.text('โอน'));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('scheduled-title')),
      'เก็บเงิน',
    );
    await tester.enterText(find.byKey(const Key('scheduled-amount')), '1000');
    await tester.tap(find.byKey(const Key('scheduled-destination')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Krungthai บัญชีออม').last);
    await tester.pumpAndSettle();
    await revealSave(tester);
    await tester.tap(find.byKey(const Key('scheduled-save')));
    await tester.pumpAndSettle();

    final event = (await repository.scheduledEvents()).single;
    expect(event.eventType, ScheduledEventType.transfer);
    expect(event.accountId, scb);
    expect(event.destinationAccountId, krungthai);
    expect(event.categoryId, isNull);
    expect(await repository.ledgerTransactionCount(), 0);
  });

  testWidgets('edits then cancels a manual schedule without ledger writes', (
    tester,
  ) async {
    var event = await repository.createScheduledEvent(
      eventType: ScheduledEventType.income,
      amountSatang: 1712500,
      title: 'เงินเดือน',
      accountId: scb,
      categoryId: incomeCategory,
      scheduledAt: DateTime(2026, 9, 28, 9),
    );
    await pumpEditor(tester, existing: event);
    await tester.enterText(
      find.byKey(const Key('scheduled-title')),
      'เงินเดือนใหม่',
    );
    await revealSave(tester);
    await tester.tap(find.byKey(const Key('scheduled-save')));
    await tester.pumpAndSettle();
    event = (await repository.scheduledEvents()).single;
    expect(event.title, 'เงินเดือนใหม่');

    await pumpEditor(tester, existing: event);
    await tester.tap(find.byKey(const Key('scheduled-cancel')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ยกเลิกรายการ').last);
    await tester.pumpAndSettle();

    expect(
      (await repository.scheduledEvents()).single.storedStatus.name,
      'cancelled',
    );
    expect(await repository.ledgerTransactionCount(), 0);
  });
}
