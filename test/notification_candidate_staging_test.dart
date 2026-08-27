import 'package:flutter_test/flutter_test.dart';
import 'package:ngoen_ku_pai_nai/data/repositories/sqlite_finance_repository.dart';
import 'package:ngoen_ku_pai_nai/domain/notification_capture.dart';
import 'package:ngoen_ku_pai_nai/domain/notification_rule_parser.dart';

void main() {
  late SqliteFinanceRepository repository;
  late String account, category, source;

  setUp(() async {
    repository = SqliteFinanceRepository.memory();
    account = await repository.createAccount(
      name: 'SCB',
      type: 'bank',
      openingBalanceSatang: 1000000,
    );
    category = await repository.createCategory(
      name: 'ทั่วไป',
      type: 'expense',
      iconKey: 'other',
    );
    source = await repository.createNotificationSource(
      sourceKind: 'line',
      displayName: 'LINE',
      packageName: 'jp.naver.line.android',
      defaultAccountId: account,
    );
  });
  tearDown(() => repository.dispose());

  Future<String> rule({
    String direction = 'outgoing',
    String pattern = 'synthetic paid {amount} บาท',
    int priority = 0,
    bool enabled = true,
  }) async {
    final id = await repository.createNotificationRule(
      notificationSourceId: source,
      name: direction,
      senderOrChatPattern: 'synthetic sender',
      bodyPattern: pattern,
      parserKind: 'template',
      directionRule: direction,
      categoryId: direction == 'incoming' ? null : category,
      priority: priority,
    );
    if (!enabled) await repository.setNotificationRuleEnabled(id, false);
    return id;
  }

  Future<String> raw(
    String key,
    DateTime at, {
    String body = 'synthetic paid 100.00 บาท',
    String sender = 'synthetic sender',
  }) async => (await repository.ingestCapturedNotification(
    CapturedNotification(
      profileId: repository.activeProfileId,
      notificationSourceId: source,
      packageName: 'jp.naver.line.android',
      notificationKeyHash: key,
      capturedAt: at,
      title: 'synthetic title',
      body: body,
      senderOrChat: sender,
    ),
  ))!;

  test('rule CRUD ordering enable and profile isolation', () async {
    final low = await rule(priority: 1);
    final high = await rule(priority: 10);
    expect((await repository.notificationRules(source)).map((r) => r.id), [
      high,
      low,
    ]);
    final original = (await repository.notificationRules(source)).first;
    await repository.updateNotificationRule(
      NotificationRule(
        id: original.id,
        notificationSourceId: original.notificationSourceId,
        name: 'updated',
        senderOrChatPattern: original.senderOrChatPattern,
        titlePattern: original.titlePattern,
        bodyPattern: original.bodyPattern,
        parserKind: original.parserKind,
        directionRule: original.directionRule,
        accountId: original.accountId,
        categoryId: original.categoryId,
        priority: original.priority,
        enabled: original.enabled,
        ruleVersion: original.ruleVersion,
      ),
    );
    final updated = (await repository.notificationRules(source)).first;
    expect(updated.name, 'updated');
    expect(updated.ruleVersion, 2);
    await repository.setNotificationRuleEnabled(high, false);
    expect((await repository.notificationRules(source)).first.enabled, isFalse);
    final other = await repository.createProfile('other', draft: false);
    await repository.switchProfile(other);
    expect(await repository.notificationRules(source), isEmpty);
  });

  test('preview is read-only and uses source default account', () async {
    final id = await rule();
    final configured = (await repository.notificationRules(
      source,
    )).singleWhere((r) => r.id == id);
    final result = await repository.previewNotificationRule(
      configured,
      NotificationRuleSample(
        packageName: 'jp.naver.line.android',
        capturedAt: DateTime.utc(2026, 8, 18),
        senderOrChat: 'synthetic sender',
        body: 'synthetic paid 1,500.00 บาท',
      ),
    );
    expect(result.amountSatang, 150000);
    expect(result.accountId, account);
    expect(repository.query('SELECT * FROM transaction_candidates'), isEmpty);
  });

  test('parsed raw creates pending candidate and evidence only', () async {
    await rule();
    final rawId = await raw('key-1', DateTime.utc(2026, 8, 18, 12));
    final transactionCount = await repository.ledgerTransactionCount();
    final candidate = await repository.processRawNotification(rawId);
    expect(candidate, isNotNull);
    final row = repository.query('SELECT * FROM transaction_candidates').single;
    expect(row['review_status'], 'pending_review');
    expect(row['candidate_type'], 'expense');
    expect(row['amount_satang'], 10000);
    expect(row['matched_transaction_id'], isNull);
    expect(repository.query('SELECT * FROM candidate_evidence'), hasLength(1));
    expect(await repository.ledgerTransactionCount(), transactionCount);
  });

  test(
    'LINE child and summary consolidate to one candidate two evidence',
    () async {
      await rule();
      final first = await raw('child', DateTime.utc(2026, 8, 18, 12));
      final second = await raw('summary', DateTime.utc(2026, 8, 18, 12, 0, 5));
      expect(await repository.processRawNotification(first), isNotNull);
      expect(await repository.processRawNotification(second), isNotNull);
      expect(
        repository.query('SELECT * FROM transaction_candidates'),
        hasLength(1),
      );
      expect(
        repository.query('SELECT * FROM candidate_evidence'),
        hasLength(2),
      );
    },
  );

  test('same amount separate times remain separate candidates', () async {
    await rule();
    final first = await raw('one', DateTime.utc(2026, 8, 18, 12));
    final second = await raw('two', DateTime.utc(2026, 8, 18, 12, 1));
    await repository.processRawNotification(first);
    await repository.processRawNotification(second);
    expect(
      repository.query('SELECT * FROM transaction_candidates'),
      hasLength(2),
    );
  });

  test('reprocessing evidence is idempotent', () async {
    await rule();
    final event = await raw('same', DateTime.utc(2026, 8, 18, 12));
    final first = await repository.processRawNotification(event);
    final second = await repository.processRawNotification(event);
    expect(second, first);
    expect(
      repository.query('SELECT * FROM transaction_candidates'),
      hasLength(1),
    );
    expect(repository.query('SELECT * FROM candidate_evidence'), hasLength(1));
  });

  test('unmatched disabled and ambiguous rules create no candidate', () async {
    final unmatched = await raw(
      'unknown',
      DateTime.utc(2026, 8, 18, 12),
      sender: 'other',
    );
    await rule(enabled: false);
    expect(await repository.processRawNotification(unmatched), isNull);
    expect(repository.query('SELECT * FROM transaction_candidates'), isEmpty);

    await rule(direction: 'outgoing');
    await rule(direction: 'incoming');
    final ambiguous = await raw('ambiguous', DateTime.utc(2026, 8, 18, 13));
    expect(await repository.processRawNotification(ambiguous), isNull);
    expect(repository.query('SELECT * FROM transaction_candidates'), isEmpty);
  });

  test('candidate staging leaves Actual and Projected unchanged', () async {
    await rule();
    final event = await raw('safe', DateTime.utc(2026, 8, 18, 12));
    final before = await repository.projectedBalance(
      cutoff: DateTime.utc(2026, 8, 31),
    );
    await repository.processRawNotification(event);
    final after = await repository.projectedBalance(
      cutoff: DateTime.utc(2026, 8, 31),
    );
    expect(after.actualNetWorthSatang, before.actualNetWorthSatang);
    expect(after.projectedNetWorthSatang, before.projectedNetWorthSatang);
    expect(await repository.ledgerTransactionCount(), 0);
  });
}
