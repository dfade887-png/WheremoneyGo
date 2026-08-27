import 'package:flutter_test/flutter_test.dart';
import 'package:ngoen_ku_pai_nai/data/local/migration_runner.dart';
import 'package:ngoen_ku_pai_nai/data/local/schema_v4.dart';
import 'package:ngoen_ku_pai_nai/data/local/schema_v5.dart';
import 'package:sqlite3/sqlite3.dart';

const _now = '2026-08-18T00:00:00.000Z';

void _migrateToV4(Database db) {
  MigrationRunner.migrateToLatest(
    db,
    v5Statements: ['PRAGMA user_version = 4'],
  );
  expect(db.userVersion, 4);
}

void main() {
  test('v4 ledger and relationships migrate safely to v5', () {
    final db = sqlite3.openInMemory();
    addTearDown(db.close);
    _migrateToV4(db);

    db.execute(
      "INSERT INTO accounts(id,name,opening_balance_satang,created_at,updated_at) VALUES('a','Bank',100000,?,?),('b','Wallet',5000,?,?)",
      [_now, _now, _now, _now],
    );
    db.execute(
      "INSERT INTO categories(id,name,created_at,updated_at) VALUES('c','General',?,?)",
      [_now, _now],
    );
    for (final row in [
      ('income', 'a', 'income', 20000, 'confirmed', null, null),
      ('pending', 'a', 'expense', 25000, 'pending', null, null),
      ('deleted', 'a', 'expense', 5000, 'deleted', null, null),
      ('soft', 'a', 'expense', 7000, 'confirmed', null, _now),
      ('out', 'a', 'transfer_out', 10000, 'confirmed', 'group', null),
      ('in', 'b', 'transfer_in', 10000, 'confirmed', 'group', null),
      ('payment', 'a', 'expense', 1000, 'confirmed', null, null),
    ]) {
      db.execute(
        'INSERT INTO transactions(id,account_id,category_id,type,amount_satang,occurred_at,transfer_group_id,status,created_at,updated_at,deleted_at) VALUES(?,?,?,?,?,?,?,?,?,?,?)',
        [
          row.$1,
          row.$2,
          row.$3 == 'transfer_out' || row.$3 == 'transfer_in' ? null : 'c',
          row.$3,
          row.$4,
          _now,
          row.$6,
          row.$5,
          _now,
          _now,
          row.$7,
        ],
      );
    }
    db.execute(
      "INSERT INTO statement_imports(id,account_id,institution,adapter_version,file_name,file_hash,status,imported_at) VALUES('si','a','demo','1','safe.csv','hash','confirmed',?)",
      [_now],
    );
    db.execute(
      "INSERT INTO statement_rows(id,statement_import_id,row_index,posted_date,transaction_date,description_raw,direction,amount_satang,row_fingerprint,classification,matched_transaction_id) VALUES('sr','si',1,'2026-08-18','2026-08-18','sanitized','credit',20000,'row-fp','match_existing','income')",
    );
    db.execute(
      "INSERT INTO commitments(id,category_id,default_account_id,name,commitment_type,total_payable_satang,status,created_at,updated_at) VALUES('commitment','c','a','Phone','fixed_total',100000,'active',?,?)",
      [_now, _now],
    );
    db.execute(
      "INSERT INTO commitment_payments(id,commitment_id,transaction_id,created_at,updated_at) VALUES('cp','commitment','payment',?,?)",
      [_now, _now],
    );

    final countBefore = db
        .select('SELECT COUNT(*) count FROM transactions')
        .single['count'];
    MigrationRunner.migrateToLatest(db);

    expect(db.userVersion, SchemaV5.version);
    expect(
      db.select('SELECT COUNT(*) count FROM transactions').single['count'],
      countBefore,
    );
    for (final id in ['income', 'out', 'in', 'payment']) {
      expect(
        db.select('SELECT posted_at FROM transactions WHERE id=?', [
          id,
        ]).single['posted_at'],
        _now,
      );
    }
    for (final id in ['pending', 'deleted', 'soft']) {
      expect(
        db.select('SELECT posted_at FROM transactions WHERE id=?', [
          id,
        ]).single['posted_at'],
        isNull,
      );
    }
    expect(
      db
          .select(
            "SELECT COUNT(*) count FROM transactions WHERE transfer_group_id='group'",
          )
          .single['count'],
      2,
    );
    expect(
      db
          .select("SELECT row_fingerprint FROM statement_rows WHERE id='sr'")
          .single['row_fingerprint'],
      'row-fp',
    );
    expect(
      db
          .select(
            "SELECT transaction_id FROM commitment_payments WHERE id='cp'",
          )
          .single['transaction_id'],
      'payment',
    );
    expect(
      db
          .select("SELECT profile_id FROM transactions WHERE id='income'")
          .single['profile_id'],
      SchemaV4.legacyProfileId,
    );
    final netWorth =
        db.select(
              '''SELECT SUM(a.opening_balance_satang + COALESCE((SELECT SUM(CASE WHEN t.type IN ('income','refund','transfer_in') THEN t.amount_satang WHEN t.type IN ('expense','transfer_out') THEN -t.amount_satang WHEN t.type='balance_adjustment' THEN t.amount_satang ELSE 0 END) FROM transactions t WHERE t.account_id=a.id AND t.profile_id=a.profile_id AND t.status='confirmed' AND t.deleted_at IS NULL),0)) total FROM accounts a''',
            ).single['total']
            as int;
    expect(netWorth, 124000);
  });

  test('v5 migration failure rolls back column tables and version', () {
    final db = sqlite3.openInMemory();
    addTearDown(db.close);
    _migrateToV4(db);

    expect(
      () => MigrationRunner.migrateToLatest(
        db,
        v5Statements: [
          SchemaV5.statements[0],
          SchemaV5.statements[2],
          'INVALID SQL',
        ],
      ),
      throwsA(anything),
    );
    expect(db.userVersion, 4);
    expect(
      db
          .select('PRAGMA table_info(transactions)')
          .any((row) => row['name'] == 'posted_at'),
      isFalse,
    );
    expect(
      db.select(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='scheduled_financial_events'",
      ),
      isEmpty,
    );
  });
}
