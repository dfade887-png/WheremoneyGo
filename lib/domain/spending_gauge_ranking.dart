import 'spending_gauge.dart';

/// Presentation-only ordering for the compact Home summary.
/// Financial values remain owned by [SpendingGauge].
List<SpendingGauge> rankHomeSpendingGauges(
  Iterable<SpendingGauge> gauges, {
  int limit = 3,
}) {
  final ranked = gauges.where((gauge) => gauge.hasBudget).toList()
    ..sort((left, right) {
      final stateCompare = _priority(
        right.state,
      ).compareTo(_priority(left.state));
      if (stateCompare != 0) return stateCompare;
      final ratioCompare = (right.usageRatio ?? 0).compareTo(
        left.usageRatio ?? 0,
      );
      if (ratioCompare != 0) return ratioCompare;
      final nameCompare = left.name.compareTo(right.name);
      return nameCompare != 0
          ? nameCompare
          : left.categoryId.compareTo(right.categoryId);
    });
  return ranked.take(limit).toList(growable: false);
}

int _priority(SpendingGaugeState state) => switch (state) {
  SpendingGaugeState.over => 4,
  SpendingGaugeState.critical => 3,
  SpendingGaugeState.warning => 2,
  SpendingGaugeState.safe => 1,
  SpendingGaugeState.unbudgeted => 0,
};
