import 'package:kmstry_frontend/core/media/media_reference.dart';

class VenueGalleryItem {
  final String id;
  final String url;
  final String? thumbnailUrl;
  final String mediaType; // 'photo' | 'video'
  final DateTime? createdAt;
  final MediaReference? mediaReference;
  final MediaReference? thumbnailReference;

  const VenueGalleryItem({
    required this.id,
    required this.url,
    this.thumbnailUrl,
    required this.mediaType,
    this.createdAt,
    this.mediaReference,
    this.thumbnailReference,
  });

  bool get isVideo => mediaType == 'video';

  factory VenueGalleryItem.fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString() ?? '';
    final mediaReference = MediaReference.fromJson(
      json,
      fallbackId: id.isEmpty ? '' : 'venue-gallery:$id',
      legacyUrlKeys: const ['url'],
    );
    final thumbnailReference = MediaReference.fromJson(
      json,
      fallbackId: id.isEmpty ? '' : 'venue-gallery:$id:thumbnail',
      legacyUrlKeys: const ['thumbnailUrl', 'thumbnail_url'],
      idKey: 'thumbnail_media_id',
      temporaryUrlKey: 'thumbnail_temporary_url',
      refreshPathKey: 'thumbnail_refresh_path',
      expiresAtKey: 'thumbnail_url_expires_at',
    );
    return VenueGalleryItem(
      id: id,
      url: mediaReference.url,
      thumbnailUrl: thumbnailReference.url.isEmpty
          ? null
          : thumbnailReference.url,
      mediaType:
          (json['mediaType'] ?? json['media_type'])?.toString() ?? 'photo',
      createdAt: DateTime.tryParse(
        (json['createdAt'] ?? json['created_at'])?.toString() ?? '',
      ),
      mediaReference: mediaReference.url.isNotEmpty || mediaReference.canRefresh
          ? mediaReference
          : null,
      thumbnailReference:
          thumbnailReference.url.isNotEmpty || thumbnailReference.canRefresh
          ? thumbnailReference
          : null,
    );
  }
}
