import 'dart:convert';

import 'package:crypto/crypto.dart';

enum PendingDirection { incoming, outgoing }

final class PendingBankEvent {
  const PendingBankEvent({
    required this.id,
    required this.sourcePackage,
    required this.amountSatang,
    required this.detectedAt,
    required this.direction,
    required this.status,
  });

  final String id;
  final String sourcePackage;
  final int amountSatang;
  final DateTime detectedAt;
  final PendingDirection direction;
  final String status;
}

final class PendingTransferSuggestion {
  const PendingTransferSuggestion({
    required this.idempotencyKey,
    required this.outgoingEventId,
    required this.incomingEventId,
    required this.amountSatang,
  });

  final String idempotencyKey;
  final String outgoingEventId;
  final String incomingEventId;
  final int amountSatang;
}

abstract final class PendingTransferMatcher {
  static List<PendingTransferSuggestion> correlate(
    Iterable<PendingBankEvent> events, {
    Duration window = const Duration(minutes: 5),
  }) {
    final pending = events.where((event) => event.status == 'pending').toList();
    final suggestions = <PendingTransferSuggestion>[];
    final used = <String>{};
    for (final outgoing in pending.where(
      (e) => e.direction == PendingDirection.outgoing,
    )) {
      final candidates =
          pending.where((incoming) {
            final delta = incoming.detectedAt
                .difference(outgoing.detectedAt)
                .abs();
            return incoming.direction == PendingDirection.incoming &&
                incoming.sourcePackage != outgoing.sourcePackage &&
                incoming.amountSatang == outgoing.amountSatang &&
                delta <= window &&
                !used.contains(incoming.id);
          }).toList()..sort(
            (a, b) => a.detectedAt
                .difference(outgoing.detectedAt)
                .abs()
                .compareTo(b.detectedAt.difference(outgoing.detectedAt).abs()),
          );
      if (candidates.length != 1 || used.contains(outgoing.id)) continue;
      final incoming = candidates.single;
      used
        ..add(outgoing.id)
        ..add(incoming.id);
      final ids = [outgoing.id, incoming.id]..sort();
      suggestions.add(
        PendingTransferSuggestion(
          idempotencyKey: sha256
              .convert(
                utf8.encode(
                  'transfer|${ids.join('|')}|${outgoing.amountSatang}',
                ),
              )
              .toString(),
          outgoingEventId: outgoing.id,
          incomingEventId: incoming.id,
          amountSatang: outgoing.amountSatang,
        ),
      );
    }
    return suggestions;
  }
}
