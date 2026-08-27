import 'candidate_matching.dart';

final class CandidateReviewItem {
  const CandidateReviewItem({
    required this.id,
    required this.type,
    required this.amountSatang,
    required this.occurredAt,
    required this.sourceLabel,
    required this.match,
    this.accountId,
    this.accountName,
    this.destinationAccountId,
    this.destinationAccountName,
    this.categoryId,
    this.categoryName,
    this.merchantOrSender,
  });

  final String id, type, sourceLabel;
  final int amountSatang;
  final DateTime occurredAt;
  final String? accountId, accountName;
  final String? destinationAccountId, destinationAccountName;
  final String? categoryId, categoryName, merchantOrSender;
  final CandidateMatchResult match;
}

final class CandidateTargetSummary {
  const CandidateTargetSummary({
    required this.id,
    required this.targetType,
    required this.type,
    required this.amountSatang,
    required this.occurredAt,
    required this.title,
    required this.accountId,
    required this.accountName,
    required this.reasons,
    this.destinationAccountId,
  });
  final String id, type, title, accountId, accountName;
  final String? destinationAccountId;
  final CandidateMatchTargetType targetType;
  final int amountSatang;
  final DateTime occurredAt;
  final List<CandidateMatchReason> reasons;
}

final class CandidateResolutionResult {
  const CandidateResolutionResult({
    required this.status,
    this.transactionId,
    this.scheduledEventId,
    this.transferGroupId,
    this.createdFinancialRecord = false,
  });
  final String status;
  final String? transactionId, scheduledEventId, transferGroupId;
  final bool createdFinancialRecord;
}

abstract interface class CandidateReviewRepository {
  Future<List<CandidateReviewItem>> pendingCandidateReviews();
  Future<List<CandidateTargetSummary>> candidateTargetSummaries(String id);
  Future<CandidateResolutionResult> resolveCandidateAsExisting(
    String candidateId,
    CandidateMatchTargetType targetType,
    String targetId, {
    bool failBeforeCandidateUpdate = false,
  });
  Future<CandidateResolutionResult> resolveCandidateAsScheduled(
    String candidateId,
    String scheduledEventId, {
    String? destinationAccountId,
    bool failBeforeCandidateUpdate = false,
  });
  Future<CandidateResolutionResult> reconcileCandidateExistingAndScheduled(
    String candidateId,
    CandidateMatchTargetType existingTargetType,
    String existingTargetId,
    String scheduledEventId, {
    bool failAfterScheduledLink = false,
    bool failAfterCommitmentLink = false,
  });
  Future<CandidateResolutionResult> createTransactionFromCandidate(
    String candidateId, {
    String? categoryId,
    String? destinationAccountId,
    bool failBeforeCandidateUpdate = false,
  });
  Future<CandidateResolutionResult> ignoreCandidate(String candidateId);
}
