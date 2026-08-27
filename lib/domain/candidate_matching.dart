enum CandidateMatchKind {
  noMatch,
  existingTransactionMatch,
  scheduledMatch,
  ambiguous,
}

enum CandidateMatchTargetType { transaction, transferGroup, scheduledEvent }

final class CandidateMatchReason {
  const CandidateMatchReason(this.code, this.description, this.weight);
  final String code;
  final String description;
  final int weight;
}

final class CandidateMatchAlternative {
  const CandidateMatchAlternative({
    required this.targetType,
    required this.targetId,
    required this.score,
    required this.reasons,
  });
  final CandidateMatchTargetType targetType;
  final String targetId;
  final int score;
  final List<CandidateMatchReason> reasons;
}

final class CandidateMatchResult {
  const CandidateMatchResult({
    required this.candidateId,
    required this.kind,
    required this.alternatives,
    this.explanation,
  });
  final String candidateId;
  final CandidateMatchKind kind;
  final List<CandidateMatchAlternative> alternatives;
  final String? explanation;

  CandidateMatchAlternative? get best => alternatives.firstOrNull;
  String? get targetId => best?.targetId;
  CandidateMatchTargetType? get targetType => best?.targetType;
  int get score => best?.score ?? 0;
}

abstract final class CandidateMatchingPolicy {
  static const existingTransactionWindow = Duration(minutes: 10);
  static const scheduledEventWindow = Duration(hours: 36);
  static const strongScore = 80;
  static const possibleScore = 55;
  static const uniqueScoreGap = 12;
}

final class MatchCandidate {
  const MatchCandidate({
    required this.id,
    required this.profileId,
    required this.type,
    required this.amountSatang,
    required this.occurredAt,
    this.accountId,
    this.destinationAccountId,
    this.categoryId,
    this.merchantOrSender,
    this.referenceNo,
  });
  final String id, profileId, type;
  final int amountSatang;
  final DateTime occurredAt;
  final String? accountId;
  final String? destinationAccountId;
  final String? categoryId;
  final String? merchantOrSender;
  final String? referenceNo;
}

final class MatchTransactionTarget {
  const MatchTransactionTarget({
    required this.id,
    required this.profileId,
    required this.type,
    required this.amountSatang,
    required this.occurredAt,
    required this.accountId,
    this.categoryId,
    this.destinationAccountId,
    this.referenceNo,
    this.description,
    this.isTransfer = false,
  });
  final String id, profileId, type, accountId;
  final int amountSatang;
  final DateTime occurredAt;
  final String? categoryId;
  final String? destinationAccountId;
  final String? referenceNo;
  final String? description;
  final bool isTransfer;
}

final class MatchScheduledTarget {
  const MatchScheduledTarget({
    required this.id,
    required this.profileId,
    required this.type,
    required this.amountSatang,
    required this.scheduledAt,
    required this.accountId,
    this.destinationAccountId,
    this.categoryId,
    this.title,
    this.note,
  });
  final String id, profileId, type, accountId;
  final int amountSatang;
  final DateTime scheduledAt;
  final String? destinationAccountId;
  final String? categoryId;
  final String? title;
  final String? note;
}

abstract interface class CandidateMatchingRepository {
  Future<CandidateMatchResult> matchCandidate(String id);
  Future<List<CandidateMatchResult>> matchPendingCandidates();
}

final class CandidateMatchingEngine {
  const CandidateMatchingEngine();

