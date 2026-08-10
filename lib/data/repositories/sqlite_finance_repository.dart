import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models/financial_models.dart';
import '../../domain/repositories/finance_repository.dart';
import '../local/migration_runner.dart';
import '../local/schema_v1.dart';

final class SqliteFinanceRepository implements FinanceRepository {
  SqliteFinanceRepository._(this.database);

  factory SqliteFinanceRepository.memory() {
    final database = sqlite3.openInMemory();
    final repository = SqliteFinanceRepository._(database);
    repository._migrate();
    return repository;
  }

  factory SqliteFinanceRepository.file(String path) {
    final database = sqlite3.open(path);
    final repository = SqliteFinanceRepository._(database);
    repository._migrate();
    return repository;
  }

  final Database database;
  static const _uuid = Uuid();
  static const _backupTables = <String>[
    'accounts', 'categories', 'budget_periods', 'transactions',
    'recurring_expenses', 'installments', 'commitment_occurrences',
    'period_budgets', 'saving_goals', 'salary_profiles',
    'payroll_deductions', 'app_settings', 'statement_imports', 'statement_rows',
  ];

  void _migrate() {
    MigrationRunner.migrateToV1(database);
  }

  void dispose() => database.close();
  void execute(String sql, [List<Object?> parameters = const []]) => database.execute(sql, parameters);
  List<Map<String, Object?>> query(String sql, [List<Object?> parameters = const []]) =>
      database.select(sql, parameters).map((row) => Map<String, Object?>.from(row)).toList();

  @override
  Future<int> schemaVersion() async => database.userVersion;

  @override
  Future<int> ledgerTransactionCount() async => database.select('SELECT COUNT(*) AS count FROM transactions WHERE deleted_at IS NULL').first['count'] as int;

  @override
  Future<String> createTransfer({required String fromAccountId, required String toAccountId, required int amountSatang, bool failAfterDebit = false}) async {
    if (amountSatang <= 0) throw ArgumentError.value(amountSatang);
    final group = _uuid.v4();
    _atomic(() {
      _insertTransaction(accountId: fromAccountId, type: 'transfer_out', amount: amountSatang, transferGroupId: group);
      if (failAfterDebit) throw StateError('Injected transfer failure');
      _insertTransaction(accountId: toAccountId, type: 'transfer_in', amount: amountSatang, transferGroupId: group);
    });
    return group;
  }

  @override
  Future<void> softDeleteTransfer(String transferGroupId, {bool failAfterFirst = false}) async {
    _atomic(() {
      final ids = database.select('SELECT id FROM transactions WHERE transfer_group_id = ? AND deleted_at IS NULL ORDER BY id', [transferGroupId]);
      if (ids.length != 2) throw StateError('Transfer pair is incomplete');
      final now = DateTime.now().toUtc().toIso8601String();
      database.execute('UPDATE transactions SET deleted_at = ?, updated_at = ? WHERE id = ?', [now, now, ids.first['id']]);
      if (failAfterFirst) throw StateError('Injected delete failure');
      database.execute('UPDATE transactions SET deleted_at = ?, updated_at = ? WHERE id = ?', [now, now, ids.last['id']]);
    });
  }

