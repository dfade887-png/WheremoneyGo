enum PaydayHolidayPolicy { before, after, exact }

abstract final class PaydayCalendar {
  static DateTime resolve({
    required int year,
    required int month,
    required int payday,
    required PaydayHolidayPolicy policy,
    Set<DateTime> manualHolidays = const {},
  }) {
    if (payday < 1 || payday > 31) {
      throw ArgumentError.value(payday, 'payday');
    }
    final lastDay = DateTime(year, month + 1, 0).day;
    var date = DateTime(year, month, payday.clamp(1, lastDay));
    if (policy == PaydayHolidayPolicy.exact) return date;
    final direction = policy == PaydayHolidayPolicy.before ? -1 : 1;
    while (_isHoliday(date, manualHolidays)) {
      date = date.add(Duration(days: direction));
    }
    return date;
  }

  static (DateTime start, DateTime end) cycleContaining({
    required DateTime date,
    required int payday,
    required PaydayHolidayPolicy policy,
    Set<DateTime> manualHolidays = const {},
  }) {
    final current = resolve(
      year: date.year,
      month: date.month,
      payday: payday,
      policy: policy,
      manualHolidays: manualHolidays,
    );
    final useCurrent = !DateTime(
      date.year,
      date.month,
      date.day,
    ).isBefore(current);
    final startMonth = useCurrent ? date.month : date.month - 1;
    final start = resolve(
      year: date.year,
      month: startMonth,
      payday: payday,
      policy: policy,
      manualHolidays: manualHolidays,
    );
    final next = resolve(
      year: start.year,
      month: start.month + 1,
      payday: payday,
      policy: policy,
      manualHolidays: manualHolidays,
    );
    return (start, next.subtract(const Duration(days: 1)));
  }

  static bool _isHoliday(DateTime date, Set<DateTime> manual) {
    final day = DateTime(date.year, date.month, date.day);
    return date.weekday == DateTime.saturday ||
        date.weekday == DateTime.sunday ||
        manual.any(
          (value) =>
              value.year == day.year &&
              value.month == day.month &&
              value.day == day.day,
        );
  }
}
