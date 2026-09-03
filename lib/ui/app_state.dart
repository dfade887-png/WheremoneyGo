import 'dart:io' show Platform;

import 'package:flutter/widgets.dart';
import '../core/money.dart';
import '../domain/models/financial_models.dart';
import '../domain/financial_snapshot.dart' as projection;
import '../domain/financial_calendar.dart';
import '../domain/candidate_review.dart';
import '../data/repositories/sqlite_finance_repository.dart';
import '../data/notification_capture_bridge.dart';
import '../data/slip_media_scanner.dart';
import '../data/slip_media_lifecycle_gate.dart';
import 'local_finance_store.dart';

enum AppStep {
  welcome,
  payday,
  accounts,
  recurring,
  saving,
  dashboard,
  calendar,
}

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

final class AppState extends ChangeNotifier with WidgetsBindingObserver {
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
  List<OnboardingAccountInput> onboardingAccounts = [];
  String? salaryAccountDraftId;
  String? savingsAccountDraftId;
  InstallmentProgress? phoneProgress;
  List<Map<String, Object?>> accounts = const [];
  List<Map<String, Object?>> categories = const [];
  List<Map<String, Object?>> activities = const [];
  List<Map<String, Object?>> commitments = const [];
  List<Map<String, Object?>> profiles = const [];
  String? activeProfileId;
  projection.FinancialSnapshot? projectionSnapshot;
  List<FinancialCalendarEvent> dashboardUpcoming = const [];
  List<CandidateReviewItem> dashboardCandidates = const [];
  bool onboardingSubmitting = false;
  String? notificationLaunchCandidateId;
  bool _drainInProgress = false;
  bool _drainRerunRequested = false;
  bool _lifecycleDisposed = false;
  SlipMediaScanner? _slipScanner;
  final SlipMediaLifecycleGate _slipLifecycleGate = SlipMediaLifecycleGate();

  SqliteFinanceRepository get financeRepository {
    final store = _store;
    if (store == null) throw StateError('AppState is not initialized');
    return store.repository;
  }

