import 'models/scheduled_financial_event.dart';
import 'transaction_lifecycle.dart';

final class ProjectedAccountBalance {
  const ProjectedAccountBalance({
    required this.accountId,
    required this.actualBalanceSatang,
    required this.projectedBalanceSatang,
  });

  final String accountId;
  final int actualBalanceSatang;
  final int projectedBalanceSatang;

  int get projectedDeltaSatang => projectedBalanceSatang - actualBalanceSatang;
}

final class ProjectedBalanceResult {
  ProjectedBalanceResult({
    required this.cutoff,
    required Iterable<ProjectedAccountBalance> accounts,
  }) : accounts = Map.unmodifiable({
         for (final row in accounts) row.accountId: row,
       });

  final DateTime cutoff;
  final Map<String, ProjectedAccountBalance> accounts;

  int get actualNetWorthSatang =>
      accounts.values.fold(0, (sum, row) => sum + row.actualBalanceSatang);

  int get projectedNetWorthSatang =>
      accounts.values.fold(0, (sum, row) => sum + row.projectedBalanceSatang);

  int get projectedNetWorthDeltaSatang =>
      projectedNetWorthSatang - actualNetWorthSatang;

  ProjectedAccountBalance account(String accountId) {
    final row = accounts[accountId];
    if (row == null) throw StateError('Projected account not found');
    return row;
  }
}

abstract final class ProjectedBalanceCalculator {
  static ProjectedBalanceResult calculate({
    required Map<String, int> actualBalancesSatang,
    required Iterable<ScheduledFinancialEvent> scheduledEvents,
    required DateTime cutoff,
  }) {
    final normalizedCutoff = cutoff.toUtc();
    final projected = Map<String, int>.from(actualBalancesSatang);
    for (final event in scheduledEvents) {
      if (event.storedStatus != ScheduledEventStoredState.scheduled) continue;
      final impactAt = (event.dueAt ?? event.scheduledAt).toUtc();
      if (impactAt.isAfter(normalizedCutoff)) continue;
      if (!projected.containsKey(event.accountId)) continue;
      switch (event.eventType) {
        case ScheduledEventType.income:
        case ScheduledEventType.refund:
          projected[event.accountId] =
              projected[event.accountId]! + event.amountSatang;
        case ScheduledEventType.expense:
          projected[event.accountId] =
              projected[event.accountId]! - event.amountSatang;
        case ScheduledEventType.transfer:
          final destination = event.destinationAccountId;
          if (destination == null || !projected.containsKey(destination)) {
            continue;
          }
          projected[event.accountId] =
              projected[event.accountId]! - event.amountSatang;
          projected[destination] = projected[destination]! + event.amountSatang;
      }
    }
    return ProjectedBalanceResult(
      cutoff: normalizedCutoff,
      accounts: actualBalancesSatang.entries.map(
        (entry) => ProjectedAccountBalance(
          accountId: entry.key,
          actualBalanceSatang: entry.value,
          projectedBalanceSatang: projected[entry.key]!,
        ),
      ),
    );
  }
}
