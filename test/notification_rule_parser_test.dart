import 'package:flutter_test/flutter_test.dart';
import 'package:ngoen_ku_pai_nai/domain/notification_rule_parser.dart';

void main() {
  test('parses Thai amount forms without floating point', () {
    expect(NotificationRuleEngine.parseThaiAmountToSatang('1,500'), 150000);
    expect(NotificationRuleEngine.parseThaiAmountToSatang('1,500.00'), 150000);
    expect(NotificationRuleEngine.parseThaiAmountToSatang('1500'), 150000);
    expect(NotificationRuleEngine.parseThaiAmountToSatang('1500.25'), 150025);
    expect(NotificationRuleEngine.parseThaiAmountToSatang('-10'), isNull);
    expect(NotificationRuleEngine.parseThaiAmountToSatang('1,2,3'), isNull);
    expect(NotificationRuleEngine.parseThaiAmountToSatang('0'), isNull);
  });

  test('template preview filters sender and extracts configured direction', () {
    const rule = NotificationRule(
      id: 'r',
      notificationSourceId: 's',
      name: 'incoming',
      senderOrChatPattern: 'synthetic sender',
      bodyPattern: 'synthetic incoming {amount} บาท',
      parserKind: 'template',
      directionRule: 'incoming',
      accountId: 'a',
      priority: 1,
      enabled: true,
      ruleVersion: 1,
    );
    final result = NotificationRuleEngine.preview(
      rule: rule,
      sample: NotificationRuleSample(
        packageName: 'line',
        capturedAt: DateTime.utc(2026),
        senderOrChat: 'Synthetic Sender',
        body: 'synthetic incoming 1,500.25 บาท',
      ),
    );
    expect(result.matched, isTrue);
    expect(result.amountSatang, 150025);
    expect(result.candidateType, 'income');
  });

  test('foreign currency and unknown sender fail safely', () {
    const rule = NotificationRule(
      id: 'r',
      notificationSourceId: 's',
      name: 'expense',
      senderOrChatPattern: 'allowed',
      bodyPattern: 'paid {amount}',
      parserKind: 'template',
      directionRule: 'outgoing',
      accountId: 'a',
      priority: 0,
      enabled: true,
      ruleVersion: 1,
    );
    RulePreviewResult preview(String sender, String body) =>
        NotificationRuleEngine.preview(
          rule: rule,
          sample: NotificationRuleSample(
            packageName: 'line',
            capturedAt: DateTime.utc(2026),
            senderOrChat: sender,
            body: body,
          ),
        );
    expect(preview('unknown', 'paid 100').matched, isFalse);
    expect(preview('allowed', 'paid 100 USD').error, 'unsupported_currency');
  });
}
