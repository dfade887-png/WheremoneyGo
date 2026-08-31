import 'dart:io' show Platform;

import 'package:flutter/services.dart';

/// Application boundary for attention-only notifications. Financial code never
/// calls Android APIs directly; failures are intentionally non-fatal.
abstract interface class CandidateNotificationService {
  Future<void> notifyCandidateCreated({
    required String candidateId,
    required String type,
    required int amountSatang,
    String? accountName,
  });

  Future<void> cancelCandidateNotification(String candidateId);
}

abstract interface class CandidateCreationInspector {
  Future<bool> hasCandidateForRawEvent(String rawEventId);
  Future<Map<String, Object?>?> candidateNotificationDetails(String id);
}

abstract interface class ProcessRawNotificationRepository {
  Future<String?> processRawNotification(String rawEventId);
}

final class AndroidCandidateNotificationService
    implements CandidateNotificationService {
  AndroidCandidateNotificationService({MethodChannel? channel})
    : _channel =
          channel ?? const MethodChannel('ngoen_ku_pai_nai/notifications');
  final MethodChannel _channel;

  @override
  Future<void> notifyCandidateCreated({
    required String candidateId,
    required String type,
    required int amountSatang,
    String? accountName,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('notifyCandidate', {
        'candidateId': candidateId,
        'type': type,
        'amountSatang': amountSatang,
        'accountName': accountName,
      });
    } on MissingPluginException {
      // Desktop/widget tests and unsupported platforms simply have no alert.
    } on PlatformException {
      // Notification permission/channel failure must not lose the Candidate.
    }
  }

  @override
  Future<void> cancelCandidateNotification(String candidateId) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('cancelCandidate', {
        'candidateId': candidateId,
      });
    } on MissingPluginException {
      // no-op outside Android
    } on PlatformException {
      // cleanup is best effort and never part of financial atomicity
    }
  }
}
