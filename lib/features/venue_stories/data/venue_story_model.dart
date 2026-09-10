import '../../../core/media/media_reference.dart';

class VenueStoryItem {
  final String id;
  final String mediaUrl;
  final String mediaType;
  final String? thumbnailUrl;
  final int? durationSecs;
  final DateTime expiresAt;
  final DateTime createdAt;
  final bool viewedByMe;
  final int viewCount;
  final MediaReference? mediaReference;

  const VenueStoryItem({
    required this.id,
    required this.mediaUrl,
    required this.mediaType,
    this.thumbnailUrl,
    this.durationSecs,
    required this.expiresAt,
    required this.createdAt,
    this.viewedByMe = false,
    this.viewCount = 0,
    this.mediaReference,
  });

  factory VenueStoryItem.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String;
    final mediaReference = MediaReference.fromJson(
      json,
      fallbackId: id,
      legacyUrlKeys: const ['media_url', 'mediaUrl'],
    );
    return VenueStoryItem(
      id: id,
      mediaUrl: mediaReference.url,
      mediaReference: mediaReference,
      mediaType: json['media_type'] as String,
      thumbnailUrl: json['thumbnail_url'] as String?,
      durationSecs: json['duration_secs'] as int?,
      expiresAt: DateTime.parse(json['expires_at'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
      viewedByMe: (json['viewed_by_me'] as bool?) ?? false,
      viewCount: (json['view_count'] as num?)?.toInt() ?? 0,
    );
  }

  VenueStoryItem copyWith({bool? viewedByMe}) => VenueStoryItem(
    id: id,
    mediaUrl: mediaUrl,
    mediaType: mediaType,
    thumbnailUrl: thumbnailUrl,
    durationSecs: durationSecs,
    expiresAt: expiresAt,
    createdAt: createdAt,
    viewedByMe: viewedByMe ?? this.viewedByMe,
    viewCount: viewCount,
    mediaReference: mediaReference,
  );

  bool get isVideo => mediaType == 'video';
}