  @override
  Future<String> stageStatement({required String accountId, required String fileName, required String fileHash, required ParsedStatement parsed}) async {
    final existing = database.select(
      "SELECT id, status FROM statement_imports WHERE account_id = ? AND file_hash = ? ORDER BY imported_at DESC LIMIT 1",
      [accountId, fileHash],
    );
    if (existing.isNotEmpty) {
      final status = existing.first['status'];
      if (status == 'confirmed') throw StateError('Confirmed statement file already imported');
      if (status == 'preview' || status == 'undone') return existing.first['id'] as String;
    }
    final importId = _uuid.v4();
    _atomic(() {
      database.execute(
        'INSERT INTO statement_imports(id, account_id, institution, adapter_version, file_name, file_hash, opening_balance_satang, closing_balance_satang, status, imported_at) VALUES(?,?,?,?,?,?,?,?,?,?)',
        [importId, accountId, parsed.institution, parsed.adapterVersion, fileName, fileHash, parsed.openingBalance?.satang, parsed.closingBalance?.satang, 'preview', DateTime.now().toUtc().toIso8601String()],
      );
      for (final row in [...parsed.rows]..sort((a, b) => a.rowIndex.compareTo(b.rowIndex))) {
        final normalized = row.descriptionRaw.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
        final fingerprint = sha256.convert(utf8.encode('$accountId|${_date(row.postedDate)}|${_date(row.transactionDate)}|${row.amount.satang}|${row.direction.name}|${row.referenceNo ?? ''}|$normalized')).toString();
        database.execute(
          'INSERT INTO statement_rows(id, statement_import_id, row_index, posted_date, transaction_date, description_raw, reference_no, direction, amount_satang, running_balance_satang, row_fingerprint) VALUES(?,?,?,?,?,?,?,?,?,?,?)',
          [_uuid.v4(), importId, row.rowIndex, _date(row.postedDate), _date(row.transactionDate), row.descriptionRaw, row.referenceNo, row.direction.name, row.amount.satang, row.runningBalance?.satang, fingerprint],
        );
      }
    });
    return importId;
  }

  @override
  Future<void> classifyStatementRow(String rowId, StatementClassification classification, {String? matchedTransactionId}) async {
    if (classification == StatementClassification.matchExisting && matchedTransactionId == null) {
      throw ArgumentError('matchedTransactionId is required');
    }
    database.execute(
      'UPDATE statement_rows SET classification = ?, matched_transaction_id = ? WHERE id = ?',
      [classification.name, matchedTransactionId, rowId],
    );
  }

  @override
  Future<void> cancelStatement(String importId) async {
    database.execute("UPDATE statement_imports SET status = 'cancelled' WHERE id = ? AND status = 'preview'", [importId]);
  }

  @override
  Future<void> confirmStatement(String importId, {bool failMidway = false}) async {
    _atomic(() {
      final batch = database.select('SELECT account_id FROM statement_imports WHERE id = ? AND status IN (\'preview\',\'undone\')', [importId]);
      if (batch.isEmpty) throw StateError('Import cannot be confirmed');
      final rows = database.select('SELECT * FROM statement_rows WHERE statement_import_id = ? ORDER BY row_index', [importId]);
      if (rows.any((row) => row['classification'] == 'pending')) throw StateError('Pending rows must be reviewed');
      for (var index = 0; index < rows.length; index++) {
        final row = rows[index];
        final classification = row['classification'] as String;
        if (classification == 'ignore' || classification == 'matchExisting') continue;
        final accountId = batch.first['account_id'] as String;
        String transactionId;
        if (classification == 'transfer') {
          final other = database.select('SELECT id FROM accounts WHERE id != ? AND deleted_at IS NULL LIMIT 1', [accountId]);
          if (other.isEmpty) throw StateError('Transfer requires a counterparty account');
          final group = _uuid.v4();
          final debit = row['direction'] == 'debit';
          transactionId = _insertTransaction(accountId: accountId, type: debit ? 'transfer_out' : 'transfer_in', amount: row['amount_satang'] as int, transferGroupId: group, source: 'statement');
          _insertTransaction(accountId: other.first['id'] as String, type: debit ? 'transfer_in' : 'transfer_out', amount: row['amount_satang'] as int, transferGroupId: group, source: 'statement');
        } else {
          transactionId = _insertTransaction(accountId: accountId, type: classification, amount: row['amount_satang'] as int, source: 'statement');
        }
        database.execute('UPDATE statement_rows SET created_transaction_id = ? WHERE id = ?', [transactionId, row['id']]);
        if (failMidway && index == 0) throw StateError('Injected import failure');
      }
      database.execute("UPDATE statement_imports SET status = 'confirmed' WHERE id = ?", [importId]);
    });
  }

