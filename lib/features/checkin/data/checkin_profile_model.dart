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
      mediaType: rawType == 'video' ? MediaType.video : MediaType.photo,
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
    final myAction = relationship?['myActionAtThisVenue']?.toString();
    final theirAction = relationship?['theirActionAtThisVenue']?.toString();

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

    final myActionCreatedAt = relationship?['myActionCreatedAt'] != null
        ? parseTimestamp(relationship!['myActionCreatedAt'])
        : null;
    final theirActionCreatedAt = relationship?['theirActionCreatedAt'] != null
        ? parseTimestamp(relationship!['theirActionCreatedAt'])
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
      isMatched: json['is_matched'] as bool? ?? false,
      chatId: json['chat_id']?.toString(),
      feedAction: json['feed_action']?.toString(),
      myActionAtThisVenue: myAction ?? json['feed_action']?.toString(),
      theirActionAtThisVenue:
          theirAction ?? json['their_action_at_this_venue']?.toString(),
      myActionCreatedAt: myActionCreatedAt,
      theirActionCreatedAt: theirActionCreatedAt,
    );
  }
}

class CheckinProfileUser {
  final String id;
  final String fullName;
  final DateTime birthdate;
  final String gender;
  final bool isVerified;
  final bool isPremium;

  CheckinProfileUser({
    required this.id,
    required this.fullName,
    required this.birthdate,
    required this.gender,
    required this.isVerified,
    required this.isPremium,
  });

  factory CheckinProfileUser.fromJson(Map<String, dynamic> json) {
    final birthdateRaw = json['birthdate']?.toString();
    return CheckinProfileUser(
      id: json['id']?.toString() ?? '',
      fullName: (json['full_name'] ?? json['fullName'])?.toString() ?? 'Guest',
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
  final String? vibe;
  final DateTime expiresAt;

  CheckinProfileCheckin({
    required this.id,
    required this.vibe,
    required this.expiresAt,
  });

  factory CheckinProfileCheckin.fromJson(Map<String, dynamic> json) {
    final expiresAtRaw = (json['expires_at'] ?? json['expiresAt'])?.toString();
    return CheckinProfileCheckin(
      id: json['id']?.toString() ?? '',
      vibe: json['vibe']?.toString(),
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
