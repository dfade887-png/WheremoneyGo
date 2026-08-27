import 'package:flutter_test/flutter_test.dart';
import 'package:ngoen_ku_pai_nai/data/repositories/sqlite_finance_repository.dart';

void main() {
  late SqliteFinanceRepository repository;

  setUp(() => repository = SqliteFinanceRepository.memory());
  tearDown(() => repository.dispose());

  Future<String> account({int openingBalanceSatang = 100000}) =>
      repository.createAccount(
        name: 'Ledger account',
        type: 'bank',
        openingBalanceSatang: openingBalanceSatang,
      );

  Future<int> balance(String accountId) async =>
      (await repository.accounts()).singleWhere(
            (row) => row['id'] == accountId,
          )['balance_satang']
          as int;

  Future<void> insertLegacyTransaction({
    required String id,
    required String accountId,
    required String type,
    required int amountSatang,
    required String status,
    String? transferGroupId,
    String? deletedAt,
  }) async {
    final now = DateTime.utc(2026, 8, 18).toIso8601String();
    repository.execute(
      'INSERT INTO transactions(id,account_id,type,amount_satang,occurred_at,'
      'transfer_group_id,source,status,created_at,updated_at,deleted_at,profile_id) '
      'VALUES(?,?,?,?,?,?,?,?,?,?,?,?)',
      [
        id,
        accountId,
        type,
        amountSatang,
        now,
        transferGroupId,
        'manual',
        status,
        now,
        now,
        deletedAt,
        repository.activeProfileId,
      ],
    );
  }

  test('confirmed income expense and refund affect Actual Balance', () async {
    final id = await account();
    await insertLegacyTransaction(
      id: 'income',
      accountId: id,
      type: 'income',
      amountSatang: 20000,
      status: 'confirmed',
    );
    await insertLegacyTransaction(
      id: 'expense',
      accountId: id,
      type: 'expense',
      amountSatang: 8000,
      status: 'confirmed',
    );
    await insertLegacyTransaction(
      id: 'refund',
      accountId: id,
      type: 'refund',
      amountSatang: 3000,
      status: 'confirmed',
    );
    expect(await balance(id), 115000);
  });

  test('confirmed transfer changes accounts but preserves net worth', () async {
    final from = await account();
    final to = await repository.createAccount(
      name: 'Destination',
      type: 'wallet',
      openingBalanceSatang: 5000,
    );
    const group = 'transfer-group';
    await insertLegacyTransaction(
      id: 'transfer-out',
      accountId: from,
      type: 'transfer_out',
      amountSatang: 25000,
      status: 'confirmed',
      transferGroupId: group,
    );
    await insertLegacyTransaction(
      id: 'transfer-in',
      accountId: to,
      type: 'transfer_in',
      amountSatang: 25000,
      status: 'confirmed',
      transferGroupId: group,
    );
    final accounts = await repository.accounts();
    expect(
      accounts.fold<int>(0, (sum, row) => sum + (row['balance_satang'] as int)),
      105000,
    );
    expect(await balance(from), 75000);
    expect(await balance(to), 30000);

    await insertLegacyTransaction(
      id: 'pending-transfer-out',
      accountId: from,
      type: 'transfer_out',
      amountSatang: 10000,
      status: 'pending',
      transferGroupId: 'pending-transfer-group',
    );
    await insertLegacyTransaction(
      id: 'pending-transfer-in',
      accountId: to,
      type: 'transfer_in',
      amountSatang: 10000,
      status: 'pending',
      transferGroupId: 'pending-transfer-group',
    );
    expect(await balance(from), 75000);
    expect(await balance(to), 30000);
  });

  test('signed balance adjustments affect Actual Balance', () async {
    final id = await account();
    await insertLegacyTransaction(
      id: 'adjust-up',
      accountId: id,
      type: 'balance_adjustment',
      amountSatang: 4000,
      status: 'confirmed',
    );
    await insertLegacyTransaction(
      id: 'adjust-down',
      accountId: id,
      type: 'balance_adjustment',
      amountSatang: -1500,
      status: 'confirmed',
    );
    expect(await balance(id), 102500);
  });

  test('deleted status and soft-deleted rows do not affect Actual', () async {
    final id = await account();
    await insertLegacyTransaction(
      id: 'deleted-status-expense',
      accountId: id,
      type: 'expense',
      amountSatang: 50000,
      status: 'deleted',
    );
    await insertLegacyTransaction(
      id: 'soft-deleted-expense',
      accountId: id,
      type: 'expense',
      amountSatang: 25000,
      status: 'confirmed',
      deletedAt: DateTime.utc(2026, 8, 18).toIso8601String(),
    );
    expect(await balance(id), 100000);
  });

  test('legacy pending transaction must not affect Actual Balance', () async {
    final id = await account();
    await insertLegacyTransaction(
      id: 'pending-expense',
      accountId: id,
      type: 'expense',
      amountSatang: 25000,
      status: 'pending',
    );
    expect(
      await balance(id),
      100000,
      reason: 'Pending review is not guaranteed to be real money',
    );
  });
}
