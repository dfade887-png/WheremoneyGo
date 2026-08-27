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
      expect(find.text('การแจ้งเตือน ตรวจพบ'), findsOneWidget);
      expect(find.text('ยังไม่พบรายการที่ตรงกัน'), findsOneWidget);
      expect(find.textContaining('com.'), findsNothing);
      expect(await repository.ledgerTransactionCount(), 0);

      await tester.tap(find.text('ตรวจสอบ'));
      await tester.pumpAndSettle();
      expect(find.text('สร้างเป็นรายการใหม่'), findsOneWidget);
      expect(find.text('ไม่ใช่รายการเงิน / ข้ามรายการนี้'), findsOneWidget);
      expect(await repository.ledgerTransactionCount(), 0);
    },
  );
}
