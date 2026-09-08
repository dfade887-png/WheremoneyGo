import 'package:flutter_test/flutter_test.dart';
import 'package:ngoen_ku_pai_nai/domain/calendar_entry_policy.dart';

void main() {
  final now = DateTime(2026, 9, 8, 14, 35);

  test('past and today are confirmed while future remains scheduled', () {
    expect(
      CalendarEntryPolicy.kindFor(DateTime(2026, 9, 7), now),
      CalendarEntryKind.confirmed,
    );
    expect(
      CalendarEntryPolicy.kindFor(DateTime(2026, 9, 8), now),
      CalendarEntryKind.confirmed,
    );
    expect(
      CalendarEntryPolicy.kindFor(DateTime(2026, 9, 9), now),
      CalendarEntryKind.scheduled,
    );
  });

  test('backdated occurrence keeps selected date and current clock time', () {
    final occurred = CalendarEntryPolicy.confirmedOccurredAt(
      DateTime(2026, 9, 7),
      now,
    );
    expect(occurred, DateTime(2026, 9, 7, 14, 35));
  });

  test('future date cannot use confirmed calendar entry boundary', () {
    expect(
      () => CalendarEntryPolicy.confirmedOccurredAt(DateTime(2026, 9, 9), now),
      throwsArgumentError,
    );
  });
}
