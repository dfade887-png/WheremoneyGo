import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models/financial_models.dart';
import '../../domain/models/scheduled_financial_event.dart';
import '../../domain/commitment_projection.dart';
import '../../domain/financial_calendar.dart';
import '../../domain/bank_notification/bank_notification_adapter.dart';
import '../../domain/repositories/finance_repository.dart';
import '../../domain/repositories/financial_calendar_repository.dart';
import '../../domain/repositories/commitment_projection_repository.dart';
import '../../domain/repositories/projected_balance_repository.dart';
import '../../domain/repositories/salary_projection_repository.dart';
import '../../domain/repositories/scheduled_financial_event_repository.dart';
import '../../domain/projected_balance.dart';
import '../../domain/payday_calendar.dart';
import '../../domain/salary_projection.dart';
import '../../domain/transaction_lifecycle.dart';
import '../../domain/notification_capture.dart';
import '../../domain/slip_media.dart';
import '../../domain/slip_parser.dart';
import '../../domain/notification_rule_parser.dart';
import '../../domain/candidate_matching.dart';
import '../../domain/candidate_review.dart';
import '../../domain/transfer_correlation.dart';
import '../candidate_notification_service.dart';
import '../local/migration_runner.dart';
import '../local/schema_v5.dart';

final class SqliteFinanceRepository
    implements
        FinanceRepository,
        ScheduledFinancialEventRepository,
        ProjectedBalanceRepository,
        CommitmentProjectionRepository,
        SalaryProjectionRepository,
        FinancialCalendarRepository,
        NotificationCaptureRepository,
        NotificationRuleRepository,
        CandidateMatchingRepository,
        CandidateReviewRepository,
        TransferCorrelationRepository,
        ProcessRawNotificationRepository,
        CandidateCreationInspector,
        SlipMediaRepository {
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
    'scheduled_financial_events',
    'notification_sources',
    'notification_rules',
    'transaction_candidates',
    'candidate_evidence',
  ];

  void _migrate() {
    MigrationRunner.migrateToLatest(database, includeV6: true);
    // T20 is additive and keeps the accepted schema/user_version at v5.
    // This also upgrades existing v5 devices without a destructive migration.
    database.execute(
      SchemaV5.statements.firstWhere(
        (statement) => statement.startsWith(
          'CREATE TABLE IF NOT EXISTS slip_media_events',
        ),
      ),
    );
    try {
      database.execute(
        "ALTER TABLE slip_media_events ADD COLUMN ingestion_source TEXT NOT NULL DEFAULT 'automatic' CHECK(ingestion_source IN ('automatic','manual'))",
      );
    } catch (_) {
      // Existing installations already have this additive T20.0.1 column.
    }
    database.execute(
      SchemaV5.statements.firstWhere(
        (statement) => statement.startsWith(
          'CREATE INDEX IF NOT EXISTS slip_media_profile_status',
        ),
      ),
    );
  }

  static const _slipEnabledKey = 'slip_detection_enabled';
  static const _slipBaselineKey = 'slip_detection_baseline_ms';

  String? _profileSetting(String key) {
    final rows = database.select(
      'SELECT value FROM profile_settings WHERE profile_id=? AND key=? AND deleted_at IS NULL',
      [activeProfileId, key],
    );
    return rows.isEmpty ? null : rows.single['value'] as String;
  }

  void _setProfileSetting(String key, String value) {
    final now = DateTime.now().toUtc().toIso8601String();
    database.execute(
      '''INSERT INTO profile_settings(id,profile_id,key,value,created_at,updated_at)
         VALUES(?,?,?,?,?,?) ON CONFLICT(profile_id,key) DO UPDATE SET
         value=excluded.value,updated_at=excluded.updated_at,deleted_at=NULL''',
      [_uuid.v4(), activeProfileId, key, value, now, now],
    );
  }

  @override
  Future<bool> slipDetectionEnabled() async =>
      _profileSetting(_slipEnabledKey) == '1';

  @override
  Future<void> setSlipDetectionEnabled(bool enabled) async {
    _setProfileSetting(_slipEnabledKey, enabled ? '1' : '0');
  }

  @override
  Future<DateTime?> slipDetectionBaseline() async {
    final value = _profileSetting(_slipBaselineKey);
    final millis = value == null ? null : int.tryParse(value);
    return millis == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
  }

  @override
  Future<void> initializeSlipDetectionBaseline(DateTime baseline) async {
    if (_profileSetting(_slipBaselineKey) == null) {
      _setProfileSetting(
        _slipBaselineKey,
        baseline.toUtc().millisecondsSinceEpoch.toString(),
      );
    }
  }

  @override
  Future<List<SlipMediaEvent>> stageNewSlipMedia(
    List<SlipMediaMetadata> media, {
    String ingestionSource = 'automatic',
  }) async {
    if (!const {'automatic', 'manual'}.contains(ingestionSource)) {
      throw ArgumentError.value(ingestionSource, 'ingestionSource');
    }
    if (!await slipDetectionEnabled()) return const [];
    final baseline = await slipDetectionBaseline();
    if (baseline == null) return const [];
    final now = DateTime.now().toUtc();
    final stagedIds = <String>[];
    database.execute('BEGIN IMMEDIATE');
    try {
      for (final item in media) {
        if (!item.supportedMimeType ||
            (ingestionSource == 'automatic' &&
                !item.dateAdded.isAfter(baseline))) {
          continue;
        }
        final id = _uuid.v4();
        database.execute(
          '''INSERT OR IGNORE INTO slip_media_events(
             id,profile_id,media_store_id,content_uri,mime_type,media_created_at,
             discovered_at,status,ingestion_source,created_at,updated_at)
             VALUES(?,?,?,?,?,?,?,'detected',?,?,?)''',
          [
            id,
            activeProfileId,
            item.mediaStoreId,
            item.contentUri,
            item.mimeType.toLowerCase(),
            item.dateTaken?.toUtc().toIso8601String(),
            now.toIso8601String(),
            ingestionSource,
            now.toIso8601String(),
            now.toIso8601String(),
          ],
        );
        final inserted = database.select(
          'SELECT id FROM slip_media_events WHERE profile_id=? AND media_store_id=? AND content_uri=?',
          [activeProfileId, item.mediaStoreId, item.contentUri],
        );
        if (inserted.isNotEmpty && inserted.single['id'] == id) {
          stagedIds.add(id);
        }
      }
      database.execute('COMMIT');
    } catch (_) {
      database.execute('ROLLBACK');
      rethrow;
    }
    if (stagedIds.isEmpty) return const [];
    return database
        .select(
          'SELECT * FROM slip_media_events WHERE id IN (${List.filled(stagedIds.length, '?').join(',')}) ORDER BY discovered_at,id',
          stagedIds,
        )
        .map(_slipEventFromRow)
        .toList(growable: false);
  }

  SlipMediaEvent _slipEventFromRow(Map<String, Object?> row) => SlipMediaEvent(
    id: row['id'] as String,
    profileId: row['profile_id'] as String,
    mediaStoreId: row['media_store_id'] as String,
    contentUri: row['content_uri'] as String,
    contentHash: row['content_hash'] as String?,
    mimeType: row['mime_type'] as String,
    mediaCreatedAt: row['media_created_at'] == null
        ? null
        : DateTime.parse(row['media_created_at'] as String),
    discoveredAt: DateTime.parse(row['discovered_at'] as String),
    status: row['status'] as String,
    ingestionSource: row['ingestion_source'] as String? ?? 'unknown',
  );

  @override
  Future<List<SlipMediaEvent>> slipMediaEvents() async => database
      .select(
        'SELECT * FROM slip_media_events WHERE profile_id=? AND deleted_at IS NULL ORDER BY discovered_at,id',
        [activeProfileId],
      )
      .map(_slipEventFromRow)
      .toList(growable: false);

  @override
  Future<SlipParseRecord?> slipParseRecord(String eventId) async {
    final rows = query(
      'SELECT * FROM slip_parse_results WHERE profile_id=? AND slip_media_event_id=? AND deleted_at IS NULL',
      [activeProfileId, eventId],
    );
    if (rows.isEmpty) return null;
    return _parseRecordFromRow(rows.single);
  }

  SlipParseRecord _parseRecordFromRow(Map<String, Object?> row) {
    final isFinancial = row['candidate_type'] != null;
    final direction = switch (row['candidate_type'] as String?) {
      'expense' => SlipDirection.outgoing,
      'income' => SlipDirection.incoming,
      _ => null,
    };
    final warnings = (row['warnings_json'] as String?) == null
        ? const <String>[]
        : (jsonDecode(row['warnings_json'] as String) as List).cast<String>();
    return SlipParseRecord(
      slipMediaEventId: row['slip_media_event_id'] as String,
      processingStatus: row['processing_status'] as String,
      failureCode: row['failure_code'] as String?,
      candidateId: row['candidate_id'] as String?,
      result: row['parser_id'] == null
          ? null
          : NormalizedSlipResult(
              isFinancialSlip: isFinancial,
              parserId: row['parser_id'] as String,
              parserVersion: row['parser_version'] as String? ?? '1',
              confidence: (row['confidence'] as num?)?.toDouble() ?? 0,
              direction: direction,
              amountSatang: row['amount_satang'] as int?,
              occurredAt: row['occurred_at'] == null
                  ? null
                  : DateTime.parse(row['occurred_at'] as String),
              merchantOrSender: row['merchant_or_sender'] as String?,
              bankHint: row['bank_hint'] as String?,
              accountHint: row['account_hint'] as String?,
              referenceNo: row['reference_no'] as String?,
              warnings: warnings,
            ),
    );
  }

  @override
  Future<SlipParseRecord> saveSlipParseResult(
    String eventId,
    NormalizedSlipResult result,
  ) async {
    final exists = query(
      'SELECT id FROM slip_media_events WHERE id=? AND profile_id=? AND deleted_at IS NULL',
      [eventId, activeProfileId],
    );
    if (exists.isEmpty) throw StateError('Slip event unavailable');
    final now = DateTime.now().toUtc().toIso8601String();
    final status = !result.isFinancialSlip
        ? 'not_financial'
        : result.isHighConfidence
        ? 'parsed'
        : 'parsed_needs_review';
    _atomic(() {
      database.execute(
        '''INSERT INTO slip_parse_results(id,profile_id,slip_media_event_id,parser_id,parser_version,processing_status,confidence,candidate_type,amount_satang,occurred_at,merchant_or_sender,bank_hint,account_hint,reference_no,warnings_json,created_at,updated_at)
           VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
           ON CONFLICT(profile_id,slip_media_event_id) DO UPDATE SET
           parser_id=excluded.parser_id,parser_version=excluded.parser_version,processing_status=excluded.processing_status,confidence=excluded.confidence,candidate_type=excluded.candidate_type,amount_satang=excluded.amount_satang,occurred_at=excluded.occurred_at,merchant_or_sender=excluded.merchant_or_sender,bank_hint=excluded.bank_hint,account_hint=excluded.account_hint,reference_no=excluded.reference_no,warnings_json=excluded.warnings_json,failure_code=NULL,updated_at=excluded.updated_at,deleted_at=NULL''',
        [
          _uuid.v4(),
          activeProfileId,
          eventId,
          result.parserId,
          result.parserVersion,
          status,
          result.confidence,
          result.direction == SlipDirection.outgoing
              ? 'expense'
              : result.direction == SlipDirection.incoming
              ? 'income'
              : null,
          result.amountSatang,
          result.occurredAt?.toUtc().toIso8601String(),
          result.merchantOrSender,
          result.bankHint,
          result.accountHint,
          result.referenceNo,
          jsonEncode(result.warnings),
          now,
          now,
        ],
      );
      database.execute(
        'UPDATE slip_media_events SET status=?,updated_at=? WHERE id=?',
        [status, now, eventId],
      );
    });
    return (await slipParseRecord(eventId))!;
  }

  @override
  Future<SlipParseRecord> markSlipParseFailed(
    String eventId,
    String failureCode,
  ) async {
    final now = DateTime.now().toUtc().toIso8601String();
    _atomic(() {
      database.execute(
        '''INSERT INTO slip_parse_results(id,profile_id,slip_media_event_id,processing_status,failure_code,created_at,updated_at)
           VALUES(?,?,?,'failed',?,?,?) ON CONFLICT(profile_id,slip_media_event_id) DO UPDATE SET processing_status='failed',failure_code=excluded.failure_code,updated_at=excluded.updated_at''',
        [_uuid.v4(), activeProfileId, eventId, failureCode, now, now],
      );
      database.execute(
        "UPDATE slip_media_events SET status='failed',updated_at=? WHERE id=? AND profile_id=?",
        [now, eventId, activeProfileId],
      );
    });
    return (await slipParseRecord(eventId))!;
  }

  @override
  Future<void> markSlipNotFinancial(String eventId) async {
    final now = DateTime.now().toUtc().toIso8601String();
    database.execute(
      "UPDATE slip_media_events SET status='ignored',updated_at=? WHERE id=? AND profile_id=?",
      [now, eventId, activeProfileId],
    );
  }

  @override
  Future<String?> createCandidateFromSlip(String eventId) async {
    final record = await slipParseRecord(eventId);
    final result = record?.result;
    if (record == null ||
        !result!.isHighConfidence ||
        record.candidateId != null) {
      return record?.candidateId;
    }
    final now = DateTime.now().toUtc().toIso8601String();
    final candidateId = _uuid.v4();
    _atomic(() {
      final existing = query(
        'SELECT candidate_id FROM candidate_evidence WHERE slip_media_event_id=?',
        [eventId],
      );
      if (existing.isNotEmpty) return;
      database.execute(
        '''INSERT INTO transaction_candidates(id,profile_id,account_id,destination_account_id,category_id,candidate_type,amount_satang,occurred_at,merchant_or_sender,reference_no,confidence,review_status,matched_scheduled_event_id,matched_transaction_id,created_at,updated_at)
           VALUES(?,?,?,?,?,?,?,?,?,?,?,'pending_review',NULL,NULL,?,?)''',
        [
          candidateId,
          activeProfileId,
          null,
          null,
          null,
          result.direction == SlipDirection.outgoing ? 'expense' : 'income',
          result.amountSatang,
          result.occurredAt!.toUtc().toIso8601String(),
          result.merchantOrSender,
          result.referenceNo,
          result.confidence,
          now,
          now,
        ],
      );
      database.execute(
        '''INSERT INTO candidate_evidence(id,candidate_id,evidence_type,slip_media_event_id,parser_id,parser_version,confidence,created_at)
           VALUES(?,?,'slip',?,?,?,?,?)''',
        [
          _uuid.v4(),
          candidateId,
          eventId,
          result.parserId,
          result.parserVersion,
          result.confidence,
          now,
        ],
      );
      database.execute(
        "UPDATE slip_parse_results SET processing_status='candidate_created',candidate_id=?,updated_at=? WHERE profile_id=? AND slip_media_event_id=?",
        [candidateId, now, activeProfileId, eventId],
      );
      database.execute(
        "UPDATE slip_media_events SET status='candidate_created',updated_at=? WHERE id=?",
        [now, eventId],
      );
    });
    return (await slipParseRecord(eventId))?.candidateId;
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

  @override
  Future<String> createNotificationSource({
    required String sourceKind,
    required String displayName,
    required String packageName,
    String? defaultAccountId,
    int retentionDays = 7,
  }) async {
    if (!const {'line', 'bank_app', 'other_android'}.contains(sourceKind)) {
      throw ArgumentError.value(sourceKind, 'sourceKind');
    }
    final normalizedPackage = packageName.trim();
    if (displayName.trim().isEmpty || normalizedPackage.isEmpty) {
      throw ArgumentError('Display name and package name are required');
    }
    if (retentionDays < 0) throw ArgumentError.value(retentionDays);
    if (defaultAccountId != null) {
      final account = database.select(
        'SELECT id FROM accounts WHERE id=? AND profile_id=? AND deleted_at IS NULL',
        [defaultAccountId, activeProfileId],
      );
      if (account.isEmpty) throw StateError('Default account is unavailable');
    }
    final existing = database.select(
      'SELECT id FROM notification_sources WHERE profile_id=? AND package_name=? AND deleted_at IS NULL LIMIT 1',
      [activeProfileId, normalizedPackage],
    );
    if (existing.isNotEmpty) return existing.single['id'] as String;
    final id = _uuid.v4();
    final now = DateTime.now().toUtc().toIso8601String();
    database.execute(
      'INSERT INTO notification_sources(id,profile_id,source_kind,display_name,package_name,enabled,default_account_id,retention_days,created_at,updated_at) VALUES(?,?,?,?,?,1,?,?,?,?)',
      [
        id,
        activeProfileId,
        sourceKind,
        displayName.trim(),
        normalizedPackage,
        defaultAccountId,
        retentionDays,
        now,
        now,
      ],
    );
    return id;
  }

  @override
  Future<List<NotificationSource>> notificationSources() async => database
      .select(
        'SELECT * FROM notification_sources WHERE profile_id=? AND deleted_at IS NULL ORDER BY display_name,id',
        [activeProfileId],
      )
      .map(
        (row) => NotificationSource(
          id: row['id'] as String,
          profileId: row['profile_id'] as String,
          sourceKind: row['source_kind'] as String,
          displayName: row['display_name'] as String,
          packageName: row['package_name'] as String,
          enabled: row['enabled'] == 1,
          defaultAccountId: row['default_account_id'] as String?,
          retentionDays: row['retention_days'] as int,
        ),
      )
      .toList(growable: false);

  @override
  Future<void> setNotificationSourceEnabled(String id, bool enabled) async {
    final changed = database.select(
      'SELECT id FROM notification_sources WHERE id=? AND profile_id=? AND deleted_at IS NULL',
      [id, activeProfileId],
    );
    if (changed.isEmpty) throw StateError('Notification source unavailable');
    database.execute(
      'UPDATE notification_sources SET enabled=?,updated_at=? WHERE id=?',
      [enabled ? 1 : 0, DateTime.now().toUtc().toIso8601String(), id],
    );
  }

  @override
  Future<String?> ingestCapturedNotification(CapturedNotification event) async {
    final source = database.select(
      '''SELECT id FROM notification_sources
         WHERE id=? AND profile_id=? AND package_name=? AND enabled=1 AND deleted_at IS NULL''',
      [event.notificationSourceId, event.profileId, event.packageName],
    );
    if (source.isEmpty) return null;
    final existing = database.select(
      'SELECT id FROM raw_notification_events WHERE profile_id=? AND package_name=? AND notification_key_hash=?',
      [event.profileId, event.packageName, event.notificationKeyHash],
    );
    final captured = event.capturedAt.toUtc().toIso8601String();
    if (existing.isNotEmpty) {
      database.execute(
        '''UPDATE raw_notification_events
           SET notification_source_id=?,content_fingerprint=?,title=?,body=?,sender_or_chat=?,captured_at=?,parse_status='captured',matched_rule_id=NULL
           WHERE id=?''',
        [
          event.notificationSourceId,
          event.contentFingerprint,
          event.title,
          event.body,
          event.senderOrChat,
          captured,
          existing.single['id'],
        ],
      );
      return existing.single['id'] as String;
    }
    final id = _uuid.v4();
    database.execute(
      '''INSERT INTO raw_notification_events(
         id,profile_id,notification_source_id,package_name,notification_key_hash,
         content_fingerprint,title,body,sender_or_chat,captured_at,parse_status,
         matched_rule_id,created_at)
         VALUES(?,?,?,?,?,?,?,?,?,?,'captured',NULL,?)''',
      [
        id,
        event.profileId,
        event.notificationSourceId,
        event.packageName,
        event.notificationKeyHash,
        event.contentFingerprint,
        event.title,
        event.body,
        event.senderOrChat,
        captured,
        DateTime.now().toUtc().toIso8601String(),
      ],
    );
    return id;
  }

  @override
  Future<String> createNotificationRule({
    required String notificationSourceId,
    required String name,
    required String bodyPattern,
    required String parserKind,
    required String directionRule,
    String? senderOrChatPattern,
    String? titlePattern,
    String? accountId,
    String? categoryId,
    int priority = 0,
  }) async {
    if (!const {'template', 'regex', 'keyword'}.contains(parserKind)) {
      throw ArgumentError.value(parserKind);
    }
    if (!const {
      'incoming',
      'outgoing',
      'refund',
      'transfer',
    }.contains(directionRule)) {
      throw ArgumentError.value(directionRule);
    }
    final source = database.select(
      'SELECT id,default_account_id FROM notification_sources WHERE id=? AND profile_id=? AND deleted_at IS NULL',
      [notificationSourceId, activeProfileId],
    );
    if (source.isEmpty) throw StateError('Notification source unavailable');
    _validateRuleDefinition(
      name: name,
      bodyPattern: bodyPattern,
      parserKind: parserKind,
      directionRule: directionRule,
      accountId: accountId ?? source.single['default_account_id'] as String?,
      categoryId: categoryId,
    );
    final id = _uuid.v4();
    final now = DateTime.now().toUtc().toIso8601String();
    database.execute(
      '''INSERT INTO notification_rules(
         id,notification_source_id,name,sender_or_chat_pattern,title_pattern,
         body_pattern,parser_kind,direction_rule,account_id,category_id,priority,
         enabled,rule_version,created_at,updated_at)
         VALUES(?,?,?,?,?,?,?,?,?,?,?,1,1,?,?)''',
      [
        id,
        notificationSourceId,
        name.trim(),
        senderOrChatPattern?.trim(),
        titlePattern?.trim(),
        bodyPattern,
        parserKind,
        directionRule,
        accountId,
        categoryId,
        priority,
        now,
        now,
      ],
    );
    return id;
  }

  void _validateRuleDefinition({
    required String name,
    required String bodyPattern,
    required String parserKind,
    required String directionRule,
    required String? accountId,
    required String? categoryId,
  }) {
    if (name.trim().isEmpty) throw ArgumentError('Rule name is required');
    if (bodyPattern.trim().isEmpty) {
      throw ArgumentError('Body pattern is required');
    }
    if (parserKind == 'regex') {
      try {
        RegExp(bodyPattern);
      } on FormatException {
        throw ArgumentError('Invalid regular expression');
      }
    }
    if (parserKind == 'template' && !bodyPattern.contains('{amount}')) {
      throw ArgumentError('Template must contain {amount}');
    }
    if (accountId == null) throw StateError('Rule account is required');
    if (database.select(
      'SELECT id FROM accounts WHERE id=? AND profile_id=? AND is_active=1 AND deleted_at IS NULL',
      [accountId, activeProfileId],
    ).isEmpty) {
      throw StateError('Rule account unavailable');
    }
    if (categoryId != null) {
      final categories = database.select(
        'SELECT category_type FROM categories WHERE id=? AND profile_id=? AND archived_at IS NULL AND deleted_at IS NULL',
        [categoryId, activeProfileId],
      );
      final expected = directionRule == 'incoming' ? 'income' : 'expense';
      if (categories.isEmpty ||
          categories.single['category_type'] != expected) {
        throw StateError('Rule category is unavailable or incompatible');
      }
    }
  }

  @override
  Future<List<NotificationRule>> notificationRules(String sourceId) async =>
      database
          .select(
            '''SELECT r.* FROM notification_rules r
               JOIN notification_sources s ON s.id=r.notification_source_id
               WHERE r.notification_source_id=? AND s.profile_id=?
                 AND r.deleted_at IS NULL AND s.deleted_at IS NULL
               ORDER BY r.priority DESC,r.id''',
            [sourceId, activeProfileId],
          )
          .map(_notificationRuleFromRow)
          .toList(growable: false);

  NotificationRule _notificationRuleFromRow(Row row) => NotificationRule(
    id: row['id'] as String,
    notificationSourceId: row['notification_source_id'] as String,
    name: row['name'] as String,
    senderOrChatPattern: row['sender_or_chat_pattern'] as String?,
    titlePattern: row['title_pattern'] as String?,
    bodyPattern: row['body_pattern'] as String,
    parserKind: row['parser_kind'] as String,
    directionRule: row['direction_rule'] as String,
    accountId: row['account_id'] as String?,
    categoryId: row['category_id'] as String?,
    priority: row['priority'] as int,
    enabled: row['enabled'] == 1,
    ruleVersion: row['rule_version'] as int,
  );

  @override
  Future<void> updateNotificationRule(NotificationRule rule) async {
    final owned = database.select(
      '''SELECT r.id FROM notification_rules r JOIN notification_sources s
         ON s.id=r.notification_source_id
         WHERE r.id=? AND s.profile_id=? AND r.deleted_at IS NULL''',
      [rule.id, activeProfileId],
    );
    if (owned.isEmpty) throw StateError('Notification rule unavailable');
    if (!const {'template', 'regex', 'keyword'}.contains(rule.parserKind) ||
        !const {
          'incoming',
          'outgoing',
          'refund',
          'transfer',
        }.contains(rule.directionRule)) {
      throw ArgumentError('Invalid rule configuration');
    }
    final source = database.select(
      'SELECT default_account_id FROM notification_sources WHERE id=? AND profile_id=? AND deleted_at IS NULL',
      [rule.notificationSourceId, activeProfileId],
    );
    _validateRuleDefinition(
      name: rule.name,
      bodyPattern: rule.bodyPattern,
      parserKind: rule.parserKind,
      directionRule: rule.directionRule,
      accountId:
          rule.accountId ?? source.single['default_account_id'] as String?,
      categoryId: rule.categoryId,
    );
    database.execute(
      '''UPDATE notification_rules SET name=?,sender_or_chat_pattern=?,
         title_pattern=?,body_pattern=?,parser_kind=?,direction_rule=?,
         account_id=?,category_id=?,priority=?,enabled=?,rule_version=rule_version+1,
         updated_at=? WHERE id=?''',
      [
        rule.name.trim(),
        rule.senderOrChatPattern,
        rule.titlePattern,
        rule.bodyPattern,
        rule.parserKind,
        rule.directionRule,
        rule.accountId,
        rule.categoryId,
        rule.priority,
        rule.enabled ? 1 : 0,
        DateTime.now().toUtc().toIso8601String(),
        rule.id,
      ],
    );
  }

  @override
  Future<void> setNotificationRuleEnabled(String id, bool enabled) async {
    final owned = database.select(
      '''SELECT r.id FROM notification_rules r JOIN notification_sources s
         ON s.id=r.notification_source_id
         WHERE r.id=? AND s.profile_id=? AND r.deleted_at IS NULL''',
      [id, activeProfileId],
    );
    if (owned.isEmpty) throw StateError('Notification rule unavailable');
    database.execute(
      'UPDATE notification_rules SET enabled=?,updated_at=? WHERE id=?',
      [enabled ? 1 : 0, DateTime.now().toUtc().toIso8601String(), id],
    );
  }

  @override
  Future<RulePreviewResult> previewNotificationRule(
    NotificationRule rule,
    NotificationRuleSample sample,
  ) async {
    final source = database.select(
      'SELECT default_account_id,package_name FROM notification_sources WHERE id=? AND profile_id=? AND deleted_at IS NULL',
      [rule.notificationSourceId, activeProfileId],
    );
    if (source.isEmpty || source.single['package_name'] != sample.packageName) {
      return const RulePreviewResult(matched: false, error: 'source_mismatch');
    }
    return NotificationRuleEngine.preview(
      rule: rule,
      sample: sample,
      fallbackAccountId: source.single['default_account_id'] as String?,
    );
  }

  @override
  Future<List<RawNotificationSample>> recentRawNotificationSamples(
    String sourceId, {
    int limit = 30,
  }) async {
    if (limit < 1 || limit > 100) throw ArgumentError.value(limit);
    final owned = query(
      '''SELECT id FROM notification_sources
         WHERE id=? AND profile_id=? AND deleted_at IS NULL''',
      [sourceId, activeProfileId],
    );
    if (owned.isEmpty) throw StateError('Notification source unavailable');
    return query(
          '''SELECT id,notification_source_id,title,body,sender_or_chat,captured_at,parse_status
         FROM raw_notification_events
         WHERE profile_id=? AND notification_source_id=? AND deleted_at IS NULL
         ORDER BY captured_at DESC,id DESC LIMIT ?''',
          [activeProfileId, sourceId, limit],
        )
        .map(
          (row) => RawNotificationSample(
            id: row['id'] as String,
            notificationSourceId: row['notification_source_id'] as String,
            capturedAt: DateTime.parse(row['captured_at'] as String).toUtc(),
            parseStatus: row['parse_status'] as String,
            title: row['title'] as String?,
            body: row['body'] as String?,
            senderOrChat: row['sender_or_chat'] as String?,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<NotificationReprocessSummary> reprocessRawNotifications(
    String sourceId, {
    int limit = 50,
  }) async {
    if (limit < 1 || limit > 100) throw ArgumentError.value(limit);
    final source = query(
      '''SELECT id FROM notification_sources
         WHERE id=? AND profile_id=? AND enabled=1 AND deleted_at IS NULL''',
      [sourceId, activeProfileId],
    );
    if (source.isEmpty) throw StateError('Notification source unavailable');
    final rows = query(
      '''SELECT raw.*,s.default_account_id FROM raw_notification_events raw
         JOIN notification_sources s ON s.id=raw.notification_source_id
         WHERE raw.profile_id=? AND raw.notification_source_id=?
           AND raw.parse_status IN ('captured','parse_failed')
           AND raw.deleted_at IS NULL
         ORDER BY raw.captured_at DESC,raw.id DESC LIMIT ?''',
      [activeProfileId, sourceId, limit],
    );
    var created = 0;
    var noMatch = 0;
    var ambiguous = 0;
    var existing = 0;
    for (final raw in rows) {
      final evidenceBefore = query(
        'SELECT candidate_id FROM candidate_evidence WHERE notification_event_id=?',
        [raw['id']],
      );
      if (evidenceBefore.isNotEmpty) {
        existing++;
        continue;
      }
      final signatures = await _matchingRuleSignatures(raw);
      if (signatures.isEmpty) {
        noMatch++;
        await processRawNotification(raw['id'] as String);
      } else if (signatures.length > 1) {
        ambiguous++;
        await processRawNotification(raw['id'] as String);
      } else {
        final result = await processRawNotification(raw['id'] as String);
        if (result == null) {
          noMatch++;
        } else {
          created++;
        }
      }
    }
    return NotificationReprocessSummary(
      examined: rows.length,
      created: created,
      noMatch: noMatch,
      ambiguous: ambiguous,
      existing: existing,
    );
  }

  Future<Set<String>> _matchingRuleSignatures(Map<String, Object?> raw) async {
    final rules = (await notificationRules(
      raw['notification_source_id'] as String,
    )).where((rule) => rule.enabled);
    final sample = NotificationRuleSample(
      packageName: raw['package_name'] as String,
      capturedAt: DateTime.parse(raw['captured_at'] as String).toUtc(),
      title: raw['title'] as String?,
      body: raw['body'] as String?,
      senderOrChat: raw['sender_or_chat'] as String?,
    );
    final signatures = <String>{};
    for (final rule in rules) {
      final preview = NotificationRuleEngine.preview(
        rule: rule,
        sample: sample,
        fallbackAccountId: raw['default_account_id'] as String?,
      );
      if (preview.matched) {
        signatures.add(
          '${preview.candidateType}|${preview.amountSatang}|${preview.accountId}|${preview.categoryId}',
        );
      }
    }
    return signatures;
  }

  @override
  Future<String?> processRawNotification(String rawEventId) async {
    final already = database.select(
      '''SELECT ce.candidate_id FROM candidate_evidence ce
         JOIN raw_notification_events raw ON raw.id=ce.notification_event_id
         WHERE ce.notification_event_id=? AND raw.profile_id=?''',
      [rawEventId, activeProfileId],
    );
    if (already.isNotEmpty) return already.single['candidate_id'] as String;
    final rows = database.select(
      '''SELECT raw.*,s.default_account_id,s.enabled source_enabled
         FROM raw_notification_events raw JOIN notification_sources s
         ON s.id=raw.notification_source_id
         WHERE raw.id=? AND raw.profile_id=? AND raw.deleted_at IS NULL
           AND s.profile_id=raw.profile_id AND s.deleted_at IS NULL''',
      [rawEventId, activeProfileId],
    );
    if (rows.isEmpty || rows.single['source_enabled'] != 1) return null;
    final raw = rows.single;
    final rules = (await notificationRules(
      raw['notification_source_id'] as String,
    )).where((rule) => rule.enabled).toList();
    final sample = NotificationRuleSample(
      packageName: raw['package_name'] as String,
      capturedAt: DateTime.parse(raw['captured_at'] as String).toUtc(),
      title: raw['title'] as String?,
      body: raw['body'] as String?,
      senderOrChat: raw['sender_or_chat'] as String?,
    );
    final matches = <(NotificationRule, RulePreviewResult)>[];
    for (final rule in rules) {
      final preview = NotificationRuleEngine.preview(
        rule: rule,
        sample: sample,
        fallbackAccountId: raw['default_account_id'] as String?,
      );
      if (preview.matched) matches.add((rule, preview));
    }
    if (matches.isEmpty) {
      database.execute(
        "UPDATE raw_notification_events SET parse_status='parse_failed',matched_rule_id=NULL WHERE id=?",
        [rawEventId],
      );
      return null;
    }
    final signatures = matches
        .map(
          (m) =>
              '${m.$2.candidateType}|${m.$2.amountSatang}|${m.$2.accountId}|${m.$2.categoryId}',
        )
        .toSet();
    if (signatures.length != 1) {
      database.execute(
        "UPDATE raw_notification_events SET parse_status='parse_failed',matched_rule_id=NULL WHERE id=?",
        [rawEventId],
      );
      return null;
    }
    final selected = matches.first;
    final preview = selected.$2;
    late String candidateId;
    _atomic(() {
      final nearby = database.select(
        '''SELECT c.id,raw.captured_at FROM transaction_candidates c
           JOIN candidate_evidence ce ON ce.candidate_id=c.id
           JOIN raw_notification_events raw ON raw.id=ce.notification_event_id
           WHERE c.profile_id=? AND raw.notification_source_id=?
             AND raw.matched_rule_id=? AND c.candidate_type=? AND c.amount_satang=?
             AND c.account_id=? AND COALESCE(c.merchant_or_sender,'')=COALESCE(?,'')
             AND ABS(strftime('%s',raw.captured_at)-strftime('%s',?))<=10
             AND (raw.body=? OR instr(raw.body,?)>0 OR instr(?,raw.body)>0)
             AND c.deleted_at IS NULL LIMIT 1''',
        [
          activeProfileId,
          raw['notification_source_id'],
          selected.$1.id,
          preview.candidateType,
          preview.amountSatang,
          preview.accountId,
          raw['sender_or_chat'],
          raw['captured_at'],
          raw['body'],
          raw['body'],
          raw['body'],
        ],
      );
      candidateId = nearby.isEmpty ? _uuid.v4() : nearby.single['id'] as String;
      final now = DateTime.now().toUtc().toIso8601String();
      if (nearby.isEmpty) {
        database.execute(
          '''INSERT INTO transaction_candidates(
             id,profile_id,account_id,destination_account_id,category_id,
             candidate_type,amount_satang,occurred_at,merchant_or_sender,
             reference_no,confidence,review_status,matched_scheduled_event_id,
             matched_transaction_id,created_at,updated_at)
             VALUES(?,?,?,?,?,?,?,?,?,?,?,'pending_review',NULL,NULL,?,?)''',
          [
            candidateId,
            activeProfileId,
            preview.accountId,
            null,
            preview.categoryId,
            preview.candidateType,
            preview.amountSatang,
            raw['captured_at'],
            raw['sender_or_chat'] ?? raw['title'],
            null,
            .95,
            now,
            now,
          ],
        );
      }
      database.execute(
        '''INSERT OR IGNORE INTO candidate_evidence(
           id,candidate_id,evidence_type,notification_event_id,created_at)
           VALUES(?,?,'notification',?,?)''',
        [_uuid.v4(), candidateId, rawEventId, now],
      );
      database.execute(
        "UPDATE raw_notification_events SET parse_status='parsed',matched_rule_id=? WHERE id=?",
        [selected.$1.id, rawEventId],
      );
    });
    return candidateId;
  }

  @override
  Future<bool> hasCandidateForRawEvent(String rawEventId) async => query(
    '''SELECT ce.candidate_id FROM candidate_evidence ce
           JOIN transaction_candidates c ON c.id=ce.candidate_id
           WHERE ce.notification_event_id=? AND c.profile_id=? AND c.deleted_at IS NULL''',
    [rawEventId, activeProfileId],
  ).isNotEmpty;

  @override
  Future<Map<String, Object?>?> candidateNotificationDetails(String id) async {
    final rows = query(
      '''SELECT c.candidate_type, c.amount_satang, a.name account_name
         FROM transaction_candidates c LEFT JOIN accounts a ON a.id=c.account_id
         WHERE c.id=? AND c.profile_id=? AND c.deleted_at IS NULL''',
      [id, activeProfileId],
    );
    return rows.firstOrNull;
  }

  @override
  Future<CandidateMatchResult> matchCandidate(String id) async {
    final candidates = _matchingCandidates(id: id);
    if (candidates.isEmpty) {
      throw StateError('Pending Candidate unavailable');
    }
    final targets = _matchingTargets(candidates);
    return const CandidateMatchingEngine().match(
      candidates.single,
      transactions: targets.$1,
      scheduledEvents: targets.$2,
    );
  }

  @override
  Future<List<CandidateMatchResult>> matchPendingCandidates() async {
    final candidates = _matchingCandidates();
    if (candidates.isEmpty) return const [];
    final targets = _matchingTargets(candidates);
    return const CandidateMatchingEngine().matchBatch(
      candidates,
      transactions: targets.$1,
      scheduledEvents: targets.$2,
    );
  }

  @override
  Future<TransferCorrelationResult> correlateCandidate(
    String candidateId,
  ) async {
    final results = _correlatePendingCandidatesSync();
    return results
            .where((item) => item.candidateId == candidateId)
            .firstOrNull ??
        TransferCorrelationResult(
          candidateId: candidateId,
          kind: TransferCorrelationKind.noCorrelation,
        );
  }

  @override
  Future<List<TransferCorrelationResult>> correlatePendingCandidates() async =>
      _correlatePendingCandidatesSync();

  @override
  Future<CandidateResolutionResult> confirmCorrelatedTransfer(
    TransferCorrelationResult correlation, {
    bool failAfterTransferOut = false,
    bool failBeforeCandidateUpdates = false,
  }) async {
    late CandidateResolutionResult result;
    _atomic(() {
      final pairedId = correlation.pairedCandidateId;
      if (pairedId == null) throw StateError('ไม่พบคู่รายการโอน');
      final rows = query(
        '''SELECT * FROM transaction_candidates
           WHERE profile_id=? AND id IN (?,?) AND deleted_at IS NULL''',
        [activeProfileId, correlation.candidateId, pairedId],
      );
      if (rows.length != 2) throw StateError('คู่รายการเปลี่ยนไปแล้ว');
      final pending = rows
          .where((row) => row['review_status'] == 'pending_review')
          .length;
      if (pending == 0) {
        final first = _alreadyResolvedCandidate(rows.first);
        final second = _alreadyResolvedCandidate(rows.last);
        if (first == null || second == null) {
          throw StateError('ผลการยืนยันเดิมไม่สมบูรณ์');
        }
        result = CandidateResolutionResult(
          status: first.status,
          transactionId: first.transactionId,
          scheduledEventId: first.scheduledEventId,
          createdFinancialRecord: false,
        );
        return;
      }
      if (pending != 2) throw StateError('คู่รายการถูกดำเนินการไปบางส่วนแล้ว');

      final current = _correlatePendingCandidatesSync()
          .where((item) => item.candidateId == correlation.candidateId)
          .firstOrNull;
      if (current == null ||
          current.pairedCandidateId != pairedId ||
          current.kind != correlation.kind ||
          current.sourceAccountId != correlation.sourceAccountId ||
          current.destinationAccountId != correlation.destinationAccountId ||
          current.amountSatang != correlation.amountSatang ||
          current.transferGroupId != correlation.transferGroupId ||
          current.scheduledEventId != correlation.scheduledEventId) {
        throw StateError('คำแนะนำเปลี่ยนไปแล้ว กรุณารีเฟรช');
      }

      String? groupId;
      var created = false;
      if (current.kind == TransferCorrelationKind.existingTransfer) {
        groupId = current.transferGroupId;
        if (groupId == null ||
            !_validExistingCorrelationTransfer(current, groupId)) {
          throw StateError('รายการโอนที่บันทึกไว้เปลี่ยนไปแล้ว');
        }
      } else if (current.kind == TransferCorrelationKind.scheduledTransfer) {
        final eventId = current.scheduledEventId;
        if (eventId == null) throw StateError('รายการโอนล่วงหน้าเปลี่ยนไปแล้ว');
        groupId = _confirmScheduledTransferSync(
          eventId,
          occurredAt: _correlationOccurredAt(rows),
        );
        created = true;
      } else if (current.kind == TransferCorrelationKind.likelyTransferPair) {
        _validateTransferAccounts(
          current.sourceAccountId!,
          current.destinationAccountId,
        );
        groupId = _uuid.v4();
        final occurredAt = _correlationOccurredAt(rows);
        _insertTransaction(
          accountId: current.sourceAccountId!,
          type: 'transfer_out',
          amount: current.amountSatang,
          transferGroupId: groupId,
          source: 'notification_correlation',
          occurredAt: occurredAt,
        );
        if (failAfterTransferOut) {
          throw StateError('Injected failure after transfer out');
        }
        _insertTransaction(
          accountId: current.destinationAccountId!,
          type: 'transfer_in',
          amount: current.amountSatang,
          transferGroupId: groupId,
          source: 'notification_correlation',
          occurredAt: occurredAt,
        );
        created = true;
      } else {
        throw StateError('คำแนะนำนี้ยังยืนยันเป็นการโอนไม่ได้');
      }
      if (failBeforeCandidateUpdates) {
        throw StateError('Injected failure before candidate updates');
      }
      final status = current.kind == TransferCorrelationKind.existingTransfer
          ? 'matched_existing'
          : 'confirmed_new';
      for (final id in [correlation.candidateId, pairedId]) {
        _finishCandidate(
          id,
          status: status,
          scheduledEventId: current.scheduledEventId,
        );
        _audit(
          'transaction_candidate',
          id,
          'update',
          metadata: {
            'action': 'confirmed_correlated_transfer',
            'pairedCandidateId': id == correlation.candidateId
                ? pairedId
                : correlation.candidateId,
            'transferGroupId': groupId,
            if (current.scheduledEventId != null)
              'scheduledEventId': current.scheduledEventId,
          },
        );
      }
      result = CandidateResolutionResult(
        status: status,
        transferGroupId: groupId,
        scheduledEventId: current.scheduledEventId,
        createdFinancialRecord: created,
      );
    });
    return result;
  }

  @override
  Future<List<CandidateReviewItem>> pendingCandidateReviews() async {
    final candidates = _matchingCandidates();
    if (candidates.isEmpty) return const [];
    final matches = await matchPendingCandidates();
    final matchById = {for (final match in matches) match.candidateId: match};
    final rows = query(
      '''SELECT c.*,a.name account_name,d.name destination_account_name,
                cat.name category_name,
                CASE WHEN EXISTS(
                  SELECT 1 FROM candidate_evidence e
                  WHERE e.candidate_id=c.id AND e.evidence_type='slip'
                ) THEN 'สลิป'
                WHEN EXISTS(
                  SELECT 1 FROM candidate_evidence e
                  JOIN raw_notification_events r ON r.id=e.notification_event_id
                  JOIN notification_sources s ON s.id=r.notification_source_id
                  WHERE e.candidate_id=c.id AND s.source_kind='line'
                ) THEN 'LINE' ELSE 'การแจ้งเตือน' END source_label
         FROM transaction_candidates c
         LEFT JOIN accounts a ON a.id=c.account_id
         LEFT JOIN accounts d ON d.id=c.destination_account_id
         LEFT JOIN categories cat ON cat.id=c.category_id
         WHERE c.profile_id=? AND c.review_status='pending_review'
           AND c.deleted_at IS NULL ORDER BY c.occurred_at DESC,c.id''',
      [activeProfileId],
    );
    return rows
        .map(
          (row) => CandidateReviewItem(
            id: row['id'] as String,
            type: row['candidate_type'] as String,
            amountSatang: row['amount_satang'] as int,
            occurredAt: DateTime.parse(row['occurred_at'] as String).toUtc(),
            sourceLabel: row['source_label'] as String,
            accountId: row['account_id'] as String?,
            accountName: row['account_name'] as String?,
            destinationAccountId: row['destination_account_id'] as String?,
            destinationAccountName: row['destination_account_name'] as String?,
            categoryId: row['category_id'] as String?,
            categoryName: row['category_name'] as String?,
            merchantOrSender: row['merchant_or_sender'] as String?,
            match: matchById[row['id']]!,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<List<CandidateTargetSummary>> candidateTargetSummaries(
    String id,
  ) async {
    final result = await matchCandidate(id);
    return result.alternatives
        .map((alternative) {
          if (alternative.targetType ==
              CandidateMatchTargetType.scheduledEvent) {
            final row = query(
              '''SELECT e.*,a.name account_name FROM scheduled_financial_events e
             JOIN accounts a ON a.id=e.account_id
             WHERE e.id=? AND e.profile_id=? AND e.deleted_at IS NULL''',
              [alternative.targetId, activeProfileId],
            ).single;
            return CandidateTargetSummary(
              id: alternative.targetId,
              targetType: alternative.targetType,
              type: row['event_type'] as String,
              amountSatang: row['amount_satang'] as int,
              occurredAt: DateTime.parse(row['scheduled_at'] as String).toUtc(),
              title: row['title'] as String,
              accountId: row['account_id'] as String,
              accountName: row['account_name'] as String,
              destinationAccountId: row['destination_account_id'] as String?,
              reasons: alternative.reasons,
            );
          }
          final isTransfer =
              alternative.targetType == CandidateMatchTargetType.transferGroup;
          final row = query(
            '''SELECT t.*,a.name account_name,c.name category_name FROM transactions t
           JOIN accounts a ON a.id=t.account_id LEFT JOIN categories c ON c.id=t.category_id
           WHERE ${isTransfer ? 't.transfer_group_id' : 't.id'}=? AND t.profile_id=?
             AND t.status='confirmed' AND t.deleted_at IS NULL
           ORDER BY CASE WHEN t.type='transfer_out' THEN 0 ELSE 1 END LIMIT 1''',
            [alternative.targetId, activeProfileId],
          ).single;
          return CandidateTargetSummary(
            id: alternative.targetId,
            targetType: alternative.targetType,
            type: isTransfer ? 'transfer' : row['type'] as String,
            amountSatang: row['amount_satang'] as int,
            occurredAt: DateTime.parse(row['occurred_at'] as String).toUtc(),
            title: isTransfer
                ? 'โอนระหว่างบัญชี'
                : (row['category_name'] as String?) ??
                      (row['note'] as String?) ??
                      'รายการที่บันทึกแล้ว',
            accountId: row['account_id'] as String,
            accountName: row['account_name'] as String,
            destinationAccountId: isTransfer
                ? query(
                        "SELECT account_id FROM transactions WHERE profile_id=? AND transfer_group_id=? AND type='transfer_in' AND status='confirmed' AND deleted_at IS NULL",
                        [activeProfileId, alternative.targetId],
                      ).single['account_id']
                      as String
                : null,
            reasons: alternative.reasons,
          );
        })
        .toList(growable: false);
  }

  @override
  Future<CandidateResolutionResult> resolveCandidateAsExisting(
    String candidateId,
    CandidateMatchTargetType targetType,
    String targetId, {
    bool failBeforeCandidateUpdate = false,
  }) async {
    late CandidateResolutionResult result;
    _atomic(() {
      final row = _candidateResolutionRow(candidateId);
      final resolved = _alreadyResolvedCandidate(row);
      if (resolved != null) {
        result = resolved;
        return;
      }
      if (targetType == CandidateMatchTargetType.scheduledEvent) {
        throw ArgumentError('Existing target must be a real transaction');
      }
      _requireCurrentAlternative(candidateId, targetType, targetId);
      String? transactionId = targetId;
      if (targetType == CandidateMatchTargetType.transferGroup) {
        final pair = query(
          "SELECT id FROM transactions WHERE profile_id=? AND transfer_group_id=? AND status='confirmed' AND deleted_at IS NULL",
          [activeProfileId, targetId],
        );
        if (pair.length != 2) throw StateError('รายการโอนไม่พร้อมใช้งานแล้ว');
        transactionId = null; // Schema v5 has no transfer-group link column.
      }
      if (failBeforeCandidateUpdate) {
        throw StateError('Injected candidate resolution failure');
      }
      _finishCandidate(
        candidateId,
        status: 'matched_existing',
        transactionId: transactionId,
      );
      _audit(
        'transaction_candidate',
        candidateId,
        'update',
        metadata: {
          'action': 'matched_existing',
          if (targetType == CandidateMatchTargetType.transferGroup)
            'transferGroupId': targetId,
        },
      );
      result = CandidateResolutionResult(
        status: 'matched_existing',
        transactionId: transactionId,
        transferGroupId: targetType == CandidateMatchTargetType.transferGroup
            ? targetId
            : null,
      );
    });
    return result;
  }

  @override
  Future<CandidateResolutionResult> resolveCandidateAsScheduled(
    String candidateId,
    String scheduledEventId, {
    String? destinationAccountId,
    bool failBeforeCandidateUpdate = false,
  }) async {
    late CandidateResolutionResult result;
    _atomic(() {
      final row = _candidateResolutionRow(candidateId);
      final resolved = _alreadyResolvedCandidate(row);
      if (resolved != null) {
        result = resolved;
        return;
      }
      final events = query(
        "SELECT * FROM scheduled_financial_events WHERE id=? AND profile_id=? AND stored_status='scheduled' AND deleted_at IS NULL",
        [scheduledEventId, activeProfileId],
      );
      if (events.isEmpty) {
        throw StateError('รายการในปฏิทินเปลี่ยนไปแล้ว กรุณารีเฟรช');
      }
      final event = events.single;
      _validateCandidateScheduledCompatibility(
        row,
        event,
        destinationAccountId,
      );
      final isTransfer = event['event_type'] == 'transfer';
      final link = isTransfer
          ? _confirmScheduledTransferSync(
              scheduledEventId,
              occurredAt: DateTime.parse(row['occurred_at'] as String),
            )
          : _confirmScheduledEventSync(
              scheduledEventId,
              occurredAt: DateTime.parse(row['occurred_at'] as String),
            );
      if (failBeforeCandidateUpdate) {
        throw StateError('Injected candidate resolution failure');
      }
      _finishCandidate(
        candidateId,
        status: 'confirmed_new',
        transactionId: isTransfer ? null : link,
        scheduledEventId: scheduledEventId,
        destinationAccountId: destinationAccountId,
      );
      result = CandidateResolutionResult(
        status: 'confirmed_new',
        transactionId: isTransfer ? null : link,
        transferGroupId: isTransfer ? link : null,
        scheduledEventId: scheduledEventId,
        createdFinancialRecord: true,
      );
    });
    return result;
  }

  @override
  Future<CandidateResolutionResult> reconcileCandidateExistingAndScheduled(
    String candidateId,
    CandidateMatchTargetType existingTargetType,
    String existingTargetId,
    String scheduledEventId, {
    bool failAfterScheduledLink = false,
    bool failAfterCommitmentLink = false,
  }) async {
    late CandidateResolutionResult result;
    _atomic(() {
      final candidate = _candidateResolutionRow(candidateId);
      if (candidate['review_status'] != 'pending_review') {
        result = _validateThreeWayRetry(
          candidate,
          existingTargetType,
          existingTargetId,
          scheduledEventId,
        );
        return;
      }
      if (existingTargetType == CandidateMatchTargetType.scheduledEvent) {
        throw ArgumentError('ต้องเลือกรายการเงินจริงที่บันทึกแล้ว');
      }
      final eventRows = query(
        '''SELECT * FROM scheduled_financial_events
           WHERE id=? AND profile_id=? AND deleted_at IS NULL''',
        [scheduledEventId, activeProfileId],
      );
      if (eventRows.isEmpty) {
        throw StateError('ไม่พบรายการในปฏิทินของโปรไฟล์นี้');
      }
      final eventRow = eventRows.single;
      if (eventRow['stored_status'] != 'scheduled') {
        throw StateError('รายการในปฏิทินถูกดำเนินการไปแล้ว');
      }
      final candidateType = candidate['candidate_type'] as String;
      if (candidateType == 'transfer') {
        if (existingTargetType != CandidateMatchTargetType.transferGroup) {
          throw StateError('ต้องเลือกรายการโอนที่ครบทั้งสองฝั่ง');
        }
        _reconcileExistingTransfer(
          candidate,
          eventRow,
          existingTargetId,
          scheduledEventId,
        );
      } else {
        if (existingTargetType != CandidateMatchTargetType.transaction) {
          throw StateError('ประเภทรายการจริงไม่ตรงกัน');
        }
        final transactionRows = query(
          '''SELECT * FROM transactions WHERE id=? AND profile_id=?
             AND status='confirmed' AND deleted_at IS NULL''',
          [existingTargetId, activeProfileId],
        );
        if (transactionRows.isEmpty) {
          throw StateError('รายการเงินจริงถูกลบหรือไม่พร้อมใช้งานแล้ว');
        }
        final transaction = transactionRows.single;
        _validateThreeWayNonTransfer(candidate, transaction, eventRow);
        final otherLinks = query(
          '''SELECT id FROM scheduled_financial_events
             WHERE profile_id=? AND linked_transaction_id=? AND id<>?
               AND deleted_at IS NULL''',
          [activeProfileId, existingTargetId, scheduledEventId],
        );
        if (otherLinks.isNotEmpty) {
          throw StateError('รายการเงินจริงนี้เชื่อมกับรายการในปฏิทินอื่นแล้ว');
        }
        final occurrenceConflicts = query(
          '''SELECT id FROM commitment_occurrences
             WHERE profile_id=? AND linked_transaction_id=?
               AND deleted_at IS NULL AND (? IS NULL OR id<>?)''',
          [
            activeProfileId,
            existingTargetId,
            eventRow['origin_type'] == 'commitment_occurrence'
                ? eventRow['origin_id']
                : null,
            eventRow['origin_id'],
          ],
        );
        if (occurrenceConflicts.isNotEmpty) {
          throw StateError('รายการเงินจริงนี้เชื่อมกับงวดภาระอื่นแล้ว');
        }
        if (eventRow['origin_type'] == 'commitment_occurrence') {
          _reconcileExistingCommitmentPayment(
            ScheduledFinancialEvent.fromRow(eventRow),
            existingTargetId,
          );
          if (failAfterCommitmentLink) {
            throw StateError('Injected failure after commitment link');
          }
        }
        final now = DateTime.now().toUtc().toIso8601String();
        database.execute(
          '''UPDATE scheduled_financial_events
             SET stored_status='fulfilled',linked_transaction_id=?,
                 linked_transfer_group_id=NULL,updated_at=?
             WHERE id=? AND profile_id=? AND stored_status='scheduled'
               AND linked_transaction_id IS NULL AND linked_transfer_group_id IS NULL
               AND deleted_at IS NULL''',
          [existingTargetId, now, scheduledEventId, activeProfileId],
        );
        if (database.updatedRows != 1) {
          throw StateError('เชื่อมรายการในปฏิทินไม่สำเร็จ กรุณารีเฟรช');
        }
      }
      if (failAfterScheduledLink) {
        throw StateError('Injected failure after scheduled link');
      }
      _finishCandidate(
        candidateId,
        status: 'matched_existing',
        transactionId: candidateType == 'transfer' ? null : existingTargetId,
        scheduledEventId: scheduledEventId,
      );
      _audit(
        'transaction_candidate',
        candidateId,
        'update',
        metadata: {
          'action': 'reconcile_existing_and_scheduled',
          if (candidateType == 'transfer')
            'transferGroupId': existingTargetId
          else
            'transactionId': existingTargetId,
          'scheduledEventId': scheduledEventId,
        },
      );
      result = CandidateResolutionResult(
        status: 'matched_existing',
        transactionId: candidateType == 'transfer' ? null : existingTargetId,
        transferGroupId: candidateType == 'transfer' ? existingTargetId : null,
        scheduledEventId: scheduledEventId,
      );
    });
    return result;
  }

  void _validateThreeWayNonTransfer(
    Map<String, Object?> candidate,
    Map<String, Object?> transaction,
    Map<String, Object?> event,
  ) {
    final type = candidate['candidate_type'];
    final amount = candidate['amount_satang'];
    final account = candidate['account_id'];
    if (event['event_type'] != type ||
        transaction['type'] != type ||
        event['amount_satang'] != amount ||
        transaction['amount_satang'] != amount ||
        transaction['account_id'] != event['account_id'] ||
        (account != null && transaction['account_id'] != account)) {
      throw StateError('ยอด ประเภท หรือบัญชีของทั้งสามรายการไม่ตรงกัน');
    }
  }

  void _reconcileExistingTransfer(
    Map<String, Object?> candidate,
    Map<String, Object?> event,
    String groupId,
    String eventId,
  ) {
    if (event['event_type'] != 'transfer' ||
        event['amount_satang'] != candidate['amount_satang'] ||
        (candidate['account_id'] != null &&
            candidate['account_id'] != event['account_id']) ||
        (candidate['destination_account_id'] != null &&
            candidate['destination_account_id'] !=
                event['destination_account_id'])) {
      throw StateError('รายการโอนทั้งสามรายการไม่ตรงกัน');
    }
    final pair = query(
      '''SELECT account_id,type,amount_satang FROM transactions
         WHERE profile_id=? AND transfer_group_id=? AND status='confirmed'
           AND deleted_at IS NULL''',
      [activeProfileId, groupId],
    );
    final valid =
        pair.length == 2 &&
        pair.any(
          (row) =>
              row['type'] == 'transfer_out' &&
              row['account_id'] == event['account_id'] &&
              row['amount_satang'] == event['amount_satang'],
        ) &&
        pair.any(
          (row) =>
              row['type'] == 'transfer_in' &&
              row['account_id'] == event['destination_account_id'] &&
              row['amount_satang'] == event['amount_satang'],
        );
    if (!valid) throw StateError('รายการโอนจริงไม่ครบหรือบัญชีไม่ตรงกัน');
    final conflicts = query(
      '''SELECT id FROM scheduled_financial_events
         WHERE profile_id=? AND linked_transfer_group_id=? AND id<>?
           AND deleted_at IS NULL''',
      [activeProfileId, groupId, eventId],
    );
    if (conflicts.isNotEmpty) {
      throw StateError('รายการโอนนี้เชื่อมกับปฏิทินอื่นแล้ว');
    }
    final now = DateTime.now().toUtc().toIso8601String();
    database.execute(
      '''UPDATE scheduled_financial_events
         SET stored_status='fulfilled',linked_transaction_id=NULL,
             linked_transfer_group_id=?,updated_at=?
         WHERE id=? AND profile_id=? AND stored_status='scheduled'
           AND linked_transaction_id IS NULL AND linked_transfer_group_id IS NULL
           AND deleted_at IS NULL''',
      [groupId, now, eventId, activeProfileId],
    );
    if (database.updatedRows != 1) {
      throw StateError('เชื่อมรายการโอนกับปฏิทินไม่สำเร็จ');
    }
  }

  void _reconcileExistingCommitmentPayment(
    ScheduledFinancialEvent event,
    String transactionId,
  ) {
    if (event.originId == null) throw StateError('ไม่พบงวดภาระที่เกี่ยวข้อง');
    final rows = query(
      '''SELECT o.linked_transaction_id,c.id commitment_id
         FROM commitment_occurrences o
         JOIN commitments c ON c.legacy_installment_id=o.installment_id
           AND c.profile_id=o.profile_id
         WHERE o.id=? AND o.profile_id=? AND o.is_skipped=0
           AND o.deleted_at IS NULL AND c.status='active' AND c.deleted_at IS NULL''',
      [event.originId, activeProfileId],
    );
    if (rows.isEmpty) throw StateError('งวดภาระไม่พร้อมรับชำระ');
    final row = rows.single;
    final linked = row['linked_transaction_id'] as String?;
    if (linked != null && linked != transactionId) {
      throw StateError('งวดภาระนี้เชื่อมกับรายการเงินจริงอื่นแล้ว');
    }
    _validateExistingCommitmentTransaction(event, transactionId);
    if (linked == null) {
      database.execute(
        '''UPDATE commitment_occurrences SET linked_transaction_id=?,updated_at=?
           WHERE id=? AND profile_id=? AND linked_transaction_id IS NULL
             AND is_skipped=0 AND deleted_at IS NULL''',
        [
          transactionId,
          DateTime.now().toUtc().toIso8601String(),
          event.originId,
          activeProfileId,
        ],
      );
      if (database.updatedRows != 1) {
        throw StateError('เชื่อมรายการเงินจริงกับงวดภาระไม่สำเร็จ');
      }
    }
    final payments = query(
      '''SELECT commitment_id FROM commitment_payments
         WHERE transaction_id=? AND profile_id=? AND deleted_at IS NULL''',
      [transactionId, activeProfileId],
    );
    if (payments.isEmpty) {
      final now = DateTime.now().toUtc().toIso8601String();
      database.execute(
        '''INSERT INTO commitment_payments(
           id,commitment_id,transaction_id,created_at,updated_at,profile_id)
           VALUES(?,?,?,?,?,?)''',
        [
          _uuid.v4(),
          row['commitment_id'],
          transactionId,
          now,
          now,
          activeProfileId,
        ],
      );
    } else if (payments.single['commitment_id'] != row['commitment_id']) {
      throw StateError('รายการเงินจริงนี้เป็นการชำระภาระอื่นแล้ว');
    }
  }

  CandidateResolutionResult _validateThreeWayRetry(
    Map<String, Object?> candidate,
    CandidateMatchTargetType targetType,
    String targetId,
    String eventId,
  ) {
    if (candidate['review_status'] != 'matched_existing' ||
        candidate['matched_scheduled_event_id'] != eventId) {
      throw StateError('รายการนี้ถูกดำเนินการด้วยวิธีอื่นแล้ว');
    }
    final event = query(
      '''SELECT * FROM scheduled_financial_events
         WHERE id=? AND profile_id=? AND stored_status='fulfilled'
           AND deleted_at IS NULL''',
      [eventId, activeProfileId],
    );
    if (event.isEmpty) throw StateError('ผลการเชื่อมเดิมไม่สมบูรณ์');
    final isTransfer = targetType == CandidateMatchTargetType.transferGroup;
    final correct = isTransfer
        ? event.single['linked_transfer_group_id'] == targetId &&
              candidate['matched_transaction_id'] == null
        : event.single['linked_transaction_id'] == targetId &&
              candidate['matched_transaction_id'] == targetId;
    if (!correct) throw StateError('รายการนี้เชื่อมกับเป้าหมายอื่นแล้ว');
    return CandidateResolutionResult(
      status: 'matched_existing',
      transactionId: isTransfer ? null : targetId,
      transferGroupId: isTransfer ? targetId : null,
      scheduledEventId: eventId,
    );
  }

  @override
  Future<CandidateResolutionResult> createTransactionFromCandidate(
    String candidateId, {
    String? categoryId,
    String? destinationAccountId,
    bool failBeforeCandidateUpdate = false,
  }) async {
    late CandidateResolutionResult result;
    _atomic(() {
      final row = _candidateResolutionRow(candidateId);
      final resolved = _alreadyResolvedCandidate(row);
      if (resolved != null) {
        result = resolved;
        return;
      }
      final type = row['candidate_type'] as String;
      final accountId = row['account_id'] as String?;
      if (accountId == null) throw StateError('กรุณาเลือกบัญชีก่อนสร้างรายการ');
      final occurredAt = DateTime.parse(row['occurred_at'] as String);
      final amount = row['amount_satang'] as int;
      final effectiveCategory = categoryId ?? row['category_id'] as String?;
      String? transactionId;
      String? transferGroupId;
      if (type == 'transfer') {
        final destination =
            destinationAccountId ?? row['destination_account_id'] as String?;
        _validateTransferAccounts(accountId, destination);
        transferGroupId = _uuid.v4();
        _insertTransaction(
          accountId: accountId,
          type: 'transfer_out',
          amount: amount,
          transferGroupId: transferGroupId,
          source: 'notification_candidate',
          occurredAt: occurredAt,
        );
        _insertTransaction(
          accountId: destination!,
          type: 'transfer_in',
          amount: amount,
          transferGroupId: transferGroupId,
          source: 'notification_candidate',
          occurredAt: occurredAt,
        );
      } else {
        _validateCandidateCategory(type, effectiveCategory);
        transactionId = _insertTransaction(
          accountId: accountId,
          type: type,
          amount: amount,
          source: 'notification_candidate',
          categoryId: effectiveCategory,
          note: row['merchant_or_sender'] as String?,
          occurredAt: occurredAt,
        );
      }
      if (failBeforeCandidateUpdate) {
        throw StateError('Injected candidate resolution failure');
      }
      _finishCandidate(
        candidateId,
        status: 'confirmed_new',
        transactionId: transactionId,
        destinationAccountId: destinationAccountId,
        categoryId: categoryId,
      );
      _audit(
        'transaction_candidate',
        candidateId,
        'update',
        metadata: {
          'action': 'confirmed_new',
          ...?transferGroupId == null
              ? null
              : {'transferGroupId': transferGroupId},
        },
      );
      result = CandidateResolutionResult(
        status: 'confirmed_new',
        transactionId: transactionId,
        transferGroupId: transferGroupId,
        createdFinancialRecord: true,
      );
    });
    return result;
  }

  @override
  Future<CandidateResolutionResult> ignoreCandidate(String candidateId) async {
    late CandidateResolutionResult result;
    _atomic(() {
      final row = _candidateResolutionRow(candidateId);
      final resolved = _alreadyResolvedCandidate(row);
      if (resolved != null) {
        result = resolved;
        return;
      }
      _finishCandidate(candidateId, status: 'ignored');
      _audit(
        'transaction_candidate',
        candidateId,
        'update',
        metadata: {'action': 'ignored'},
      );
      result = const CandidateResolutionResult(status: 'ignored');
    });
    return result;
  }

  Map<String, Object?> _candidateResolutionRow(String id) {
    final rows = query(
      'SELECT * FROM transaction_candidates WHERE id=? AND profile_id=? AND deleted_at IS NULL',
      [id, activeProfileId],
    );
    if (rows.isEmpty) throw StateError('ไม่พบรายการรอตรวจในโปรไฟล์นี้');
    return rows.single;
  }

  CandidateResolutionResult? _alreadyResolvedCandidate(
    Map<String, Object?> row,
  ) {
    final status = row['review_status'] as String;
    if (status == 'pending_review') return null;
    if (const {
      'matched_existing',
      'confirmed_new',
      'ignored',
    }.contains(status)) {
      return CandidateResolutionResult(
        status: status,
        transactionId: row['matched_transaction_id'] as String?,
        scheduledEventId: row['matched_scheduled_event_id'] as String?,
        createdFinancialRecord: status == 'confirmed_new',
      );
    }
    throw StateError('รายการนี้ถูกดำเนินการไปแล้ว');
  }

  void _requireCurrentAlternative(
    String candidateId,
    CandidateMatchTargetType type,
    String targetId,
  ) {
    final candidates = _matchingCandidates(id: candidateId);
    if (candidates.isEmpty) throw StateError('รายการนี้ถูกดำเนินการไปแล้ว');
    final targets = _matchingTargets(candidates);
    final match = const CandidateMatchingEngine().match(
      candidates.single,
      transactions: targets.$1,
      scheduledEvents: targets.$2,
    );
    if (!match.alternatives.any(
      (a) => a.targetType == type && a.targetId == targetId,
    )) {
      throw StateError('รายการที่เลือกไม่ตรงหรือเปลี่ยนไปแล้ว กรุณารีเฟรช');
    }
  }

  void _validateCandidateScheduledCompatibility(
    Map<String, Object?> candidate,
    Map<String, Object?> event,
    String? selectedDestination,
  ) {
    if (candidate['candidate_type'] != event['event_type'] ||
        candidate['amount_satang'] != event['amount_satang'] ||
        (candidate['account_id'] != null &&
            candidate['account_id'] != event['account_id'])) {
      throw StateError('รายการในปฏิทินไม่ตรงกับรายการรอตรวจ');
    }
    final distance = DateTime.parse(
      candidate['occurred_at'] as String,
    ).difference(DateTime.parse(event['scheduled_at'] as String)).abs();
    if (distance > CandidateMatchingPolicy.scheduledEventWindow) {
      throw StateError('เวลาของรายการอยู่นอกช่วงที่ยืนยันได้');
    }
    if (event['event_type'] == 'transfer') {
      final destination =
          selectedDestination ?? candidate['destination_account_id'] as String?;
      if (destination == null) throw StateError('กรุณาเลือกบัญชีปลายทาง');
      if (destination != event['destination_account_id']) {
        throw StateError('บัญชีปลายทางไม่ตรงกับรายการในปฏิทิน');
      }
    }
  }

  void _validateCandidateCategory(String type, String? categoryId) {
    if (categoryId == null) {
      throw StateError('กรุณาเลือกหมวดหมู่ก่อนสร้างรายการ');
    }
    final rows = query(
      'SELECT category_type FROM categories WHERE id=? AND profile_id=? AND archived_at IS NULL AND deleted_at IS NULL',
      [categoryId, activeProfileId],
    );
    final expected = type == 'income' ? 'income' : 'expense';
    if (rows.isEmpty || rows.single['category_type'] != expected) {
      throw StateError('หมวดหมู่ไม่พร้อมใช้หรือไม่ตรงกับประเภทรายการ');
    }
  }

  void _validateTransferAccounts(String from, String? to) {
    if (to == null) throw StateError('กรุณาเลือกบัญชีปลายทาง');
    if (from == to) {
      throw StateError('บัญชีต้นทางและปลายทางต้องไม่ใช่บัญชีเดียวกัน');
    }
    final count =
        query(
              'SELECT COUNT(*) count FROM accounts WHERE profile_id=? AND id IN (?,?) AND is_active=1 AND deleted_at IS NULL',
              [activeProfileId, from, to],
            ).single['count']
            as int;
    if (count != 2) throw StateError('บัญชีโอนไม่พร้อมใช้งาน');
  }

  void _finishCandidate(
    String id, {
    required String status,
    String? transactionId,
    String? scheduledEventId,
    String? destinationAccountId,
    String? categoryId,
  }) {
    final now = DateTime.now().toUtc().toIso8601String();
    database.execute(
      '''UPDATE transaction_candidates SET review_status=?,matched_transaction_id=?,
         matched_scheduled_event_id=?,destination_account_id=COALESCE(?,destination_account_id),
         category_id=COALESCE(?,category_id),resolved_at=?,updated_at=?
         WHERE id=? AND profile_id=? AND review_status='pending_review' AND deleted_at IS NULL''',
      [
        status,
        transactionId,
        scheduledEventId,
        destinationAccountId,
        categoryId,
        now,
        now,
        id,
        activeProfileId,
      ],
    );
    if (database.updatedRows != 1) {
      throw StateError('รายการนี้ถูกดำเนินการไปแล้ว');
    }
  }

  List<TransferCorrelationResult> _correlatePendingCandidatesSync() {
    final matchCandidates = _matchingCandidates();
    if (matchCandidates.isEmpty) return const [];
    final input = matchCandidates
        .map(
          (item) => TransferCorrelationCandidate(
            id: item.id,
            profileId: item.profileId,
            type: item.type,
            amountSatang: item.amountSatang,
            occurredAt: item.occurredAt,
            pending: true,
            accountId: item.accountId,
            referenceNo: item.referenceNo,
          ),
        )
        .toList(growable: false);
    final raw = const TransferCorrelationEngine().correlate(input);
    final byId = {for (final item in matchCandidates) item.id: item};
    final t15Targets = _matchingTargets(matchCandidates);
    final t15 = {
      for (final item in matchCandidates)
        item.id: const CandidateMatchingEngine().match(
          item,
          transactions: t15Targets.$1,
          scheduledEvents: t15Targets.$2,
        ),
    };
    final decorated = <String, TransferCorrelationResult>{};
    for (final item in raw) {
      if (decorated.containsKey(item.candidateId)) continue;
      final pairedId = item.pairedCandidateId;
      if (pairedId == null ||
          item.kind != TransferCorrelationKind.likelyTransferPair) {
        decorated[item.candidateId] = item;
        continue;
      }
      final pair = byId[pairedId];
      final candidate = byId[item.candidateId];
      if (pair == null || candidate == null) {
        decorated[item.candidateId] = item;
        continue;
      }
      final outgoing = candidate.type == 'expense' ? candidate : pair;
      final incoming = candidate.type == 'income' ? candidate : pair;
      final existingGroups = _matchingExistingTransferGroups(
        outgoing,
        incoming,
      );
      final scheduledIds = _matchingScheduledTransfers(outgoing, incoming);
      TransferCorrelationResult selected;
      if (existingGroups.length > 1 || scheduledIds.length > 1) {
        selected = _correlationPairResult(
          item,
          TransferCorrelationKind.ambiguous,
          reasons: const ['multiple_financial_targets'],
        );
      } else if (existingGroups.length == 1) {
        selected = _correlationPairResult(
          item,
          TransferCorrelationKind.existingTransfer,
          transferGroupId: existingGroups.single,
          reasons: const ['existing_transfer_pair'],
        );
      } else if (scheduledIds.length == 1) {
        selected = _correlationPairResult(
          item,
          TransferCorrelationKind.scheduledTransfer,
          scheduledEventId: scheduledIds.single,
          reasons: const ['scheduled_transfer_match'],
        );
      } else {
        final candidateT15 = t15[candidate.id]!;
        final pairT15 = t15[pair.id]!;
        final hasStrongerT15 = {candidateT15.kind, pairT15.kind}.any(
          (kind) =>
              kind == CandidateMatchKind.existingTransactionMatch ||
              kind == CandidateMatchKind.scheduledMatch ||
              kind == CandidateMatchKind.ambiguous,
        );
        selected = hasStrongerT15
            ? _correlationPairResult(
                item,
                TransferCorrelationKind.noCorrelation,
                reasons: const ['stronger_t15_match'],
              )
            : item;
      }
      decorated[item.candidateId] = selected;
      decorated[pairedId] = TransferCorrelationResult(
        candidateId: pairedId,
        pairedCandidateId: item.candidateId,
        kind: selected.kind,
        sourceAccountId: selected.sourceAccountId,
        destinationAccountId: selected.destinationAccountId,
        amountSatang: selected.amountSatang,
        timeDelta: selected.timeDelta,
        reasonCodes: selected.reasonCodes,
        transferGroupId: selected.transferGroupId,
        scheduledEventId: selected.scheduledEventId,
      );
    }
    return raw
        .map((item) => decorated[item.candidateId] ?? item)
        .toList(growable: false);
  }

  TransferCorrelationResult _correlationPairResult(
    TransferCorrelationResult base,
    TransferCorrelationKind kind, {
    required List<String> reasons,
    String? transferGroupId,
    String? scheduledEventId,
  }) => TransferCorrelationResult(
    candidateId: base.candidateId,
    pairedCandidateId: base.pairedCandidateId,
    kind: kind,
    sourceAccountId: base.sourceAccountId,
    destinationAccountId: base.destinationAccountId,
    amountSatang: base.amountSatang,
    timeDelta: base.timeDelta,
    reasonCodes: [...reasons, ...base.reasonCodes],
    transferGroupId: transferGroupId,
    scheduledEventId: scheduledEventId,
  );

  List<String> _matchingExistingTransferGroups(
    MatchCandidate outgoing,
    MatchCandidate incoming,
  ) {
    final from = outgoing.occurredAt
        .subtract(TransferCorrelationPolicy.window)
        .toIso8601String();
    final to = outgoing.occurredAt
        .add(TransferCorrelationPolicy.window)
        .toIso8601String();
    final rows = query(
      '''SELECT transfer_group_id,account_id,type,amount_satang,occurred_at
         FROM transactions WHERE profile_id=? AND transfer_group_id IS NOT NULL
           AND status='confirmed' AND deleted_at IS NULL AND occurred_at BETWEEN ? AND ?
         ORDER BY occurred_at,id''',
      [activeProfileId, from, to],
    );
    final groups = <String, List<Map<String, Object?>>>{};
    for (final row in rows) {
      groups.putIfAbsent(row['transfer_group_id'] as String, () => []).add(row);
    }
    return groups.entries
        .where((entry) {
          final pair = entry.value;
          return pair.length == 2 &&
              pair.any(
                (row) =>
                    row['type'] == 'transfer_out' &&
                    row['account_id'] == outgoing.accountId &&
                    row['amount_satang'] == outgoing.amountSatang &&
                    DateTime.parse(
                          row['occurred_at'] as String,
                        ).difference(outgoing.occurredAt).abs() <=
                        TransferCorrelationPolicy.window,
              ) &&
              pair.any(
                (row) =>
                    row['type'] == 'transfer_in' &&
                    row['account_id'] == incoming.accountId &&
                    row['amount_satang'] == incoming.amountSatang &&
                    DateTime.parse(
                          row['occurred_at'] as String,
                        ).difference(incoming.occurredAt).abs() <=
                        TransferCorrelationPolicy.window,
              );
        })
        .map((entry) => entry.key)
        .toList(growable: false);
  }

  List<String> _matchingScheduledTransfers(
    MatchCandidate outgoing,
    MatchCandidate incoming,
  ) => query(
    '''SELECT id FROM scheduled_financial_events
       WHERE profile_id=? AND event_type='transfer' AND stored_status='scheduled'
         AND account_id=? AND destination_account_id=? AND amount_satang=?
         AND deleted_at IS NULL AND scheduled_at BETWEEN ? AND ?
       ORDER BY scheduled_at,id''',
    [
      activeProfileId,
      outgoing.accountId,
      incoming.accountId,
      outgoing.amountSatang,
      outgoing.occurredAt
          .subtract(CandidateMatchingPolicy.scheduledEventWindow)
          .toIso8601String(),
      outgoing.occurredAt
          .add(CandidateMatchingPolicy.scheduledEventWindow)
          .toIso8601String(),
    ],
  ).map((row) => row['id'] as String).toList(growable: false);

  bool _validExistingCorrelationTransfer(
    TransferCorrelationResult correlation,
    String groupId,
  ) {
    final pair = query(
      '''SELECT account_id,type,amount_satang FROM transactions
         WHERE profile_id=? AND transfer_group_id=? AND status='confirmed'
           AND deleted_at IS NULL''',
      [activeProfileId, groupId],
    );
    return pair.length == 2 &&
        pair.any(
          (row) =>
              row['type'] == 'transfer_out' &&
              row['account_id'] == correlation.sourceAccountId &&
              row['amount_satang'] == correlation.amountSatang,
        ) &&
        pair.any(
          (row) =>
              row['type'] == 'transfer_in' &&
              row['account_id'] == correlation.destinationAccountId &&
              row['amount_satang'] == correlation.amountSatang,
        );
  }

  DateTime _correlationOccurredAt(List<Map<String, Object?>> rows) {
    final values =
        rows
            .map((row) => DateTime.parse(row['occurred_at'] as String).toUtc())
            .toList()
          ..sort();
    return DateTime.fromMillisecondsSinceEpoch(
      (values.first.millisecondsSinceEpoch +
              values.last.millisecondsSinceEpoch) ~/
          2,
      isUtc: true,
    );
  }

  List<MatchCandidate> _matchingCandidates({String? id}) => database
      .select(
        '''SELECT * FROM transaction_candidates
           WHERE profile_id=? AND review_status='pending_review'
             AND deleted_at IS NULL ${id == null ? '' : 'AND id=?'}
           ORDER BY occurred_at,id''',
        id == null ? [activeProfileId] : [activeProfileId, id],
      )
      .map(
        (row) => MatchCandidate(
          id: row['id'] as String,
          profileId: row['profile_id'] as String,
          type: row['candidate_type'] as String,
          amountSatang: row['amount_satang'] as int,
          occurredAt: DateTime.parse(row['occurred_at'] as String).toUtc(),
          accountId: row['account_id'] as String?,
          destinationAccountId: row['destination_account_id'] as String?,
          categoryId: row['category_id'] as String?,
          merchantOrSender: row['merchant_or_sender'] as String?,
          referenceNo: row['reference_no'] as String?,
        ),
      )
      .toList(growable: false);

  (List<MatchTransactionTarget>, List<MatchScheduledTarget>) _matchingTargets(
    List<MatchCandidate> candidates,
  ) {
    final first = candidates.first.occurredAt;
    var minimum = first;
    var maximum = first;
    for (final candidate in candidates.skip(1)) {
      if (candidate.occurredAt.isBefore(minimum)) {
        minimum = candidate.occurredAt;
      }
      if (candidate.occurredAt.isAfter(maximum)) maximum = candidate.occurredAt;
    }
    final from = minimum
        .subtract(CandidateMatchingPolicy.scheduledEventWindow)
        .toIso8601String();
    final to = maximum
        .add(CandidateMatchingPolicy.scheduledEventWindow)
        .toIso8601String();
    final rows = database.select(
      '''SELECT t.*,
         (SELECT sr.reference_no FROM statement_rows sr
          WHERE sr.matched_transaction_id=t.id OR sr.created_transaction_id=t.id
          ORDER BY sr.row_index LIMIT 1) reference_no,
         (SELECT sr.description_raw FROM statement_rows sr
          WHERE sr.matched_transaction_id=t.id OR sr.created_transaction_id=t.id
          ORDER BY sr.row_index LIMIT 1) statement_description
         FROM transactions t
         WHERE t.profile_id=? AND t.status='confirmed' AND t.deleted_at IS NULL
           AND t.occurred_at BETWEEN ? AND ?
         ORDER BY t.occurred_at,t.id''',
      [activeProfileId, from, to],
    );
    final transactionTargets = <MatchTransactionTarget>[];
    final transferRows = <String, List<Row>>{};
    for (final row in rows) {
      final type = row['type'] as String;
      final group = row['transfer_group_id'] as String?;
      if (group != null && (type == 'transfer_out' || type == 'transfer_in')) {
        transferRows.putIfAbsent(group, () => []).add(row);
      } else if (const {'income', 'expense', 'refund'}.contains(type)) {
        transactionTargets.add(
          MatchTransactionTarget(
            id: row['id'] as String,
            profileId: row['profile_id'] as String,
            type: type,
            amountSatang: row['amount_satang'] as int,
            occurredAt: DateTime.parse(row['occurred_at'] as String).toUtc(),
            accountId: row['account_id'] as String,
            categoryId: row['category_id'] as String?,
            referenceNo: row['reference_no'] as String?,
            description:
                row['statement_description'] as String? ??
                row['note'] as String?,
          ),
        );
      }
    }
    for (final entry in transferRows.entries) {
      final outgoing = entry.value
          .where((row) => row['type'] == 'transfer_out')
          .toList();
      final incoming = entry.value
          .where((row) => row['type'] == 'transfer_in')
          .toList();
      if (outgoing.length != 1 ||
          incoming.length != 1 ||
          outgoing.single['amount_satang'] !=
              incoming.single['amount_satang']) {
        continue;
      }
      final source = outgoing.single;
      final destination = incoming.single;
      transactionTargets.add(
        MatchTransactionTarget(
          id: entry.key,
          profileId: source['profile_id'] as String,
          type: 'transfer',
          amountSatang: source['amount_satang'] as int,
          occurredAt: DateTime.parse(source['occurred_at'] as String).toUtc(),
          accountId: source['account_id'] as String,
          destinationAccountId: destination['account_id'] as String,
          description: source['note'] as String?,
          isTransfer: true,
        ),
      );
    }
    final scheduledTargets = database
        .select(
          '''SELECT * FROM scheduled_financial_events
             WHERE profile_id=? AND stored_status='scheduled'
               AND deleted_at IS NULL
               AND COALESCE(due_at,scheduled_at) BETWEEN ? AND ?
             ORDER BY COALESCE(due_at,scheduled_at),id''',
          [activeProfileId, from, to],
        )
        .map(
          (row) => MatchScheduledTarget(
            id: row['id'] as String,
            profileId: row['profile_id'] as String,
            type: row['event_type'] as String,
            amountSatang: row['amount_satang'] as int,
            scheduledAt: DateTime.parse(
              (row['due_at'] ?? row['scheduled_at']) as String,
            ).toUtc(),
            accountId: row['account_id'] as String,
            destinationAccountId: row['destination_account_id'] as String?,
            categoryId: row['category_id'] as String?,
            title: row['title'] as String?,
            note: row['note'] as String?,
          ),
        )
        .toList(growable: false);
    transactionTargets.sort(
      (a, b) => a.occurredAt.compareTo(b.occurredAt) != 0
          ? a.occurredAt.compareTo(b.occurredAt)
          : a.id.compareTo(b.id),
    );
    return (transactionTargets, scheduledTargets);
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
    DateTime? occurredAt,
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
        occurredAt: occurredAt,
      );
      if (failAfterDebit) throw StateError('Injected transfer failure');
      _insertTransaction(
        accountId: toAccountId,
        type: 'transfer_in',
        amount: amountSatang,
        transferGroupId: group,
        occurredAt: occurredAt,
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
      data[table] = table == 'candidate_evidence'
          ? query(
              "SELECT * FROM candidate_evidence WHERE evidence_type<>'notification' ORDER BY id",
            )
          : await dumpTable(table);
    }
    final payload = jsonEncode({
      'schemaVersion': SchemaV5.version,
      'data': data,
    });
    return {
      'schemaVersion': SchemaV5.version,
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
            schemaVersion != 4 &&
            schemaVersion != SchemaV5.version) ||
        checksum != sha256.convert(utf8.encode(payload)).toString() ||
        data is! Map) {
      throw const FormatException('Invalid or unsupported backup');
    }
    _atomic(() {
      // Raw notification content is local-only and deliberately excluded from
      // backup payloads. Clear dependent evidence before replacing config.
      database.execute('DELETE FROM candidate_evidence');
      database.execute('DELETE FROM raw_notification_events');
      final preProfileBackup = schemaVersion == 2 || schemaVersion == 3;
      final tables = preProfileBackup
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
    '''SELECT a.*, a.opening_balance_satang + COALESCE(SUM(CASE WHEN t.status<>'confirmed' OR t.deleted_at IS NOT NULL THEN 0 WHEN t.type IN ('income','refund','transfer_in') THEN t.amount_satang WHEN t.type IN ('expense','transfer_out') THEN -t.amount_satang WHEN t.type='balance_adjustment' THEN t.amount_satang ELSE 0 END),0) AS balance_satang FROM accounts a LEFT JOIN transactions t ON t.account_id=a.id AND t.profile_id=a.profile_id WHERE a.profile_id=? AND a.deleted_at IS NULL ${includeArchived ? '' : 'AND a.is_active=1 AND a.archived_at IS NULL'} GROUP BY a.id ORDER BY a.created_at''',
    [activeProfileId],
  );

  @override
  Future<ProjectedBalanceResult> projectedBalance({
    required DateTime cutoff,
  }) async {
    final actualRows = await accounts();
    final actualBalances = <String, int>{
      for (final row in actualRows)
        row['id'] as String: row['balance_satang'] as int,
    };
    final eventRows = query(
      '''SELECT e.* FROM scheduled_financial_events e
         JOIN accounts source ON source.id=e.account_id AND source.profile_id=e.profile_id AND source.deleted_at IS NULL
         LEFT JOIN accounts destination ON destination.id=e.destination_account_id AND destination.profile_id=e.profile_id AND destination.deleted_at IS NULL
         WHERE e.profile_id=? AND e.stored_status='scheduled' AND e.deleted_at IS NULL
           AND COALESCE(e.due_at,e.scheduled_at)<=?
           AND (e.event_type<>'transfer' OR destination.id IS NOT NULL)
         ORDER BY COALESCE(e.due_at,e.scheduled_at),e.id''',
      [activeProfileId, cutoff.toUtc().toIso8601String()],
    );
    return ProjectedBalanceCalculator.calculate(
      actualBalancesSatang: actualBalances,
      scheduledEvents: eventRows.map(ScheduledFinancialEvent.fromRow),
      cutoff: cutoff,
    );
  }

  @override
  Future<FinancialCalendarResult> calendarEvents({
    required DateTime from,
    required DateTime to,
    required DateTime now,
    Set<FinancialCalendarDisplayStatus>? statuses,
    bool includeActual = true,
  }) async {
    final normalizedFrom = from.toUtc();
    final normalizedTo = to.toUtc();
    if (normalizedFrom.isAfter(normalizedTo)) {
      throw ArgumentError('Calendar range start must not be after end');
    }
    if (statuses != null && statuses.isEmpty) {
      return FinancialCalendarResult(
        events: const [],
        excludedBrokenTransferGroupIds: const [],
      );
    }
    final scheduledRows = query(
      '''SELECT * FROM scheduled_financial_events
         WHERE profile_id=? AND deleted_at IS NULL ORDER BY scheduled_at,created_at,id''',
      [activeProfileId],
    );
    final scheduled = scheduledRows
        .map(ScheduledFinancialEvent.fromRow)
        .toList();
    final suppressedTransactionIds = scheduled
        .map((event) => event.linkedTransactionId)
        .whereType<String>()
        .toSet();
    final suppressedTransferGroups = scheduled
        .map((event) => event.linkedTransferGroupId)
        .whereType<String>()
        .toSet();
    final events = <FinancialCalendarEvent>[
      for (final event in scheduled)
        if (!_calendarImpactAt(event).isBefore(normalizedFrom) &&
            !_calendarImpactAt(event).isAfter(normalizedTo))
          FinancialCalendarMapper.fromScheduled(event, now: now),
    ];
    final brokenGroups = <String>[];
    if (includeActual) {
      final actualRows = query(
        '''SELECT t.* FROM transactions t
           JOIN accounts a ON a.id=t.account_id AND a.profile_id=t.profile_id AND a.deleted_at IS NULL
           WHERE t.profile_id=? AND t.status='confirmed' AND t.deleted_at IS NULL
             AND t.occurred_at>=? AND t.occurred_at<=?
           ORDER BY t.occurred_at,t.created_at,t.id''',
        [
          activeProfileId,
          normalizedFrom.toIso8601String(),
          normalizedTo.toIso8601String(),
        ],
      );
      final transferRows = <String, List<Map<String, Object?>>>{};
      for (final row in actualRows) {
        final id = row['id'] as String;
        final transferGroup = row['transfer_group_id'] as String?;
        if (suppressedTransactionIds.contains(id) ||
            (transferGroup != null &&
                suppressedTransferGroups.contains(transferGroup))) {
          continue;
        }
        if (transferGroup != null) {
          transferRows.putIfAbsent(transferGroup, () => []).add(row);
          continue;
        }
        final mapped = _calendarActualTransaction(row);
        if (mapped != null) events.add(mapped);
      }
      for (final entry in transferRows.entries) {
        final pair = entry.value;
        final outgoing = pair
            .where((row) => row['type'] == 'transfer_out')
            .toList();
        final incoming = pair
            .where((row) => row['type'] == 'transfer_in')
            .toList();
        final valid =
            pair.length == 2 &&
            outgoing.length == 1 &&
            incoming.length == 1 &&
            outgoing.single['amount_satang'] ==
                incoming.single['amount_satang'] &&
            outgoing.single['account_id'] != incoming.single['account_id'];
        if (!valid) {
          brokenGroups.add(entry.key);
          continue;
        }
        final out = outgoing.single;
        final input = incoming.single;
        events.add(
          FinancialCalendarEvent(
            id: 'actual-transfer:${entry.key}',
            dateTime: DateTime.parse(out['occurred_at'] as String).toUtc(),
            title: (out['note'] as String?) ?? 'โอนเงิน',
            note: out['note'] as String?,
            amountSatang: out['amount_satang'] as int,
            eventType: FinancialCalendarEventType.transfer,
            direction: FinancialCalendarDirection.transfer,
            accountId: out['account_id'] as String,
            destinationAccountId: input['account_id'] as String,
            displayStatus: FinancialCalendarDisplayStatus.actual,
            originKind: FinancialCalendarOriginKind.manualTransaction,
            transferGroupId: entry.key,
            actuality: FinancialCalendarActuality.actual,
            createdAt: DateTime.parse(out['created_at'] as String).toUtc(),
          ),
        );
      }
    }
    if (statuses != null) {
      events.removeWhere((event) => !statuses.contains(event.displayStatus));
    }
    events.sort((left, right) {
      final byDate = left.dateTime.compareTo(right.dateTime);
      if (byDate != 0) return byDate;
      final byCreated = left.createdAt.compareTo(right.createdAt);
      return byCreated != 0 ? byCreated : left.id.compareTo(right.id);
    });
    brokenGroups.sort();
    return FinancialCalendarResult(
      events: events,
      excludedBrokenTransferGroupIds: brokenGroups,
    );
  }

  static DateTime _calendarImpactAt(ScheduledFinancialEvent event) =>
      (event.dueAt ?? event.scheduledAt).toUtc();

  FinancialCalendarEvent? _calendarActualTransaction(Map<String, Object?> row) {
    final type = switch (row['type']) {
      'income' => FinancialCalendarEventType.income,
      'expense' => FinancialCalendarEventType.expense,
      'refund' => FinancialCalendarEventType.refund,
      _ => null,
    };
    if (type == null) return null;
    final direction = type == FinancialCalendarEventType.expense
        ? FinancialCalendarDirection.outgoing
        : FinancialCalendarDirection.incoming;
    final source = row['source'] as String;
    return FinancialCalendarEvent(
      id: 'actual:${row['id']}',
      dateTime: DateTime.parse(row['occurred_at'] as String).toUtc(),
      title:
          (row['note'] as String?) ??
          switch (type) {
            FinancialCalendarEventType.income => 'รายรับ',
            FinancialCalendarEventType.expense => 'รายจ่าย',
            FinancialCalendarEventType.refund => 'เงินคืน',
            FinancialCalendarEventType.transfer => 'โอนเงิน',
          },
      note: row['note'] as String?,
      amountSatang: row['amount_satang'] as int,
      eventType: type,
      direction: direction,
      accountId: row['account_id'] as String,
      categoryId: row['category_id'] as String?,
      displayStatus: FinancialCalendarDisplayStatus.actual,
      originKind: source == 'scheduled_event'
          ? FinancialCalendarOriginKind.scheduledConfirmation
          : FinancialCalendarOriginKind.manualTransaction,
      transactionId: row['id'] as String,
      actuality: FinancialCalendarActuality.actual,
      createdAt: DateTime.parse(row['created_at'] as String).toUtc(),
    );
  }

  @override
  Future<SalaryProjectionResult> projectSalaryPaydaysToScheduledEvents({
    required DateTime referenceDate,
    Set<DateTime> manualHolidays = const {},
  }) async {
    var created = 0;
    var updated = 0;
    var cancelled = 0;
    final unresolved = <String>[];
    final referenceDay = DateTime.utc(
      referenceDate.year,
      referenceDate.month,
      referenceDate.day,
    );
    _atomic(() {
      final salaryProfiles = query(
        'SELECT * FROM salary_profiles WHERE profile_id=? AND deleted_at IS NULL ORDER BY created_at,id',
        [activeProfileId],
      );
      final settingRows = query(
        "SELECT value FROM profile_settings WHERE profile_id=? AND key='onboarding_profile_v1' AND deleted_at IS NULL",
        [activeProfileId],
      );
      final salaryAccounts = query(
        '''SELECT id FROM accounts WHERE profile_id=? AND is_salary_account=1
           AND is_active=1 AND archived_at IS NULL AND deleted_at IS NULL ORDER BY id''',
        [activeProfileId],
      );
      final salaryCategories = query(
        '''SELECT id FROM categories WHERE profile_id=? AND category_type='income'
           AND name='เงินเดือน' AND archived_at IS NULL AND deleted_at IS NULL ORDER BY id''',
        [activeProfileId],
      );
      if (salaryProfiles.length != 1) unresolved.add('salary_profile');
      if (settingRows.length != 1) unresolved.add('payday_configuration');
      if (salaryAccounts.length != 1) unresolved.add('salary_account');
      if (salaryCategories.length != 1) unresolved.add('salary_category');
      if (unresolved.isNotEmpty) {
        cancelled += _cancelFutureSalaryEvents(referenceDay);
        return;
      }
      final configValue = jsonDecode(settingRows.single['value'] as String);
      if (configValue is! Map<String, dynamic>) {
        unresolved.add('payday_configuration');
        cancelled += _cancelFutureSalaryEvents(referenceDay);
        return;
      }
      final payday = configValue['payday'];
      final holidayRule = configValue['holidayRule'];
      final policy = holidayRule == 'before'
          ? PaydayHolidayPolicy.before
          : holidayRule == 'after'
          ? PaydayHolidayPolicy.after
          : holidayRule == 'same'
          ? PaydayHolidayPolicy.exact
          : null;
      if (payday is! int || payday < 1 || payday > 31 || policy == null) {
        unresolved.add('payday_configuration');
        cancelled += _cancelFutureSalaryEvents(referenceDay);
        return;
      }
      final salaryProfile = salaryProfiles.single;
      final deductions = query(
        '''SELECT amount_satang FROM payroll_deductions
           WHERE profile_id=? AND salary_profile_id=? AND is_active=1 AND deleted_at IS NULL''',
        [activeProfileId, salaryProfile['id']],
      ).fold<int>(0, (sum, row) => sum + (row['amount_satang'] as int));
      final netSalary =
          (salaryProfile['gross_salary_satang'] as int) - deductions;
      if (netSalary <= 0) {
        unresolved.add('salary_amount');
        cancelled += _cancelFutureSalaryEvents(referenceDay);
        return;
      }
      final candidates = <String, DateTime>{};
      for (var offset = -2; offset <= 8; offset++) {
        final month = DateTime(referenceDay.year, referenceDay.month + offset);
        final resolved = PaydayCalendar.resolve(
          year: month.year,
          month: month.month,
          payday: payday,
          policy: policy,
          manualHolidays: manualHolidays,
        );
        candidates[_salaryOccurrenceKey(month)] = DateTime.utc(
          resolved.year,
          resolved.month,
          resolved.day,
        );
      }
      final ordered = candidates.entries.toList()
        ..sort((left, right) => left.value.compareTo(right.value));
      final previous = ordered
          .where((entry) => !entry.value.isAfter(referenceDay))
          .last;
      final projectedPaydays = <MapEntry<String, DateTime>>[
        previous,
        ...ordered.where((entry) => entry.value.isAfter(referenceDay)).take(6),
      ];
      final desiredKeys = projectedPaydays.map((entry) => entry.key).toSet();
      final salaryProfileId = salaryProfile['id'] as String;
      final existingRows = query(
        '''SELECT * FROM scheduled_financial_events
           WHERE profile_id=? AND origin_type='salary_payday' AND origin_id=? AND deleted_at IS NULL''',
        [activeProfileId, salaryProfileId],
      );
      for (final row in existingRows) {
        final event = ScheduledFinancialEvent.fromRow(row);
        if (event.storedStatus == ScheduledEventStoredState.scheduled &&
            !event.scheduledAt.toUtc().isBefore(referenceDay) &&
            !desiredKeys.contains(event.occurrenceKey)) {
          cancelled += _stopProjectedSalaryEvent(event);
        }
      }
      final accountId = salaryAccounts.single['id'] as String;
      final categoryId = salaryCategories.single['id'] as String;
      for (final projectedPayday in projectedPaydays) {
        final occurrenceKey = projectedPayday.key;
        final paydayDate = projectedPayday.value;
        final matching = existingRows
            .where((row) => row['occurrence_key'] == occurrenceKey)
            .toList();
        if (matching.isNotEmpty) {
          final event = ScheduledFinancialEvent.fromRow(matching.single);
          if (event.storedStatus != ScheduledEventStoredState.scheduled ||
              paydayDate.isBefore(referenceDay)) {
            continue;
          }
          final unchanged =
              event.accountId == accountId &&
              event.categoryId == categoryId &&
              event.amountSatang == netSalary &&
              event.title == 'เงินเดือน' &&
              event.scheduledAt.toUtc() == paydayDate &&
              event.dueAt == null;
          if (unchanged) continue;
          database.execute(
            '''UPDATE scheduled_financial_events
               SET account_id=?,category_id=?,amount_satang=?,title='เงินเดือน',scheduled_at=?,due_at=NULL,updated_at=?
               WHERE id=? AND profile_id=? AND stored_status='scheduled' AND deleted_at IS NULL''',
            [
              accountId,
              categoryId,
              netSalary,
              paydayDate.toIso8601String(),
              DateTime.now().toUtc().toIso8601String(),
              event.id,
              activeProfileId,
            ],
          );
          updated += database.updatedRows;
          continue;
        }
        final now = DateTime.now().toUtc().toIso8601String();
        database.execute(
          '''INSERT INTO scheduled_financial_events(
               id,profile_id,account_id,category_id,event_type,amount_satang,title,
               scheduled_at,stored_status,origin_type,origin_id,occurrence_key,created_at,updated_at)
             VALUES(?,?,?,?,?,?,?,?,'scheduled','salary_payday',?,?,?,?)''',
          [
            _uuid.v4(),
            activeProfileId,
            accountId,
            categoryId,
            'income',
            netSalary,
            'เงินเดือน',
            paydayDate.toIso8601String(),
            salaryProfileId,
            occurrenceKey,
            now,
            now,
          ],
        );
        created++;
      }
    });
    return SalaryProjectionResult(
      createdCount: created,
      updatedCount: updated,
      cancelledCount: cancelled,
      unresolvedReasons: unresolved,
    );
  }

  int _cancelFutureSalaryEvents(DateTime referenceDay) {
    final now = DateTime.now().toUtc().toIso8601String();
    database.execute(
      '''UPDATE scheduled_financial_events
         SET stored_status='cancelled',cancelled_at=?,updated_at=?
         WHERE profile_id=? AND origin_type='salary_payday' AND stored_status='scheduled'
           AND scheduled_at>=? AND deleted_at IS NULL''',
      [now, now, activeProfileId, referenceDay.toIso8601String()],
    );
    return database.updatedRows;
  }

  int _stopProjectedSalaryEvent(ScheduledFinancialEvent event) {
    final now = DateTime.now().toUtc().toIso8601String();
    database.execute(
      '''UPDATE scheduled_financial_events SET stored_status='cancelled',cancelled_at=?,updated_at=?
         WHERE id=? AND profile_id=? AND stored_status='scheduled' AND deleted_at IS NULL''',
      [now, now, event.id, activeProfileId],
    );
    return database.updatedRows;
  }

  static String _salaryOccurrenceKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}';

  @override
  Future<CommitmentProjectionResult>
  projectCommitmentOccurrencesToScheduledEvents() async {
    var created = 0;
    var updated = 0;
    var skipped = 0;
    var fulfilled = 0;
    final unresolved = <String>[];
    _atomic(() {
      final occurrences = query(
        '''SELECT o.*,
                  c.id commitment_id,c.name commitment_name,c.category_id commitment_category_id,
                  c.default_account_id commitment_account_id,c.status commitment_status,
                  c.deleted_at commitment_deleted_at,
                  i.deleted_at installment_deleted_at,
                  r.deleted_at recurring_deleted_at
           FROM commitment_occurrences o
           LEFT JOIN installments i ON i.id=o.installment_id AND i.profile_id=o.profile_id
           LEFT JOIN recurring_expenses r ON r.id=o.recurring_expense_id AND r.profile_id=o.profile_id
           LEFT JOIN commitments c ON c.legacy_installment_id=o.installment_id AND c.profile_id=o.profile_id
           WHERE o.profile_id=? ORDER BY o.due_date,o.id''',
        [activeProfileId],
      );
      for (final occurrence in occurrences) {
        final occurrenceId = occurrence['id'] as String;
        final existingRows = query(
          '''SELECT * FROM scheduled_financial_events
             WHERE profile_id=? AND origin_type='commitment_occurrence' AND origin_id=? AND occurrence_key=?''',
          [activeProfileId, occurrenceId, occurrenceId],
        );
        final existing = existingRows.isEmpty
            ? null
            : ScheduledFinancialEvent.fromRow(existingRows.single);
        if (existingRows.isNotEmpty &&
            existingRows.single['deleted_at'] != null) {
          unresolved.add(occurrenceId);
          continue;
        }
        if (occurrence['deleted_at'] != null ||
            occurrence['installment_deleted_at'] != null ||
            occurrence['recurring_deleted_at'] != null) {
          updated += _stopProjectedCommitmentEvent(existing, cancelled: true);
          continue;
        }
        final linkedTransactionId =
            occurrence['linked_transaction_id'] as String?;
        if (linkedTransactionId != null) {
          if (existing?.storedStatus == ScheduledEventStoredState.scheduled) {
            final transaction = query(
              "SELECT id FROM transactions WHERE id=? AND profile_id=? AND type='expense' AND status='confirmed' AND deleted_at IS NULL",
              [linkedTransactionId, activeProfileId],
            );
            if (transaction.isEmpty) {
              unresolved.add(occurrenceId);
              continue;
            }
            database.execute(
              '''UPDATE scheduled_financial_events
                 SET stored_status='fulfilled',linked_transaction_id=?,updated_at=?
                 WHERE id=? AND profile_id=? AND stored_status='scheduled' AND deleted_at IS NULL''',
              [
                linkedTransactionId,
                DateTime.now().toUtc().toIso8601String(),
                existing!.id,
                activeProfileId,
              ],
            );
            fulfilled += database.updatedRows;
          }
          continue;
        }
        if (occurrence['is_skipped'] == 1) {
          final changed = _stopProjectedCommitmentEvent(existing);
          updated += changed;
          skipped += changed;
          continue;
        }
        final parentActive =
            occurrence['commitment_id'] != null &&
            occurrence['commitment_status'] == 'active' &&
            occurrence['commitment_deleted_at'] == null;
        if (!parentActive) {
          updated += _stopProjectedCommitmentEvent(existing, cancelled: true);
          if (existing == null) unresolved.add(occurrenceId);
          continue;
        }
        final accountId = occurrence['commitment_account_id'] as String?;
        final categoryId = occurrence['commitment_category_id'] as String?;
        if (accountId == null ||
            !_projectionAccountAndCategoryAreUsable(accountId, categoryId)) {
          updated += _stopProjectedCommitmentEvent(existing, cancelled: true);
          unresolved.add(occurrenceId);
          continue;
        }
        if (existing != null &&
            existing.storedStatus != ScheduledEventStoredState.scheduled) {
          continue;
        }
        final dueAt = _commitmentDueDateUtc(occurrence['due_date'] as String);
        final now = DateTime.now().toUtc().toIso8601String();
        if (existing == null) {
          database.execute(
            '''INSERT INTO scheduled_financial_events(
                 id,profile_id,account_id,category_id,event_type,amount_satang,title,note,
                 scheduled_at,stored_status,origin_type,origin_id,occurrence_key,created_at,updated_at)
               VALUES(?,?,?,?,?,?,?,?,?,'scheduled','commitment_occurrence',?,?,?,?)''',
            [
              _uuid.v4(),
              activeProfileId,
              accountId,
              categoryId,
              'expense',
              occurrence['planned_amount_satang'],
              occurrence['commitment_name'],
              'Projected from commitment occurrence',
              dueAt.toIso8601String(),
              occurrenceId,
              occurrenceId,
              now,
              now,
            ],
          );
          created++;
        } else {
          final unchanged =
              existing.accountId == accountId &&
              existing.categoryId == categoryId &&
              existing.amountSatang == occurrence['planned_amount_satang'] &&
              existing.title == occurrence['commitment_name'] &&
              existing.scheduledAt.toUtc() == dueAt &&
              existing.dueAt == null;
          if (unchanged) continue;
          database.execute(
            '''UPDATE scheduled_financial_events
               SET account_id=?,category_id=?,amount_satang=?,title=?,scheduled_at=?,due_at=NULL,updated_at=?
               WHERE id=? AND profile_id=? AND stored_status='scheduled' AND deleted_at IS NULL''',
            [
              accountId,
              categoryId,
              occurrence['planned_amount_satang'],
              occurrence['commitment_name'],
              dueAt.toIso8601String(),
              now,
              existing.id,
              activeProfileId,
            ],
          );
          updated += database.updatedRows;
        }
      }
    });
    return CommitmentProjectionResult(
      createdCount: created,
      updatedCount: updated,
      skippedCount: skipped,
      fulfilledCount: fulfilled,
      unresolvedOccurrenceIds: unresolved,
    );
  }

  int _stopProjectedCommitmentEvent(
    ScheduledFinancialEvent? event, {
    bool cancelled = false,
  }) {
    if (event == null ||
        event.storedStatus != ScheduledEventStoredState.scheduled) {
      return 0;
    }
    final now = DateTime.now().toUtc().toIso8601String();
    database.execute(
      '''UPDATE scheduled_financial_events
         SET stored_status=?,cancelled_at=?,updated_at=?
         WHERE id=? AND profile_id=? AND stored_status='scheduled' AND deleted_at IS NULL''',
      [
        cancelled ? 'cancelled' : 'skipped',
        cancelled ? now : null,
        now,
        event.id,
        activeProfileId,
      ],
    );
    return database.updatedRows;
  }

  bool _projectionAccountAndCategoryAreUsable(
    String accountId,
    String? categoryId,
  ) {
    final account = query(
      'SELECT id FROM accounts WHERE id=? AND profile_id=? AND deleted_at IS NULL',
      [accountId, activeProfileId],
    );
    if (account.isEmpty) return false;
    if (categoryId == null) return true;
    return query(
      "SELECT id FROM categories WHERE id=? AND profile_id=? AND category_type='expense' AND deleted_at IS NULL AND archived_at IS NULL",
      [categoryId, activeProfileId],
    ).isNotEmpty;
  }

  static DateTime _commitmentDueDateUtc(String value) {
    final date = DateTime.parse(value);
    return DateTime.utc(date.year, date.month, date.day);
  }

  @override
  Future<ScheduledFinancialEvent> createScheduledEvent({
    required ScheduledEventType eventType,
    required int amountSatang,
    required String title,
    required String accountId,
    required DateTime scheduledAt,
    String? destinationAccountId,
    String? categoryId,
    String? note,
    DateTime? dueAt,
    String originType = 'manual',
    String? originId,
    String? occurrenceKey,
  }) async {
    _validateScheduledEventInput(
      eventType: eventType,
      amountSatang: amountSatang,
      title: title,
      accountId: accountId,
      destinationAccountId: destinationAccountId,
      categoryId: categoryId,
      originType: originType,
    );
    final id = _uuid.v4();
    final now = DateTime.now().toUtc().toIso8601String();
    _atomic(() {
      database.execute(
        '''INSERT INTO scheduled_financial_events(id,profile_id,account_id,destination_account_id,category_id,event_type,amount_satang,title,note,scheduled_at,due_at,stored_status,origin_type,origin_id,occurrence_key,created_at,updated_at)
           VALUES(?,?,?,?,?,?,?,?,?,?,?,'scheduled',?,?,?,?,?)''',
        [
          id,
          activeProfileId,
          accountId,
          destinationAccountId,
          categoryId,
          eventType.name,
          amountSatang,
          title.trim(),
          _nullableTrim(note),
          scheduledAt.toUtc().toIso8601String(),
          dueAt?.toUtc().toIso8601String(),
          originType.trim(),
          originId,
          occurrenceKey ?? id,
          now,
          now,
        ],
      );
    });
    return _scheduledEventById(id);
  }

  @override
  Future<List<ScheduledFinancialEvent>> scheduledEvents({
    DateTime? from,
    DateTime? to,
    String? accountId,
    Set<ScheduledEventStoredState>? statuses,
    bool includeDeleted = false,
  }) async {
    if (from != null && to != null && from.isAfter(to)) {
      throw ArgumentError('Scheduled range start must not be after end');
    }
    if (statuses != null && statuses.isEmpty) return const [];
    final clauses = <String>['profile_id=?'];
    final parameters = <Object?>[activeProfileId];
    if (!includeDeleted) clauses.add('deleted_at IS NULL');
    if (from != null) {
      clauses.add('scheduled_at>=?');
      parameters.add(from.toUtc().toIso8601String());
    }
    if (to != null) {
      clauses.add('scheduled_at<=?');
      parameters.add(to.toUtc().toIso8601String());
    }
    if (accountId != null) {
      clauses.add('(account_id=? OR destination_account_id=?)');
      parameters
        ..add(accountId)
        ..add(accountId);
    }
    if (statuses != null) {
      clauses.add(
        'stored_status IN (${List.filled(statuses.length, '?').join(',')})',
      );
      parameters.addAll(statuses.map((status) => status.name));
    }
    return query(
      'SELECT * FROM scheduled_financial_events WHERE ${clauses.join(' AND ')} ORDER BY scheduled_at,id',
      parameters,
    ).map(ScheduledFinancialEvent.fromRow).toList();
  }

  @override
  Future<ScheduledFinancialEvent> updateScheduledEvent({
    required String id,
    required ScheduledEventType eventType,
    required int amountSatang,
    required String title,
    required String accountId,
    required DateTime scheduledAt,
    String? destinationAccountId,
    String? categoryId,
    String? note,
    DateTime? dueAt,
  }) async {
    _validateScheduledEventInput(
      eventType: eventType,
      amountSatang: amountSatang,
      title: title,
      accountId: accountId,
      destinationAccountId: destinationAccountId,
      categoryId: categoryId,
      originType: 'manual',
    );
    _atomic(() {
      database.execute(
        '''UPDATE scheduled_financial_events
           SET account_id=?,destination_account_id=?,category_id=?,event_type=?,amount_satang=?,title=?,note=?,scheduled_at=?,due_at=?,updated_at=?
           WHERE id=? AND profile_id=? AND stored_status='scheduled' AND deleted_at IS NULL''',
        [
          accountId,
          destinationAccountId,
          categoryId,
          eventType.name,
          amountSatang,
          title.trim(),
          _nullableTrim(note),
          scheduledAt.toUtc().toIso8601String(),
          dueAt?.toUtc().toIso8601String(),
          DateTime.now().toUtc().toIso8601String(),
          id,
          activeProfileId,
        ],
      );
      if (database.updatedRows != 1) {
        throw StateError('Scheduled event is unavailable or terminal');
      }
    });
    return _scheduledEventById(id);
  }

  @override
  Future<ScheduledFinancialEvent> cancelScheduledEvent(String id) =>
      _setScheduledTerminalState(id, ScheduledEventStoredState.cancelled);

  @override
  Future<ScheduledFinancialEvent> skipScheduledEvent(String id) =>
      _setScheduledTerminalState(id, ScheduledEventStoredState.skipped);

  @override
  Future<String> confirmScheduledEvent(
    String id, {
    DateTime? occurredAt,
    bool failAfterLedgerInsert = false,
    bool failAfterOccurrenceLink = false,
    bool failAfterCommitmentPayment = false,
  }) async => _confirmScheduledEventSync(
    id,
    occurredAt: occurredAt,
    failAfterLedgerInsert: failAfterLedgerInsert,
    failAfterOccurrenceLink: failAfterOccurrenceLink,
    failAfterCommitmentPayment: failAfterCommitmentPayment,
  );

  String _confirmScheduledEventSync(
    String id, {
    DateTime? occurredAt,
    bool failAfterLedgerInsert = false,
    bool failAfterOccurrenceLink = false,
    bool failAfterCommitmentPayment = false,
  }) {
    late String transactionId;
    _atomic(() {
      final rows = query(
        'SELECT * FROM scheduled_financial_events WHERE id=? AND profile_id=? AND deleted_at IS NULL',
        [id, activeProfileId],
      );
      if (rows.isEmpty) throw StateError('Scheduled event not found');
      final event = ScheduledFinancialEvent.fromRow(rows.single);
      if (event.eventType == ScheduledEventType.transfer) {
        throw StateError('Use scheduled transfer confirmation');
      }
      if (event.storedStatus == ScheduledEventStoredState.fulfilled) {
        final linkedId = event.linkedTransactionId;
        if (linkedId == null ||
            database.select(
              "SELECT id FROM transactions WHERE id=? AND profile_id=? AND status='confirmed' AND deleted_at IS NULL",
              [linkedId, activeProfileId],
            ).isEmpty) {
          throw StateError('Fulfilled event has no valid ledger transaction');
        }
        if (event.originType == 'commitment_occurrence') {
          _validateFulfilledCommitmentPayment(event, linkedId);
        }
        transactionId = linkedId;
        return;
      }
      if (event.storedStatus != ScheduledEventStoredState.scheduled) {
        throw StateError('Scheduled event is terminal');
      }
      if (event.originType == 'commitment_occurrence') {
        transactionId = _confirmCommitmentScheduledPayment(
          event,
          occurredAt: occurredAt,
          failAfterLedgerInsert: failAfterLedgerInsert,
          failAfterOccurrenceLink: failAfterOccurrenceLink,
          failAfterCommitmentPayment: failAfterCommitmentPayment,
        );
      } else {
        _validateScheduledEventInput(
          eventType: event.eventType,
          amountSatang: event.amountSatang,
          title: event.title,
          accountId: event.accountId,
          destinationAccountId: event.destinationAccountId,
          categoryId: event.categoryId,
          originType: event.originType,
        );
        transactionId = _insertTransaction(
          accountId: event.accountId,
          type: event.eventType.name,
          amount: event.amountSatang,
          source: 'scheduled_event',
          categoryId: event.categoryId,
          note: event.note ?? event.title,
          occurredAt: occurredAt ?? DateTime.now(),
        );
        if (failAfterLedgerInsert) {
          throw StateError('Injected scheduled confirmation failure');
        }
      }
      final now = DateTime.now().toUtc().toIso8601String();
      database.execute(
        '''UPDATE scheduled_financial_events
           SET stored_status='fulfilled',linked_transaction_id=?,updated_at=?
           WHERE id=? AND profile_id=? AND stored_status='scheduled' AND linked_transaction_id IS NULL AND linked_transfer_group_id IS NULL AND deleted_at IS NULL''',
        [transactionId, now, id, activeProfileId],
      );
      if (database.updatedRows != 1) {
        throw StateError('Scheduled event could not be fulfilled');
      }
      _audit(
        'scheduled_event',
        id,
        'update',
        metadata: {'transition': 'fulfilled', 'transactionId': transactionId},
      );
    });
    return transactionId;
  }

  String _confirmCommitmentScheduledPayment(
    ScheduledFinancialEvent event, {
    required DateTime? occurredAt,
    required bool failAfterLedgerInsert,
    required bool failAfterOccurrenceLink,
    required bool failAfterCommitmentPayment,
  }) {
    if (event.eventType != ScheduledEventType.expense ||
        event.originId == null) {
      throw StateError('Invalid commitment scheduled event');
    }
    final rows = query(
      '''SELECT o.*,c.id commitment_id,c.default_account_id,c.category_id,c.status commitment_status,c.deleted_at commitment_deleted_at
         FROM commitment_occurrences o
         JOIN commitments c ON c.legacy_installment_id=o.installment_id AND c.profile_id=o.profile_id
         WHERE o.id=? AND o.profile_id=? AND o.deleted_at IS NULL''',
      [event.originId, activeProfileId],
    );
    if (rows.isEmpty) throw StateError('Commitment occurrence not found');
    final occurrence = rows.single;
    if (occurrence['is_skipped'] == 1 ||
        occurrence['commitment_status'] != 'active' ||
        occurrence['commitment_deleted_at'] != null) {
      throw StateError('Commitment occurrence is not payable');
    }
    if (occurrence['planned_amount_satang'] != event.amountSatang ||
        occurrence['default_account_id'] != event.accountId ||
        occurrence['category_id'] != event.categoryId) {
      throw StateError('Commitment occurrence and scheduled event mismatch');
    }
    _validateScheduledEventInput(
      eventType: event.eventType,
      amountSatang: event.amountSatang,
      title: event.title,
      accountId: event.accountId,
      destinationAccountId: event.destinationAccountId,
      categoryId: event.categoryId,
      originType: event.originType,
    );
    final commitmentId = occurrence['commitment_id'] as String;
    final existingTransactionId =
        occurrence['linked_transaction_id'] as String?;
    late String transactionId;
    var createdTransaction = false;
    if (existingTransactionId != null) {
      _validateExistingCommitmentTransaction(event, existingTransactionId);
      transactionId = existingTransactionId;
    } else {
      transactionId = _insertTransaction(
        accountId: event.accountId,
        type: 'expense',
        amount: event.amountSatang,
        source: 'scheduled_event',
        categoryId: event.categoryId,
        note: event.note ?? event.title,
        occurredAt: occurredAt ?? DateTime.now(),
      );
      createdTransaction = true;
      if (failAfterLedgerInsert) {
        throw StateError('Injected failure before occurrence link');
      }
      database.execute(
        '''UPDATE commitment_occurrences SET linked_transaction_id=?,updated_at=?
           WHERE id=? AND profile_id=? AND linked_transaction_id IS NULL AND is_skipped=0 AND deleted_at IS NULL''',
        [
          transactionId,
          DateTime.now().toUtc().toIso8601String(),
          event.originId,
          activeProfileId,
        ],
      );
      if (database.updatedRows != 1) {
        throw StateError('Commitment occurrence could not be linked');
      }
    }
    if (failAfterOccurrenceLink) {
      throw StateError('Injected failure before commitment payment');
    }
    final paymentRows = query(
      'SELECT id,commitment_id FROM commitment_payments WHERE transaction_id=? AND profile_id=? AND deleted_at IS NULL',
      [transactionId, activeProfileId],
    );
    if (paymentRows.isEmpty) {
      final now = DateTime.now().toUtc().toIso8601String();
      database.execute(
        'INSERT INTO commitment_payments(id,commitment_id,transaction_id,created_at,updated_at,profile_id) VALUES(?,?,?,?,?,?)',
        [_uuid.v4(), commitmentId, transactionId, now, now, activeProfileId],
      );
    } else if (paymentRows.single['commitment_id'] != commitmentId) {
      throw StateError('Transaction belongs to another commitment');
    }
    if (failAfterCommitmentPayment) {
      throw StateError('Injected failure before scheduled fulfillment');
    }
    if (createdTransaction) {
      _audit('transaction', transactionId, 'create');
    }
    return transactionId;
  }

  void _validateExistingCommitmentTransaction(
    ScheduledFinancialEvent event,
    String transactionId,
  ) {
    final transaction = query(
      '''SELECT id FROM transactions
         WHERE id=? AND profile_id=? AND account_id=? AND type='expense' AND amount_satang=?
           AND category_id IS ? AND status='confirmed' AND deleted_at IS NULL''',
      [
        transactionId,
        activeProfileId,
        event.accountId,
        event.amountSatang,
        event.categoryId,
      ],
    );
    if (transaction.isEmpty) {
      throw StateError('Occurrence has no matching real payment');
    }
  }

  void _validateFulfilledCommitmentPayment(
    ScheduledFinancialEvent event,
    String transactionId,
  ) {
    final rows = query(
      '''SELECT o.id FROM commitment_occurrences o
         JOIN commitments c ON c.legacy_installment_id=o.installment_id AND c.profile_id=o.profile_id
         JOIN commitment_payments p ON p.commitment_id=c.id AND p.transaction_id=o.linked_transaction_id AND p.profile_id=o.profile_id AND p.deleted_at IS NULL
         WHERE o.id=? AND o.profile_id=? AND o.linked_transaction_id=? AND o.deleted_at IS NULL''',
      [event.originId, activeProfileId, transactionId],
    );
    if (rows.isEmpty) {
      throw StateError('Fulfilled commitment event has no valid payment link');
    }
  }

  @override
  Future<String> confirmScheduledTransfer(
    String id, {
    DateTime? occurredAt,
    bool failAfterTransferOut = false,
    bool failBeforeFulfillment = false,
  }) async => _confirmScheduledTransferSync(
    id,
    occurredAt: occurredAt,
    failAfterTransferOut: failAfterTransferOut,
    failBeforeFulfillment: failBeforeFulfillment,
  );

  String _confirmScheduledTransferSync(
    String id, {
    DateTime? occurredAt,
    bool failAfterTransferOut = false,
    bool failBeforeFulfillment = false,
  }) {
    late String transferGroupId;
    _atomic(() {
      final rows = query(
        'SELECT * FROM scheduled_financial_events WHERE id=? AND profile_id=? AND deleted_at IS NULL',
        [id, activeProfileId],
      );
      if (rows.isEmpty) throw StateError('Scheduled transfer not found');
      final event = ScheduledFinancialEvent.fromRow(rows.single);
      if (event.eventType != ScheduledEventType.transfer) {
        throw StateError('Scheduled event is not a transfer');
      }
      if (event.storedStatus == ScheduledEventStoredState.fulfilled) {
        final linkedGroup = event.linkedTransferGroupId;
        if (linkedGroup == null || event.linkedTransactionId != null) {
          throw StateError('Fulfilled transfer has no valid ledger pair');
        }
        final linkedRows = query(
          "SELECT account_id,type,amount_satang FROM transactions WHERE transfer_group_id=? AND profile_id=? AND status='confirmed' AND deleted_at IS NULL ORDER BY type",
          [linkedGroup, activeProfileId],
        );
        final validPair =
            linkedRows.length == 2 &&
            linkedRows.any(
              (row) =>
                  row['type'] == 'transfer_out' &&
                  row['account_id'] == event.accountId &&
                  row['amount_satang'] == event.amountSatang,
            ) &&
            linkedRows.any(
              (row) =>
                  row['type'] == 'transfer_in' &&
                  row['account_id'] == event.destinationAccountId &&
                  row['amount_satang'] == event.amountSatang,
            );
        if (!validPair) {
          throw StateError('Fulfilled transfer has no valid ledger pair');
        }
        transferGroupId = linkedGroup;
        return;
      }
      if (event.storedStatus != ScheduledEventStoredState.scheduled) {
        throw StateError('Scheduled transfer is terminal');
      }
      _validateScheduledEventInput(
        eventType: event.eventType,
        amountSatang: event.amountSatang,
        title: event.title,
        accountId: event.accountId,
        destinationAccountId: event.destinationAccountId,
        categoryId: event.categoryId,
        originType: event.originType,
      );
      final effectiveOccurredAt = occurredAt ?? DateTime.now();
      transferGroupId = _uuid.v4();
      _insertTransaction(
        accountId: event.accountId,
        type: 'transfer_out',
        amount: event.amountSatang,
        transferGroupId: transferGroupId,
        source: 'scheduled_event',
        note: event.note ?? event.title,
        occurredAt: effectiveOccurredAt,
      );
      if (failAfterTransferOut) {
        throw StateError('Injected failure after scheduled transfer out');
      }
      _insertTransaction(
        accountId: event.destinationAccountId!,
        type: 'transfer_in',
        amount: event.amountSatang,
        transferGroupId: transferGroupId,
        source: 'scheduled_event',
        note: event.note ?? event.title,
        occurredAt: effectiveOccurredAt,
      );
      if (failBeforeFulfillment) {
        throw StateError('Injected failure before scheduled fulfillment');
      }
      final now = DateTime.now().toUtc().toIso8601String();
      database.execute(
        '''UPDATE scheduled_financial_events
           SET stored_status='fulfilled',linked_transaction_id=NULL,linked_transfer_group_id=?,updated_at=?
           WHERE id=? AND profile_id=? AND event_type='transfer' AND stored_status='scheduled' AND linked_transaction_id IS NULL AND linked_transfer_group_id IS NULL AND deleted_at IS NULL''',
        [transferGroupId, now, id, activeProfileId],
      );
      if (database.updatedRows != 1) {
        throw StateError('Scheduled transfer could not be fulfilled');
      }
      _audit(
        'scheduled_event',
        id,
        'update',
        metadata: {
          'transition': 'fulfilled',
          'transferGroupId': transferGroupId,
        },
      );
      _audit('transfer', transferGroupId, 'create');
    });
    return transferGroupId;
  }

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
          "UPDATE transactions SET deleted_at=NULL,status='confirmed',posted_at=COALESCE(posted_at,occurred_at),updated_at=? WHERE id=?",
          [now, id],
        );
      } else {
        database.execute(
          "UPDATE transactions SET deleted_at=NULL,status='confirmed',posted_at=COALESCE(posted_at,occurred_at),updated_at=? WHERE transfer_group_id=?",
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
      final profile = activeProfileId;
      database.execute(
        'DELETE FROM candidate_evidence WHERE candidate_id IN (SELECT id FROM transaction_candidates WHERE profile_id=?)',
        [profile],
      );
      database.execute(
        'DELETE FROM raw_notification_events WHERE profile_id=?',
        [profile],
      );
      database.execute(
        'DELETE FROM notification_rules WHERE notification_source_id IN (SELECT id FROM notification_sources WHERE profile_id=?)',
        [profile],
      );
      const scoped = <String>[
        'transaction_candidates',
        'notification_sources',
        'scheduled_financial_events',
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
      for (final table in scoped) {
        database.execute('DELETE FROM $table WHERE profile_id=?', [profile]);
        if (failMidway && table == 'transactions') {
          throw StateError('Injected reset failure');
        }
      }
      _audit('database', 'local-user-data', 'reset');
    });
  }

  void _validateScheduledEventInput({
    required ScheduledEventType eventType,
    required int amountSatang,
    required String title,
    required String accountId,
    required String? destinationAccountId,
    required String? categoryId,
    required String originType,
  }) {
    if (amountSatang <= 0) throw ArgumentError.value(amountSatang);
    if (title.trim().isEmpty) throw ArgumentError.value(title, 'title');
    if (originType.trim().isEmpty) {
      throw ArgumentError.value(originType, 'originType');
    }
    final isTransfer = eventType == ScheduledEventType.transfer;
    if (isTransfer) {
      if (destinationAccountId == null || destinationAccountId == accountId) {
        throw ArgumentError('Transfer accounts must be present and different');
      }
    } else if (destinationAccountId != null) {
      throw ArgumentError('Only transfers may have a destination account');
    }
    final accountIds = [accountId, ?destinationAccountId];
    final placeholders = List.filled(accountIds.length, '?').join(',');
    final ownedAccounts =
        database.select(
              'SELECT COUNT(*) count FROM accounts WHERE profile_id=? AND deleted_at IS NULL AND id IN ($placeholders)',
              [activeProfileId, ...accountIds],
            ).single['count']
            as int;
    if (ownedAccounts != accountIds.length) {
      throw StateError('Scheduled accounts must belong to active profile');
    }
    if (categoryId == null) return;
    final category = database.select(
      'SELECT category_type FROM categories WHERE id=? AND profile_id=? AND deleted_at IS NULL AND archived_at IS NULL',
      [categoryId, activeProfileId],
    );
    if (category.isEmpty) {
      throw StateError('Scheduled category must belong to active profile');
    }
    if (!isTransfer) {
      final expectedType = eventType == ScheduledEventType.income
          ? 'income'
          : 'expense';
      if (category.single['category_type'] != expectedType) {
        throw StateError('Scheduled category type mismatch');
      }
    }
  }

  ScheduledFinancialEvent _scheduledEventById(String id) {
    final rows = query(
      'SELECT * FROM scheduled_financial_events WHERE id=? AND profile_id=? AND deleted_at IS NULL',
      [id, activeProfileId],
    );
    if (rows.isEmpty) throw StateError('Scheduled event not found');
    return ScheduledFinancialEvent.fromRow(rows.single);
  }

  Future<ScheduledFinancialEvent> _setScheduledTerminalState(
    String id,
    ScheduledEventStoredState state,
  ) async {
    if (state != ScheduledEventStoredState.cancelled &&
        state != ScheduledEventStoredState.skipped) {
      throw ArgumentError.value(state);
    }
    _atomic(() {
      final now = DateTime.now().toUtc().toIso8601String();
      database.execute(
        '''UPDATE scheduled_financial_events
           SET stored_status=?,cancelled_at=?,updated_at=?
           WHERE id=? AND profile_id=? AND stored_status='scheduled' AND deleted_at IS NULL''',
        [
          state.name,
          state == ScheduledEventStoredState.cancelled ? now : null,
          now,
          id,
          activeProfileId,
        ],
      );
      if (database.updatedRows != 1) {
        throw StateError('Scheduled event is unavailable or terminal');
      }
    });
    return _scheduledEventById(id);
  }

  static String? _nullableTrim(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
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
    final effectiveOccurredAt = (occurredAt ?? DateTime.now())
        .toUtc()
        .toIso8601String();
    database.execute(
      'INSERT INTO transactions(id, account_id, category_id, type, amount_satang, occurred_at, transfer_group_id, refund_of_transaction_id, source, note, created_at, updated_at,profile_id,posted_at) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
      [
        id,
        accountId,
        categoryId,
        type,
        amount,
        effectiveOccurredAt,
        transferGroupId,
        refundOfTransactionId,
        source,
        note,
        now,
        now,
        activeProfileId,
        effectiveOccurredAt,
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

  var _atomicDepth = 0;

  void _atomic(void Function() action) {
    if (_atomicDepth > 0) {
      action();
      return;
    }
    database.execute('BEGIN IMMEDIATE');
    _atomicDepth++;
    try {
      action();
      database.execute('COMMIT');
    } catch (_) {
      database.execute('ROLLBACK');
      rethrow;
    } finally {
      _atomicDepth--;
    }
  }

  static String _date(DateTime value) =>
      value.toUtc().toIso8601String().split('T').first;
}
