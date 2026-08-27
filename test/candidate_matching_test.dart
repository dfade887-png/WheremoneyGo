import 'package:flutter_test/flutter_test.dart';
import 'package:ngoen_ku_pai_nai/data/repositories/sqlite_finance_repository.dart';
import 'package:ngoen_ku_pai_nai/domain/candidate_matching.dart';
import 'package:ngoen_ku_pai_nai/domain/models/scheduled_financial_event.dart';

void main() {
  late SqliteFinanceRepository repository;
  late String accountA, accountB, expenseCategory, incomeCategory;
  final base = DateTime.utc(2026, 8, 24, 12);

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
      openingBalanceSatang: 0,
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

  String candidate({
    String type = 'expense',
    int amount = 12000,
    DateTime? at,
    String? account,
    String? destination,
    String? category,
    String? merchant,
    String? reference,
    String? id,
  }) {
    final value =
        id ??
        'candidate-${repository.query('SELECT COUNT(*) n FROM transaction_candidates').single['n']}';
    final now = (at ?? base).toUtc().toIso8601String();
    repository.execute(
      '''INSERT INTO transaction_candidates(
         id,profile_id,account_id,destination_account_id,category_id,
         candidate_type,amount_satang,occurred_at,merchant_or_sender,
         reference_no,confidence,review_status,created_at,updated_at)
         VALUES(?,?,?,?,?,?,?,?,?,?,0.95,'pending_review',?,?)''',
      [
        value,
        repository.activeProfileId,
        account,
        destination,
        category,
        type,
        amount,
        now,
        merchant,
        reference,
        now,
        now,
      ],
    );
    return value;
  }

  Future<String> transaction({
    String type = 'expense',
    int amount = 12000,
    DateTime? at,
    String? account,
    String? category,
    String? note,
  }) => repository.createTransaction(
    accountId: account ?? accountA,
    categoryId:
        category ?? (type == 'income' ? incomeCategory : expenseCategory),
    type: type,
    amountSatang: amount,
    occurredAt: at ?? base,
    note: note,
  );

  Future<String> scheduled({
    ScheduledEventType type = ScheduledEventType.expense,
    int amount = 150000,
    DateTime? at,
    String? account,
    String? destination,
    String? category,
    String origin = 'manual',
    String title = 'Dentist',
  }) async => (await repository.createScheduledEvent(
    eventType: type,
    amountSatang: amount,
    title: title,
    accountId: account ?? accountA,
    destinationAccountId: destination,
    categoryId:
        category ??
        (type == ScheduledEventType.income
            ? incomeCategory
            : type == ScheduledEventType.transfer
            ? null
            : expenseCategory),
    scheduledAt: at ?? base,
    originType: origin,
  )).id;

  Future<void> addStatementReference(
    String transactionId,
    String reference,
  ) async {
    final profile = repository.activeProfileId;
    repository.execute(
      '''INSERT INTO statement_imports(
         id,account_id,institution,adapter_version,file_name,file_hash,status,imported_at,profile_id)
         VALUES('import',?,'bank','v1','x.csv','hash','confirmed',?,?)''',
      [accountA, base.toIso8601String(), profile],
    );
    repository.execute(
      '''INSERT INTO statement_rows(
         id,statement_import_id,row_index,posted_date,transaction_date,
         description_raw,reference_no,direction,amount_satang,row_fingerprint,
         classification,matched_transaction_id)
         VALUES('row','import',1,?,?,?,?,?,12000,'fingerprint','matchExisting',?)''',
      [
        base.toIso8601String(),
        base.toIso8601String(),
        'Merchant',
        reference,
        'debit',
        transactionId,
      ],
    );
  }

  test('1 exact expense match', () async {
    final target = await transaction();
    final id = candidate(account: accountA, category: expenseCategory);
    final result = await repository.matchCandidate(id);
    expect(result.kind, CandidateMatchKind.existingTransactionMatch);
    expect(result.targetId, target);
  });

  test('2 income match', () async {
    final target = await transaction(type: 'income', category: incomeCategory);
    final id = candidate(
      type: 'income',
      account: accountA,
      category: incomeCategory,
    );
    expect((await repository.matchCandidate(id)).targetId, target);
  });

  test('3 refund match', () async {
    final target = await transaction(type: 'refund');
    final id = candidate(
      type: 'refund',
      account: accountA,
      category: expenseCategory,
    );
    expect((await repository.matchCandidate(id)).targetId, target);
  });

  test(
    '4 Manual Quick Add duplicate recommends existing transaction only',
    () async {
      final target = await transaction(at: base);
      final id = candidate(
        at: base.add(const Duration(minutes: 1)),
        account: accountA,
      );
      final result = await repository.matchCandidate(id);
      expect(result.targetId, target);
      expect(
        repository.query(
          'SELECT review_status,matched_transaction_id FROM transaction_candidates WHERE id=?',
          [id],
        ).single,
        {'review_status': 'pending_review', 'matched_transaction_id': null},
      );
    },
  );

  test('5 Scheduled expense match', () async {
    final target = await scheduled();
    final id = candidate(
      amount: 150000,
      account: accountA,
      category: expenseCategory,
    );
    expect((await repository.matchCandidate(id)).targetId, target);
  });

  test('6 Salary Scheduled match', () async {
    final target = await scheduled(
      type: ScheduledEventType.income,
      amount: 1712500,
      category: incomeCategory,
      origin: 'salary',
      title: 'Salary',
    );
    final id = candidate(type: 'income', amount: 1712500, account: accountA);
    expect((await repository.matchCandidate(id)).targetId, target);
  });

  test('7 Commitment Scheduled match', () async {
    final target = await scheduled(origin: 'commitment');
    final id = candidate(amount: 150000, account: accountA);
    expect((await repository.matchCandidate(id)).targetId, target);
  });

  test('8 Existing transfer-pair match', () async {
    final group = await repository.createTransfer(
      fromAccountId: accountA,
      toAccountId: accountB,
      amountSatang: 200000,
    );
    repository.execute(
      'UPDATE transactions SET occurred_at=? WHERE transfer_group_id=?',
      [base.toIso8601String(), group],
    );
    final id = candidate(
      type: 'transfer',
      amount: 200000,
      account: accountA,
      destination: accountB,
    );
    final result = await repository.matchCandidate(id);
    expect(result.targetType, CandidateMatchTargetType.transferGroup);
    expect(result.targetId, group);
  });

  test('9 Scheduled transfer match', () async {
    final target = await scheduled(
      type: ScheduledEventType.transfer,
      amount: 200000,
      destination: accountB,
    );
    final id = candidate(
      type: 'transfer',
      amount: 200000,
      account: accountA,
      destination: accountB,
    );
    expect((await repository.matchCandidate(id)).targetId, target);
  });

  test('10 unresolved transfer destination never claims exact match', () async {
    await repository.createTransfer(
      fromAccountId: accountA,
      toAccountId: accountB,
      amountSatang: 200000,
    );
    final id = candidate(type: 'transfer', amount: 200000, account: accountA);
    expect(
      (await repository.matchCandidate(id)).kind,
      CandidateMatchKind.noMatch,
    );
  });

  test('11 amount mismatch', () async {
    await transaction();
    final id = candidate(amount: 12001, account: accountA);
    expect(
      (await repository.matchCandidate(id)).kind,
      CandidateMatchKind.noMatch,
    );
  });

  test('12 account mismatch', () async {
    await transaction();
    final id = candidate(account: accountB);
    expect(
      (await repository.matchCandidate(id)).kind,
      CandidateMatchKind.noMatch,
    );
  });

  test('13 type mismatch', () async {
    await transaction();
    final id = candidate(type: 'income', account: accountA);
    expect(
      (await repository.matchCandidate(id)).kind,
      CandidateMatchKind.noMatch,
    );
  });

  test('14 time-window rejection', () async {
    await transaction();
    final id = candidate(
      at: base.add(const Duration(minutes: 11)),
      account: accountA,
    );
    expect(
      (await repository.matchCandidate(id)).kind,
      CandidateMatchKind.noMatch,
    );
  });

  test('15 exact reference strengthens explainable match', () async {
    final target = await transaction();
    await addStatementReference(target, 'REF-1');
    final id = candidate(account: accountA, reference: 'REF-1');
    final result = await repository.matchCandidate(id);
    expect(
      result.best!.reasons.map((reason) => reason.code),
      contains('exact_reference'),
    );
  });

  test('16 conflicting reference rejects match', () async {
    final target = await transaction();
    await addStatementReference(target, 'REF-1');
    final id = candidate(account: accountA, reference: 'REF-2');
    expect(
      (await repository.matchCandidate(id)).kind,
      CandidateMatchKind.noMatch,
    );
  });

  test('17 two plausible Transaction ambiguity', () async {
    await transaction();
    await transaction();
    final id = candidate(account: accountA);
    expect(
      (await repository.matchCandidate(id)).kind,
      CandidateMatchKind.ambiguous,
    );
  });

  test('18 Scheduled plus Existing Transaction is safely ambiguous', () async {
    await transaction(amount: 150000);
    await scheduled();
    final id = candidate(amount: 150000, account: accountA);
    final result = await repository.matchCandidate(id);
    expect(result.kind, CandidateMatchKind.ambiguous);
    expect(
      result.alternatives.map((item) => item.targetType),
      containsAll([
        CandidateMatchTargetType.transaction,
        CandidateMatchTargetType.scheduledEvent,
      ]),
    );
  });

  test('19 repeated same-amount purchases remain distinct by time', () async {
    final first = await transaction(at: base);
    final second = await transaction(at: base.add(const Duration(minutes: 8)));
    candidate(id: 'a', at: base, account: accountA);
    candidate(
      id: 'b',
      at: base.add(const Duration(minutes: 8)),
      account: accountA,
    );
    final results = await repository.matchPendingCandidates();
    expect(results.map((result) => result.targetId), [first, second]);
  });

  test('20 two Candidates collision on one target', () async {
    await transaction();
    candidate(id: 'a', account: accountA);
    candidate(id: 'b', account: accountA);
    final results = await repository.matchPendingCandidates();
    expect(
      results.every((result) => result.kind == CandidateMatchKind.ambiguous),
      isTrue,
    );
    expect(
      results.every((result) => result.explanation!.contains('มากกว่าหนึ่ง')),
      isTrue,
    );
  });

  test('21 profile isolation', () async {
    await transaction();
    final other = await repository.createProfile('Other', draft: false);
    await repository.switchProfile(other);
    final otherAccount = await repository.createAccount(
      name: 'Other',
      type: 'bank',
      openingBalanceSatang: 0,
    );
    final id = candidate(account: otherAccount);
    expect(
      (await repository.matchCandidate(id)).kind,
      CandidateMatchKind.noMatch,
    );
  });

  test('22 soft-delete exclusion', () async {
    final target = await transaction();
    repository.execute('UPDATE transactions SET deleted_at=? WHERE id=?', [
      base.toIso8601String(),
      target,
    ]);
    final id = candidate(account: accountA);
    expect(
      (await repository.matchCandidate(id)).kind,
      CandidateMatchKind.noMatch,
    );
  });

  test('23 terminal Scheduled exclusion', () async {
    final target = await scheduled();
    repository.execute(
      "UPDATE scheduled_financial_events SET stored_status='cancelled' WHERE id=?",
      [target],
    );
    final id = candidate(amount: 150000, account: accountA);
    expect(
      (await repository.matchCandidate(id)).kind,
      CandidateMatchKind.noMatch,
    );
  });

  test('24 deterministic batch ordering', () async {
    candidate(id: 'z', at: base.add(const Duration(minutes: 1)));
    candidate(id: 'b', at: base);
    candidate(id: 'a', at: base);
    expect(
      (await repository.matchPendingCandidates()).map(
        (result) => result.candidateId,
      ),
      ['a', 'b', 'z'],
    );
  });

  test('25 matching is read-only for every protected table', () async {
    await transaction();
    await scheduled(amount: 12000);
    candidate(account: accountA);
    const tables = [
      'transactions',
      'scheduled_financial_events',
      'transaction_candidates',
      'candidate_evidence',
      'commitment_payments',
      'commitment_occurrences',
    ];
    final before = {
      for (final table in tables)
        table: repository.query('SELECT * FROM $table'),
    };
    await repository.matchPendingCandidates();
    final after = {
      for (final table in tables)
        table: repository.query('SELECT * FROM $table'),
    };
    expect(after, before);
  });

  test('26 Actual and Projected safety', () async {
    await transaction();
    await scheduled(amount: 12000);
    candidate(account: accountA);
    final projectedBefore = await repository.projectedBalance(
      cutoff: base.add(const Duration(days: 1)),
    );
    await repository.matchPendingCandidates();
    final projectedAfter = await repository.projectedBalance(
      cutoff: base.add(const Duration(days: 1)),
    );
    expect(
      projectedAfter.actualNetWorthSatang,
      projectedBefore.actualNetWorthSatang,
    );
    expect(
      projectedAfter.projectedNetWorthSatang,
      projectedBefore.projectedNetWorthSatang,
    );
  });
}