  CandidateMatchResult match(
    MatchCandidate candidate, {
    required List<MatchTransactionTarget> transactions,
    required List<MatchScheduledTarget> scheduledEvents,
  }) {
    final alternatives = <CandidateMatchAlternative>[
      for (final target in transactions) ?_scoreTransaction(candidate, target),
      for (final target in scheduledEvents) ?_scoreScheduled(candidate, target),
    ]..sort(_compareAlternatives);
    if (alternatives.isEmpty ||
        alternatives.first.score < CandidateMatchingPolicy.possibleScore) {
      return CandidateMatchResult(
        candidateId: candidate.id,
        kind: CandidateMatchKind.noMatch,
        alternatives: const [],
        explanation: 'ไม่มีเป้าหมายที่ผ่านเกณฑ์แบบอนุรักษ์นิยม',
      );
    }
    final plausible = alternatives
        .where((item) => item.score >= CandidateMatchingPolicy.possibleScore)
        .toList(growable: false);
    final best = plausible.first;
    final second = plausible.length > 1 ? plausible[1] : null;
    final hasCrossDomainStrong =
        plausible.any(
          (item) =>
              item.targetType == CandidateMatchTargetType.scheduledEvent &&
              item.score >= CandidateMatchingPolicy.strongScore,
        ) &&
        plausible.any(
          (item) =>
              item.targetType != CandidateMatchTargetType.scheduledEvent &&
              item.score >= CandidateMatchingPolicy.strongScore,
        );
    final tooClose =
        second != null &&
        best.score - second.score < CandidateMatchingPolicy.uniqueScoreGap;
    if (hasCrossDomainStrong ||
        tooClose ||
        best.score < CandidateMatchingPolicy.strongScore) {
      return CandidateMatchResult(
        candidateId: candidate.id,
        kind: CandidateMatchKind.ambiguous,
        alternatives: plausible,
        explanation: hasCrossDomainStrong
            ? 'พบทั้งรายการจริงและรายการตามกำหนดที่อาจเป็นเหตุการณ์เดียวกัน'
            : 'มีหลายเป้าหมายใกล้เคียงกันหรือคะแนนยังไม่เด็ดขาด',
      );
    }
    return CandidateMatchResult(
      candidateId: candidate.id,
      kind: best.targetType == CandidateMatchTargetType.scheduledEvent
          ? CandidateMatchKind.scheduledMatch
          : CandidateMatchKind.existingTransactionMatch,
      alternatives: [best],
    );
  }

  List<CandidateMatchResult> matchBatch(
    List<MatchCandidate> candidates, {
    required List<MatchTransactionTarget> transactions,
    required List<MatchScheduledTarget> scheduledEvents,
  }) {
    final ordered = [...candidates]
      ..sort(
        (a, b) => a.occurredAt.compareTo(b.occurredAt) != 0
            ? a.occurredAt.compareTo(b.occurredAt)
            : a.id.compareTo(b.id),
      );
    final results = [
      for (final candidate in ordered)
        match(
          candidate,
          transactions: transactions,
          scheduledEvents: scheduledEvents,
        ),
    ];
    final claims = <String, List<int>>{};
    for (var index = 0; index < results.length; index++) {
      final result = results[index];
      if (result.kind == CandidateMatchKind.existingTransactionMatch ||
          result.kind == CandidateMatchKind.scheduledMatch) {
        final best = result.best!;
        claims
            .putIfAbsent('${best.targetType.name}|${best.targetId}', () => [])
            .add(index);
      }
    }
    for (final indexes in claims.values.where((value) => value.length > 1)) {
      for (final index in indexes) {
        final previous = results[index];
        results[index] = CandidateMatchResult(
          candidateId: previous.candidateId,
          kind: CandidateMatchKind.ambiguous,
          alternatives: previous.alternatives,
          explanation: 'มี Candidate มากกว่าหนึ่งรายการอ้างเป้าหมายเดียวกัน',
        );
      }
    }
    return results;
  }

  CandidateMatchAlternative? _scoreTransaction(
    MatchCandidate candidate,
    MatchTransactionTarget target,
  ) {
    if (candidate.profileId != target.profileId ||
        candidate.type != target.type ||
        candidate.amountSatang != target.amountSatang) {
      return null;
    }
    final distance = candidate.occurredAt.difference(target.occurredAt).abs();
    if (distance > CandidateMatchingPolicy.existingTransactionWindow) {
      return null;
    }
    if (candidate.accountId != null &&
        candidate.accountId != target.accountId) {
      return null;
    }
    if (candidate.type == 'transfer') {
      if (!target.isTransfer || candidate.destinationAccountId == null) {
        return null;
      }
      if (candidate.destinationAccountId != target.destinationAccountId) {
        return null;
      }
    }
    if (_referencesConflict(candidate.referenceNo, target.referenceNo)) {
      return null;
    }
    final reasons = <CandidateMatchReason>[
      const CandidateMatchReason('exact_type', 'ประเภทรายการตรงกัน', 20),
      const CandidateMatchReason('exact_amount', 'จำนวนสตางค์ตรงกัน', 30),
      if (candidate.accountId == target.accountId)
        const CandidateMatchReason('exact_account', 'บัญชีตรงกัน', 25)
      else
        const CandidateMatchReason(
          'account_unresolved',
          'Candidate ยังไม่ระบุบัญชี',
          5,
        ),
      CandidateMatchReason(
        'close_time',
        'เวลาอยู่ในช่วงรายการจริง',
        _timeScore(
          distance,
          CandidateMatchingPolicy.existingTransactionWindow,
          15,
        ),
      ),
      if (candidate.categoryId != null &&
          candidate.categoryId == target.categoryId)
        const CandidateMatchReason('exact_category', 'หมวดหมู่ตรงกัน', 5),
      if (_sameOptional(candidate.referenceNo, target.referenceNo))
        const CandidateMatchReason('exact_reference', 'เลขอ้างอิงตรงกัน', 20),
      if (_textSupports(candidate.merchantOrSender, target.description))
        const CandidateMatchReason(
          'merchant_support',
          'ผู้รับหรือรายละเอียดสอดคล้องกัน',
          5,
        ),
      if (candidate.type == 'transfer')
        const CandidateMatchReason(
          'exact_destination',
          'บัญชีปลายทางตรงกัน',
          15,
        ),
    ];
    return CandidateMatchAlternative(
      targetType: target.isTransfer
          ? CandidateMatchTargetType.transferGroup
          : CandidateMatchTargetType.transaction,
      targetId: target.id,
      score: _total(reasons),
      reasons: reasons,
    );
  }

