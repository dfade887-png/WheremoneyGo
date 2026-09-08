/// In-memory OCR output. It must never be written to SQLite or debug logs.
final class SlipOcrResult {
  const SlipOcrResult.success({required this.text, this.lines = const []})
    : failureCode = null;
  const SlipOcrResult.failure(this.failureCode) : text = '', lines = const [];

  final String text;
  final List<String> lines;
  final String? failureCode;
  bool get succeeded => failureCode == null;
}

abstract interface class SlipOcrEngine {
  Future<SlipOcrResult> recognize(String contentUri);
}

enum SlipDirection { outgoing, incoming }

final class NormalizedSlipResult {
  const NormalizedSlipResult({
    required this.isFinancialSlip,
    required this.parserId,
    required this.parserVersion,
    required this.confidence,
    this.direction,
    this.amountSatang,
    this.occurredAt,
    this.merchantOrSender,
    this.bankHint,
    this.accountHint,
    this.referenceNo,
    this.warnings = const [],
  });

  final bool isFinancialSlip;
  final String parserId, parserVersion;
  final double confidence;
  final SlipDirection? direction;
  final int? amountSatang;
  final DateTime? occurredAt;
  final String? merchantOrSender, bankHint, accountHint, referenceNo;
  final List<String> warnings;

  bool get isHighConfidence =>
      isFinancialSlip &&
      confidence >= .85 &&
      direction != null &&
      amountSatang != null &&
      occurredAt != null;
}

abstract interface class SlipParser {
  String get id;
  String get version;
  NormalizedSlipResult? parse(SlipOcrResult ocr);
}

final class SlipParserRegistry {
  const SlipParserRegistry(this.parsers);
  final List<SlipParser> parsers;

  NormalizedSlipResult parse(SlipOcrResult ocr) {
    for (final parser in parsers) {
      final parsed = parser.parse(ocr);
      if (parsed != null) return parsed;
    }
    return const NormalizedSlipResult(
      isFinancialSlip: false,
      parserId: 'unsupported',
      parserVersion: '1',
      confidence: 0,
      warnings: ['unsupported_format'],
    );
  }
}

/// Deliberately narrow. This parser is only for synthetic, labelled fixtures;
/// it does not claim support for any bank's real slip format.
final class SyntheticStructuredSlipParser implements SlipParser {
  const SyntheticStructuredSlipParser();
  @override
  String get id => 'synthetic_structured_slip';
  @override
  String get version => '1';

  @override
  NormalizedSlipResult? parse(SlipOcrResult ocr) {
    if (!ocr.succeeded || !ocr.text.contains('FINANCE SLIP')) return null;
    final rows = <String, String>{};
    for (final line in ocr.text.split(RegExp(r'\r?\n'))) {
      final match = RegExp(r'^\s*([A-Z_ ]+)\s*:\s*(.*?)\s*$').firstMatch(line);
      if (match != null) rows[match.group(1)!.trim()] = match.group(2)!.trim();
    }
    final direction = switch (rows['DIRECTION']?.toUpperCase()) {
      'OUTGOING' => SlipDirection.outgoing,
      'INCOMING' => SlipDirection.incoming,
      _ => null,
    };
    final amount = _toSatang(rows['AMOUNT']);
    final occurredAt = DateTime.tryParse(rows['DATETIME'] ?? '');
    final reference = rows['REFERENCE'];
    final conflict = rows['DIRECTION']?.contains('/') ?? false;
    if (conflict || amount == null || direction == null) {
      return NormalizedSlipResult(
        isFinancialSlip: false,
        parserId: id,
        parserVersion: version,
        confidence: 0,
        warnings: const ['ambiguous_or_malformed'],
      );
    }
    var score = .55; // labelled structure + valid direction/amount
    if (occurredAt != null) score += .25;
    if (reference != null && reference.isNotEmpty) score += .15;
    if ((rows['PARTY'] ?? '').isNotEmpty) score += .05;
    return NormalizedSlipResult(
      isFinancialSlip: true,
      parserId: id,
      parserVersion: version,
      confidence: score,
      direction: direction,
      amountSatang: amount,
      occurredAt: occurredAt?.toLocal(),
      merchantOrSender: rows['PARTY'],
      bankHint: rows['BANK'],
      accountHint: rows['ACCOUNT_HINT'],
      referenceNo: reference,
      warnings: occurredAt == null ? const ['missing_datetime'] : const [],
    );
  }

  int? _toSatang(String? input) {
    if (input == null) return null;
    final normalized = input.replaceAll('THB', '').replaceAll(',', '').trim();
    final match = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$').firstMatch(normalized);
    if (match == null) return null;
    final whole = int.tryParse(match.group(1)!);
    if (whole == null) return null;
    final fraction = (match.group(2) ?? '').padRight(2, '0');
    return whole * 100 + (int.tryParse(fraction) ?? 0);
  }
}
