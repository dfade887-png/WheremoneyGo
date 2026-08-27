import 'dart:convert';

import 'package:crypto/crypto.dart';

final class CapturedNotification {
  const CapturedNotification({
    required this.profileId,
    required this.notificationSourceId,
    required this.packageName,
    required this.notificationKeyHash,
    required this.capturedAt,
    this.title,
    this.body,
    this.senderOrChat,
  });

  final String profileId;
  final String notificationSourceId;
  final String packageName;
  final String notificationKeyHash;
  final DateTime capturedAt;
  final String? title;
  final String? body;
  final String? senderOrChat;

  factory CapturedNotification.fromPlatform(Map<Object?, Object?> value) {
    String? optional(String key) {
      final result = value[key]?.toString().trim();
      return result == null || result.isEmpty ? null : result;
    }

    return CapturedNotification(
      profileId: value['profileId']! as String,
      notificationSourceId: value['sourceId']! as String,
      packageName: value['packageName']! as String,
      notificationKeyHash: value['notificationKeyHash']! as String,
      capturedAt: DateTime.fromMillisecondsSinceEpoch(
        value['capturedAtMillis']! as int,
        isUtc: true,
      ),
      title: optional('title'),
      body: optional('body'),
      senderOrChat: optional('senderOrChat'),
    );
  }

  String get contentFingerprint {
    String normalize(String? text) =>
        (text ?? '').trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    final content = [
      packageName,
      normalize(senderOrChat),
      normalize(title),
      normalize(body),
    ].join('|');
    return sha256.convert(utf8.encode(content)).toString();
  }
}

final class NotificationSource {
  const NotificationSource({
    required this.id,
    required this.profileId,
    required this.sourceKind,
    required this.displayName,
    required this.packageName,
    required this.enabled,
    required this.retentionDays,
    this.defaultAccountId,
  });

  final String id, profileId, sourceKind, displayName, packageName;
  final bool enabled;
  final int retentionDays;
  final String? defaultAccountId;
}

abstract interface class NotificationCaptureRepository {
  Future<String> createNotificationSource({
    required String sourceKind,
    required String displayName,
    required String packageName,
    String? defaultAccountId,
    int retentionDays = 7,
  });
  Future<List<NotificationSource>> notificationSources();
  Future<void> setNotificationSourceEnabled(String id, bool enabled);
  Future<String?> ingestCapturedNotification(CapturedNotification event);
}
