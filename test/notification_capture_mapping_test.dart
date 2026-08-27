import 'package:flutter_test/flutter_test.dart';
import 'package:ngoen_ku_pai_nai/domain/notification_capture.dart';

void main() {
  test(
    'platform mapping keeps nullable generic metadata and UTC timestamp',
    () {
      final event = CapturedNotification.fromPlatform({
        'profileId': 'profile',
        'sourceId': 'source',
        'packageName': 'jp.naver.line.android',
        'notificationKeyHash': 'hash',
        'capturedAtMillis': DateTime.utc(
          2026,
          8,
          18,
          12,
        ).millisecondsSinceEpoch,
        'title': ' Chat ',
        'body': ' Synthetic body ',
        'senderOrChat': null,
      });
      expect(event.title, 'Chat');
      expect(event.body, 'Synthetic body');
      expect(event.senderOrChat, isNull);
      expect(event.capturedAt, DateTime.utc(2026, 8, 18, 12));
      expect(event.contentFingerprint, hasLength(64));
    },
  );
}
