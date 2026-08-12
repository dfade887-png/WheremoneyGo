import 'package:flutter/foundation.dart';
import '../core/money.dart';
import '../domain/financial_rules.dart';
import '../domain/models/financial_models.dart';
import 'local_finance_store.dart';

enum AppStep { welcome, payday, accounts, recurring, saving, dashboard }

enum ViewStatus { ready, loading, empty, error }

final class FinanceSnapshot {
  const FinanceSnapshot({
    required this.currentCash,
    required this.dailyAllowance,
    required this.forecast,
    required this.foodSpent,
  });
  final Money currentCash, dailyAllowance, forecast, foodSpent;
}

final class AppState extends ChangeNotifier {
  AppState({LocalFinanceStore? store}) {
    _store = store;
  }

  LocalFinanceStore? _store;
  bool initialized = false;
  AppStep step = AppStep.welcome;
  ViewStatus viewStatus = ViewStatus.ready;
  int payday = 25;
  String holidayRule = 'before';
  String accountName = 'บัญชีเงินเดือน';
  Money openingBalance = Money.fromBaht(10500);
  Money foodSpent = Money.fromBaht(2040);
  Money savingTarget = Money.fromBaht(2500);
  Money emergencyTarget = Money.fromBaht(30000);
  InstallmentProgress? phoneProgress;

  Future<void> initialize() async {
    viewStatus = ViewStatus.loading;
    notifyListeners();
    try {
      _store ??= await LocalFinanceStore.open();
      final profile = await _store!.loadProfile();
      if (profile != null) {
        payday = profile.payday;
        holidayRule = profile.holidayRule;
        accountName = profile.accountName;
        openingBalance = profile.openingBalance;
        savingTarget = profile.savingTarget;
        emergencyTarget = profile.emergencyTarget;
        foodSpent = profile.foodSpent;
        step = AppStep.dashboard;
        phoneProgress = await _store!.loadInstallmentProgress('phone');
      }
      initialized = true;
      viewStatus = ViewStatus.ready;
    } catch (_) {
      viewStatus = ViewStatus.error;
    }
    notifyListeners();
  }

  Future<void> completeOnboarding() async {
    await _store!.saveProfile(
      LocalProfile(
        payday: payday,
        holidayRule: holidayRule,
        accountName: accountName,
        openingBalance: openingBalance,
        savingTarget: savingTarget,
        emergencyTarget: emergencyTarget,
        foodSpent: foodSpent,
      ),
    );
    go(AppStep.dashboard);
  }

  FinanceSnapshot get snapshot {
    final currentCash = FinancialRules.currentCash([
      openingBalance,
      Money.fromBaht(1200),
    ]);
    final flexible = FinancialRules.remainingFlexible(
      Money.fromBaht(5626),
      Money.zero,
    );
    return FinanceSnapshot(
      currentCash: currentCash,
      dailyAllowance: FinancialRules.dailyAllowance(flexible, 30),
      forecast: FinancialRules.forecast(
        currentCash: Money.fromBaht(17125),
        expectedIncomeNotReceived: Money.zero,
        unpaidCommitments: Money.fromBaht(5999),
        remainingVariableSpend: Money.fromBaht(8626),
      ),
      foodSpent: foodSpent,
    );
  }

  void go(AppStep value) {
    step = value;
    notifyListeners();
  }

  void setViewStatus(ViewStatus value) {
    viewStatus = value;
    notifyListeners();
  }

  Future<void> addFoodExpense(Money value) async {
    await _store!.addExpense(amount: value, categoryName: 'อาหาร');
    foodSpent += value;
    openingBalance -= value;
    notifyListeners();
  }

  Future<void> configurePhoneInstallment({
    required Money total,
    required Money paid,
    required Money regular,
  }) async {
    await _store!.configureInstallment(
      id: 'phone',
      name: 'โทรศัพท์',
      total: total,
      paid: paid,
      regular: regular,
    );
    phoneProgress = await _store!.loadInstallmentProgress('phone');
    notifyListeners();
  }
}
