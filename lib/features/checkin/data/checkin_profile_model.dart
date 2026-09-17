import '../../../core/media/media_reference.dart';
import '../../media/media_text_overlay.dart';

enum MediaType { photo, video }

class CheckinProfileMedia {
  final String id;
  final String url;
  final MediaType mediaType;
  final bool isFeatured;
  final String? thumbnailUrl;
  final int? durationSeconds;
  final MediaReference? mediaReference;
  final MediaTextOverlay? textOverlay;

  CheckinProfileMedia({
    required this.id,
    required this.url,
    required this.mediaType,
    required this.isFeatured,
    this.thumbnailUrl,
    this.durationSeconds,
    this.mediaReference,
    this.textOverlay,
  });

  factory CheckinProfileMedia.fromJson(Map<String, dynamic> json) {
    final rawType = (json['media_type'] ?? json['mediaType'])?.toString();
    final normalizedType = rawType?.trim().toLowerCase();
    final rawDuration = json['duration_seconds'] ?? json['durationSeconds'];
    int? duration;
    if (rawDuration is num) {
      duration = rawDuration.toInt();
    } else if (rawDuration != null) {
      duration = int.tryParse(rawDuration.toString());
    }
    final id = json['id']?.toString() ?? '';
    final mediaReference = MediaReference.fromJson(
      json,
      fallbackId: id,
      legacyUrlKeys: const ['url'],
    );
    return CheckinProfileMedia(
      id: id,
      url: mediaReference.url,
      mediaReference: mediaReference,
      mediaType:
          (normalizedType == 'video' ||
              normalizedType?.startsWith('video/') == true)
          ? MediaType.video
          : MediaType.photo,
      isFeatured: json['is_featured'] == true || json['isFeatured'] == true,
      thumbnailUrl: (json['thumbnail_url'] ?? json['thumbnailUrl'])?.toString(),
      durationSeconds: duration,
      textOverlay: MediaTextOverlay.fromJson(
        json['text_overlay'] ?? json['textOverlay'],
      ),
    );
  }

  // 👇 BURAYA KOYUYORSUN
  CheckinProfileMedia copyWith({
    String? id,
    String? url,
    MediaType? mediaType,
    bool? isFeatured,
    String? thumbnailUrl,
    int? durationSeconds,
    MediaReference? mediaReference,
  }) {
    return CheckinProfileMedia(
      id: id ?? this.id,
      url: url ?? this.url,
      mediaType: mediaType ?? this.mediaType,
      isFeatured: isFeatured ?? this.isFeatured,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      mediaReference: mediaReference ?? this.mediaReference,
      textOverlay: textOverlay,
    );
  }
}

class CheckinProfile {
  final CheckinProfileUser user;
  final CheckinProfileCheckin checkin;
  final List<CheckinProfileMedia> media;
  final List<CheckinVisitedPlace> visitedPlaces;
  final bool isMatched;
  final String? chatId;
  final String?
  feedAction; // "interested" | "pass" | null (deprecated, use myActionAtThisVenue)
  final String? myActionAtThisVenue; // "interested" | "pass" | null
  final String? theirActionAtThisVenue; // "interested" | "pass" | null
  final DateTime? myActionCreatedAt;
  final DateTime? theirActionCreatedAt;

  CheckinProfile({
    required this.user,
    required this.checkin,
    required this.media,
    this.visitedPlaces = const [],
    required this.isMatched,
    this.chatId,
    this.feedAction,
    this.myActionAtThisVenue,
    this.theirActionAtThisVenue,
    this.myActionCreatedAt,
    this.theirActionCreatedAt,
  });

