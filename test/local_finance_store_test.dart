import 'package:flutter_test/flutter_test.dart';
import 'package:ngoen_ku_pai_nai/core/money.dart';
import 'package:ngoen_ku_pai_nai/ui/local_finance_store.dart';

void main() {
  test('onboarding profile survives a repository reload', () async {
    final store = LocalFinanceStore.memory();
    await store.saveProfile(LocalProfile(
      payday: 25,
      holidayRule: 'before',
      accountName: 'บัญชีเงินเดือน',
      openingBalance: Money.fromBaht(10500),
      savingTarget: Money.fromBaht(2500),
      emergencyTarget: Money.fromBaht(30000),
      foodSpent: Money.zero,
    ));
    final loaded = await store.loadProfile();
    expect(loaded, isNotNull);
    expect(loaded!.payday, 25);
    expect(loaded.openingBalance, Money.fromBaht(10500));
    expect(loaded.savingTarget, Money.fromBaht(2500));
  });

  test('quick-add food expense is persisted in the ledger', () async {
    final store = LocalFinanceStore.memory();
    await store.saveProfile(LocalProfile(
      payday: 25,
      holidayRule: 'before',
      accountName: 'บัญชีเงินเดือน',
      openingBalance: Money.fromBaht(10500),
      savingTarget: Money.fromBaht(2500),
      emergencyTarget: Money.fromBaht(30000),
      foodSpent: Money.zero,
    ));
    await store.addExpense(amount: Money.fromBaht(120), categoryName: 'อาหาร');
    final loaded = await store.loadProfile();
    expect(loaded!.foodSpent, Money.fromBaht(120));
    expect(loaded.openingBalance, Money.fromBaht(10380));
    expect(await store.repository.ledgerTransactionCount(), 1);
  });
}
