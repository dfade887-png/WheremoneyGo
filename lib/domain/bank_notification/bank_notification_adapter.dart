import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../../core/money.dart';

enum BankEventDirection { incoming, outgoing, unknown }

final class BankNotificationInput {
  const BankNotificationInput({
    required this.notificationKey,
    required this.sourcePackage,
    required this.title,
    required this.body,
    required this.postedAt,
  });
  final String notificationKey, sourcePackage, title, body;
  final DateTime postedAt;
}

final class ParsedBankEvent {
  const ParsedBankEvent({
    required this.institution,
    required this.adapterVersion,
    required this.direction,
    required this.notificationKeyHash,
    required this.contentFingerprint,
    this.amount,
    this.accountHintMasked,
    this.merchantHint,
    this.errorCode,
  });
  final String institution,
      adapterVersion,
      notificationKeyHash,
      contentFingerprint;
  final BankEventDirection direction;
  final Money? amount;
  final String? accountHintMasked, merchantHint, errorCode;
  bool get parsed => errorCode == null && amount != null;
}

abstract interface class BankNotificationAdapter {
  String get institution;
  String get sourcePackage;
  String get adapterVersion;
  ParsedBankEvent parse(BankNotificationInput input);
}

/// Fixture-only adapter. It is deliberately not registered as a real bank.
final class ReferenceBankFixtureAdapter implements BankNotificationAdapter {
  @override
  String get institution => 'reference-bank-fixture';
  @override
  String get sourcePackage => 'com.example.reference.bank';
  @override
  String get adapterVersion => 'fixture-1';

  @override
  ParsedBankEvent parse(BankNotificationInput input) {
    final normalized = '${input.title} ${input.body}'
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ');
    final keyHash = sha256
        .convert(utf8.encode(input.notificationKey))
        .toString();
    final fingerprint = sha256
        .convert(utf8.encode('${input.sourcePackage}|$normalized'))
        .toString();
    if (input.sourcePackage != sourcePackage) {
      return ParsedBankEvent(
        institution: institution,
        adapterVersion: adapterVersion,
        direction: BankEventDirection.unknown,
        notificationKeyHash: keyHash,
        contentFingerprint: fingerprint,
        errorCode: 'unsupported_package',
      );
    }
    final amountMatch = RegExp(
      r'(\d+(?:[.,]\d{1,2})?)\s*thb',
      caseSensitive: false,
    ).firstMatch(normalized);
    if (amountMatch == null) {
      return ParsedBankEvent(
        institution: institution,
        adapterVersion: adapterVersion,
        direction: BankEventDirection.unknown,
        notificationKeyHash: keyHash,
        contentFingerprint: fingerprint,
        errorCode: 'amount_redacted_or_unavailable',
      );
    }
    final numeric = amountMatch.group(1)!.replaceAll(',', '');
    final parts = numeric.split('.');
    final satang =
        int.parse(parts.first) * 100 +
        (parts.length == 1 ? 0 : int.parse(parts.last.padRight(2, '0')));
    final direction = normalized.contains('outgoing')
        ? BankEventDirection.outgoing
        : normalized.contains('incoming')
        ? BankEventDirection.incoming
        : BankEventDirection.unknown;
    if (direction == BankEventDirection.unknown) {
      return ParsedBankEvent(
        institution: institution,
        adapterVersion: adapterVersion,
        direction: direction,
        notificationKeyHash: keyHash,
        contentFingerprint: fingerprint,
        amount: Money.fromSatang(satang),
        errorCode: 'direction_unavailable',
      );
    }
    return ParsedBankEvent(
      institution: institution,
      adapterVersion: adapterVersion,
      direction: direction,
      notificationKeyHash: keyHash,
      contentFingerprint: fingerprint,
      amount: Money.fromSatang(satang),
    );
  }
}
