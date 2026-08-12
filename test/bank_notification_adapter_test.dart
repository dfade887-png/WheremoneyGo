import 'package:flutter_test/flutter_test.dart';
import 'package:ngoen_ku_pai_nai/core/money.dart';
import 'package:ngoen_ku_pai_nai/domain/bank_notification/bank_notification_adapter.dart';

void main() {
  final adapter = ReferenceBankFixtureAdapter();
  BankNotificationInput input(
    String body, {
    String package = 'com.example.reference.bank',
    String key = 'key',
  }) => BankNotificationInput(
    notificationKey: key,
    sourcePackage: package,
    title: 'Fixture',
    body: body,
    postedAt: DateTime.utc(2026),
  );
  test('fixture outgoing amount normalizes to integer satang', () {
    final event = adapter.parse(input('Outgoing 55.25 THB'));
    expect(event.amount, Money.fromSatang(5525));
    expect(event.direction, BankEventDirection.outgoing);
    expect(event.parsed, isTrue);
  });
  test(
    'allowlist rejects other source packages',
    () => expect(
      adapter.parse(input('Outgoing 55 THB', package: 'evil.app')).errorCode,
      'unsupported_package',
    ),
  );
  test(
    'redacted content fails safely without retaining raw content',
    () => expect(
      adapter.parse(input('Sensitive content hidden')).errorCode,
      'amount_redacted_or_unavailable',
    ),
  );
  test('same normalized content has stable fingerprint', () {
    expect(
      adapter.parse(input('Outgoing   55 THB')).contentFingerprint,
      adapter.parse(input(' outgoing 55 thb ')).contentFingerprint,
    );
  });
  test('notification key changes key hash but not content fingerprint', () {
    final a = adapter.parse(input('Outgoing 55 THB', key: 'a'));
    final b = adapter.parse(input('Outgoing 55 THB', key: 'b'));
    expect(a.notificationKeyHash, isNot(b.notificationKeyHash));
    expect(a.contentFingerprint, b.contentFingerprint);
  });
}
