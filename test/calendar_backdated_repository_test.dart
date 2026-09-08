import 'package:flutter_test/flutter_test.dart';
import 'package:ngoen_ku_pai_nai/data/repositories/sqlite_finance_repository.dart';

void main() {
  late SqliteFinanceRepository repository;

  setUp(() => repository = SqliteFinanceRepository.memory());
  tearDown(() => repository.dispose());

  test(
    'backdated confirmed expense uses financial date but changes Actual now',
    () async {
      final accountId = await repository.createAccount(
        name: 'SCB',
        type: 'bank',
        openingBalanceSatang: 500000,
      );
      final categoryId = await repository.createCategory(
        name: 'อาหาร',
        type: 'expense',
        iconKey: 'food',
      );
      final occurredAt = DateTime(2026, 9, 7, 14, 35);
      final before = DateTime.now().toUtc();

      final id = await repository.createTransaction(
        accountId: accountId,
        categoryId: categoryId,
        type: 'expense',
        amountSatang: 12000,
        occurredAt: occurredAt,
      );

      final transaction = repository.query(
        'SELECT occurred_at,posted_at,created_at,status FROM transactions WHERE id=?',
        [id],
      ).single;
      final account = (await repository.accounts()).single;
      expect(
        DateTime.parse(transaction['occurred_at'] as String).toLocal(),
        occurredAt,
      );
      expect(
        DateTime.parse(transaction['posted_at'] as String).toLocal(),
        occurredAt,
      );
      expect(
        DateTime.parse(transaction['created_at'] as String).isAfter(before),
        isTrue,
      );
      expect(transaction['status'], 'confirmed');
      expect(account['balance_satang'], 488000);
      expect((await repository.activity()).single['id'], id);
    },
  );

  test(
    'backdated transfer stays atomic and shares financial timestamp',
    () async {
      final source = await repository.createAccount(
        name: 'SCB',
        type: 'bank',
        openingBalanceSatang: 500000,
      );
      final destination = await repository.createAccount(
        name: 'Krungthai',
        type: 'bank',
        openingBalanceSatang: 0,
      );
      final occurredAt = DateTime(2026, 9, 7, 14, 35);

      final group = await repository.createTransfer(
        fromAccountId: source,
        toAccountId: destination,
        amountSatang: 100000,
        occurredAt: occurredAt,
      );

      final rows = repository.query(
        'SELECT type,occurred_at,posted_at,status FROM transactions WHERE transfer_group_id=? ORDER BY type',
        [group],
      );
      expect(rows, hasLength(2));
      for (final row in rows) {
        expect(
          DateTime.parse(row['occurred_at'] as String).toLocal(),
          occurredAt,
        );
        expect(
          DateTime.parse(row['posted_at'] as String).toLocal(),
          occurredAt,
        );
        expect(row['status'], 'confirmed');
      }
      final accounts = await repository.accounts();
      expect(
        accounts.fold<int>(
          0,
          (sum, row) => sum + (row['balance_satang'] as int),
        ),
        500000,
      );
    },
  );
}
