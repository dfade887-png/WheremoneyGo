import '../financial_calendar.dart';

abstract interface class FinancialCalendarRepository {
  Future<FinancialCalendarResult> calendarEvents({
    required DateTime from,
    required DateTime to,
    required DateTime now,
    Set<FinancialCalendarDisplayStatus>? statuses,
    bool includeActual = true,
  });
}
