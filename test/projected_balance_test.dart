import 'package:flutter_test/flutter_test.dart';
import 'package:ngoen_ku_pai_nai/data/repositories/sqlite_finance_repository.dart';
import 'package:ngoen_ku_pai_nai/domain/models/scheduled_financial_event.dart';

void main() {
  late SqliteFinanceRepository repository;
  late String accountA;
  late String accountB;

  setUp(() async {
    repository = SqliteFinanceRepository.memory();
    accountA = await repository.createAccount(
      name: 'A',
      type: 'bank',
      openingBalanceSatang: 1000000,
    );
    accountB = await repository.createAccount(
      name: 'B',
      type: 'bank',
      openingBalanceSatang: 500000,
    );
  });

  tearDown(() => repository.dispose());

  Future<ScheduledFinancialEvent> schedule(
    ScheduledEventType type,
    int amount, {
    DateTime? at,
    String? accountId,
    String? destinationId,
  }) => repository.createScheduledEvent(
    eventType: type,
    amountSatang: amount,
    title: type.name,
    accountId: accountId ?? accountA,
    destinationAccountId: destinationId,
    scheduledAt: at ?? DateTime.utc(2026, 8, 24),
  );

  test('income expense and refund project without changing Actual', () async {
    await schedule(ScheduledEventType.income, 200000);
    await schedule(ScheduledEventType.expense, 150000);
    await schedule(ScheduledEventType.refund, 50000);

    final result = await repository.projectedBalance(
      cutoff: DateTime.utc(2026, 8, 24),
    );

    expect(result.account(accountA).actualBalanceSatang, 1000000);
    expect(result.account(accountA).projectedBalanceSatang, 1100000);
    expect(result.account(accountA).projectedDeltaSatang, 100000);
    expect(
      (await repository.accounts()).singleWhere(
        (row) => row['id'] == accountA,
      )['balance_satang'],
      1000000,
    );
    expect(await repository.ledgerTransactionCount(), 0);
  });

  test('transfer redistributes projection but preserves net worth', () async {
    await schedule(
      ScheduledEventType.transfer,
      200000,
      destinationId: accountB,
    );
    final result = await repository.projectedBalance(
      cutoff: DateTime.utc(2026, 8, 24),
    );
    expect(result.account(accountA).projectedBalanceSatang, 800000);
    expect(result.account(accountB).projectedBalanceSatang, 700000);
    expect(result.actualNetWorthSatang, 1500000);
    expect(result.projectedNetWorthSatang, 1500000);
  });

  test('cutoff is inclusive and uses dueAt before scheduledAt', () async {
    await repository.createScheduledEvent(
      eventType: ScheduledEventType.expense,
      amountSatang: 10000,
      title: 'first',
      accountId: accountA,
      scheduledAt: DateTime.utc(2026, 8, 30),
      dueAt: DateTime.utc(2026, 8, 24, 12),
    );
    await schedule(
      ScheduledEventType.expense,
      20000,
      at: DateTime.utc(2026, 8, 27),
    );
    expect(
      (await repository.projectedBalance(
        cutoff: DateTime.utc(2026, 8, 24, 11, 59),
      )).account(accountA).projectedBalanceSatang,
      1000000,
    );
    expect(
      (await repository.projectedBalance(
        cutoff: DateTime.utc(2026, 8, 24, 12),
      )).account(accountA).projectedBalanceSatang,
      990000,
    );
    expect(
      (await repository.projectedBalance(
        cutoff: DateTime.utc(2026, 8, 27),
      )).account(accountA).projectedBalanceSatang,
      970000,
    );
  });

  test('overdue active event remains projected', () async {
    await schedule(
      ScheduledEventType.expense,
      150000,
      at: DateTime.utc(2026, 8, 1),
    );
    final result = await repository.projectedBalance(
      cutoff: DateTime.utc(2026, 8, 20),
    );
    expect(result.account(accountA).projectedBalanceSatang, 850000);
  });

  test('cancelled skipped and soft-deleted events are excluded', () async {
    final cancelled = await schedule(ScheduledEventType.expense, 10000);
    final skipped = await schedule(ScheduledEventType.expense, 20000);
    final deleted = await schedule(ScheduledEventType.expense, 40000);
    await repository.cancelScheduledEvent(cancelled.id);
    await repository.skipScheduledEvent(skipped.id);
    repository.execute(
      'UPDATE scheduled_financial_events SET deleted_at=? WHERE id=?',
      [DateTime.now().toUtc().toIso8601String(), deleted.id],
    );
    final result = await repository.projectedBalance(
      cutoff: DateTime.utc(2026, 8, 24),
    );
    expect(result.account(accountA).projectedBalanceSatang, 1000000);
  });

  test('fulfilled expense and income are never double counted', () async {
    final expense = await schedule(ScheduledEventType.expense, 150000);
    final income = await schedule(ScheduledEventType.income, 200000);
    final before = await repository.projectedBalance(
      cutoff: DateTime.utc(2026, 8, 24),
    );
    expect(before.account(accountA).projectedBalanceSatang, 1050000);

    await repository.confirmScheduledEvent(expense.id);
    await repository.confirmScheduledEvent(income.id);
    final after = await repository.projectedBalance(
      cutoff: DateTime.utc(2026, 8, 24),
    );
    expect(after.account(accountA).actualBalanceSatang, 1050000);
    expect(after.account(accountA).projectedBalanceSatang, 1050000);
  });

  test(
    'fulfilled transfer projection equals its new Actual balances',
    () async {
      final transfer = await schedule(
        ScheduledEventType.transfer,
        200000,
        destinationId: accountB,
      );
      final before = await repository.projectedBalance(
        cutoff: DateTime.utc(2026, 8, 24),
      );
      expect(before.account(accountA).projectedBalanceSatang, 800000);
      expect(before.account(accountB).projectedBalanceSatang, 700000);

      await repository.confirmScheduledTransfer(transfer.id);
      final after = await repository.projectedBalance(
        cutoff: DateTime.utc(2026, 8, 24),
      );
      expect(after.account(accountA).actualBalanceSatang, 800000);
      expect(after.account(accountA).projectedBalanceSatang, 800000);
      expect(after.account(accountB).actualBalanceSatang, 700000);
      expect(after.account(accountB).projectedBalanceSatang, 700000);
    },
  );

  test('projection is isolated to the active profile', () async {
    await schedule(ScheduledEventType.expense, 100000);
    final profileB = await repository.createProfile('B', draft: false);
    await repository.switchProfile(profileB);
    final b = await repository.createAccount(
      name: 'Only B',
      type: 'bank',
      openingBalanceSatang: 300000,
    );
    await schedule(
      ScheduledEventType.income,
      50000,
      accountId: b,
      at: DateTime.utc(2026, 8, 24),
    );
    final result = await repository.projectedBalance(
      cutoff: DateTime.utc(2026, 8, 24),
    );
    expect(result.accounts.keys, [b]);
    expect(result.account(b).projectedBalanceSatang, 350000);
  });

  test('projection performs no database writes', () async {
    await schedule(ScheduledEventType.expense, 10000);
    final beforeAccounts = await repository.dumpTable('accounts');
    final beforeTransactions = await repository.dumpTable('transactions');
    final beforeEvents = await repository.dumpTable(
      'scheduled_financial_events',
    );

    await repository.projectedBalance(cutoff: DateTime.utc(2026, 8, 24));

    expect(await repository.dumpTable('accounts'), beforeAccounts);
    expect(await repository.dumpTable('transactions'), beforeTransactions);
    expect(
      await repository.dumpTable('scheduled_financial_events'),
      beforeEvents,
    );
  });

  test('soft-deleted account and its events are excluded', () async {
    await schedule(ScheduledEventType.expense, 10000);
    repository.execute('UPDATE accounts SET deleted_at=? WHERE id=?', [
      DateTime.now().toUtc().toIso8601String(),
      accountA,
    ]);
    final result = await repository.projectedBalance(
      cutoff: DateTime.utc(2026, 8, 24),
    );
    expect(result.accounts.containsKey(accountA), isFalse);
    expect(result.accounts.containsKey(accountB), isTrue);
  });
}
