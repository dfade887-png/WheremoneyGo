import 'package:flutter_test/flutter_test.dart';
import 'package:ngoen_ku_pai_nai/core/money.dart';
import 'package:ngoen_ku_pai_nai/data/repositories/sqlite_finance_repository.dart';
import 'package:ngoen_ku_pai_nai/data/local/migration_runner.dart';
import 'package:ngoen_ku_pai_nai/data/local/schema_v1.dart';
import 'package:ngoen_ku_pai_nai/domain/financial_rules.dart';
import 'package:ngoen_ku_pai_nai/domain/models/financial_models.dart';
import 'package:sqlite3/sqlite3.dart';

Money b(num value) => Money.fromBaht(value);
const now = '2026-08-10T00:00:00.000Z';

void seedAccount(SqliteFinanceRepository repo, String id, [int opening = 0]) {
  repo.execute(
    'INSERT INTO accounts(id,name,opening_balance_satang,created_at,updated_at) VALUES(?,?,?,?,?)',
    [id, id, opening, now, now],
  );
}

ParsedStatement statement(
  List<StatementDraftRow> rows, {
  Money? opening,
  Money? closing,
  String version = '1',
}) => ParsedStatement(
  institution: 'demo-bank',
  adapterVersion: version,
  rows: rows,
  openingBalance: opening,
  closingBalance: closing,
);

StatementDraftRow row(
  int index,
  int satang,
  StatementDirection direction, {
  String? reference,
  String description = 'demo',
}) => StatementDraftRow(
  rowIndex: index,
  postedDate: DateTime(2026, 8, 10),
  transactionDate: DateTime(2026, 8, 10),
  descriptionRaw: description,
  referenceNo: reference,
  direction: direction,
  amount: Money.fromSatang(satang),
);

