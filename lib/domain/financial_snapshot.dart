import 'dart:math' as math;

import '../core/money.dart';

enum SpendingVelocity { normal, fast, critical, overBudget }

final class CategoryBudgetSnapshot {
  const CategoryBudgetSnapshot({
    required this.categoryId,
    required this.name,
    required this.spentNet,
    required this.budget,
    required this.budgetUsedRatio,
    required this.cycleElapsedRatio,
    required this.velocity,
    required this.remainingBudget,
    required this.projectedOverspend,
  });
  final String categoryId, name;
  final Money spentNet, budget, remainingBudget, projectedOverspend;
  final double? budgetUsedRatio;
  final double cycleElapsedRatio;
  final SpendingVelocity velocity;
}

final class FinancialSnapshot {
  const FinancialSnapshot({
    required this.activeProfileId,
    required this.calculatedAt,
    required this.cycleStart,
    required this.cycleEnd,
    required this.daysRemaining,
    required this.actualMoney,
    required this.expectedIncomeRemaining,
    required this.unpaidObligations,
    required this.plannedFlexibleSpendRemaining,
    required this.savingReservation,
    required this.minimumReserve,
    required this.flexibleMoneyRemaining,
    required this.todayAvailableRaw,
    required this.todayAvailableSafe,
    required this.forecastEndOfCycle,
    required this.savingGoal,
    required this.savingGoalGap,
    required this.categoryBudgets,
    required this.warnings,
    required this.calculationBreakdown,
  });
  final String activeProfileId;
  final DateTime calculatedAt, cycleStart, cycleEnd;
  final int daysRemaining;
  final Money actualMoney,
      expectedIncomeRemaining,
      unpaidObligations,
      plannedFlexibleSpendRemaining,
      savingReservation,
      minimumReserve,
      flexibleMoneyRemaining,
      todayAvailableRaw,
      todayAvailableSafe,
      forecastEndOfCycle,
      savingGoal,
      savingGoalGap;
  final List<CategoryBudgetSnapshot> categoryBudgets;
  final List<String> warnings, calculationBreakdown;
}

