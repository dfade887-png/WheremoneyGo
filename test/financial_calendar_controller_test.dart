import 'package:flutter_test/flutter_test.dart';
import 'package:ngoen_ku_pai_nai/data/repositories/sqlite_finance_repository.dart';
import 'package:ngoen_ku_pai_nai/domain/models/scheduled_financial_event.dart';
import 'package:ngoen_ku_pai_nai/ui/financial_calendar_controller.dart';

void main() {
  late SqliteFinanceRepository repository;
  late String account;
  late String category;
  late String incomeCategory;
  final now = DateTime(2026, 8, 18, 10);

  setUp(() async {
    repository = SqliteFinanceRepository.memory();
    account = await repository.createAccount(
      name: 'SCB',
      type: 'bank',
      openingBalanceSatang: 1605300,
    );
    category = await repository.createCategory(
      name: 'ทำฟัน',
      type: 'expense',
      iconKey: 'health',
    );
    incomeCategory = await repository.createCategory(
      name: 'รายรับ',
      type: 'income',
      iconKey: 'income',
    );
  });

  tearDown(() => repository.dispose());

  FinancialCalendarController makeController() => FinancialCalendarController(
    calendarRepository: repository,
    projectedBalanceRepository: repository,
    confirmationRepository: repository,
    now: () => now,
  );

  Future<String> schedule({
    ScheduledEventType type = ScheduledEventType.expense,
    DateTime? at,
    String originType = 'manual',
  }) async => (await repository.createScheduledEvent(
    eventType: type,
    amountSatang: 150000,
    title: type == ScheduledEventType.income ? 'เงินเดือน' : 'ทำฟัน',
    accountId: account,
    categoryId: type == ScheduledEventType.transfer
        ? null
        : type == ScheduledEventType.income
        ? incomeCategory
        : category,
    scheduledAt: at ?? DateTime(2026, 8, 24, 12).toUtc(),
    originType: originType,
  )).id;

  test(
    'loads one month without financial writes and projects selected day',
    () async {
      await schedule();
      final controller = makeController();
      await controller.load();

      expect(controller.visibleMonth, DateTime(2026, 8));
      expect(controller.calendarResult!.events, hasLength(1));
      expect(controller.projectedBalance!.actualNetWorthSatang, 1605300);
      expect(await repository.ledgerTransactionCount(), 0);

      await controller.selectDate(DateTime(2026, 8, 24));
      expect(controller.projectedBalance!.projectedNetWorthSatang, 1455300);
      expect(await repository.ledgerTransactionCount(), 0);
      controller.dispose();
    },
  );

  test('groups UTC events by local calendar day', () async {
    final at = DateTime.utc(2026, 8, 23, 18, 30);
    await schedule(at: at);
    final controller = makeController();
    await controller.load();
    final local = at.toLocal();
    expect(
      controller.eventsFor(DateTime(local.year, local.month, local.day)),
      hasLength(1),
    );
    controller.dispose();
  });

  test(
    'confirmation uses repository then refreshes actual and planned state',
    () async {
      await schedule(at: DateTime(2026, 8, 10).toUtc());
      final controller = makeController();
      await controller.load();
      final event = controller.calendarResult!.events.single;
      expect(event.isActionRequired, isTrue);

      await controller.confirm(event);

      expect(await repository.ledgerTransactionCount(), 1);
      expect(
        controller.calendarResult!.events.single.displayStatus.name,
        'fulfilled',
      );
      expect(controller.projectedBalance!.actualNetWorthSatang, 1455300);
      controller.dispose();
    },
  );

  test(
    'month navigation reloads bounded month and salary remains planned',
    () async {
      await schedule(
        type: ScheduledEventType.income,
        at: DateTime(2026, 9, 27).toUtc(),
        originType: 'salary_payday',
      );
      final controller = makeController();
      await controller.load();
      expect(controller.calendarResult!.events, isEmpty);
      await controller.nextMonth();
      expect(controller.visibleMonth, DateTime(2026, 9));
      expect(controller.calendarResult!.events.single.title, 'เงินเดือน');
      expect(await repository.ledgerTransactionCount(), 0);
      controller.dispose();
    },
  );
}
