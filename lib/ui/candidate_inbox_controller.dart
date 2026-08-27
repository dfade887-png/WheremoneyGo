import 'package:flutter/foundation.dart';

import '../domain/candidate_review.dart';

final class CandidateInboxController extends ChangeNotifier {
  CandidateInboxController(this.repository, {this.onFinancialChange});

  final CandidateReviewRepository repository;
  final Future<void> Function()? onFinancialChange;
  List<CandidateReviewItem> pendingCandidates = const [];
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