abstract final class FinancialSnapshotCalculator {
  static FinancialSnapshot calculate({
    required String profileId,
    required DateTime now,
    required int payday,
    required Iterable<int> activeAccountBalancesSatang,
    required Iterable<Map<String, Object?>> transactions,
    required Iterable<Map<String, Object?>> categoryBudgets,
    required int expectedIncomeRemainingSatang,
    required int unpaidObligationsSatang,
    required int plannedFlexibleSpendSatang,
    required int savingReservationSatang,
    required int minimumReserveSatang,
    required int savingGoalSatang,
  }) {
    final cycle = _cycle(now, payday);
    final days = math.max(
      1,
      cycle.$2.difference(DateTime(now.year, now.month, now.day)).inDays + 1,
    );
    final actual = activeAccountBalancesSatang.fold<int>(
      0,
      (sum, value) => sum + value,
    );
    final flexible =
        actual +
        expectedIncomeRemainingSatang -
        unpaidObligationsSatang -
        savingReservationSatang -
        minimumReserveSatang;
    final raw = flexible ~/ days;
    final safe = math.max(0, raw);
    final forecast =
        actual +
        expectedIncomeRemainingSatang -
        unpaidObligationsSatang -
        plannedFlexibleSpendSatang;
    final elapsed =
        ((DateTime(now.year, now.month, now.day).difference(cycle.$1).inDays +
                    1) /
                (cycle.$2.difference(cycle.$1).inDays + 1))
            .clamp(0.0, 1.0);
    final netByCategory = <String, int>{};
    for (final row in transactions) {
      if (row['deleted_at'] != null || row['status'] == 'pending') continue;
      final category = row['category_id'] as String?;
      if (category == null) continue;
      final type = row['type'];
      if (type == 'expense') {
        netByCategory[category] =
            (netByCategory[category] ?? 0) + (row['amount_satang'] as int);
      }
      if (type == 'refund') {
        netByCategory[category] =
            (netByCategory[category] ?? 0) - (row['amount_satang'] as int);
      }
    }
    final snapshots = categoryBudgets.map((row) {
      final id = row['category_id'] as String;
      final budget = row['amount_satang'] as int;
      final spent = netByCategory[id] ?? 0;
      final ratio = budget <= 0 ? null : spent / budget;
      final velocity = ratio == null
          ? SpendingVelocity.normal
          : ratio > 1
          ? SpendingVelocity.overBudget
          : ratio >= .8 && elapsed < .8
          ? SpendingVelocity.critical
          : ratio - elapsed >= .15
          ? SpendingVelocity.fast
          : SpendingVelocity.normal;
      final projected = elapsed <= 0
          ? 0
          : math.max(0, (spent / elapsed).round() - budget);
      return CategoryBudgetSnapshot(
        categoryId: id,
        name: row['category_name'] as String? ?? 'ไม่ระบุหมวด',
        spentNet: Money.fromSatang(spent),
        budget: Money.fromSatang(budget),
        budgetUsedRatio: ratio,
        cycleElapsedRatio: elapsed,
        velocity: velocity,
        remainingBudget: Money.fromSatang(math.max(0, budget - spent)),
        projectedOverspend: Money.fromSatang(projected),
      );
    }).toList();
    return FinancialSnapshot(
      activeProfileId: profileId,
      calculatedAt: now.toUtc(),
      cycleStart: cycle.$1,
      cycleEnd: cycle.$2,
      daysRemaining: days,
      actualMoney: Money.fromSatang(actual),
      expectedIncomeRemaining: Money.fromSatang(expectedIncomeRemainingSatang),
      unpaidObligations: Money.fromSatang(unpaidObligationsSatang),
      plannedFlexibleSpendRemaining: Money.fromSatang(
        plannedFlexibleSpendSatang,
      ),
      savingReservation: Money.fromSatang(savingReservationSatang),
      minimumReserve: Money.fromSatang(minimumReserveSatang),
      flexibleMoneyRemaining: Money.fromSatang(flexible),
      todayAvailableRaw: Money.fromSatang(raw),
      todayAvailableSafe: Money.fromSatang(safe),
      forecastEndOfCycle: Money.fromSatang(forecast),
      savingGoal: Money.fromSatang(savingGoalSatang),
      savingGoalGap: Money.fromSatang(savingGoalSatang - forecast),
      categoryBudgets: snapshots,
      warnings: [
        if (raw < 0) 'วันนี้ควรงดรายจ่ายยืดหยุ่น',
        for (final item in snapshots.where(
          (e) =>
              e.velocity == SpendingVelocity.critical ||
              e.velocity == SpendingVelocity.overBudget,
        ))
          '${item.name}: ${item.velocity == SpendingVelocity.overBudget ? 'เกินงบแล้ว' : 'เงินเริ่มไหลแรงแล้ว'}',
      ],
      calculationBreakdown: [
        'เงินจริง ${Money.fromSatang(actual)}',
        '+ รายรับที่ยังไม่เข้า ${Money.fromSatang(expectedIncomeRemainingSatang)}',
        '- ภาระที่ยังไม่จ่าย ${Money.fromSatang(unpaidObligationsSatang)}',
        '- เงินกันออม ${Money.fromSatang(savingReservationSatang)}',
        '- เงินสำรองขั้นต่ำ ${Money.fromSatang(minimumReserveSatang)}',
      ],
    );
  }

  static (DateTime, DateTime) _cycle(DateTime now, int payday) {
    final today = DateTime(now.year, now.month, now.day);
    DateTime safeDay(int year, int month) =>
        DateTime(year, month + 1, 0, 0, 0).day < payday
        ? DateTime(year, month + 1, 0)
        : DateTime(year, month, payday);
    if (today.day >= payday) {
      return (
        safeDay(today.year, today.month),
        safeDay(today.year, today.month + 1).subtract(const Duration(days: 1)),
      );
    }
    return (
      safeDay(today.year, today.month - 1),
      safeDay(today.year, today.month).subtract(const Duration(days: 1)),
    );
  }
}
