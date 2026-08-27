import '../commitment_projection.dart';

abstract interface class CommitmentProjectionRepository {
  Future<CommitmentProjectionResult>
  projectCommitmentOccurrencesToScheduledEvents();
}
