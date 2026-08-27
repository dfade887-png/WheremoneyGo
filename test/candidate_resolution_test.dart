import 'package:flutter_test/flutter_test.dart';
import 'package:ngoen_ku_pai_nai/data/repositories/sqlite_finance_repository.dart';
import 'package:ngoen_ku_pai_nai/domain/candidate_matching.dart';
import 'package:ngoen_ku_pai_nai/domain/models/scheduled_financial_event.dart';

void main() {
  late SqliteFinanceRepository repository;
  late String accountId;
  late String secondAccountId;
  late String expenseCategoryId;
  late String incomeCategoryId;
  var sequence = 0;

  setUp(() async {
    repository = SqliteFinanceRepository.memory();
    accountId = await repository.createAccount(
      name: 'SCB',
      type: 'bank',
      openingBalanceSatang: 1000000,
    );
    secondAccountId = await repository.createAccount(
      name: 'KBank',
      type: 'bank',
      openingBalanceSatang: 500000,
    );
    expenseCategoryId = await repository.createCategory(
      name: 'อาหาร',
      type: 'expense',
      iconKey: 'food',
    );
    incomeCategoryId = await repository.createCategory(
      name: 'เงินเดือน',
      type: 'income',
      iconKey: 'salary',
    );
  });

  tearDown(() => repository.dispose());

  String addCandidate({
    String type = 'expense',
    int amount = 12000,
    DateTime? occurredAt,
    String? account,
    String? destination,
    String? category,
    String? profile,
  }) {
    final id = 'candidate-${sequence++}';
    final now = DateTime.now().toUtc().toIso8601String();
    repository.execute(
      '''INSERT INTO transaction_candidates(
        id,profile_id,account_id,destination_account_id,category_id,candidate_type,
        amount_satang,occurred_at,confidence,created_at,updated_at)
        VALUES(?,?,?,?,?,?,?,?,?,?,?)''',
      [
        id,
        profile ?? repository.activeProfileId,
        account ?? accountId,
        destination,
        category,
        type,
        amount,
        (occurredAt ?? DateTime.now()).toUtc().toIso8601String(),
        0.9,
        now,
        now,
      ],
    );
    return id;
  }

  test(
    'existing resolution links without another financial write and is idempotent',
    () async {
      final occurredAt = DateTime.now().toUtc();
      final transactionId = await repository.createTransaction(
        accountId: accountId,
        categoryId: expenseCategoryId,
        type: 'expense',
        amountSatang: 12000,
        occurredAt: occurredAt,
      );
      final candidateId = addCandidate(
        category: expenseCategoryId,
        occurredAt: occurredAt,
      );
      final before = await repository.ledgerTransactionCount();

      final first = await repository.resolveCandidateAsExisting(
        candidateId,
        CandidateMatchTargetType.transaction,
        transactionId,
      );
      final second = await repository.resolveCandidateAsExisting(
        candidateId,
        CandidateMatchTargetType.transaction,
        transactionId,
      );

      expect(first.status, 'matched_existing');
      expect(second.transactionId, transactionId);
      expect(await repository.ledgerTransactionCount(), before);
      expect(
        repository.query(
          'SELECT review_status FROM transaction_candidates WHERE id=?',
          [candidateId],
        ).single['review_status'],
        'matched_existing',
      );
    },
  );

  test('create new expense posts once and uses confirmed_new', () async {
    final candidateId = addCandidate(category: expenseCategoryId);
    final first = await repository.createTransactionFromCandidate(candidateId);
    await repository.createTransactionFromCandidate(candidateId);
    expect(first.transactionId, isNotNull);
    expect(await repository.ledgerTransactionCount(), 1);
    final row = repository.query('SELECT * FROM transactions').single;
    expect(row['source'], 'notification_candidate');
    expect(row['status'], 'confirmed');
    expect(row['posted_at'], row['occurred_at']);
    expect(
      repository
          .query('SELECT review_status FROM transaction_candidates')
          .single['review_status'],
      'confirmed_new',
    );
  });

  test('create new income posts once', () async {
    final id = addCandidate(
      type: 'income',
      amount: 5000000,
      category: incomeCategoryId,
    );
    await repository.createTransactionFromCandidate(id);
    expect(
      repository
          .query(
            "SELECT type,amount_satang FROM transactions WHERE type='income'",
          )
          .single['amount_satang'],
      5000000,
    );
  });

  test('missing category is rejected without a financial write', () async {
    final id = addCandidate(category: null);
    await expectLater(
      repository.createTransactionFromCandidate(id),
      throwsStateError,
    );
    expect(await repository.ledgerTransactionCount(), 0);
    expect(
      repository
          .query('SELECT review_status FROM transaction_candidates')
          .single['review_status'],
      'pending_review',
    );
  });

  test(
    'new transfer creates exactly two rows and double submit is safe',
    () async {
      final id = addCandidate(type: 'transfer', destination: secondAccountId);
      final first = await repository.createTransactionFromCandidate(id);
      await repository.createTransactionFromCandidate(id);
      final rows = repository.query(
        'SELECT * FROM transactions WHERE transfer_group_id=?',
        [first.transferGroupId],
      );
      expect(rows, hasLength(2));
      expect(rows.map((r) => r['type']).toSet(), {
        'transfer_out',
        'transfer_in',
      });
      expect(await repository.ledgerTransactionCount(), 2);
    },
  );

  test('missing transfer destination is rejected', () async {
    final id = addCandidate(type: 'transfer');
    await expectLater(
      repository.createTransactionFromCandidate(id),
      throwsStateError,
    );
    expect(await repository.ledgerTransactionCount(), 0);
  });

  test(
    'scheduled expense confirmation and candidate update are one transaction',
    () async {
      final occurredAt = DateTime.now().toUtc();
      final event = await repository.createScheduledEvent(
        eventType: ScheduledEventType.expense,
        amountSatang: 12000,
        title: 'ทำฟัน',
        accountId: accountId,
        categoryId: expenseCategoryId,
        scheduledAt: occurredAt,
      );
      final id = addCandidate(
        category: expenseCategoryId,
        occurredAt: occurredAt,
      );
      final result = await repository.resolveCandidateAsScheduled(id, event.id);
      expect(result.createdFinancialRecord, isTrue);
      expect(await repository.ledgerTransactionCount(), 1);
      expect(
        repository.query(
          'SELECT stored_status FROM scheduled_financial_events WHERE id=?',
          [event.id],
        ).single['stored_status'],
        'fulfilled',
      );
      expect(
        repository.query(
          'SELECT review_status,matched_scheduled_event_id FROM transaction_candidates WHERE id=?',
          [id],
        ).single,
        containsPair('review_status', 'confirmed_new'),
      );
    },
  );

  test(
    'scheduled rollback removes ledger, fulfillment, and candidate resolution',
    () async {
      final occurredAt = DateTime.now().toUtc();
      final event = await repository.createScheduledEvent(
        eventType: ScheduledEventType.expense,
        amountSatang: 12000,
        title: 'ทำฟัน',
        accountId: accountId,
        categoryId: expenseCategoryId,
        scheduledAt: occurredAt,
      );
      final id = addCandidate(
        category: expenseCategoryId,
        occurredAt: occurredAt,
      );
      await expectLater(
        repository.resolveCandidateAsScheduled(
          id,
          event.id,
          failBeforeCandidateUpdate: true,
        ),
        throwsStateError,
      );
      expect(await repository.ledgerTransactionCount(), 0);
      expect(
        repository.query(
          'SELECT stored_status FROM scheduled_financial_events WHERE id=?',
          [event.id],
        ).single['stored_status'],
        'scheduled',
      );
      expect(
        repository.query(
          'SELECT review_status FROM transaction_candidates WHERE id=?',
          [id],
        ).single['review_status'],
        'pending_review',
      );
    },
  );

  test('salary scheduled candidate increases Actual exactly once', () async {
    final occurredAt = DateTime.now().toUtc();
    final event = await repository.createScheduledEvent(
      eventType: ScheduledEventType.income,
      amountSatang: 5000000,
      title: 'เงินเดือน',
      accountId: accountId,
      categoryId: incomeCategoryId,
      scheduledAt: occurredAt,
      originType: 'salary',
      originId: 'salary-profile',
      occurrenceKey: 'salary-aug',
    );
    final id = addCandidate(
      type: 'income',
      amount: 5000000,
      category: incomeCategoryId,
      occurredAt: occurredAt,
    );
    await repository.resolveCandidateAsScheduled(id, event.id);
    await repository.resolveCandidateAsScheduled(id, event.id);
    expect(
      repository
          .query("SELECT COUNT(*) count FROM transactions WHERE type='income'")
          .single['count'],
      1,
    );
  });

  test('scheduled transfer candidate creates one pair and links event', () async {
    final occurredAt = DateTime.now().toUtc();
    final event = await repository.createScheduledEvent(
      eventType: ScheduledEventType.transfer,
      amountSatang: 25000,
      title: 'ย้ายเงินออม',
      accountId: accountId,
      destinationAccountId: secondAccountId,
      scheduledAt: occurredAt,
    );
    final id = addCandidate(
      type: 'transfer',
      amount: 25000,
      destination: secondAccountId,
      occurredAt: occurredAt,
    );
    final result = await repository.resolveCandidateAsScheduled(id, event.id);
    expect(
      repository.query('SELECT * FROM transactions WHERE transfer_group_id=?', [
        result.transferGroupId,
      ]),
      hasLength(2),
    );
    expect(
      repository.query(
        'SELECT linked_transfer_group_id FROM scheduled_financial_events WHERE id=?',
        [event.id],
      ).single['linked_transfer_group_id'],
      result.transferGroupId,
    );
  });

  test(
    'commitment scheduled candidate links payment and progress atomically',
    () async {
      final now = DateTime.now().toUtc();
      final stamp = now.toIso8601String();
      repository.execute(
        '''INSERT INTO installments(id,category_id,name,amount_satang,due_day,start_date,
         total_payable_satang,regular_payment_satang,status,created_at,updated_at,profile_id)
         VALUES('installment-t16',?,'โทรศัพท์',150000,27,'2026-01-01',600000,150000,
         'active',?,?,?)''',
        [expenseCategoryId, stamp, stamp, repository.activeProfileId],
      );
      final commitment = await repository.createCommitment(
        name: 'ผ่อนโทรศัพท์',
        type: 'fixed_total',
        totalSatang: 600000,
        regularSatang: 150000,
        accountId: accountId,
        categoryId: expenseCategoryId,
      );
      repository.execute(
        'UPDATE commitments SET legacy_installment_id=? WHERE id=?',
        ['installment-t16', commitment],
      );
      repository.execute(
        '''INSERT INTO commitment_occurrences(id,installment_id,due_date,planned_amount_satang,
         created_at,updated_at,profile_id) VALUES('occurrence-t16','installment-t16',?,150000,?,?,?)''',
        [stamp.split('T').first, stamp, stamp, repository.activeProfileId],
      );
      await repository.projectCommitmentOccurrencesToScheduledEvents();
      final event = (await repository.scheduledEvents()).single;
      final id = addCandidate(
        amount: 150000,
        category: expenseCategoryId,
        occurredAt: now,
      );

      final result = await repository.resolveCandidateAsScheduled(id, event.id);
      expect(
        repository.query(
          'SELECT * FROM commitment_payments WHERE transaction_id=?',
          [result.transactionId],
        ),
        hasLength(1),
      );
      expect(
        repository
            .query(
              "SELECT linked_transaction_id FROM commitment_occurrences WHERE id='occurrence-t16'",
            )
            .single['linked_transaction_id'],
        result.transactionId,
      );
      expect(await repository.ledgerTransactionCount(), 1);
    },
  );

  test('new transaction rollback leaves no orphan ledger row', () async {
    final id = addCandidate(category: expenseCategoryId);
    await expectLater(
      repository.createTransactionFromCandidate(
        id,
        failBeforeCandidateUpdate: true,
      ),
      throwsStateError,
    );
    expect(await repository.ledgerTransactionCount(), 0);
  });

  test('ignore changes candidate only', () async {
    final id = addCandidate();
    await repository.ignoreCandidate(id);
    await repository.ignoreCandidate(id);
    expect(await repository.ledgerTransactionCount(), 0);
    expect(
      repository
          .query('SELECT review_status,resolved_at FROM transaction_candidates')
          .single,
      containsPair('review_status', 'ignored'),
    );
  });

  test(
    'stale scheduled target is rejected and profile isolation holds',
    () async {
      final occurredAt = DateTime.now().toUtc();
      final event = await repository.createScheduledEvent(
        eventType: ScheduledEventType.expense,
        amountSatang: 12000,
        title: 'บิล',
        accountId: accountId,
        categoryId: expenseCategoryId,
        scheduledAt: occurredAt,
      );
      await repository.cancelScheduledEvent(event.id);
      final id = addCandidate(
        category: expenseCategoryId,
        occurredAt: occurredAt,
      );
      await expectLater(
        repository.resolveCandidateAsScheduled(id, event.id),
        throwsStateError,
      );
      final otherProfile = await repository.createProfile('คนอื่น');
      final foreignId = addCandidate(profile: otherProfile, account: null);
      await expectLater(
        repository.ignoreCandidate(foreignId),
        throwsStateError,
      );
    },
  );
}
