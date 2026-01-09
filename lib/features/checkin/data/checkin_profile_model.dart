class CheckinProfile {
  final CheckinProfileUser user;
  final CheckinProfileCheckin checkin;
  final List<CheckinProfilePhoto> photos;

  CheckinProfile({
    required this.user,
    required this.checkin,
    required this.photos,
  });

  factory CheckinProfile.fromJson(Map<String, dynamic> json) {
    return CheckinProfile(
      user: CheckinProfileUser.fromJson(json['user']),
      checkin: CheckinProfileCheckin.fromJson(json['checkin']),
      photos: (json['photos'] as List)
          .map((e) => CheckinProfilePhoto.fromJson(e))
          .toList(),
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
