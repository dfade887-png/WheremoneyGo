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
  List<Map<String, Object?>> accounts = const [];
  List<Map<String, Object?>> categories = const [];
  List<Map<String, Object?>> activities = const [];
  List<Map<String, Object?>> commitments = const [];

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
      await refreshDailyData();
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
    await refreshDailyData();
    go(AppStep.dashboard);
  }

  FinanceSnapshot get snapshot {
    final currentCash = Money.fromSatang(
      accounts
          .where((a) => a['is_active'] == 1 && a['include_in_net_worth'] == 1)
          .fold<int>(0, (sum, a) => sum + ((a['balance_satang'] as int?) ?? 0)),
    );
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

  Future<void> refreshDailyData() async {
    accounts = await _store!.accounts();
    categories = await _store!.categories();
    activities = await _store!.activity();
    commitments = await _store!.commitments();
    notifyListeners();
  }

  Future<void> addAccount(String name, String type, Money opening) async {
    await _store!.addAccount(name: name, type: type, openingBalance: opening);
    await refreshDailyData();
  }

  Future<void> addCategory(String name, String type, String iconKey) async {
    await _store!.addCategory(name: name, type: type, iconKey: iconKey);
    await refreshDailyData();
  }

  Future<void> addDailyTransaction({
    required String accountId,
    required String categoryId,
    required String type,
    required Money amount,
    String? note,
  }) async {
    await _store!.addTransaction(
      accountId: accountId,
      categoryId: categoryId,
      type: type,
      amount: amount,
      note: note,
    );
    await refreshDailyData();
  }

  Future<void> addTransfer(String from, String to, Money amount) async {
    await _store!.transfer(
      fromAccountId: from,
      toAccountId: to,
      amount: amount,
    );
    await refreshDailyData();
  }

  Future<void> removeTransaction(String id) async {
    await _store!.deleteTransaction(id);
    await refreshDailyData();
  }

  Future<void> undoTransaction(String id) async {
    await _store!.restoreDeletedTransaction(id);
    await refreshDailyData();
  }

  Future<void> resetAllData() async {
    await _store!.resetAll();
    accounts = const [];
    categories = const [];
    activities = const [];
    commitments = const [];
    step = AppStep.welcome;
    notifyListeners();
  }

  Future<String> createBackup() => _store!.backupToFile();

  Future<void> addCommitment({
    required String name,
    required String type,
    int? totalSatang,
    int? regularSatang,
    String? accountId,
    String? categoryId,
  }) async {
    await _store!.addCommitment(
      name: name,
      type: type,
      totalSatang: totalSatang,
      regularSatang: regularSatang,
      accountId: accountId,
      categoryId: categoryId,
    );
    await refreshDailyData();
  }

  Future<void> payCommitment({
    required String commitmentId,
    required String accountId,
    required String categoryId,
    required Money amount,
  }) async {
    await _store!.payCommitment(
      commitmentId: commitmentId,
      accountId: accountId,
      categoryId: categoryId,
      amount: amount,
    );
    await refreshDailyData();
  }

  Future<void> archiveDailyAccount(String id) async {
    await _store!.archiveAccount(id);
    await refreshDailyData();
  }

  Future<void> restoreDailyAccount(String id) async {
    await _store!.restoreAccount(id);
    await refreshDailyData();
  }

  Future<void> updateDailyAccount(String id, String name, String type) async {
    await _store!.updateAccount(id, name, type);
    await refreshDailyData();
  }

  Future<void> adjustDailyAccount(String id, Money delta, String reason) async {
    await _store!.adjustAccount(id, delta, reason);
    await refreshDailyData();
  }

  Future<void> editDailyTransaction({
    required String id,
    required String accountId,
    required String categoryId,
    required Money amount,
    required DateTime occurredAt,
    String? note,
  }) async {
    await _store!.updateTransaction(
      id: id,
      accountId: accountId,
      categoryId: categoryId,
      amount: amount,
      occurredAt: occurredAt,
      note: note,
    );
    await refreshDailyData();
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