  @override
  Future<void> undoStatement(String importId) async {
    _atomic(() {
      final batch = database.select("SELECT id FROM statement_imports WHERE id = ? AND status = 'confirmed'", [importId]);
      if (batch.isEmpty) throw StateError('Only confirmed imports can be undone');
      final createdIds = database.select('SELECT created_transaction_id FROM statement_rows WHERE statement_import_id = ? AND created_transaction_id IS NOT NULL', [importId]).map((row) => row['created_transaction_id'] as String).toList();
      final now = DateTime.now().toUtc().toIso8601String();
      for (final id in createdIds) {
        final groups = database.select('SELECT transfer_group_id FROM transactions WHERE id = ?', [id]);
        final group = groups.first['transfer_group_id'];
        if (group == null) {
          database.execute('UPDATE transactions SET deleted_at = ?, updated_at = ? WHERE id = ?', [now, now, id]);
        } else {
          database.execute('UPDATE transactions SET deleted_at = ?, updated_at = ? WHERE transfer_group_id = ?', [now, now, group]);
        }
        database.execute('UPDATE commitment_occurrences SET linked_transaction_id = NULL WHERE linked_transaction_id = ?', [id]);
        database.execute('UPDATE budget_periods SET salary_transaction_id = NULL WHERE salary_transaction_id = ?', [id]);
      }
      database.execute('UPDATE statement_rows SET matched_transaction_id = NULL, created_transaction_id = NULL WHERE statement_import_id = ?', [importId]);
      database.execute("UPDATE statement_imports SET status = 'undone' WHERE id = ?", [importId]);
    });
  }

  @override
  Future<List<Map<String, Object?>>> statementRows(String importId) async => query('SELECT * FROM statement_rows WHERE statement_import_id = ? ORDER BY row_index', [importId]);

  @override
  Future<List<Map<String, Object?>>> dumpTable(String table) async {
    if (!_backupTables.contains(table)) throw ArgumentError.value(table);
    return query('SELECT * FROM $table ORDER BY id');
  }

  @override
  Future<Map<String, Object?>> exportBackup() async {
    final data = <String, Object?>{};
    for (final table in _backupTables) {
      data[table] = await dumpTable(table);
    }
    final payload = jsonEncode({'schemaVersion': SchemaV1.version, 'data': data});
    return {'schemaVersion': SchemaV1.version, 'data': data, 'checksum': sha256.convert(utf8.encode(payload)).toString()};
  }

  @override
  Future<void> restoreBackup(Map<String, Object?> backup) async {
    final schemaVersion = backup['schemaVersion'];
    final data = backup['data'];
    final checksum = backup['checksum'];
    final payload = jsonEncode({'schemaVersion': schemaVersion, 'data': data});
    if (schemaVersion != SchemaV1.version || checksum != sha256.convert(utf8.encode(payload)).toString() || data is! Map) {
      throw const FormatException('Invalid or unsupported backup');
    }
    _atomic(() {
      for (final table in _backupTables.reversed) {
        database.execute('DELETE FROM $table');
      }
      final typed = Map<String, Object?>.from(data);
      for (final table in _backupTables) {
        for (final raw in (typed[table] as List? ?? const [])) {
          final row = Map<String, Object?>.from(raw as Map);
          final columns = row.keys.toList();
          database.execute('INSERT INTO $table(${columns.join(',')}) VALUES(${List.filled(columns.length, '?').join(',')})', columns.map((key) => row[key]).toList());
        }
      }
    });
  }

  String _insertTransaction({required String accountId, required String type, required int amount, String? transferGroupId, String source = 'manual'}) {
    final id = _uuid.v4();
    final now = DateTime.now().toUtc().toIso8601String();
    database.execute(
      'INSERT INTO transactions(id, account_id, type, amount_satang, occurred_at, transfer_group_id, source, created_at, updated_at) VALUES(?,?,?,?,?,?,?,?,?)',
      [id, accountId, type, amount, now, transferGroupId, source, now, now],
    );
    return id;
  }

  void _atomic(void Function() action) {
    database.execute('BEGIN IMMEDIATE');
    try {
      action();
      database.execute('COMMIT');
    } catch (_) {
      database.execute('ROLLBACK');
      rethrow;
    }
  }

  static String _date(DateTime value) => value.toUtc().toIso8601String().split('T').first;
}
