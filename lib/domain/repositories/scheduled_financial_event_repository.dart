import '../models/scheduled_financial_event.dart';
import '../transaction_lifecycle.dart';

abstract interface class ScheduledFinancialEventRepository {
  Future<ScheduledFinancialEvent> createScheduledEvent({
    required ScheduledEventType eventType,
    required int amountSatang,
    required String title,
    required String accountId,
    required DateTime scheduledAt,
    String? destinationAccountId,
    String? categoryId,
    String? note,
    DateTime? dueAt,
    String originType = 'manual',
    String? originId,
    String? occurrenceKey,
  });

  Future<List<ScheduledFinancialEvent>> scheduledEvents({
    DateTime? from,
    DateTime? to,
    String? accountId,
    Set<ScheduledEventStoredState>? statuses,
    bool includeDeleted = false,
  });

  Future<ScheduledFinancialEvent> updateScheduledEvent({
    required String id,
    required ScheduledEventType eventType,
    required int amountSatang,
    required String title,
    required String accountId,
    required DateTime scheduledAt,
    String? destinationAccountId,
    String? categoryId,
    String? note,
    DateTime? dueAt,
  });

  Future<ScheduledFinancialEvent> cancelScheduledEvent(String id);
  Future<ScheduledFinancialEvent> skipScheduledEvent(String id);

  Future<String> confirmScheduledEvent(
    String id, {
    DateTime? occurredAt,
    bool failAfterLedgerInsert = false,
    bool failAfterOccurrenceLink = false,
    bool failAfterCommitmentPayment = false,
  });

  Future<String> confirmScheduledTransfer(
    String id, {
    DateTime? occurredAt,
    bool failAfterTransferOut = false,
    bool failBeforeFulfillment = false,
  });
}