  CandidateMatchAlternative? _scoreScheduled(
    MatchCandidate candidate,
    MatchScheduledTarget target,
  ) {
    if (candidate.profileId != target.profileId ||
        candidate.type != target.type ||
        candidate.amountSatang != target.amountSatang) {
      return null;
    }
    final distance = candidate.occurredAt.difference(target.scheduledAt).abs();
    if (distance > CandidateMatchingPolicy.scheduledEventWindow) return null;
    if (candidate.accountId != null &&
        candidate.accountId != target.accountId) {
      return null;
    }
    if (candidate.type == 'transfer') {
      if (candidate.destinationAccountId == null ||
          candidate.destinationAccountId != target.destinationAccountId) {
        return null;
      }
    }
    final reasons = <CandidateMatchReason>[
      const CandidateMatchReason('exact_type', 'ประเภทรายการตรงกัน', 20),
      const CandidateMatchReason('exact_amount', 'จำนวนสตางค์ตรงกัน', 30),
      if (candidate.accountId == target.accountId)
        const CandidateMatchReason('exact_account', 'บัญชีตรงกัน', 25)
      else
        const CandidateMatchReason(
          'account_unresolved',
          'Candidate ยังไม่ระบุบัญชี',
          5,
        ),
      CandidateMatchReason(
        'scheduled_time',
        'เวลาอยู่ใกล้กำหนดการ',
        _timeScore(distance, CandidateMatchingPolicy.scheduledEventWindow, 15),
      ),
      if (candidate.categoryId != null &&
          candidate.categoryId == target.categoryId)
        const CandidateMatchReason('exact_category', 'หมวดหมู่ตรงกัน', 5),
      if (_textSupports(
        candidate.merchantOrSender,
        '${target.title ?? ''} ${target.note ?? ''}',
      ))
        const CandidateMatchReason(
          'description_support',
          'ชื่อหรือรายละเอียดสอดคล้องกัน',
          5,
        ),
      if (candidate.type == 'transfer')
        const CandidateMatchReason(
          'exact_destination',
          'บัญชีปลายทางตรงกัน',
          15,
        ),
    ];
    return CandidateMatchAlternative(
      targetType: CandidateMatchTargetType.scheduledEvent,
      targetId: target.id,
      score: _total(reasons),
      reasons: reasons,
    );
  }

  static int _compareAlternatives(
    CandidateMatchAlternative a,
    CandidateMatchAlternative b,
  ) => b.score.compareTo(a.score) != 0
      ? b.score.compareTo(a.score)
      : a.targetType.index.compareTo(b.targetType.index) != 0
      ? a.targetType.index.compareTo(b.targetType.index)
      : a.targetId.compareTo(b.targetId);

  static int _timeScore(Duration distance, Duration window, int maximum) =>
      (maximum * (window.inSeconds - distance.inSeconds) / window.inSeconds)
          .round()
          .clamp(0, maximum);
  static int _total(List<CandidateMatchReason> reasons) =>
      reasons.fold<int>(0, (sum, reason) => sum + reason.weight).clamp(0, 100);
  static String? _clean(String? value) {
    final clean = value?.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    return clean == null || clean.isEmpty ? null : clean;
  }

  static bool _sameOptional(String? a, String? b) =>
      _clean(a) != null && _clean(a) == _clean(b);
  static bool _referencesConflict(String? a, String? b) =>
      _clean(a) != null && _clean(b) != null && _clean(a) != _clean(b);
  static bool _textSupports(String? a, String? b) {
    final left = _clean(a);
    final right = _clean(b);
    return left != null &&
        right != null &&
        (left.contains(right) || right.contains(left));
  }
}
