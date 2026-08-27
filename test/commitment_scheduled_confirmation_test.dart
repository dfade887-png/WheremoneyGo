import 'package:flutter_test/flutter_test.dart';
import 'package:ngoen_ku_pai_nai/core/money.dart';
import 'package:ngoen_ku_pai_nai/data/repositories/sqlite_finance_repository.dart';
import 'package:ngoen_ku_pai_nai/domain/financial_rules.dart';
import 'package:ngoen_ku_pai_nai/domain/models/scheduled_financial_event.dart';

void main() {
  late SqliteFinanceRepository repository;
  late String accountId;
  late String categoryId;
  late String commitmentId;
  const installmentId = 'phone-installment';

  setUp(() async {
    repository = SqliteFinanceRepository.memory();
    accountId = await repository.createAccount(
      name: 'SCB',
      type: 'bank',
      openingBalanceSatang: 1000000,
    );
    categoryId = await repository.createCategory(
      name: 'Phone',
      type: 'expense',
      iconKey: 'phone',
    );
    final now = DateTime.now().toUtc().toIso8601String();
    repository.execute(
      '''INSERT INTO installments(id,category_id,name,amount_satang,due_day,start_date,total_payable_satang,regular_payment_satang,status,created_at,updated_at,profile_id)
         VALUES(?,?,?,?,?,?,?,?,?,?,?,?)''',
      [
        installmentId,
        categoryId,
        'Phone',
        150000,
        25,
        '2026-01-01',
        600000,
        150000,
        'active',
        now,
        now,
        repository.activeProfileId,
      ],
    );
    commitmentId = await repository.createCommitment(
      name: 'Phone installment',
      type: 'fixed_total',
      totalSatang: 600000,
      regularSatang: 150000,
      accountId: accountId,
      categoryId: categoryId,
    );
    repository.execute(
      'UPDATE commitments SET legacy_installment_id=? WHERE id=?',
      [installmentId, commitmentId],
    );
  });

  tearDown(() => repository.dispose());

  Future<String> projectOccurrence() async {
    final now = DateTime.now().toUtc().toIso8601String();
    repository.execute(
      '''INSERT INTO commitment_occurrences(id,installment_id,due_date,planned_amount_satang,created_at,updated_at,profile_id)
         VALUES('aug',?,'2026-08-25',150000,?,?,?)''',
      [installmentId, now, now, repository.activeProfileId],
    );
    await repository.projectCommitmentOccurrencesToScheduledEvents();
    return (await repository.scheduledEvents()).single.id;
  }

  Future<int> actual() async =>
      (await repository.accounts()).singleWhere(
            (row) => row['id'] == accountId,
          )['balance_satang']
          as int;

  test('confirmation creates real payment and links every layer', () async {
    final eventId = await projectOccurrence();
    final occurredAt = DateTime.utc(2026, 8, 26, 10, 15);

    final transactionId = await repository.confirmScheduledEvent(
      eventId,
      occurredAt: occurredAt,
    );

    final transaction = repository.query(
      'SELECT * FROM transactions WHERE id=?',
      [transactionId],
    ).single;
    expect(transaction['type'], 'expense');
    expect(transaction['amount_satang'], 150000);
    expect(transaction['account_id'], accountId);
    expect(transaction['category_id'], categoryId);
    expect(transaction['source'], 'scheduled_event');
    expect(transaction['occurred_at'], occurredAt.toIso8601String());
    expect(transaction['posted_at'], occurredAt.toIso8601String());
    expect(
      repository
          .query(
            "SELECT linked_transaction_id FROM commitment_occurrences WHERE id='aug'",
          )
          .single['linked_transaction_id'],
      transactionId,
    );
    final payment = repository.query(
      'SELECT * FROM commitment_payments WHERE transaction_id=?',
      [transactionId],
    ).single;
    expect(payment['commitment_id'], commitmentId);
    expect(payment['profile_id'], repository.activeProfileId);
    final event = (await repository.scheduledEvents()).single;
    expect(event.linkedTransactionId, transactionId);
    expect(event.storedStatus.name, 'fulfilled');
    expect(await actual(), 850000);
    expect(await repository.commitmentPaidSatang(commitmentId), 150000);
  });

  test('progress moves from 25 to 50 percent after real payment', () async {
    await repository.recordCommitmentPayment(
      commitmentId: commitmentId,
      accountId: accountId,
      categoryId: categoryId,
      amountSatang: 150000,
    );
    final before = FinancialRules.installmentProgress(
      totalPayable: Money.fromSatang(600000),
      regularPayment: Money.fromSatang(150000),
      confirmedPayments: [Money.fromSatang(150000)],
      linkedRefunds: const [],
    );
    expect(before.progressRatio, .25);
    final eventId = await projectOccurrence();
    await repository.confirmScheduledEvent(eventId);
    final paid = await repository.commitmentPaidSatang(commitmentId);
    final after = FinancialRules.installmentProgress(
      totalPayable: Money.fromSatang(600000),
      regularPayment: Money.fromSatang(150000),
      confirmedPayments: [Money.fromSatang(paid)],
      linkedRefunds: const [],
    );
    expect(paid, 300000);
    expect(after.progressRatio, .5);
  });

  test('Actual and Projected converge without double subtraction', () async {
    final eventId = await projectOccurrence();
    final before = await repository.projectedBalance(
      cutoff: DateTime.utc(2026, 8, 25),
    );
    expect(before.account(accountId).actualBalanceSatang, 1000000);
    expect(before.account(accountId).projectedBalanceSatang, 850000);

    await repository.confirmScheduledEvent(eventId);
    final after = await repository.projectedBalance(
      cutoff: DateTime.utc(2026, 8, 25),
    );
    expect(after.account(accountId).actualBalanceSatang, 850000);
    expect(after.account(accountId).projectedBalanceSatang, 850000);
  });

  test('double confirmation is idempotent across payment domain', () async {
    final eventId = await projectOccurrence();
    final first = await repository.confirmScheduledEvent(eventId);
    final second = await repository.confirmScheduledEvent(eventId);
    expect(second, first);
    expect(await repository.ledgerTransactionCount(), 1);
    expect(await repository.dumpTable('commitment_payments'), hasLength(1));
    expect(await repository.commitmentPaidSatang(commitmentId), 150000);
  });

  test('failure after transaction rolls back every layer', () async {
    final eventId = await projectOccurrence();
    await expectLater(
      repository.confirmScheduledEvent(eventId, failAfterLedgerInsert: true),
      throwsStateError,
    );
    _expectUnchanged(repository);
    expect(await actual(), 1000000);
  });

  test('failure after occurrence link rolls back every layer', () async {
    final eventId = await projectOccurrence();
    await expectLater(
      repository.confirmScheduledEvent(eventId, failAfterOccurrenceLink: true),
      throwsStateError,
    );
    _expectUnchanged(repository);
    expect(await actual(), 1000000);
  });

  test('failure after payment creation rolls back every layer', () async {
    final eventId = await projectOccurrence();
    await expectLater(
      repository.confirmScheduledEvent(
        eventId,
        failAfterCommitmentPayment: true,
      ),
      throwsStateError,
    );
    _expectUnchanged(repository);
    expect(await actual(), 1000000);
  });

  test('existing linked real payment is reused without duplicate', () async {
    final eventId = await projectOccurrence();
    final transactionId = await repository.createTransaction(
      accountId: accountId,
      categoryId: categoryId,
      type: 'expense',
      amountSatang: 150000,
    );
    repository.execute(
      "UPDATE commitment_occurrences SET linked_transaction_id=? WHERE id='aug'",
      [transactionId],
    );
    final returned = await repository.confirmScheduledEvent(eventId);
    expect(returned, transactionId);
    expect(await repository.ledgerTransactionCount(), 1);
    expect(await repository.dumpTable('commitment_payments'), hasLength(1));
  });

  test(
    'amount mismatch and inactive parents reject with zero writes',
    () async {
      final eventId = await projectOccurrence();
      repository.execute(
        'UPDATE scheduled_financial_events SET amount_satang=170000 WHERE id=?',
        [eventId],
      );
      await expectLater(
        repository.confirmScheduledEvent(eventId),
        throwsStateError,
      );
      _expectUnchanged(repository);
      repository.execute(
        'UPDATE scheduled_financial_events SET amount_satang=150000 WHERE id=?',
        [eventId],
      );
      for (final status in ['paused', 'completed', 'archived']) {
        repository.execute('UPDATE commitments SET status=? WHERE id=?', [
          status,
          commitmentId,
        ]);
        await expectLater(
          repository.confirmScheduledEvent(eventId),
          throwsStateError,
        );
        _expectUnchanged(repository);
      }
      repository.execute(
        "UPDATE commitments SET status='active',deleted_at=? WHERE id=?",
        [DateTime.now().toUtc().toIso8601String(), commitmentId],
      );
      await expectLater(
        repository.confirmScheduledEvent(eventId),
        throwsStateError,
      );
      _expectUnchanged(repository);
    },
  );

  test('cross-profile confirmation writes nothing', () async {
    final eventId = await projectOccurrence();
    final profileB = await repository.createProfile('B', draft: false);
    await repository.switchProfile(profileB);
    await expectLater(
      repository.confirmScheduledEvent(eventId),
      throwsStateError,
    );
    expect(await repository.ledgerTransactionCount(), 0);
    expect(await repository.dumpTable('commitment_payments'), isEmpty);
  });

  test('generic scheduled expense creates no commitment payment', () async {
    final event = await repository.createScheduledEvent(
      eventType: ScheduledEventType.expense,
      amountSatang: 10000,
      title: 'Generic',
      accountId: accountId,
      categoryId: categoryId,
      scheduledAt: DateTime.utc(2026, 8, 25),
    );
    await repository.confirmScheduledEvent(event.id);
    expect(await repository.dumpTable('commitment_payments'), isEmpty);
  });
}

void _expectUnchanged(SqliteFinanceRepository repository) {
  expect(repository.query('SELECT * FROM transactions'), isEmpty);
  expect(repository.query('SELECT * FROM commitment_payments'), isEmpty);
  expect(
    repository
        .query(
          "SELECT linked_transaction_id FROM commitment_occurrences WHERE id='aug'",
        )
        .single['linked_transaction_id'],
    isNull,
  );
  expect(
    repository
        .query(
          'SELECT stored_status,linked_transaction_id FROM scheduled_financial_events',
        )
        .single,
    containsPair('stored_status', 'scheduled'),
  );
}
