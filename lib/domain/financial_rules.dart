import 'dart:math' as math;

import '../core/money.dart';
import 'models/financial_models.dart';

abstract final class FinancialRules {
  static InstallmentProgress installmentProgress({
    required Money? totalPayable,
    required Money? regularPayment,
    required Iterable<Money> confirmedPayments,
    required Iterable<Money> linkedRefunds,
  }) {
    final paid =
        confirmedPayments.fold(Money.zero, (sum, value) => sum + value) -
        linkedRefunds.fold(Money.zero, (sum, value) => sum + value);
    if (totalPayable == null || totalPayable.satang <= 0) {
      return InstallmentProgress(
        paid: paid,
        remaining: Money.zero,
        overpayment: Money.zero,
        progressRatio: null,
        estimatedRemainingPayments: null,
      );
    }
    final rawRemaining = totalPayable - paid;
    final remaining = Money.fromSatang(math.max(0, rawRemaining.satang));
    final overpayment = Money.fromSatang(math.max(0, -rawRemaining.satang));
    final estimated = regularPayment == null || regularPayment.satang <= 0
        ? null
        : (remaining.satang / regularPayment.satang).ceil();
    return InstallmentProgress(
      paid: paid,
      remaining: remaining,
      overpayment: overpayment,
      progressRatio: paid.satang / totalPayable.satang,
      estimatedRemainingPayments: estimated,
    );
  }

  static Money expectedNetIncome(Money gross, Iterable<Money> deductions) =>
      deductions.fold(gross, (value, item) => value - item);

  static Money accountBalance({
    required Money opening,
    required Iterable<(TransactionType, Money)> transactions,
  }) {
    var balance = opening;
    for (final (type, amount) in transactions) {
      switch (type) {
        case TransactionType.income:
        case TransactionType.refund:
        case TransactionType.transferIn:
          balance += amount;
        case TransactionType.expense:
        case TransactionType.transferOut:
          balance -= amount;
        case TransactionType.balanceAdjustment:
          balance += amount;
      }
    }
    return balance;
  }

  static Money currentCash(Iterable<Money> includedAccountBalances) =>
      includedAccountBalances.fold(Money.zero, (value, item) => value + item);

  static Money plannedSpendable({
    required Money expectedNetIncome,
    required Money fixed,
    required Money installments,
    required Money savingTarget,
    required Money reserved,
  }) => expectedNetIncome - fixed - installments - savingTarget - reserved;

  static Money remainingFlexible(Money planned, Money flexibleSpent) =>
      planned - flexibleSpent;

  static Money dailyAllowance(
    Money remainingFlexible,
    int daysRemainingInclusive,
  ) {
    if (daysRemainingInclusive <= 0) {
      throw ArgumentError.value(
        daysRemainingInclusive,
        'daysRemainingInclusive',
      );
    }
    return Money.fromSatang(
      math.max(0, remainingFlexible.satang) ~/ daysRemainingInclusive,
    );
  }

  static Map<String, Money> categorySpend({
    required Iterable<(String?, Money)> expenses,
    required Iterable<(String?, Money)> refunds,
  }) {
    final totals = <String, Money>{};
    for (final (category, amount) in expenses) {
      final key = category ?? 'uncategorized';
      totals[key] = (totals[key] ?? Money.zero) + amount;
    }
    for (final (category, amount) in refunds) {
      final key = category ?? 'uncategorized';
      totals[key] = (totals[key] ?? Money.zero) - amount;
    }
    return totals;
  }

  static double? categoryShare(Money category, Money totalNetExpense) =>
      totalNetExpense.satang <= 0
      ? null
      : category.satang / totalNetExpense.satang * 100;

  static Money forecast({
    required Money currentCash,
    required Money expectedIncomeNotReceived,
    required Money unpaidCommitments,
    required Money remainingVariableSpend,
  }) =>
      currentCash +
      expectedIncomeNotReceived -
      unpaidCommitments -
      remainingVariableSpend;

  static double? savingRate(Money actualSaving, Money actualNetIncome) =>
      actualNetIncome.satang <= 0
      ? null
      : actualSaving.satang / actualNetIncome.satang * 100;

  static double? emergencyRunway(
    Money emergencyFund,
    Money averageEssentialMonthlyExpense,
  ) => averageEssentialMonthlyExpense.satang <= 0
      ? null
      : emergencyFund.satang / averageEssentialMonthlyExpense.satang;

  static BudgetAnalysis analyzeBudget({
    required Money spent,
    required Money budget,
    required int elapsedDays,
    required int totalDays,
  }) {
    final elapsed = elapsedDays / totalDays * 100;
    if (budget.satang == 0 && spent.satang > 0) {
      return BudgetAnalysis(
        elapsedPercent: elapsed,
        pace: BudgetPace.unsupported,
      );
    }
    if (budget.satang <= 0) {
      return BudgetAnalysis(elapsedPercent: elapsed, pace: BudgetPace.onTrack);
    }
    final used = spent.satang / budget.satang * 100;
    final pace = used > 100
        ? BudgetPace.overBudget
        : used >= 80 && elapsed < 80
        ? BudgetPace.fast
        : used - elapsed >= 15
        ? BudgetPace.aheadOfPace
        : BudgetPace.onTrack;
    return BudgetAnalysis(
      usedPercent: used,
      elapsedPercent: elapsed,
      pace: pace,
    );
  }

  static OccurrenceStatus occurrenceStatus({
    required bool skipped,
    required String? linkedTransactionId,
    required DateTime dueDate,
    required DateTime today,
  }) {
    if (skipped) return OccurrenceStatus.skipped;
    if (linkedTransactionId != null) return OccurrenceStatus.paid;
    return dueDate.isBefore(today)
        ? OccurrenceStatus.overdue
        : OccurrenceStatus.planned;
  }

  static Money expectedIncomeNotReceived({
    required Money expected,
    required String? salaryTransactionId,
  }) => salaryTransactionId == null ? expected : Money.zero;

  static ReconciliationResult reconcile({
    required Money opening,
    required Iterable<Money> credits,
    required Iterable<Money> debits,
    required Money closing,
    required Money calculatedLedgerClosing,
  }) {
    final expected =
        credits.fold(opening, (v, e) => v + e) -
        debits.fold(Money.zero, (v, e) => v + e);
    return ReconciliationResult(
      expectedClosing: expected,
      internalDifference: closing - expected,
      ledgerDifference: closing - calculatedLedgerClosing,
    );
  }

  static Money actualSavingFromGoalTransfers({
    required Iterable<Money> transfersIn,
    required Iterable<Money> transfersOut,
  }) =>
      transfersIn.fold(Money.zero, (v, e) => v + e) -
      transfersOut.fold(Money.zero, (v, e) => v + e);
}
