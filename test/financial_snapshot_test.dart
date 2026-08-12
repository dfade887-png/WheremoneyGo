import 'package:flutter_test/flutter_test.dart';
import 'package:ngoen_ku_pai_nai/domain/financial_snapshot.dart';

void main() {
  FinancialSnapshot snapshot(
    List<Map<String, Object?>> transactions, {
    List<int> balances = const [100000],
    int obligations = 10000,
    int flexible = 30000,
  }) => FinancialSnapshotCalculator.calculate(
    profileId: 'p',
    now: DateTime(2026, 8, 15),
    payday: 25,
    activeAccountBalancesSatang: balances,
    transactions: transactions,
    categoryBudgets: const [
      {'category_id': 'food', 'category_name': 'อาหาร', 'amount_satang': 30000},
    ],
    expectedIncomeRemainingSatang: 0,
    unpaidObligationsSatang: obligations,
    plannedFlexibleSpendSatang: flexible,
    savingReservationSatang: 10000,
    minimumReserveSatang: 5000,
    savingGoalSatang: 25000,
  );
  Map<String, Object?> tx(
    String type,
    int amount, {
    String? deleted,
    String status = 'confirmed',
  }) => {
    'type': type,
    'amount_satang': amount,
    'category_id': 'food',
    'deleted_at': deleted,
    'status': status,
  };

  test('actual money and forecast are independent from saving goal', () {
    final result = snapshot(const [], balances: const [50000, 25000]);
    expect(result.actualMoney.satang, 75000);
    expect(result.forecastEndOfCycle.satang, 35000);
    expect(result.forecastEndOfCycle.satang, isNot(result.savingGoal.satang));
  });

  test(
    'expense refund transfer pending and deleted produce correct net spend',
    () {
      final result = snapshot([
        tx('expense', 20000),
        tx('refund', 5000),
        tx('transfer_out', 9000),
        tx('expense', 7000, status: 'pending'),
        tx('expense', 8000, deleted: 'x'),
      ]);
      expect(result.categoryBudgets.single.spentNet.satang, 15000);
    },
  );

  test('transfer does not alter snapshot when account total is unchanged', () {
    final before = snapshot(const [], balances: const [100000, 0]);
    final after = snapshot(
      [tx('transfer_out', 25000), tx('transfer_in', 25000)],
      balances: const [75000, 25000],
    );
    expect(after.actualMoney, before.actualMoney);
    expect(after.forecastEndOfCycle, before.forecastEndOfCycle);
  });

  test('negative flexible money gives zero safe allowance and warning', () {
    final result = snapshot(
      const [],
      balances: const [1000],
      obligations: 50000,
    );
    expect(result.todayAvailableRaw.satang, lessThan(0));
    expect(result.todayAvailableSafe.satang, 0);
    expect(result.warnings, contains('วันนี้ควรงดรายจ่ายยืดหยุ่น'));
  });

  test('velocity uses cycle elapsed and budget usage', () {
    final result = snapshot([tx('expense', 25000)]);
    expect(
      result.categoryBudgets.single.velocity,
      anyOf(SpendingVelocity.critical, SpendingVelocity.fast),
    );
  });
}
