final class SalaryProjectionResult {
  SalaryProjectionResult({
    required this.createdCount,
    required this.updatedCount,
    required this.cancelledCount,
    required Iterable<String> unresolvedReasons,
  }) : unresolvedReasons = List.unmodifiable(unresolvedReasons);

  final int createdCount;
  final int updatedCount;
  final int cancelledCount;
  final List<String> unresolvedReasons;
}