  factory CheckinProfile.fromJson(Map<String, dynamic> json) {
    // Parse relationship object (preferred)
    final relationship = json['relationship'] is Map
        ? Map<String, dynamic>.from(json['relationship'] as Map)
        : null;
    final myAction =
        (relationship?['myActionAtThisVenue'] ??
                relationship?['my_action_at_this_venue'])
            ?.toString();
    final theirAction =
        (relationship?['theirActionAtThisVenue'] ??
                relationship?['their_action_at_this_venue'])
            ?.toString();

    // Parse timestamps from relationship
    DateTime? parseTimestamp(dynamic value) {
      if (value == null) return null;
      if (value is String) {
        try {
          return DateTime.parse(value);
        } catch (e) {
          return null;
        }
      }
      return null;
    }

    final myActionCreatedAt =
        (relationship?['myActionCreatedAt'] ??
                relationship?['my_action_created_at']) !=
            null
        ? parseTimestamp(
            relationship!['myActionCreatedAt'] ??
                relationship['my_action_created_at'],
          )
        : null;
    final theirActionCreatedAt =
        (relationship?['theirActionCreatedAt'] ??
                relationship?['their_action_created_at']) !=
            null
        ? parseTimestamp(
            relationship!['theirActionCreatedAt'] ??
                relationship['their_action_created_at'],
          )
        : null;

    // Backward compatibility: fallback to flat fields if relationship doesn't exist
    return CheckinProfile(
      user: CheckinProfileUser.fromJson(
        json['user'] is Map
            ? Map<String, dynamic>.from(json['user'] as Map)
            : const {},
      ),
      checkin: CheckinProfileCheckin.fromJson(
        json['checkin'] is Map
            ? Map<String, dynamic>.from(json['checkin'] as Map)
            : const {},
      ),
      media: (json['media'] is List ? json['media'] as List : const [])
          .whereType<Map>()
          .map(
            (e) => CheckinProfileMedia.fromJson(Map<String, dynamic>.from(e)),
          )
          .toList(),
      visitedPlaces: CheckinVisitedPlace.listFromJson(
        json['visitedPlaces'] ?? json['visited_places'],
      ),
      isMatched: (json['isMatched'] ?? json['is_matched']) == true,
      chatId: (json['chatId'] ?? json['chat_id'])?.toString(),
      feedAction: (json['feedAction'] ?? json['feed_action'])?.toString(),
      myActionAtThisVenue:
          myAction ??
          (json['myActionAtThisVenue'] ??
                  json['feedAction'] ??
                  json['feed_action'])
              ?.toString(),
      theirActionAtThisVenue:
          theirAction ??
          (json['theirActionAtThisVenue'] ?? json['their_action_at_this_venue'])
              ?.toString(),
      myActionCreatedAt: myActionCreatedAt,
      theirActionCreatedAt: theirActionCreatedAt,
    );
  }
}

class CheckinProfileUser {
  final String id;
  final String? username;
  final String fullName;
  final String? photo;
  final MediaReference? photoReference;
  final DateTime birthdate;
  final String gender;
  final bool isVerified;
  final bool isPremium;
  final int friendCount;
  final int followedVenueCount;

  CheckinProfileUser({
    required this.id,
    this.username,
    required this.fullName,
    this.photo,
    this.photoReference,
    required this.birthdate,
    required this.gender,
    required this.isVerified,
    required this.isPremium,
    this.friendCount = 0,
    this.followedVenueCount = 0,
  });

  factory CheckinProfileUser.fromJson(Map<String, dynamic> json) {
    final birthdateRaw = json['birthdate']?.toString();
    final id = json['id']?.toString() ?? '';
    final photoReference = MediaReference.profilePhoto(json, userId: id);
    return CheckinProfileUser(
      id: id,
      username: (json['username'] ?? json['user_name'])?.toString(),
      fullName: (json['full_name'] ?? json['fullName'])?.toString() ?? 'Guest',
      photo: photoReference.url.isEmpty ? null : photoReference.url,
      photoReference: photoReference.url.isEmpty ? null : photoReference,
      birthdate:
          DateTime.tryParse(birthdateRaw ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      gender: json['gender']?.toString() ?? '',
      isVerified: json['is_verified'] == true || json['isVerified'] == true,
      isPremium: json['is_premium'] == true || json['isPremium'] == true,
      friendCount: (json['friendCount'] ?? json['friend_count']) is num
          ? ((json['friendCount'] ?? json['friend_count']) as num).toInt()
          : 0,
      followedVenueCount:
          (json['followedVenueCount'] ?? json['followed_venue_count']) is num
          ? ((json['followedVenueCount'] ?? json['followed_venue_count'])
                    as num)
                .toInt()
          : 0,
    );
  }
}

class PublicUserProfile {
  final String id;
  final String? username;
  final String fullName;
  final String? photo;
  final MediaReference? photoReference;
  final DateTime birthdate;
  final String gender;
  final bool isVerified;
  final bool isPremium;
  final String? bio;
  final int friendCount;
  final int followedVenueCount;
  final List<CheckinVisitedPlace> visitedPlaces;
  final PublicUserActiveCheckin? activeCheckin;

