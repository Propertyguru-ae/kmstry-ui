class VenueCheckin {
  final String id;
  final String userId;
  final String? fullName;
  final String userPhoto;
  final String? featuredPhoto;
  final bool isFeaturedVideo;

  VenueCheckin({
    required this.id,
    required this.userId,
    this.fullName,
    required this.userPhoto,
    this.featuredPhoto,
    this.isFeaturedVideo = false,
  });

  factory VenueCheckin.fromJson(Map<String, dynamic> json) {
    final user = json['user'] ?? {};
    final photos = json['photos'] as List? ?? [];
    final media = json['media'] as List? ?? [];

    String? featuredPhoto;
    bool isFeaturedVideo = false;

    if (media.isNotEmpty) {
      final normalizedMedia = media.whereType<Map>().map((e) {
        return Map<String, dynamic>.from(e);
      }).toList();

      if (normalizedMedia.isNotEmpty) {
        final featured = normalizedMedia.firstWhere(
          (m) => m['is_featured'] == true || m['isFeatured'] == true,
          orElse: () => normalizedMedia.first,
        );
        final mediaType = (featured['media_type'] ?? featured['mediaType'])
            ?.toString()
            .toLowerCase();
        isFeaturedVideo = mediaType == 'video';

        if (isFeaturedVideo) {
          final thumbnail =
              (featured['thumbnail_url'] ?? featured['thumbnailUrl']) as String?;
          if (thumbnail != null && thumbnail.isNotEmpty) {
            featuredPhoto = thumbnail;
          }
        } else {
          final url = featured['url'] as String?;
          if (url != null && url.isNotEmpty) {
            featuredPhoto = url;
          }
        }
      }
    }

    // Backward compatibility for old responses containing only `photos`.
    if (featuredPhoto == null && photos.isNotEmpty) {
      final normalizedPhotos = photos.whereType<Map>().map((e) {
        return Map<String, dynamic>.from(e);
      }).toList();

      if (normalizedPhotos.isNotEmpty) {
        final featured = normalizedPhotos.firstWhere(
          (p) => p['is_featured'] == true || p['isFeatured'] == true,
          orElse: () => normalizedPhotos.first,
        );
        final url = featured['url'] as String?;
        if (url != null && url.isNotEmpty) {
          featuredPhoto = url;
        }
      }
    }

    return VenueCheckin(
      id: json['id'] as String,
      userId: user['id'] as String,
      fullName: user['full_name'], // nullable OK
      userPhoto:
          user['photo'] ?? 'https://via.placeholder.com/300x300.png?text=User',
      featuredPhoto: featuredPhoto,
      isFeaturedVideo: isFeaturedVideo,
    );
  }
}

extension VenueCheckinX on VenueCheckin {
  /// Grid + Hero için tek foto kaynağı:
  /// featured varsa onu, yoksa userPhoto
  String get displayPhoto => featuredPhoto ?? userPhoto;
}
