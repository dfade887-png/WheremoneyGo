import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models/financial_models.dart';
import '../../domain/bank_notification/bank_notification_adapter.dart';
import '../../domain/repositories/finance_repository.dart';
import '../local/migration_runner.dart';
import '../local/schema_v4.dart';

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
    'financial_profiles',
    'application_metadata',
    'profile_settings',
    'accounts',
    'categories',
    'budget_periods',
    'transactions',
    'recurring_expenses',
    'installments',
    'commitment_occurrences',
    'period_budgets',
    'saving_goals',
    'salary_profiles',
    'payroll_deductions',
    'app_settings',
    'statement_imports',
    'statement_rows',
    'installment_total_adjustments',
    'audit_events',
    'commitments',
    'commitment_payments',
  ];

  void _migrate() {
    MigrationRunner.migrateToLatest(database);
  }

  void dispose() => database.close();
  void execute(String sql, [List<Object?> parameters = const []]) =>
      database.execute(sql, parameters);
  List<Map<String, Object?>> query(
    String sql, [
    List<Object?> parameters = const [],
  ]) => database
      .select(sql, parameters)
      .map((row) => Map<String, Object?>.from(row))
      .toList();

  @override
  Future<int> schemaVersion() async => database.userVersion;

  @override
  Future<int> ledgerTransactionCount() async =>
      database
              .select(
                'SELECT COUNT(*) AS count FROM transactions WHERE deleted_at IS NULL',
              )
              .first['count']
          as int;

  String get activeProfileId =>
      database
              .select(
                "SELECT value FROM application_metadata WHERE key='active_profile_id'",
              )
              .single['value']
          as String;

  Future<List<Map<String, Object?>>> profiles({
    bool includeArchived = true,
  }) async => query(
    "SELECT p.*,(SELECT COUNT(*) FROM accounts a WHERE a.profile_id=p.id AND a.deleted_at IS NULL) account_count,(SELECT COUNT(*) FROM transactions t WHERE t.profile_id=p.id AND t.deleted_at IS NULL) transaction_count FROM financial_profiles p WHERE p.deleted_at IS NULL ${includeArchived ? '' : "AND p.status<>'archived'"} ORDER BY p.is_primary DESC,p.last_used_at DESC",
  );

  Future<String> createProfile(String name, {bool draft = true}) async {
    final id = _uuid.v4();
    final now = DateTime.now().toUtc().toIso8601String();
    database.execute(
      'INSERT INTO financial_profiles(id,name,status,last_used_at,created_at,updated_at) VALUES(?,?,?,?,?,?)',
      [id, name.trim(), draft ? 'draft' : 'active', now, now, now],
    );
    return id;
  }

  Future<void> switchProfile(String id) async {
    _atomic(() {
      final rows = database.select(
        "SELECT id FROM financial_profiles WHERE id=? AND status<>'archived' AND deleted_at IS NULL",
        [id],
      );
      if (rows.isEmpty) throw StateError('Profile is unavailable');
      final now = DateTime.now().toUtc().toIso8601String();
      database.execute(
        "UPDATE application_metadata SET value=?,updated_at=? WHERE key='active_profile_id'",
        [id, now],
      );
      database.execute(
        'UPDATE financial_profiles SET last_used_at=?,updated_at=? WHERE id=?',
        [now, now, id],
      );
    });
  }

  Future<void> renameProfile(String id, String name) async => database.execute(
    'UPDATE financial_profiles SET name=?,updated_at=? WHERE id=?',
    [name.trim(), DateTime.now().toUtc().toIso8601String(), id],
  );

  Future<void> archiveProfile(String id) async {
    if (id == activeProfileId) {
      throw StateError('Switch profile before archiving');
    }
    database.execute(
      "UPDATE financial_profiles SET status='archived',updated_at=? WHERE id=?",
      [DateTime.now().toUtc().toIso8601String(), id],
    );
  }

  Future<void> restoreProfile(String id) async => database.execute(
    "UPDATE financial_profiles SET status='active',updated_at=? WHERE id=?",
    [DateTime.now().toUtc().toIso8601String(), id],
  );

  Future<void> setPrimaryProfile(String id) async {
    _atomic(() {
      database.execute('UPDATE financial_profiles SET is_primary=0');
      database.execute(
        'UPDATE financial_profiles SET is_primary=1,updated_at=? WHERE id=?',
        [DateTime.now().toUtc().toIso8601String(), id],
      );
    });
  }

  Future<String> stageBankEvent(
    ParsedBankEvent event, {
    required String sourcePackage,
    required DateTime detectedAt,
  }) async {
    final existing = database.select(
      'SELECT id FROM bank_notification_events WHERE profile_id=? AND (notification_key_hash=? OR content_fingerprint=?) LIMIT 1',
      [activeProfileId, event.notificationKeyHash, event.contentFingerprint],
    );
    if (existing.isNotEmpty) return existing.first['id'] as String;
    final id = _uuid.v4();
    final now = DateTime.now().toUtc().toIso8601String();
    database.execute(
      'INSERT INTO bank_notification_events(id,source_package,institution,adapter_version,notification_key_hash,content_fingerprint,detected_at,posted_at,direction,amount_satang,account_hint_masked,merchant_hint,status,parse_error_code,created_at,updated_at,profile_id) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
      [
        id,
        sourcePackage,
        event.institution,
        event.adapterVersion,
        event.notificationKeyHash,
        event.contentFingerprint,
        detectedAt.toUtc().toIso8601String(),
        detectedAt.toUtc().toIso8601String(),
        event.direction.name,
        event.amount?.satang,
        event.accountHintMasked,
        event.merchantHint,
        event.parsed ? 'pending' : 'parse_failed',
        event.errorCode,
        now,
        now,
        activeProfileId,
      ],
    );
    return id;
  }

  Future<void> ignoreBankEvent(String id) async => database.execute(
    "UPDATE bank_notification_events SET status='ignored',updated_at=? WHERE id=? AND status IN ('pending','parse_failed')",
    [DateTime.now().toUtc().toIso8601String(), id],
  );

  Future<String> confirmBankEventExpense(
    String id, {
    required String accountId,
    required String categoryId,
    bool failAfterTransaction = false,
  }) async {
    late String transactionId;
    _atomic(() {
      final rows = database.select(
        "SELECT amount_satang,status FROM bank_notification_events WHERE id=? AND status='pending'",
        [id],
      );
      if (rows.isEmpty || rows.first['amount_satang'] == null) {
        throw StateError('Bank event cannot be confirmed');
      }
      transactionId = _insertTransaction(
        accountId: accountId,
        type: 'expense',
        amount: rows.first['amount_satang'] as int,
        source: 'bank_notification',
      );
      database.execute('UPDATE transactions SET category_id=? WHERE id=?', [
        categoryId,
        transactionId,
      ]);
      if (failAfterTransaction) {
        throw StateError('Injected bank confirmation failure');
      }
      database.execute(
        "UPDATE bank_notification_events SET status='confirmed',matched_transaction_id=?,updated_at=? WHERE id=?",
        [transactionId, DateTime.now().toUtc().toIso8601String(), id],
      );
    });
    return transactionId;
  }

  Future<String> confirmBankEventsAsTransfer({
    required String outgoingEventId,
    required String incomingEventId,
    required String fromAccountId,
    required String toAccountId,
  }) async {
    late String group;
    _atomic(() {
      final events = database.select(
        "SELECT id,amount_satang,status FROM bank_notification_events WHERE id IN (?,?)",
        [outgoingEventId, incomingEventId],
      );
      if (events.length != 2 || events.any((e) => e['status'] != 'pending')) {
        throw StateError('Both events must be pending');
      }
      final amounts = events.map((e) => e['amount_satang']).toSet();
      if (amounts.length != 1 || amounts.single == null) {
        throw StateError('Amounts do not match');
      }
      group = _uuid.v4();
      final out = _insertTransaction(
        accountId: fromAccountId,
        type: 'transfer_out',
        amount: amounts.single as int,
        transferGroupId: group,
        source: 'bank_notification',
      );
      final incoming = _insertTransaction(
        accountId: toAccountId,
        type: 'transfer_in',
        amount: amounts.single as int,
        transferGroupId: group,
        source: 'bank_notification',
      );
      final now = DateTime.now().toUtc().toIso8601String();
      database.execute(
        "UPDATE bank_notification_events SET status='matched_existing',matched_transaction_id=?,updated_at=? WHERE id=?",
        [out, now, outgoingEventId],
      );
      database.execute(
        "UPDATE bank_notification_events SET status='matched_existing',matched_transaction_id=?,updated_at=? WHERE id=?",
        [incoming, now, incomingEventId],
      );
      _audit('transfer', group, 'create');
    });
    return group;
  }

  @override
  Future<String> createTransfer({
    required String fromAccountId,
    required String toAccountId,
    required int amountSatang,
    bool failAfterDebit = false,
  }) async {
    if (amountSatang <= 0) throw ArgumentError.value(amountSatang);
    if (fromAccountId == toAccountId) {
      throw ArgumentError('Transfer accounts must be different');
    }
    final owned =
        database.select(
              'SELECT COUNT(*) count FROM accounts WHERE profile_id=? AND id IN (?,?) AND deleted_at IS NULL',
              [activeProfileId, fromAccountId, toAccountId],
            ).single['count']
            as int;
    if (owned != 2) {
      throw StateError('Transfer accounts must belong to active profile');
    }
    final group = _uuid.v4();
    _atomic(() {
      _insertTransaction(
        accountId: fromAccountId,
        type: 'transfer_out',
        amount: amountSatang,
        transferGroupId: group,
      );
      if (failAfterDebit) throw StateError('Injected transfer failure');
      _insertTransaction(
        accountId: toAccountId,
        type: 'transfer_in',
        amount: amountSatang,
        transferGroupId: group,
      );
      _audit('transfer', group, 'create');
    });
    return group;
  }

  @override
  Future<void> softDeleteTransfer(
    String transferGroupId, {
    bool failAfterFirst = false,
  }) async {
    _atomic(() {
      final ids = database.select(
        'SELECT id FROM transactions WHERE transfer_group_id = ? AND deleted_at IS NULL ORDER BY id',
        [transferGroupId],
      );
      if (ids.length != 2) throw StateError('Transfer pair is incomplete');
      final now = DateTime.now().toUtc().toIso8601String();
      database.execute(
        "UPDATE transactions SET deleted_at = ?, status='deleted', updated_at = ? WHERE id = ?",
        [now, now, ids.first['id']],
      );
      if (failAfterFirst) throw StateError('Injected delete failure');
      database.execute(
        "UPDATE transactions SET deleted_at = ?, status='deleted', updated_at = ? WHERE id = ?",
        [now, now, ids.last['id']],
      );
      _audit('transfer', transferGroupId, 'delete');
    });
  }

  @override
  Future<String> stageStatement({
    required String accountId,
    required String fileName,
    required String fileHash,
    required ParsedStatement parsed,
  }) async {
    final existing = database.select(
      "SELECT id, status FROM statement_imports WHERE account_id = ? AND file_hash = ? ORDER BY imported_at DESC LIMIT 1",
      [accountId, fileHash],
    );
    if (existing.isNotEmpty) {
      final status = existing.first['status'];
      if (status == 'confirmed') {
        throw StateError('Confirmed statement file already imported');
      }
      if (status == 'preview' || status == 'undone') {
        return existing.first['id'] as String;
      }
    }
    final importId = _uuid.v4();
    _atomic(() {
      database.execute(
        'INSERT INTO statement_imports(id, account_id, institution, adapter_version, file_name, file_hash, opening_balance_satang, closing_balance_satang, status, imported_at, profile_id) VALUES(?,?,?,?,?,?,?,?,?,?,?)',
        [
          importId,
          accountId,
          parsed.institution,
          parsed.adapterVersion,
          fileName,
          fileHash,
          parsed.openingBalance?.satang,
          parsed.closingBalance?.satang,
          'preview',
          DateTime.now().toUtc().toIso8601String(),
          activeProfileId,
        ],
      );
      for (final row in [
        ...parsed.rows,
      ]..sort((a, b) => a.rowIndex.compareTo(b.rowIndex))) {
        final normalized = row.descriptionRaw.trim().toLowerCase().replaceAll(
          RegExp(r'\s+'),
          ' ',
        );
        final fingerprint = sha256
            .convert(
              utf8.encode(
                '$accountId|${_date(row.postedDate)}|${_date(row.transactionDate)}|${row.amount.satang}|${row.direction.name}|${row.referenceNo ?? ''}|$normalized',
              ),
            )
            .toString();
        database.execute(
          'INSERT INTO statement_rows(id, statement_import_id, row_index, posted_date, transaction_date, description_raw, reference_no, direction, amount_satang, running_balance_satang, row_fingerprint, profile_id) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)',
          [
            _uuid.v4(),
            importId,
            row.rowIndex,
            _date(row.postedDate),
            _date(row.transactionDate),
            row.descriptionRaw,
            row.referenceNo,
            row.direction.name,
            row.amount.satang,
            row.runningBalance?.satang,
            fingerprint,
            activeProfileId,
          ],
        );
      }
    });
    return importId;
  }

  @override
  Future<void> classifyStatementRow(
    String rowId,
    StatementClassification classification, {
    String? matchedTransactionId,
  }) async {
    if (classification == StatementClassification.matchExisting &&
        matchedTransactionId == null) {
      throw ArgumentError('matchedTransactionId is required');
    }
    database.execute(
      'UPDATE statement_rows SET classification = ?, matched_transaction_id = ? WHERE id = ?',
      [classification.name, matchedTransactionId, rowId],
    );
  }

  @override
  Future<void> cancelStatement(String importId) async {
    database.execute(
      "UPDATE statement_imports SET status = 'cancelled' WHERE id = ? AND status = 'preview'",
      [importId],
    );
  }

  @override
  Future<void> confirmStatement(
    String importId, {
    bool failMidway = false,
  }) async {
    _atomic(() {
      final batch = database.select(
        'SELECT account_id FROM statement_imports WHERE id = ? AND status IN (\'preview\',\'undone\')',
        [importId],
      );
      if (batch.isEmpty) throw StateError('Import cannot be confirmed');
      final rows = database.select(
        'SELECT * FROM statement_rows WHERE statement_import_id = ? ORDER BY row_index',
        [importId],
      );
      if (rows.any((row) => row['classification'] == 'pending')) {
        throw StateError('Pending rows must be reviewed');
      }
      for (var index = 0; index < rows.length; index++) {
        final row = rows[index];
        final classification = row['classification'] as String;
        if (classification == 'ignore' || classification == 'matchExisting') {
          continue;
        }
        final accountId = batch.first['account_id'] as String;
        String transactionId;
        if (classification == 'transfer') {
          final other = database.select(
            'SELECT id FROM accounts WHERE id != ? AND deleted_at IS NULL LIMIT 1',
            [accountId],
          );
          if (other.isEmpty) {
            throw StateError('Transfer requires a counterparty account');
          }
          final group = _uuid.v4();
          final debit = row['direction'] == 'debit';
          transactionId = _insertTransaction(
            accountId: accountId,
            type: debit ? 'transfer_out' : 'transfer_in',
            amount: row['amount_satang'] as int,
            transferGroupId: group,
            source: 'statement',
          );
          _insertTransaction(
            accountId: other.first['id'] as String,
            type: debit ? 'transfer_in' : 'transfer_out',
            amount: row['amount_satang'] as int,
            transferGroupId: group,
            source: 'statement',
          );
        } else {
          transactionId = _insertTransaction(
            accountId: accountId,
            type: classification,
            amount: row['amount_satang'] as int,
            source: 'statement',
          );
        }
        database.execute(
          'UPDATE statement_rows SET created_transaction_id = ? WHERE id = ?',
          [transactionId, row['id']],
        );
        if (failMidway && index == 0) {
          throw StateError('Injected import failure');
        }
      }
      database.execute(
        "UPDATE statement_imports SET status = 'confirmed' WHERE id = ?",
        [importId],
      );
    });
  }

  @override
  Future<void> undoStatement(String importId) async {
    _atomic(() {
      final batch = database.select(
        "SELECT id FROM statement_imports WHERE id = ? AND status = 'confirmed'",
        [importId],
      );
      if (batch.isEmpty) {
        throw StateError('Only confirmed imports can be undone');
      }
      final createdIds = database
          .select(
            'SELECT created_transaction_id FROM statement_rows WHERE statement_import_id = ? AND created_transaction_id IS NOT NULL',
            [importId],
          )
          .map((row) => row['created_transaction_id'] as String)
          .toList();
      final now = DateTime.now().toUtc().toIso8601String();
      for (final id in createdIds) {
        final groups = database.select(
          'SELECT transfer_group_id FROM transactions WHERE id = ?',
          [id],
        );
        final group = groups.first['transfer_group_id'];
        if (group == null) {
          database.execute(
            'UPDATE transactions SET deleted_at = ?, updated_at = ? WHERE id = ?',
            [now, now, id],
          );
        } else {
          database.execute(
            'UPDATE transactions SET deleted_at = ?, updated_at = ? WHERE transfer_group_id = ?',
            [now, now, group],
          );
        }
        database.execute(
          'UPDATE commitment_occurrences SET linked_transaction_id = NULL WHERE linked_transaction_id = ?',
          [id],
        );
        database.execute(
          'UPDATE budget_periods SET salary_transaction_id = NULL WHERE salary_transaction_id = ?',
          [id],
        );
      }
      database.execute(
        'UPDATE statement_rows SET matched_transaction_id = NULL, created_transaction_id = NULL WHERE statement_import_id = ?',
        [importId],
      );
      database.execute(
        "UPDATE statement_imports SET status = 'undone' WHERE id = ?",
        [importId],
      );
    });
  }

  @override
  Future<List<Map<String, Object?>>> statementRows(
    String importId,
  ) async => query(
    'SELECT * FROM statement_rows WHERE statement_import_id = ? ORDER BY row_index',
    [importId],
  );

  @override
  Future<List<Map<String, Object?>>> dumpTable(String table) async {
    if (!_backupTables.contains(table)) throw ArgumentError.value(table);
    return query(
      'SELECT * FROM $table ORDER BY ${table == 'application_metadata' ? 'key' : 'id'}',
    );
  }

  @override
  Future<Map<String, Object?>> exportBackup() async {
    final data = <String, Object?>{};
    for (final table in _backupTables) {
      data[table] = await dumpTable(table);
    }
    final payload = jsonEncode({
      'schemaVersion': SchemaV4.version,
      'data': data,
    });
    return {
      'schemaVersion': SchemaV4.version,
      'data': data,
      'checksum': sha256.convert(utf8.encode(payload)).toString(),
    };
  }

  @override
  Future<void> restoreBackup(Map<String, Object?> backup) async {
    final schemaVersion = backup['schemaVersion'];
    final data = backup['data'];
    final checksum = backup['checksum'];
    final payload = jsonEncode({'schemaVersion': schemaVersion, 'data': data});
    if ((schemaVersion != 2 &&
            schemaVersion != 3 &&
            schemaVersion != SchemaV4.version) ||
        checksum != sha256.convert(utf8.encode(payload)).toString() ||
        data is! Map) {
      throw const FormatException('Invalid or unsupported backup');
    }
    _atomic(() {
      final legacyBackup = schemaVersion != SchemaV4.version;
      final tables = legacyBackup
          ? _backupTables
                .where(
                  (table) => !const {
                    'financial_profiles',
                    'application_metadata',
                    'profile_settings',
                  }.contains(table),
                )
                .toList()
          : _backupTables;
      for (final table in tables.reversed) {
        database.execute('DELETE FROM $table');
      }
      final typed = Map<String, Object?>.from(data);
      for (final table in tables) {
        for (final raw in (typed[table] as List? ?? const [])) {
          final row = Map<String, Object?>.from(raw as Map);
          final columns = row.keys.toList();
          database.execute(
            'INSERT INTO $table(${columns.join(',')}) VALUES(${List.filled(columns.length, '?').join(',')})',
            columns.map((key) => row[key]).toList(),
          );
        }
      }
    });
  }

  Future<String> createAccount({
    required String name,
    required String type,
    required int openingBalanceSatang,
    bool salaryAccount = false,
    String? iconKey,
    int? colorValue,
  }) async {
    if (!const {'bank', 'cash', 'wallet'}.contains(type)) {
      throw ArgumentError.value(type, 'type');
    }
    final id = _uuid.v4();
    final now = DateTime.now().toUtc().toIso8601String();
    _atomic(() {
      if (salaryAccount) {
        database.execute(
          'UPDATE accounts SET is_salary_account=0 WHERE profile_id=?',
          [activeProfileId],
        );
      }
      database.execute(
        'INSERT INTO accounts(id,name,opening_balance_satang,is_active,include_in_net_worth,account_type,icon_key,color_value,is_salary_account,created_at,updated_at,profile_id) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)',
        [
          id,
          name.trim(),
          openingBalanceSatang,
          1,
          1,
          type,
          iconKey,
          colorValue,
          salaryAccount ? 1 : 0,
          now,
          now,
          activeProfileId,
        ],
      );
      _audit('account', id, 'create');
    });
    return id;
  }

  Future<void> updateAccount(
    String id, {
    required String name,
    required String type,
  }) async {
    if (!const {'bank', 'cash', 'wallet'}.contains(type)) {
      throw ArgumentError.value(type);
    }
    _atomic(() {
      database.execute(
        'UPDATE accounts SET name=?,account_type=?,updated_at=? WHERE id=? AND profile_id=? AND deleted_at IS NULL',
        [
          name.trim(),
          type,
          DateTime.now().toUtc().toIso8601String(),
          id,
          activeProfileId,
        ],
      );
      if (database.updatedRows != 1) throw StateError('Account not found');
      _audit('account', id, 'update');
    });
  }

  Future<void> archiveAccount(String id) async {
    _atomic(() {
      final active =
          database.select(
                "SELECT COUNT(*) count FROM accounts WHERE profile_id=? AND is_active=1 AND archived_at IS NULL AND deleted_at IS NULL AND id<>?",
                [activeProfileId, id],
              ).first['count']
              as int;
      if (active < 1) {
        throw StateError('At least one active account is required');
      }
      final now = DateTime.now().toUtc().toIso8601String();
      database.execute(
        'UPDATE accounts SET is_active=0,archived_at=?,updated_at=? WHERE id=? AND profile_id=?',
        [now, now, id, activeProfileId],
      );
      _audit('account', id, 'archive');
    });
  }

  Future<void> restoreAccount(String id) async {
    _atomic(() {
      database.execute(
        'UPDATE accounts SET is_active=1,archived_at=NULL,updated_at=? WHERE id=? AND profile_id=?',
        [DateTime.now().toUtc().toIso8601String(), id, activeProfileId],
      );
      _audit('account', id, 'restore');
    });
  }

  Future<List<Map<String, Object?>>> accounts({
    bool includeArchived = true,
  }) async => query(
    '''SELECT a.*, a.opening_balance_satang + COALESCE(SUM(CASE WHEN t.deleted_at IS NOT NULL THEN 0 WHEN t.type IN ('income','refund','transfer_in') THEN t.amount_satang WHEN t.type IN ('expense','transfer_out') THEN -t.amount_satang WHEN t.type='balance_adjustment' THEN t.amount_satang ELSE 0 END),0) AS balance_satang FROM accounts a LEFT JOIN transactions t ON t.account_id=a.id AND t.profile_id=a.profile_id WHERE a.profile_id=? AND a.deleted_at IS NULL ${includeArchived ? '' : 'AND a.is_active=1 AND a.archived_at IS NULL'} GROUP BY a.id ORDER BY a.created_at''',
    [activeProfileId],
  );

  Future<String> adjustBalance({
    required String accountId,
    required int deltaSatang,
    required String reason,
  }) async {
    if (deltaSatang == 0 || reason.trim().isEmpty) {
      throw ArgumentError('Adjustment and reason are required');
    }
    late String id;
    _atomic(() {
      id = _insertTransaction(
        accountId: accountId,
        type: 'balance_adjustment',
        amount: deltaSatang,
        source: 'system',
        note: reason,
      );
      _audit('transaction', id, 'adjust', metadata: {'reason': reason});
    });
    return id;
  }

  Future<String> createCategory({
    required String name,
    required String type,
    required String iconKey,
    int? colorValue,
  }) async {
    if (!const {'income', 'expense'}.contains(type)) {
      throw ArgumentError.value(type);
    }
    final id = _uuid.v4();
    final now = DateTime.now().toUtc().toIso8601String();
    _atomic(() {
      database.execute(
        'INSERT INTO categories(id,name,is_essential,category_type,icon_key,color_value,created_at,updated_at,profile_id) VALUES(?,?,?,?,?,?,?,?,?)',
        [
          id,
          name.trim(),
          0,
          type,
          iconKey,
          colorValue,
          now,
          now,
          activeProfileId,
        ],
      );
      _audit('category', id, 'create');
    });
    return id;
  }

  Future<void> archiveCategory(String id) async {
    _atomic(() {
      final now = DateTime.now().toUtc().toIso8601String();
      database.execute(
        'UPDATE categories SET archived_at=?,updated_at=? WHERE id=?',
        [now, now, id],
      );
      _audit('category', id, 'archive');
    });
  }

  Future<void> restoreCategory(String id) async {
    _atomic(() {
      database.execute(
        'UPDATE categories SET archived_at=NULL,updated_at=? WHERE id=?',
        [DateTime.now().toUtc().toIso8601String(), id],
      );
      _audit('category', id, 'restore');
    });
  }

  Future<void> updateCategory(
    String id, {
    required String name,
    required String iconKey,
    int? colorValue,
  }) async {
    _atomic(() {
      database.execute(
        'UPDATE categories SET name=?,icon_key=?,color_value=?,updated_at=? WHERE id=?',
        [
          name.trim(),
          iconKey,
          colorValue,
          DateTime.now().toUtc().toIso8601String(),
          id,
        ],
      );
      if (database.updatedRows != 1) throw StateError('Category not found');
      _audit('category', id, 'update');
    });
  }

  Future<List<Map<String, Object?>>> categories({
    String? type,
    bool activeOnly = true,
  }) async => query(
    'SELECT * FROM categories WHERE profile_id=? AND deleted_at IS NULL ${activeOnly ? 'AND archived_at IS NULL' : ''} ${type == null ? '' : 'AND category_type=?'} ORDER BY sort_order,name',
    type == null ? [activeProfileId] : [activeProfileId, type],
  );

  Future<String> createTransaction({
    required String accountId,
    required String categoryId,
    required String type,
    required int amountSatang,
    DateTime? occurredAt,
    String? note,
    String? refundOfTransactionId,
  }) async {
    if (!const {'income', 'expense', 'refund'}.contains(type) ||
        amountSatang <= 0) {
      throw ArgumentError('Invalid transaction');
    }
    final category = database.select(
      'SELECT category_type FROM categories WHERE id=? AND profile_id=? AND archived_at IS NULL',
      [categoryId, activeProfileId],
    );
    if (category.isEmpty) throw StateError('Category unavailable');
    final expected = type == 'income' ? 'income' : 'expense';
    if (category.first['category_type'] != expected) {
      throw StateError('Category type mismatch');
    }
    late String id;
    _atomic(() {
      id = _insertTransaction(
        accountId: accountId,
        type: type,
        amount: amountSatang,
        source: 'manual',
        categoryId: categoryId,
        note: note,
        occurredAt: occurredAt,
        refundOfTransactionId: refundOfTransactionId,
      );
      _audit('transaction', id, 'create');
    });
    return id;
  }

  Future<List<Map<String, Object?>>> activity({
    bool includeDeleted = false,
  }) async => query(
    '''SELECT t.*,a.name account_name,c.name category_name,c.icon_key,c.color_value FROM transactions t JOIN accounts a ON a.id=t.account_id LEFT JOIN categories c ON c.id=t.category_id WHERE t.profile_id=? AND ${includeDeleted ? '1=1' : 't.deleted_at IS NULL'} ORDER BY t.occurred_at DESC,t.created_at DESC''',
    [activeProfileId],
  );

  Future<void> softDeleteTransaction(String id) async {
    final group = database.select(
      'SELECT transfer_group_id FROM transactions WHERE id=?',
      [id],
    );
    if (group.isEmpty) throw StateError('Transaction not found');
    if (group.first['transfer_group_id'] != null) {
      return softDeleteTransfer(group.first['transfer_group_id'] as String);
    }
    _atomic(() {
      final now = DateTime.now().toUtc().toIso8601String();
      database.execute(
        "UPDATE transactions SET deleted_at=?,status='deleted',updated_at=? WHERE id=? AND deleted_at IS NULL",
        [now, now, id],
      );
      _audit('transaction', id, 'delete');
    });
  }

  Future<void> restoreTransactionRecord(String id) async {
    _atomic(() {
      final rows = database.select(
        'SELECT transfer_group_id FROM transactions WHERE id=?',
        [id],
      );
      if (rows.isEmpty) throw StateError('Transaction not found');
      final group = rows.first['transfer_group_id'];
      final now = DateTime.now().toUtc().toIso8601String();
      if (group == null) {
        database.execute(
          "UPDATE transactions SET deleted_at=NULL,status='confirmed',updated_at=? WHERE id=?",
          [now, id],
        );
      } else {
        database.execute(
          "UPDATE transactions SET deleted_at=NULL,status='confirmed',updated_at=? WHERE transfer_group_id=?",
          [now, group],
        );
      }
      _audit('transaction', id, 'restore');
    });
  }

  Future<void> updateTransaction({
    required String id,
    required String accountId,
    required String categoryId,
    required int amountSatang,
    required DateTime occurredAt,
    String? note,
  }) async {
    if (amountSatang <= 0) throw ArgumentError.value(amountSatang);
    _atomic(() {
      final rows = database.select(
        'SELECT type,transfer_group_id FROM transactions WHERE id=? AND deleted_at IS NULL',
        [id],
      );
      if (rows.isEmpty) throw StateError('Transaction not found');
      if (rows.single['transfer_group_id'] != null) {
        throw StateError('Use transfer edit for a transfer pair');
      }
      final expected = rows.single['type'] == 'income' ? 'income' : 'expense';
      final category = database.select(
        'SELECT category_type FROM categories WHERE id=? AND profile_id=? AND archived_at IS NULL',
        [categoryId, activeProfileId],
      );
      if (category.isEmpty || category.single['category_type'] != expected) {
        throw StateError('Category type mismatch');
      }
      database.execute(
        'UPDATE transactions SET account_id=?,category_id=?,amount_satang=?,occurred_at=?,note=?,updated_at=? WHERE id=?',
        [
          accountId,
          categoryId,
          amountSatang,
          occurredAt.toUtc().toIso8601String(),
          note,
          DateTime.now().toUtc().toIso8601String(),
          id,
        ],
      );
      _audit('transaction', id, 'update');
    });
  }

  Future<void> updateTransfer({
    required String groupId,
    required String fromAccountId,
    required String toAccountId,
    required int amountSatang,
  }) async {
    if (fromAccountId == toAccountId || amountSatang <= 0) {
      throw ArgumentError('Invalid transfer');
    }
    _atomic(() {
      final rows = database.select(
        'SELECT id,type FROM transactions WHERE transfer_group_id=? AND deleted_at IS NULL',
        [groupId],
      );
      if (rows.length != 2) throw StateError('Transfer pair is incomplete');
      final now = DateTime.now().toUtc().toIso8601String();
      for (final row in rows) {
        database.execute(
          'UPDATE transactions SET account_id=?,amount_satang=?,updated_at=? WHERE id=?',
          [
            row['type'] == 'transfer_out' ? fromAccountId : toAccountId,
            amountSatang,
            now,
            row['id'],
          ],
        );
      }
      _audit('transfer', groupId, 'update');
    });
  }

  Future<String> createCommitment({
    required String name,
    required String type,
    int? totalSatang,
    int? regularSatang,
    String? accountId,
    String? categoryId,
  }) async {
    if (!const {'fixed_total', 'open_ended'}.contains(type)) {
      throw ArgumentError.value(type);
    }
    if (type == 'fixed_total' && (totalSatang == null || totalSatang <= 0)) {
      throw ArgumentError('Fixed total is required');
    }
    final id = _uuid.v4();
    final now = DateTime.now().toUtc().toIso8601String();
    database.execute(
      'INSERT INTO commitments(id,category_id,default_account_id,name,commitment_type,total_payable_satang,regular_payment_satang,status,created_at,updated_at,profile_id) VALUES(?,?,?,?,?,?,?,?,?,?,?)',
      [
        id,
        categoryId,
        accountId,
        name.trim(),
        type,
        totalSatang,
        regularSatang,
        'active',
        now,
        now,
        activeProfileId,
      ],
    );
    _audit('commitment', id, 'create');
    return id;
  }

  Future<String> recordCommitmentPayment({
    required String commitmentId,
    required String accountId,
    required String categoryId,
    required int amountSatang,
  }) async {
    late String transactionId;
    _atomic(() {
      transactionId = _insertTransaction(
        accountId: accountId,
        type: 'expense',
        amount: amountSatang,
        categoryId: categoryId,
        source: 'manual',
      );
      final now = DateTime.now().toUtc().toIso8601String();
      database.execute(
        'INSERT INTO commitment_payments(id,commitment_id,transaction_id,created_at,updated_at,profile_id) VALUES(?,?,?,?,?,?)',
        [_uuid.v4(), commitmentId, transactionId, now, now, activeProfileId],
      );
      _audit('transaction', transactionId, 'create');
    });
    return transactionId;
  }

  Future<int> commitmentPaidSatang(String commitmentId) async =>
      database.select(
            "SELECT COALESCE(SUM(CASE WHEN t.type='expense' THEN t.amount_satang WHEN t.type='refund' THEN -t.amount_satang ELSE 0 END),0) total FROM commitment_payments p JOIN transactions t ON t.id=p.transaction_id WHERE p.commitment_id=? AND p.deleted_at IS NULL AND t.deleted_at IS NULL",
            [commitmentId],
          ).first['total']
          as int;

  Future<List<Map<String, Object?>>> commitments() async => query(
    '''SELECT c.*,COALESCE(SUM(CASE WHEN t.deleted_at IS NULL AND t.type='expense' THEN t.amount_satang WHEN t.deleted_at IS NULL AND t.type='refund' THEN -t.amount_satang ELSE 0 END),0) AS paid_satang FROM commitments c LEFT JOIN commitment_payments p ON p.commitment_id=c.id AND p.deleted_at IS NULL LEFT JOIN transactions t ON t.id=p.transaction_id WHERE c.profile_id=? AND c.deleted_at IS NULL AND c.status<>'archived' GROUP BY c.id ORDER BY c.created_at DESC''',
    [activeProfileId],
  );

  Future<void> updateCommitmentTarget(String id, int? targetSatang) async {
    if (targetSatang != null && targetSatang <= 0) {
      throw ArgumentError.value(targetSatang);
    }
    database.execute(
      "UPDATE commitments SET target_satang=?,updated_at=? WHERE id=? AND commitment_type='open_ended'",
      [targetSatang, DateTime.now().toUtc().toIso8601String(), id],
    );
  }

  Future<void> resetUserData({bool failMidway = false}) async {
    _atomic(() {
      const scoped = <String>[
        'statement_rows',
        'statement_imports',
        'bank_notification_events',
        'commitment_payments',
        'commitments',
        'installment_total_adjustments',
        'commitment_occurrences',
        'transactions',
        'period_budgets',
        'budget_periods',
        'payroll_deductions',
        'salary_profiles',
        'saving_goals',
        'recurring_expenses',
        'installments',
        'categories',
        'accounts',
        'profile_settings',
        'audit_events',
      ];
      final profile = activeProfileId;
      for (final table in scoped) {
        database.execute('DELETE FROM $table WHERE profile_id=?', [profile]);
        if (failMidway && table == 'transactions') {
          throw StateError('Injected reset failure');
        }
      }
      _audit('database', 'local-user-data', 'reset');
    });
  }

  String _insertTransaction({
    required String accountId,
    required String type,
    required int amount,
    String? transferGroupId,
    String source = 'manual',
    String? categoryId,
    String? note,
    DateTime? occurredAt,
    String? refundOfTransactionId,
  }) {
    final id = _uuid.v4();
    final now = DateTime.now().toUtc().toIso8601String();
    database.execute(
      'INSERT INTO transactions(id, account_id, category_id, type, amount_satang, occurred_at, transfer_group_id, refund_of_transaction_id, source, note, created_at, updated_at,profile_id) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)',
      [
        id,
        accountId,
        categoryId,
        type,
        amount,
        (occurredAt ?? DateTime.now()).toUtc().toIso8601String(),
        transferGroupId,
        refundOfTransactionId,
        source,
        note,
        now,
        now,
        activeProfileId,
      ],
    );
    return id;
  }

  void _audit(
    String entityType,
    String entityId,
    String action, {
    Map<String, Object?>? metadata,
  }) {
    final now = DateTime.now().toUtc().toIso8601String();
    database.execute(
      'INSERT INTO audit_events(id,entity_type,entity_id,action,occurred_at,metadata_json,created_at,profile_id) VALUES(?,?,?,?,?,?,?,?)',
      [
        _uuid.v4(),
        entityType,
        entityId,
        action,
        now,
        metadata == null ? null : jsonEncode(metadata),
        now,
        activeProfileId,
      ],
    );
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

  static String _date(DateTime value) =>
      value.toUtc().toIso8601String().split('T').first;
}
