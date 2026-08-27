import 'package:flutter_test/flutter_test.dart';
import 'package:ngoen_ku_pai_nai/data/repositories/sqlite_finance_repository.dart';
import 'package:ngoen_ku_pai_nai/domain/models/scheduled_financial_event.dart';
import 'package:ngoen_ku_pai_nai/domain/transaction_lifecycle.dart';

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
        100000,
        25,
        '2026-01-01',
        1200000,
        100000,
        'active',
        now,
        now,
        repository.activeProfileId,
      ],
    );
    commitmentId = await repository.createCommitment(
      name: 'Phone installment',
      type: 'fixed_total',
      totalSatang: 1200000,
      regularSatang: 100000,
      accountId: accountId,
      categoryId: categoryId,
    );
    repository.execute(
      'UPDATE commitments SET legacy_installment_id=? WHERE id=?',
      [installmentId, commitmentId],
    );
  });

  tearDown(() => repository.dispose());

  void occurrence(
    String id, {
    int amount = 100000,
    String due = '2026-08-25',
    bool skipped = false,
    String? transactionId,
  }) {
    final now = DateTime.now().toUtc().toIso8601String();
    repository.execute(
      '''INSERT INTO commitment_occurrences(
           id,installment_id,due_date,planned_amount_satang,linked_transaction_id,is_skipped,
           created_at,updated_at,profile_id)
         VALUES(?,?,?,?,?,?,?,?,?)''',
      [
        id,
        installmentId,
        due,
        amount,
        transactionId,
        skipped ? 1 : 0,
        now,
        now,
        repository.activeProfileId,
      ],
    );
  }

  test('one unpaid occurrence maps exactly to one scheduled expense', () async {
    occurrence('aug', amount: 150000, due: '2026-08-24');
    final result = await repository
        .projectCommitmentOccurrencesToScheduledEvents();
    expect(result.createdCount, 1);
    final event = (await repository.scheduledEvents()).single;
    expect(event.eventType, ScheduledEventType.expense);
    expect(event.amountSatang, 150000);
    expect(event.accountId, accountId);
    expect(event.categoryId, categoryId);
    expect(event.title, 'Phone installment');
    expect(event.scheduledAt, DateTime.utc(2026, 8, 24));
    expect(event.dueAt, isNull);
    expect(event.originType, 'commitment_occurrence');
    expect(event.originId, 'aug');
    expect(event.occurrenceKey, 'aug');
  });

  test('multiple projection is idempotent', () async {
    occurrence('aug');
    occurrence('sep', due: '2026-09-25');
    occurrence('oct', due: '2026-10-25');
    final first = await repository
        .projectCommitmentOccurrencesToScheduledEvents();
    final second = await repository
        .projectCommitmentOccurrencesToScheduledEvents();
    expect(first.createdCount, 3);
    expect(second.createdCount, 0);
    expect(second.updatedCount, 0);
    expect(await repository.scheduledEvents(), hasLength(3));
  });

  test('skip before projection creates no event', () async {
    occurrence('aug', skipped: true);
    final result = await repository
        .projectCommitmentOccurrencesToScheduledEvents();
    expect(result.createdCount, 0);
    expect(await repository.scheduledEvents(), isEmpty);
  });

  test('skip after projection marks active event skipped', () async {
    occurrence('aug');
    await repository.projectCommitmentOccurrencesToScheduledEvents();
    repository.execute(
      'UPDATE commitment_occurrences SET is_skipped=1 WHERE id=?',
      ['aug'],
    );
    final result = await repository
        .projectCommitmentOccurrencesToScheduledEvents();
    expect(result.skippedCount, 1);
    expect(
      (await repository.scheduledEvents()).single.storedStatus,
      ScheduledEventStoredState.skipped,
    );
  });

  test('active reprojection updates amount and due date', () async {
    occurrence('aug');
    await repository.projectCommitmentOccurrencesToScheduledEvents();
    repository.execute(
      "UPDATE commitment_occurrences SET planned_amount_satang=170000,due_date='2026-08-26' WHERE id='aug'",
    );
    final result = await repository
        .projectCommitmentOccurrencesToScheduledEvents();
    final event = (await repository.scheduledEvents()).single;
    expect(result.updatedCount, 1);
    expect(event.amountSatang, 170000);
    expect(event.scheduledAt, DateTime.utc(2026, 8, 26));
  });

  test('fulfilled event history is protected from occurrence edits', () async {
    occurrence('aug');
    await repository.projectCommitmentOccurrencesToScheduledEvents();
    final event = (await repository.scheduledEvents()).single;
    await repository.confirmScheduledEvent(event.id);
    repository.execute(
      'UPDATE commitment_occurrences SET planned_amount_satang=170000 WHERE id=?',
      ['aug'],
    );
    await repository.projectCommitmentOccurrencesToScheduledEvents();
    final unchanged = (await repository.scheduledEvents()).single;
    expect(unchanged.storedStatus, ScheduledEventStoredState.fulfilled);
    expect(unchanged.amountSatang, 100000);
  });

  test(
    'inactive parent creates no active projection and cancels existing',
    () async {
      occurrence('aug');
      await repository.projectCommitmentOccurrencesToScheduledEvents();
      repository.execute("UPDATE commitments SET status='paused' WHERE id=?", [
        commitmentId,
      ]);
      await repository.projectCommitmentOccurrencesToScheduledEvents();
      expect(
        (await repository.scheduledEvents()).single.storedStatus,
        ScheduledEventStoredState.cancelled,
      );
    },
  );

  test('linked paid occurrence creates no duplicate active event', () async {
    final transactionId = await repository.createTransaction(
      accountId: accountId,
      categoryId: categoryId,
      type: 'expense',
      amountSatang: 100000,
    );
    occurrence('aug', transactionId: transactionId);
    final result = await repository
        .projectCommitmentOccurrencesToScheduledEvents();
    expect(result.createdCount, 0);
    expect(await repository.scheduledEvents(), isEmpty);
  });

  test('linked occurrence reconciles an existing active event', () async {
    occurrence('aug');
    await repository.projectCommitmentOccurrencesToScheduledEvents();
    final transactionId = await repository.createTransaction(
      accountId: accountId,
      categoryId: categoryId,
      type: 'expense',
      amountSatang: 100000,
    );
    repository.execute(
      'UPDATE commitment_occurrences SET linked_transaction_id=? WHERE id=?',
      [transactionId, 'aug'],
    );

    final result = await repository
        .projectCommitmentOccurrencesToScheduledEvents();

    final event = (await repository.scheduledEvents()).single;
    expect(result.fulfilledCount, 1);
    expect(event.storedStatus, ScheduledEventStoredState.fulfilled);
    expect(event.linkedTransactionId, transactionId);
  });

  test(
    'projection affects Projected once but not Actual or progress',
    () async {
      occurrence('aug', amount: 150000);
      final actualBefore = (await repository.accounts()).singleWhere(
        (row) => row['id'] == accountId,
      )['balance_satang'];
      final paidBefore = await repository.commitmentPaidSatang(commitmentId);

      await repository.projectCommitmentOccurrencesToScheduledEvents();
      final projected = await repository.projectedBalance(
        cutoff: DateTime.utc(2026, 8, 25),
      );

      expect(projected.account(accountId).actualBalanceSatang, 1000000);
      expect(projected.account(accountId).projectedBalanceSatang, 850000);
      expect(
        (await repository.accounts()).singleWhere(
          (row) => row['id'] == accountId,
        )['balance_satang'],
        actualBefore,
      );
      expect(await repository.commitmentPaidSatang(commitmentId), paidBefore);
      expect(await repository.ledgerTransactionCount(), 0);
      expect(await repository.dumpTable('commitment_payments'), isEmpty);
    },
  );

  test('profile isolation prevents cross-profile projection', () async {
    occurrence('aug');
    final profileB = await repository.createProfile('B', draft: false);
    await repository.switchProfile(profileB);
    final result = await repository
        .projectCommitmentOccurrencesToScheduledEvents();
    expect(result.createdCount, 0);
    expect(await repository.scheduledEvents(), isEmpty);
  });

  test('missing account mapping is reported and never guessed', () async {
    occurrence('aug');
    repository.execute(
      'UPDATE commitments SET default_account_id=NULL WHERE id=?',
      [commitmentId],
    );
    final result = await repository
        .projectCommitmentOccurrencesToScheduledEvents();
    expect(result.unresolvedOccurrenceIds, ['aug']);
    expect(await repository.scheduledEvents(), isEmpty);
  });
}
