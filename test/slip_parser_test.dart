import 'package:flutter_test/flutter_test.dart';
import 'package:ngoen_ku_pai_nai/domain/slip_parser.dart';

void main() {
  const parser = SyntheticStructuredSlipParser();
  SlipOcrResult fixture(String body) => SlipOcrResult.success(text: body);

  test('outgoing fixture parses exactly to expense satang', () {
    final result = parser.parse(
      fixture('''FINANCE SLIP
DIRECTION: OUTGOING
AMOUNT: THB 1,234.50
DATETIME: 2026-09-03T10:30:00
PARTY: Test shop
REFERENCE: test-001'''),
    )!;
    expect(result.isHighConfidence, isTrue);
    expect(result.direction, SlipDirection.outgoing);
    expect(result.amountSatang, 123450);
  });

  test('incoming fixture parses to income', () {
    final result = parser.parse(
      fixture('''FINANCE SLIP
DIRECTION: INCOMING
AMOUNT: 20.5
DATETIME: 2026-09-03T10:30:00
REFERENCE: test-002'''),
    )!;
    expect(result.direction, SlipDirection.incoming);
    expect(result.amountSatang, 2050);
  });

  test('malformed amount and ambiguous direction cannot become a slip', () {
    for (final body in [
      '''FINANCE SLIP
DIRECTION: OUTGOING
AMOUNT: one hundred''',
      '''FINANCE SLIP
DIRECTION: OUTGOING/INCOMING
AMOUNT: 100
DATETIME: 2026-09-03T10:30:00''',
    ]) {
      expect(parser.parse(fixture(body))!.isFinancialSlip, isFalse);
    }
  });

  test(
    'missing optional party is tolerated but missing time is not high confidence',
    () {
      final withoutParty = parser.parse(
        fixture('''FINANCE SLIP
DIRECTION: OUTGOING
AMOUNT: 100
DATETIME: 2026-09-03T10:30:00
REFERENCE: x'''),
      )!;
      final withoutTime = parser.parse(
        fixture('''FINANCE SLIP
DIRECTION: OUTGOING
AMOUNT: 100
REFERENCE: x'''),
      )!;
      expect(withoutParty.isFinancialSlip, isTrue);
      expect(withoutTime.isHighConfidence, isFalse);
    },
  );

  test('unlabelled OCR text and isolated amount are unsupported', () {
    expect(parser.parse(fixture('120.00')), isNull);
    final registry = SlipParserRegistry([parser]);
    expect(registry.parse(fixture('120.00')).isFinancialSlip, isFalse);
  });
}
