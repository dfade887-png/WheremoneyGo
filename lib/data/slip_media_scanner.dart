import '../domain/slip_media.dart';
import 'notification_capture_bridge.dart';

/// Coordinates a lightweight, local-only MediaStore scan.
final class SlipMediaScanner {
  SlipMediaScanner(this.repository, this.bridge);

  final SlipMediaRepository repository;
  final NotificationCaptureBridge bridge;
  bool _running = false;
  bool _rerunRequested = false;

  Future<int> scanIfEnabled({bool Function()? allowStaging}) async {
    if (_running) {
      _rerunRequested = true;
      return 0;
    }
    _running = true;
    var total = 0;
    try {
      do {
        _rerunRequested = false;
        if (!await repository.slipDetectionEnabled()) break;
        final permission = await bridge.slipImagePermissionState();
        if (permission == 'denied' || permission == 'unsupported') break;
        final baseline = await repository.slipDetectionBaseline();
        if (baseline == null) break;
        final media = await bridge.scanNewSlipImages(after: baseline);
        // A picker may have opened while MediaStore was being queried. Do not
        // turn that picker-return lifecycle event into an unrelated scan.
        if (allowStaging != null && !allowStaging()) break;
        total += (await repository.stageNewSlipMedia(
          media,
          ingestionSource: 'automatic',
        )).length;
      } while (_rerunRequested);
      return total;
    } finally {
      _running = false;
    }
  }
}
