import 'package:flutter_test/flutter_test.dart';
import 'package:ngoen_ku_pai_nai/data/repositories/sqlite_finance_repository.dart';
import 'package:sqlite3/sqlite3.dart';

const _now = '2026-08-18T00:00:00.000Z';

void main() {
  late SqliteFinanceRepository repository;
  late String accountId;
  late String destinationId;
  late String categoryId;

  setUp(() async {
    repository = SqliteFinanceRepository.memory();
    accountId = await repository.createAccount(
      name: 'Bank',
      type: 'bank',
      openingBalanceSatang: 100000,
    );
    destinationId = await repository.createAccount(
      name: 'Wallet',
      type: 'wallet',
      openingBalanceSatang: 5000,
    );
    categoryId = await repository.createCategory(
      name: 'Food',
      type: 'expense',
      iconKey: 'restaurant',
    );
  });

  tearDown(() => repository.dispose());

  int actualNetWorth() =>
      repository.query(
            'SELECT SUM(balance_satang) total FROM (${_accountsQuery()})',
            [repository.activeProfileId],
          ).single['total']
          as int;

  test('scheduled event is stored without changing Actual Balance', () {
    final before = actualNetWorth();
    repository.execute(
      '''INSERT INTO scheduled_financial_events(id,profile_id,account_id,category_id,event_type,amount_satang,title,scheduled_at,origin_type,origin_id,occurrence_key,created_at,updated_at)
         VALUES('schedule',?,?,?,?,?,'Lunch',?,'manual','plan','2026-08-20',?,?)''',
      [
        repository.activeProfileId,
        accountId,
        categoryId,
        'expense',
        5000,
        '2026-08-20T12:00:00.000Z',
        _now,
        _now,
      ],
    );
    expect(actualNetWorth(), before);
    expect(
      repository
          .query("SELECT stored_status FROM scheduled_financial_events")
          .single['stored_status'],
      'scheduled',
    );
  });

  test('generated occurrence identity rejects duplicates', () {
    void insert(String id) => repository.execute(
      '''INSERT INTO scheduled_financial_events(id,profile_id,account_id,event_type,amount_satang,title,scheduled_at,origin_type,origin_id,occurrence_key,created_at,updated_at)
         VALUES(?,?,?,'income',10000,'Salary',?,'salary','salary-profile','2026-08',?,?)''',
      [
        id,
        repository.activeProfileId,
        accountId,
        '2026-08-25T00:00:00.000Z',
        _now,
        _now,
      ],
    );
    insert('salary-1');
    expect(() => insert('salary-2'), throwsA(isA<SqliteException>()));
  });

  test('scheduled transfer supports distinct source and destination', () {
    repository.execute(
      '''INSERT INTO scheduled_financial_events(id,profile_id,account_id,destination_account_id,event_type,amount_satang,title,scheduled_at,origin_type,occurrence_key,created_at,updated_at)
         VALUES('transfer',?,?,?,'transfer',25000,'Move money',?,'manual','transfer-1',?,?)''',
      [
        repository.activeProfileId,
        accountId,
        destinationId,
        '2026-08-20T00:00:00.000Z',
        _now,
        _now,
      ],
    );
    expect(
      () => repository.execute(
        '''INSERT INTO scheduled_financial_events(id,profile_id,account_id,destination_account_id,event_type,amount_satang,title,scheduled_at,origin_type,occurrence_key,created_at,updated_at)
           VALUES('invalid',?,?,?,'transfer',1,'Invalid',?,'manual','invalid',?,?)''',
        [
          repository.activeProfileId,
          accountId,
          accountId,
          '2026-08-20T00:00:00.000Z',
          _now,
          _now,
        ],
      ),
      throwsA(isA<SqliteException>()),
    );
  });

  test('new real ledger transaction receives posted timestamp', () async {
    final transactionId = await repository.createTransaction(
      accountId: accountId,
      categoryId: categoryId,
      type: 'expense',
      amountSatang: 2500,
      occurredAt: DateTime.utc(2026, 8, 18, 12),
    );
    final row = repository.query(
      'SELECT occurred_at,posted_at,status FROM transactions WHERE id=?',
      [transactionId],
    ).single;
    expect(row['status'], 'confirmed');
    expect(row['posted_at'], row['occurred_at']);
  });

  test('generic notification config raw evidence and candidate can link', () {
    final before = actualNetWorth();
    repository.execute(
      '''INSERT INTO notification_sources(id,profile_id,source_kind,display_name,package_name,enabled,default_account_id,created_at,updated_at)
         VALUES('source',?,'line','LINE finance','jp.naver.line.android',1,?,?,?)''',
      [repository.activeProfileId, accountId, _now, _now],
    );
    repository.execute(
      '''INSERT INTO notification_rules(id,notification_source_id,name,body_pattern,parser_kind,direction_rule,account_id,category_id,created_at,updated_at)
         VALUES('rule','source','Incoming','amount:{amount}','template','incoming',?,?,?,?)''',
      [accountId, categoryId, _now, _now],
    );
    repository.execute(
      '''INSERT INTO raw_notification_events(id,profile_id,notification_source_id,package_name,notification_key_hash,content_fingerprint,captured_at,parse_status,matched_rule_id,created_at)
         VALUES('raw',?,'source','jp.naver.line.android','key-hash','fingerprint',?,'parsed','rule',?)''',
      [repository.activeProfileId, _now, _now],
    );
    repository.execute(
      '''INSERT INTO transaction_candidates(id,profile_id,account_id,category_id,candidate_type,amount_satang,occurred_at,confidence,created_at,updated_at)
         VALUES('candidate',?,?,?,'income',25000,?,0.95,?,?)''',
      [repository.activeProfileId, accountId, categoryId, _now, _now, _now],
    );
    repository.execute(
      "INSERT INTO candidate_evidence(id,candidate_id,evidence_type,notification_event_id,created_at) VALUES('evidence','candidate','notification','raw',?)",
      [_now],
    );
    expect(actualNetWorth(), before);
    expect(
      repository
          .query("SELECT review_status FROM transaction_candidates")
          .single['review_status'],
      'pending_review',
    );
    expect(
      () => repository.execute(
        "INSERT INTO candidate_evidence(id,candidate_id,evidence_type,notification_event_id,created_at) VALUES('duplicate','candidate','notification','raw',?)",
        [_now],
      ),
      throwsA(isA<SqliteException>()),
    );
  });

  test('backup excludes raw notification content and its evidence', () async {
    repository.execute(
      '''INSERT INTO notification_sources(id,profile_id,source_kind,display_name,package_name,created_at,updated_at)
         VALUES('source',?,'line','LINE finance','jp.naver.line.android',?,?)''',
      [repository.activeProfileId, _now, _now],
    );
    repository.execute(
      '''INSERT INTO raw_notification_events(id,profile_id,notification_source_id,package_name,notification_key_hash,content_fingerprint,title,body,captured_at,created_at)
         VALUES('raw',?,'source','jp.naver.line.android','key','fp','private title','private body',?,?)''',
      [repository.activeProfileId, _now, _now],
    );
    repository.execute(
      '''INSERT INTO transaction_candidates(id,profile_id,account_id,candidate_type,amount_satang,occurred_at,confidence,created_at,updated_at)
         VALUES('candidate',?,?,'expense',1000,?,0.8,?,?)''',
      [repository.activeProfileId, accountId, _now, _now, _now],
    );
    repository.execute(
      "INSERT INTO candidate_evidence(id,candidate_id,evidence_type,notification_event_id,created_at) VALUES('evidence','candidate','notification','raw',?)",
      [_now],
    );

    final backup = await repository.exportBackup();
    final data = Map<String, Object?>.from(backup['data'] as Map);
    expect(data, isNot(contains('raw_notification_events')));
    expect(data['candidate_evidence'], isEmpty);

    final restored = SqliteFinanceRepository.memory();
    addTearDown(restored.dispose);
    await restored.restoreBackup(backup);
    expect(
      restored
          .query('SELECT COUNT(*) count FROM raw_notification_events')
          .single['count'],
      0,
    );
    expect(
      restored
          .query('SELECT COUNT(*) count FROM transaction_candidates')
          .single['count'],
      1,
    );
  });
}

String _accountsQuery() =>
    '''SELECT a.opening_balance_satang + COALESCE(SUM(CASE WHEN t.status<>'confirmed' OR t.deleted_at IS NOT NULL THEN 0 WHEN t.type IN ('income','refund','transfer_in') THEN t.amount_satang WHEN t.type IN ('expense','transfer_out') THEN -t.amount_satang WHEN t.type='balance_adjustment' THEN t.amount_satang ELSE 0 END),0) balance_satang
       FROM accounts a
       LEFT JOIN transactions t ON t.account_id=a.id AND t.profile_id=a.profile_id
       WHERE a.profile_id=? AND a.deleted_at IS NULL
       GROUP BY a.id''';
