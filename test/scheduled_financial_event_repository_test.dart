import 'package:flutter_test/flutter_test.dart';
import 'package:ngoen_ku_pai_nai/data/repositories/sqlite_finance_repository.dart';
import 'package:ngoen_ku_pai_nai/domain/models/scheduled_financial_event.dart';
import 'package:ngoen_ku_pai_nai/domain/transaction_lifecycle.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late SqliteFinanceRepository repository;
  late String sourceAccount;
  late String destinationAccount;
  late String expenseCategory;
  late String incomeCategory;

  setUp(() async {
    repository = SqliteFinanceRepository.memory();
    sourceAccount = await repository.createAccount(
      name: 'SCB',
      type: 'bank',
      openingBalanceSatang: 100000,
    );
    destinationAccount = await repository.createAccount(
      name: 'Wallet',
      type: 'wallet',
      openingBalanceSatang: 5000,
    );
    expenseCategory = await repository.createCategory(
      name: 'Food',
      type: 'expense',
      iconKey: 'restaurant',
    );
    incomeCategory = await repository.createCategory(
      name: 'Salary',
      type: 'income',
      iconKey: 'payments',
    );
  });

  tearDown(() => repository.dispose());

  Future<ScheduledFinancialEvent> expense({
    String title = 'Dentist',
    int amountSatang = 150000,
    DateTime? scheduledAt,
    DateTime? dueAt,
    String? originId,
    String? occurrenceKey,
  }) => repository.createScheduledEvent(
    eventType: ScheduledEventType.expense,
    amountSatang: amountSatang,
    title: title,
    accountId: sourceAccount,
    categoryId: expenseCategory,
    scheduledAt: scheduledAt ?? DateTime.utc(2026, 8, 24),
    dueAt: dueAt,
    originId: originId,
    occurrenceKey: occurrenceKey,
  );

  Future<int> netWorth() async => (await repository.accounts()).fold<int>(
    0,
    (sum, row) => sum + (row['balance_satang'] as int),
  );

  test('creates one-time income expense and transfer outside ledger', () async {
    final before = await netWorth();
    final scheduledExpense = await expense();
    final scheduledIncome = await repository.createScheduledEvent(
      eventType: ScheduledEventType.income,
      amountSatang: 1800000,
      title: 'Salary',
      accountId: sourceAccount,
      categoryId: incomeCategory,
      scheduledAt: DateTime.utc(2026, 8, 27),
    );
    final scheduledTransfer = await repository.createScheduledEvent(
      eventType: ScheduledEventType.transfer,
      amountSatang: 500000,
      title: 'Save money',
      accountId: sourceAccount,
      destinationAccountId: destinationAccount,
      scheduledAt: DateTime.utc(2026, 8, 28),
    );

    expect(scheduledExpense.eventType, ScheduledEventType.expense);
    expect(scheduledExpense.amountSatang, 150000);
    expect(scheduledIncome.eventType, ScheduledEventType.income);
    expect(scheduledTransfer.destinationAccountId, destinationAccount);
    expect(scheduledTransfer.storedStatus, ScheduledEventStoredState.scheduled);
    expect(await repository.ledgerTransactionCount(), 0);
    expect(await netWorth(), before);
  });

  test('repository rejects invalid amount and account shapes', () async {
    Future<ScheduledFinancialEvent> create({
      required ScheduledEventType type,
      required int amount,
      String? destination,
    }) => repository.createScheduledEvent(
      eventType: type,
      amountSatang: amount,
      title: 'Plan',
      accountId: sourceAccount,
      destinationAccountId: destination,
      scheduledAt: DateTime.utc(2026, 8, 24),
    );

    await expectLater(
      create(type: ScheduledEventType.expense, amount: 0),
      throwsArgumentError,
    );
    await expectLater(
      create(type: ScheduledEventType.transfer, amount: 100),
      throwsArgumentError,
    );
    await expectLater(
      create(
        type: ScheduledEventType.transfer,
        amount: 100,
        destination: sourceAccount,
      ),
      throwsArgumentError,
    );
    await expectLater(
      create(
        type: ScheduledEventType.expense,
        amount: 100,
        destination: destinationAccount,
      ),
      throwsArgumentError,
    );
  });

  test('effective due uses dueAt before scheduledAt', () async {
    final now = DateTime.utc(2026, 8, 20, 12);
    final future = await expense(scheduledAt: DateTime.utc(2026, 8, 21));
    final due = await expense(
      title: 'Past',
      scheduledAt: DateTime.utc(2026, 8, 19),
    );
    final overridden = await expense(
      title: 'Later due',
      scheduledAt: DateTime.utc(2026, 8, 19),
      dueAt: DateTime.utc(2026, 8, 22),
    );

    expect(future.effectiveStatus(now), ScheduledEventState.scheduled);
    expect(due.effectiveStatus(now), ScheduledEventState.due);
    expect(overridden.effectiveStatus(now), ScheduledEventState.scheduled);
    expect(
      overridden.effectiveStatus(DateTime.utc(2026, 8, 22)),
      ScheduledEventState.due,
    );
  });

  test('cancel and skip are terminal and never derive due', () async {
    final cancelled = await repository.cancelScheduledEvent(
      (await expense(title: 'Cancel')).id,
    );
    final skipped = await repository.skipScheduledEvent(
      (await expense(title: 'Skip')).id,
    );
    final farFuture = DateTime.utc(2030);

    expect(cancelled.storedStatus, ScheduledEventStoredState.cancelled);
    expect(cancelled.cancelledAt, isNotNull);
    expect(cancelled.effectiveStatus(farFuture), ScheduledEventState.cancelled);
    expect(skipped.storedStatus, ScheduledEventStoredState.skipped);
    expect(skipped.cancelledAt, isNull);
    expect(skipped.effectiveStatus(farFuture), ScheduledEventState.skipped);
    await expectLater(
      repository.cancelScheduledEvent(cancelled.id),
      throwsStateError,
    );
    await expectLater(
      repository.skipScheduledEvent(skipped.id),
      throwsStateError,
    );
  });

  test('fulfilled row remains terminal and cannot become due', () async {
    final event = await expense(title: 'Already paid');
    final transactionId = await repository.createTransaction(
      accountId: sourceAccount,
      categoryId: expenseCategory,
      type: 'expense',
      amountSatang: event.amountSatang,
    );
    repository.execute(
      "UPDATE scheduled_financial_events SET stored_status='fulfilled',linked_transaction_id=? WHERE id=?",
      [transactionId, event.id],
    );
    final fulfilled = (await repository.scheduledEvents()).single;
    expect(
      fulfilled.effectiveStatus(DateTime.utc(2030)),
      ScheduledEventState.fulfilled,
    );
    await expectLater(
      repository.updateScheduledEvent(
        id: event.id,
        eventType: ScheduledEventType.expense,
        amountSatang: 1,
        title: 'Cannot edit',
        accountId: sourceAccount,
        categoryId: expenseCategory,
        scheduledAt: DateTime.utc(2026, 8, 25),
      ),
      throwsStateError,
    );
  });

  test('active and derived-due events remain editable', () async {
    final event = await expense(scheduledAt: DateTime.utc(2026, 8, 1));
    expect(
      event.effectiveStatus(DateTime.utc(2026, 8, 20)),
      ScheduledEventState.due,
    );
    final updated = await repository.updateScheduledEvent(
      id: event.id,
      eventType: ScheduledEventType.expense,
      amountSatang: 200000,
      title: 'Updated dentist',
      accountId: sourceAccount,
      categoryId: expenseCategory,
      note: 'new note',
      scheduledAt: DateTime.utc(2026, 8, 25),
      dueAt: DateTime.utc(2026, 8, 26),
    );
    expect(updated.amountSatang, 200000);
    expect(updated.title, 'Updated dentist');
    expect(updated.note, 'new note');
    expect(updated.dueAt, DateTime.utc(2026, 8, 26));
  });

  test('update revalidates transfer and category invariants', () async {
    final event = await repository.createScheduledEvent(
      eventType: ScheduledEventType.transfer,
      amountSatang: 10000,
      title: 'Transfer',
      accountId: sourceAccount,
      destinationAccountId: destinationAccount,
      scheduledAt: DateTime.utc(2026, 8, 24),
    );
    await expectLater(
      repository.updateScheduledEvent(
        id: event.id,
        eventType: ScheduledEventType.transfer,
        amountSatang: 10000,
        title: 'Invalid',
        accountId: sourceAccount,
        destinationAccountId: sourceAccount,
        scheduledAt: event.scheduledAt,
      ),
      throwsArgumentError,
    );
    await expectLater(
      repository.updateScheduledEvent(
        id: event.id,
        eventType: ScheduledEventType.income,
        amountSatang: 10000,
        title: 'Wrong category',
        accountId: sourceAccount,
        categoryId: expenseCategory,
        scheduledAt: event.scheduledAt,
      ),
      throwsStateError,
    );
  });

  test('query filters date range account and stored status', () async {
    final first = await expense(scheduledAt: DateTime.utc(2026, 8, 10));
    final second = await repository.createScheduledEvent(
      eventType: ScheduledEventType.transfer,
      amountSatang: 10000,
      title: 'Transfer',
      accountId: sourceAccount,
      destinationAccountId: destinationAccount,
      scheduledAt: DateTime.utc(2026, 8, 20),
    );
    await repository.cancelScheduledEvent(second.id);

    expect(
      (await repository.scheduledEvents(
        from: DateTime.utc(2026, 8, 1),
        to: DateTime.utc(2026, 8, 15),
      )).map((event) => event.id),
      [first.id],
    );
    expect(
      (await repository.scheduledEvents(
        accountId: destinationAccount,
      )).single.id,
      second.id,
    );
    expect(
      (await repository.scheduledEvents(
        statuses: {ScheduledEventStoredState.cancelled},
      )).single.id,
      second.id,
    );
  });

  test('profile isolation applies to reads and all mutations', () async {
    final event = await expense();
    final profileB = await repository.createProfile('B', draft: false);
    await repository.switchProfile(profileB);
    final accountB = await repository.createAccount(
      name: 'B bank',
      type: 'bank',
      openingBalanceSatang: 0,
    );
    final categoryB = await repository.createCategory(
      name: 'B food',
      type: 'expense',
      iconKey: 'restaurant',
    );

    expect(await repository.scheduledEvents(), isEmpty);
    await expectLater(
      repository.updateScheduledEvent(
        id: event.id,
        eventType: ScheduledEventType.expense,
        amountSatang: 100,
        title: 'Cross profile',
        accountId: accountB,
        categoryId: categoryB,
        scheduledAt: DateTime.utc(2026, 8, 24),
      ),
      throwsStateError,
    );
    await expectLater(
      repository.cancelScheduledEvent(event.id),
      throwsStateError,
    );
    await expectLater(
      repository.skipScheduledEvent(event.id),
      throwsStateError,
    );
  });

  test('duplicate generated occurrence remains protected', () async {
    await expense(originId: 'commitment', occurrenceKey: '2026-08');
    await expectLater(
      expense(originId: 'commitment', occurrenceKey: '2026-08'),
      throwsA(isA<SqliteException>()),
    );
  });

  test('scheduled CRUD never creates ledger rows or changes Actual', () async {
    final before = await netWorth();
    final event = await expense();
    await repository.updateScheduledEvent(
      id: event.id,
      eventType: ScheduledEventType.expense,
      amountSatang: 200000,
      title: 'Updated',
      accountId: sourceAccount,
      categoryId: expenseCategory,
      scheduledAt: DateTime.utc(2026, 8, 25),
    );
    await repository.cancelScheduledEvent(event.id);
    final skipped = await expense(title: 'Skipped');
    await repository.skipScheduledEvent(skipped.id);

    expect(await repository.ledgerTransactionCount(), 0);
    expect(await netWorth(), before);
  });
}
