import 'package:flutter_test/flutter_test.dart';
import 'package:ngoen_ku_pai_nai/data/local/migration_runner.dart';
import 'package:ngoen_ku_pai_nai/data/local/schema_v2.dart';
import 'package:ngoen_ku_pai_nai/data/repositories/sqlite_finance_repository.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('existing v1 installment migrates with nullable total', () {
    final db = sqlite3.openInMemory();
    addTearDown(db.close);
    MigrationRunner.migrateToV1(db);
    db.execute(
      "INSERT INTO installments(id,name,amount_satang,due_day,start_date,created_at,updated_at) VALUES('phone','Phone',100000,1,'2026-01-01','x','x')",
    );
    MigrationRunner.migrateToLatest(db);
    // MigrationRunner's historical test path intentionally stops at v5;
    // production repositories opt into the additive v6 slip migration.
    expect(db.userVersion, 5);
    final row = db
        .select(
          "SELECT total_payable_satang,status FROM installments WHERE id='phone'",
        )
        .single;
    expect(row['total_payable_satang'], isNull);
    expect(row['status'], 'active');
  });
  test('v2 migration failure rolls back all v2 changes', () {
    final db = sqlite3.openInMemory();
    addTearDown(db.close);
    MigrationRunner.migrateToV1(db);
    expect(
      () => MigrationRunner.migrateToLatest(
        db,
        v2Statements: [SchemaV2.statements.first, 'INVALID SQL'],
      ),
      throwsA(anything),
    );
    expect(db.userVersion, 1);
    expect(
      db
          .select("PRAGMA table_info(installments)")
          .any((row) => row['name'] == 'total_payable_satang'),
      isFalse,
    );
  });
  test('v2 backup restore preserves installment total and adjustment', () async {
    final repo = SqliteFinanceRepository.memory();
    addTearDown(repo.dispose);
    repo.execute(
      "INSERT INTO installments(id,name,amount_satang,due_day,start_date,total_payable_satang,regular_payment_satang,created_at,updated_at) VALUES('phone','Phone',100000,1,'2026-01-01',2700000,100000,'x','x')",
    );
    repo.execute(
      "INSERT INTO installment_total_adjustments(id,installment_id,new_total_satang,reason,effective_at,created_at,updated_at) VALUES('a','phone',2700000,'contract','x','x','x')",
    );
    final backup = await repo.exportBackup();
    final restored = SqliteFinanceRepository.memory();
    addTearDown(restored.dispose);
    await restored.restoreBackup(backup);
    expect(
      (await restored.dumpTable('installments')).single['total_payable_satang'],
      2700000,
    );
    expect(
      (await restored.dumpTable(
        'installment_total_adjustments',
      )).single['reason'],
      'contract',
    );
  });
}
