import 'package:flutter_test/flutter_test.dart';
import 'package:ngoen_ku_pai_nai/data/repositories/sqlite_finance_repository.dart';
import 'package:ngoen_ku_pai_nai/domain/models/scheduled_financial_event.dart';
import 'package:ngoen_ku_pai_nai/domain/transaction_lifecycle.dart';

void main() {
  late SqliteFinanceRepository repository;
  late String sourceId;
  late String destinationId;

  setUp(() async {
    repository = SqliteFinanceRepository.memory();
    sourceId = await repository.createAccount(
      name: 'SCB',
      type: 'bank',
      openingBalanceSatang: 1000000,
    );
    destinationId = await repository.createAccount(
      name: 'Savings',
      type: 'bank',
      openingBalanceSatang: 500000,
    );
  });

  tearDown(() => repository.dispose());

  Future<ScheduledFinancialEvent> schedule({DateTime? scheduledAt}) =>
      repository.createScheduledEvent(
        eventType: ScheduledEventType.transfer,
        amountSatang: 200000,
        title: 'Move to savings',
        note: 'monthly saving',
        accountId: sourceId,
        destinationAccountId: destinationId,
        scheduledAt: scheduledAt ?? DateTime.utc(2026, 8, 25),
      );

  Future<int> balance(String accountId) async =>
      (await repository.accounts()).singleWhere(
            (row) => row['id'] == accountId,
          )['balance_satang']
          as int;

  test('confirmation creates and links one real transfer pair', () async {
    final event = await schedule();
    expect(await repository.ledgerTransactionCount(), 0);
    expect(await balance(sourceId), 1000000);
    expect(await balance(destinationId), 500000);
    final occurredAt = DateTime.utc(2026, 8, 27, 9, 30);

    final group = await repository.confirmScheduledTransfer(
      event.id,
      occurredAt: occurredAt,
    );

    final pair = repository.query(
      'SELECT * FROM transactions WHERE transfer_group_id=? ORDER BY type',
      [group],
    );
    expect(pair, hasLength(2));
    final incoming = pair.singleWhere((row) => row['type'] == 'transfer_in');
    final outgoing = pair.singleWhere((row) => row['type'] == 'transfer_out');
    expect(outgoing['account_id'], sourceId);
    expect(incoming['account_id'], destinationId);
    for (final row in pair) {
      expect(row['amount_satang'], 200000);
      expect(row['profile_id'], repository.activeProfileId);
      expect(row['source'], 'scheduled_event');
      expect(row['status'], 'confirmed');
      expect(row['deleted_at'], isNull);
      expect(row['occurred_at'], occurredAt.toIso8601String());
      expect(row['posted_at'], occurredAt.toIso8601String());
      expect(row['transfer_group_id'], group);
    }
    final fulfilled = (await repository.scheduledEvents()).single;
    expect(fulfilled.storedStatus, ScheduledEventStoredState.fulfilled);
    expect(fulfilled.linkedTransferGroupId, group);
    expect(fulfilled.linkedTransactionId, isNull);
    expect(await balance(sourceId), 800000);
    expect(await balance(destinationId), 700000);
    expect(await balance(sourceId) + await balance(destinationId), 1500000);
  });

  test('derived-due and future transfers are confirmable', () async {
    final due = await schedule(scheduledAt: DateTime.utc(2026, 8, 1));
    expect(
      due.effectiveStatus(DateTime.utc(2026, 8, 20)),
      ScheduledEventState.due,
    );
    await repository.confirmScheduledTransfer(due.id);

    final future = await schedule(scheduledAt: DateTime.utc(2030, 1, 1));
    expect(
      future.effectiveStatus(DateTime.utc(2026, 8, 20)),
      ScheduledEventState.scheduled,
    );
    await repository.confirmScheduledTransfer(future.id);
    expect(await repository.ledgerTransactionCount(), 4);
  });

  test('double confirmation returns same group without duplicate', () async {
    final event = await schedule();
    final first = await repository.confirmScheduledTransfer(event.id);
    final second = await repository.confirmScheduledTransfer(event.id);
    expect(second, first);
    expect(await repository.ledgerTransactionCount(), 2);
    expect(
      repository.query('SELECT DISTINCT transfer_group_id FROM transactions'),
      hasLength(1),
    );
  });

  test('cancelled skipped and non-transfer events are rejected', () async {
    final cancelled = await schedule();
    final skipped = await schedule();
    await repository.cancelScheduledEvent(cancelled.id);
    await repository.skipScheduledEvent(skipped.id);
    final income = await repository.createScheduledEvent(
      eventType: ScheduledEventType.income,
      amountSatang: 1000,
      title: 'Income',
      accountId: sourceId,
      scheduledAt: DateTime.utc(2026, 8, 25),
    );
    await expectLater(
      repository.confirmScheduledTransfer(cancelled.id),
      throwsStateError,
    );
    await expectLater(
      repository.confirmScheduledTransfer(skipped.id),
      throwsStateError,
    );
    await expectLater(
      repository.confirmScheduledTransfer(income.id),
      throwsStateError,
    );
    expect(await repository.ledgerTransactionCount(), 0);
  });

  test('failure after transfer out rolls back everything', () async {
    final event = await schedule();
    await expectLater(
      repository.confirmScheduledTransfer(event.id, failAfterTransferOut: true),
      throwsStateError,
    );
    expect(await repository.ledgerTransactionCount(), 0);
    expect(
      (await repository.scheduledEvents()).single.storedStatus,
      ScheduledEventStoredState.scheduled,
    );
    expect(await balance(sourceId), 1000000);
    expect(await balance(destinationId), 500000);
  });

  test('failure after both rows rolls back pair and fulfillment', () async {
    final event = await schedule();
    await expectLater(
      repository.confirmScheduledTransfer(
        event.id,
        failBeforeFulfillment: true,
      ),
      throwsStateError,
    );
    expect(await repository.ledgerTransactionCount(), 0);
    final unchanged = (await repository.scheduledEvents()).single;
    expect(unchanged.storedStatus, ScheduledEventStoredState.scheduled);
    expect(unchanged.linkedTransferGroupId, isNull);
    expect(await balance(sourceId) + await balance(destinationId), 1500000);
  });

  test('soft-deleted transfer cannot be confirmed', () async {
    final event = await schedule();
    repository.execute(
      'UPDATE scheduled_financial_events SET deleted_at=? WHERE id=?',
      [DateTime.now().toUtc().toIso8601String(), event.id],
    );
    await expectLater(
      repository.confirmScheduledTransfer(event.id),
      throwsStateError,
    );
    expect(await repository.ledgerTransactionCount(), 0);
  });

  test('another profile cannot confirm or inspect the transfer', () async {
    final event = await schedule();
    final profileB = await repository.createProfile('B', draft: false);
    await repository.switchProfile(profileB);
    await repository.createAccount(
      name: 'B account',
      type: 'bank',
      openingBalanceSatang: 0,
    );
    await expectLater(
      repository.confirmScheduledTransfer(event.id),
      throwsStateError,
    );
    expect(await repository.ledgerTransactionCount(), 0);
    expect(await repository.scheduledEvents(), isEmpty);
  });
}
