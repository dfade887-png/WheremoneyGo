/// The architectural layer that owns a financial record.
///
/// Only [realLedger] represents money that has actually occurred. The other
/// layers are plans or evidence and must never affect Actual Balance directly.
enum FinancialRecordLayer {
  realLedger,
  scheduled,
  candidate,
  rawNotification,
  unconfirmedStatement,
}

extension FinancialRecordLayerBalanceSemantics on FinancialRecordLayer {
  bool get affectsActualBalance => this == FinancialRecordLayer.realLedger;
}

/// Compatibility states from schema v4. This is intentionally separate from
/// the approved lifecycle and must not be used for future scheduled events.
enum LegacyTransactionStatus { pending, confirmed, deleted }

/// Persisted states for a future financial event.
///
/// `due` is deliberately absent: it is derived from [dueAt] and the clock.
enum ScheduledEventStoredState { scheduled, fulfilled, skipped, cancelled }

/// Effective lifecycle state exposed to domain consumers.
enum ScheduledEventState { scheduled, due, fulfilled, skipped, cancelled }

abstract final class TransactionLifecycle {
  /// A schema-v4 transaction is safe to treat as real ledger money only when
  /// it is confirmed and has not been soft-deleted.
  static bool legacyTransactionAffectsActualBalance({
    required LegacyTransactionStatus status,
    required DateTime? deletedAt,
  }) => status == LegacyTransactionStatus.confirmed && deletedAt == null;

  /// Derives `due` without requiring a persisted midnight status update.
  static ScheduledEventState effectiveScheduledState({
    required ScheduledEventStoredState storedState,
    required DateTime dueAt,
    required DateTime now,
  }) {
    switch (storedState) {
      case ScheduledEventStoredState.scheduled:
        return now.isBefore(dueAt)
            ? ScheduledEventState.scheduled
            : ScheduledEventState.due;
      case ScheduledEventStoredState.fulfilled:
        return ScheduledEventState.fulfilled;
      case ScheduledEventStoredState.skipped:
        return ScheduledEventState.skipped;
      case ScheduledEventStoredState.cancelled:
        return ScheduledEventState.cancelled;
    }
  }

  /// Confirmation is represented by a direct transition to `fulfilled`.
  /// The posted ledger transaction is the financial record; there is no
  /// intermediate confirmed/posted state for a scheduled event.
  static bool canTransitionScheduledEvent({
    required ScheduledEventState from,
    required ScheduledEventStoredState to,
  }) {
    if (from != ScheduledEventState.scheduled &&
        from != ScheduledEventState.due) {
      return false;
    }
    return to == ScheduledEventStoredState.fulfilled ||
        to == ScheduledEventStoredState.skipped ||
        to == ScheduledEventStoredState.cancelled;
  }
}
