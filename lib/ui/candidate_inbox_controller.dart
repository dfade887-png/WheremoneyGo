import 'package:flutter/foundation.dart';

import '../domain/candidate_review.dart';
import '../domain/transfer_correlation.dart';
import '../data/candidate_notification_service.dart';

final class CandidateInboxController extends ChangeNotifier {
  CandidateInboxController(
    this.repository, {
    this.onFinancialChange,
    CandidateNotificationService? notificationService,
  }) : notificationService =
           notificationService ?? AndroidCandidateNotificationService();

  final CandidateReviewRepository repository;
  final Future<void> Function()? onFinancialChange;
  final CandidateNotificationService notificationService;
  final Set<String> _rejectedCorrelationPairs = {};
  List<CandidateReviewItem> pendingCandidates = const [];
  Map<String, TransferCorrelationResult> correlations = const {};
  List<CandidateTargetSummary> alternatives = const [];
  CandidateReviewItem? selectedCandidate;
  bool loading = false;
  String? error;
  String? resolvingCandidateId;

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      pendingCandidates = await repository.pendingCandidateReviews();
      if (repository is TransferCorrelationRepository) {
        final results = await (repository as TransferCorrelationRepository)
            .correlatePendingCandidates();
        correlations = {
          for (final item in results)
            if (!_rejectedCorrelationPairs.contains(_pairKey(item)))
              item.candidateId: item,
        };
      }
    } catch (_) {
      error = 'โหลดรายการรอตรวจไม่สำเร็จ กรุณาลองใหม่';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> select(CandidateReviewItem item) async {
    selectedCandidate = item;
    alternatives = const [];
    error = null;
    notifyListeners();
    try {
      alternatives = await repository.candidateTargetSummaries(item.id);
    } catch (_) {
      error = 'คำแนะนำเปลี่ยนไปแล้ว กรุณารีเฟรช';
      await load();
    }
    notifyListeners();
  }

  Future<bool> resolveExisting(CandidateTargetSummary target) => _resolve(
    () => repository.resolveCandidateAsExisting(
      selectedCandidate!.id,
      target.targetType,
      target.id,
    ),
  );

  Future<bool> resolveScheduled(
    CandidateTargetSummary target, {
    String? destinationAccountId,
  }) => _resolve(
    () => repository.resolveCandidateAsScheduled(
      selectedCandidate!.id,
      target.id,
      destinationAccountId: destinationAccountId,
    ),
  );

  Future<bool> reconcileAll(
    CandidateTargetSummary existing,
    CandidateTargetSummary scheduled,
  ) => _resolve(
    () => repository.reconcileCandidateExistingAndScheduled(
      selectedCandidate!.id,
      existing.targetType,
      existing.id,
      scheduled.id,
    ),
  );

  Future<bool> createNew({String? categoryId, String? destinationAccountId}) =>
      _resolve(
        () => repository.createTransactionFromCandidate(
          selectedCandidate!.id,
          categoryId: categoryId,
          destinationAccountId: destinationAccountId,
        ),
      );

  Future<bool> ignore() =>
      _resolve(() => repository.ignoreCandidate(selectedCandidate!.id));

  TransferCorrelationResult? correlationFor(String candidateId) {
    final result = correlations[candidateId];
    return result?.hasPair == true ? result : null;
  }

  void rejectCorrelation(TransferCorrelationResult result) {
    _rejectedCorrelationPairs.add(_pairKey(result));
    correlations = Map.of(correlations)
      ..remove(result.candidateId)
      ..remove(result.pairedCandidateId);
    notifyListeners();
  }

  Future<bool> confirmCorrelation(TransferCorrelationResult result) async {
    if (repository is! TransferCorrelationRepository ||
        resolvingCandidateId != null) {
      return false;
    }
    resolvingCandidateId = result.candidateId;
    error = null;
    notifyListeners();
    try {
      final resolution = await (repository as TransferCorrelationRepository)
          .confirmCorrelatedTransfer(result);
      await notificationService.cancelCandidateNotification(result.candidateId);
      if (result.pairedCandidateId != null) {
        await notificationService.cancelCandidateNotification(
          result.pairedCandidateId!,
        );
      }
      if (resolution.createdFinancialRecord) await onFinancialChange?.call();
      await load();
      return true;
    } catch (_) {
      error = 'คำแนะนำการโอนเปลี่ยนไปแล้ว กรุณารีเฟรชและตรวจอีกครั้ง';
      await load();
      return false;
    } finally {
      resolvingCandidateId = null;
      notifyListeners();
    }
  }

  static String _pairKey(TransferCorrelationResult result) {
    final pair = [result.candidateId, ?result.pairedCandidateId]..sort();
    return pair.join('|');
  }

  Future<bool> _resolve(
    Future<CandidateResolutionResult> Function() action,
  ) async {
    final candidate = selectedCandidate;
    if (candidate == null || resolvingCandidateId != null) return false;
    resolvingCandidateId = candidate.id;
    error = null;
    notifyListeners();
    try {
      final result = await action();
      await notificationService.cancelCandidateNotification(candidate.id);
      if (result.createdFinancialRecord) await onFinancialChange?.call();
      selectedCandidate = null;
      alternatives = const [];
      await load(); // Re-runs T15 so collision recommendations cannot stay stale.
      return true;
    } catch (_) {
      error = 'ยืนยันไม่สำเร็จ ข้อมูลอาจเปลี่ยนไป กรุณาตรวจสอบอีกครั้ง';
      await load();
      return false;
    } finally {
      resolvingCandidateId = null;
      notifyListeners();
    }
  }
}
