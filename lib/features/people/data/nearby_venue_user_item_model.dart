class NearbyVenueUserItem {
  final String checkinId;
  final String userId;
  final String? fullName;
  final String? userPhotoUrl;
  final String? featuredMediaUrl;
  final String? venueId;
  final String? venueName;
  final String? venueType;
  final String? venuePhoto;
  final double? nearbyVenueDistanceMeters;
  final bool isFeaturedVideo;

  const NearbyVenueUserItem({
    required this.checkinId,
    required this.userId,
    this.fullName,
    this.userPhotoUrl,
    this.featuredMediaUrl,
    this.venueId,
    this.venueName,
    this.venueType,
    this.venuePhoto,
    this.nearbyVenueDistanceMeters,
    this.isFeaturedVideo = false,
  });

  // Attendee kartı: kişinin o mekandaki temsili olan featured foto öncelikli;
  // yoksa profil fotoğrafı.
  String get displayPhoto =>
      (featuredMediaUrl != null && featuredMediaUrl!.trim().isNotEmpty)
      ? featuredMediaUrl!.trim()
      : (userPhotoUrl != null && userPhotoUrl!.trim().isNotEmpty)
      ? userPhotoUrl!.trim()
      : '';

  factory NearbyVenueUserItem.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> asMap(dynamic value) {
      if (value is Map) return Map<String, dynamic>.from(value);
      return const <String, dynamic>{};
    }

    String? readString(Map<String, dynamic> source, List<String> keys) {
      for (final key in keys) {
        final raw = source[key];
        if (raw == null) continue;
        final value = raw.toString().trim();
        if (value.isNotEmpty && value.toLowerCase() != 'null') {
          return value;
        }
      }
      return null;
    }

    final user = asMap(json['user']);
    final venue = asMap(json['venue']);
    final mediaRaw = json['media'];
    final firstMedia = mediaRaw is List && mediaRaw.isNotEmpty
        ? asMap(mediaRaw.first)
        : const <String, dynamic>{};
    final mediaType = readString(firstMedia, const [
      'mediaType',
      'media_type',
    ])?.toLowerCase();
    final distanceRaw =
        json['nearbyVenueDistanceMeters'] ??
        json['nearby_venue_distance_meters'];
    final distance = distanceRaw is num
        ? distanceRaw.toDouble()
        : double.tryParse(distanceRaw?.toString() ?? '');
    final isVideo = mediaType == 'video';
    final featuredMediaUrl = isVideo
        ? readString(firstMedia, const ['thumbnailUrl', 'thumbnail_url', 'url'])
        : readString(firstMedia, const [
            'url',
            'thumbnailUrl',
            'thumbnail_url',
          ]);

    return NearbyVenueUserItem(
      checkinId: readString(json, const ['id']) ?? '',
      userId:
          readString(json, const ['userId', 'user_id']) ??
          user['id']?.toString() ??
          '',
      fullName: readString(user, const ['fullName', 'full_name', 'name']),
      userPhotoUrl: readString(user, const ['photo', 'photoUrl', 'photo_url']),
      featuredMediaUrl: featuredMediaUrl,
      venueId:
          readString(json, const ['venueId', 'venue_id']) ??
          readString(venue, const ['id']),
      venueName: readString(venue, const ['name']),
      venueType: readString(venue, const ['type', 'venueType', 'venue_type']),
      venuePhoto: readString(venue, const ['photo', 'photoUrl', 'photo_url']),
      nearbyVenueDistanceMeters: distance,
      isFeaturedVideo: isVideo,
    );
  }
}
