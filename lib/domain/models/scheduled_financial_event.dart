import '../transaction_lifecycle.dart';

enum ScheduledEventType { income, expense, refund, transfer }

final class ScheduledFinancialEvent {
  const ScheduledFinancialEvent({
    required this.id,
    required this.profileId,
    required this.accountId,
    required this.eventType,
    required this.amountSatang,
    required this.title,
    required this.scheduledAt,
    required this.storedStatus,
    required this.originType,
    required this.occurrenceKey,
    required this.createdAt,
    required this.updatedAt,
    this.destinationAccountId,
    this.categoryId,
    this.note,
    this.dueAt,
    this.originId,
    this.linkedTransactionId,
    this.linkedTransferGroupId,
    this.cancelledAt,
  });

  final String id;
  final String profileId;
  final String accountId;
  final String? destinationAccountId;
  final String? categoryId;
  final ScheduledEventType eventType;
  final int amountSatang;
  final String title;
  final String? note;
  final DateTime scheduledAt;
  final DateTime? dueAt;
  final ScheduledEventStoredState storedStatus;
  final String originType;
  final String? originId;
  final String occurrenceKey;
  final String? linkedTransactionId;
  final String? linkedTransferGroupId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? cancelledAt;

  ScheduledEventState effectiveStatus(DateTime now) =>
      TransactionLifecycle.effectiveScheduledState(
        storedState: storedStatus,
        dueAt: dueAt ?? scheduledAt,
        now: now,
      );

  bool get isEditable => storedStatus == ScheduledEventStoredState.scheduled;

  factory ScheduledFinancialEvent.fromRow(Map<String, Object?> row) =>
      ScheduledFinancialEvent(
        id: row['id'] as String,
        profileId: row['profile_id'] as String,
        accountId: row['account_id'] as String,
        destinationAccountId: row['destination_account_id'] as String?,
        categoryId: row['category_id'] as String?,
        eventType: ScheduledEventType.values.byName(
          row['event_type'] as String,
        ),
        amountSatang: row['amount_satang'] as int,
        title: row['title'] as String,
        note: row['note'] as String?,
        scheduledAt: DateTime.parse(row['scheduled_at'] as String),
        dueAt: _optionalDate(row['due_at']),
        storedStatus: ScheduledEventStoredState.values.byName(
          row['stored_status'] as String,
        ),
        originType: row['origin_type'] as String,
        originId: row['origin_id'] as String?,
        occurrenceKey: row['occurrence_key'] as String,
        linkedTransactionId: row['linked_transaction_id'] as String?,
        linkedTransferGroupId: row['linked_transfer_group_id'] as String?,
        createdAt: DateTime.parse(row['created_at'] as String),
        updatedAt: DateTime.parse(row['updated_at'] as String),
        cancelledAt: _optionalDate(row['cancelled_at']),
      );

  static DateTime? _optionalDate(Object? value) =>
      value == null ? null : DateTime.parse(value as String);
}
