import 'package:flutter_test/flutter_test.dart';
import 'package:ngoen_ku_pai_nai/data/repositories/sqlite_finance_repository.dart';
import 'package:ngoen_ku_pai_nai/domain/notification_capture.dart';

void main() {
  late SqliteFinanceRepository repository;
  const linePackage = 'jp.naver.line.android';

  setUp(() => repository = SqliteFinanceRepository.memory());
  tearDown(() => repository.dispose());

  Future<String> lineSource() => repository.createNotificationSource(
    sourceKind: 'line',
    displayName: 'LINE',
    packageName: linePackage,
  );

  CapturedNotification event(
    String sourceId, {
    String packageName = linePackage,
    String key = 'key-hash-1',
    String body = 'ตัวอย่างแจ้งเตือนสังเคราะห์ ไม่มีข้อมูลเงินจริง',
    String? profileId,
  }) => CapturedNotification(
    profileId: profileId ?? repository.activeProfileId,
    notificationSourceId: sourceId,
    packageName: packageName,
    notificationKeyHash: key,
    capturedAt: DateTime.utc(2026, 8, 18, 12),
    title: 'ห้องทดสอบ',
    body: body,
    senderOrChat: 'ผู้ส่งตัวอย่าง',
  );

  test('creates enables and disables a profile-scoped source', () async {
    final id = await lineSource();
    expect((await repository.notificationSources()).single.enabled, isTrue);
    await repository.setNotificationSourceEnabled(id, false);
    expect((await repository.notificationSources()).single.enabled, isFalse);
    await repository.setNotificationSourceEnabled(id, true);
    expect((await repository.notificationSources()).single.enabled, isTrue);
  });

  test('synthetic LINE notification reaches raw event only', () async {
    final source = await lineSource();
    final actualBefore = (await repository.projectedBalance(
      cutoff: DateTime.utc(2026, 8, 31),
    )).actualNetWorthSatang;
    final id = await repository.ingestCapturedNotification(event(source));
    final raw = repository.query('SELECT * FROM raw_notification_events');

    expect(id, isNotNull);
    expect(raw.single['package_name'], linePackage);
    expect(raw.single['title'], 'ห้องทดสอบ');
    expect(raw.single['sender_or_chat'], 'ผู้ส่งตัวอย่าง');
    expect(raw.single['parse_status'], 'captured');
    expect(await repository.ledgerTransactionCount(), 0);
    expect(repository.query('SELECT * FROM transaction_candidates'), isEmpty);
    expect(
      repository.query('SELECT * FROM scheduled_financial_events'),
      isEmpty,
    );
    expect(
      (await repository.projectedBalance(
        cutoff: DateTime.utc(2026, 8, 31),
      )).actualNetWorthSatang,
      actualBefore,
    );
  });

  test('unknown package and disabled source are ignored', () async {
    final source = await lineSource();
    expect(
      await repository.ingestCapturedNotification(
        event(source, packageName: 'com.example.unknown'),
      ),
      isNull,
    );
    await repository.setNotificationSourceEnabled(source, false);
    expect(await repository.ingestCapturedNotification(event(source)), isNull);
    expect(repository.query('SELECT * FROM raw_notification_events'), isEmpty);
  });

  test('duplicate identity updates one stable raw row', () async {
    final source = await lineSource();
    final first = await repository.ingestCapturedNotification(event(source));
    final second = await repository.ingestCapturedNotification(
      event(source, body: 'ข้อความฉบับอัปเดต'),
    );
    final rows = repository.query('SELECT * FROM raw_notification_events');
    expect(second, first);
    expect(rows, hasLength(1));
    expect(rows.single['body'], 'ข้อความฉบับอัปเดต');
    expect(
      rows.single['content_fingerprint'],
      isNot(event(source).contentFingerprint),
    );
  });

  test('notification sources and capture remain isolated by profile', () async {
    final profileA = repository.activeProfileId;
    final sourceA = await lineSource();
    final profileB = await repository.createProfile('B', draft: false);
    await repository.switchProfile(profileB);
    expect(await repository.notificationSources(), isEmpty);
    expect(
      await repository.ingestCapturedNotification(
        event(sourceA, profileId: profileA),
      ),
      isNotNull,
    );
    expect(
      repository
          .query('SELECT profile_id FROM raw_notification_events')
          .single['profile_id'],
      profileA,
    );
  });

  test('raw notification content is excluded from backup', () async {
    final source = await lineSource();
    await repository.ingestCapturedNotification(event(source));
    final backup = await repository.exportBackup();
    expect(backup, isNot(contains('raw_notification_events')));
    expect(backup.toString(), isNot(contains('ตัวอย่างแจ้งเตือนสังเคราะห์')));
  });

  test('source configuration survives repository reopen simulation', () async {
    await lineSource();
    final backup = await repository.exportBackup();
    final restored = SqliteFinanceRepository.memory();
    addTearDown(restored.dispose);
    await restored.restoreBackup(backup);
    expect(
      (await restored.notificationSources()).single.packageName,
      linePackage,
    );
  });
}
