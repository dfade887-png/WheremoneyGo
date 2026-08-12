import 'package:flutter_test/flutter_test.dart';
import 'package:ngoen_ku_pai_nai/data/repositories/sqlite_finance_repository.dart';

void main() {
  late SqliteFinanceRepository repository;
  setUp(() => repository = SqliteFinanceRepository.memory());
  tearDown(() => repository.dispose());

  test('account lifecycle and zero cash are supported', () async {
    final bank = await repository.createAccount(
      name: 'Salary',
      type: 'bank',
      openingBalanceSatang: 100000,
    );
    final cash = await repository.createAccount(
      name: 'Cash',
      type: 'cash',
      openingBalanceSatang: 0,
    );
    await repository.archiveAccount(cash);
    expect(
      (await repository.accounts(includeArchived: false)).map((e) => e['id']),
      [bank],
    );
    await repository.restoreAccount(cash);
    expect(await repository.accounts(), hasLength(2));
  });

  test('cannot archive final active account', () async {
    final id = await repository.createAccount(
      name: 'Only',
      type: 'bank',
      openingBalanceSatang: 0,
    );
    expect(() => repository.archiveAccount(id), throwsStateError);
  });

  test('balance adjustment changes cash and writes audit', () async {
    final id = await repository.createAccount(
      name: 'Bank',
      type: 'bank',
      openingBalanceSatang: 10000,
    );
    await repository.adjustBalance(
      accountId: id,
      deltaSatang: -2500,
      reason: 'reconcile',
    );
    expect((await repository.accounts()).single['balance_satang'], 7500);
    expect(
      (await repository.dumpTable(
        'audit_events',
      )).any((e) => e['action'] == 'adjust'),
      isTrue,
    );
  });

  test('custom category supports icon archive and restore', () async {
    final id = await repository.createCategory(
      name: 'เติมเกม',
      type: 'expense',
      iconKey: 'sports_esports',
    );
    await repository.archiveCategory(id);
    expect(await repository.categories(type: 'expense'), isEmpty);
    await repository.restoreCategory(id);
    expect(
      (await repository.categories(type: 'expense')).single['icon_key'],
      'sports_esports',
    );
  });

  test('expense income and linked refund calculate correctly', () async {
    final account = await repository.createAccount(
      name: 'Bank',
      type: 'bank',
      openingBalanceSatang: 100000,
    );
    final expense = await repository.createCategory(
      name: 'Food',
      type: 'expense',
      iconKey: 'restaurant',
    );
    final income = await repository.createCategory(
      name: 'Salary',
      type: 'income',
      iconKey: 'payments',
    );
    final original = await repository.createTransaction(
      accountId: account,
      categoryId: expense,
      type: 'expense',
      amountSatang: 20000,
    );
    await repository.createTransaction(
      accountId: account,
      categoryId: income,
      type: 'income',
      amountSatang: 50000,
    );
    await repository.createTransaction(
      accountId: account,
      categoryId: expense,
      type: 'refund',
      amountSatang: 5000,
      refundOfTransactionId: original,
    );
    expect((await repository.accounts()).single['balance_satang'], 135000);
  });

  test('category type mismatch is rejected', () async {
    final account = await repository.createAccount(
      name: 'Bank',
      type: 'bank',
      openingBalanceSatang: 0,
    );
    final income = await repository.createCategory(
      name: 'Salary',
      type: 'income',
      iconKey: 'payments',
    );
    expect(
      () => repository.createTransaction(
        accountId: account,
        categoryId: income,
        type: 'expense',
        amountSatang: 100,
      ),
      throwsStateError,
    );
  });

  test('transfer is atomic and combined cash unchanged', () async {
    final a = await repository.createAccount(
      name: 'Bank',
      type: 'bank',
      openingBalanceSatang: 100000,
    );
    final b = await repository.createAccount(
      name: 'Wallet',
      type: 'wallet',
      openingBalanceSatang: 5000,
    );
    await repository.createTransfer(
      fromAccountId: a,
      toAccountId: b,
      amountSatang: 25000,
    );
    expect(
      (await repository.accounts()).fold<int>(
        0,
        (sum, e) => sum + (e['balance_satang'] as int),
      ),
      105000,
    );
    expect(
      () => repository.createTransfer(
        fromAccountId: a,
        toAccountId: a,
        amountSatang: 100,
      ),
      throwsArgumentError,
    );
    expect(
      () => repository.createTransfer(
        fromAccountId: a,
        toAccountId: b,
        amountSatang: 100,
        failAfterDebit: true,
      ),
      throwsStateError,
    );
    expect(await repository.ledgerTransactionCount(), 2);
  });

  test('soft delete and restore recalculate balance', () async {
    final account = await repository.createAccount(
      name: 'Bank',
      type: 'bank',
      openingBalanceSatang: 10000,
    );
    final category = await repository.createCategory(
      name: 'Food',
      type: 'expense',
      iconKey: 'restaurant',
    );
    final tx = await repository.createTransaction(
      accountId: account,
      categoryId: category,
      type: 'expense',
      amountSatang: 2500,
    );
    await repository.softDeleteTransaction(tx);
    expect((await repository.accounts()).single['balance_satang'], 10000);
    await repository.restoreTransactionRecord(tx);
    expect((await repository.accounts()).single['balance_satang'], 7500);
  });

  test('transaction edit reverses old value and applies new value', () async {
    final a = await repository.createAccount(
      name: 'A',
      type: 'bank',
      openingBalanceSatang: 10000,
    );
    final b = await repository.createAccount(
      name: 'B',
      type: 'wallet',
      openingBalanceSatang: 0,
    );
    final food = await repository.createCategory(
      name: 'Food',
      type: 'expense',
      iconKey: 'restaurant',
    );
    final tx = await repository.createTransaction(
      accountId: a,
      categoryId: food,
      type: 'expense',
      amountSatang: 1000,
    );
    await repository.updateTransaction(
      id: tx,
      accountId: b,
      categoryId: food,
      amountSatang: 2500,
      occurredAt: DateTime.utc(2026, 8, 12),
    );
    final balances = {
      for (final row in await repository.accounts())
        row['id']: row['balance_satang'],
    };
    expect(balances[a], 10000);
    expect(balances[b], -2500);
  });

  test('transfer edit changes both sides atomically', () async {
    final a = await repository.createAccount(
      name: 'A',
      type: 'bank',
      openingBalanceSatang: 10000,
    );
    final b = await repository.createAccount(
      name: 'B',
      type: 'wallet',
      openingBalanceSatang: 0,
    );
    final group = await repository.createTransfer(
      fromAccountId: a,
      toAccountId: b,
      amountSatang: 1000,
    );
    await repository.updateTransfer(
      groupId: group,
      fromAccountId: b,
      toAccountId: a,
      amountSatang: 2000,
    );
    final balances = {
      for (final row in await repository.accounts())
        row['id']: row['balance_satang'],
    };
    expect(balances[a], 12000);
    expect(balances[b], -2000);
  });

  test(
    'fixed and open commitments derive paid from linked transactions',
    () async {
      final account = await repository.createAccount(
        name: 'Bank',
        type: 'bank',
        openingBalanceSatang: 3000000,
      );
      final category = await repository.createCategory(
        name: 'Phone',
        type: 'expense',
        iconKey: 'phone_android',
      );
      final fixed = await repository.createCommitment(
        name: 'Phone',
        type: 'fixed_total',
        totalSatang: 2700000,
        regularSatang: 100000,
        accountId: account,
        categoryId: category,
      );
      for (var i = 0; i < 16; i++) {
        await repository.recordCommitmentPayment(
          commitmentId: fixed,
          accountId: account,
          categoryId: category,
          amountSatang: 100000,
        );
      }
      expect(await repository.commitmentPaidSatang(fixed), 1600000);
      final dental = await repository.createCommitment(
        name: 'Dental',
        type: 'open_ended',
        regularSatang: 250000,
        accountId: account,
        categoryId: category,
      );
      await repository.recordCommitmentPayment(
        commitmentId: dental,
        accountId: account,
        categoryId: category,
        amountSatang: 250000,
      );
      expect(await repository.commitmentPaidSatang(dental), 250000);
    },
  );

  test('reset is atomic and never inferred from negative cash', () async {
    await repository.createAccount(
      name: 'Bank',
      type: 'bank',
      openingBalanceSatang: -7500000,
    );
    expect(() => repository.resetUserData(failMidway: true), throwsStateError);
    expect(await repository.accounts(), hasLength(1));
    await repository.resetUserData();
    expect(await repository.accounts(), isEmpty);
  });

  test(
    'pending bank pair confirms as one transfer without changing total',
    () async {
      final a = await repository.createAccount(
        name: 'Bank',
        type: 'bank',
        openingBalanceSatang: 100000,
      );
      final b = await repository.createAccount(
        name: 'Wallet',
        type: 'wallet',
        openingBalanceSatang: 0,
      );
      final now = DateTime.utc(2026, 8, 12).toIso8601String();
      for (final row in [
        ('out', 'bank', 'out-key', 'out-fp', 'outgoing'),
        ('in', 'wallet', 'in-key', 'in-fp', 'incoming'),
      ]) {
        repository.execute(
          "INSERT INTO bank_notification_events(id,source_package,institution,adapter_version,notification_key_hash,content_fingerprint,detected_at,direction,amount_satang,status,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?,'pending',?,?)",
          [
            row.$1,
            row.$2,
            'fixture',
            '1',
            row.$3,
            row.$4,
            now,
            row.$5,
            50000,
            now,
            now,
          ],
        );
      }
      await repository.confirmBankEventsAsTransfer(
        outgoingEventId: 'out',
        incomingEventId: 'in',
        fromAccountId: a,
        toAccountId: b,
      );
      expect(
        (await repository.accounts()).fold<int>(
          0,
          (sum, row) => sum + (row['balance_satang'] as int),
        ),
        100000,
      );
      expect(
        repository
            .query(
              "SELECT COUNT(*) count FROM bank_notification_events WHERE status='matched_existing'",
            )
            .single['count'],
        2,
      );
      expect(
        () => repository.confirmBankEventsAsTransfer(
          outgoingEventId: 'out',
          incomingEventId: 'in',
          fromAccountId: a,
          toAccountId: b,
        ),
        throwsStateError,
      );
    },
  );
}