  Future<void> initialize() async {
    viewStatus = ViewStatus.loading;
    notifyListeners();
    try {
      _store ??= await LocalFinanceStore.open();
      _slipScanner ??= SlipMediaScanner(
        _store!.repository,
        NotificationCaptureBridge(),
      );
      if (Platform.isAndroid) {
        try {
          notificationLaunchCandidateId = await NotificationCaptureBridge()
              .consumeLaunchCandidate();
        } catch (_) {
          // Older native builds may not expose the launch-intent channel.
        }
      }
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
        onboardingAccounts = [
          OnboardingAccountInput(
            id: 'primary',
            name: profile.accountName,
            type: 'bank',
            openingBalance: profile.openingBalance,
          ),
        ];
        salaryAccountDraftId = 'primary';
      }
      await refreshDailyData();
      initialized = true;
      viewStatus = ViewStatus.ready;
      WidgetsBinding.instance.addObserver(this);
      _requestNotificationDrain();
      _requestSlipMediaScan();
    } catch (_) {
      viewStatus = ViewStatus.error;
    }
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && initialized) {
      _requestNotificationDrain();
      _requestSlipMediaScan();
    }
  }

  void _requestNotificationDrain() {
    if (_lifecycleDisposed || !Platform.isAndroid || !initialized) return;
    if (_drainInProgress) {
      _drainRerunRequested = true;
      return;
    }
    _drainInProgress = true;
    Future<void>(() async {
      try {
        final repository = financeRepository;
        await NotificationCaptureCoordinator(
          repository,
          NotificationCaptureBridge(),
          () => _store!.activeProfileId,
        ).synchronizeAndDrain();
        await refreshDailyData();
      } catch (_) {
        // Lifecycle drain is best-effort; financial writes remain unaffected.
      } finally {
        _drainInProgress = false;
        if (_drainRerunRequested && !_lifecycleDisposed) {
          _drainRerunRequested = false;
          _requestNotificationDrain();
        }
      }
    });
  }

  void requestNotificationCaptureSync() => _requestNotificationDrain();

  Future<bool> slipDetectionEnabled() =>
      financeRepository.slipDetectionEnabled();

  Future<String> slipImagePermissionState() =>
      NotificationCaptureBridge().slipImagePermissionState();

  Future<void> setSlipDetectionEnabled(bool enabled) async {
    await financeRepository.setSlipDetectionEnabled(enabled);
    if (enabled) {
      await financeRepository.initializeSlipDetectionBaseline(
        DateTime.now().toUtc(),
      );
      _requestSlipMediaScan();
    }
    notifyListeners();
  }

  /// Performs an on-demand metadata-only scan. It never writes financial data.
  Future<int> scanSlipMediaNow() async {
    final scanner = _slipScanner;
    if (scanner == null) return 0;
    if (_slipLifecycleGate.manualSelectionActive) {
      _slipLifecycleGate.deferAutomaticScan();
      return 0;
    }
    return scanner.scanIfEnabled(
      allowStaging: () => _slipLifecycleGate.automaticStagingAllowed,
    );
  }

  /// Opens Android's document picker. Only the URI explicitly selected by the
  /// user is staged; no gallery-wide read is performed by this action.
  Future<int> addSlipFromDevice() async {
    _slipLifecycleGate.beginManualSelection();
    try {
      final items = await NotificationCaptureBridge().pickSlipImages();
      if (items.isEmpty) return 0;
      return (await financeRepository.stageNewSlipMedia(
        items,
        ingestionSource: 'manual',
      )).length;
    } finally {
      // The picker-triggered resume is deliberately not scanned here. A later
      // genuine resume scans from the unchanged automatic baseline.
      _slipLifecycleGate.endManualSelection();
    }
  }

  void _requestSlipMediaScan() {
    if (_lifecycleDisposed || !Platform.isAndroid || !initialized) return;
    if (_slipLifecycleGate.manualSelectionActive) {
      _slipLifecycleGate.deferAutomaticScan();
      return;
    }
    final scanner = _slipScanner;
    if (scanner == null) return;
    Future<void>(() async {
      try {
        await scanner.scanIfEnabled(
          allowStaging: () => _slipLifecycleGate.automaticStagingAllowed,
        );
      } catch (_) {
        // Slip discovery is best-effort and must never affect financial state.
      }
    });
  }

  @override
  void dispose() {
    _lifecycleDisposed = true;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> completeOnboarding() async {
    if (onboardingSubmitting) return;
    onboardingSubmitting = true;
    viewStatus = ViewStatus.loading;
    notifyListeners();
    try {
      if (onboardingAccounts.isEmpty) {
        throw StateError('ต้องมีบัญชีอย่างน้อยหนึ่งบัญชี');
      }
      final salary = onboardingAccounts.firstWhere(
        (item) => item.id == salaryAccountDraftId,
        orElse: () => onboardingAccounts.first,
      );
      accountName = salary.name;
      openingBalance = salary.openingBalance;
      await _store!.saveOnboardingProfile(
        LocalProfile(
          payday: payday,
          holidayRule: holidayRule,
          accountName: accountName,
          openingBalance: openingBalance,
          savingTarget: savingTarget,
          emergencyTarget: emergencyTarget,
          foodSpent: foodSpent,
        ),
        accounts: onboardingAccounts,
        salaryAccountDraftId: salary.id,
        savingsAccountDraftId: savingsAccountDraftId,
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
    final now = DateTime.now();
    final upcoming = await financeRepository.calendarEvents(
      from: now.toUtc(),
      to: now.add(const Duration(days: 45)).toUtc(),
      now: now.toUtc(),
    );
    dashboardUpcoming = upcoming.events
        .where(
          (event) =>
              event.displayStatus == FinancialCalendarDisplayStatus.scheduled ||
              event.displayStatus == FinancialCalendarDisplayStatus.due,
        )
        .take(3)
        .toList(growable: false);
    dashboardCandidates = (await financeRepository.pendingCandidateReviews())
        .take(20)
        .toList(growable: false);
    notifyListeners();
  }

  Future<void> createAndSwitchProfile(String name) async {
    final id = await _store!.createProfile(name);
    await _store!.switchProfile(id);
    activeProfileId = id;
    payday = 25;
    accountName = '';
    openingBalance = Money.zero;
    onboardingAccounts = [];
    salaryAccountDraftId = null;
    savingsAccountDraftId = null;
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
