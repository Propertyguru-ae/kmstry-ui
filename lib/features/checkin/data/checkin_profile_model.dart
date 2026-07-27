enum MediaType { photo, video }

class CheckinProfileMedia {
  final String id;
  final String url;
  final MediaType mediaType;
  final bool isFeatured;
  final String? thumbnailUrl;
  final int? durationSeconds;

  CheckinProfileMedia({
    required this.id,
    required this.url,
    required this.mediaType,
    required this.isFeatured,
    this.thumbnailUrl,
    this.durationSeconds,
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
    return CheckinProfileMedia(
      id: json['id']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      mediaType:
          (normalizedType == 'video' || normalizedType?.startsWith('video/') == true)
          ? MediaType.video
          : MediaType.photo,
      isFeatured: json['is_featured'] == true || json['isFeatured'] == true,
      thumbnailUrl:
          (json['thumbnail_url'] ?? json['thumbnailUrl'])?.toString(),
      durationSeconds: duration,
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
  }) {
    return CheckinProfileMedia(
      id: id ?? this.id,
      url: url ?? this.url,
      mediaType: mediaType ?? this.mediaType,
      isFeatured: isFeatured ?? this.isFeatured,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      durationSeconds: durationSeconds ?? this.durationSeconds,
    );
  }
}

class CheckinProfile {
  final CheckinProfileUser user;
  final CheckinProfileCheckin checkin;
  final List<CheckinProfileMedia> media;
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
    final myAction = (relationship?['myActionAtThisVenue'] ??
            relationship?['my_action_at_this_venue'])
        ?.toString();
    final theirAction = (relationship?['theirActionAtThisVenue'] ??
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
        json['user'] is Map ? Map<String, dynamic>.from(json['user'] as Map) : const {},
      ),
      checkin: CheckinProfileCheckin.fromJson(
        json['checkin'] is Map
            ? Map<String, dynamic>.from(json['checkin'] as Map)
            : const {},
      ),
      media: (json['media'] is List ? json['media'] as List : const [])
          .whereType<Map>()
          .map((e) => CheckinProfileMedia.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      isMatched: (json['isMatched'] ?? json['is_matched']) == true,
      chatId: (json['chatId'] ?? json['chat_id'])?.toString(),
      feedAction: (json['feedAction'] ?? json['feed_action'])?.toString(),
      myActionAtThisVenue:
          myAction ??
          (json['myActionAtThisVenue'] ?? json['feedAction'] ?? json['feed_action'])
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
  final DateTime birthdate;
  final String gender;
  final bool isVerified;
  final bool isPremium;

  CheckinProfileUser({
    required this.id,
    this.username,
    required this.fullName,
    this.photo,
    required this.birthdate,
    required this.gender,
    required this.isVerified,
    required this.isPremium,
  });

  factory CheckinProfileUser.fromJson(Map<String, dynamic> json) {
    final birthdateRaw = json['birthdate']?.toString();
    return CheckinProfileUser(
      id: json['id']?.toString() ?? '',
      username: (json['username'] ?? json['user_name'])?.toString(),
      fullName: (json['full_name'] ?? json['fullName'])?.toString() ?? 'Guest',
      photo: (json['photo'] ?? json['photo_url'])?.toString(),
      birthdate:
          DateTime.tryParse(birthdateRaw ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      gender: json['gender']?.toString() ?? '',
      isVerified: json['is_verified'] == true || json['isVerified'] == true,
      isPremium: json['is_premium'] == true || json['isPremium'] == true,
    );
  }
}

class CheckinProfileCheckin {
  final String id;
  final String? venueId;
  final String? vibe;
  final List<String> whatBringsToKmstry;
  final DateTime expiresAt;

  CheckinProfileCheckin({
    required this.id,
    required this.venueId,
    required this.vibe,
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
