import 'package:flutter_test/flutter_test.dart';
import 'package:ngoen_ku_pai_nai/data/repositories/sqlite_finance_repository.dart';
import 'package:ngoen_ku_pai_nai/domain/models/scheduled_financial_event.dart';
import 'package:ngoen_ku_pai_nai/domain/transaction_lifecycle.dart';
import 'package:ngoen_ku_pai_nai/domain/transfer_correlation.dart';

void main() {
  late SqliteFinanceRepository repository;
  late String source, destination;

  setUp(() async {
    repository = SqliteFinanceRepository.memory();
    source = await repository.createAccount(
      name: 'SCB',
      type: 'bank',
      openingBalanceSatang: 500000,
    );
    destination = await repository.createAccount(
      name: 'Krungthai savings',
      type: 'bank',
      openingBalanceSatang: 200000,
    );
  });
  tearDown(() => repository.dispose());

  void addCandidate(String id, String type, DateTime at, {int amount = 10000}) {
    final now = at.toUtc().toIso8601String();
    repository.execute(
      '''INSERT INTO transaction_candidates(
        id,profile_id,account_id,candidate_type,amount_satang,occurred_at,
        confidence,review_status,created_at,updated_at)
        VALUES(?,?,?,?,?,?,0.95,'pending_review',?,?)''',
      [
        id,
        repository.activeProfileId,
        type == 'expense' ? source : destination,
        type,
        amount,
        now,
        now,
        now,
      ],
    );
  }

  Future<TransferCorrelationResult> pair({DateTime? at}) async {
    final base = at ?? DateTime.now().toUtc();
    addCandidate('out', 'expense', base);
    addCandidate('in', 'income', base.add(const Duration(minutes: 3)));
    return repository.correlateCandidate('out');
  }

  int ledgerCount() =>
      repository.query('SELECT COUNT(*) n FROM transactions').single['n']
          as int;
  int netWorth() =>
      repository
              .query('SELECT SUM(opening_balance_satang) n FROM accounts')
              .single['n']
          as int;
  Future<int> actualNetWorth() async => (await repository.accounts()).fold<int>(
    0,
    (total, row) => total + (row['balance_satang'] as int),
  );

  test('correlation is read-only', () async {
    final beforeWorth = netWorth();
    final result = await pair();
    expect(result.kind, TransferCorrelationKind.likelyTransferPair);
    expect(ledgerCount(), 0);
    expect(netWorth(), beforeWorth);
    expect(
      repository
          .query('SELECT DISTINCT review_status FROM transaction_candidates')
          .single['review_status'],
      'pending_review',
    );
  });

  test(
    'explicit confirmation creates one atomic transfer and resolves both',
    () async {
      final beforeWorth = await actualNetWorth();
      final result = await pair();
      final resolution = await repository.confirmCorrelatedTransfer(result);
      expect(resolution.createdFinancialRecord, isTrue);
      expect(resolution.transferGroupId, isNotNull);
      expect(ledgerCount(), 2);
      expect(
        repository
            .query(
              'SELECT COUNT(DISTINCT transfer_group_id) n FROM transactions',
            )
            .single['n'],
        1,
      );
      expect(
        repository
            .query(
              "SELECT COUNT(*) n FROM transaction_candidates WHERE review_status='confirmed_new'",
            )
            .single['n'],
        2,
      );
      expect(await actualNetWorth(), beforeWorth);
    },
  );

  test('double confirmation is idempotent and creates no duplicate pair', () async {
    final result = await pair();
    final first = await repository.confirmCorrelatedTransfer(result);
    final second = await repository.confirmCorrelatedTransfer(result);
    expect(first.createdFinancialRecord, isTrue);
    expect(second.createdFinancialRecord, isFalse);
    expect(ledgerCount(), 2);
  });

  test('failure rolls back both ledger and candidate state', () async {
    final result = await pair();
    await expectLater(
      repository.confirmCorrelatedTransfer(result, failAfterTransferOut: true),
      throwsStateError,
    );
    expect(ledgerCount(), 0);
    expect(
      repository
          .query(
            "SELECT COUNT(*) n FROM transaction_candidates WHERE review_status='pending_review'",
          )
          .single['n'],
      2,
    );
  });

  test('stale pair is rejected without partial write', () async {
    final result = await pair();
    await repository.ignoreCandidate('in');
    await expectLater(
      repository.confirmCorrelatedTransfer(result),
      throwsStateError,
    );
    expect(ledgerCount(), 0);
  });

  test('existing transfer has precedence and is not duplicated', () async {
    await repository.createTransfer(
      fromAccountId: source,
      toAccountId: destination,
      amountSatang: 10000,
    );
    final result = await pair(at: DateTime.now().toUtc());
    expect(result.kind, TransferCorrelationKind.existingTransfer);
    final resolution = await repository.confirmCorrelatedTransfer(result);
    expect(resolution.createdFinancialRecord, isFalse);
    expect(ledgerCount(), 2);
  });

  test(
    'scheduled transfer has precedence and confirmation fulfills it once',
    () async {
      final at = DateTime.now().toUtc();
      final event = await repository.createScheduledEvent(
        eventType: ScheduledEventType.transfer,
        amountSatang: 10000,
        title: 'Move to savings',
        accountId: source,
        destinationAccountId: destination,
        scheduledAt: at,
      );
      final result = await pair(at: at);
      expect(result.kind, TransferCorrelationKind.scheduledTransfer);
      expect(result.scheduledEventId, event.id);
      await repository.confirmCorrelatedTransfer(result);
      expect(ledgerCount(), 2);
      final fulfilled = (await repository.scheduledEvents()).single;
      expect(fulfilled.storedStatus, ScheduledEventStoredState.fulfilled);
      expect(fulfilled.linkedTransferGroupId, isNotNull);
    },
  );
}