  const PublicUserProfile({
    required this.id,
    this.username,
    required this.fullName,
    this.photo,
    this.photoReference,
    required this.birthdate,
    required this.gender,
    required this.isVerified,
    required this.isPremium,
    this.bio,
    required this.friendCount,
    required this.followedVenueCount,
    this.visitedPlaces = const [],
    this.activeCheckin,
  });

  factory PublicUserProfile.fromJson(Map<String, dynamic> json) {
    final activeRaw = json['activeCheckin'] ?? json['active_checkin'];
    final birthdateRaw = json['birthdate']?.toString();
    String? readString(List<String> keys) {
      for (final key in keys) {
        final value = json[key]?.toString().trim();
        if (value != null &&
            value.isNotEmpty &&
            value.toLowerCase() != 'null') {
          return value;
        }
      }
      return null;
    }

    final id = json['id']?.toString() ?? '';
    final photoReference = MediaReference.profilePhoto(json, userId: id);
    return PublicUserProfile(
      id: id,
      username: readString(const ['username', 'user_name']),
      fullName:
          readString(const ['fullName', 'full_name']) ??
          readString(const ['username']) ??
          'User',
      photo: photoReference.url.isEmpty ? null : photoReference.url,
      photoReference: photoReference.url.isEmpty ? null : photoReference,
      birthdate:
          DateTime.tryParse(birthdateRaw ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      gender: json['gender']?.toString() ?? '',
      isVerified: json['isVerified'] == true || json['is_verified'] == true,
      isPremium: json['isPremium'] == true || json['is_premium'] == true,
      bio: readString(const ['bio', 'bio_text', 'about', 'aboutMe']),
      friendCount: (json['friendCount'] ?? json['friend_count']) is num
          ? ((json['friendCount'] ?? json['friend_count']) as num).toInt()
          : 0,
      followedVenueCount:
          (json['followedVenueCount'] ?? json['followed_venue_count']) is num
          ? ((json['followedVenueCount'] ?? json['followed_venue_count'])
                    as num)
                .toInt()
          : 0,
      visitedPlaces: CheckinVisitedPlace.listFromJson(
        json['visitedPlaces'] ?? json['visited_places'],
      ),
      activeCheckin: activeRaw is Map
          ? PublicUserActiveCheckin.fromJson(
              Map<String, dynamic>.from(activeRaw),
            )
          : null,
    );
  }
}

class CheckinVisitedPlace {
  final String id;
  final String? venueId;
  final String venueName;
  final String? venueType;
  final String? venuePhoto;
  final DateTime checkedInAt;
  final bool showOnProfile;

  const CheckinVisitedPlace({
    required this.id,
    this.venueId,
    required this.venueName,
    this.venueType,
    this.venuePhoto,
    required this.checkedInAt,
    this.showOnProfile = true,
  });

