import 'package:flutter_test/flutter_test.dart';
import 'package:ngoen_ku_pai_nai/domain/transfer_correlation.dart';

void main() {
  const engine = TransferCorrelationEngine();
  final at = DateTime.utc(2026, 8, 29, 12);

  TransferCorrelationCandidate candidate(
    String id,
    String type, {
    int amount = 10000,
    DateTime? occurredAt,
    String profile = 'profile-a',
    String? account,
    bool pending = true,
  }) => TransferCorrelationCandidate(
    id: id,
    profileId: profile,
    type: type,
    amountSatang: amount,
    occurredAt: occurredAt ?? at,
    pending: pending,
    accountId: account ?? (type == 'expense' ? 'scb' : 'ktb'),
  );

  TransferCorrelationResult result(
    List<TransferCorrelationCandidate> values,
    String id,
  ) => engine.correlate(values).singleWhere((item) => item.candidateId == id);

  test('exact opposite pair inside 15 minutes is suggested both ways', () {
    final values = [
      candidate('out', 'expense'),
      candidate('in', 'income', occurredAt: at.add(const Duration(minutes: 8))),
    ];
    expect(
      result(values, 'out').kind,
      TransferCorrelationKind.likelyTransferPair,
    );
    expect(result(values, 'out').pairedCandidateId, 'in');
    expect(result(values, 'in').pairedCandidateId, 'out');
  });

  test(
    'different amount, same account, same direction, and outside window do not pair',
    () {
      for (final incoming in [
        candidate('different', 'income', amount: 9999),
        candidate('same-account', 'income', account: 'scb'),
        candidate('same-direction', 'expense', account: 'ktb'),
        candidate(
          'late',
          'income',
          occurredAt: at.add(const Duration(minutes: 16)),
        ),
      ]) {
        expect(
          result([candidate('out', 'expense'), incoming], 'out').kind,
          TransferCorrelationKind.noCorrelation,
        );
      }
    },
  );

  test('requires account, same profile, and pending candidates', () {
    final invalid = [
      candidate('missing', 'income', account: null).copyWithAccount(null),
      candidate('profile', 'income', profile: 'profile-b'),
      candidate('resolved', 'income', pending: false),
    ];
    for (final incoming in invalid) {
      expect(
        result([candidate('out', 'expense'), incoming], 'out').kind,
        TransferCorrelationKind.noCorrelation,
      );
    }
  });

  test(
    'two equally plausible candidates are ambiguous and never auto-picked',
    () {
      final values = [
        candidate('out', 'expense'),
        candidate(
          'in-1',
          'income',
          occurredAt: at.add(const Duration(minutes: 4)),
        ),
        candidate(
          'in-2',
          'income',
          occurredAt: at.add(const Duration(minutes: 5)),
        ),
      ];
      expect(result(values, 'out').kind, TransferCorrelationKind.ambiguous);
      expect(result(values, 'out').pairedCandidateId, isNull);
    },
  );

  test('repeated transfers outside collision window remain separate pairs', () {
    final values = [
      candidate('out-1', 'expense'),
      candidate(
        'in-1',
        'income',
        occurredAt: at.add(const Duration(minutes: 1)),
      ),
      candidate(
        'out-2',
        'expense',
        occurredAt: at.add(const Duration(minutes: 10)),
      ),
      candidate(
        'in-2',
        'income',
        occurredAt: at.add(const Duration(minutes: 11)),
      ),
    ];
    expect(result(values, 'out-1').pairedCandidateId, 'in-1');
    expect(result(values, 'out-2').pairedCandidateId, 'in-2');
  });

  test('closest-time choice is deterministic regardless of input order', () {
    final values = [
      candidate('out', 'expense'),
      candidate('far', 'income', occurredAt: at.add(const Duration(minutes: 9))),
      candidate('near', 'income', occurredAt: at.add(const Duration(minutes: 3))),
    ];
    expect(result(values, 'out').pairedCandidateId, 'near');
    expect(result(values.reversed.toList(), 'out').pairedCandidateId, 'near');
  });

  test('child and summary evidence remain one candidate input', () {
    final values = [
      candidate('grouped-child-summary', 'expense'),
      candidate('incoming', 'income', occurredAt: at.add(const Duration(minutes: 1))),
    ];
    expect(engine.correlate(values), hasLength(2));
    expect(result(values, 'grouped-child-summary').pairedCandidateId, 'incoming');
  });
}

extension on TransferCorrelationCandidate {
  TransferCorrelationCandidate copyWithAccount(String? accountId) =>
      TransferCorrelationCandidate(
        id: id,
        profileId: profileId,
        type: type,
        amountSatang: amountSatang,
        occurredAt: occurredAt,
        pending: pending,
        accountId: accountId,
        referenceNo: referenceNo,
      );
}
