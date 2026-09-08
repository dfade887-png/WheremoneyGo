import 'package:flutter_test/flutter_test.dart';
import 'package:ngoen_ku_pai_nai/data/repositories/sqlite_finance_repository.dart';

void main() {
  late SqliteFinanceRepository repo;
  late String account, food;
  final september = DateTime(2026, 9);

  setUp(() async {
    repo = SqliteFinanceRepository.memory();
    account = await repo.createAccount(
      name: 'Test',
      type: 'bank',
      openingBalanceSatang: 500000,
    );
    food = await repo.createCategory(
      name: 'Food',
      type: 'expense',
      iconKey: 'food',
    );
  });
  tearDown(() => repo.dispose());

  Future<void> expense(
    int amount,
    DateTime date, {
    String status = 'confirmed',
    String type = 'expense',
  }) async {
    final id = await repo.createTransaction(
      accountId: account,
      categoryId: food,
      type: type,
      amountSatang: amount,
      occurredAt: date,
    );
    if (status != 'confirmed') {
      repo.execute('UPDATE transactions SET status=? WHERE id=?', [status, id]);
    }
  }

  test(
    'confirmed expenses/refunds use occurred month and preserve true over-budget ratio',
    () async {
      await repo.setCategoryMonthlyBudget(food, 300000);
      await expense(185000, DateTime(2026, 9, 7));
      await expense(25000, DateTime(2026, 9, 8), type: 'refund');
      await expense(99999, DateTime(2026, 8, 31));
      final gauge = (await repo.monthlySpendingGauges(september)).single;
      expect(gauge.usedSatang, 160000);
      expect(gauge.remainingSatang, 140000);
      expect(gauge.usageRatio, closeTo(.533333, .00001));
    },
  );

  test(
    'pending, deleted and transfers never consume a category budget',
    () async {
      await repo.setCategoryMonthlyBudget(food, 100000);
      await expense(10000, DateTime(2026, 9, 1), status: 'pending');
      final deleted = await repo.createTransaction(
        accountId: account,
        categoryId: food,
        type: 'expense',
        amountSatang: 20000,
        occurredAt: DateTime(2026, 9, 2),
      );
      await repo.softDeleteTransaction(deleted);
      final other = await repo.createAccount(
        name: 'Other',
        type: 'bank',
        openingBalanceSatang: 0,
      );
      await repo.createTransfer(
        fromAccountId: account,
        toAccountId: other,
        amountSatang: 50000,
        occurredAt: DateTime(2026, 9, 3),
      );
      expect(
        (await repo.monthlySpendingGauges(september)).single.usedSatang,
        0,
      );
    },
  );

  test(
    'budget metadata never changes Actual and removal retains ledger history',
    () async {
      await expense(12000, DateTime(2026, 9, 7));
      final before = (await repo.accounts()).single['balance_satang'];
      await repo.setCategoryMonthlyBudget(food, 300000);
      await repo.removeCategoryMonthlyBudget(food);
      expect((await repo.accounts()).single['balance_satang'], before);
      final gauge = (await repo.monthlySpendingGauges(september)).single;
      expect(gauge.hasBudget, isFalse);
      expect(gauge.usedSatang, 12000);
    },
  );

  test('budgets are profile isolated', () async {
    await repo.setCategoryMonthlyBudget(food, 300000);
    final second = await repo.createProfile('Second');
    await repo.switchProfile(second);
    expect(await repo.monthlySpendingGauges(september), isEmpty);
  });
}
