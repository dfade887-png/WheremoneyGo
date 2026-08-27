import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ngoen_ku_pai_nai/data/repositories/sqlite_finance_repository.dart';
import 'package:ngoen_ku_pai_nai/domain/models/scheduled_financial_event.dart';
import 'package:ngoen_ku_pai_nai/domain/transaction_lifecycle.dart';

void main() {
  late SqliteFinanceRepository repository;
  late String accountId;
  late String categoryId;
  const salaryProfileId = 'salary-config';
  final reference = DateTime.utc(2026, 8, 18);

  void configureSalary({
    int gross = 1800000,
    int deduction = 87500,
    int payday = 27,
    String holidayRule = 'before',
  }) {
    final now = DateTime.now().toUtc().toIso8601String();
    repository.execute(
      '''INSERT OR REPLACE INTO salary_profiles(id,gross_salary_satang,created_at,updated_at,profile_id)
         VALUES(?,?,?,?,?)''',
      [salaryProfileId, gross, now, now, repository.activeProfileId],
    );
    repository.execute(
      "DELETE FROM payroll_deductions WHERE salary_profile_id=?",
      [salaryProfileId],
    );
    if (deduction > 0) {
      repository.execute(
        '''INSERT INTO payroll_deductions(id,salary_profile_id,name,amount_satang,is_active,created_at,updated_at,profile_id)
           VALUES(?,?,?,?,1,?,?,?)''',
        [
          'social-security',
          salaryProfileId,
          'ประกันสังคม',
          deduction,
          now,
          now,
          repository.activeProfileId,
        ],
      );
    }
    repository.execute(
      '''INSERT INTO profile_settings(id,profile_id,key,value,created_at,updated_at)
         VALUES('salary-payday-setting',?,'onboarding_profile_v1',?,?,?)
         ON CONFLICT(profile_id,key) DO UPDATE SET value=excluded.value,updated_at=excluded.updated_at,deleted_at=NULL''',
      [
        repository.activeProfileId,
        jsonEncode({'payday': payday, 'holidayRule': holidayRule}),
        now,
        now,
      ],
    );
  }

  setUp(() async {
    repository = SqliteFinanceRepository.memory();
    accountId = await repository.createAccount(
      name: 'SCB salary',
      type: 'bank',
      openingBalanceSatang: 1000000,
      salaryAccount: true,
    );
    categoryId = await repository.createCategory(
      name: 'เงินเดือน',
      type: 'income',
      iconKey: 'salary',
    );
    configureSalary();
  });

  tearDown(() => repository.dispose());

  Future<List<ScheduledFinancialEvent>> project() async {
    await repository.projectSalaryPaydaysToScheduledEvents(
      referenceDate: reference,
    );
    return repository.scheduledEvents();
  }

  test('projects previous one and next six net salary events', () async {
    final result = await repository.projectSalaryPaydaysToScheduledEvents(
      referenceDate: reference,
    );
    final events = await repository.scheduledEvents();
    expect(result.createdCount, 7);
    expect(events, hasLength(7));
    expect(
      events.every((event) => event.eventType == ScheduledEventType.income),
      isTrue,
    );
    expect(events.every((event) => event.amountSatang == 1712500), isTrue);
    expect(events.every((event) => event.accountId == accountId), isTrue);
    expect(events.every((event) => event.categoryId == categoryId), isTrue);
    expect(
      events.every((event) => event.originType == 'salary_payday'),
      isTrue,
    );
    expect(events.first.scheduledAt, DateTime.utc(2026, 7, 27));
    expect(events.first.occurrenceKey, '2026-07');
  });

  test('payday resolver shifts weekend before and manual holiday', () async {
    final events = await project();
    expect(
      events.map((event) => event.scheduledAt),
      contains(DateTime.utc(2026, 9, 25)),
    );
    final holidayResult = await repository
        .projectSalaryPaydaysToScheduledEvents(
          referenceDate: reference,
          manualHolidays: {DateTime(2026, 8, 27)},
        );
    expect(holidayResult.updatedCount, 1);
    expect(holidayResult.createdCount, 0);
    expect(holidayResult.cancelledCount, 0);
    expect(
      (await repository.scheduledEvents()).map((event) => event.scheduledAt),
      contains(DateTime.utc(2026, 8, 26)),
    );
  });

  test('projection is idempotent and unchanged run is a no-op', () async {
    await project();
    final second = await repository.projectSalaryPaydaysToScheduledEvents(
      referenceDate: reference,
    );
    expect(second.createdCount, 0);
    expect(second.updatedCount, 0);
    expect(second.cancelledCount, 0);
    expect(await repository.scheduledEvents(), hasLength(7));
  });

  test('due salary remains projected without auto-posting', () async {
    final events = await project();
    final previous = events.first;
    expect(
      previous.effectiveStatus(DateTime.utc(2026, 8, 18)),
      ScheduledEventState.due,
    );
    final projected = await repository.projectedBalance(cutoff: reference);
    expect(projected.account(accountId).actualBalanceSatang, 1000000);
    expect(projected.account(accountId).projectedBalanceSatang, 2712500);
    expect(await repository.ledgerTransactionCount(), 0);
  });

  test('salary affects Projected once and generic T6 confirms early', () async {
    final events = await project();
    await repository.skipScheduledEvent(events.first.id);
    final august = events.singleWhere(
      (event) => event.occurrenceKey == '2026-08',
    );
    final before = await repository.projectedBalance(
      cutoff: DateTime.utc(2026, 8, 27),
    );
    expect(before.account(accountId).actualBalanceSatang, 1000000);
    expect(before.account(accountId).projectedBalanceSatang, 2712500);

    final actualArrival = DateTime.utc(2026, 8, 26, 9);
    final transactionId = await repository.confirmScheduledEvent(
      august.id,
      occurredAt: actualArrival,
    );
    final transaction = repository.query(
      'SELECT * FROM transactions WHERE id=?',
      [transactionId],
    ).single;
    expect(transaction['type'], 'income');
    expect(transaction['source'], 'scheduled_event');
    expect(transaction['occurred_at'], actualArrival.toIso8601String());
    final after = await repository.projectedBalance(
      cutoff: DateTime.utc(2026, 8, 27),
    );
    expect(after.account(accountId).actualBalanceSatang, 2712500);
    expect(after.account(accountId).projectedBalanceSatang, 2712500);
  });

  test(
    'amount update changes future active events but preserves fulfilled',
    () async {
      final events = await project();
      final previous = events.first;
      await repository.confirmScheduledEvent(previous.id);
      configureSalary(gross: 2000000, deduction: 0);
      final result = await repository.projectSalaryPaydaysToScheduledEvents(
        referenceDate: reference,
      );
      final refreshed = await repository.scheduledEvents();
      expect(result.updatedCount, 6);
      expect(
        refreshed.singleWhere((event) => event.id == previous.id).amountSatang,
        1712500,
      );
      expect(
        refreshed
            .where(
              (event) =>
                  event.storedStatus == ScheduledEventStoredState.scheduled,
            )
            .every((event) => event.amountSatang == 2000000),
        isTrue,
      );
    },
  );

  test('payday change updates future occurrence dates in place', () async {
    await project();
    configureSalary(payday: 28);
    final result = await repository.projectSalaryPaydaysToScheduledEvents(
      referenceDate: reference,
    );
    expect(result.updatedCount, 5);
    expect(result.cancelledCount, 0);
    expect(result.createdCount, 0);
    expect(
      (await repository.scheduledEvents()).where(
        (event) =>
            event.storedStatus == ScheduledEventStoredState.scheduled &&
            !event.scheduledAt.isBefore(reference),
      ),
      isNotEmpty,
    );
  });

  test('removed config cancels future active events only', () async {
    final events = await project();
    repository.execute('UPDATE salary_profiles SET deleted_at=? WHERE id=?', [
      DateTime.now().toUtc().toIso8601String(),
      salaryProfileId,
    ]);
    final result = await repository.projectSalaryPaydaysToScheduledEvents(
      referenceDate: reference,
    );
    expect(result.unresolvedReasons, contains('salary_profile'));
    expect(result.cancelledCount, 6);
    final refreshed = await repository.scheduledEvents();
    expect(
      refreshed
          .singleWhere((event) => event.id == events.first.id)
          .storedStatus,
      ScheduledEventStoredState.scheduled,
    );
  });

  test(
    'missing account or category is unresolved and creates no event',
    () async {
      repository.execute('UPDATE accounts SET is_salary_account=0');
      var result = await repository.projectSalaryPaydaysToScheduledEvents(
        referenceDate: reference,
      );
      expect(result.unresolvedReasons, contains('salary_account'));
      expect(await repository.scheduledEvents(), isEmpty);
      repository.execute('UPDATE accounts SET is_salary_account=1');
      repository.execute('UPDATE categories SET deleted_at=? WHERE id=?', [
        DateTime.now().toUtc().toIso8601String(),
        categoryId,
      ]);
      result = await repository.projectSalaryPaydaysToScheduledEvents(
        referenceDate: reference,
      );
      expect(result.unresolvedReasons, contains('salary_category'));
      expect(await repository.scheduledEvents(), isEmpty);
    },
  );

  test('salary projection is isolated to active profile', () async {
    await project();
    final profileB = await repository.createProfile('B', draft: false);
    await repository.switchProfile(profileB);
    final result = await repository.projectSalaryPaydaysToScheduledEvents(
      referenceDate: reference,
    );
    expect(result.createdCount, 0);
    expect(result.unresolvedReasons, isNotEmpty);
    expect(await repository.scheduledEvents(), isEmpty);
  });
}
