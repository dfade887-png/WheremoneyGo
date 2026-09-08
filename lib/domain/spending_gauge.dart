enum SpendingGaugeState { safe, warning, critical, over, unbudgeted }

final class SpendingGauge {
  const SpendingGauge({
    required this.categoryId,
    required this.name,
    required this.usedSatang,
    required this.budgetSatang,
    this.iconKey,
    this.colorValue,
  });
  final String categoryId, name;
  final String? iconKey;
  final int? colorValue;
  final int usedSatang, budgetSatang;
  bool get hasBudget => budgetSatang > 0;
  int get remainingSatang => budgetSatang - usedSatang;
  int get overBudgetSatang =>
      hasBudget && usedSatang > budgetSatang ? usedSatang - budgetSatang : 0;
  double? get usageRatio => hasBudget ? usedSatang / budgetSatang : null;
  int? get usagePercent =>
      usageRatio == null ? null : (usageRatio! * 100).round();
  SpendingGaugeState get state {
    final ratio = usageRatio;
    if (ratio == null) return SpendingGaugeState.unbudgeted;
    if (ratio >= 1) return SpendingGaugeState.over;
    if (ratio >= .9) return SpendingGaugeState.critical;
    if (ratio >= .7) return SpendingGaugeState.warning;
    return SpendingGaugeState.safe;
  }
}
