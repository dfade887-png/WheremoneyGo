import 'package:flutter_test/flutter_test.dart';
import 'package:ngoen_ku_pai_nai/domain/bank_notification/pending_transfer_matcher.dart';

void main() {
  PendingBankEvent event(
    String id,
    PendingDirection direction,
    int amount,
    int minute, {
    String package = 'bank',
    String status = 'pending',
  }) => PendingBankEvent(
    id: id,
    sourcePackage: package,
    amountSatang: amount,
    detectedAt: DateTime.utc(2026, 8, 12, 12, minute),
    direction: direction,
    status: status,
  );

  test('equal amount in time window suggests pending transfer', () {
    final matches = PendingTransferMatcher.correlate([
      event('out', PendingDirection.outgoing, 50000, 0),
      event('in', PendingDirection.incoming, 50000, 3, package: 'wallet'),
    ]);
    expect(matches, hasLength(1));
    expect(matches.single.amountSatang, 50000);
  });

  test('amount mismatch and outside window do not match', () {
    expect(
      PendingTransferMatcher.correlate([
        event('out', PendingDirection.outgoing, 50000, 0),
        event('in', PendingDirection.incoming, 51000, 1, package: 'wallet'),
      ]),
      isEmpty,
    );
    expect(
      PendingTransferMatcher.correlate([
        event('out', PendingDirection.outgoing, 50000, 0),
        event('in', PendingDirection.incoming, 50000, 8, package: 'wallet'),
      ]),
      isEmpty,
    );
  });

  test('confirmed event is excluded and key is deterministic', () {
    final input = [
      event('out', PendingDirection.outgoing, 50000, 0),
      event('in', PendingDirection.incoming, 50000, 1, package: 'wallet'),
    ];
    expect(
      PendingTransferMatcher.correlate(input).single.idempotencyKey,
      PendingTransferMatcher.correlate(input.reversed).single.idempotencyKey,
    );
    expect(
      PendingTransferMatcher.correlate([
        input.first,
        event(
          'in',
          PendingDirection.incoming,
          50000,
          1,
          package: 'wallet',
          status: 'confirmed',
        ),
      ]),
      isEmpty,
    );
  });
}
