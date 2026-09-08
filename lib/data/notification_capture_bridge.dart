import 'dart:io' show Platform;

import 'package:flutter/services.dart';

import '../domain/notification_capture.dart';
import '../domain/slip_media.dart';
import '../domain/slip_parser.dart';
import 'candidate_notification_service.dart';

final class NotificationCaptureBridge {
  NotificationCaptureBridge({MethodChannel? channel})
    : _channel =
          channel ??
          const MethodChannel('ngoen_ku_pai_nai/notification_capture');

  final MethodChannel _channel;

  Future<bool> hasAccess() async =>
      await _channel.invokeMethod<bool>('hasNotificationAccess') ?? false;

  Future<void> openAccessSettings() =>
      _channel.invokeMethod<void>('openNotificationAccess');

  Future<bool> hasPostNotificationsPermission() async => !Platform.isAndroid
      ? false
      : await _channel.invokeMethod<bool>('hasPostNotificationsPermission') ??
            false;

  Future<void> requestPostNotifications() => Platform.isAndroid
      ? _channel.invokeMethod<void>('requestPostNotifications')
      : Future.value();

  Future<void> openAppNotificationSettings() => Platform.isAndroid
      ? _channel.invokeMethod<void>('openAppNotificationSettings')
      : Future.value();

  Future<String?> consumeLaunchCandidate() => Platform.isAndroid
      ? _channel.invokeMethod<String>('consumeLaunchCandidate')
      : Future.value();

  Future<bool> isPackageInstalled(String packageName) async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('isPackageInstalled', {
            'packageName': packageName,
          }) ??
          false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<String> slipImagePermissionState() async {
    if (!Platform.isAndroid) return 'unsupported';
    try {
      return await _channel.invokeMethod<String>('slipImagePermissionState') ??
          'denied';
    } on MissingPluginException {
      return 'denied';
    }
  }

  Future<String> requestSlipImagePermission() async {
    if (!Platform.isAndroid) return 'unsupported';
    try {
      return await _channel.invokeMethod<String>(
            'requestSlipImagePermission',
          ) ??
          'denied';
    } on MissingPluginException {
      return 'denied';
    }
  }

  Future<List<SlipMediaMetadata>> scanNewSlipImages({
    required DateTime after,
  }) async {
    if (!Platform.isAndroid) return const [];
    try {
      final rows =
          await _channel.invokeListMethod<Object?>('scanNewSlipImages', {
            'afterMillis': after.toUtc().millisecondsSinceEpoch,
          }) ??
          const [];
      return rows
          .map(
            (row) => SlipMediaMetadata.fromPlatform(
              Map<Object?, Object?>.from(row! as Map),
            ),
          )
          .toList(growable: false);
    } on MissingPluginException {
      return const [];
    }
  }

  Future<List<SlipMediaMetadata>> pickSlipImages() async {
    if (!Platform.isAndroid) return const [];
    try {
      final rows =
          await _channel.invokeListMethod<Object?>('pickSlipImages') ??
          const [];
      return rows
          .map(
            (row) => SlipMediaMetadata.fromPlatform(
              Map<Object?, Object?>.from(row! as Map),
            ),
          )
          .toList(growable: false);
    } on MissingPluginException {
      return const [];
    }
  }

  /// The platform recognizer works on the local content URI; this method never
  /// sends image data or OCR text over the network.
  Future<SlipOcrResult> recognizeSlipText(String contentUri) async {
    if (!Platform.isAndroid) return const SlipOcrResult.failure('unsupported');
    try {
      final value = await _channel.invokeMapMethod<Object?, Object?>(
        'recognizeSlipText',
        {'contentUri': contentUri},
      );
      if (value == null) return const SlipOcrResult.failure('ocr_empty');
      if (value['ok'] == false) {
        return SlipOcrResult.failure(
          value['failureCode'] as String? ?? 'unknown_native_error',
        );
      }
      return SlipOcrResult.success(
        text: value['text'] as String? ?? '',
        lines: (value['lines'] as List? ?? const []).cast<String>(),
      );
    } on PlatformException {
      return const SlipOcrResult.failure('channel_error');
    } on MissingPluginException {
      return const SlipOcrResult.failure('unsupported');
    }
  }

  Future<void> syncConfiguration({
    required String profileId,
    required List<NotificationSource> sources,
  }) => _channel.invokeMethod<void>('configureCapture', {
    'profileId': profileId,
    'sources': sources
        .where((source) => source.enabled)
        .map(
          (source) => {
            'sourceId': source.id,
            'packageName': source.packageName,
          },
        )
        .toList(),
  });

  Future<List<CapturedNotification>> readPending() async {
    final rows =
        await _channel.invokeListMethod<Object?>('readCapturedNotifications') ??
        const [];
    return rows
        .map(
          (row) => CapturedNotification.fromPlatform(
            Map<Object?, Object?>.from(row! as Map),
          ),
        )
        .toList(growable: false);
  }

  Future<void> acknowledge(
    List<CapturedNotification> events,
  ) => _channel.invokeMethod<void>('acknowledgeCapturedNotifications', {
    'identities': events
        .map(
          (event) =>
              '${event.profileId}|${event.packageName}|${event.notificationKeyHash}',
        )
        .toList(),
  });
}

final class NotificationCaptureCoordinator {
  NotificationCaptureCoordinator(
    this._repository,
    this._bridge,
    this._activeProfileId, {
    CandidateNotificationService? notificationService,
  }) : _notificationService =
           notificationService ?? AndroidCandidateNotificationService();

  final NotificationCaptureRepository _repository;
  final NotificationCaptureBridge _bridge;
  final String Function() _activeProfileId;
  final CandidateNotificationService _notificationService;

  Future<int> synchronizeAndDrain() async {
    final sources = await _repository.notificationSources();
    await _bridge.syncConfiguration(
      profileId: _activeProfileId(),
      sources: sources,
    );
    var ingested = 0;
    final completed = <CapturedNotification>[];
    for (final event in await _bridge.readPending()) {
      final rawId = await _repository.ingestCapturedNotification(event);
      if (rawId != null) {
        ingested++;
        final inspector = _repository is CandidateCreationInspector
            ? _repository as CandidateCreationInspector
            : null;
        final existed = inspector == null
            ? true
            : await inspector.hasCandidateForRawEvent(rawId);
        if (!existed && _repository is ProcessRawNotificationRepository) {
          final candidateId =
              await (_repository as ProcessRawNotificationRepository)
                  .processRawNotification(rawId);
          if (candidateId != null) {
            final details = await inspector.candidateNotificationDetails(
              candidateId,
            );
            await _notificationService.notifyCandidateCreated(
              candidateId: candidateId,
              type: details?['candidate_type'] as String? ?? 'expense',
              amountSatang: details?['amount_satang'] as int? ?? 0,
              accountName: details?['account_name'] as String?,
            );
          }
        }
        completed.add(event);
      }
    }
    await _bridge.acknowledge(completed);
    return ingested;
  }
}
