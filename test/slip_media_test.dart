import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ngoen_ku_pai_nai/data/notification_capture_bridge.dart';
import 'package:ngoen_ku_pai_nai/data/slip_media_scanner.dart';
import 'package:ngoen_ku_pai_nai/data/slip_media_lifecycle_gate.dart';
import 'package:ngoen_ku_pai_nai/data/repositories/sqlite_finance_repository.dart';
import 'package:ngoen_ku_pai_nai/domain/slip_media.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SlipMediaMetadata image(
    String id,
    DateTime added, {
    String mime = 'image/jpeg',
  }) => SlipMediaMetadata(
    mediaStoreId: id,
    contentUri: 'content://media/external/images/media/$id',
    mimeType: mime,
    dateAdded: added,
  );

  test('slip detection is off and has no baseline by default', () async {
    final repository = SqliteFinanceRepository.memory();
    expect(await repository.slipDetectionEnabled(), isFalse);
    expect(await repository.slipDetectionBaseline(), isNull);
    expect(await repository.slipMediaEvents(), isEmpty);
    repository.dispose();
  });

  test('enabling records a baseline and ignores historical media', () async {
    final repository = SqliteFinanceRepository.memory();
    final baseline = DateTime.utc(2026, 1, 1);
    await repository.setSlipDetectionEnabled(true);
    await repository.initializeSlipDetectionBaseline(baseline);
    final staged = await repository.stageNewSlipMedia([
      image('old', baseline.subtract(const Duration(seconds: 1))),
      image('new', baseline.add(const Duration(seconds: 1))),
    ]);
    expect(staged.map((e) => e.mediaStoreId), ['new']);
    repository.dispose();
  });

  test('repeated scans do not duplicate the same media identity', () async {
    final repository = SqliteFinanceRepository.memory();
    await repository.setSlipDetectionEnabled(true);
    await repository.initializeSlipDetectionBaseline(DateTime.utc(2026));
    final item = image('same', DateTime.utc(2026, 1, 2));
    expect(await repository.stageNewSlipMedia([item]), hasLength(1));
    expect(await repository.stageNewSlipMedia([item]), isEmpty);
    expect(await repository.slipMediaEvents(), hasLength(1));
    repository.dispose();
  });

  test('unsupported media is never staged', () async {
    final repository = SqliteFinanceRepository.memory();
    await repository.setSlipDetectionEnabled(true);
    await repository.initializeSlipDetectionBaseline(DateTime.utc(2026));
    final staged = await repository.stageNewSlipMedia([
      image('gif', DateTime.utc(2026, 1, 2), mime: 'image/gif'),
      image('video', DateTime.utc(2026, 1, 2), mime: 'video/mp4'),
    ]);
    expect(staged, isEmpty);
    repository.dispose();
  });

  test('scanner does not scan while disabled or before baseline', () async {
    const channel = MethodChannel('test/slip_media');
    var scanCalls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'slipImagePermissionState') return 'granted';
          if (call.method == 'scanNewSlipImages') {
            scanCalls++;
            return <Object?>[];
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final repository = SqliteFinanceRepository.memory();
    final scanner = SlipMediaScanner(
      repository,
      NotificationCaptureBridge(channel: channel),
    );
    expect(await scanner.scanIfEnabled(), 0);
    expect(scanCalls, 0);
    await repository.setSlipDetectionEnabled(true);
    expect(await scanner.scanIfEnabled(), 0);
    expect(scanCalls, 0);
    repository.dispose();
  });

  test('staging metadata does not create financial records', () async {
    final repository = SqliteFinanceRepository.memory();
    await repository.setSlipDetectionEnabled(true);
    await repository.initializeSlipDetectionBaseline(DateTime.utc(2026, 1, 1));
    expect(
      await repository.stageNewSlipMedia([
        image('1', DateTime.utc(2026, 1, 2), mime: 'image/png'),
      ]),
      hasLength(1),
    );
    expect(await repository.slipMediaEvents(), hasLength(1));
    expect(await repository.ledgerTransactionCount(), 0);
    repository.dispose();
  });

  test(
    'manual selection stages exactly the explicit N selected URIs',
    () async {
      final repository = SqliteFinanceRepository.memory();
      await repository.setSlipDetectionEnabled(true);
      final baseline = DateTime.utc(2026, 1, 2);
      await repository.initializeSlipDetectionBaseline(baseline);
      final staged = await repository.stageNewSlipMedia([
        image('chosen-a', baseline.subtract(const Duration(days: 30))),
        image('chosen-b', baseline.subtract(const Duration(days: 20))),
      ], ingestionSource: 'manual');
      expect(staged, hasLength(2));
      expect(staged.map((event) => event.ingestionSource), [
        'manual',
        'manual',
      ]);
      expect(await repository.ledgerTransactionCount(), 0);
      repository.dispose();
    },
  );

  test(
    'manual picker defers its resume scan but later automatic ingestion preserves new media',
    () async {
      final baseline = DateTime.utc(2026, 1, 1);
      final repository = SqliteFinanceRepository.memory();
      await repository.setSlipDetectionEnabled(true);
      await repository.initializeSlipDetectionBaseline(baseline);
      final gate = SlipMediaLifecycleGate();
      gate.beginManualSelection();
      gate.deferAutomaticScan();
      expect(gate.automaticStagingAllowed, isFalse);
      expect(await repository.slipMediaEvents(), isEmpty);
      gate.endManualSelection();
      // The persisted automatic baseline stays unchanged, so this item is not
      // lost merely because it appeared while the picker was open.
      expect(
        await repository.stageNewSlipMedia([
          image('unrelated-new', baseline.add(const Duration(minutes: 1))),
        ], ingestionSource: 'automatic'),
        hasLength(1),
      );
      expect(await repository.slipMediaEvents(), hasLength(1));
      repository.dispose();
    },
  );

  test(
    'manual and later automatic staging cannot duplicate selected identity',
    () async {
      final repository = SqliteFinanceRepository.memory();
      await repository.setSlipDetectionEnabled(true);
      await repository.initializeSlipDetectionBaseline(DateTime.utc(2026));
      final selected = image('selected', DateTime.utc(2026, 1, 2));
      expect(
        await repository.stageNewSlipMedia([
          selected,
        ], ingestionSource: 'manual'),
        hasLength(1),
      );
      expect(
        await repository.stageNewSlipMedia([
          selected,
        ], ingestionSource: 'automatic'),
        isEmpty,
      );
      expect(await repository.slipMediaEvents(), hasLength(1));
      expect(await repository.ledgerTransactionCount(), 0);
      repository.dispose();
    },
  );
}
