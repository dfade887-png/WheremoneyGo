import 'package:flutter_test/flutter_test.dart';
import 'package:ngoen_ku_pai_nai/data/repositories/sqlite_finance_repository.dart';
import 'package:ngoen_ku_pai_nai/domain/models/scheduled_financial_event.dart';
import 'package:ngoen_ku_pai_nai/domain/transaction_lifecycle.dart';

void main() {
  late SqliteFinanceRepository repository;
  late String accountId;
  late String expenseCategory;
  late String incomeCategory;

  setUp(() async {
    repository = SqliteFinanceRepository.memory();
    accountId = await repository.createAccount(
      name: 'SCB',
      type: 'bank',
      openingBalanceSatang: 100000,
    );
    expenseCategory = await repository.createCategory(
      name: 'Expense',
      type: 'expense',
      iconKey: 'receipt',
    );
    incomeCategory = await repository.createCategory(
      name: 'Income',
      type: 'income',
      iconKey: 'payments',
    );
  });

  tearDown(() => repository.dispose());

  Future<ScheduledFinancialEvent> schedule(
    ScheduledEventType type, {
    DateTime? scheduledAt,
    int amountSatang = 25000,
  }) => repository.createScheduledEvent(
    eventType: type,
    amountSatang: amountSatang,
    title: '${type.name} plan',
    note: 'confirmed by user',
    accountId: accountId,
    categoryId: type == ScheduledEventType.income
        ? incomeCategory
        : expenseCategory,
    scheduledAt: scheduledAt ?? DateTime.utc(2026, 8, 24),
  );

  Future<int> balance() async =>
      (await repository.accounts()).singleWhere(
            (row) => row['id'] == accountId,
          )['balance_satang']
          as int;

  test(
    'expense confirmation atomically creates and links real ledger',
    () async {
      final event = await schedule(ScheduledEventType.expense);
      expect(await balance(), 100000);
      final occurredAt = DateTime.utc(2026, 8, 24, 13, 42);

      final transactionId = await repository.confirmScheduledEvent(
        event.id,
        occurredAt: occurredAt,
      );

      expect(await balance(), 75000);
      expect(await repository.ledgerTransactionCount(), 1);
      final transaction = repository.query(
        'SELECT * FROM transactions WHERE id=?',
        [transactionId],
      ).single;
      expect(transaction['type'], 'expense');
      expect(transaction['amount_satang'], 25000);
      expect(transaction['account_id'], accountId);
      expect(transaction['category_id'], expenseCategory);
      expect(transaction['profile_id'], repository.activeProfileId);
      expect(transaction['source'], 'scheduled_event');
      expect(transaction['status'], 'confirmed');
      expect(transaction['deleted_at'], isNull);
      expect(transaction['occurred_at'], occurredAt.toIso8601String());
      expect(transaction['posted_at'], occurredAt.toIso8601String());
      expect(transaction['note'], 'confirmed by user');
      final fulfilled = (await repository.scheduledEvents()).single;
      expect(fulfilled.storedStatus, ScheduledEventStoredState.fulfilled);
      expect(fulfilled.linkedTransactionId, transactionId);
      expect(fulfilled.linkedTransferGroupId, isNull);
    },
  );

  test('income and refund confirmation increase Actual Balance', () async {
    final income = await schedule(
      ScheduledEventType.income,
      amountSatang: 50000,
    );
    final refund = await schedule(
      ScheduledEventType.refund,
      amountSatang: 5000,
    );

    await repository.confirmScheduledEvent(income.id);
    expect(await balance(), 150000);
    await repository.confirmScheduledEvent(refund.id);
    expect(await balance(), 155000);
    expect(
      repository
          .query('SELECT type FROM transactions ORDER BY created_at,id')
          .map((row) => row['type']),
      containsAll(['income', 'refund']),
    );
  });

  test('derived-due and future events can be confirmed explicitly', () async {
    final due = await schedule(
      ScheduledEventType.expense,
      scheduledAt: DateTime.utc(2026, 8, 1),
      amountSatang: 1000,
    );
    final future = await schedule(
      ScheduledEventType.expense,
      scheduledAt: DateTime.utc(2030, 1, 1),
      amountSatang: 2000,
    );
    expect(
      due.effectiveStatus(DateTime.utc(2026, 8, 20)),
      ScheduledEventState.due,
    );
    expect(
      future.effectiveStatus(DateTime.utc(2026, 8, 20)),
      ScheduledEventState.scheduled,
    );

    await repository.confirmScheduledEvent(due.id);
    await repository.confirmScheduledEvent(future.id);

    expect(await repository.ledgerTransactionCount(), 2);
    expect(await balance(), 97000);
  });

  test('cancelled and skipped events cannot be confirmed', () async {
    final cancelled = await schedule(ScheduledEventType.expense);
    final skipped = await schedule(ScheduledEventType.expense);
    await repository.cancelScheduledEvent(cancelled.id);
    await repository.skipScheduledEvent(skipped.id);

    await expectLater(
      repository.confirmScheduledEvent(cancelled.id),
      throwsStateError,
    );
    await expectLater(
      repository.confirmScheduledEvent(skipped.id),
      throwsStateError,
    );
    expect(await repository.ledgerTransactionCount(), 0);
    expect(await balance(), 100000);
  });

  test(
    'double confirmation returns existing transaction without duplicate',
    () async {
      final event = await schedule(ScheduledEventType.expense);
      final first = await repository.confirmScheduledEvent(event.id);
      final second = await repository.confirmScheduledEvent(event.id);

      expect(second, first);
      expect(await repository.ledgerTransactionCount(), 1);
      expect(await balance(), 75000);
    },
  );

  test(
    'transfer confirmation is reserved for T7 and creates no ledger',
    () async {
      final destination = await repository.createAccount(
        name: 'Savings',
        type: 'bank',
        openingBalanceSatang: 0,
      );
      final transfer = await repository.createScheduledEvent(
        eventType: ScheduledEventType.transfer,
        amountSatang: 50000,
        title: 'Save',
        accountId: accountId,
        destinationAccountId: destination,
        scheduledAt: DateTime.utc(2026, 8, 25),
      );

      await expectLater(
        repository.confirmScheduledEvent(transfer.id),
        throwsStateError,
      );
      expect(await repository.ledgerTransactionCount(), 0);
      expect(await balance(), 100000);
      expect(
        (await repository.scheduledEvents()).single.storedStatus,
        ScheduledEventStoredState.scheduled,
      );
    },
  );

  test('injected failure rolls back ledger link status and Actual', () async {
    final event = await schedule(ScheduledEventType.expense);

    await expectLater(
      repository.confirmScheduledEvent(event.id, failAfterLedgerInsert: true),
      throwsStateError,
    );

    expect(await repository.ledgerTransactionCount(), 0);
    expect(await balance(), 100000);
    final unchanged = (await repository.scheduledEvents()).single;
    expect(unchanged.storedStatus, ScheduledEventStoredState.scheduled);
    expect(unchanged.linkedTransactionId, isNull);
  });

  test('cross-profile confirmation cannot create or link ledger', () async {
    final event = await schedule(ScheduledEventType.expense);
    final profileB = await repository.createProfile('B', draft: false);
    await repository.switchProfile(profileB);
    await repository.createAccount(
      name: 'B account',
      type: 'bank',
      openingBalanceSatang: 0,
    );

    await expectLater(
      repository.confirmScheduledEvent(event.id),
      throwsStateError,
    );
    expect(await repository.ledgerTransactionCount(), 0);
    expect(await repository.scheduledEvents(), isEmpty);
  });

  test('soft-deleted event and dependencies cannot be confirmed', () async {
    final deletedEvent = await schedule(ScheduledEventType.expense);
    repository.execute(
      'UPDATE scheduled_financial_events SET deleted_at=? WHERE id=?',
      [DateTime.now().toUtc().toIso8601String(), deletedEvent.id],
    );
    await expectLater(
      repository.confirmScheduledEvent(deletedEvent.id),
      throwsStateError,
    );

    final deletedAccountEvent = await schedule(ScheduledEventType.expense);
    repository.execute('UPDATE accounts SET deleted_at=? WHERE id=?', [
      DateTime.now().toUtc().toIso8601String(),
      accountId,
    ]);
    await expectLater(
      repository.confirmScheduledEvent(deletedAccountEvent.id),
      throwsStateError,
    );
    expect(await repository.ledgerTransactionCount(), 0);
  });
}
