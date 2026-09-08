import 'package:flutter_test/flutter_test.dart';
import 'package:ngoen_ku_pai_nai/data/repositories/sqlite_finance_repository.dart';
import 'package:ngoen_ku_pai_nai/domain/slip_media.dart';
import 'package:ngoen_ku_pai_nai/domain/slip_parser.dart';

void main() {
  late SqliteFinanceRepository repository;
  late String eventId;

  setUp(() async {
    repository = SqliteFinanceRepository.memory();
    await repository.setSlipDetectionEnabled(true);
    await repository.initializeSlipDetectionBaseline(DateTime.utc(2026));
    final staged = await repository.stageNewSlipMedia([
      SlipMediaMetadata(
        mediaStoreId: 'synthetic-1',
        contentUri: 'content://synthetic/1',
        mimeType: 'image/jpeg',
        dateAdded: DateTime.utc(2026, 9, 3),
      ),
    ], ingestionSource: 'manual');
    eventId = staged.single.id;
  });

  tearDown(() => repository.dispose());

  NormalizedSlipResult high() => NormalizedSlipResult(
    isFinancialSlip: true,
    parserId: 'fixture',
    parserVersion: '1',
    confidence: .95,
    direction: SlipDirection.outgoing,
    amountSatang: 12050,
    occurredAt: DateTime.utc(2026, 9, 3, 10),
    referenceNo: 'fixture-ref',
  );

  test(
    'high confidence creates one pending candidate with slip evidence only',
    () async {
      final beforeTransactions = await repository.ledgerTransactionCount();
      await repository.saveSlipParseResult(eventId, high());
      final first = await repository.createCandidateFromSlip(eventId);
      final second = await repository.createCandidateFromSlip(eventId);
      expect(first, isNotNull);
      expect(second, first);
      expect(await repository.ledgerTransactionCount(), beforeTransactions);
      expect(
        repository.query(
          'SELECT evidence_type,slip_media_event_id FROM candidate_evidence WHERE candidate_id=?',
          [first],
        ).single,
        {'evidence_type': 'slip', 'slip_media_event_id': eventId},
      );
      expect(
        repository.query(
          'SELECT review_status FROM transaction_candidates WHERE id=?',
          [first],
        ).single['review_status'],
        'pending_review',
      );
    },
  );

  test(
    'medium confidence creates no candidate and leaves financial state alone',
    () async {
      await repository.saveSlipParseResult(
        eventId,
        NormalizedSlipResult(
          isFinancialSlip: true,
          parserId: 'fixture',
          parserVersion: '1',
          confidence: .7,
          direction: SlipDirection.outgoing,
          amountSatang: 100,
        ),
      );
      expect(await repository.createCandidateFromSlip(eventId), isNull);
      expect(
        repository
            .query('SELECT COUNT(*) count FROM transaction_candidates')
            .single['count'],
        0,
      );
    },
  );

  test('failure is retry-safe and stores only its safe code', () async {
    final first = await repository.markSlipParseFailed(
      eventId,
      'permission_revoked',
    );
    expect(first.failureCode, 'permission_revoked');
    expect(
      repository
          .query('SELECT COUNT(*) count FROM slip_parse_results')
          .single['count'],
      1,
    );
    await repository.saveSlipParseResult(eventId, high());
    expect(await repository.createCandidateFromSlip(eventId), isNotNull);
    expect(
      repository
          .query('SELECT COUNT(*) count FROM slip_media_events')
          .single['count'],
      1,
    );
  });
}
