import 'package:flutter/services.dart';

import '../domain/notification_capture.dart';

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
    this._activeProfileId,
  );

  final NotificationCaptureRepository _repository;
  final NotificationCaptureBridge _bridge;
  final String Function() _activeProfileId;

  Future<int> synchronizeAndDrain() async {
    final sources = await _repository.notificationSources();
    await _bridge.syncConfiguration(
      profileId: _activeProfileId(),
      sources: sources,
    );
    var ingested = 0;
    final completed = <CapturedNotification>[];
    for (final event in await _bridge.readPending()) {
      if (await _repository.ingestCapturedNotification(event) != null) {
        ingested++;
        completed.add(event);
      }
    }
    await _bridge.acknowledge(completed);
    return ingested;
  }
}
