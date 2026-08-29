import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ngoen_ku_pai_nai/data/repositories/sqlite_finance_repository.dart';
import 'package:ngoen_ku_pai_nai/ui/candidate_inbox_controller.dart';
import 'package:ngoen_ku_pai_nai/ui/candidate_inbox_screen.dart';

void main() {
  testWidgets(
    'pending no-match candidate renders safely and opening is read-only',
    (tester) async {
      final repository = SqliteFinanceRepository.memory();
      addTearDown(repository.dispose);
      final account = await repository.createAccount(
        name: 'SCB',
        type: 'bank',
        openingBalanceSatang: 100000,
      );
      final now = DateTime.now().toUtc().toIso8601String();
      repository.execute(
        '''INSERT INTO transaction_candidates(id,profile_id,account_id,candidate_type,
         amount_satang,occurred_at,confidence,created_at,updated_at)
         VALUES('candidate-ui',?,?,?,?,?,?,?,?)''',
        [
          repository.activeProfileId,
          account,
          'expense',
          150000,
          now,
          0.9,
          now,
          now,
        ],
      );
      final controller = CandidateInboxController(repository);
      await tester.pumpWidget(
        MaterialApp(home: CandidateInboxScreen(controller: controller)),
      );
      await tester.pumpAndSettle();

      expect(find.text('LINE ตรวจพบ'), findsNothing);
      expect(find.text('รายจ่าย'), findsOneWidget);
      expect(find.textContaining('ตรวจพบจาก การแจ้งเตือน'), findsOneWidget);
      expect(find.text('ยังไม่พบรายการที่ตรงกัน'), findsOneWidget);
      expect(find.textContaining('com.'), findsNothing);
      expect(await repository.ledgerTransactionCount(), 0);

      await tester.tap(find.text('ตรวจสอบ'));
      await tester.pumpAndSettle();
      expect(find.text('สร้างเป็นรายการใหม่'), findsOneWidget);
      expect(find.text('ผลที่จะเกิดขึ้น'), findsOneWidget);
      expect(find.text('ไม่ใช่รายการเงิน / ข้ามรายการนี้'), findsOneWidget);
      expect(await repository.ledgerTransactionCount(), 0);
    },
  );

  testWidgets('correlated pair opens preview and rejection stays read-only', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    addTearDown(tester.view.resetPhysicalSize);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = SqliteFinanceRepository.memory();
    addTearDown(repository.dispose);
    final source = await repository.createAccount(
      name: 'SCB main account with a very long Thai-sized label',
      type: 'bank',
      openingBalanceSatang: 100000,
    );
    final destination = await repository.createAccount(
      name: 'Krungthai',
      type: 'bank',
      openingBalanceSatang: 50000,
    );
    final now = DateTime.now().toUtc();
    _candidate(repository, 'pair-out', source, 'expense', now);
    _candidate(
      repository,
      'pair-in',
      destination,
      'income',
      now.add(const Duration(minutes: 2)),
    );
    final controller = CandidateInboxController(repository);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(home: CandidateInboxScreen(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(find.text('อาจเป็นการโอนระหว่างบัญชี'), findsNWidgets(2));
    expect(await repository.ledgerTransactionCount(), 0);
    final reviewPair = find.byKey(const ValueKey('review-transfer-pair-out'));
    await tester.scrollUntilVisible(
      reviewPair,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(reviewPair);
    await tester.pumpAndSettle();
    expect(find.text('ตรวจสอบการโอนระหว่างบัญชี'), findsOneWidget);
    expect(
      find.textContaining('เงินจริงจะเปลี่ยนเมื่อคุณกดยืนยัน'),
      findsOneWidget,
    );
    final reject = find.byKey(const Key('reject-correlated-transfer'));
    await tester.ensureVisible(reject);
    await tester.tap(reject);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('candidate-pair-out')), findsOneWidget);
    expect(find.byKey(const ValueKey('candidate-pair-in')), findsOneWidget);
    expect(find.text('อาจเป็นการโอนระหว่างบัญชี'), findsNothing);
    expect(await repository.ledgerTransactionCount(), 0);
  });

  testWidgets('correlated pair requires explicit dialog confirmation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    addTearDown(tester.view.resetPhysicalSize);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = SqliteFinanceRepository.memory();
    addTearDown(repository.dispose);
    final source = await repository.createAccount(
      name: 'SCB',
      type: 'bank',
      openingBalanceSatang: 100000,
    );
    final destination = await repository.createAccount(
      name: 'KTB',
      type: 'bank',
      openingBalanceSatang: 50000,
    );
    final now = DateTime.now().toUtc();
    _candidate(repository, 'confirm-out', source, 'expense', now);
    _candidate(
      repository,
      'confirm-in',
      destination,
      'income',
      now.add(const Duration(minutes: 1)),
    );
    final controller = CandidateInboxController(repository);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(home: CandidateInboxScreen(controller: controller)),
    );
    await tester.pumpAndSettle();
    final reviewPair = find.byKey(
      const ValueKey('review-transfer-confirm-out'),
    );
    await tester.scrollUntilVisible(
      reviewPair,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(reviewPair);
    await tester.pumpAndSettle();
    final confirm = find.byKey(const Key('confirm-correlated-transfer'));
    await tester.ensureVisible(confirm);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(find.text('ยืนยันการโอน?'), findsOneWidget);
    expect(await repository.ledgerTransactionCount(), 0);
    await tester.tap(
      find.byKey(const Key('confirm-correlated-transfer-dialog')),
    );
    await tester.pumpAndSettle();
    expect(await repository.ledgerTransactionCount(), 2);
    expect(find.byKey(const Key('candidate-inbox-empty')), findsOneWidget);
  });
}

void _candidate(
  SqliteFinanceRepository repository,
  String id,
  String accountId,
  String type,
  DateTime occurredAt,
) {
  final now = occurredAt.toUtc().toIso8601String();
  repository.execute(
    '''INSERT INTO transaction_candidates(id,profile_id,account_id,candidate_type,
       amount_satang,occurred_at,confidence,review_status,created_at,updated_at)
       VALUES(?,?,?,?,?,?,0.95,'pending_review',?,?)''',
    [id, repository.activeProfileId, accountId, type, 10000, now, now, now],
  );
}