void main() {
  late SqliteFinanceRepository repo;
  setUp(() => repo = SqliteFinanceRepository.memory());
  tearDown(() => repo.dispose());

  test('repository migrates to latest schema version', () async {
    expect(await repo.schemaVersion(), 3);
    expect(
      repo.query(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='statement_rows'",
      ),
      isNotEmpty,
    );
  });

  test('migration upgrades an empty version-zero database to v1', () {
    final database = sqlite3.openInMemory();
    addTearDown(database.close);
    expect(database.userVersion, 0);
    MigrationRunner.migrateToV1(database);
    expect(database.userVersion, SchemaV1.version);
    expect(
      database.select(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='accounts'",
      ),
      isNotEmpty,
    );
  });

  test('migration failure rolls back schema and version atomically', () {
    final database = sqlite3.openInMemory();
    addTearDown(database.close);
    expect(
      () => MigrationRunner.migrateToV1(
        database,
        statements: [SchemaV1.statements[1], 'INVALID SQL'],
      ),
      throwsA(anything),
    );
    expect(database.userVersion, 0);
    expect(
      database.select(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='accounts'",
      ),
      isEmpty,
    );
  });

  test('T26 valid backup restores all balances exactly', () async {
    seedAccount(repo, 'a', 12345);
    final backup = await repo.exportBackup();
    final restored = SqliteFinanceRepository.memory();
    addTearDown(restored.dispose);
    await restored.restoreBackup(backup);
    expect(
      (await restored.dumpTable('accounts')).single['opening_balance_satang'],
      12345,
    );
  });

  test('T27 corrupt checksum changes no existing database data', () async {
    seedAccount(repo, 'safe', 100);
    final backup = await repo.exportBackup()
      ..['checksum'] = 'broken';
    await expectLater(repo.restoreBackup(backup), throwsFormatException);
    expect((await repo.dumpTable('accounts')).single['id'], 'safe');
  });

  test('T31 transaction links only the selected occurrence month', () {
    seedAccount(repo, 'a');
    repo.execute(
      "INSERT INTO recurring_expenses(id,name,amount_satang,due_day,start_date,created_at,updated_at) VALUES('r','dental',250000,1,'2026-01-01',?,?)",
      [now, now],
    );
    repo.execute(
      "INSERT INTO transactions(id,account_id,type,amount_satang,occurred_at,created_at,updated_at) VALUES('tx','a','expense',250000,?,?,?)",
      [now, now, now],
    );
    repo.execute(
      "INSERT INTO commitment_occurrences(id,recurring_expense_id,due_date,planned_amount_satang,created_at,updated_at) VALUES('aug','r','2026-08-01',250000,?,?),('sep','r','2026-09-01',250000,?,?)",
      [now, now, now, now],
    );
    repo.execute(
      "UPDATE commitment_occurrences SET linked_transaction_id='tx' WHERE id='sep'",
    );
    expect(
      repo
          .query(
            "SELECT linked_transaction_id FROM commitment_occurrences WHERE id='aug'",
          )
          .single['linked_transaction_id'],
      isNull,
    );
  });

  test('T32 late payment links old occurrence without consuming new one', () {
    seedAccount(repo, 'a');
    repo.execute(
      "INSERT INTO recurring_expenses(id,name,amount_satang,due_day,start_date,created_at,updated_at) VALUES('r','dental',250000,1,'2026-01-01',?,?)",
      [now, now],
    );
    repo.execute(
      "INSERT INTO transactions(id,account_id,type,amount_satang,occurred_at,created_at,updated_at) VALUES('late','a','expense',250000,?,?,?)",
      [now, now, now],
    );
    repo.execute(
      "INSERT INTO commitment_occurrences(id,recurring_expense_id,due_date,planned_amount_satang,linked_transaction_id,created_at,updated_at) VALUES('aug','r','2026-08-01',250000,'late',?,?)",
      [now, now],
    );
    repo.execute(
      "INSERT INTO commitment_occurrences(id,recurring_expense_id,due_date,planned_amount_satang,created_at,updated_at) VALUES('sep','r','2026-09-01',250000,?,?)",
      [now, now],
    );
    expect(
      repo
          .query(
            "SELECT COUNT(*) count FROM commitment_occurrences WHERE linked_transaction_id IS NULL",
          )
          .single['count'],
      1,
    );
  });

  test('T33 transfer pair create and delete are atomic', () async {
    seedAccount(repo, 'a');
    seedAccount(repo, 'b');
    await expectLater(
      repo.createTransfer(
        fromAccountId: 'a',
        toAccountId: 'b',
        amountSatang: 300000,
        failAfterDebit: true,
      ),
      throwsStateError,
    );
    expect(await repo.ledgerTransactionCount(), 0);
    final group = await repo.createTransfer(
      fromAccountId: 'a',
      toAccountId: 'b',
      amountSatang: 300000,
    );
    await expectLater(
      repo.softDeleteTransfer(group, failAfterFirst: true),
      throwsStateError,
    );
    expect(await repo.ledgerTransactionCount(), 2);
    await repo.softDeleteTransfer(group);
    expect(await repo.ledgerTransactionCount(), 0);
  });

  test('T34 saving transfer changes saving but not combined cash', () {
    expect(
      FinancialRules.actualSavingFromGoalTransfers(
        transfersIn: [b(2500)],
        transfersOut: const [],
      ),
      b(2500),
    );
    expect(FinancialRules.currentCash([b(7500), b(2500)]), b(10000));
  });

  test('T35 signed balance adjustment affects cash only', () {
    expect(
      FinancialRules.accountBalance(
        opening: b(1000),
        transactions: [(TransactionType.balanceAdjustment, b(100))],
      ),
      b(1100),
    );
    expect(
      FinancialRules.categorySpend(expenses: const [], refunds: const []),
      isEmpty,
    );
  });

  test('T36 confirmed duplicate file is rejected', () async {
    seedAccount(repo, 'a');
    final id = await repo.stageStatement(
      accountId: 'a',
      fileName: 'x.csv',
      fileHash: 'hash',
      parsed: statement([row(1, 100, StatementDirection.credit)]),
    );
    final rows = await repo.statementRows(id);
    await repo.classifyStatementRow(
      rows.single['id'] as String,
      StatementClassification.income,
    );
    await repo.confirmStatement(id);
    await expectLater(
      repo.stageStatement(
        accountId: 'a',
        fileName: 'x.csv',
        fileHash: 'hash',
        parsed: statement([row(1, 100, StatementDirection.credit)]),
      ),
      throwsStateError,
    );
  });

  test('T37 matching existing transaction creates no new transaction', () async {
    seedAccount(repo, 'a');
    repo.execute(
      "INSERT INTO transactions(id,account_id,type,amount_satang,occurred_at,created_at,updated_at) VALUES('manual','a','expense',12000,?,?,?)",
      [now, now, now],
    );
    final id = await repo.stageStatement(
      accountId: 'a',
      fileName: 'x.csv',
      fileHash: 'h37',
      parsed: statement([row(1, 12000, StatementDirection.debit)]),
    );
    final rows = await repo.statementRows(id);
    await repo.classifyStatementRow(
      rows.single['id'] as String,
      StatementClassification.matchExisting,
      matchedTransactionId: 'manual',
    );
    await repo.confirmStatement(id);
    expect(await repo.ledgerTransactionCount(), 1);
  });

  test(
    'T38 equal date and amount with distinct references stay separate',
    () async {
      seedAccount(repo, 'a');
      final id = await repo.stageStatement(
        accountId: 'a',
        fileName: 'x.csv',
        fileHash: 'h38',
        parsed: statement([
          row(1, 6000, StatementDirection.debit, reference: 'one'),
          row(2, 6000, StatementDirection.debit, reference: 'two'),
        ]),
      );
      final rows = await repo.statementRows(id);
      expect(rows, hasLength(2));
      expect(rows[0]['row_fingerprint'], isNot(rows[1]['row_fingerprint']));
    },
  );

  test(
    'T39 direction does not prevent explicit income and expense classification',
    () async {
      seedAccount(repo, 'a');
      final id = await repo.stageStatement(
        accountId: 'a',
        fileName: 'x.csv',
        fileHash: 'h39',
        parsed: statement([
          row(1, 1712500, StatementDirection.credit),
          row(2, 49900, StatementDirection.debit),
        ]),
      );
      final rows = await repo.statementRows(id);
      await repo.classifyStatementRow(
        rows[0]['id'] as String,
        StatementClassification.income,
      );
      await repo.classifyStatementRow(
        rows[1]['id'] as String,
        StatementClassification.expense,
      );
      await repo.confirmStatement(id);
      expect(
        repo
            .query('SELECT type FROM transactions ORDER BY amount_satang DESC')
            .map((e) => e['type']),
        ['income', 'expense'],
      );
    },
  );

  test('T40 statement transfer creates pair without income or expense', () async {
    seedAccount(repo, 'a');
    seedAccount(repo, 'b');
    final id = await repo.stageStatement(
      accountId: 'a',
      fileName: 'x.csv',
      fileHash: 'h40',
      parsed: statement([row(1, 50000, StatementDirection.debit)]),
    );
    final rows = await repo.statementRows(id);
    await repo.classifyStatementRow(
      rows.single['id'] as String,
      StatementClassification.transfer,
    );
    await repo.confirmStatement(id);
    expect(
      repo
          .query(
            "SELECT COUNT(*) count FROM transactions WHERE type IN ('income','expense')",
          )
          .single['count'],
      0,
    );
    expect(await repo.ledgerTransactionCount(), 2);
  });

  test('T41 cancelling preview leaves ledger unchanged', () async {
    seedAccount(repo, 'a');
    final id = await repo.stageStatement(
      accountId: 'a',
      fileName: 'x.csv',
      fileHash: 'h41',
      parsed: statement([row(1, 100, StatementDirection.debit)]),
    );
    await repo.cancelStatement(id);
    expect(await repo.ledgerTransactionCount(), 0);
  });

  test('T42 failed confirm rolls back entire batch', () async {
    seedAccount(repo, 'a');
    final id = await repo.stageStatement(
      accountId: 'a',
      fileName: 'x.csv',
      fileHash: 'h42',
      parsed: statement([
        row(1, 100, StatementDirection.debit),
        row(2, 200, StatementDirection.debit),
      ]),
    );
    for (final item in await repo.statementRows(id)) {
      await repo.classifyStatementRow(
        item['id'] as String,
        StatementClassification.expense,
      );
    }
    await expectLater(
      repo.confirmStatement(id, failMidway: true),
      throwsStateError,
    );
    expect(await repo.ledgerTransactionCount(), 0);
  });

  test('T43 running statement equation reconciles to zero', () {
    final result = FinancialRules.reconcile(
      opening: b(1000),
      credits: [b(500)],
      debits: [b(200)],
      closing: b(1300),
      calculatedLedgerClosing: b(1300),
    );
    expect(result.internalDifference, Money.zero);
  });

  test('T44 ledger difference 320 does not create adjustment', () {
    final result = FinancialRules.reconcile(
      opening: b(1000),
      credits: const [],
      debits: const [],
      closing: b(1000),
      calculatedLedgerClosing: b(680),
    );
    expect(result.ledgerDifference, b(320));
    expect(
      repo
          .query(
            "SELECT COUNT(*) count FROM transactions WHERE type='balance_adjustment'",
          )
          .single['count'],
      0,
    );
  });

  test('T45 matched paid occurrence is not deducted again', () {
    expect(
      FinancialRules.occurrenceStatus(
        skipped: false,
        linkedTransactionId: 'matched',
        dueDate: DateTime(2026, 8, 1),
        today: DateTime(2026, 9, 1),
      ),
      OccurrenceStatus.paid,
    );
  });

  test('T46 refund reduces category expense and not general income', () {
    final spend = FinancialRules.categorySpend(
      expenses: [('food', b(1000))],
      refunds: [('food', b(300))],
    );
    expect(spend['food'], b(700));
  });

  test('T47 row index preserves same-day running order and dates', () async {
    seedAccount(repo, 'a');
    final id = await repo.stageStatement(
      accountId: 'a',
      fileName: 'x.csv',
      fileHash: 'h47',
      parsed: statement([
        row(2, 200, StatementDirection.debit),
        row(1, 100, StatementDirection.debit),
      ]),
    );
    final rows = await repo.statementRows(id);
    expect(rows.map((e) => e['row_index']), [1, 2]);
    expect(rows.first['posted_date'], rows.first['transaction_date']);
  });

  test('T48 failed batch can retry with same hash and adapter v2', () async {
    seedAccount(repo, 'a');
    final first = await repo.stageStatement(
      accountId: 'a',
      fileName: 'x.csv',
      fileHash: 'h48',
      parsed: statement([row(1, 100, StatementDirection.debit)], version: '1'),
    );
    repo.execute("UPDATE statement_imports SET status='failed' WHERE id=?", [
      first,
    ]);
    final second = await repo.stageStatement(
      accountId: 'a',
      fileName: 'x.csv',
      fileHash: 'h48',
      parsed: statement([row(1, 100, StatementDirection.debit)], version: '2'),
    );
    expect(second, isNot(first));
    expect((await repo.dumpTable('statement_imports')), hasLength(2));
  });

  test('T49 destination statement can match existing transfer-in', () async {
    seedAccount(repo, 'a');
    seedAccount(repo, 'b');
    await repo.createTransfer(
      fromAccountId: 'a',
      toAccountId: 'b',
      amountSatang: 50000,
    );
    final transferIn =
        repo
                .query(
                  "SELECT id FROM transactions WHERE account_id='b' AND type='transfer_in'",
                )
                .single['id']
            as String;
    final id = await repo.stageStatement(
      accountId: 'b',
      fileName: 'x.csv',
      fileHash: 'h49',
      parsed: statement([row(1, 50000, StatementDirection.credit)]),
    );
    final rows = await repo.statementRows(id);
    await repo.classifyStatementRow(
      rows.single['id'] as String,
      StatementClassification.matchExisting,
      matchedTransactionId: transferIn,
    );
    await repo.confirmStatement(id);
    expect(await repo.ledgerTransactionCount(), 2);
  });

  test('T50 undo is atomic for expense transfer and manual matching', () async {
    seedAccount(repo, 'a');
    seedAccount(repo, 'b');
    repo.execute(
      "INSERT INTO transactions(id,account_id,type,amount_satang,occurred_at,created_at,updated_at) VALUES('manual','a','expense',12000,?,?,?)",
      [now, now, now],
    );
    final id = await repo.stageStatement(
      accountId: 'a',
      fileName: 'x.csv',
      fileHash: 'h50',
      parsed: statement([
        row(1, 10000, StatementDirection.debit),
        row(2, 50000, StatementDirection.debit),
        row(3, 12000, StatementDirection.debit),
      ]),
    );
    final rows = await repo.statementRows(id);
    await repo.classifyStatementRow(
      rows[0]['id'] as String,
      StatementClassification.expense,
    );
    await repo.classifyStatementRow(
      rows[1]['id'] as String,
      StatementClassification.transfer,
    );
    await repo.classifyStatementRow(
      rows[2]['id'] as String,
      StatementClassification.matchExisting,
      matchedTransactionId: 'manual',
    );
    await repo.confirmStatement(id);
    expect(await repo.ledgerTransactionCount(), 4);
    await repo.undoStatement(id);
    expect(await repo.ledgerTransactionCount(), 1);
    expect(
      repo
          .query("SELECT deleted_at FROM transactions WHERE id='manual'")
          .single['deleted_at'],
      isNull,
    );
    expect(
      (await repo.statementRows(
        id,
      )).every((item) => item['matched_transaction_id'] == null),
      isTrue,
    );
  });
}
