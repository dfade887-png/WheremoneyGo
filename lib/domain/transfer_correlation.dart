import 'candidate_review.dart';

enum TransferCorrelationKind {
  noCorrelation,
  likelyTransferPair,
  existingTransfer,
  scheduledTransfer,
  ambiguous,
}

final class TransferCorrelationCandidate {
  const TransferCorrelationCandidate({
    required this.id,
    required this.profileId,
    required this.type,
    required this.amountSatang,
    required this.occurredAt,
    required this.pending,
    this.accountId,
    this.referenceNo,
  });

  final String id, profileId, type;
  final int amountSatang;
  final DateTime occurredAt;
  final bool pending;
  final String? accountId, referenceNo;

  bool get outgoing => type == 'expense';
  bool get incoming => type == 'income';
}

final class TransferCorrelationResult {
  const TransferCorrelationResult({
    required this.candidateId,
    required this.kind,
    this.pairedCandidateId,
    this.sourceAccountId,
    this.destinationAccountId,
    this.amountSatang = 0,
    this.timeDelta = Duration.zero,
    this.reasonCodes = const [],
    this.transferGroupId,
    this.scheduledEventId,
  });

  final String candidateId;
  final TransferCorrelationKind kind;
  final String? pairedCandidateId, sourceAccountId, destinationAccountId;
  final int amountSatang;
  final Duration timeDelta;
  final List<String> reasonCodes;
  final String? transferGroupId, scheduledEventId;

  bool get hasPair => pairedCandidateId != null;
}

abstract final class TransferCorrelationPolicy {
  static const window = Duration(minutes: 15);
  static const collisionWindow = Duration(minutes: 2);
}

abstract interface class TransferCorrelationRepository {
  Future<TransferCorrelationResult> correlateCandidate(String candidateId);
  Future<List<TransferCorrelationResult>> correlatePendingCandidates();
  Future<CandidateResolutionResult> confirmCorrelatedTransfer(
    TransferCorrelationResult correlation, {
    bool failAfterTransferOut = false,
    bool failBeforeCandidateUpdates = false,
  });
}

final class TransferCorrelationEngine {
  const TransferCorrelationEngine();

  List<TransferCorrelationResult> correlate(
    List<TransferCorrelationCandidate> candidates,
  ) {
    final active = candidates.where((item) => item.pending).toList()
      ..sort((a, b) {
        final time = a.occurredAt.compareTo(b.occurredAt);
        return time != 0 ? time : a.id.compareTo(b.id);
      });
    final edges = <_Edge>[];
    for (final outgoing in active.where((item) => item.outgoing)) {
      for (final incoming in active.where((item) => item.incoming)) {
        final edge = _eligible(outgoing, incoming);
        if (edge != null) edges.add(edge);
      }
    }
    final byCandidate = <String, List<_Edge>>{};
    for (final edge in edges) {
      byCandidate.putIfAbsent(edge.outgoing.id, () => []).add(edge);
      byCandidate.putIfAbsent(edge.incoming.id, () => []).add(edge);
    }
    for (final list in byCandidate.values) {
      list.sort((a, b) {
        final delta = a.delta.compareTo(b.delta);
        if (delta != 0) return delta;
        final left = '${a.outgoing.id}|${a.incoming.id}';
        final right = '${b.outgoing.id}|${b.incoming.id}';
        return left.compareTo(right);
      });
    }

    final results = <String, TransferCorrelationResult>{};
    for (final candidate in active) {
      final options = byCandidate[candidate.id] ?? const <_Edge>[];
      if (options.isEmpty) {
        results[candidate.id] = TransferCorrelationResult(
          candidateId: candidate.id,
          kind: TransferCorrelationKind.noCorrelation,
        );
        continue;
      }
      final bestDelta = options.first.delta;
      final closeCollisions = options
          .where(
            (edge) =>
                edge.delta - bestDelta <=
                TransferCorrelationPolicy.collisionWindow,
          )
          .length;
      if (closeCollisions > 1) {
        results[candidate.id] = TransferCorrelationResult(
          candidateId: candidate.id,
          kind: TransferCorrelationKind.ambiguous,
          amountSatang: candidate.amountSatang,
          reasonCodes: const ['multiple_close_pairs'],
        );
      }
    }

    for (final edge in edges) {
      if (results[edge.outgoing.id]?.kind ==
              TransferCorrelationKind.ambiguous ||
          results[edge.incoming.id]?.kind ==
              TransferCorrelationKind.ambiguous) {
        continue;
      }
      final outgoingBest = byCandidate[edge.outgoing.id]!.first;
      final incomingBest = byCandidate[edge.incoming.id]!.first;
      if (!identical(edge, outgoingBest) || !identical(edge, incomingBest)) {
        continue;
      }
      final reasons = <String>[
        'exact_amount',
        'opposite_direction',
        'different_accounts',
        if (edge.delta <= const Duration(minutes: 2))
          'time_very_close'
        else if (edge.delta <= const Duration(minutes: 5))
          'time_close'
        else
          'time_within_window',
        if (_clean(edge.outgoing.referenceNo) != null &&
            _clean(edge.outgoing.referenceNo) ==
                _clean(edge.incoming.referenceNo))
          'exact_reference',
      ];
      final pair = TransferCorrelationResult(
        candidateId: edge.outgoing.id,
        pairedCandidateId: edge.incoming.id,
        kind: TransferCorrelationKind.likelyTransferPair,
        sourceAccountId: edge.outgoing.accountId,
        destinationAccountId: edge.incoming.accountId,
        amountSatang: edge.outgoing.amountSatang,
        timeDelta: edge.delta,
        reasonCodes: reasons,
      );
      results[edge.outgoing.id] = pair;
      results[edge.incoming.id] = TransferCorrelationResult(
        candidateId: edge.incoming.id,
        pairedCandidateId: edge.outgoing.id,
        kind: pair.kind,
        sourceAccountId: pair.sourceAccountId,
        destinationAccountId: pair.destinationAccountId,
        amountSatang: pair.amountSatang,
        timeDelta: pair.timeDelta,
        reasonCodes: pair.reasonCodes,
      );
    }
    for (final candidate in active) {
      results.putIfAbsent(
        candidate.id,
        () => TransferCorrelationResult(
          candidateId: candidate.id,
          kind: byCandidate[candidate.id]?.isNotEmpty == true
              ? TransferCorrelationKind.ambiguous
              : TransferCorrelationKind.noCorrelation,
          amountSatang: candidate.amountSatang,
          reasonCodes: byCandidate[candidate.id]?.isNotEmpty == true
              ? const ['pair_collision']
              : const [],
        ),
      );
    }
    return active.map((item) => results[item.id]!).toList(growable: false);
  }

  _Edge? _eligible(
    TransferCorrelationCandidate outgoing,
    TransferCorrelationCandidate incoming,
  ) {
    if (outgoing.id == incoming.id ||
        outgoing.profileId != incoming.profileId ||
        outgoing.accountId == null ||
        incoming.accountId == null ||
        outgoing.accountId == incoming.accountId ||
        outgoing.amountSatang != incoming.amountSatang) {
      return null;
    }
    final delta = outgoing.occurredAt.difference(incoming.occurredAt).abs();
    if (delta > TransferCorrelationPolicy.window) return null;
    return _Edge(outgoing, incoming, delta);
  }

  static String? _clean(String? value) {
    final clean = value?.trim().toLowerCase();
    return clean == null || clean.isEmpty ? null : clean;
  }
}

final class _Edge {
  const _Edge(this.outgoing, this.incoming, this.delta);
  final TransferCorrelationCandidate outgoing, incoming;
  final Duration delta;
}
