final class CommitmentProjectionResult {
  CommitmentProjectionResult({
    required this.createdCount,
    required this.updatedCount,
    required this.skippedCount,
    required this.fulfilledCount,
    required Iterable<String> unresolvedOccurrenceIds,
  }) : unresolvedOccurrenceIds = List.unmodifiable(unresolvedOccurrenceIds);

  final int createdCount;
  final int updatedCount;
  final int skippedCount;
  final int fulfilledCount;
  final List<String> unresolvedOccurrenceIds;
}
