import 'package:flutter/foundation.dart';
import '../core/money.dart';
import '../domain/models/financial_models.dart';
import '../domain/financial_snapshot.dart' as projection;
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
  List<Map<String, Object?>> profiles = const [];
  String? activeProfileId;
  projection.FinancialSnapshot? projectionSnapshot;
  bool onboardingSubmitting = false;

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
    if (onboardingSubmitting) return;
    onboardingSubmitting = true;
    viewStatus = ViewStatus.loading;
    notifyListeners();
    try {
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
      step = AppStep.dashboard;
      viewStatus = ViewStatus.ready;
    } catch (_) {
      viewStatus = ViewStatus.error;
    } finally {
      onboardingSubmitting = false;
      notifyListeners();
    }
  }

  FinanceSnapshot get snapshot {
    final calculated = projectionSnapshot;
    final currentCash = calculated?.actualMoney ?? Money.zero;
    return FinanceSnapshot(
      currentCash: currentCash,
      dailyAllowance: calculated?.todayAvailableSafe ?? Money.zero,
      forecast: calculated?.forecastEndOfCycle ?? Money.zero,
      foodSpent:
          calculated?.categoryBudgets
              .where((b) => b.name == 'อาหาร')
              .firstOrNull
              ?.spentNet ??
          Money.zero,
    );
  }

  Future<void> refreshDailyData() async {
    profiles = await _store!.profiles();
    activeProfileId = _store!.activeProfileId;
    accounts = await _store!.accounts();
    categories = await _store!.categories();
    activities = await _store!.activity();
    commitments = await _store!.commitments();
    final inputs = await _store!.projectionInputs();
    projectionSnapshot = projection.FinancialSnapshotCalculator.calculate(
      profileId: activeProfileId!,
      now: DateTime.now(),
      payday: payday,
      activeAccountBalancesSatang: accounts
          .where((a) => a['is_active'] == 1 && a['include_in_net_worth'] == 1)
          .map((a) => a['balance_satang'] as int),
      transactions: activities,
      categoryBudgets: inputs['categoryBudgets'] as List<Map<String, Object?>>,
      expectedIncomeRemainingSatang:
          inputs['expectedIncomeRemainingSatang'] as int,
      unpaidObligationsSatang: inputs['unpaidObligationsSatang'] as int,
      plannedFlexibleSpendSatang: inputs['plannedFlexibleSpendSatang'] as int,
      savingReservationSatang: inputs['savingReservationSatang'] as int,
      minimumReserveSatang: inputs['minimumReserveSatang'] as int,
      savingGoalSatang: inputs['savingGoalSatang'] as int,
    );
    notifyListeners();
  }

  Future<void> createAndSwitchProfile(String name) async {
    final id = await _store!.createProfile(name);
    await _store!.switchProfile(id);
    activeProfileId = id;
    payday = 25;
    accountName = '';
    openingBalance = Money.zero;
    foodSpent = Money.zero;
    savingTarget = Money.zero;
    emergencyTarget = Money.zero;
    step = AppStep.payday;
    await refreshDailyData();
  }

  Future<void> switchFinancialProfile(String id) async {
    await _store!.switchProfile(id);
    final profile = await _store!.loadProfile();
    if (profile != null) {
      payday = profile.payday;
      holidayRule = profile.holidayRule;
      accountName = profile.accountName;
      openingBalance = profile.openingBalance;
      savingTarget = profile.savingTarget;
      emergencyTarget = profile.emergencyTarget;
      foodSpent = profile.foodSpent;
    }
    await refreshDailyData();
  }

  Future<void> renameFinancialProfile(String id, String name) async {
    if (name.trim().isEmpty) return;
    await _store!.renameProfile(id, name.trim());
    await refreshDailyData();
  }

  Future<void> archiveFinancialProfile(String id) async {
    await _store!.archiveProfile(id);
    await refreshDailyData();
  }

  Future<void> restoreFinancialProfile(String id) async {
    await _store!.restoreProfile(id);
    await refreshDailyData();
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
