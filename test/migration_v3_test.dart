import 'package:flutter_test/flutter_test.dart';
import 'package:ngoen_ku_pai_nai/data/local/migration_runner.dart';
import 'package:ngoen_ku_pai_nai/data/local/schema_v3.dart';
import 'package:ngoen_ku_pai_nai/data/repositories/sqlite_finance_repository.dart';
import 'package:sqlite3/sqlite3.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';

void main() {
  test('schema v3 creates daily driver tables', () async {
    final repository = SqliteFinanceRepository.memory();
    addTearDown(repository.dispose);
    expect(await repository.schemaVersion(), 5);
    expect(
      repository
          .query(
            "SELECT name FROM sqlite_master WHERE type='table' AND name IN ('audit_events','commitments','commitment_payments')",
          )
          .length,
      3,
    );
  });

  test('v2 installment and linked payment migrate without guessing total', () {
    final db = sqlite3.openInMemory();
    addTearDown(db.close);
    MigrationRunner.migrateToLatest(
      db,
      v3Statements: ['PRAGMA user_version = 2'],
      v4Statements: ['PRAGMA user_version = 2'],
    );
    final now = DateTime.utc(2026, 8, 12).toIso8601String();
    db.execute(
      "INSERT INTO accounts(id,name,opening_balance_satang,created_at,updated_at) VALUES('a','Bank',0,?,?)",
      [now, now],
    );
    db.execute(
      "INSERT INTO categories(id,name,created_at,updated_at) VALUES('c','Phone',?,?)",
      [now, now],
    );
    db.execute(
      "INSERT INTO installments(id,category_id,name,amount_satang,due_day,start_date,total_payable_satang,regular_payment_satang,status,created_at,updated_at) VALUES('i','c','Phone',100000,1,'2026-01-01',NULL,100000,'active',?,?)",
      [now, now],
    );
    db.execute(
      "INSERT INTO transactions(id,account_id,category_id,type,amount_satang,occurred_at,source,created_at,updated_at) VALUES('t','a','c','expense',100000,?,'manual',?,?)",
      [now, now, now],
    );
    db.execute(
      "INSERT INTO commitment_occurrences(id,installment_id,due_date,planned_amount_satang,linked_transaction_id,created_at,updated_at) VALUES('o','i','2026-08-01',100000,'t',?,?)",
      [now, now],
    );
    MigrationRunner.migrateToLatest(db);
    final commitment = db
        .select("SELECT * FROM commitments WHERE legacy_installment_id='i'")
        .single;
    expect(commitment['total_payable_satang'], isNull);
    expect(
      db
          .select('SELECT COUNT(*) count FROM commitment_payments')
          .single['count'],
      1,
    );
  });

  test('v3 migration failure rolls back all changes', () {
    final db = sqlite3.openInMemory();
    addTearDown(db.close);
    MigrationRunner.migrateToLatest(
      db,
      v3Statements: ['PRAGMA user_version = 2'],
      v4Statements: ['PRAGMA user_version = 2'],
    );
    expect(
      () => MigrationRunner.migrateToLatest(
        db,
        v3Statements: [SchemaV3.statements.first, 'INVALID SQL'],
      ),
      throwsA(anything),
    );
    expect(db.userVersion, 2);
    expect(
      db
          .select('PRAGMA table_info(accounts)')
          .any((r) => r['name'] == 'account_type'),
      isFalse,
    );
  });

  test(
    'schema v2 backup restores into v3 and keeps checksum protection',
    () async {
      final source = SqliteFinanceRepository.memory();
      final target = SqliteFinanceRepository.memory();
      addTearDown(source.dispose);
      addTearDown(target.dispose);
      await source.createAccount(
        name: 'Legacy',
        type: 'bank',
        openingBalanceSatang: 12345,
      );
      final exported = await source.exportBackup();
      final data = Map<String, Object?>.from(exported['data'] as Map)
        ..remove('audit_events')
        ..remove('commitments')
        ..remove('commitment_payments');
      final payload = jsonEncode({'schemaVersion': 2, 'data': data});
      await target.restoreBackup({
        'schemaVersion': 2,
        'data': data,
        'checksum': sha256.convert(utf8.encode(payload)).toString(),
      });
      expect((await target.accounts()).single['opening_balance_satang'], 12345);
      expect(await target.schemaVersion(), 5);
    },
  );
}
