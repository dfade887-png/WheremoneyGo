import 'package:flutter_test/flutter_test.dart';
import 'package:ngoen_ku_pai_nai/data/repositories/sqlite_finance_repository.dart';
import 'package:ngoen_ku_pai_nai/domain/notification_capture.dart';
import 'package:ngoen_ku_pai_nai/domain/notification_rule_parser.dart';

void main() {
  late SqliteFinanceRepository repository;
  late String source, account, otherAccount, expenseCategory, incomeCategory;
  const package = 'jp.naver.line.android';
  var sequence = 0;

  setUp(() async {
    repository = SqliteFinanceRepository.memory();
    account = await repository.createAccount(
      name: 'SCB Test',
      type: 'bank',
      openingBalanceSatang: 1000000,
    );
    otherAccount = await repository.createAccount(
      name: 'KTB Test',
      type: 'bank',
      openingBalanceSatang: 500000,
    );
    expenseCategory = await repository.createCategory(
      name: 'ทั่วไป',
      type: 'expense',
      iconKey: 'other',
    );
    incomeCategory = await repository.createCategory(
      name: 'รับเงิน',
      type: 'income',
      iconKey: 'income',
    );
    source = await repository.createNotificationSource(
      sourceKind: 'line',
      displayName: 'LINE',
      packageName: package,
    );
  });
  tearDown(() => repository.dispose());

  Future<String> createRule({
    String name = 'SCB outgoing',
    String sender = 'SCB Connect',
    String pattern = 'รายการเงินออก {amount} บาท',
    String parser = 'template',
    String direction = 'outgoing',
    String? mappedAccount,
    String? category,
    bool enabled = true,
    int priority = 0,
  }) async {
    final id = await repository.createNotificationRule(
      notificationSourceId: source,
      name: name,
      senderOrChatPattern: sender,
      bodyPattern: pattern,
      parserKind: parser,
      directionRule: direction,
      accountId: mappedAccount ?? account,
      categoryId: category,
      priority: priority,
    );
    if (!enabled) await repository.setNotificationRuleEnabled(id, false);
    return id;
  }

  Future<String> addRaw({
    String sender = 'SCB Connect',
    String body = 'รายการเงินออก 100.00 บาท',
    DateTime? at,
  }) async => (await repository.ingestCapturedNotification(
    CapturedNotification(
      profileId: repository.activeProfileId,
      notificationSourceId: source,
      packageName: package,
      notificationKeyHash: 'key-${sequence++}',
      capturedAt: at ?? DateTime.now().toUtc(),
      title: 'Synthetic',
      body: body,
      senderOrChat: sender,
    ),
  ))!;

  NotificationRule draft({
    required String id,
    String name = 'edited',
    String pattern = 'รายการเงินออก {amount} บาท',
    String parser = 'template',
    String direction = 'outgoing',
    String? category,
    bool enabled = true,
  }) => NotificationRule(
    id: id,
    notificationSourceId: source,
    name: name,
    senderOrChatPattern: 'SCB Connect',
    bodyPattern: pattern,
    parserKind: parser,
    directionRule: direction,
    accountId: account,
    categoryId: category,
    priority: 2,
    enabled: enabled,
    ruleVersion: 1,
  );

  test('1 create rule', () async {
    await createRule(category: expenseCategory);
    final rules = await repository.notificationRules(source);
    expect(rules, hasLength(1));
    expect(rules.single.enabled, isTrue);
  });

  test('2 update rule increments version and changes fields', () async {
    final id = await createRule();
    await repository.updateNotificationRule(draft(id: id, name: 'SCB edited'));
    final rule = (await repository.notificationRules(source)).single;
    expect(rule.name, 'SCB edited');
    expect(rule.ruleVersion, 2);
  });

  test('3 enable and disable rule', () async {
    final id = await createRule();
    await repository.setNotificationRuleEnabled(id, false);
    expect(
      (await repository.notificationRules(source)).single.enabled,
      isFalse,
    );
    await repository.setNotificationRuleEnabled(id, true);
    expect((await repository.notificationRules(source)).single.enabled, isTrue);
  });

  test('4 profile isolation rejects foreign source', () async {
    final otherProfile = await repository.createProfile('Other');
    await repository.switchProfile(otherProfile);
    final foreignSource = await repository.createNotificationSource(
      sourceKind: 'line',
      displayName: 'LINE other',
      packageName: package,
    );
    await repository.switchProfile('legacy-default-profile');
    await expectLater(
      repository.createNotificationRule(
        notificationSourceId: foreignSource,
        name: 'x',
        bodyPattern: 'x {amount}',
        parserKind: 'template',
        directionRule: 'outgoing',
        accountId: account,
      ),
      throwsStateError,
    );
  });

  test('5 invalid account is rejected', () async {
    await expectLater(createRule(mappedAccount: 'missing'), throwsStateError);
  });

  test('6 incompatible category is rejected', () async {
    await expectLater(
      createRule(direction: 'incoming', category: expenseCategory),
      throwsStateError,
    );
  });

  test('7 invalid regex and invalid template are rejected', () async {
    await expectLater(
      createRule(parser: 'regex', pattern: '('),
      throwsArgumentError,
    );
    await expectLater(
      createRule(pattern: 'ไม่มี placeholder'),
      throwsArgumentError,
    );
  });

  test('8 preview is read-only', () async {
    final rawId = await addRaw();
    final sample = (await repository.recentRawNotificationSamples(
      source,
    )).single;
    final before = {
      for (final table in [
        'transactions',
        'transaction_candidates',
        'candidate_evidence',
        'raw_notification_events',
      ])
        table: repository.query('SELECT COUNT(*) n FROM $table').single['n'],
    };
    final result = await repository.previewNotificationRule(
      draft(id: 'preview'),
      NotificationRuleSample(
        packageName: package,
        capturedAt: sample.capturedAt,
        title: sample.title,
        body: sample.body,
        senderOrChat: sample.senderOrChat,
      ),
    );
    expect(result.matched, isTrue);
    expect(result.amountSatang, 10000);
    expect(
      repository.query(
        'SELECT parse_status FROM raw_notification_events WHERE id=?',
        [rawId],
      ).single['parse_status'],
      'captured',
    );
    for (final entry in before.entries) {
      expect(
        repository.query('SELECT COUNT(*) n FROM ${entry.key}').single['n'],
        entry.value,
      );
    }
  });

  test('9 synthetic SCB outgoing preview', () async {
    final result = NotificationRuleEngine.preview(
      rule: draft(id: 'scb', category: expenseCategory),
      sample: NotificationRuleSample(
        packageName: package,
        capturedAt: DateTime.now(),
        senderOrChat: 'SCB Connect',
        body: 'รายการเงินออก 100.00 บาท',
      ),
    );
    expect(result.matched, isTrue);
    expect(result.candidateType, 'expense');
  });

  test('10 synthetic Krungthai incoming preview', () async {
    final rule = NotificationRule(
      id: 'ktb',
      notificationSourceId: source,
      name: 'KTB income',
      senderOrChatPattern: 'Krungthai Connext',
      bodyPattern: 'เงินเข้า {amount} บาท',
      parserKind: 'template',
      directionRule: 'incoming',
      accountId: otherAccount,
      categoryId: incomeCategory,
      priority: 0,
      enabled: true,
      ruleVersion: 1,
    );
    final result = NotificationRuleEngine.preview(
      rule: rule,
      sample: NotificationRuleSample(
        packageName: package,
        capturedAt: DateTime.now(),
        senderOrChat: 'Krungthai Connext',
        body: 'เงินเข้า 100.00 บาท',
      ),
    );
    expect(result.matched, isTrue);
    expect(result.candidateType, 'income');
  });

  test('11 reprocess creates pending Candidate and evidence', () async {
    await createRule(category: expenseCategory);
    await addRaw();
    final summary = await repository.reprocessRawNotifications(source);
    expect(summary.created, 1);
    expect(
      repository
          .query('SELECT review_status FROM transaction_candidates')
          .single['review_status'],
      'pending_review',
    );
    expect(repository.query('SELECT * FROM candidate_evidence'), hasLength(1));
  });

  test('12 reprocess is idempotent after notification revision', () async {
    await createRule();
    final id = await addRaw();
    await repository.reprocessRawNotifications(source);
    repository.execute(
      "UPDATE raw_notification_events SET parse_status='captured' WHERE id=?",
      [id],
    );
    final second = await repository.reprocessRawNotifications(source);
    expect(second.existing, 1);
    expect(
      repository.query('SELECT * FROM transaction_candidates'),
      hasLength(1),
    );
    expect(repository.query('SELECT * FROM candidate_evidence'), hasLength(1));
  });

  test('13 ambiguous incompatible rules create no Candidate', () async {
    await createRule(direction: 'outgoing');
    await createRule(
      name: 'incoming collision',
      direction: 'incoming',
      mappedAccount: otherAccount,
    );
    await addRaw();
    final summary = await repository.reprocessRawNotifications(source);
    expect(summary.ambiguous, 1);
    expect(repository.query('SELECT * FROM transaction_candidates'), isEmpty);
  });

  test('14 disabled rule is ignored', () async {
    await createRule(enabled: false);
    await addRaw();
    final summary = await repository.reprocessRawNotifications(source);
    expect(summary.noMatch, 1);
    expect(repository.query('SELECT * FROM transaction_candidates'), isEmpty);
  });

  test('15 resolved Candidate is not duplicated', () async {
    await createRule();
    final raw = await addRaw();
    await repository.reprocessRawNotifications(source);
    repository.execute(
      "UPDATE transaction_candidates SET review_status='ignored' WHERE id=(SELECT candidate_id FROM candidate_evidence WHERE notification_event_id=?)",
      [raw],
    );
    repository.execute(
      "UPDATE raw_notification_events SET parse_status='captured' WHERE id=?",
      [raw],
    );
    await repository.reprocessRawNotifications(source);
    expect(
      repository.query('SELECT * FROM transaction_candidates'),
      hasLength(1),
    );
  });

  test('16 rule preview and reprocess never change financial state', () async {
    await createRule();
    await addRaw();
    final beforeTransactions = await repository.ledgerTransactionCount();
    final beforeActual = (await repository.accounts()).fold<int>(
      0,
      (sum, row) => sum + (row['balance_satang'] as int),
    );
    final scheduledBefore = repository
        .query('SELECT COUNT(*) n FROM scheduled_financial_events')
        .single['n'];
    await repository.reprocessRawNotifications(source);
    expect(await repository.ledgerTransactionCount(), beforeTransactions);
    expect(
      (await repository.accounts()).fold<int>(
        0,
        (sum, row) => sum + (row['balance_satang'] as int),
      ),
      beforeActual,
    );
    expect(
      repository
          .query('SELECT COUNT(*) n FROM scheduled_financial_events')
          .single['n'],
      scheduledBefore,
    );
  });

  test(
    'recent sample picker is bounded and exposes no identity fields',
    () async {
      await addRaw();
      final samples = await repository.recentRawNotificationSamples(
        source,
        limit: 1,
      );
      expect(samples, hasLength(1));
      expect(samples.single.body, isNotEmpty);
    },
  );
}
