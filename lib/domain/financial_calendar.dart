import 'models/scheduled_financial_event.dart';
import 'transaction_lifecycle.dart';

enum FinancialCalendarEventType { income, expense, refund, transfer }

enum FinancialCalendarDirection { incoming, outgoing, transfer }

enum FinancialCalendarDisplayStatus {
  scheduled,
  due,
  fulfilled,
  skipped,
  cancelled,
  actual,
}

enum FinancialCalendarOriginKind {
  manualSchedule,
  commitment,
  salary,
  manualTransaction,
  scheduledConfirmation,
}

enum FinancialCalendarActuality { planned, actual }

final class FinancialCalendarEvent {
  const FinancialCalendarEvent({
    required this.id,
    required this.dateTime,
    required this.title,
    required this.amountSatang,
    required this.eventType,
    required this.direction,
    required this.accountId,
    required this.displayStatus,
    required this.originKind,
    required this.actuality,
    required this.createdAt,
    this.note,
    this.destinationAccountId,
    this.categoryId,
    this.scheduledEventId,
    this.transactionId,
    this.transferGroupId,
  });

  final String id;
  final DateTime dateTime;
  final String title;
  final String? note;
  final int amountSatang;
  final FinancialCalendarEventType eventType;
  final FinancialCalendarDirection direction;
  final String accountId;
  final String? destinationAccountId;
  final String? categoryId;
  final FinancialCalendarDisplayStatus displayStatus;
  final FinancialCalendarOriginKind originKind;
  final String? scheduledEventId;
  final String? transactionId;
  final String? transferGroupId;
  final FinancialCalendarActuality actuality;
  final DateTime createdAt;

  bool get isTransfer => eventType == FinancialCalendarEventType.transfer;
  bool get isActionRequired =>
      displayStatus == FinancialCalendarDisplayStatus.due;
}

final class FinancialCalendarResult {
  FinancialCalendarResult({
    required Iterable<FinancialCalendarEvent> events,
    required Iterable<String> excludedBrokenTransferGroupIds,
  }) : events = List.unmodifiable(events),
       excludedBrokenTransferGroupIds = List.unmodifiable(
         excludedBrokenTransferGroupIds,
       );

  final List<FinancialCalendarEvent> events;
  final List<String> excludedBrokenTransferGroupIds;
}

abstract final class FinancialCalendarMapper {
  static FinancialCalendarEvent fromScheduled(
    ScheduledFinancialEvent event, {
    required DateTime now,
  }) {
    final effective = event.effectiveStatus(now);
    final status = switch (effective) {
      ScheduledEventState.scheduled => FinancialCalendarDisplayStatus.scheduled,
      ScheduledEventState.due => FinancialCalendarDisplayStatus.due,
      ScheduledEventState.fulfilled => FinancialCalendarDisplayStatus.fulfilled,
      ScheduledEventState.skipped => FinancialCalendarDisplayStatus.skipped,
      ScheduledEventState.cancelled => FinancialCalendarDisplayStatus.cancelled,
    };
    final type = FinancialCalendarEventType.values.byName(event.eventType.name);
    return FinancialCalendarEvent(
      id: 'scheduled:${event.id}',
      dateTime: (event.dueAt ?? event.scheduledAt).toUtc(),
      title: event.title,
      note: event.note,
      amountSatang: event.amountSatang,
      eventType: type,
      direction: _direction(type),
      accountId: event.accountId,
      destinationAccountId: event.destinationAccountId,
      categoryId: event.categoryId,
      displayStatus: status,
      originKind: switch (event.originType) {
        'commitment_occurrence' => FinancialCalendarOriginKind.commitment,
        'salary_payday' => FinancialCalendarOriginKind.salary,
        _ => FinancialCalendarOriginKind.manualSchedule,
      },
      scheduledEventId: event.id,
      transactionId: event.linkedTransactionId,
      transferGroupId: event.linkedTransferGroupId,
      actuality: status == FinancialCalendarDisplayStatus.fulfilled
          ? FinancialCalendarActuality.actual
          : FinancialCalendarActuality.planned,
      createdAt: event.createdAt.toUtc(),
    );
  }

  static FinancialCalendarDirection _direction(
    FinancialCalendarEventType type,
  ) => switch (type) {
    FinancialCalendarEventType.income ||
    FinancialCalendarEventType.refund => FinancialCalendarDirection.incoming,
    FinancialCalendarEventType.expense => FinancialCalendarDirection.outgoing,
    FinancialCalendarEventType.transfer => FinancialCalendarDirection.transfer,
  };
}
