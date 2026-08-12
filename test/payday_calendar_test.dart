import 'package:flutter_test/flutter_test.dart';
import 'package:ngoen_ku_pai_nai/domain/payday_calendar.dart';

void main() {
  test('short month uses its final calendar day', () {
    expect(
      PaydayCalendar.resolve(
        year: 2027,
        month: 2,
        payday: 31,
        policy: PaydayHolidayPolicy.exact,
      ),
      DateTime(2027, 2, 28),
    );
    expect(
      PaydayCalendar.resolve(
        year: 2028,
        month: 2,
        payday: 31,
        policy: PaydayHolidayPolicy.exact,
      ),
      DateTime(2028, 2, 29),
    );
  });

  test('weekend resolves before or after', () {
    expect(
      PaydayCalendar.resolve(
        year: 2026,
        month: 8,
        payday: 1,
        policy: PaydayHolidayPolicy.before,
      ),
      DateTime(2026, 7, 31),
    );
    expect(
      PaydayCalendar.resolve(
        year: 2026,
        month: 8,
        payday: 1,
        policy: PaydayHolidayPolicy.after,
      ),
      DateTime(2026, 8, 3),
    );
  });

  test('manual holiday participates without network', () {
    expect(
      PaydayCalendar.resolve(
        year: 2026,
        month: 8,
        payday: 25,
        policy: PaydayHolidayPolicy.after,
        manualHolidays: {DateTime(2026, 8, 25)},
      ),
      DateTime(2026, 8, 26),
    );
  });

  test('cycle crosses year correctly', () {
    final cycle = PaydayCalendar.cycleContaining(
      date: DateTime(2027, 1, 3),
      payday: 25,
      policy: PaydayHolidayPolicy.exact,
    );
    expect(cycle.$1, DateTime(2026, 12, 25));
    expect(cycle.$2, DateTime(2027, 1, 24));
  });
}
