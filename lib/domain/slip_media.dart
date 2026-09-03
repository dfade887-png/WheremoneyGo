/// Metadata discovered from Android MediaStore. No image bytes are retained.
final class SlipMediaMetadata {
  const SlipMediaMetadata({
    required this.mediaStoreId,
    required this.contentUri,
    required this.mimeType,
    required this.dateAdded,
    this.dateTaken,
    this.width,
    this.height,
    this.sizeBytes,
  });

  final String mediaStoreId;
  final String contentUri;
  final String mimeType;
  final DateTime dateAdded;
  final DateTime? dateTaken;
  final int? width;
  final int? height;
  final int? sizeBytes;

  factory SlipMediaMetadata.fromPlatform(Map<Object?, Object?> value) {
    int? optionalInt(String key) => (value[key] as num?)?.toInt();
    DateTime? optionalDate(String key) {
      final millis = optionalInt(key);
      return millis == null || millis <= 0
          ? null
          : DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
    }

    return SlipMediaMetadata(
      mediaStoreId: value['mediaStoreId']! as String,
      contentUri: value['contentUri']! as String,
      mimeType: value['mimeType']! as String,
      dateAdded: DateTime.fromMillisecondsSinceEpoch(
        (value['dateAddedMillis']! as num).toInt(),
        isUtc: true,
      ),
      dateTaken: optionalDate('dateTakenMillis'),
      width: optionalInt('width'),
      height: optionalInt('height'),
      sizeBytes: optionalInt('sizeBytes'),
    );
  }

  bool get supportedMimeType => const {
    'image/jpeg',
    'image/png',
    'image/webp',
  }.contains(mimeType.toLowerCase());
}

final class SlipMediaEvent {
  const SlipMediaEvent({
    required this.id,
    required this.profileId,
    required this.mediaStoreId,
    required this.contentUri,
    required this.mimeType,
    required this.discoveredAt,
    required this.status,
    required this.ingestionSource,
    this.contentHash,
    this.mediaCreatedAt,
  });

  final String id;
  final String profileId;
  final String mediaStoreId;
  final String contentUri;
  final String? contentHash;
  final String mimeType;
  final DateTime? mediaCreatedAt;
  final DateTime discoveredAt;
  final String status;
  final String ingestionSource;
}

abstract interface class SlipMediaRepository {
  Future<bool> slipDetectionEnabled();
  Future<void> setSlipDetectionEnabled(bool enabled);
  Future<DateTime?> slipDetectionBaseline();
  Future<void> initializeSlipDetectionBaseline(DateTime baseline);
  Future<List<SlipMediaEvent>> stageNewSlipMedia(
    List<SlipMediaMetadata> media, {
    String ingestionSource,
  });
  Future<List<SlipMediaEvent>> slipMediaEvents();
}
