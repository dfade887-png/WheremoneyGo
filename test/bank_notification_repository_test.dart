import 'package:flutter_test/flutter_test.dart';
import 'package:ngoen_ku_pai_nai/data/repositories/sqlite_finance_repository.dart';
import 'package:ngoen_ku_pai_nai/domain/bank_notification/bank_notification_adapter.dart';

void main() {
  late SqliteFinanceRepository repo;
  final adapter = ReferenceBankFixtureAdapter();
  setUp(() {
    repo = SqliteFinanceRepository.memory();
    repo.execute(
      "INSERT INTO accounts(id,name,opening_balance_satang,created_at,updated_at) VALUES('a','a',0,'x','x')",
    );
    repo.execute(
      "INSERT INTO categories(id,name,created_at,updated_at) VALUES('food','Food','x','x')",
    );
  });
  tearDown(() => repo.dispose());
  ParsedBankEvent parsed([String key = 'k']) => adapter.parse(
    BankNotificationInput(
      notificationKey: key,
      sourcePackage: adapter.sourcePackage,
      title: 'Fixture',
      body: 'Outgoing 55 THB',
      postedAt: DateTime.utc(2026),
    ),
  );
  test('duplicate callback returns same pending event', () async {
    final first = await repo.stageBankEvent(
      parsed(),
      sourcePackage: adapter.sourcePackage,
      detectedAt: DateTime.utc(2026),
    );
    final second = await repo.stageBankEvent(
      parsed(),
      sourcePackage: adapter.sourcePackage,
      detectedAt: DateTime.utc(2026),
    );
    expect(second, first);
    expect(
      repo
          .query('SELECT COUNT(*) count FROM bank_notification_events')
          .single['count'],
      1,
    );
  });
  test('confirmation is atomic and idempotent', () async {
    final id = await repo.stageBankEvent(
      parsed(),
      sourcePackage: adapter.sourcePackage,
      detectedAt: DateTime.utc(2026),
    );
    await expectLater(
      repo.confirmBankEventExpense(
        id,
        accountId: 'a',
        categoryId: 'food',
        failAfterTransaction: true,
      ),
      throwsStateError,
    );
    expect(await repo.ledgerTransactionCount(), 0);
    await repo.confirmBankEventExpense(id, accountId: 'a', categoryId: 'food');
    expect(await repo.ledgerTransactionCount(), 1);
    await expectLater(
      repo.confirmBankEventExpense(id, accountId: 'a', categoryId: 'food'),
      throwsStateError,
    );
    expect(await repo.ledgerTransactionCount(), 1);
  });
  test('raw notification text is never persisted', () async {
    await repo.stageBankEvent(
      parsed(),
      sourcePackage: adapter.sourcePackage,
      detectedAt: DateTime.utc(2026),
    );
    final columns = repo
        .query('PRAGMA table_info(bank_notification_events)')
        .map((row) => row['name'])
        .toSet();
    expect(columns, isNot(contains('raw_text')));
  });
}
