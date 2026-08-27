import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ngoen_ku_pai_nai/data/repositories/sqlite_finance_repository.dart';
import 'package:ngoen_ku_pai_nai/domain/candidate_matching.dart';
import 'package:ngoen_ku_pai_nai/domain/models/scheduled_financial_event.dart';
import 'package:ngoen_ku_pai_nai/ui/candidate_inbox_controller.dart';
import 'package:ngoen_ku_pai_nai/ui/candidate_inbox_screen.dart';

void main() {
  late SqliteFinanceRepository repository;
  late String accountA, accountB, expenseCategory, incomeCategory;
  var sequence = 0;

  setUp(() async {
    repository = SqliteFinanceRepository.memory();
    accountA = await repository.createAccount(
      name: 'SCB',
      type: 'bank',
      openingBalanceSatang: 1000000,
    );
    accountB = await repository.createAccount(
      name: 'KBank',
      type: 'bank',
      openingBalanceSatang: 500000,
    );
    expenseCategory = await repository.createCategory(
      name: 'รายจ่าย',
      type: 'expense',
      iconKey: 'expense',
    );
    incomeCategory = await repository.createCategory(
      name: 'รายรับ',
      type: 'income',
      iconKey: 'income',
    );
  });
  tearDown(() => repository.dispose());

  String candidate({
    required String type,
    required int amount,
    required DateTime at,
    String? account,
    String? destination,
    String? category,
    String? profile,
  }) {
    final id = 'three-way-${sequence++}';
    final now = DateTime.now().toUtc().toIso8601String();
    repository.execute(
      '''INSERT INTO transaction_candidates(id,profile_id,account_id,destination_account_id,
         category_id,candidate_type,amount_satang,occurred_at,confidence,created_at,updated_at)
         VALUES(?,?,?,?,?,?,?,?,?,?,?)''',
      [
        id,
        profile ?? repository.activeProfileId,
        account ?? accountA,
        destination,
        category,
        type,
        amount,
        at.toUtc().toIso8601String(),
        0.9,
        now,
        now,
      ],
    );
    return id;
  }

  Future<({String candidateId, String transactionId, String eventId})>
  setupNonTransfer({
    String type = 'expense',
    int amount = 150000,
    String? transactionAccount,
    String? eventAccount,
    String? candidateAccount,
  }) async {
    final at = DateTime.now().toUtc();
    final category = type == 'income' ? incomeCategory : expenseCategory;
    final transactionId = await repository.createTransaction(
      accountId: transactionAccount ?? accountA,
      categoryId: category,
      type: type,
      amountSatang: amount,
      occurredAt: at,
    );
    final event = await repository.createScheduledEvent(
      eventType: ScheduledEventType.values.byName(type),
      amountSatang: amount,
      title: type,
      accountId: eventAccount ?? accountA,
      categoryId: category,
      scheduledAt: at,
    );
    return (
      candidateId: candidate(
        type: type,
        amount: amount,
        at: at,
        account: candidateAccount ?? accountA,
        category: category,
      ),
      transactionId: transactionId,
      eventId: event.id,
    );
  }

  Future<void> reconcile(
    ({String candidateId, String transactionId, String eventId}) data,
  ) => repository.reconcileCandidateExistingAndScheduled(
    data.candidateId,
    CandidateMatchTargetType.transaction,
    data.transactionId,
    data.eventId,
  );

  test(
    '1 expense reuses existing ledger and links both candidate targets',
    () async {
      final data = await setupNonTransfer();
      final before = await repository.ledgerTransactionCount();
      await reconcile(data);
      expect(await repository.ledgerTransactionCount(), before);
      expect(
        repository
            .query(
              'SELECT review_status,matched_transaction_id,matched_scheduled_event_id FROM transaction_candidates',
            )
            .single,
        containsPair('matched_transaction_id', data.transactionId),
      );
      expect(
        repository
            .query(
              'SELECT stored_status,linked_transaction_id FROM scheduled_financial_events',
            )
            .single,
        containsPair('linked_transaction_id', data.transactionId),
      );
    },
  );

  test('2 salary income reuses existing income', () async {
    final data = await setupNonTransfer(type: 'income', amount: 5000000);
    await reconcile(data);
    expect(
      repository
          .query("SELECT COUNT(*) count FROM transactions WHERE type='income'")
          .single['count'],
      1,
    );
  });

  test('3 refund reuses existing refund', () async {
    final data = await setupNonTransfer(type: 'refund', amount: 40000);
    await reconcile(data);
    expect(
      repository
          .query("SELECT COUNT(*) count FROM transactions WHERE type='refund'")
          .single['count'],
      1,
    );
  });

  test('4 Actual unchanged', () async {
    final data = await setupNonTransfer();
    final before = (await repository.accounts()).singleWhere(
      (a) => a['id'] == accountA,
    )['balance_satang'];
    await reconcile(data);
    final after = (await repository.accounts()).singleWhere(
      (a) => a['id'] == accountA,
    )['balance_satang'];
    expect(after, before);
  });

  test('5 Projected removes stale scheduled expense', () async {
    final data = await setupNonTransfer();
    final cutoff = DateTime.now().toUtc().add(const Duration(days: 1));
    final before = await repository.projectedBalance(cutoff: cutoff);
    expect(before.account(accountA).projectedBalanceSatang, 700000);
    await reconcile(data);
    final after = await repository.projectedBalance(cutoff: cutoff);
    expect(after.account(accountA).actualBalanceSatang, 850000);
    expect(after.account(accountA).projectedBalanceSatang, 850000);
  });

  test('6 retry is idempotent', () async {
    final data = await setupNonTransfer();
    await reconcile(data);
    await reconcile(data);
    expect(await repository.ledgerTransactionCount(), 1);
  });

  test('7 deleted existing transaction rejects with no writes', () async {
    final data = await setupNonTransfer();
    await repository.softDeleteTransaction(data.transactionId);
    await expectLater(reconcile(data), throwsStateError);
    expect(
      repository
          .query('SELECT review_status FROM transaction_candidates')
          .single['review_status'],
      'pending_review',
    );
    expect(
      repository
          .query('SELECT stored_status FROM scheduled_financial_events')
          .single['stored_status'],
      'scheduled',
    );
  });

  test('8 terminal scheduled event rejects', () async {
    final data = await setupNonTransfer();
    await repository.cancelScheduledEvent(data.eventId);
    await expectLater(reconcile(data), throwsStateError);
  });

  test('9 amount mismatch rejects', () async {
    final data = await setupNonTransfer();
    repository.execute(
      'UPDATE scheduled_financial_events SET amount_satang=149999 WHERE id=?',
      [data.eventId],
    );
    await expectLater(reconcile(data), throwsStateError);
  });

  test('10 account mismatch rejects', () async {
    final data = await setupNonTransfer(eventAccount: accountB);
    await expectLater(reconcile(data), throwsStateError);
  });

  test('11 profile isolation rejects foreign candidate', () async {
    final data = await setupNonTransfer();
    final other = await repository.createProfile('อื่น');
    repository.execute(
      'UPDATE transaction_candidates SET profile_id=? WHERE id=?',
      [other, data.candidateId],
    );
    await expectLater(reconcile(data), throwsStateError);
  });

  test('12 existing transaction linked to another schedule conflicts', () async {
    final data = await setupNonTransfer();
    final other = await repository.createScheduledEvent(
      eventType: ScheduledEventType.expense,
      amountSatang: 150000,
      title: 'อื่น',
      accountId: accountA,
      categoryId: expenseCategory,
      scheduledAt: DateTime.now(),
    );
    repository.execute(
      "UPDATE scheduled_financial_events SET stored_status='fulfilled',linked_transaction_id=? WHERE id=?",
      [data.transactionId, other.id],
    );
    await expectLater(reconcile(data), throwsStateError);
  });

  test('13 failure after scheduled link rolls everything back', () async {
    final data = await setupNonTransfer();
    await expectLater(
      repository.reconcileCandidateExistingAndScheduled(
        data.candidateId,
        CandidateMatchTargetType.transaction,
        data.transactionId,
        data.eventId,
        failAfterScheduledLink: true,
      ),
      throwsStateError,
    );
    expect(
      repository.query(
        'SELECT stored_status FROM scheduled_financial_events WHERE id=?',
        [data.eventId],
      ).single['stored_status'],
      'scheduled',
    );
    expect(
      repository
          .query('SELECT review_status FROM transaction_candidates')
          .single['review_status'],
      'pending_review',
    );
  });

  test('14 existing-only T16 leaves scheduled active', () async {
    final data = await setupNonTransfer();
    await repository.resolveCandidateAsExisting(
      data.candidateId,
      CandidateMatchTargetType.transaction,
      data.transactionId,
    );
    expect(
      repository
          .query('SELECT stored_status FROM scheduled_financial_events')
          .single['stored_status'],
      'scheduled',
    );
  });

  test('15 transfer reuses pair and links scheduled group', () async {
    final at = DateTime.now().toUtc();
    final group = await repository.createTransfer(
      fromAccountId: accountA,
      toAccountId: accountB,
      amountSatang: 25000,
    );
    final event = await repository.createScheduledEvent(
      eventType: ScheduledEventType.transfer,
      amountSatang: 25000,
      title: 'โอน',
      accountId: accountA,
      destinationAccountId: accountB,
      scheduledAt: at,
    );
    final id = candidate(
      type: 'transfer',
      amount: 25000,
      at: at,
      destination: accountB,
    );
    await repository.reconcileCandidateExistingAndScheduled(
      id,
      CandidateMatchTargetType.transferGroup,
      group,
      event.id,
    );
    expect(await repository.ledgerTransactionCount(), 2);
    expect(
      repository
          .query(
            'SELECT linked_transfer_group_id FROM scheduled_financial_events',
          )
          .single['linked_transfer_group_id'],
      group,
    );
    expect(
      repository
          .query('SELECT matched_transaction_id FROM transaction_candidates')
          .single['matched_transaction_id'],
      isNull,
    );
  });

  test('16 transfer rollback restores scheduled and candidate', () async {
    final at = DateTime.now().toUtc();
    final group = await repository.createTransfer(
      fromAccountId: accountA,
      toAccountId: accountB,
      amountSatang: 25000,
    );
    final event = await repository.createScheduledEvent(
      eventType: ScheduledEventType.transfer,
      amountSatang: 25000,
      title: 'โอน',
      accountId: accountA,
      destinationAccountId: accountB,
      scheduledAt: at,
    );
    final id = candidate(
      type: 'transfer',
      amount: 25000,
      at: at,
      destination: accountB,
    );
    await expectLater(
      repository.reconcileCandidateExistingAndScheduled(
        id,
        CandidateMatchTargetType.transferGroup,
        group,
        event.id,
        failAfterScheduledLink: true,
      ),
      throwsStateError,
    );
    expect(
      repository
          .query('SELECT stored_status FROM scheduled_financial_events')
          .single['stored_status'],
      'scheduled',
    );
  });

  test('17 commitment reuses transaction and creates one payment', () async {
    final at = DateTime.now().toUtc();
    final stamp = at.toIso8601String();
    repository.execute(
      '''INSERT INTO installments(id,category_id,name,amount_satang,due_day,start_date,total_payable_satang,
         regular_payment_satang,status,created_at,updated_at,profile_id)
         VALUES('installment-three',?,'โทรศัพท์',150000,27,'2026-01-01',600000,150000,'active',?,?,?)''',
      [expenseCategory, stamp, stamp, repository.activeProfileId],
    );
    final commitment = await repository.createCommitment(
      name: 'โทรศัพท์',
      type: 'fixed_total',
      totalSatang: 600000,
      regularSatang: 150000,
      accountId: accountA,
      categoryId: expenseCategory,
    );
    repository.execute(
      'UPDATE commitments SET legacy_installment_id=? WHERE id=?',
      ['installment-three', commitment],
    );
    repository.execute(
      '''INSERT INTO commitment_occurrences(id,installment_id,due_date,planned_amount_satang,
         created_at,updated_at,profile_id) VALUES('occ-three','installment-three',?,150000,?,?,?)''',
      [stamp.split('T').first, stamp, stamp, repository.activeProfileId],
    );
    await repository.projectCommitmentOccurrencesToScheduledEvents();
    final event = (await repository.scheduledEvents()).single;
    final transaction = await repository.createTransaction(
      accountId: accountA,
      categoryId: expenseCategory,
      type: 'expense',
      amountSatang: 150000,
      occurredAt: at,
    );
    final id = candidate(
      type: 'expense',
      amount: 150000,
      at: at,
      category: expenseCategory,
    );
    await expectLater(
      repository.reconcileCandidateExistingAndScheduled(
        id,
        CandidateMatchTargetType.transaction,
        transaction,
        event.id,
        failAfterCommitmentLink: true,
      ),
      throwsStateError,
    );
    expect(
      repository.query(
        'SELECT * FROM commitment_payments WHERE transaction_id=?',
        [transaction],
      ),
      isEmpty,
    );
    expect(
      repository
          .query(
            "SELECT linked_transaction_id FROM commitment_occurrences WHERE id='occ-three'",
          )
          .single['linked_transaction_id'],
      isNull,
    );
    await repository.reconcileCandidateExistingAndScheduled(
      id,
      CandidateMatchTargetType.transaction,
      transaction,
      event.id,
    );
    expect(
      repository.query(
        'SELECT * FROM commitment_payments WHERE transaction_id=?',
        [transaction],
      ),
      hasLength(1),
    );
    expect(await repository.ledgerTransactionCount(), 1);
  });

  testWidgets(
    '18 UI shows explicit three-way action only for compatible pair',
    (tester) async {
      final data = await setupNonTransfer();
      final controller = CandidateInboxController(repository);
      await tester.pumpWidget(
        MaterialApp(home: CandidateInboxScreen(controller: controller)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('ตรวจสอบ'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('candidate-reconcile-all')), findsOneWidget);
      expect(find.text('ยืนยันว่าเป็นรายการเดียวกันทั้งหมด'), findsOneWidget);
      expect(data.eventId, isNotEmpty);
    },
  );
}
