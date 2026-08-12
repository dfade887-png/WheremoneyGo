import '../../core/money.dart';

enum TransactionType {
  income,
  expense,
  refund,
  transferIn,
  transferOut,
  balanceAdjustment,
}

enum BudgetType { fixed, installment, reserved, flexible }

enum OccurrenceStatus { skipped, paid, overdue, planned }

enum BudgetPace { onTrack, fast, aheadOfPace, overBudget, unsupported }

enum StatementDirection { credit, debit }

enum StatementClassification {
  pending,
  income,
  expense,
  transfer,
  refund,
  matchExisting,
  ignore,
}

enum StatementImportStatus { preview, confirmed, cancelled, failed, undone }

enum InstallmentContractStatus { active, paused, cancelled, completed }

final class InstallmentProgress {
  const InstallmentProgress({
    required this.paid,
    required this.remaining,
    required this.overpayment,
    required this.progressRatio,
    required this.estimatedRemainingPayments,
  });
  final Money paid;
  final Money remaining;
  final Money overpayment;
  final double? progressRatio;
  final int? estimatedRemainingPayments;
}

final class BudgetPeriod {
  const BudgetPeriod({required this.start, required this.end});
  final DateTime start;
  final DateTime end;
  int daysRemainingInclusive(DateTime today) =>
      end.difference(today).inDays + 1;
  int get totalDaysInclusive => end.difference(start).inDays + 1;
  int elapsedDaysInclusive(DateTime today) =>
      today.difference(start).inDays + 1;
}

final class CategorySpend {
  const CategorySpend(this.categoryId, this.netSpend);
  final String? categoryId;
  final Money netSpend;
}

final class BudgetAnalysis {
  const BudgetAnalysis({
    this.usedPercent,
    this.elapsedPercent,
    required this.pace,
  });
  final double? usedPercent;
  final double? elapsedPercent;
  final BudgetPace pace;
}

final class ReconciliationResult {
  const ReconciliationResult({
    required this.expectedClosing,
    required this.internalDifference,
    required this.ledgerDifference,
  });
  final Money expectedClosing;
  final Money internalDifference;
  final Money ledgerDifference;
  bool get isInternallyBalanced => internalDifference == Money.zero;
  bool get isLedgerBalanced => ledgerDifference == Money.zero;
}

final class StatementDraftRow {
  const StatementDraftRow({
    required this.rowIndex,
    required this.postedDate,
    required this.transactionDate,
    required this.descriptionRaw,
    required this.direction,
    required this.amount,
    this.referenceNo,
    this.runningBalance,
  });
  final int rowIndex;
  final DateTime postedDate;
  final DateTime transactionDate;
  final String descriptionRaw;
  final StatementDirection direction;
  final Money amount;
  final String? referenceNo;
  final Money? runningBalance;
}

final class ParsedStatement {
  const ParsedStatement({
    required this.institution,
    required this.adapterVersion,
    required this.rows,
    this.openingBalance,
    this.closingBalance,
  });
  final String institution;
  final String adapterVersion;
  final List<StatementDraftRow> rows;
  final Money? openingBalance;
  final Money? closingBalance;
}
