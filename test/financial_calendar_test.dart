import 'package:flutter_test/flutter_test.dart';
import 'package:ngoen_ku_pai_nai/data/repositories/sqlite_finance_repository.dart';
import 'package:ngoen_ku_pai_nai/domain/financial_calendar.dart';
import 'package:ngoen_ku_pai_nai/domain/models/scheduled_financial_event.dart';

void main() {
  late SqliteFinanceRepository repository;
  late String accountA;
  late String accountB;
  late String expenseCategory;
  late String incomeCategory;
  final from = DateTime.utc(2026, 8, 1);
  final to = DateTime.utc(2026, 8, 31, 23, 59, 59);
  final now = DateTime.utc(2026, 8, 20);

  setUp(() async {
    repository = SqliteFinanceRepository.memory();
    accountA = await repository.createAccount(
      name: 'SCB',
      type: 'bank',
      openingBalanceSatang: 1000000,
    );
    accountB = await repository.createAccount(
      name: 'KTB',
      type: 'bank',
      openingBalanceSatang: 500000,
    );
    expenseCategory = await repository.createCategory(
      name: 'Expense',
      type: 'expense',
      iconKey: 'expense',
    );
    incomeCategory = await repository.createCategory(
      name: 'Income',
      type: 'income',
      iconKey: 'income',
    );
  });

  tearDown(() => repository.dispose());

  Future<ScheduledFinancialEvent> schedule(
    ScheduledEventType type,
    String title,
    DateTime at, {
    int amount = 10000,
    String origin = 'manual',
    String? destination,
  }) => repository.createScheduledEvent(
    eventType: type,
    amountSatang: amount,
    title: title,
    accountId: accountA,
    destinationAccountId: destination,
    categoryId: type == ScheduledEventType.transfer
        ? null
        : type == ScheduledEventType.income
        ? incomeCategory
        : expenseCategory,
    scheduledAt: at,
    originType: origin,
  );

  Future<FinancialCalendarResult> calendar({
    Set<FinancialCalendarDisplayStatus>? statuses,
  }) => repository.calendarEvents(
    from: from,
    to: to,
    now: now,
    statuses: statuses,
  );

  test(
    'normalizes future and due scheduled events with action state',
    () async {
      await schedule(
        ScheduledEventType.income,
        'Future income',
        DateTime.utc(2026, 8, 25),
      );
      await schedule(
        ScheduledEventType.expense,
        'Due expense',
        DateTime.utc(2026, 8, 10),
      );
      final events = (await calendar()).events;
      expect(events, hasLength(2));
      expect(events.first.displayStatus, FinancialCalendarDisplayStatus.due);
      expect(events.first.isActionRequired, isTrue);
      expect(
        events.last.displayStatus,
        FinancialCalendarDisplayStatus.scheduled,
      );
      expect(events.last.isActionRequired, isFalse);
      expect(events.last.direction, FinancialCalendarDirection.incoming);
    },
  );

  test('cancelled skipped and status filters remain visible', () async {
    final cancelled = await schedule(
      ScheduledEventType.expense,
      'Cancelled',
      DateTime.utc(2026, 8, 15),
    );
    final skipped = await schedule(
      ScheduledEventType.expense,
      'Skipped',
      DateTime.utc(2026, 8, 16),
    );
    await repository.cancelScheduledEvent(cancelled.id);
    await repository.skipScheduledEvent(skipped.id);
    expect((await calendar()).events, hasLength(2));
    final filtered = await calendar(
      statuses: {FinancialCalendarDisplayStatus.skipped},
    );
    expect(filtered.events.single.title, 'Skipped');
  });

  test('fulfilled expense and income suppress linked actual rows', () async {
    final expense = await schedule(
      ScheduledEventType.expense,
      'Dentist',
      DateTime.utc(2026, 8, 18),
    );
    final income = await schedule(
      ScheduledEventType.income,
      'Salary',
      DateTime.utc(2026, 8, 19),
    );
    await repository.confirmScheduledEvent(
      expense.id,
      occurredAt: DateTime.utc(2026, 8, 18, 12),
    );
    await repository.confirmScheduledEvent(
      income.id,
      occurredAt: DateTime.utc(2026, 8, 19, 8),
    );
    final events = (await calendar()).events;
    expect(events, hasLength(2));
    expect(
      events.every(
        (event) =>
            event.displayStatus == FinancialCalendarDisplayStatus.fulfilled &&
            event.actuality == FinancialCalendarActuality.actual &&
            event.transactionId != null,
      ),
      isTrue,
    );
  });

  test('fulfilled scheduled transfer suppresses both ledger rows', () async {
    final transfer = await schedule(
      ScheduledEventType.transfer,
      'Save',
      DateTime.utc(2026, 8, 20),
      destination: accountB,
    );
    final group = await repository.confirmScheduledTransfer(
      transfer.id,
      occurredAt: DateTime.utc(2026, 8, 20, 10),
    );
    final event = (await calendar()).events.single;
    expect(event.eventType, FinancialCalendarEventType.transfer);
    expect(event.displayStatus, FinancialCalendarDisplayStatus.fulfilled);
    expect(event.transferGroupId, group);
    expect(event.destinationAccountId, accountB);
  });

  test(
    'manual transaction and transfer normalize as actual activities',
    () async {
      await repository.createTransaction(
        accountId: accountA,
        categoryId: expenseCategory,
        type: 'expense',
        amountSatang: 6000,
        occurredAt: DateTime.utc(2026, 8, 20, 12),
        note: 'Coffee',
      );
      final group = await repository.createTransfer(
        fromAccountId: accountA,
        toAccountId: accountB,
        amountSatang: 200000,
      );
      repository.execute(
        'UPDATE transactions SET occurred_at=?,posted_at=? WHERE transfer_group_id=?',
        [
          DateTime.utc(2026, 8, 20, 20).toIso8601String(),
          DateTime.utc(2026, 8, 20, 20).toIso8601String(),
          group,
        ],
      );
      final events = (await calendar()).events;
      expect(events, hasLength(2));
      expect(events.first.title, 'Coffee');
      expect(events.first.displayStatus, FinancialCalendarDisplayStatus.actual);
      expect(events.last.eventType, FinancialCalendarEventType.transfer);
      expect(events.last.transferGroupId, group);
    },
  );

  test('broken transfer pair is excluded and reported', () async {
    final group = await repository.createTransfer(
      fromAccountId: accountA,
      toAccountId: accountB,
      amountSatang: 10000,
    );
    repository.execute(
      "DELETE FROM transactions WHERE transfer_group_id=? AND type='transfer_in'",
      [group],
    );
    repository.execute(
      'UPDATE transactions SET occurred_at=? WHERE transfer_group_id=?',
      [DateTime.utc(2026, 8, 20).toIso8601String(), group],
    );
    final result = await calendar();
    expect(result.events, isEmpty);
    expect(result.excludedBrokenTransferGroupIds, [group]);
  });

  test('date range soft delete and profile isolation are enforced', () async {
    await schedule(
      ScheduledEventType.expense,
      'Before',
      DateTime.utc(2026, 7, 31),
    );
    final inside = await schedule(
      ScheduledEventType.expense,
      'Inside',
      DateTime.utc(2026, 8, 10),
    );
    final deleted = await schedule(
      ScheduledEventType.expense,
      'Deleted',
      DateTime.utc(2026, 8, 11),
    );
    repository.execute(
      'UPDATE scheduled_financial_events SET deleted_at=? WHERE id=?',
      [DateTime.now().toUtc().toIso8601String(), deleted.id],
    );
    expect((await calendar()).events.single.scheduledEventId, inside.id);
    final profileB = await repository.createProfile('B', draft: false);
    await repository.switchProfile(profileB);
    expect((await calendar()).events, isEmpty);
  });

  test(
    'commitment and salary normalized origins appear automatically',
    () async {
      await schedule(
        ScheduledEventType.expense,
        'Phone',
        DateTime.utc(2026, 8, 24),
        origin: 'commitment_occurrence',
      );
      await schedule(
        ScheduledEventType.income,
        'Salary',
        DateTime.utc(2026, 8, 27),
        origin: 'salary_payday',
      );
      final events = (await calendar()).events;
      expect(events.first.originKind, FinancialCalendarOriginKind.commitment);
      expect(events.last.originKind, FinancialCalendarOriginKind.salary);
    },
  );

  test('sorting is deterministic and calendar query is read-only', () async {
    final at = DateTime.utc(2026, 8, 20, 12);
    await schedule(ScheduledEventType.expense, 'B', at);
    await schedule(ScheduledEventType.expense, 'A', at);
    final beforeAccounts = await repository.dumpTable('accounts');
    final beforeTransactions = await repository.dumpTable('transactions');
    final beforeScheduled = await repository.dumpTable(
      'scheduled_financial_events',
    );
    final first = await calendar();
    final second = await calendar();
    expect(
      second.events.map((event) => event.id),
      first.events.map((event) => event.id),
    );
    expect(await repository.dumpTable('accounts'), beforeAccounts);
    expect(await repository.dumpTable('transactions'), beforeTransactions);
    expect(
      await repository.dumpTable('scheduled_financial_events'),
      beforeScheduled,
    );
  });

  test('realistic mixed day returns four normalized activities', () async {
    final salary = await schedule(
      ScheduledEventType.income,
      'Salary',
      DateTime.utc(2026, 8, 20, 8),
      amount: 1712500,
      origin: 'salary_payday',
    );
    await repository.confirmScheduledEvent(
      salary.id,
      occurredAt: DateTime.utc(2026, 8, 20, 8),
    );
    await repository.createTransaction(
      accountId: accountA,
      categoryId: expenseCategory,
      type: 'expense',
      amountSatang: 12000,
      occurredAt: DateTime.utc(2026, 8, 20, 12),
      note: 'Food',
    );
    await schedule(
      ScheduledEventType.expense,
      'Dentist',
      DateTime.utc(2026, 8, 20, 18),
      amount: 150000,
    );
    final group = await repository.createTransfer(
      fromAccountId: accountA,
      toAccountId: accountB,
      amountSatang: 200000,
    );
    repository.execute(
      'UPDATE transactions SET occurred_at=?,posted_at=? WHERE transfer_group_id=?',
      [
        DateTime.utc(2026, 8, 20, 20).toIso8601String(),
        DateTime.utc(2026, 8, 20, 20).toIso8601String(),
        group,
      ],
    );

    final events = (await calendar()).events;

    expect(events, hasLength(4));
    expect(events.map((event) => event.eventType), [
      FinancialCalendarEventType.income,
      FinancialCalendarEventType.expense,
      FinancialCalendarEventType.expense,
      FinancialCalendarEventType.transfer,
    ]);
    expect(
      events.first.displayStatus,
      FinancialCalendarDisplayStatus.fulfilled,
    );
    expect(events[1].displayStatus, FinancialCalendarDisplayStatus.actual);
    expect(events[2].displayStatus, FinancialCalendarDisplayStatus.scheduled);
    expect(events.last.transferGroupId, group);
  });
}
