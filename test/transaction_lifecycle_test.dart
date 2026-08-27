import 'package:flutter_test/flutter_test.dart';
import 'package:ngoen_ku_pai_nai/domain/transaction_lifecycle.dart';

void main() {
  group('transaction lifecycle contract', () {
    test('only real ledger records can affect Actual Balance', () {
      for (final layer in FinancialRecordLayer.values) {
        expect(
          layer.affectsActualBalance,
          layer == FinancialRecordLayer.realLedger,
          reason: '$layer must not affect Actual Balance',
        );
      }
    });

    test('legacy compatibility admits confirmed non-deleted records only', () {
      expect(
        TransactionLifecycle.legacyTransactionAffectsActualBalance(
          status: LegacyTransactionStatus.confirmed,
          deletedAt: null,
        ),
        isTrue,
      );
      expect(
        TransactionLifecycle.legacyTransactionAffectsActualBalance(
          status: LegacyTransactionStatus.pending,
          deletedAt: null,
        ),
        isFalse,
      );
      expect(
        TransactionLifecycle.legacyTransactionAffectsActualBalance(
          status: LegacyTransactionStatus.deleted,
          deletedAt: null,
        ),
        isFalse,
      );
      expect(
        TransactionLifecycle.legacyTransactionAffectsActualBalance(
          status: LegacyTransactionStatus.confirmed,
          deletedAt: DateTime.utc(2026, 8, 18),
        ),
        isFalse,
      );
    });

    test('due is derived from time and is never persisted', () {
      final dueAt = DateTime.utc(2026, 8, 18, 12);
      expect(
        TransactionLifecycle.effectiveScheduledState(
          storedState: ScheduledEventStoredState.scheduled,
          dueAt: dueAt,
          now: dueAt.subtract(const Duration(seconds: 1)),
        ),
        ScheduledEventState.scheduled,
      );
      expect(
        TransactionLifecycle.effectiveScheduledState(
          storedState: ScheduledEventStoredState.scheduled,
          dueAt: dueAt,
          now: dueAt,
        ),
        ScheduledEventState.due,
      );
    });

    test('scheduled and due can only reach approved terminal states', () {
      for (final from in [
        ScheduledEventState.scheduled,
        ScheduledEventState.due,
      ]) {
        for (final to in [
          ScheduledEventStoredState.fulfilled,
          ScheduledEventStoredState.skipped,
          ScheduledEventStoredState.cancelled,
        ]) {
          expect(
            TransactionLifecycle.canTransitionScheduledEvent(
              from: from,
              to: to,
            ),
            isTrue,
          );
        }
        expect(
          TransactionLifecycle.canTransitionScheduledEvent(
            from: from,
            to: ScheduledEventStoredState.scheduled,
          ),
          isFalse,
        );
      }
    });

    test('fulfilled skipped and cancelled are terminal', () {
      for (final from in [
        ScheduledEventState.fulfilled,
        ScheduledEventState.skipped,
        ScheduledEventState.cancelled,
      ]) {
        for (final to in ScheduledEventStoredState.values) {
          expect(
            TransactionLifecycle.canTransitionScheduledEvent(
              from: from,
              to: to,
            ),
            isFalse,
          );
        }
      }
    });
  });
}
