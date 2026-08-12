import 'package:flutter_test/flutter_test.dart';
import 'package:ngoen_ku_pai_nai/data/local/migration_runner.dart';
import 'package:ngoen_ku_pai_nai/data/local/schema_v4.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('v3 data migrates into default profile preserving relationships', () {
    final db = sqlite3.openInMemory();
    addTearDown(db.close);
    MigrationRunner.migrateToLatest(
      db,
      v4Statements: ['PRAGMA user_version = 3'],
    );
    final now = DateTime.utc(2026, 8, 12).toIso8601String();
    db.execute(
      "INSERT INTO accounts(id,name,opening_balance_satang,created_at,updated_at) VALUES('a','Legacy',-6100000,?,?)",
      [now, now],
    );
    db.execute(
      "INSERT INTO categories(id,name,created_at,updated_at) VALUES('c','Food',?,?)",
      [now, now],
    );
    db.execute(
      "INSERT INTO transactions(id,account_id,category_id,type,amount_satang,occurred_at,created_at,updated_at) VALUES('t','a','c','expense',10000,?,?,?)",
      [now, now, now],
    );
    MigrationRunner.migrateToLatest(db);
    expect(db.userVersion, 4);
    expect(
      db
          .select("SELECT profile_id FROM accounts WHERE id='a'")
          .single['profile_id'],
      SchemaV4.legacyProfileId,
    );
    expect(
      db
          .select("SELECT profile_id FROM transactions WHERE id='t'")
          .single['profile_id'],
      SchemaV4.legacyProfileId,
    );
    expect(
      db
          .select("SELECT opening_balance_satang FROM accounts WHERE id='a'")
          .single['opening_balance_satang'],
      -6100000,
    );
  });

  test('v4 failure rolls back profile and all added columns', () {
    final db = sqlite3.openInMemory();
    addTearDown(db.close);
    MigrationRunner.migrateToLatest(
      db,
      v4Statements: ['PRAGMA user_version = 3'],
    );
    expect(
      () => MigrationRunner.migrateToLatest(
        db,
        v4Statements: [
          SchemaV4.statements.first,
          SchemaV4.statements[1],
          'INVALID SQL',
        ],
      ),
      throwsA(anything),
    );
    expect(db.userVersion, 3);
    expect(
      db.select(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='financial_profiles'",
      ),
      isEmpty,
    );
    expect(
      db
          .select('PRAGMA table_info(accounts)')
          .any((r) => r['name'] == 'profile_id'),
      isFalse,
    );
  });
}
