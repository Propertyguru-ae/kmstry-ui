class CheckinProfile {
  final CheckinProfileUser user;
  final CheckinProfileCheckin checkin;
  final List<CheckinProfilePhoto> photos;
  final bool isMatched;
  final String? feedAction; // "interested" | "pass" | null (deprecated, use myActionAtThisVenue)
  final String? myActionAtThisVenue; // "interested" | "pass" | null
  final String? theirActionAtThisVenue; // "interested" | "pass" | null
  final DateTime? myActionCreatedAt;
  final DateTime? theirActionCreatedAt;

  CheckinProfile({
    required this.user,
    required this.checkin,
    required this.photos,
    required this.isMatched,
    this.feedAction,
    this.myActionAtThisVenue,
    this.theirActionAtThisVenue,
    this.myActionCreatedAt,
    this.theirActionCreatedAt,
  });

  factory CheckinProfile.fromJson(Map<String, dynamic> json) {
    // Parse relationship object (preferred)
    final relationship = json['relationship'] as Map<String, dynamic>?;
    final myAction = relationship?['myActionAtThisVenue'] as String?;
    final theirAction = relationship?['theirActionAtThisVenue'] as String?;
    
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
      user: CheckinProfileUser.fromJson(json['user']),
      checkin: CheckinProfileCheckin.fromJson(json['checkin']),
      photos: (json['photos'] as List)
          .map((e) => CheckinProfilePhoto.fromJson(e))
          .toList(),
      isMatched: json['is_matched'] as bool? ?? false,
      feedAction: json['feed_action'] as String?,
      myActionAtThisVenue: myAction ?? json['feed_action'] as String?,
      theirActionAtThisVenue: theirAction ?? json['their_action_at_this_venue'] as String?,
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
    return CheckinProfileUser(
      id: json['id'],
      fullName: json['full_name'],
      birthdate: DateTime.parse(json['birthdate']),
      gender: json['gender'],
      isVerified: json['is_verified'],
      isPremium: json['is_premium'],
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
    return CheckinProfileCheckin(
      id: json['id'],
      vibe: json['vibe'],
      expiresAt: DateTime.parse(json['expires_at']),
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
      id: json['id'],
      url: json['url'],
      isFeatured: json['isFeatured'],
    );
  }
}
