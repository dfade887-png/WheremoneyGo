import 'package:flutter_test/flutter_test.dart';
import 'package:ngoen_ku_pai_nai/core/money.dart';
import 'package:ngoen_ku_pai_nai/ui/local_finance_store.dart';

void main() {
  test('onboarding profile survives a repository reload', () async {
    final store = LocalFinanceStore.memory();
    await store.saveProfile(
      LocalProfile(
        payday: 25,
        holidayRule: 'before',
        accountName: 'บัญชีเงินเดือน',
        openingBalance: Money.fromBaht(10500),
        savingTarget: Money.fromBaht(2500),
        emergencyTarget: Money.fromBaht(30000),
        foodSpent: Money.zero,
      ),
    );
    final loaded = await store.loadProfile();
    expect(loaded, isNotNull);
    expect(loaded!.payday, 25);
    expect(loaded.openingBalance, Money.fromBaht(10500));
    expect(loaded.savingTarget, Money.fromBaht(2500));
  });

  test('quick-add food expense is persisted in the ledger', () async {
    final store = LocalFinanceStore.memory();
    await store.saveProfile(
      LocalProfile(
        payday: 25,
        holidayRule: 'before',
        accountName: 'บัญชีเงินเดือน',
        openingBalance: Money.fromBaht(10500),
        savingTarget: Money.fromBaht(2500),
        emergencyTarget: Money.fromBaht(30000),
        foodSpent: Money.zero,
      ),
    );
    await store.addExpense(amount: Money.fromBaht(120), categoryName: 'อาหาร');
    final loaded = await store.loadProfile();
    expect(loaded!.foodSpent, Money.fromBaht(120));
    expect(loaded.openingBalance, Money.fromBaht(10380));
    expect(await store.repository.ledgerTransactionCount(), 1);
  });

  test(
    'manual expense edit delete and restore recalculate from ledger',
    () async {
      final store = LocalFinanceStore.memory();
      await store.saveProfile(
        LocalProfile(
          payday: 25,
          holidayRule: 'before',
          accountName: 'Salary',
          openingBalance: Money.fromBaht(1000),
          savingTarget: Money.zero,
          emergencyTarget: Money.fromBaht(1),
          foodSpent: Money.zero,
        ),
      );
      final id = await store.addExpense(
        amount: Money.fromBaht(100),
        categoryName: 'อาหาร',
      );
      await store.editExpense(
        id,
        amount: Money.fromBaht(150),
        categoryName: 'อาหาร',
      );
      expect((await store.loadProfile())!.foodSpent, Money.fromBaht(150));
      await store.softDeleteTransaction(id);
      expect((await store.loadProfile())!.foodSpent, Money.zero);
      await store.restoreTransaction(id);
      expect((await store.loadProfile())!.foodSpent, Money.fromBaht(150));
    },
  );

  test(
    'opening installment progress never changes account or ledger',
    () async {
      final store = LocalFinanceStore.memory();
      await store.saveProfile(
        LocalProfile(
          payday: 25,
          holidayRule: 'before',
          accountName: 'Salary',
          openingBalance: Money.fromBaht(10000),
          savingTarget: Money.zero,
          emergencyTarget: Money.zero,
          foodSpent: Money.zero,
        ),
      );

      final before = (await store.accounts()).single['balance_satang'];
      await store.configureInstallment(
        id: 'phone',
        name: 'โทรศัพท์',
        total: Money.fromBaht(27000),
        paid: Money.fromBaht(16000),
        regular: Money.fromBaht(1000),
      );

      final progress = await store.loadInstallmentProgress('phone');
      expect(progress!.paid, Money.fromBaht(16000));
      expect(progress.remaining, Money.fromBaht(11000));
      expect(progress.estimatedRemainingPayments, 11);
      expect((await store.accounts()).single['balance_satang'], before);
      expect(await store.repository.ledgerTransactionCount(), 0);
    },
  );

  test('operational bootstrap is profile scoped and idempotent', () async {
    final store = LocalFinanceStore.memory();
    final profile = LocalProfile(
      payday: 25,
      holidayRule: 'before',
      accountName: 'Salary',
      openingBalance: Money.fromBaht(1000),
      savingTarget: Money.zero,
      emergencyTarget: Money.zero,
      foodSpent: Money.zero,
    );
    await store.saveProfile(profile);
    await store.saveProfile(profile);

    expect((await store.accounts()).length, 1);
    final categories = await store.categories();
    expect(categories.length, 6);
    expect(
      categories.where((row) => row['category_type'] == 'income').length,
      2,
    );

    final secondId = await store.createProfile('งานจริง');
    await store.switchProfile(secondId);
    expect(await store.accounts(), isEmpty);
    expect(await store.categories(), isEmpty);
  });

  test('multi-account onboarding persists roles without forced cash', () async {
    final store = LocalFinanceStore.memory();
    await store.saveOnboardingProfile(
      LocalProfile(
        payday: 25,
        holidayRule: 'before',
        accountName: 'SCB',
        openingBalance: Money.fromBaht(5000),
        savingTarget: Money.fromBaht(2500),
        emergencyTarget: Money.fromBaht(30000),
        foodSpent: Money.zero,
      ),
      accounts: [
        OnboardingAccountInput(
          id: 'scb',
          name: 'SCB',
          type: 'bank',
          openingBalance: Money.fromBaht(5000),
        ),
        OnboardingAccountInput(
          id: 'ktb',
          name: 'Krungthai',
          type: 'bank',
          openingBalance: Money.fromBaht(7000),
        ),
        OnboardingAccountInput(
          id: 'wallet',
          name: 'TrueMoney',
          type: 'wallet',
          openingBalance: Money.zero,
        ),
      ],
      salaryAccountDraftId: 'scb',
      savingsAccountDraftId: 'ktb',
    );

    final accounts = await store.accounts();
    expect(
      accounts.map((row) => row['name']),
      containsAll(['SCB', 'Krungthai', 'TrueMoney']),
    );
    expect(accounts.where((row) => row['account_type'] == 'cash'), isEmpty);
    expect(
      accounts.fold<int>(0, (sum, row) => sum + (row['balance_satang'] as int)),
      Money.fromBaht(12000).satang,
    );
  });
}
