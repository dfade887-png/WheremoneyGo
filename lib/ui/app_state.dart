import 'package:flutter/foundation.dart';
import '../core/money.dart';
import '../domain/financial_rules.dart';

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
  AppStep step = AppStep.welcome;
  ViewStatus viewStatus = ViewStatus.ready;
  int payday = 25;
  String holidayRule = 'before';
  String accountName = 'บัญชีเงินเดือน';
  Money openingBalance = Money.fromBaht(10500);
  Money foodSpent = Money.fromBaht(2040);
  Money savingTarget = Money.fromBaht(2500);
  Money emergencyTarget = Money.fromBaht(30000);

  FinanceSnapshot get snapshot {
    final currentCash = FinancialRules.currentCash([
      openingBalance,
      Money.fromBaht(1200),
    ]);
    final flexible = FinancialRules.remainingFlexible(
      Money.fromBaht(5626),
      foodSpent,
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

  void addFoodExpense(Money value) {
    foodSpent += value;
    notifyListeners();
  }
}
