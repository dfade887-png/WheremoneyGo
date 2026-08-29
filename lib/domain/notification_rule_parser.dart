final class NotificationRule {
  const NotificationRule({
    required this.id,
    required this.notificationSourceId,
    required this.name,
    required this.bodyPattern,
    required this.parserKind,
    required this.directionRule,
    required this.priority,
    required this.enabled,
    required this.ruleVersion,
    this.senderOrChatPattern,
    this.titlePattern,
    this.accountId,
    this.categoryId,
  });

  final String id, notificationSourceId, name, bodyPattern;
  final String parserKind, directionRule;
  final String? senderOrChatPattern, titlePattern, accountId, categoryId;
  final int priority, ruleVersion;
  final bool enabled;
}

final class NotificationRuleSample {
  const NotificationRuleSample({
    required this.packageName,
    required this.capturedAt,
    this.title,
    this.body,
    this.senderOrChat,
  });
  final String packageName;
  final DateTime capturedAt;
  final String? title, body, senderOrChat;
}

final class ParsedFinancialEvent {
  const ParsedFinancialEvent({
    required this.sourceId,
    required this.ruleId,
    required this.accountId,
    required this.type,
    required this.amountSatang,
    required this.occurredAt,
    required this.confidence,
    required this.evidenceRawEventIds,
    this.destinationAccountId,
    this.categoryId,
    this.merchantOrSender,
    this.referenceNo,
  });
  final String sourceId, ruleId, accountId, type;
  final String? destinationAccountId, categoryId, merchantOrSender, referenceNo;
  final int amountSatang;
  final DateTime occurredAt;
  final double confidence;
  final List<String> evidenceRawEventIds;
}

final class RulePreviewResult {
  const RulePreviewResult({
    required this.matched,
    this.amountSatang,
    this.candidateType,
    this.accountId,
    this.categoryId,
    this.error,
  });
  final bool matched;
  final int? amountSatang;
  final String? candidateType, accountId, categoryId, error;
}

final class RawNotificationSample {
  const RawNotificationSample({
    required this.id,
    required this.notificationSourceId,
    required this.capturedAt,
    required this.parseStatus,
    this.title,
    this.body,
    this.senderOrChat,
  });
  final String id, notificationSourceId, parseStatus;
  final DateTime capturedAt;
  final String? title, body, senderOrChat;
}

final class NotificationReprocessSummary {
  const NotificationReprocessSummary({
    required this.examined,
    required this.created,
    required this.noMatch,
    required this.ambiguous,
    required this.existing,
  });
  final int examined, created, noMatch, ambiguous, existing;
}

abstract final class NotificationRuleEngine {
  static RulePreviewResult preview({
    required NotificationRule rule,
    required NotificationRuleSample sample,
    String? fallbackAccountId,
  }) {
    bool fieldMatches(String? pattern, String? value) {
      if (pattern == null || pattern.trim().isEmpty) return true;
      if (value == null) return false;
      return rule.parserKind == 'regex'
          ? RegExp(pattern, caseSensitive: false).hasMatch(value)
          : value.toLowerCase().contains(pattern.trim().toLowerCase());
    }

    if (!fieldMatches(rule.senderOrChatPattern, sample.senderOrChat) ||
        !fieldMatches(rule.titlePattern, sample.title)) {
      return const RulePreviewResult(matched: false);
    }
    final body = sample.body ?? '';
    RegExpMatch? amountMatch;
    try {
      if (rule.parserKind == 'regex') {
        amountMatch = RegExp(
          rule.bodyPattern,
          caseSensitive: false,
        ).firstMatch(body);
      } else if (rule.parserKind == 'template') {
        final escaped = RegExp.escape(
          rule.bodyPattern,
        ).replaceFirst(r'\{amount\}', r'([0-9][0-9,]*(?:\.[0-9]{1,2})?)');
        amountMatch = RegExp(escaped, caseSensitive: false).firstMatch(body);
      } else if (rule.parserKind == 'keyword') {
        if (!body.toLowerCase().contains(rule.bodyPattern.toLowerCase())) {
          return const RulePreviewResult(matched: false);
        }
        amountMatch = RegExp(
          r'([0-9][0-9,]*(?:\.[0-9]{1,2})?)',
        ).firstMatch(body);
      } else {
        return const RulePreviewResult(
          matched: false,
          error: 'unsupported_parser_kind',
        );
      }
    } on FormatException {
      return const RulePreviewResult(matched: false, error: 'invalid_pattern');
    }
    if (amountMatch == null) return const RulePreviewResult(matched: false);
    if (RegExp(
      r'\b(?:USD|EUR|JPY|CNY)\b|[$€¥]',
      caseSensitive: false,
    ).hasMatch(body)) {
      return const RulePreviewResult(
        matched: false,
        error: 'unsupported_currency',
      );
    }
    final captured = amountMatch.groupCount > 0
        ? amountMatch.group(1)
        : amountMatch.group(0);
    final amount = parseThaiAmountToSatang(captured ?? '');
    if (amount == null) {
      return const RulePreviewResult(matched: false, error: 'invalid_amount');
    }
    final account = rule.accountId ?? fallbackAccountId;
    if (account == null) {
      return const RulePreviewResult(
        matched: false,
        error: 'account_unresolved',
      );
    }
    final type = switch (rule.directionRule) {
      'incoming' => 'income',
      'outgoing' => 'expense',
      'refund' => 'refund',
      'transfer' => 'transfer',
      _ => null,
    };
    if (type == null) {
      return const RulePreviewResult(
        matched: false,
        error: 'invalid_direction',
      );
    }
    return RulePreviewResult(
      matched: true,
      amountSatang: amount,
      candidateType: type,
      accountId: account,
      categoryId: rule.categoryId,
    );
  }

  static int? parseThaiAmountToSatang(String input) {
    final source = input.trim();
    if (!RegExp(
      r'^(?:\d+|\d{1,3}(?:,\d{3})+)(?:\.\d{1,2})?$',
    ).hasMatch(source)) {
      return null;
    }
    final normalized = source.replaceAll(',', '');
    final parts = normalized.split('.');
    final whole = int.tryParse(parts[0]);
    if (whole == null || whole > 90000000000000) return null;
    final fraction = parts.length == 1
        ? 0
        : int.parse(parts[1].padRight(2, '0'));
    final value = whole * 100 + fraction;
    return value > 0 ? value : null;
  }
}

abstract interface class NotificationRuleRepository {
  Future<String> createNotificationRule({
    required String notificationSourceId,
    required String name,
    required String bodyPattern,
    required String parserKind,
    required String directionRule,
    String? senderOrChatPattern,
    String? titlePattern,
    String? accountId,
    String? categoryId,
    int priority = 0,
  });
  Future<List<NotificationRule>> notificationRules(String sourceId);
  Future<void> updateNotificationRule(NotificationRule rule);
  Future<void> setNotificationRuleEnabled(String id, bool enabled);
  Future<RulePreviewResult> previewNotificationRule(
    NotificationRule rule,
    NotificationRuleSample sample,
  );
  Future<List<RawNotificationSample>> recentRawNotificationSamples(
    String sourceId, {
    int limit = 30,
  });
  Future<NotificationReprocessSummary> reprocessRawNotifications(
    String sourceId, {
    int limit = 50,
  });
  Future<String?> processRawNotification(String rawEventId);
}
