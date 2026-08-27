import '../salary_projection.dart';

abstract interface class SalaryProjectionRepository {
  Future<SalaryProjectionResult> projectSalaryPaydaysToScheduledEvents({
    required DateTime referenceDate,
    Set<DateTime> manualHolidays = const {},
  });
}
