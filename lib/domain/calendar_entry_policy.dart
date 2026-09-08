enum CalendarEntryKind { confirmed, scheduled }

/// Product boundary: past/today are real confirmed entries; future dates are plans.
abstract final class CalendarEntryPolicy {
  static CalendarEntryKind kindFor(DateTime selected, DateTime now) {
    final day = DateTime(selected.year, selected.month, selected.day);
    final today = DateTime(now.year, now.month, now.day);
    return day.isAfter(today)
        ? CalendarEntryKind.scheduled
        : CalendarEntryKind.confirmed;
  }

  static DateTime confirmedOccurredAt(DateTime selected, DateTime now) {
    if (kindFor(selected, now) != CalendarEntryKind.confirmed) {
      throw ArgumentError('Future calendar dates require a scheduled event');
    }
    return DateTime(
      selected.year,
      selected.month,
      selected.day,
      now.hour,
      now.minute,
      now.second,
      now.millisecond,
      now.microsecond,
    );
  }
}