  static List<CheckinVisitedPlace> listFromJson(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((e) => CheckinVisitedPlace.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  factory CheckinVisitedPlace.fromJson(Map<String, dynamic> json) {
    final venueRaw = json['venue'];
    final venue = venueRaw is Map ? Map<String, dynamic>.from(venueRaw) : null;
    final checkedInRaw =
        (json['checkedInAt'] ??
                json['checked_in_at'] ??
                json['createdAt'] ??
                json['created_at'])
            ?.toString();
    final venueNameRaw =
        (json['venueName'] ?? json['venue_name'] ?? venue?['name'])
            ?.toString()
            .trim();
    return CheckinVisitedPlace(
      id: json['id']?.toString() ?? '',
      venueId: (json['venueId'] ?? json['venue_id'] ?? venue?['id'])
          ?.toString(),
      venueName: venueNameRaw != null && venueNameRaw.isNotEmpty
          ? venueNameRaw
          : 'Venue',
      venueType: (json['venueType'] ?? json['venue_type'] ?? venue?['type'])
          ?.toString(),
      venuePhoto: (json['venuePhoto'] ?? json['venue_photo'] ?? venue?['photo'])
          ?.toString(),
      checkedInAt:
          DateTime.tryParse(checkedInRaw ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      showOnProfile: json.containsKey('showOnProfile')
          ? json['showOnProfile'] == true
          : (json.containsKey('show_on_profile')
                ? json['show_on_profile'] == true
                : true),
    );
  }

  CheckinVisitedPlace copyWith({bool? showOnProfile}) {
    return CheckinVisitedPlace(
      id: id,
      venueId: venueId,
      venueName: venueName,
      venueType: venueType,
      venuePhoto: venuePhoto,
      checkedInAt: checkedInAt,
      showOnProfile: showOnProfile ?? this.showOnProfile,
    );
  }
}

class PublicUserActiveCheckin {
  final String id;
  final String? venueId;
  final String? avatarPhoto;
  final String? venueName;
  final String? venueType;
  final String? venuePhoto;
  final DateTime? expiresAt;

  const PublicUserActiveCheckin({
    required this.id,
    this.venueId,
    this.avatarPhoto,
    this.venueName,
    this.venueType,
    this.venuePhoto,
    this.expiresAt,
  });

  factory PublicUserActiveCheckin.fromJson(Map<String, dynamic> json) {
    final venueRaw = json['venue'];
    final venue = venueRaw is Map ? Map<String, dynamic>.from(venueRaw) : null;
    return PublicUserActiveCheckin(
      id: json['id']?.toString() ?? '',
      venueId: (json['venueId'] ?? json['venue_id'])?.toString(),
      avatarPhoto: (json['avatarPhoto'] ?? json['avatar_photo'])?.toString(),
      venueName: (json['venueName'] ?? json['venue_name'] ?? venue?['name'])
          ?.toString(),
      venueType: (json['venueType'] ?? json['venue_type'] ?? venue?['type'])
          ?.toString(),
      venuePhoto: (json['venuePhoto'] ?? json['venue_photo'] ?? venue?['photo'])
          ?.toString(),
      expiresAt: DateTime.tryParse(
        (json['expiresAt'] ?? json['expires_at'] ?? '').toString(),
      ),
    );
  }
}

class CheckinProfileCheckin {
  final String id;
  final String? venueId;
  final String? vibe;
  final String? avatarPhoto;
  final List<String> whatBringsToKmstry;
  final DateTime expiresAt;

  CheckinProfileCheckin({
    required this.id,
    required this.venueId,
    required this.vibe,
    this.avatarPhoto,
    this.whatBringsToKmstry = const [],
    required this.expiresAt,
  });

  factory CheckinProfileCheckin.fromJson(Map<String, dynamic> json) {
    final expiresAtRaw = (json['expires_at'] ?? json['expiresAt'])?.toString();
    List<String> parseWhatBrings(dynamic value) {
      if (value is List) {
        return value
            .map((e) => e?.toString().trim() ?? '')
            .where((e) => e.isNotEmpty)
            .toList();
      }
      if (value is String) {
        final v = value.trim();
        return v.isEmpty ? const [] : [v];
      }
      return const [];
    }

    final whatBrings = parseWhatBrings(
      json['whatBringsToKmstry'] ??
          json['what_brings_to_kmstry'] ??
          json['whatBrings'] ??
          json['what_brings'] ??
          json['whatBringsYou'] ??
          json['what_brings_you'],
    );
    return CheckinProfileCheckin(
      id: json['id']?.toString() ?? '',
      venueId: (json['venue_id'] ?? json['venueId'])?.toString(),
      vibe: json['vibe']?.toString(),
      avatarPhoto: (json['avatarPhoto'] ?? json['avatar_photo'])?.toString(),
      whatBringsToKmstry: whatBrings,
      expiresAt:
          DateTime.tryParse(expiresAtRaw ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class CheckinProfilePhoto {
  final String id;
  final String url;
  final bool isFeatured;

  CheckinProfilePhoto({
    required this.id,
    required this.url,
    required this.isFeatured,
  });

  factory CheckinProfilePhoto.fromJson(Map<String, dynamic> json) {
    return CheckinProfilePhoto(
      id: json['id']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      isFeatured: json['isFeatured'] == true || json['is_featured'] == true,
    );
  }
}
