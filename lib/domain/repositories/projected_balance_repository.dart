import '../projected_balance.dart';

abstract interface class ProjectedBalanceRepository {
  Future<ProjectedBalanceResult> projectedBalance({required DateTime cutoff});
}
